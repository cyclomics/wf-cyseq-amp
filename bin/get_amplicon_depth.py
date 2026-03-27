#!/usr/bin/env python
"""
Takes the output of `samtools depth -a` and a BED file, computes the median
depth per amplicon, and writes a YAML file containing Plotly chart data.
"""

import argparse
import statistics
import yaml
from collections import defaultdict
from pathlib import Path


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
    with open(bed_file) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            amplicons.append({
                "chrom": fields[0],
                "start": int(fields[1]),
                "end": int(fields[2]),
                "name": fields[3],
            })

    return amplicons


def parse_depth(depth_tsv: str, amplicons: list[dict]) -> dict[str, list[int]]:
    """
    Read samtools depth output and bucket per-base depths by amplicon name.
    """
    depths: dict[str, list[int]] = defaultdict(list)

    with open(depth_tsv) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            chrom, pos, depth = line.split("\t")
            pos = int(pos)
            depth = int(depth)

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