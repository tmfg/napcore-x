#!/usr/bin/env python3
import collections
import copy
import datetime
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
import zipfile


archive = Path(sys.argv[1]).resolve(strict=True)
if not archive.is_file():
    raise SystemExit(f"Not a regular file: {archive}")

date_element = re.compile(
    rb"<(?P<prefix>(?:[A-Za-z_][\w.-]*:)?)"
    rb"(?P<tag>FromDate|ToDate)>(?P<leading>\s*)"
    rb"(?P<year>20\d{2})(?P<rest>-\d{2}-\d{2}(?:T[^<\s]+)?)"
    rb"(?P<trailing>\s*)</(?P=prefix)(?P=tag)>"
)
namespace = {"netex": "http://www.netex.org.uk/netex"}
stats = collections.Counter()
service_dates = []


def shift_service_dates(data, count_changes=True):
    def replace(match):
        if match["year"] != b"2025":
            return match.group(0)
        if count_changes:
            stats[f'{match["tag"].decode()}_shifted'] += 1
        return (
            match.group(0)[: match.start("year") - match.start()]
            + b"2026"
            + match.group("rest")
            + match.group("trailing")
            + b"</"
            + match.group("prefix")
            + match.group("tag")
            + b">"
        )

    return date_element.sub(replace, data)


fd, temp_name = tempfile.mkstemp(
    prefix=f".{archive.name}.", suffix=".tmp", dir=archive.parent
)
os.close(fd)
temporary = Path(temp_name)

try:
    with zipfile.ZipFile(archive, "r") as source:
        names = [entry.filename for entry in source.infolist()]
        if len(names) != len(set(names)):
            raise ValueError("Archive contains duplicate entry names.")

        with zipfile.ZipFile(temporary, "w") as target:
            target.comment = source.comment
            for entry in source.infolist():
                contents = source.read(entry)
                if entry.filename.lower().endswith(".xml"):
                    contents = shift_service_dates(contents)
                    root = ET.fromstring(contents)
                    for tag in ("FromDate", "ToDate"):
                        for element in root.findall(f".//netex:{tag}", namespace):
                            value = datetime.date.fromisoformat(element.text.strip()[:10])
                            if value.year == 2025:
                                raise ValueError(
                                    f"Unshifted service date in {entry.filename}: {value}"
                                )
                            if value.year == 2026:
                                stats[f"{tag}_2026"] += 1
                                service_dates.append(value)
                    for period in root.findall(
                        ".//netex:UicOperatingPeriod", namespace
                    ):
                        start = datetime.date.fromisoformat(
                            period.find("netex:FromDate", namespace).text.strip()[:10]
                        )
                        end = datetime.date.fromisoformat(
                            period.find("netex:ToDate", namespace).text.strip()[:10]
                        )
                        bits = period.find("netex:ValidDayBits", namespace).text.strip()
                        if len(bits) != (end - start).days + 1 or set(bits) - {"0", "1"}:
                            raise ValueError(
                                f"Invalid operating-period bitmask in {entry.filename}"
                            )
                    stats["xml_files"] += 1
                target.writestr(copy.copy(entry), contents)

    if not stats["FromDate_shifted"] or not stats["ToDate_shifted"]:
        raise ValueError("No 2025 service dates were found; original archive left unchanged.")
    if stats["FromDate_shifted"] != stats["ToDate_shifted"]:
        raise ValueError("FromDate and ToDate counts differ; original archive left unchanged.")

    with zipfile.ZipFile(archive, "r") as source, zipfile.ZipFile(temporary, "r") as target:
        if source.namelist() != target.namelist() or source.comment != target.comment:
            raise ValueError("Archive structure changed; original archive left unchanged.")
        for old_entry, new_entry in zip(source.infolist(), target.infolist()):
            original = source.read(old_entry)
            expected = (
                shift_service_dates(original, count_changes=False)
                if old_entry.filename.lower().endswith(".xml")
                else original
            )
            if target.read(new_entry) != expected:
                raise ValueError(
                    f"Unexpected content change in {old_entry.filename}; "
                    "original archive left unchanged."
                )

    if not service_dates:
        raise ValueError("No 2026 service dates found; original archive left unchanged.")

    shutil.copystat(archive, temporary)
    os.replace(temporary, archive)
except Exception:
    temporary.unlink(missing_ok=True)
    raise

print(f"Replaced {archive} with the validated 2026-date archive.")
print(
    f"Shifted {stats['FromDate_shifted']} FromDate and "
    f"{stats['ToDate_shifted']} ToDate values across {stats['xml_files']} XML files."
)
print(f"Service date range: {min(service_dates)} through {max(service_dates)}.")
print("The original ZIP was replaced only after validation; no backup was retained.")
