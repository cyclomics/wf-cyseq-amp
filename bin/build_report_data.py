#!/usr/bin/env python

import json
import argparse
import re
from datetime import datetime

parser = argparse.ArgumentParser()

parser.add_argument("--counts_json", required=True)
parser.add_argument("--template", required=True)
parser.add_argument("--output", required=True)

args = parser.parse_args()

# Load counts
with open(args.counts_json) as f:
    counts = json.load(f)

cards = []
samples = []
reads = []

for key, value in counts.items():

    type_val, sample_id = key.split("__")

    cards.append({
        "name": f"{type_val} reads ({sample_id})",
        "value": value
    })

    samples.append(sample_id)
    reads.append(value)

# Build plots
plots = [
    {
        "name": "Reads per sample",
        "data": [
            {
                "type": "bar",
                "x": samples,
                "y": reads
            }
        ],
        "layout": {
            "title": "Reads per sample"
        }
    }
]

report_data = {
    "generation_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
    "cards": cards,
    "plots": plots,
    "final": False
}

# Write JSON output
with open("report_data.json", "w") as f:
    json.dump(report_data, f, indent=2)


# Inject JSON into HTML
with open(args.template) as f:
    template = f.read()

json_data = json.dumps(report_data)

html = re.sub(
    r'<script id="embedded-data" type="application/json">.*?</script>',
    f'<script id="embedded-data" type="application/json">{json_data}</script>',
    template,
    flags=re.S
)

with open(args.output, "w") as f:
    f.write(html)