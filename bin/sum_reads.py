#!/usr/bin/env python
import json
import os
import argparse

parser = argparse.ArgumentParser(description="Update running totals of reads")
parser.add_argument("--type", required=True)
parser.add_argument("--sample_id", required=True)
parser.add_argument("--json_file", required=True)
parser.add_argument("--published_file", required=False)
args = parser.parse_args()

totals_file = "number_of_reads_running.json"

# read new reads
with open(args.json_file) as f:
    new_data = json.load(f)
new_reads = new_data['reads']

# start from published totals if it exists
totals = {}
if args.published_file:
    try:
        with open(args.published_file) as f:
            totals = json.load(f)
    except FileNotFoundError:
        pass  # first run, no published file yet

# update totals
key = f"{args.type}__{args.sample_id}"
totals[key] = totals.get(key, 0) + new_reads

# write updated totals
tmp_file = totals_file + ".tmp"
with open(tmp_file, "w") as f:
    json.dump(totals, f, indent=2)
os.replace(tmp_file, totals_file)