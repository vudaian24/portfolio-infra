"""Hold the EKS node group at the size the time of day calls for (ADR 0011).

EventBridge Scheduler runs this every 15 minutes. It is a reconcile loop, not a
pair of edge triggers: each run reads the wanted size from the clock and the
node group's desired size from the EKS API, and calls the API only when they
differ. A run that fails is therefore repaired by the next one, which is what
keeps the site from staying down after a single failed scale-up call.

It compares the desired size, not the running nodes: a desired size of 1 with no
node in service is not something the loop can see or fix. The node-down alarm
reports that case, and the loop re-arms it once each morning (see follow_window).

Environment:
  CLUSTER_NAME, NODE_GROUP_NAME  the node group to drive
  TIMEZONE                       IANA name, e.g. Asia/Ho_Chi_Minh
  SHUTDOWN_TIME, STARTUP_TIME    local HH:MM; the window may wrap past midnight
  OFF_DAYS                       optional comma-separated local days, e.g. "Sun",
                                 on which the node group stays at 0 all day
  FLAG_PARAMETER                 SSM parameter; anything but "true" disables the loop
  SITE_ALARM_NAME                optional alarm whose actions follow the window
  RECONCILE_INTERVAL_MINUTES     minutes between runs (default 15); places the
                                 morning re-arm of SITE_ALARM_NAME
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
OFF_DAYS = {d.strip() for d in os.environ.get("OFF_DAYS", "").split(",") if d.strip()}
FLAG_PARAMETER = os.environ["FLAG_PARAMETER"]
SITE_ALARM_NAME = os.environ.get("SITE_ALARM_NAME", "")
RECONCILE_INTERVAL = int(os.environ.get("RECONCILE_INTERVAL_MINUTES", "15"))

# The node group never holds more than one node (ADR 0003). minSize stays 0 so
# that Terraform, which also declares 0, never sees drift on this field.
MAX_SIZE = 1
MIN_SIZE = 0

# Indexed by datetime.weekday(). Not strftime("%a"), which follows the locale.
DAY_NAMES = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")


def _minutes(hhmm):
    hour, minute = hhmm.split(":")
    return int(hour) * 60 + int(minute)


def wanted_size(now):
    """0 on an off day or inside the night window, 1 otherwise."""
    if DAY_NAMES[now.weekday()] in OFF_DAYS:
        return 0
    current = now.hour * 60 + now.minute
    shutdown = _minutes(SHUTDOWN_TIME)
    startup = _minutes(STARTUP_TIME)
    if shutdown > startup:  # the usual case: the window wraps past midnight
        in_window = current >= shutdown or current < startup
    else:
        in_window = shutdown <= current < startup
    return 0 if in_window else 1


def rearm_due(now):
    """True for the run one interval after startup_time (08:15 by default).

    The half-open range, not an exact minute, still matches a run that the
    scheduler retried a little late, and matches no other run of the day.
    """
    rearm = _minutes(STARTUP_TIME) + RECONCILE_INTERVAL
    current = now.hour * 60 + now.minute
    return rearm <= current < rearm + RECONCILE_INTERVAL


def follow_window(now, wanted):
    """Mute the node-down alarm inside the window, and re-arm it each morning.

    The site is meant to be down inside the window, so the alarm would fire every
    night; its actions are off whenever the wanted size is 0.

    The alarm goes to ALARM every night soon after 22:00 and stays there until
    the node is back. CloudWatch runs actions only on a state change, so if the
    node never comes back, enabling the actions at startup_time sends nothing.
    One interval later the node has had time to join (about 82 s, ADR 0011), and
    the alarm should be OK again. Setting it to OK then is a no-op on a normal
    morning; on a morning the node is missing, the next evaluation moves it back
    to ALARM with actions on, and that sends the mail. Once a day, so an outage
    that lasts all day mails once, not every 15 minutes.
    """
    if not SITE_ALARM_NAME:
        return
    if not wanted:
        cloudwatch.disable_alarm_actions(AlarmNames=[SITE_ALARM_NAME])
        return
    cloudwatch.enable_alarm_actions(AlarmNames=[SITE_ALARM_NAME])
    if rearm_due(now):
        cloudwatch.set_alarm_state(
            AlarmName=SITE_ALARM_NAME,
            StateValue="OK",
            StateReason=(
                "Re-armed by the night scheduler one interval after startup, "
                "so a node that did not come back raises a new alarm."
            ),
        )
        print(f"{now:%Y-%m-%d %H:%M %Z}: re-armed {SITE_ALARM_NAME}")


def enabled():
    value = ssm.get_parameter(Name=FLAG_PARAMETER)["Parameter"]["Value"]
    return value.strip().lower() == "true"


def handler(event, context):  # noqa: ARG001 - the scheduler sends no payload
    if not enabled():
        print(f"{FLAG_PARAMETER} is not true: leaving the node group alone")
        return {"skipped": "flag-off"}

    now = datetime.datetime.now(TIMEZONE)
    wanted = wanted_size(now)

    # Before the node group checks, so a run that skips the node group (UPDATING,
    # DEGRADED) still mutes the alarm at night and re-arms it in the morning.
    follow_window(now, wanted)

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

    return {"wanted": wanted, "current": current}
