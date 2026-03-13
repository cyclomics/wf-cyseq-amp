#!/usr/bin/env python
import json
import argparse
import re

parser = argparse.ArgumentParser(description="Finalize report with all run data")
parser.add_argument("--html", required=True)
parser.add_argument("--json", required=True)
parser.add_argument("--output", required=True)
args = parser.parse_args()

# load report data
with open(args.json) as f:
    data = json.load(f)

data["final"] = True
json_data = json.dumps(data)

with open(args.html) as f:
    html = f.read()

# replace embedded JSON
# using lambda is important so we don't misinterpret content as regex escape sequences
html = re.sub(
    r'<script id="embedded-data" type="application/json">.*?</script>',
    lambda _: f'<script id="embedded-data" type="application/json">{json_data}</script>',
    html,
    flags=re.S
)

# write final report
with open(args.output, "w") as f:
    f.write(html)