#!/usr/bin/env python
"""
Takes ready-to-use Plotly YMLs, derives cards from the reads YML,
assembles report_data, and injects it as JSON into the HTML template.
"""

import json
import yaml
import argparse
import re
from datetime import datetime


def load_plot_yaml(yml_file: str) -> dict:
    """Load and return a Plotly YML file."""
    with open(yml_file) as f:
        return yaml.safe_load(f) or {}


def derive_card(reads_plot: dict) -> dict:
    """Derive summary cards from the reads Plotly YML x/y lists."""
    label = reads_plot.get("name", "(data label missing)")
    value = reads_plot.get("data", {}).get("y", "N/A")
    
    return {"name": label, "value": value}


def normalise_plot(plot: dict) -> dict:
    """
    Normalise a Plotly YML into report format.
    Ensures data is always a list (consistent with Plotly multi-trace format).
    """
    data = plot.get("data", {})
    if isinstance(data, dict):
        data = [data]
    return {
        "name": plot.get("name", ""),
        "data": data,
        "layout": plot.get("layout", {}),
    }


def build_report_data(cards: list[dict], plots: list[dict]) -> dict:
    """Assemble the full report_data structure."""
    return {
        "generation_time": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "cards": cards,
        "plots": plots,
        "final": False,
    }


def inject_into_html(template_file: str, report_data: dict, output_file: str) -> None:
    """Inject report_data as JSON into the HTML template and write output."""
    with open(template_file) as f:
        template = f.read()

    json_data = json.dumps(report_data)

    # Use lambda to avoid misinterpreting content as regex escape sequences
    html = re.sub(
        r'<script id="embedded-data" type="application/json">.*?</script>',
        lambda _: f'<script id="embedded-data" type="application/json">{json_data}</script>',
        template,
        flags=re.S,
    )

    with open(output_file, "w") as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--counts_yml", required=True)
    parser.add_argument("--template", required=True)
    parser.add_argument("--output_html", required=True)
    parser.add_argument("--output_json", required=True)
    parser.add_argument("--sample_id", required=False, default=None)
    parser.add_argument("--amplicon_depth_yml", required=False, default=None)
    args = parser.parse_args()

    reads_plot = load_plot_yaml(args.counts_yml)
    cards = [derive_card(reads_plot)]
    
    plots = [normalise_plot(reads_plot)]
    # plots = []

    if args.amplicon_depth_yml:
        depth_plot = load_plot_yaml(args.amplicon_depth_yml)
        plots.append(normalise_plot(depth_plot))

    report_data = build_report_data(cards, plots)
    if args.sample_id:
        report_data["sample_id"] = args.sample_id

    with open(args.output_json, "w") as f:
        json.dump(report_data, f, indent=2)

    inject_into_html(args.template, report_data, args.output_html)


if __name__ == "__main__":
    main()