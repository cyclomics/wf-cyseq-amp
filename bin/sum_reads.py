#!/usr/bin/env python
"""
Accumulates read counts and outputs a ready-to-use Plotly YML.

Output schema:
    name: Reads per sample
    data:
        type: bar
        x: [sample_1, sample_2, ...]
        y: [100, 200, ...]
    layout:
        title: Reads per sample
        xaxis:
            title: Sample
        yaxis:
            title: Read count
"""

import json
import yaml
import os
import argparse

def load_new_reads(json_file: str) -> tuple[str, int]:
    """Read type and read count from input JSON."""
    with open(json_file) as f:
        data = json.load(f)
    return data["type"], data["reads"]


def load_existing_totals(published_file: str | None) -> dict[str, int]:
    """
    Load accumulated totals from existing Plotly YML.
    Returns empty dict if no published file exists yet.
    """
    if not published_file:
        return {}
    try:
        with open(published_file) as f:
            existing = yaml.safe_load(f) or {}
        x = existing.get("data", {}).get("x", [])
        y = existing.get("data", {}).get("y", [])
        return dict(zip(x, y))
    except FileNotFoundError:
        return {}


def update_totals(totals: dict[str, int], read_type: str, new_reads: int) -> dict[str, int]:
    """Add new reads to the running totals."""
    key = f"{read_type}"
    totals[key] = totals.get(key, 0) + new_reads
    return totals


def build_plot_yaml(totals: dict[str, int]) -> dict:
    """Build a ready-to-use Plotly YML from accumulated totals."""
    return {
        "name": "Raw reads",
        "data": {
            "type": "bar",
            "x": list(totals.keys()),
            "y": list(totals.values()),
        },
        "layout": {
            "title": "Number of raw reads",
            "xaxis": {"title": "Sample"},
            "yaxis": {"title": "Read count"},
        },
    }


def write_yaml(plot: dict, output_file: str) -> None:
    """Atomically write YAML to avoid partial reads."""
    tmp_file = output_file + ".tmp"
    with open(tmp_file, "w") as f:
        yaml.dump(plot, f, default_flow_style=False, sort_keys=False)
    os.replace(tmp_file, output_file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json_file", required=True)
    parser.add_argument("--published_file", required=False)
    args = parser.parse_args()

    output_file = args.published_file

    read_type, new_reads = load_new_reads(args.json_file)
    totals = load_existing_totals(args.published_file)
    totals = update_totals(totals, read_type, new_reads)
    plot = build_plot_yaml(totals)
    write_yaml(plot, output_file)


if __name__ == "__main__":
    main()