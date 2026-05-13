#!/usr/bin/env python
import argparse
import json
from pathlib import Path
from typing import Any
import pandas as pd

TAB_PRIORITY = 2
TAB_NAME = "variant-table"

COLUMN_SCHEMA = {
    "Genomic change": {
        "type": "text",
        "filter": "regex",
    },
    "Codon change": {
        "type": "text",
        "filter": "regex",
    },
    "Amino acid change": {
        "type": "text",
        "filter": "regex",
    },
    "VAF (%)": {
        "type": "numeric",
        "source": "AF",
        "scale": 100,
    },
    "Coverage": {
        "type": "numeric",
        "source": "DP",
        "format": "human",
    },
    "Symbol": {
        "type": "dropdown",
    },
    "Type": {
        "type": "dropdown",
    }
}

def human_format(num: Any) -> str:
    try:
        num = float(num)
    except (ValueError, TypeError):
        return str(num)
    magnitude = 0
    while abs(num) >= 1000 and magnitude < 4:
        magnitude += 1
        num /= 1000.0
    suffixes = ["", "K", "M", "B", "T"]
    formatted_num = f"{num:.2f}".rstrip("0").rstrip(".")
    return f"{formatted_num}{suffixes[magnitude]}"

def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def load_vcf(vcf_file: Path) -> pd.DataFrame:
    skip_rows = 0
    with open(vcf_file, "r", encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("##"): skip_rows += 1
            else: break
    return pd.read_csv(vcf_file, sep="\t", skiprows=skip_rows, dtype=str).rename(columns={"#CHROM": "CHROM"})

def _parse_info_field(info: str) -> dict:
    if not isinstance(info, str):
        return {}

    result = {}
    for entry in info.split(";"):
        if "=" in entry:
            k, v = entry.split("=", 1)
            result[k] = v
        else:
            result[entry] = True
    return result

def restructure_annotations(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return pd.DataFrame(columns=list(COLUMN_SCHEMA.keys()))

    info = df["INFO"].apply(_parse_info_field)

    def get(key):
        return info.apply(lambda d: d.get(key))

    out = {}

    # Genomic change (pure string)
    out["Genomic change"] = (
        df["CHROM"] + ":" +
        df["POS"] + ":" +
        df["REF"] + ">" +
        df["ALT"]
    )

    # Text fields
    out["Codon change"] = (
        get("hgvsc")
        .str.split(":", n=1)
        .str[-1]
    )
    out["Amino acid change"] = (
        get("hgvsp")
        .str.split(":", n=1)
        .str[-1]
    )

    # Numeric: VAF
    out["VAF (%)"] = get("AF").apply(to_float).apply(
        lambda x: round(x * 100, 2) if x is not None else None
    )

    # Numeric: Coverage
    out["Coverage"] = get("DP").apply(to_float)

    # Categorical
    out["Symbol"] = get("gene")
    out["Type"] = get("variant_class")

    annotation_df = pd.DataFrame(out)

    annotation_df = annotation_df.replace(
        ["", "None", "nan", "NaN"],
        pd.NA
    )

    return annotation_df

def main(vcf_file: Path, variant_table_file: Path, priority_limit: int) -> None:
    json_obj = {
        TAB_NAME: {
            "name": TAB_NAME,
            "data": [],
            "columns": [],
            "column_types": {},
            "priority": TAB_PRIORITY
        }
    }

    if TAB_PRIORITY < priority_limit:
        raw_df = load_vcf(vcf_file)
        processed_df = restructure_annotations(raw_df)

        json_obj[TAB_NAME]["columns"] = processed_df.columns.tolist()
        json_obj[TAB_NAME]["data"] = processed_df.to_dict(orient="records")

        # NEW: send schema to frontend
        json_obj[TAB_NAME]["column_types"] = COLUMN_SCHEMA

    with open(variant_table_file, "w", encoding="utf-8") as fh:
        json.dump(json_obj, fh, indent=2)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("vcf_file", type=Path)
    parser.add_argument("variant_table_file", type=Path)
    parser.add_argument("--priority-limit", type=int, default=89)
    args = parser.parse_args()
    main(args.vcf_file, args.variant_table_file, args.priority_limit)