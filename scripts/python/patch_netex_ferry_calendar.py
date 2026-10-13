import re
import sys

path, from_date, to_date = sys.argv[1], sys.argv[2], sys.argv[3]
content = open(path, encoding="utf-8").read()

daytype_ids = sorted(set(re.findall(r'<DayType version="1" id="(OTH:DayType:[^"]+)"/>', content)))
if not daytype_ids:
    print("No un-patched OTH DayType declarations found - nothing to do.")
    sys.exit(0)

period_id = "OTH:OperatingPeriod:ferry-patch"


def add_props(m):
    day_id = m.group(1)
    return (
        f'<DayType version="1" id="{day_id}">'
        f'<properties><PropertyOfDay><DaysOfWeek>Everyday</DaysOfWeek></PropertyOfDay></properties>'
        f'</DayType>'
    )


# Every OTH DayType needs an "Everyday" property, since OperatingPeriodRef
# assignments only yield dates matching the DayType's own days-of-week.
content, n_daytypes = re.subn(
    r'<DayType version="1" id="(OTH:DayType:[^"]+)"/>', add_props, content
)

operating_period = (
    f'<OperatingPeriod version="1" id="{period_id}">'
    f'<FromDate>{from_date}T00:00:00</FromDate><ToDate>{to_date}T00:00:00</ToDate>'
    f'</OperatingPeriod>'
)
content = content.replace("<operatingPeriods>", "<operatingPeriods>" + operating_period, 1)

assignments = "".join(
    f'<DayTypeAssignment order="1" version="1" id="OTH:DayTypeAssignment:ferry-patch-{i}">'
    f'<OperatingPeriodRef ref="{period_id}" version="1"/>'
    f'<DayTypeRef ref="{day_id}" version="1"/>'
    f'</DayTypeAssignment>'
    for i, day_id in enumerate(daytype_ids)
)
content = content.replace("<dayTypeAssignments>", "<dayTypeAssignments>" + assignments, 1)

open(path, "w", encoding="utf-8").write(content)
print(f"Patched {n_daytypes} OTH DayType(s) with an Everyday property.")
print(f"Added {len(daytype_ids)} DayTypeAssignment(s) for {from_date}..{to_date}.")
