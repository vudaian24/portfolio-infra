# Scheduled night shutdown of the single EKS node (ADR 0011). A Lambda holds the
# node group at the size the clock calls for; EventBridge Scheduler runs it every
# 15 minutes so a failed run is repaired by the next one.

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

locals {
  function_name   = "${var.name_prefix}-night-scheduler"
  site_alarm_name = var.node_asg_name == null ? "" : "${var.name_prefix}-night-scheduler-node-down"
  node_group_arn = join("", [
    "arn:aws:eks:", data.aws_region.current.region, ":",
    data.aws_caller_identity.current.account_id, ":nodegroup/",
    var.cluster_name, "/", var.node_group_name, "/*",
  ])
}

# The off switch. Set it to "false" with the AWS CLI to keep the node running,
# for a late deploy or a debugging session; no apply needed either way.
resource "aws_ssm_parameter" "enabled" {
  name        = var.flag_parameter_name
  description = "Night shutdown of ${var.node_group_name}: \"true\" lets the reconcile loop scale the node group, anything else disables it (ADR 0011)."
  type        = "String"
  value       = "false"

  # The value is operational state, flipped with the CLI, not through Terraform.
  lifecycle {
    ignore_changes = [value]
  }
}

# ---------------------------------------------------------------- the Lambda

data "archive_file" "handler" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/${local.function_name}.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "lambda" {
  statement {
    sid       = "ReadAndScaleTheNodeGroup"
    actions   = ["eks:DescribeNodegroup", "eks:UpdateNodegroupConfig"]
    resources = [local.node_group_arn]
  }

  statement {
    sid       = "ReadTheFlag"
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.enabled.arn]
  }

  statement {
    sid       = "WriteItsOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }

  dynamic "statement" {
    for_each = local.site_alarm_name == "" ? [] : [local.site_alarm_name]

    content {
      sid     = "FollowTheWindowWithTheSiteAlarm"
      actions = ["cloudwatch:EnableAlarmActions", "cloudwatch:DisableAlarmActions"]
      resources = [join("", [
        "arn:aws:cloudwatch:", data.aws_region.current.region, ":",
        data.aws_caller_identity.current.account_id, ":alarm:", statement.value,
      ])]
    }
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.function_name}-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda.json
}

# Created here so the retention is set from the start and the role can be
# scoped to this one group.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "night_scheduler" {
  function_name = local.function_name
  description   = "Holds ${var.node_group_name} at 0 nodes between ${var.shutdown_time} and ${var.startup_time} ${var.timezone} (ADR 0011)."
  role          = aws_iam_role.lambda.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  architectures = ["arm64"]
  timeout       = 30
  memory_size   = 128

  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256

  # No reservation. This account's whole Lambda concurrency quota is 10, and AWS
  # rejects any reservation that leaves UnreservedConcurrentExecution below 10.
  # Nothing is lost: the timeout is 30 s against a 15-minute schedule, so runs
  # cannot overlap, and a duplicate delivery finds the node group UPDATING and
  # skips it.

  environment {
    variables = {
      CLUSTER_NAME    = var.cluster_name
      NODE_GROUP_NAME = var.node_group_name
      TIMEZONE        = var.timezone
      SHUTDOWN_TIME   = var.shutdown_time
      STARTUP_TIME    = var.startup_time
      FLAG_PARAMETER  = aws_ssm_parameter.enabled.name
      SITE_ALARM_NAME = local.site_alarm_name
    }
  }

  tracing_config {
    mode = "PassThrough"
  }

  depends_on = [aws_cloudwatch_log_group.lambda, aws_iam_role_policy.lambda]
}

# ------------------------------------------------------------- the schedule

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    # Confused deputy: only this account's schedules may assume the role.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${local.function_name}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "scheduler" {
  statement {
    sid       = "InvokeTheReconcileLoop"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.night_scheduler.arn]
  }
}

resource "aws_iam_role_policy" "scheduler" {
  name   = "${local.function_name}-scheduler-policy"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler.json
}

resource "aws_scheduler_schedule" "reconcile" {
  name        = local.function_name
  description = "Reconciles ${var.node_group_name} every ${var.reconcile_interval_minutes} minutes (ADR 0011)."
  group_name  = "default"

  # OFF: the run must land on the quarter hour, because shutdown_time and
  # startup_time are only reached if a run happens at exactly that minute.
  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "cron(0/${var.reconcile_interval_minutes} * * * ? *)"
  schedule_expression_timezone = var.timezone

  target {
    arn      = aws_lambda_function.night_scheduler.arn
    role_arn = aws_iam_role.scheduler.arn

    # No dead-letter queue: a lost invocation is repaired by the next run,
    # which is the reason for the reconcile loop.
    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}

# ---------------------------------------------------------------- alerting

resource "aws_sns_topic" "alerts" {
  name = "${local.function_name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# The reconcile loop silently stopping is the failure that leaves the site down,
# so alarm on the Lambda failing rather than on the node group being empty.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.function_name}-errors"
  alarm_description   = "The night shutdown reconcile loop is failing; the node group may stay at 0 (ADR 0011)."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.night_scheduler.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# The loop can succeed and still leave the site down, so alarm on the effect as
# well as on the Lambda. ALB HealthyHostCount would be the closer signal, but it
# is only published per target group, and the target group belongs to the AWS
# Load Balancer Controller: the 443 listener's default action is a fixed
# response and the routing lives in a listener rule, so Terraform cannot name it.
# The node group's Auto Scaling group is the part this module actually moves, and
# EKS publishes AWS/AutoScaling group metrics for it.
#
# Two 5-minute periods, so the ~82 s morning scale-up does not trip it. The loop
# disables these actions inside the window, where an empty node group is correct,
# and enables them again at the 06:45 tick.
resource "aws_cloudwatch_metric_alarm" "node_down" {
  count = var.node_asg_name == null ? 0 : 1

  alarm_name          = local.site_alarm_name
  alarm_description   = "The node group has no instance in service outside the night window; the site is down (ADR 0011)."
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    AutoScalingGroupName = var.node_asg_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
