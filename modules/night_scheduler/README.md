# night_scheduler

Scales the EKS managed node group to 0 overnight and back to 1 in the morning. Design and the measurements behind it: [ADR 0011](../../../docs/adr/0011-scheduled-night-shutdown-of-the-node.md).

Saves the node, its public IPv4 address and its root volume, about **0.40 USD a day** for a 23:00 to 07:00 window. The EKS control plane and the ALB are billed for existing and keep running, so roughly 91 USD a month is untouched. **The site returns 503 for the whole window.**

## What it creates

| Resource | Notes |
| --- | --- |
| `aws_ssm_parameter.enabled` | The off switch, created with `"false"`. `lifecycle.ignore_changes` keeps Terraform out of it; flip it with the AWS CLI. |
| `aws_lambda_function.night_scheduler` | `lambda/handler.py`, Python 3.13 on arm64, 128 MB, zipped by `archive_file` at plan time. `reserved_concurrent_executions = 1`. |
| `aws_iam_role.lambda` + policy | `eks:DescribeNodegroup` and `eks:UpdateNodegroupConfig` on this node group only, `ssm:GetParameter` on the flag, its own log group, and the two alarm-action calls when `site_alarm_name` is set. |
| `aws_cloudwatch_log_group.lambda` | Created here so retention is set from the first run. |
| `aws_scheduler_schedule.reconcile` | `cron(0/15 * * * ? *)` in `timezone`, flexible window `OFF`, invoking the Lambda through its own role. |
| `aws_sns_topic.alerts` + email subscription | The subscription must be confirmed once from the inbox, or no mail arrives. |
| `aws_cloudwatch_metric_alarm.lambda_errors` | Two 15-minute periods with an error. The loop silently dying is what leaves the site down. |

## Why a reconcile loop

Every run reads the wanted size from the clock and the real size from the EKS API, and calls the API only when they differ. A failed run is repaired by the next one, at most 15 minutes later, so a single failed scale-up cannot leave the site down all morning. Two edge-triggered schedules, one to scale down and one to scale up, have no such recovery; that is why they were rejected in ADR 0011.

For the same reason the schedule has no dead-letter queue: a lost invocation needs no replay.

The loop leaves the node group alone unless its status is `ACTIVE`, so it never calls the API while an earlier update is still running or while the group is `DEGRADED`.

## Requirements on the caller

- The node group must allow `min_size = 0`, and Terraform must ignore `desired_size`, or the next apply fights the Lambda. The `compute` module takes `node_min_size` for this.
- `startup_time` and `shutdown_time` must land on a multiple of `reconcile_interval_minutes`, or the loop never runs at that exact minute. The defaults, 06:45 and 23:00 with a 15-minute interval, do.
- `startup_time` is deliberately earlier than the hour the site must answer: a new node needs 5 to 7 minutes before the pods are ready and the ALB has a healthy target.

## Applying it the first time

This module creates IAM roles and policies, and the CI plan job stops on any plan that changes `aws_iam_*` (README, *First apply*). **The apply that turns `night_shutdown_enabled` on therefore runs from a laptop as the admin**, not through CI. Later applies that do not touch IAM go through CI as usual.

## Operating it

The module ships with the flag at `"false"`, so nothing happens until it is turned on:

```bash
aws ssm put-parameter --name /portfolio/prod/night-shutdown-enabled \
  --type String --overwrite --value true
```

Set it back to `false` to keep the node running through a night, for a late deploy or a debugging session. No apply is involved either way, and the next run of the loop reads the new value.

Run it by hand to test a cycle during office hours:

```bash
aws lambda invoke --function-name portfolio-prod-night-scheduler /dev/stdout
```

See [runbooks/cluster-operations.md](../../../docs/runbooks/cluster-operations.md) for what to check after a cycle.

## Notes

- `archive_file` builds the zip under `modules/night_scheduler/build/` (git-ignored) while Terraform plans. `terraform apply <planfile>` does not re-run data sources, so the CI apply job needs that file from the plan job; `terraform-ci.yml` carries it with the plan artifact.
- A deploy pushed inside the window reaches ECR and `portfolio-gitops`, but Argo CD is down, so the smoke test fails and CI reverts the tag. Turn the flag off first.
