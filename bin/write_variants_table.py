#!/usr/bin/env python
"""Flatten a SnpEff-annotated VCF into a variant table (TSV + JSON).

This expects VCF records annotated by SnpEff, where:
  * INFO/ANN carries the functional annotation as pipe-delimited fields,
    with one comma-separated entry per affected transcript. SnpEff orders
    these entries from most to least severe impact, so we keep the first
    entry as the variant's "primary" annotation.
  * VAF and depth live on the sample genotype column (FORMAT/DP,
    FORMAT/VAF) rather than in INFO.

The output schema (variant-table columns) is unchanged from the previous
version of this script, so downstream consumers don't need to change.
"""

import argparse
import json
from pathlib import Path
from typing import Any

import pandas as pd

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
    },
}

# Order of the pipe-delimited subfields inside INFO/ANN. This mirrors the
# ##INFO=<ID=ANN,...> header line SnpEff writes into the VCF, so if the
# annotator's output format ever changes, that header is the place to check.
ANN_FIELDS = [
    "allele",
    "annotation",
    "annotation_impact",
    "gene_name",
    "gene_id",
    "feature_type",
    "feature_id",
    "transcript_biotype",
    "rank",
    "hgvs_c",
    "hgvs_p",
    "cdna_pos_len",
    "cds_pos_len",
    "aa_pos_len",
    "distance",
    "errors_warnings_info",
]


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


def to_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def load_vcf(vcf_file: Path) -> pd.DataFrame:
    skip_rows = 0
    with open(vcf_file, "r", encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("##"):
                skip_rows += 1
            else:
                break
    return pd.read_csv(vcf_file, sep="\t", skiprows=skip_rows, dtype=str).rename(
        columns={"#CHROM": "CHROM"}
    )


def _parse_info_field(info: str) -> dict:
    if not isinstance(info, str):
        return {}

    result = {}
    for entry in info.split(";"):
        key, sep, value = entry.partition("=")
        result[key] = value if sep else True
    return result


def _parse_primary_ann(ann_value: Any) -> dict:
    """Return the primary (first, most severe) SnpEff annotation as a dict.

    A variant can hit several transcripts, each reported as its own
    pipe-delimited entry, comma-separated. We surface only the first entry
    here to keep one row per variant; the full annotation is still in the
    source VCF for anyone who needs every transcript.
    """
    if not isinstance(ann_value, str) or not ann_value:
        return {}

    first_entry = ann_value.split(",", 1)[0]
    return dict(zip(ANN_FIELDS, first_entry.split("|")))


def _get_sample_column(df: pd.DataFrame) -> str:
    """Return the name of the (single) sample genotype column after FORMAT."""
    sample_columns = list(df.columns[df.columns.get_loc("FORMAT") + 1 :])
    if not sample_columns:
        raise ValueError("VCF has a FORMAT column but no sample genotype column")
    if len(sample_columns) > 1:
        raise ValueError(
            "Expected a single-sample VCF, but found multiple sample columns: "
            f"{sample_columns}"
        )
    return sample_columns[0]


def _parse_genotype(format_field: str, sample_field: str) -> dict:
    """Zip a VCF FORMAT column (e.g. 'DP:VAF') with its sample values."""
    if not isinstance(format_field, str) or not isinstance(sample_field, str):
        return {}
    return dict(zip(format_field.split(":"), sample_field.split(":")))


def restructure_annotations(df: pd.DataFrame) -> pd.DataFrame:
    if df.empty:
        return pd.DataFrame(columns=list(COLUMN_SCHEMA.keys()))

    sample_col = _get_sample_column(df)

    ann = (
        df["INFO"]
        .apply(_parse_info_field)
        .apply(lambda d: d.get("ANN", ""))
        .apply(_parse_primary_ann)
    )
    genotype = df.apply(
        lambda row: _parse_genotype(row["FORMAT"], row[sample_col]), axis=1
    )

    out = {}

    # Genomic change (pure string)
    out["Genomic change"] = (
        df["CHROM"] + ":" + df["POS"] + ":" + df["REF"] + ">" + df["ALT"]
    )

    # Text fields, straight off the primary ANN entry
    out["Codon change"] = ann.apply(lambda d: d.get("hgvs_c"))
    out["Amino acid change"] = ann.apply(lambda d: d.get("hgvs_p"))

    # Numeric: VAF is already a fraction on the sample genotype column
    out["VAF (%)"] = genotype.apply(lambda d: to_float(d.get("VAF"))).apply(
        lambda x: round(x * 100, 2) if x is not None else None
    )

    # Numeric: Coverage, also from the sample genotype column
    out["Coverage"] = genotype.apply(lambda d: to_float(d.get("DP")))

    # Categorical
    out["Symbol"] = ann.apply(lambda d: d.get("gene_name"))
    out["Type"] = ann.apply(lambda d: d.get("annotation"))

    annotation_df = pd.DataFrame(out)

    annotation_df = annotation_df.replace(
        ["", "None", "nan", "NaN"],
        pd.NA,
    )

    return annotation_df


def main(vcf_file: Path, variants_tsv: Path, variants_json: Path) -> None:
    json_obj = {
        TAB_NAME: {
            "name": TAB_NAME,
            "data": [],
            "columns": [],
            "column_types": {},
        }
    }

    raw_df = load_vcf(vcf_file)
    processed_df = restructure_annotations(raw_df)

    with open(variants_tsv, "w", encoding="utf-8") as fh:
        processed_df.to_csv(fh, sep="\t", index=False)

    json_obj[TAB_NAME]["columns"] = processed_df.columns.tolist()

    json_df = processed_df.astype(object).where(
        pd.notna(processed_df),
        None,
    )

    json_obj[TAB_NAME]["data"] = json_df.to_dict(orient="records")
    json_obj[TAB_NAME]["column_types"] = COLUMN_SCHEMA

    with open(variants_json, "w", encoding="utf-8") as fh:
        json.dump(json_obj, fh, indent=2, allow_nan=False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("vcf_file", type=Path)
    parser.add_argument("variants_tsv", type=Path)
    parser.add_argument("variants_json", type=Path)
    args = parser.parse_args()
    main(args.vcf_file, args.variants_tsv, args.variants_json)
