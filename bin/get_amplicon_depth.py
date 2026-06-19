#!/usr/bin/env python
"""
Takes the output of `samtools depth -a` and a BED file, computes the median
depth per amplicon, and writes a YAML file containing Plotly chart data.
"""

import argparse
import statistics
from collections import defaultdict
from pathlib import Path

import yaml


def parse_bed(bed_file: str) -> list[dict]:
    """
    Parse BED file, returning list of amplicon regions.
    Assumes following data in column indexes:
        0: chromosome name
        1: start (0-based, exclusive)
        2: end (0-based, inclusive)
        3: amplicon name
    """
    amplicons = []

    with open(bed_file, encoding="utf-8") as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()

            if not line or line.startswith("#"):
                continue

            fields = line.split()

            if len(fields) < 3:
                raise ValueError(
                    f"Invalid BED line {lineno}: expected at least 3 columns, got {len(fields)}: {line!r}"
                )

            amplicons.append(
                {
                    "chrom": fields[0],
                    "start": int(fields[1]),
                    "end": int(fields[2]),
                    "name": fields[3] if len(fields) > 3 else f"amplicon_{lineno}",
                }
            )

    return amplicons


def parse_depth(
    depth_tsv: str,
    amplicons: list[dict],
) -> dict[str, list[int]]:
    """
    Read samtools depth output and bucket per-base depths by amplicon name.

    Expected format:
        chrom <whitespace> pos <whitespace> depth
    """
    depths: dict[str, list[int]] = defaultdict(list)

    with open(depth_tsv) as f:
        for lineno, line in enumerate(f, start=1):
            line = line.strip()

            if not line:
                continue

            fields = line.split()

            if len(fields) != 3:
                raise ValueError(
                    f"Invalid depth line {lineno}: "
                    f"expected 3 columns, got {len(fields)}: {line!r}"
                )

            chrom, pos_str, depth_str = fields

            try:
                pos = int(pos_str)
                depth = int(depth_str)
            except ValueError as e:
                raise ValueError(
                    f"Invalid depth line {lineno}: "
                    f"position and depth must be integers: {line!r}"
                ) from e

            for amp in amplicons:
                if chrom == amp["chrom"] and amp["start"] < pos <= amp["end"]:
                    depths[amp["name"]].append(depth)
                    break

    return depths


def compute_medians(depths: dict[str, list[int]]) -> tuple[list[str], list[float]]:
    """Compute median depth per amplicon, preserving BED order."""
    amplicon_names = list(depths.keys())
    median_depths = [
        statistics.median(depths[name]) if depths[name] else 0.0
        for name in amplicon_names
    ]
    
    return amplicon_names, median_depths


def build_plot_values_yaml(amplicon_names: list[str], median_depths: list[float]) -> dict:
    return {
        "data": {
            "x": amplicon_names,
            "y": median_depths,
        },
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("depth_tsv", help="Output of samtools depth -a")
    parser.add_argument("amplicon_bed", help="BED file with amplicon regions")
    parser.add_argument("output_yml", help="Output YAML file")
    args = parser.parse_args()

    output_path = args.output_yml
    amplicons = parse_bed(args.amplicon_bed)
    depths = parse_depth(args.depth_tsv, amplicons)
    amplicon_names, median_depths = compute_medians(depths)
    chart = build_plot_values_yaml(amplicon_names, median_depths)

    with open(output_path, "w") as f:
        yaml.dump(chart, f, default_flow_style=False, sort_keys=False)

if __name__ == "__main__":
    main()