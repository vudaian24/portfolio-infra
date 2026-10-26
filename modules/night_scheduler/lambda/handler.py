"""Hold the EKS node group at the size the time of day calls for (ADR 0011).

EventBridge Scheduler runs this every 15 minutes. It is a reconcile loop, not a
pair of edge triggers: each run reads the wanted size from the clock and the
real size from the EKS API, and calls the API only when they differ. A run that
fails is therefore repaired by the next one, which is what keeps the site from
staying down after a single failed scale-up.

Environment:
  CLUSTER_NAME, NODE_GROUP_NAME  the node group to drive
  TIMEZONE                       IANA name, e.g. Asia/Ho_Chi_Minh
  SHUTDOWN_TIME, STARTUP_TIME    local HH:MM; the window may wrap past midnight
  FLAG_PARAMETER                 SSM parameter; anything but "true" disables the loop
  SITE_ALARM_NAME                optional alarm whose actions follow the window
"""

import datetime
import os
import zoneinfo

import boto3

eks = boto3.client("eks")
ssm = boto3.client("ssm")
cloudwatch = boto3.client("cloudwatch")

CLUSTER_NAME = os.environ["CLUSTER_NAME"]
NODE_GROUP_NAME = os.environ["NODE_GROUP_NAME"]
TIMEZONE = zoneinfo.ZoneInfo(os.environ["TIMEZONE"])
SHUTDOWN_TIME = os.environ["SHUTDOWN_TIME"]
STARTUP_TIME = os.environ["STARTUP_TIME"]
FLAG_PARAMETER = os.environ["FLAG_PARAMETER"]
SITE_ALARM_NAME = os.environ.get("SITE_ALARM_NAME", "")

# The node group never holds more than one node (ADR 0003). minSize stays 0 so
# that Terraform, which also declares 0, never sees drift on this field.
MAX_SIZE = 1
MIN_SIZE = 0


def _minutes(hhmm):
    hour, minute = hhmm.split(":")
    return int(hour) * 60 + int(minute)


def wanted_size(now):
    """0 inside the night window, 1 outside it."""
    current = now.hour * 60 + now.minute
    shutdown = _minutes(SHUTDOWN_TIME)
    startup = _minutes(STARTUP_TIME)
    if shutdown > startup:  # the usual case: the window wraps past midnight
        in_window = current >= shutdown or current < startup
    else:
        in_window = shutdown <= current < startup
    return 0 if in_window else 1


def enabled():
    value = ssm.get_parameter(Name=FLAG_PARAMETER)["Parameter"]["Value"]
    return value.strip().lower() == "true"


def handler(event, context):  # noqa: ARG001 - the scheduler sends no payload
    if not enabled():
        print(f"{FLAG_PARAMETER} is not true: leaving the node group alone")
        return {"skipped": "flag-off"}

    now = datetime.datetime.now(TIMEZONE)
    wanted = wanted_size(now)

    node_group = eks.describe_nodegroup(
        clusterName=CLUSTER_NAME, nodegroupName=NODE_GROUP_NAME
    )["nodegroup"]
    status = node_group["status"]
    current = node_group["scalingConfig"]["desiredSize"]

    # UPDATING means an earlier call is still running, DEGRADED needs a human.
    # Either way a second call would fail, and the next run picks it up again.
    if status != "ACTIVE":
        print(f"node group is {status}, not ACTIVE: skipping this run")
        return {"skipped": status, "wanted": wanted, "current": current}

    if current != wanted:
        eks.update_nodegroup_config(
            clusterName=CLUSTER_NAME,
            nodegroupName=NODE_GROUP_NAME,
            scalingConfig={
                "minSize": MIN_SIZE,
                "desiredSize": wanted,
                "maxSize": MAX_SIZE,
            },
        )
        print(f"{now:%Y-%m-%d %H:%M %Z}: desired {current} -> {wanted}")
    else:
        print(f"{now:%Y-%m-%d %H:%M %Z}: desired already {wanted}")

    # The site is meant to be down inside the window, so the 5xx alarm would
    # fire every night. Let it watch only the hours the site should answer.
    if SITE_ALARM_NAME:
        if wanted:
            cloudwatch.enable_alarm_actions(AlarmNames=[SITE_ALARM_NAME])
        else:
            cloudwatch.disable_alarm_actions(AlarmNames=[SITE_ALARM_NAME])

    return {"wanted": wanted, "current": current}
