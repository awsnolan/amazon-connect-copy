"""
Lambda: dr-test-after-hours-check

Called by Amazon Connect contact flow to determine if the contact centre
is currently within operating hours.

Uses TIMEZONE, OPEN_HOUR, CLOSE_HOUR environment variables.

Output (returned to Connect):
  {"isOpen": "true"} or {"isOpen": "false"}
"""

import os
from datetime import datetime, timezone, timedelta


# Australia/Sydney is UTC+10 (or +11 during DST)
# Simplified: use fixed offset. Production would use pytz/zoneinfo.
TIMEZONE_OFFSETS = {
    "Australia/Sydney": 10,
    "Australia/Melbourne": 10,
    "Australia/Brisbane": 10,
    "US/Eastern": -5,
    "US/Pacific": -8,
    "Europe/London": 0,
}


def handler(event, context):
    tz_name = os.environ.get("TIMEZONE", "Australia/Sydney")
    open_hour = int(os.environ.get("OPEN_HOUR", "8"))
    close_hour = int(os.environ.get("CLOSE_HOUR", "18"))

    offset_hours = TIMEZONE_OFFSETS.get(tz_name, 10)
    local_tz = timezone(timedelta(hours=offset_hours))
    now = datetime.now(local_tz)

    is_weekday = now.weekday() < 5  # Mon-Fri
    is_business_hours = open_hour <= now.hour < close_hour

    is_open = is_weekday and is_business_hours

    return {"isOpen": str(is_open).lower()}
