#!/usr/bin/env python3
"""Mock daily Flix NeTEx service from today through the same date next year."""

import argparse
import calendar
import copy
from datetime import date
import os
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET
import zipfile


NETEX = "http://www.netex.org.uk/netex"
NS = {"n": NETEX}
SHARED_FILE = "_shared_data.xml"
TIMETABLE_FILE = re.compile(r"line_\d+\.xml")
PERIOD_ID = "FTG:OperatingPeriod:flix-calendar-patch"

ET.register_namespace("", NETEX)
ET.register_namespace("siri", "http://www.siri.org.uk/siri")
ET.register_namespace("gml", "http://www.opengis.net/gml/3.2")


def tag(name):
    return f"{{{NETEX}}}{name}"


def next_year(day):
    last_day = calendar.monthrange(day.year + 1, day.month)[1]
    return day.replace(year=day.year + 1, day=min(day.day, last_day))


def collect_day_types(archive, names):
    versions = {}
    timetable_files = [name for name in names if TIMETABLE_FILE.fullmatch(name)]
    if not timetable_files:
        raise ValueError("No line_<number>.xml timetable files found")
    for name in timetable_files:
        root = ET.fromstring(archive.read(name))
        if root.findall(".//n:ServiceCalendarFrame", NS):
            raise ValueError(f"Local calendar in {name} would override the shared mock calendar")
        journeys = root.findall(".//n:ServiceJourney", NS)
        if not journeys:
            raise ValueError(f"No ServiceJourney entries found in {name}")
        for journey in journeys:
            references = journey.findall("n:dayTypes/n:DayTypeRef", NS)
            if not references:
                raise ValueError(f"ServiceJourney {journey.get('id')} in {name} has no DayTypeRef")
            for reference in references:
                day_id = reference.get("ref")
                if not day_id:
                    raise ValueError(f"DayTypeRef is missing a ref in {name}")
                version = reference.get("version", "1")
                if day_id in versions and versions[day_id] != version:
                    raise ValueError(f"Conflicting versions for DayType {day_id}")
                versions[day_id] = version
    return versions, len(timetable_files)


def mock_calendar(shared_data, versions, from_date, to_date):
    root = ET.fromstring(shared_data)
    frames = root.findall(".//n:ServiceCalendarFrame", NS)
    if len(frames) != 1:
        raise ValueError("Expected exactly one shared ServiceCalendarFrame")
    frame = frames[0]
    # Replace the old calendar, including exceptions, on repeated runs.
    for child in list(frame):
        if child.tag in {
            tag("ServiceCalendar"), tag("dayTypes"), tag("operatingDays"),
            tag("operatingPeriods"), tag("dayTypeAssignments"),
        }:
            frame.remove(child)

    day_types = ET.SubElement(frame, tag("dayTypes"))
    for day_id, version in sorted(versions.items()):
        day_type = ET.SubElement(day_types, tag("DayType"), {"id": day_id, "version": version})
        properties = ET.SubElement(day_type, tag("properties"))
        property_of_day = ET.SubElement(properties, tag("PropertyOfDay"))
        ET.SubElement(property_of_day, tag("DaysOfWeek")).text = "Everyday"

    periods = ET.SubElement(frame, tag("operatingPeriods"))
    period = ET.SubElement(periods, tag("OperatingPeriod"), {"id": PERIOD_ID, "version": "1"})
    ET.SubElement(period, tag("FromDate")).text = f"{from_date.isoformat()}T00:00:00"
    ET.SubElement(period, tag("ToDate")).text = f"{to_date.isoformat()}T00:00:00"

    assignments = ET.SubElement(frame, tag("dayTypeAssignments"))
    for index, (day_id, version) in enumerate(sorted(versions.items()), start=1):
        assignment = ET.SubElement(assignments, tag("DayTypeAssignment"), {
            "id": f"FTG:DayTypeAssignment:flix-calendar-patch-{index}",
            "version": "1", "order": str(index),
        })
        ET.SubElement(assignment, tag("OperatingPeriodRef"), {"ref": PERIOD_ID, "version": "1"})
        ET.SubElement(assignment, tag("DayTypeRef"), {"ref": day_id, "version": version})
        ET.SubElement(assignment, tag("IsAvailable")).text = "true"
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def patch_archive(source, destination, from_date, to_date):
    if from_date > to_date:
        raise ValueError("FROM_DATE must not be after TO_DATE")
    source, destination = Path(source).resolve(), Path(destination).resolve()
    if not source.is_file():
        raise ValueError(f"Source is not a regular file: {source}")
    if not destination.parent.is_dir():
        raise ValueError(f"Output directory does not exist: {destination.parent}")

    temporary = None
    try:
        with zipfile.ZipFile(source) as original:
            entries = original.infolist()
            names = [entry.filename for entry in entries]
            if len(names) != len(set(names)):
                raise ValueError("Archive contains duplicate entry names")
            if SHARED_FILE not in names:
                raise ValueError(f"Archive must contain {SHARED_FILE}")
            versions, line_count = collect_day_types(original, names)
            patched = mock_calendar(original.read(SHARED_FILE), versions, from_date, to_date)
            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
            )
            os.close(descriptor)
            temporary = Path(temporary_name)
            with zipfile.ZipFile(temporary, "w") as output:
                output.comment = original.comment
                for entry in entries:
                    data = patched if entry.filename == SHARED_FILE else original.read(entry)
                    output.writestr(copy.copy(entry), data)

        with zipfile.ZipFile(temporary) as output:
            bad_member = output.testzip()
            if bad_member is not None:
                raise ValueError(f"Patched archive failed ZIP integrity validation: {bad_member}")
        os.replace(temporary, destination)
        temporary = None
        return len(versions), line_count
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", nargs="?", type=Path, default=Path("napcore_netex_de_flix.zip"))
    parser.add_argument(
        "destination", nargs="?", type=Path, default=Path("napcore_netex_de_flix-calendar.zip"),
        help="output ZIP (may equal input for an in-place patch)",
    )
    arguments = parser.parse_args()
    try:
        from_date = date.fromisoformat(os.environ.get("FROM_DATE", date.today().isoformat()))
        to_date = date.fromisoformat(os.environ.get("TO_DATE", next_year(from_date).isoformat()))
        day_count, line_count = patch_archive(
            arguments.source, arguments.destination, from_date, to_date
        )
    except (OSError, ET.ParseError, zipfile.BadZipFile, ValueError) as error:
        parser.exit(1, f"Calendar patch failed: {error}\n")
    print(f"Patched {day_count} DayTypes across {line_count} timetable files.")
    print(f"Everyday service: {from_date}..{to_date} (inclusive).")
    print(f"Written to {arguments.destination}")


if __name__ == "__main__":
    main()
