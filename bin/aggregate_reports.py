#!/usr/bin/env python

import glob
import json
import datetime
from safe_write import safe_write_json


def load_json(path):
    with open(path) as fh:
        return json.load(fh)


def main():

    merged = {
        "generation_time": datetime.datetime.now().isoformat(),
        "cards": [],
        "plots": []
    }

    for json_file in glob.glob("metrics/*.json"):

        data = load_json(json_file)

        if "card" in data:
            merged["cards"].append(data["card"])

        if "plot" in data:
            merged["plots"].append(data["plot"])

    safe_write_json(merged, "report_data.json")


if __name__ == "__main__":
    main()