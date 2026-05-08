#!/usr/bin/env python
"""
Takes ready-to-use Plotly YMLs, derives cards from the reads YML,
assembles report_data, and injects it as JSON into the HTML template.
"""

import argparse
import base64
import json
import re
from datetime import datetime
from pathlib import Path
from typing import Union

import numpy as np
import yaml

CARD_NAMES = {
    "n_raw_reads": "Raw reads",
    "bp_total_raw": "Raw bases (bp)",
    "n_mapped_raw": "Mapped raw reads",
    "bp_mapped_raw": "Mapped bases (bp)",
    "n_consensus_reads": "Consensus reads",
    "bp_consensus": "Consensus bases (bp)",
}

Number = Union[int, float, str]


def human_format(num: Number) -> str:
    """Format a number with K/M/B/T suffixes."""

    try:
        num = float(num)
    except (TypeError, ValueError):
        return str(num)

    suffixes = ("", "K", "M", "B", "T")

    magnitude = 0
    while abs(num) >= 1000 and magnitude < len(suffixes) - 1:
        num /= 1000.0
        magnitude += 1

    formatted = f"{num:.3g}".rstrip("0").rstrip(".") or "0"

    return f"{formatted}{suffixes[magnitude]}"


def load_all_yamls(folder: str) -> list[list[dict]]:
    """Load all YAML files in a folder."""
    plots = []
    cards = []

    for yml_file in sorted(Path(folder).glob("*.y*ml")):
        with open(yml_file, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}

        if "cards" in data.keys():
            cards.extend(
                {"name": CARD_NAMES[k], "value": human_format(v)}
                for k, v in data["cards"].items()
            )
            continue

        data["_source"] = yml_file.name
        plot = normalise_plot(data)
        plots.append(plot)

    return [cards, plots]


def load_plot_yaml(yml_file: str) -> dict:
    """Load and return a Plotly YML file."""
    with open(yml_file, encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def normalise_plot(plot: dict) -> dict:
    """
    Normalise a Plotly YML into report format.
    Ensures data is always a list (consistent with Plotly multi-trace format).
    """
    data_list = plot.get("data", [])
    if isinstance(data_list, dict):
        data_list = [data_list]

    for trace in data_list:
        for axis in ["x", "y"]:
            if isinstance(trace.get(axis), dict) and "bdata" in trace[axis]:
                # Decode base64 to numpy array, then to a standard Python list
                binary_data = base64.b64decode(trace[axis]["bdata"])
                trace[axis] = np.frombuffer(
                    binary_data, dtype=trace[axis]["dtype"]
                ).tolist()

    return {
        "name": plot.get("name", ""),
        "data": data_list,
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
        lambda _: (
            f'<script id="embedded-data" type="application/json">{json_data}</script>'
        ),
        template,
        flags=re.S,
    )

    with open(output_file, "w") as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True)
    parser.add_argument("--output_html", required=True)
    parser.add_argument("--output_json", required=True)
    parser.add_argument("--sample_id", required=False, default=None)
    args = parser.parse_args()

    cards, plots = load_all_yamls(".")

    report_data = build_report_data(cards, plots)
    if args.sample_id:
        report_data["sample_id"] = args.sample_id

    with open(args.output_json, "w", encoding="utf-8") as f:
        json.dump(report_data, f, indent=2)

    inject_into_html(args.template, report_data, args.output_html)


if __name__ == "__main__":
    main()
