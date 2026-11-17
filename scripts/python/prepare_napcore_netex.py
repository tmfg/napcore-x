#!/usr/bin/env python3
"""Prepare the Flix NeTEx archive for OTP by completing stop assignments."""

import argparse
import copy
import hashlib
import os
from collections import Counter, defaultdict
from decimal import Decimal, InvalidOperation
from pathlib import Path
import re
import tempfile
import xml.etree.ElementTree as ET
import zipfile


NETEX = "http://www.netex.org.uk/netex"
NS = {"n": NETEX}
STOPS_FILE = "_stops.xml"
SHARED_FILE = "_shared_data.xml"
TIMETABLE_FILE = re.compile(r"line_\d+\.xml")

ET.register_namespace("", NETEX)
ET.register_namespace("siri", "http://www.siri.org.uk/siri")
ET.register_namespace("gml", "http://www.opengis.net/gml/3.2")


def tag(name):
    return f"{{{NETEX}}}{name}"


def required_ref(element, name):
    reference = element.find(tag(name))
    if reference is None or not reference.get("ref"):
        raise ValueError(f"{name} is missing a ref in {element.get('id', element.tag)}")
    return reference.get("ref")


def generated_id(kind, stop_point_id):
    digest = hashlib.sha256(stop_point_id.encode("utf-8")).hexdigest()[:20]
    return f"FTG:{kind}:otp-{digest}"


def coordinate_of(stop_point):
    name = stop_point.findtext(tag("Name"))
    longitude = stop_point.findtext(f"{tag('Location')}/{tag('Longitude')}")
    latitude = stop_point.findtext(f"{tag('Location')}/{tag('Latitude')}")
    if not name or longitude is None or latitude is None:
        raise ValueError(
            f"ScheduledStopPoint {stop_point.get('id')} needs a name and coordinates"
        )
    try:
        longitude_value = Decimal(longitude.strip())
        latitude_value = Decimal(latitude.strip())
    except InvalidOperation as error:
        raise ValueError(
            f"ScheduledStopPoint {stop_point.get('id')} has invalid coordinates"
        ) from error
    if not (-180 <= longitude_value <= 180 and -90 <= latitude_value <= 90):
        raise ValueError(
            f"ScheduledStopPoint {stop_point.get('id')} has out-of-range coordinates"
        )
    return name.strip(), longitude.strip(), latitude.strip()


def inspect_archive_data(archive, names):
    stop_point_ids = set()
    timetable_files = [name for name in names if TIMETABLE_FILE.fullmatch(name)]
    if not timetable_files:
        raise ValueError("No line_<number>.xml timetable files found")

    day_type_refs = set()
    day_type_ids = set()
    for name in names:
        if not name.lower().endswith(".xml"):
            continue
        root = ET.fromstring(archive.read(name))
        day_type_ids.update(
            element.get("id")
            for element in root.findall(".//n:DayType", NS)
            if element.get("id")
        )
        day_type_refs.update(
            element.get("ref")
            for element in root.findall(".//n:DayTypeRef", NS)
            if element.get("ref")
        )
        if name in timetable_files:
            for stop_point in root.findall(
                ".//n:StopPointInJourneyPattern/n:ScheduledStopPointRef", NS
            ):
                reference = stop_point.get("ref")
                if not reference:
                    raise ValueError(f"ScheduledStopPointRef has no ref in {name}")
                stop_point_ids.add(reference)

    if not stop_point_ids:
        raise ValueError("No ScheduledStopPointRef entries found in timetable files")
    return stop_point_ids, len(day_type_refs), len(day_type_refs - day_type_ids)


def add_location(parent, longitude, latitude):
    centroid = ET.SubElement(parent, tag("Centroid"))
    location = ET.SubElement(centroid, tag("Location"))
    ET.SubElement(location, tag("Longitude")).text = longitude
    ET.SubElement(location, tag("Latitude")).text = latitude


def make_stop_place(stop_place_id, stop_points):
    station = ET.Element(tag("StopPlace"), {"version": "1", "id": stop_place_id})
    point_data = [coordinate_of(point) for point in stop_points]
    names = Counter(name for name, _, _ in point_data)
    station_name = sorted(names, key=lambda value: (-names[value], value))[0]
    ET.SubElement(station, tag("Name")).text = station_name

    longitudes = [Decimal(longitude) for _, longitude, _ in point_data]
    latitudes = [Decimal(latitude) for _, _, latitude in point_data]
    longitude = str(sum(longitudes) / len(longitudes))
    latitude = str(sum(latitudes) / len(latitudes))
    add_location(station, longitude, latitude)
    ET.SubElement(station, tag("StopPlaceType")).text = "other"
    ET.SubElement(station, tag("quays"))
    return station


def make_quay(quay_id, stop_point):
    name, longitude, latitude = coordinate_of(stop_point)
    quay = ET.Element(tag("Quay"), {"version": "1", "id": quay_id})
    ET.SubElement(quay, tag("Name")).text = name
    add_location(quay, longitude, latitude)
    return quay


def make_assignment(stop_point_id, stop_place_id, quay_id):
    assignment_id = generated_id("PassengerStopAssignment", stop_point_id)
    assignment = ET.Element(
        tag("PassengerStopAssignment"), {"version": "1", "id": assignment_id}
    )
    for name, reference in (
        ("ScheduledStopPointRef", stop_point_id),
        ("StopPlaceRef", stop_place_id),
        ("QuayRef", quay_id),
    ):
        ET.SubElement(assignment, tag(name), {"ref": reference, "version": "1"})
    return assignment


def serialize(root):
    return ET.tostring(root, encoding="utf-8", xml_declaration=True)


def repair_documents(stops_data, shared_data, used_stop_point_ids):
    stops_root = ET.fromstring(stops_data)
    shared_root = ET.fromstring(shared_data)
    stop_points = {}
    for stop_point in shared_root.findall(".//n:ScheduledStopPoint", NS):
        stop_point_id = stop_point.get("id")
        if not stop_point_id or stop_point_id in stop_points:
            raise ValueError(f"Missing or duplicate ScheduledStopPoint id: {stop_point_id}")
        stop_points[stop_point_id] = stop_point

    places = {}
    for stop_place in stops_root.findall(".//n:StopPlace", NS):
        stop_place_id = stop_place.get("id")
        if not stop_place_id or stop_place_id in places:
            raise ValueError(f"Missing or duplicate StopPlace id: {stop_place_id}")
        places[stop_place_id] = stop_place

    point_to_place = {}
    point_to_quay = {}
    assignments = shared_root.findall(".//n:PassengerStopAssignment", NS)
    for assignment in assignments:
        stop_point_id = required_ref(assignment, "ScheduledStopPointRef")
        stop_place_id = required_ref(assignment, "StopPlaceRef")
        if stop_point_id not in stop_points:
            raise ValueError(f"PassengerStopAssignment references absent point {stop_point_id}")
        old_place = point_to_place.setdefault(stop_point_id, stop_place_id)
        if old_place != stop_place_id:
            raise ValueError(f"ScheduledStopPoint {stop_point_id} maps to multiple StopPlaces")
        quay_ref = assignment.find(tag("QuayRef"))
        quay_id = quay_ref.get("ref") if quay_ref is not None else generated_id("Quay", stop_point_id)
        old_quay = point_to_quay.setdefault(stop_point_id, quay_id)
        if old_quay != quay_id:
            raise ValueError(f"ScheduledStopPoint {stop_point_id} maps to multiple Quays")
        if quay_ref is None:
            quay_ref = ET.SubElement(assignment, tag("QuayRef"))
            quay_ref.set("ref", quay_id)
            quay_ref.set("version", "1")

    missing_assignments = used_stop_point_ids - point_to_place.keys()
    for stop_point_id in sorted(missing_assignments):
        if stop_point_id not in stop_points:
            raise ValueError(
                f"Timetable references absent ScheduledStopPoint {stop_point_id}"
            )
        point_to_place[stop_point_id] = generated_id("StopPlace", stop_point_id)
        point_to_quay[stop_point_id] = generated_id("Quay", stop_point_id)

    for stop_point_id in point_to_place:
        coordinate_of(stop_points[stop_point_id])

    stop_place_parent = {
        child: parent
        for parent in stops_root.iter()
        for child in list(parent)
        if child.tag == tag("StopPlace")
    }
    if not places:
        raise ValueError("No StopPlace records found in _stops.xml")
    stop_place_collection = stop_place_parent[next(iter(places.values()))]

    station_points = defaultdict(list)
    for stop_point_id, stop_place_id in point_to_place.items():
        station_points[stop_place_id].append(stop_points[stop_point_id])

    generated_stop_places = 0
    for stop_place_id, points in station_points.items():
        if stop_place_id not in places:
            places[stop_place_id] = make_stop_place(stop_place_id, points)
            stop_place_collection.append(places[stop_place_id])
            generated_stop_places += 1

    place_of_quay = {}
    for stop_place_id, stop_place in places.items():
        for quay in stop_place.findall("./n:quays/n:Quay", NS):
            quay_id = quay.get("id")
            if not quay_id:
                raise ValueError(f"Quay in StopPlace {stop_place_id} has no id")
            if quay_id in place_of_quay and place_of_quay[quay_id] != stop_place_id:
                raise ValueError(f"Quay {quay_id} appears under multiple StopPlaces")
            place_of_quay[quay_id] = stop_place_id

    added_quays = 0
    for stop_point_id, quay_id in point_to_quay.items():
        stop_place_id = point_to_place[stop_point_id]
        if quay_id in place_of_quay:
            if place_of_quay[quay_id] != stop_place_id:
                raise ValueError(
                    f"Quay {quay_id} is under {place_of_quay[quay_id]}, "
                    f"but assignment uses {stop_place_id}"
                )
            continue
        stop_place = places[stop_place_id]
        quays = stop_place.find(tag("quays"))
        if quays is None:
            quays = ET.SubElement(stop_place, tag("quays"))
        quays.append(make_quay(quay_id, stop_points[stop_point_id]))
        place_of_quay[quay_id] = stop_place_id
        added_quays += 1

    assignment_collection = next(
        (
            parent
            for parent in shared_root.iter()
            if parent.tag == tag("stopAssignments")
            and any(child.tag == tag("PassengerStopAssignment") for child in list(parent))
        ),
        None,
    )
    if assignment_collection is None:
        raise ValueError("No stopAssignments collection found in _shared_data.xml")

    for stop_point_id in sorted(missing_assignments):
        assignment_collection.append(
            make_assignment(
                stop_point_id, point_to_place[stop_point_id], point_to_quay[stop_point_id]
            )
        )

    dropped_groups = 0
    parent_by_child = {
        child: parent
        for parent in stops_root.iter()
        for child in list(parent)
    }
    for group in stops_root.findall(".//n:GroupOfStopPlaces", NS):
        member_refs = [
            reference.get("ref")
            for reference in group.findall(".//n:StopPlaceRef", NS)
        ]
        has_name = bool(group.findtext(tag("Name")))
        has_station_member = any(reference in places for reference in member_refs)
        if not has_name and not has_station_member:
            parent_by_child[group].remove(group)
            dropped_groups += 1

    for stop_point_id in used_stop_point_ids:
        if stop_point_id not in point_to_quay:
            raise ValueError(f"No Quay mapping created for timetable stop {stop_point_id}")
        if point_to_quay[stop_point_id] not in place_of_quay:
            raise ValueError(f"Quay {point_to_quay[stop_point_id]} is not defined")

    return serialize(stops_root), serialize(shared_root), {
        "added_assignments": len(missing_assignments),
        "added_quays": added_quays,
        "added_stop_places": generated_stop_places,
        "dropped_groups": dropped_groups,
    }


def repair_archive(source_path, destination_path):
    source = Path(source_path).resolve(strict=True)
    destination = Path(destination_path).resolve()
    if not source.is_file():
        raise ValueError(f"Source is not a regular file: {source}")
    if source == destination or (
        destination.exists() and os.path.samefile(source, destination)
    ):
        raise ValueError("Output must differ from the original archive")
    if not destination.parent.is_dir():
        raise ValueError(f"Output directory does not exist: {destination.parent}")

    temporary = None
    try:
        with zipfile.ZipFile(source, "r") as original:
            entries = original.infolist()
            names = [entry.filename for entry in entries]
            if len(names) != len(set(names)):
                raise ValueError("Archive contains duplicate entry names")
            if STOPS_FILE not in names or SHARED_FILE not in names:
                raise ValueError(f"Archive must contain {STOPS_FILE} and {SHARED_FILE}")

            used_stop_point_ids, day_type_refs, missing_day_types = inspect_archive_data(
                original, names
            )
            stops_data, shared_data, stats = repair_documents(
                original.read(STOPS_FILE),
                original.read(SHARED_FILE),
                used_stop_point_ids,
            )
            stats["referenced_day_types"] = day_type_refs
            stats["missing_day_types"] = missing_day_types
            replacements = {STOPS_FILE: stops_data, SHARED_FILE: shared_data}

            descriptor, temporary_name = tempfile.mkstemp(
                prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent
            )
            os.close(descriptor)
            temporary = Path(temporary_name)
            with zipfile.ZipFile(temporary, "w") as prepared:
                prepared.comment = original.comment
                for entry in entries:
                    prepared.writestr(
                        copy.copy(entry), replacements.get(entry.filename, original.read(entry))
                    )

        with zipfile.ZipFile(source, "r") as original, zipfile.ZipFile(
            temporary, "r"
        ) as prepared:
            if original.namelist() != prepared.namelist():
                raise ValueError("Prepared archive changed the ZIP entry structure")
            if original.comment != prepared.comment:
                raise ValueError("Prepared archive changed the ZIP comment")
            for entry in original.infolist():
                if entry.filename not in (STOPS_FILE, SHARED_FILE):
                    if original.read(entry) != prepared.read(entry.filename):
                        raise ValueError(f"Unexpected change to {entry.filename}")
            if prepared.testzip() is not None:
                raise ValueError("Prepared archive failed ZIP integrity validation")

        os.replace(temporary, destination)
        temporary = None
        return stats
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    script_directory = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "source",
        nargs="?",
        default=script_directory / "napcore_netex_de_flix.zip",
        type=Path,
        help="original NeTEx ZIP (default: napcore_netex_de_flix.zip)",
    )
    parser.add_argument(
        "destination",
        nargs="?",
        default=script_directory / "napcore_netex_de_flix-otp.zip",
        type=Path,
        help="prepared ZIP (default: napcore_netex_de_flix-otp.zip)",
    )
    arguments = parser.parse_args()
    try:
        stats = repair_archive(arguments.source, arguments.destination)
    except (OSError, ET.ParseError, zipfile.BadZipFile, ValueError) as error:
        parser.exit(1, f"Feed preparation failed: {error}\n")
    print(f"Prepared feed: {arguments.destination}")
    print(
        "Added {added_assignments} assignments, {added_quays} quays, "
        "{added_stop_places} StopPlaces; dropped {dropped_groups} incomplete station groups."
        .format(**stats)
    )
    print(
        "Generated StopPlaces use the scheduled stop points' published names and "
        "coordinates; unassigned points receive separate StopPlaces."
    )
    if stats["missing_day_types"]:
        print(
            f"WARNING: {stats['missing_day_types']} of "
            f"{stats['referenced_day_types']} unique DayType references have no "
            "definition; OTP will not create service dates for those trips."
        )


if __name__ == "__main__":
    main()
