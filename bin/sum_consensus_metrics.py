#!/usr/bin/env python
"""
Accumulates consensus metrics across file_ids into a running metrics folder.

This script loads metrics from a new folder, merges them with any previously
accumulated metrics, and writes the updated metrics back to the output folder.

Uses the cyseqcon.metrics Report API to handle aggregation automatically.
"""

import os
import shutil
import argparse
from pathlib import Path
from cyseqtools.consensus.metrics.report import Report

OUTPUT_FOLDER = Path("consensus_metrics")
PREV_METRICS_FOLDER = Path("prev_metrics")

def write_folder_atomic(src_folder: Path, dst_folder: Path) -> None:
    """
    Atomically replace a folder with a new folder.
    """

    tmp_folder = Path(str(dst_folder) + ".tmp")

    # Clean temp if exists
    if tmp_folder.exists():
        shutil.rmtree(tmp_folder)

    # Copy new content into temp
    shutil.copytree(src_folder, tmp_folder)

    # Atomic swap
    os.replace(tmp_folder, dst_folder)

def load_and_merge_metrics(new_metrics_folder: Path, prev_metrics_folder: Path, output_folder: Path) -> None:
    """
    Load new metrics, merge with existing published metrics if present,
    and save the aggregated result.
    """
    print("=== DEBUG: load_and_merge_metrics ===")
    print(f"new_metrics_folder: {new_metrics_folder}  exists={new_metrics_folder.exists()}")
    print(f"prev_metrics_folder:   {prev_metrics_folder}    exists={prev_metrics_folder.exists()}")
    if prev_metrics_folder.exists():
        print("prev_metrics_folder contents:")
        for p in Path(prev_metrics_folder).iterdir():
            print("   -", p)
    else:
        print("prev_metrics_folder does not exist")

    print("======================================")

    report = Report()

    # Load existing accumulated metrics if they exist
    if prev_metrics_folder.exists() and any(Path(prev_metrics_folder).iterdir()):
        print("DEBUG: Loading existing metrics from prev_metrics_folder")
        report.load_from_path(prev_metrics_folder)
        print("DEBUG: Finished loading existing metrics")
    else:
        print("DEBUG: No existing metrics to load")


    # Merge new metrics
    print("DEBUG: Loading new metrics from new_metrics_folder")
    report.load_from_path(new_metrics_folder)
    print("DEBUG: Finished loading new metrics")

    # Write merged metrics to work folder
    if not output_folder.exists():
        output_folder.mkdir(parents=True, exist_ok=True)

    print(f"DEBUG: Writing merged metrics to output_folder={output_folder}")
    report.save(output_folder)

    print("DEBUG: Contents of output_folder after save:")
    for p in output_folder.iterdir():
        print("   -", p)

    # Atomically push merged metrics to published folder
    # print(f"DEBUG: Atomic replace: {output_folder} -> {prev_metrics_folder}")
    # write_folder_atomic(output_folder, prev_metrics_folder)
    # print("DEBUG: Atomic replace completed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--metrics_folder",
        type=Path,
        required=True,
        help="Folder containing new metrics YML files from this file_id"
    )
    parser.add_argument(
        "--published_folder",
        type=Path,
        required=True,
        default=None,
        help="Folder containing previously accumulated metrics (if any)"
    )

    args = parser.parse_args()

    load_and_merge_metrics(args.metrics_folder, PREV_METRICS_FOLDER, args.published_folder)


if __name__ == "__main__":
    main()