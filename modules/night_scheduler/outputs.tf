output "alerts_topic_arn" {
  description = "SNS topic of the alarm. The email subscription must be confirmed from the inbox once."
  value       = aws_sns_topic.alerts.arn
}

output "flag_parameter_name" {
  description = "SSM parameter that switches the loop on. Set it to \"true\" to enable the night shutdown."
  value       = aws_ssm_parameter.enabled.name
}

output "function_name" {
  description = "Name of the reconcile Lambda, for a manual test run with `aws lambda invoke`."
  value       = aws_lambda_function.night_scheduler.function_name
}

output "schedule_name" {
  description = "Name of the EventBridge schedule."
  value       = aws_scheduler_schedule.reconcile.name
}
