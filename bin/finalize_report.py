#!/usr/bin/env python
"""
Finalizes the report after collecting all upstream processes.

TODO: New post-merge data will also be injected into the final report.

The report is marked as final by setting final=True in the embedde
JSON and writing the output HTML.
"""

import json
import argparse
import re


def load_report_data(json_file: str) -> dict:
    """Load report data from JSON file."""
    with open(json_file) as f:
        data = json.load(f)
    return data


def inject_into_html(report_data: dict, html_file: str, output_file: str) -> None:
    """Inject finalized report_data as JSON into the HTML and write output."""
    report_data["final"] = True
    json_data = json.dumps(report_data)

    with open(html_file) as f:
        html = f.read()

    # Use lambda to avoid misinterpreting content as regex escape sequences
    html = re.sub(
        r'<script id="embedded-data" type="application/json">.*?</script>',
        lambda _: f'<script id="embedded-data" type="application/json">{json_data}</script>',
        html,
        flags=re.S,
    )

    with open(output_file, "w") as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", required=True)
    parser.add_argument("--html", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    report_data = load_report_data(args.json)
    inject_into_html(report_data, args.html, args.output)


if __name__ == "__main__":
    main()