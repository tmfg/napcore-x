import datetime
import json
import math
import sys

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = json.load(config_file)
extracts = config.get("extracts") if isinstance(config, dict) else None
if not isinstance(extracts, list) or not extracts:
    sys.exit(f"{sys.argv[1]}: extracts must be a non-empty array")

date = datetime.date.today().isoformat()
for index, extract in enumerate(extracts, 1):
    output = extract.get("output") if isinstance(extract, dict) else None
    bbox = extract.get("bbox") if isinstance(extract, dict) else None
    if not isinstance(output, str) or not output or "\0" in output:
        sys.exit(f"{sys.argv[1]}: extract {index} requires a non-empty output path")
    if (
        not isinstance(bbox, list)
        or len(bbox) != 4
        or any(type(value) not in (int, float) or not math.isfinite(value) for value in bbox)
        or not (-180 <= bbox[0] < bbox[2] <= 180)
        or not (-90 <= bbox[1] < bbox[3] <= 90)
    ):
        sys.exit(f"{sys.argv[1]}: extract {index} requires bbox [west, south, east, north]")
    output = output.replace("$(date +%Y-%m-%d)", date)
    sys.stdout.write(output + "\0" + ",".join(map(str, bbox)) + "\0")
