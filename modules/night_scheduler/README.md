# night_scheduler

Scales the EKS managed node group to 0 overnight and back to 1 in the morning. Design and the measurements behind it: ADR 0011 (workspace `docs/adr/0011-scheduled-night-shutdown-of-the-node.md`).

Saves the node, its public IPv4 address and its root volume, about **0.39 USD a day** for the 23:00 to 06:45 window. The EKS control plane and the ALB are billed for existing and keep running, so roughly 91 USD a month is untouched. **The site returns 503 for the whole window.**

## What it creates

| Resource | Notes |
| --- | --- |
| `aws_ssm_parameter.enabled` | The off switch, created with `"false"`. `lifecycle.ignore_changes` keeps Terraform out of it; flip it with the AWS CLI. |
| `aws_lambda_function.night_scheduler` | `lambda/handler.py`, Python 3.13 on arm64, 128 MB, zipped by `archive_file` at plan time. No reserved concurrency: the account's whole quota is 10 and AWS rejects a reservation that leaves fewer than 10 unreserved. |
| `aws_iam_role.lambda` + policy | `eks:DescribeNodegroup` and `eks:UpdateNodegroupConfig` on this node group only, `ssm:GetParameter` on the flag, its own log group, and the two alarm-action calls when `node_asg_name` is set. |
| `aws_cloudwatch_log_group.lambda` | Created here so retention is set from the first run. |
| `aws_scheduler_schedule.reconcile` | `cron(0/15 * * * ? *)` in `timezone`, flexible window `OFF`, invoking the Lambda through its own role. |
| `aws_sns_topic.alerts` + email subscription | The subscription must be confirmed once from the inbox, or no mail arrives. |
| `aws_cloudwatch_metric_alarm.lambda_errors` | Two 15-minute periods with an error. The loop silently dying is what leaves the site down. |
| `aws_cloudwatch_metric_alarm.node_down` | `AWS/AutoScaling` `GroupInServiceInstances < 1` on the node group's ASG, two 5-minute periods, created when `node_asg_name` is set. Catches the loop succeeding and the node still not coming back. The Lambda disables its actions inside the window and enables them at the 06:45 tick, because an empty node group is correct at night. It has no `ok_actions`: the loop re-enables actions while the alarm is still in ALARM, so a recovery action would mail every morning once the node joins. ALB `HealthyHostCount` would be closer to the user's experience, but it is published only per target group, and the target group belongs to the Load Balancer Controller: the 443 listener's default action is a fixed response and the routing lives in a listener rule, so Terraform cannot name it. |

## Why a reconcile loop

Every run reads the wanted size from the clock and the real size from the EKS API, and calls the API only when they differ. A failed run is repaired by the next one, at most 15 minutes later, so a single failed scale-up cannot leave the site down all morning. Two edge-triggered schedules, one to scale down and one to scale up, have no such recovery; that is why they were rejected in ADR 0011.

For the same reason the schedule has no dead-letter queue: a lost invocation needs no replay.

The loop leaves the node group alone unless its status is `ACTIVE`, so it never calls the API while an earlier update is still running or while the group is `DEGRADED`.

## Requirements on the caller

- The node group must allow `min_size = 0`, and Terraform must ignore `desired_size`, or the next apply fights the Lambda. The `compute` module takes `node_min_size` for this.
- `startup_time` and `shutdown_time` must land on a multiple of `reconcile_interval_minutes`, or the loop never runs at that exact minute. The defaults, 06:45 and 23:00 with a 15-minute interval, do.
- `startup_time` is deliberately earlier than the hour the site must answer. Measured on 2026-10-26, a replacement node is launched, joined, running the pod and `healthy` on the ALB 82 seconds after the loop decides to scale up (ADR 0011, Consequences). The 15 minutes the defaults leave are margin for a slow join or a failed image pull, not the expected cost.

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

See runbooks/cluster-operations.md (workspace `docs/runbooks/cluster-operations.md`) for what to check after a cycle.

## Notes

- `archive_file` builds the zip under `modules/night_scheduler/build/` (git-ignored) while Terraform plans. `terraform apply <planfile>` does not re-run data sources, so the CI apply job needs that file from the plan job; `terraform-ci.yml` carries it with the plan artifact.
- A deploy pushed inside the window reaches ECR and `portfolio-gitops`, but Argo CD is down, so the smoke test fails and CI reverts the tag. Turn the flag off first.
