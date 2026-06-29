#!/usr/bin/env python
"""
Takes ready-to-use Plotly YMLs, derives cards from the reads YML,
assembles report data, and injects it as JSON into the HTML template.
"""

import argparse
import base64
import glob
import json
import os
import re
from datetime import datetime
from pathlib import Path
from typing import Union

import numpy as np
import yaml

CARD_NAMES = {
    "n_raw_reads": (
        "Raw reads",
        None,
        "Total number of ingested raw reads in the sequencing run.",
    ),
    "median_read_length_raw": (
        "Median raw read length",
        "bp",
        "Median length of all ingested raw reads.",
    ),
    "median_repeats": (
        "Median number of repeats",
        None,
        "Median number of identified repeats per raw read. "
        "A repeat is the basic unit of a concatemeric read, "
        "typically corresponding to the insert.",
    ),
    "n_mapped_raw": (
        "Mapped raw reads",
        None,
        "Number of ingested raw reads successfully mapped to the reference.",
    ),
    "median_mappability_raw": (
        "Median alignment completeness",
        "%",
        "Median percentage of mapped bases in a raw read over the its total length.",
    ),
    "n_consensus_reads": (
        "Consensus reads",
        None,
        "Number of consensus reads successfully generated.",
    ),
    "median_read_length_consensus": (
        "Median consensus read length",
        "bp",
        "Median length of successful consensus reads.",
    ),
    "on_target_rate": (
        "Consensus on-target rate",
        "%",
        "Percentage of successful consensus reads mapping to the target loci.",
    ),
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

    formatted = f"{num:.3g}"

    if "." in formatted:
        formatted = formatted.rstrip("0").rstrip(".")

    return f"{formatted}{suffixes[magnitude]}"


def format_card(card: str, value: Number) -> dict | None:
    """Convert a raw card entry into a report-ready dict."""

    if card not in CARD_NAMES:
        return None

    label, unit, tooltip = CARD_NAMES[card]
    formatted_value = human_format(value)

    return {
        "name": label,
        "value": f"{formatted_value}{unit}" if unit else formatted_value,
        "tooltip": tooltip,
    }


def load_all_yamls(folder: str) -> list[list[dict]]:
    """Load all YAML files in a folder."""
    plots = []
    cards = []

    for yml_file in sorted(Path(folder).glob("*.y*ml")):
        with open(yml_file, encoding="utf-8") as f:
            data = yaml.safe_load(f) or {}

        if "cards" in data:
            cards.extend(
                card_dict
                for card, value in data["cards"].items()
                if (card_dict := format_card(card, value)) is not None
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
    Ensures data is always a list.
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


def inject_into_html(template_file: str, report_data: dict, output_file: Path) -> None:
    """Inject report_data as JSON into the HTML template and write output."""
    with open(template_file, encoding="utf-8") as f:
        template = f.read()

    json_data = json.dumps(report_data)

    html = re.sub(
        r'<script id="embedded-data" type="application/json">.*?</script>',
        lambda _: (
            f'<script id="embedded-data" type="application/json">{json_data}</script>'
        ),
        template,
        flags=re.S,
    )

    with open(output_file, "w", encoding="utf-8") as f:
        f.write(html)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True)
    parser.add_argument("--sample_id", required=True)
    parser.add_argument(
        "--epi2me_report",
        type=bool,
        default=False,
        help="Generate timestamped report for EPI2ME",
    )
    parser.add_argument("--clean_dir", type=str, required=False)
    args = parser.parse_args()

    cards, plots = load_all_yamls(".")

    report_data = build_report_data(cards, plots)
    if args.sample_id:
        report_data["sample_id"] = args.sample_id

    output_json_path = Path(f"report_{args.sample_id}.json")

    if args.epi2me_report:
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")[:20]
        output_html_path = Path(f"report_{args.sample_id}_{timestamp}.html")
    else:
        output_html_path = Path(f"report_{args.sample_id}.html")

    with open(output_json_path, "w", encoding="utf-8") as f:
        json.dump(report_data, f, indent=2)

    inject_into_html(args.template, report_data, output_html_path)

    # Clean up intermediate reports
    if args.epi2me_report and args.clean_dir and os.path.exists(args.clean_dir):
        search_pattern = os.path.join(args.clean_dir, f"report_{args.sample_id}_*.html")

        for old_file in glob.glob(search_pattern):
            if os.path.basename(old_file) == output_html_path.name:
                continue

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
