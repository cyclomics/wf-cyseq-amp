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
from pathlib import Path
import base64
import numpy as np

def load_all_yamls(folder: str) -> list[dict]:
    """Load all YAML files in a folder."""
    plots = []

    for yml_file in sorted(Path(folder).glob("*.y*ml")):
        with open(yml_file, encoding='utf-8') as f:
            data = yaml.safe_load(f) or {}

        data["_source"] = yml_file.name
        plots.append(data)

    return plots


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
    data_list = plot.get("data", [])
    if isinstance(data_list, dict):
        data_list = [data_list]
        
    for trace in data_list:
        for axis in ['x', 'y']:
            if isinstance(trace.get(axis), dict) and 'bdata' in trace[axis]:
                # Decode base64 to numpy array, then to a standard Python list
                binary_data = base64.b64decode(trace[axis]['bdata'])
                trace[axis] = np.frombuffer(binary_data, dtype=trace[axis]['dtype']).tolist()
    
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
        lambda _: f'<script id="embedded-data" type="application/json">{json_data}</script>',
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

    handlers = {
        "Raw reads": {
            "card": derive_card,
            "plot": normalise_plot,
        }
    }

    all_plots = load_all_yamls(".")

    cards = []
    plots = []

    for plot in all_plots:
        plot_name = plot.get("name")
        handler = handlers.get(plot_name) if isinstance(plot_name, str) else None

        if handler:
            cards.append(handler["card"](plot))
            plots.append(handler["plot"](plot))
            continue

        plots.append(normalise_plot(plot))

    report_data = build_report_data(cards, plots)
    if args.sample_id:
        report_data["sample_id"] = args.sample_id

    with open(args.output_json, "w", encoding='utf-8') as f:
        json.dump(report_data, f, indent=2)

    inject_into_html(args.template, report_data, args.output_html)


if __name__ == "__main__":
    main()