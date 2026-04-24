#!/usr/bin/env python
import argparse
import json
from pathlib import Path
from typing import Any
import pandas as pd

TAB_PRIORITY = 2
TAB_NAME = "variant-table"

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

def load_vcf(vcf_file: Path) -> pd.DataFrame:
    skip_rows = 0
    with open(vcf_file, "r", encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("##"): skip_rows += 1
            else: break
    return pd.read_csv(vcf_file, sep="\t", skiprows=skip_rows, dtype=str).rename(columns={"#CHROM": "CHROM"})

def _parse_info_field(info: str) -> dict:
    if pd.isna(info): return {}
    result = {}
    for entry in info.split(";"):
        if "=" in entry:
            k, v = entry.split("=", maxsplit=1)
            result[k] = v
        else:
            result[entry] = ""
    return result

def restructure_annotations(variants_df: pd.DataFrame) -> pd.DataFrame:
    if variants_df.empty:
        return pd.DataFrame(columns=["Genomic change", "Codon change", "Amino acid change", "VAF (%)", "Coverage", "Symbol", "Type"])

    parsed_info = variants_df["INFO"].apply(_parse_info_field)

    def get_field(key: str):
        return parsed_info.apply(lambda d: d.get(key, "N/A"))

    annotation_df = pd.DataFrame({
        "Genomic change": variants_df["CHROM"] + ":" + variants_df["POS"] + ":" + variants_df["REF"] + ">" + variants_df["ALT"],
        "Codon change": get_field("hgvsc"),
        "Amino acid change": get_field("hgvsp"),
        "VAF (%)": get_field("AF").apply(lambda x: f"{float(x)*100:.2f}%" if x != "N/A" else "N/A"),
        "Coverage": get_field("DP").apply(human_format),
        "Symbol": get_field("gene"),
        "Type": get_field("variant_class"),
    })
    return annotation_df.replace(["None", "nan", ""], "N/A")

def main(vcf_file: Path, variant_table_file: Path, priority_limit: int) -> None:
    json_obj = {TAB_NAME: {"name": TAB_NAME, "data": [], "priority": TAB_PRIORITY}}

    if TAB_PRIORITY < priority_limit:
        raw_df = load_vcf(vcf_file)
        processed_df = restructure_annotations(raw_df)
        
        json_obj[TAB_NAME]["columns"] = processed_df.columns.tolist()
        json_obj[TAB_NAME]["data"] = processed_df.to_dict(orient='records')

    else:
        json_obj[TAB_NAME]["columns"] = []
        json_obj[TAB_NAME]["data"] = []

    with open(variant_table_file, "w", encoding="utf-8") as fh:
        json.dump(json_obj, fh, indent=2)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("vcf_file", type=Path)
    parser.add_argument("variant_table_file", type=Path)
    parser.add_argument("--priority-limit", type=int, default=89)
    args = parser.parse_args()
    main(args.vcf_file, args.variant_table_file, args.priority_limit)