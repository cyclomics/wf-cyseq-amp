#!/usr/bin/env python
"""
Accumulates consensus metrics across file_ids into a running metrics folder.

This script loads metrics from a new folder, merges them with any previously
accumulated metrics, and writes the updated metrics back to the output folder.

Uses the cyseqcon.metrics Report API to handle aggregation automatically.
"""

import argparse
import json
from pathlib import Path
from textwrap import wrap
from typing import Any, Mapping

import yaml
from cyseqtools.consensus.metrics.report import Report
from plotly.utils import PlotlyJSONEncoder

PREV_METRICS_FOLDER = Path(".prev_read_metrics")


def _get_nested(mapping: Mapping[str, Any], *keys: str, default: Any = 0) -> Any:
    """Safely retrieve a nested value from a mapping."""
    current: Any = mapping
    for key in keys:
        if not isinstance(current, Mapping):
            return default
        current = current.get(key)
        if current is None:
            return default
    return current


def _write_yaml(data: dict, output_file: Path) -> None:
    """Write metric data onto YAML file."""
    with open(output_file, "w", encoding="utf-8") as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False)


def load_and_merge_metrics(
    new_metrics_folder: Path, prev_metrics_folder: Path, output_folder: Path
) -> Report:
    """
    Load new metrics, merge with existing published metrics if present,
    and save the aggregated result.
    """
    report = Report()

    # Load existing accumulated metrics if they exist
    if prev_metrics_folder.exists() and any(Path(prev_metrics_folder).iterdir()):
        report.load_from_path(prev_metrics_folder)

    # Merge new metrics
    report.load_from_path(new_metrics_folder)

    # Write merged metrics to work folder
    if not output_folder.exists():
        output_folder.mkdir(parents=True, exist_ok=True)

    report.save(output_folder)

    return report


def save_metric_plots(report: Report) -> None:
    """Loads the metric report, generates plot figures
    and saves them to individual YAML files.
    """

    Path("plots").mkdir(exist_ok=True)
    for plot in report.available_plots:
        fig = report.plot(plot)

        # Update layout
        for trace in fig.data:
            if hasattr(trace, "name") and trace.name:
                # Breaks text into an array of strings every 30 characters
                trace.name = "<br>".join(wrap(trace.name, width=30))

        fig.update_layout(
            template="simple_white", height=450, autosize=True, legend={"valign": "top"}
        )

        fig_json = json.loads(json.dumps(fig.to_plotly_json(), cls=PlotlyJSONEncoder))
        fig_json["name"] = plot
        _write_yaml(fig_json, Path(f"plots/{plot.replace('/', '_')}.yaml"))


def save_metric_cards(report: Report) -> None:
    """Generate and save metric cards from a report.

    Card 1: Number of raw reads
    Card 2: Median raw read length
    Card 3: Median number of repeats
    Card 3b: Mapped raw reads -- should be substituted by on-target rate
    Card 4: Median mappability raw reads
    Card 5: Number of valid consensus reads
    Card 6: Median consensus read length
    """

    Path("cards").mkdir(exist_ok=True)

    metrics = report.metrics

    read_counts = getattr(metrics.get("read_counts"), "data", {})
    raw_length = getattr(metrics.get("raw_length"), "data", {})
    num_repeats = getattr(metrics.get("num_repeats"), "data", {})
    mapped_bases = getattr(metrics.get("mapped_bases"), "data", {})
    consensus = getattr(metrics.get("consensus_length"), "data", {})

    cards = {
        "cards": {
            "n_raw_reads": read_counts.get("run"),
            "median_read_length_raw": _get_nested(raw_length, "run", "median"),
            "median_repeats": _get_nested(num_repeats, "run", "median"),
            "n_mapped_raw": _get_nested(mapped_bases, "success", "grouped", "n")
            - _get_nested(mapped_bases, "fail", "Read has zero alignments", "n"),
            "median_mappability_raw": _get_nested(mapped_bases, "run", "median"),
            "n_consensus_reads": _get_nested(read_counts, "success", "grouped"),
            "median_read_length_consensus": _get_nested(
                consensus, "success", "grouped", "median"
            ),
        }
    }

    _write_yaml(cards, Path("cards/cards.yaml"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--metrics_folder",
        type=Path,
        required=True,
        help="Folder containing new metrics YML files from this file_id",
    )
    parser.add_argument(
        "--published_folder",
        type=Path,
        required=True,
        default=None,
        help="Folder containing previously accumulated metrics (if any)",
    )

    args = parser.parse_args()

    # Update live cyseqtools metrics
    report = load_and_merge_metrics(
        args.metrics_folder, PREV_METRICS_FOLDER, args.published_folder
    )

    # Save live metric figures
    save_metric_plots(report)

    # Save live card data
    save_metric_cards(report)


if __name__ == "__main__":
    main()
