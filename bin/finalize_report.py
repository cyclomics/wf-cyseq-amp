#!/usr/bin/env python
"""
Finalizes the report after collecting all upstream processes.
Merges multiple JSON fragments into a single data structure and injects it into HTML.
"""

import argparse
import glob
import json
import os
import re
from typing import Dict, List


def load_report_data(json_file: str) -> dict:
    """Load report data from JSON file."""
    with open(json_file) as f:
        return json.load(f)


def merge_report_fragments(json_paths: List[str]) -> Dict:
    merged_data = {"tabs": [], "cards": [], "plots": []}

    for path in json_paths:
        data = load_report_data(path)

        # Check for the specific variant-table fragment
        if "variant-table" in data:
            merged_data["tabs"].append(data["variant-table"])
        else:
            # Standard merge for cards and plots
            for key in ["cards", "plots"]:
                if key in data:
                    merged_data[key].extend(data[key])
            for key in ["sample_id", "generation_time"]:
                if key in data:
                    merged_data[key] = data[key]

    return merged_data


def inject_into_html(report_data: dict, html_file: str, output_file: str) -> None:
    """Inject finalized report_data as JSON into the HTML and write output."""
    report_data["final"] = True
    json_data = json.dumps(report_data)

    with open(html_file) as f:
        html = f.read()

    # Inject using the existing regex logic
    html = re.sub(
        r'<script id="embedded-data" type="application/json">.*?</script>',
        lambda _: (
            f'<script id="embedded-data" type="application/json">{json_data}</script>'
        ),
        html,
        flags=re.S,
    )

    with open(output_file, "w") as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--json", nargs="+", required=True, help="List of JSON fragments"
    )
    parser.add_argument("--html", required=True)
    parser.add_argument("--sample_id", required=True)
    parser.add_argument(
        "--epi2me_report",
        action="store_true",
        help="Generate timestamped report for EPI2ME",
    )
    parser.add_argument("--clean_dir", type=str, required=False)
    args = parser.parse_args()

    # Merge all data
    final_report_data = merge_report_fragments(args.json)

    # Inject into template
    inject_into_html(final_report_data, args.html, f"report_{args.sample_id}.html")

    # Clean up intermediate files if specified
    if args.epi2me_report and args.clean_dir and os.path.exists(args.clean_dir):
        search_pattern = os.path.join(args.clean_dir, f"report_{args.sample_id}_*.html")

        for old_file in glob.glob(search_pattern):
            print(f"Attempting to delete stale stream report: {old_file}")
            try:
                os.remove(old_file)
                print(f"Successfully deleted stale stream report: {old_file}")
            except OSError as e:
                print(f"Skipping locked file: {old_file}. Error: {e}")
    else:
        print(
            f"No clean directory specified or directory does not exist: {args.clean_dir}"
        )


if __name__ == "__main__":
    main()
