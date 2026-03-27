#!/usr/bin/env python
"""
Accumulates per-amplicon median depth across file_ids into a running YML,
storing a sum-of-medians. Outputs a ready-to-use Plotly YML.

Output schema:
    name: Depth per amplicon
    data:
        type: bar
        x: [amplicon_1, amplicon_2, ...]
        y: [142.0, 87.5, ...]
    layout:
        title: Median amplicon depth
        xaxis:
            title: Amplicon
        yaxis:
            title: Summed median depth
"""

import yaml
import os
import argparse


def load_new_depths(depth_yml: str) -> dict[str, float]:
    """
    Read amplicon depths from a Plotly YML produced by get_amplicon_depth.py.
    Returns a dict of {amplicon_name: median_depth}.
    """
    with open(depth_yml) as f:
        data = yaml.safe_load(f)
    x = data["data"]["x"]
    y = data["data"]["y"]
    return dict(zip(x, y))


def load_existing_totals(published_file: str | None) -> dict[str, float]:
    """
    Load accumulated depth totals from existing Plotly YML.
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


def update_totals(totals: dict[str, float], new_entries: dict[str, float]) -> dict[str, float]:
    """Accumulate sum-of-medians for each amplicon."""
    for amplicon, depth in new_entries.items():
        totals[amplicon] = totals.get(amplicon, 0.0) + depth
    return totals


def build_plot_yaml(
    totals: dict[str, float],
    target_depth: int | None = None,
) -> dict:
    """Build a ready-to-use Plotly YML from accumulated depth totals."""
    layout = {
        "title": "Median amplicon depth",
        "xaxis": {"title": "", "tickangle": -45, "showgrid": False},
        "yaxis": {"title": "Summed median depth", "showgrid": False},
        "width": 500,
        "height": 400,
    }

    if target_depth is not None:
        layout["shapes"] = [
            {
                "type": "line",
                "x0": 0,
                "x1": 1,
                "xref": "paper",
                "y0": target_depth,
                "y1": target_depth,
                "yref": "y",
                "line": {
                    "color": "grey",
                    "width": 1,
                    "dash": "dash",
                },
            }
        ]

    return {
        "name": "Depth per amplicon",
        "data": {
            "type": "bar",
            "x": list(totals.keys()),
            "y": list(totals.values()),
            "marker": {
                "color": [
                    "blue" if v >= target_depth else "grey"
                    for v in totals.values()
                ] if target_depth is not None else "grey"
            }
        },
        "layout": layout,
    }

def write_yaml(plot: dict, output_file: str) -> None:
    """Atomically write YAML to avoid partial reads."""
    tmp_file = output_file + ".tmp"
    with open(tmp_file, "w") as f:
        yaml.dump(plot, f, default_flow_style=False, sort_keys=False)
    os.replace(tmp_file, output_file)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--depth_yml", required=True, help="New depth YML from get_amplicon_depth.py")
    parser.add_argument("--published_file", required=False, help="Path to existing running depth YML")
    parser.add_argument("--target_depth", required=False, type=int, default=None, help="Target depth for amplicon sequencing experiment.")
    args = parser.parse_args()

    output_file = args.published_file

    new_entries = load_new_depths(args.depth_yml)
    totals = load_existing_totals(args.published_file)
    totals = update_totals(totals, new_entries)
    plot = build_plot_yaml(totals, args.target_depth)
    write_yaml(plot, output_file)


if __name__ == "__main__":
    main()