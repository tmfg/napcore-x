import copy
import re
import sys
import xml.etree.ElementTree as ET

directory = sys.argv[1]
namespace = "http://www.netex.org.uk/netex"
namespaces = {}

for _, (prefix, uri) in ET.iterparse(
    f"{directory}/_stops.xml", events=("start-ns",)
):
    namespaces[prefix] = uri
for _, (prefix, uri) in ET.iterparse(
    f"{directory}/_shared_data.xml", events=("start-ns",)
):
    namespaces[prefix] = uri
for prefix, uri in namespaces.items():
    if prefix != "xml":
        ET.register_namespace(prefix, uri)


def parse_xml(path):
    parser = ET.XMLParser(
        target=ET.TreeBuilder(insert_comments=True, insert_pis=True)
    )
    return ET.parse(path, parser=parser)


def is_element(element, name):
    return (
        isinstance(element.tag, str)
        and element.tag == f"{{{namespace}}}{name}"
    )


def elements(root, name):
    return [element for element in root.iter() if is_element(element, name)]


def child(element, name):
    if element is None:
        return None
    return next((item for item in element if is_element(item, name)), None)


def required_attribute(element, name):
    value = element.get(name)
    if value is None:
        raise ValueError(f"Missing {name} on {element.tag}")
    return value


def unique_index(root, name):
    index = {}
    for element in elements(root, name):
        identifier = required_attribute(element, "id")
        if identifier in index:
            raise ValueError(f"Duplicate {name}: {identifier}")
        index[identifier] = element
    return index


def platform_ids(stop_point):
    match = re.fullmatch(
        r"SE:001:ScheduledStopPoint:(9022[0-9]{12})", stop_point
    )
    if match is None:
        raise ValueError(
            f"Unsupported Stockholm scheduled stop identifier: {stop_point}"
        )
    code = match.group(1)
    return (
        f"SE:001:Quay:{code}",
        f"FTG:StopPlace:9021{code[4:13]}000",
        code[-3:],
    )


def qualified_name(parent, name):
    return f"{{{namespace}}}{name}"


def append_element(parent, element):
    if len(parent):
        whitespace = parent[-1].tail
        if whitespace and whitespace.isspace():
            parent[-1].tail = whitespace
            element.tail = whitespace
    parent.append(element)


stops = parse_xml(f"{directory}/_stops.xml")
shared = parse_xml(f"{directory}/_shared_data.xml")
places = unique_index(stops.getroot(), "StopPlace")
quays = unique_index(stops.getroot(), "Quay")
scheduled = unique_index(shared.getroot(), "ScheduledStopPoint")
assignments = elements(shared.getroot(), "PassengerStopAssignment")
if not places or not quays or not assignments:
    raise ValueError(
        "Expected Stockholm StopPlaces, Quays and PassengerStopAssignments"
    )

for place in places.values():
    container = child(place, "quays")
    if container is None:
        continue
    for quay in (item for item in container if is_element(item, "Quay")):
        stop_point = required_attribute(quay, "id").replace(
            ":Quay:", ":ScheduledStopPoint:", 1
        )
        _, parent_id, _ = platform_ids(stop_point)
        if parent_id != place.get("id"):
            raise ValueError(
                f"Platform does not match its station: {quay.get('id')}"
            )

stats = {
    "assignments": len(assignments),
    "original_quays": len(quays),
    "rewritten_quay_refs": 0,
    "restored_quays_at_station_centroids": 0,
}
for assignment in assignments:
    stop_ref = child(assignment, "ScheduledStopPointRef")
    quay_ref = child(assignment, "QuayRef")
    if stop_ref is None or quay_ref is None:
        raise ValueError(
            f"Incomplete PassengerStopAssignment: {assignment.get('id')}"
        )
    stop_id = required_attribute(stop_ref, "ref")
    if stop_id not in scheduled:
        raise ValueError(f"ScheduledStopPoint is absent: {stop_id}")
    quay_id, parent_id, platform = platform_ids(stop_id)
    if parent_id not in places:
        raise ValueError(f"Parent station is absent for {stop_id}: {parent_id}")
    if quay_id not in quays:
        place = places[parent_id]
        centroid = child(place, "Centroid")
        location = child(centroid, "Location")
        if (
            child(location, "Latitude") is None
            or child(location, "Longitude") is None
        ):
            raise ValueError(f"Parent station has no coordinates: {parent_id}")
        container = child(place, "quays")
        if container is None:
            container = ET.Element(qualified_name(place, "quays"))
            append_element(place, container)
        quay = ET.Element(
            qualified_name(container, "Quay"),
            {"version": "1", "id": quay_id},
        )
        append_element(container, quay)
        private_code = ET.Element(qualified_name(quay, "PrivateCode"))
        private_code.text = str(int(platform))
        append_element(quay, private_code)
        append_element(quay, copy.deepcopy(centroid))
        quays[quay_id] = quay
        stats["restored_quays_at_station_centroids"] += 1
    if required_attribute(quay_ref, "ref") != quay_id:
        quay_ref.set("ref", quay_id)
        quay_ref.attrib.pop("version", None)
        stats["rewritten_quay_refs"] += 1

for ref in elements(shared.getroot(), "QuayRef"):
    identifier = required_attribute(ref, "ref")
    if identifier not in quays:
        raise ValueError(f"Unresolved quay reference after repair: {identifier}")

stats["output_quays"] = len(quays)
stops.write(
    f"{directory}/_stops.xml", encoding="UTF-8", xml_declaration=True
)
shared.write(
    f"{directory}/_shared_data.xml", encoding="UTF-8", xml_declaration=True
)
with open(f"{directory}/stats", "w", encoding="utf-8") as report:
    for name in (
        "assignments",
        "original_quays",
        "rewritten_quay_refs",
        "restored_quays_at_station_centroids",
        "output_quays",
    ):
        report.write(f"  {name}: {stats[name]}\n")
    if stats["restored_quays_at_station_centroids"]:
        report.write(
            "WARNING: Restored platform coordinates are station centroids, "
            "not surveyed positions.\n"
        )
