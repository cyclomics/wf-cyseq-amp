#!/usr/bin/env python
"""VCF file annotation using Ensembl-VEP API and COSMIC mutation IDs."""

import argparse
import json
import logging
from dataclasses import dataclass, fields
from io import StringIO
from pathlib import Path
from typing import Any, Optional, Tuple

import pandas as pd
import requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


ENSEMBL_SERVER = "https://rest.ensembl.org"
COSMIC_API_URL = "https://clinicaltables.nlm.nih.gov/api/cosmic/v4/search?terms="
VEP_PARAMS = "canonical=1&variant_class=1&hgvs=1&vcf_string=1&pick=1"


# COSMIC helper
def obtain_legacy_cosmic_id(
    cosv_id: str,
    base_url: str = COSMIC_API_URL,
) -> str:
    """Retrieve the legacy COSMIC mutation ID for a given COSV identifier.

    Args:
        cosv_id: A COSMIC variant ID (e.g. ``"COSV12345"``).
        base_url: Base URL of the NLM Clinical Tables COSMIC search API.

    Returns:
        A comma-separated string of legacy COSM IDs, or ``"None"`` when no
        match is found or the request fails.
    """
    query = base_url + cosv_id + "&ef=LegacyMutationID"
    try:
        response = requests.get(url=query, headers={"Content-Type": "application/json"})
    except requests.exceptions.ConnectionError:
        return "None"

    try:
        id_list = set(json.loads(response.text)[2]["LegacyMutationID"])
    except KeyError:
        return "None"

    legacy_ids = [id_ for id_ in id_list if "COSM" in id_]
    return ",".join(legacy_ids)


@dataclass
class VariantAnnotation:
    """Structured representation of a single variant's VEP annotation.

    Attributes:
        variant_class: Sequence ontology variant class (e.g. ``"SNV"``).
        consequence: Most severe VEP consequence term.
        cosmic: Comma-separated COSV identifiers, or ``"None"``.
        cosmic_legacy: Comma-separated legacy COSM identifiers, or ``"None"``.
        gene: HGNC gene symbol.
        impact: Predicted impact (``"HIGH"``, ``"MODERATE"``, etc.).
        biotype: Ensembl transcript biotype.
        amino_acids: Amino-acid change string.
        canonical: ``1`` if the transcript is canonical, else ``None``.
        sift: SIFT prediction and score, e.g. ``"deleterious(0.01)"``.
        polyphen: PolyPhen prediction and score.
        hgvsc: HGVS codon change.
        hgvsp: HGVS amino acid change.
    """

    variant_class: Optional[str] = None
    consequence: Optional[str] = None
    cosmic: str = "None"
    cosmic_legacy: str = "None"
    gene: Optional[str] = None
    impact: Optional[str] = None
    biotype: Optional[str] = None
    amino_acids: Optional[str] = None
    canonical: Optional[str] = None
    sift: Optional[str] = None
    polyphen: Optional[str] = None
    hgvsc: Optional[str] = None
    hgvsp: Optional[str] = None

    # VEP response parsing helpers
    @staticmethod
    def _extract_cosmic_ids(vep_json: dict) -> Tuple[str, str]:
        """Extract COSMIC and legacy COSMIC IDs from a VEP response.

        Args:
            vep_json: Parsed VEP JSON response dict.

        Returns:
            A two-tuple ``(cosmic_ids, cosmic_legacy_ids)``, each a
            comma-separated string, or ``"None"`` if nothing was found.
        """
        colocated = vep_json.get("colocated_variants") or []
        ids: list[str] = []
        legacy: list[str] = []

        for xref in colocated:
            if xref.get("allele_string") == "COSMIC_MUTATION" and (
                cosv := xref.get("id")
            ):
                ids.append(cosv)
                legacy.append(obtain_legacy_cosmic_id(cosv))

        return (",".join(ids) or "None"), (",".join(legacy) or "None")

    @staticmethod
    def _extract_transcript_fields(vep_json: dict) -> dict:
        """Extract gene and consequence fields from the first transcript consequence.

        Args:
            vep_json: Parsed VEP JSON response dict.

        Returns:
            A dict of transcript consequence fields, with ``None`` for any
            fields not present in the response.
        """
        tc = (vep_json.get("transcript_consequences") or [{}])[0]

        sift_pred = tc.get("sift_prediction")
        pp_pred = tc.get("polyphen_prediction")

        return {
            "gene": tc.get("gene_symbol"),
            "impact": tc.get("impact"),
            "biotype": tc.get("biotype"),
            "amino_acids": tc.get("amino_acids"),
            "canonical": tc.get("canonical"),
            "sift": f"{sift_pred}({tc.get('sift_score')})" if sift_pred else None,
            "polyphen": f"{pp_pred}({tc.get('polyphen_score')})" if pp_pred else None,
            "hgvsc": tc.get("hgvsc"),
            "hgvsp": tc.get("hgvsp"),
        }

    @classmethod
    def from_vep_json(cls, vep_json: Optional[dict]) -> "VariantAnnotation":
        """Construct a :class:`VariantAnnotation` from a VEP response dict.

        Args:
            vep_json: Parsed VEP JSON response, or ``None`` if the query
                returned no data.

        Returns:
            A populated :class:`VariantAnnotation` instance, or a
            default (all-``None``) instance when *vep_json* is falsy.
        """
        if not vep_json:
            return cls()

        cosmic, cosmic_legacy = cls._extract_cosmic_ids(vep_json)
        transcript = cls._extract_transcript_fields(vep_json)

        return cls(
            variant_class=vep_json.get("variant_class"),
            consequence=vep_json.get("most_severe_consequence"),
            cosmic=cosmic,
            cosmic_legacy=cosmic_legacy,
            **transcript,
        )

    def to_info_string(self) -> str:
        """Serialise the annotation to a VCF INFO-compatible string.

        Returns:
            A semicolon-delimited string,
            or ``"."`` when all fields are ``None`` / default.
        """
        if all(
            getattr(self, f.name) is None or getattr(self, f.name) == "None"
            for f in fields(self)
        ):
            return "."

        return ";".join(f"{f.name}={getattr(self, f.name)}" for f in fields(self))


class VCFFile:
    """Read, annotate, and write VCF files.

    Attributes:
        vcf_file: Path to the input VCF file.
        vcf_header: Raw ``##`` meta-information lines preserved from the input.
        vcf: DataFrame representation of the VCF records.
    """

    CORE_COLUMNS = [
        "CHROM",
        "POS",
        "ID",
        "REF",
        "ALT",
        "QUAL",
        "FILTER",
        "INFO",
        "FORMAT",
        "SAMPLE1",
    ]

    def __init__(self, vcf_file: Path) -> None:
        self.vcf_file = vcf_file
        self.vcf_header: list[str] = []
        self.vcf: pd.DataFrame = self._read_vcf(vcf_file)

    # Private helpers
    @staticmethod
    def _relaxed_float(value: Any) -> float:
        """Convert *value* to float, returning ``0.0`` on failure.

        Args:
            value: Any value to convert.

        Returns:
            Float representation of *value*, or ``0.0`` if conversion fails.
        """
        try:
            return float(value)
        except ValueError:
            return 0.0

    def _read_vcf(self, path: Path) -> pd.DataFrame:
        """Parse a VCF file into a :class:`pandas.DataFrame`.

        Meta-information lines (starting with ``##``) are stored in
        :attr:`vcf_header`; the column header and data lines are parsed into
        a DataFrame with FORMAT fields expanded into individual columns.

        Args:
            path: Path to the VCF file.

        Returns:
            DataFrame of VCF records with FORMAT fields as extra columns.
        """
        header: list[str] = []
        lines: list[str] = []

        with open(path, "r") as fh:
            for line in fh:
                if line.startswith("##"):
                    header.append(line)
                elif line.startswith("#"):
                    continue
                else:
                    lines.append(line)

        self.vcf_header = header

        df = pd.read_csv(
            StringIO("".join(lines)),
            sep="\t",
            names=self.CORE_COLUMNS,
        )

        if df.empty:
            return df

        # for i, fmt in enumerate(df["FORMAT"].iloc[0].split(":")):
        #     df[fmt] = (
        #         df["SAMPLE1"]
        #         .str.split(":")
        #         .str[i]
        #         .apply(pd.to_numeric, errors="coerce")
        #         .fillna(0)
        #     )

        return df

    def write(self, path: Path) -> None:
        """Write the (annotated) VCF to *path*, preserving the original header.

        Args:
            path: Destination file path.
        """
        writeable_vcf = self.vcf.rename(columns={"CHROM": "#CHROM"})

        with open(path, "w", encoding="utf-8") as fh:
            fh.writelines(self.vcf_header)
            fh.writelines(writeable_vcf.to_csv(sep="\t", index=False))

    # VEP annotation
    @staticmethod
    def _get_query_allele_positions(
        ref_allele: str, alt_allele: str, start: int
    ) -> Tuple[int, int, str, str]:
        """Compute Ensembl-VEP query coordinates from VCF allele strings.

        Indels require index adjustments and allele placeholders so that
        the Ensembl REST API interprets them correctly.

        Args:
            ref_allele: Reference allele string from the VCF.
            alt_allele: Alternate allele string from the VCF.
            start: 1-based start position from the VCF POS column.

        Returns:
            A four-tuple ``(start, end, ref_allele, alt_allele)`` adjusted
            for Ensembl-VEP conventions.
        """
        if len(ref_allele) > len(alt_allele):
            # Deletion: strip the anchor base shared by REF and ALT.
            end = start + len(ref_allele) - 1
            start += 1
            alt_allele = "-"
        elif len(ref_allele) < len(alt_allele):
            # Insertion: strip the anchor base shared by REF and ALT.
            end = start
            start += 1
            ref_allele = "-"
        else:
            end = start

        # Ensembl-VEP expects the strand indicator (forward = "1") as REF.
        ref_allele = "1"

        return start, end, ref_allele, alt_allele

    @staticmethod
    def _query_ensembl_vep(query: str) -> Optional[dict]:
        """Call the Ensembl-VEP REST endpoint and return the first result.

        Args:
            query: Full URL for the VEP region endpoint.

        Returns:
            Parsed JSON dict for the first result, or ``None`` on failure.
        """
        try:
            response = requests.get(
                url=query, headers={"Content-Type": "application/json"}
            )
            return json.loads(response.text)[0]
        except (KeyError, ConnectionError, json.decoder.JSONDecodeError) as exc:
            logger.warning("Ensembl-VEP query failed: %s", exc)
            return None

    def annotate_vep(self, server: str = ENSEMBL_SERVER) -> None:
        """Annotate all variants in :attr:`vcf` using the Ensembl-VEP REST API.

        Variants are queried sequentially to respect the Ensembl rate limit
        (15 requests/second for anonymous users). Results are written back
        to the ``INFO`` column of :attr:`vcf`.

        Args:
            server: Base URL of the Ensembl REST server.
        """
        if self.vcf.empty:
            return

        annotations: list[str] = []

        for _, row in self.vcf.iterrows():
            start, end, ref, alt = self._get_query_allele_positions(
                ref_allele=row["REF"],
                alt_allele=row["ALT"],
                start=row["POS"],
            )
            query = (
                f"{server}/vep/human/region/"
                f"{row['CHROM']}:{start}-{end}:{ref}/{alt}?"
                f"{VEP_PARAMS}?"
            )

            vep_json = self._query_ensembl_vep(query)
            annotation = VariantAnnotation.from_vep_json(vep_json)
            annotations.append(";".join([row["INFO"], annotation.to_info_string()]))

        self.vcf["INFO"] = annotations


def main():
    parser = argparse.ArgumentParser(
        description="Annotate a VCF file with Ensembl-VEP and COSMIC IDs."
    )
    parser.add_argument("variant_vcf", type=Path, help="Input VCF file path.")
    parser.add_argument("file_out", type=Path, help="Output VCF file path.")
    args = parser.parse_args()

    vcf = VCFFile(args.variant_vcf)
    vcf.annotate_vep()
    vcf.write(args.file_out)


if __name__ == "__main__":
    main()
