#!/usr/bin/env bash
#
# Usage:
#   ./tag_filter_vcf.sh -v <input.vcf[.gz]> -f <reference.fai> -o <out.vcf> \
#       [-a <target.vcf[.gz]>] [-r <reject.vcf[.gz]>]
#
#   -v  input VCF (plain or bgzip)            [required]
#   -f  reference .fai (adds ##contig lines)  [required]
#   -o  output (plain) VCF path               [required]
#   -a  VCF "A": matching variants tagged TARGET, all kept   [optional]
#   -r  VCF "B": matching variants tagged REJECT, then dropped [optional]
#
# Tags are added as INFO flags (INFO/TARGET, INFO/REJECT), which is what
# `bcftools annotate -m` produces. REJECT-matched variants are then removed.
#
# Examples:
#   ./tag_filter_vcf.sh -v sample.vcf -f ref.fa.fai -o sample.tagged.vcf
#   ./tag_filter_vcf.sh -v sample.vcf -f ref.fa.fai -a targets.vcf.gz -o out.vcf
#   ./tag_filter_vcf.sh -v sample.vcf -f ref.fa.fai -a A.vcf -r B.vcf -o out.vcf

set -euo pipefail

VCF=""
FAI=""
OUT=""
TARGET_VCF=""
REJECT_VCF=""

while getopts "v:f:o:a:r:h" opt; do
    case "$opt" in
        v) VCF="$OPTARG" ;;
        f) FAI="$OPTARG" ;;
        o) OUT="$OPTARG" ;;
        a) TARGET_VCF="$OPTARG" ;;
        r) REJECT_VCF="$OPTARG" ;;
        h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Invalid option. Use -h for help." >&2; exit 2 ;;
    esac
done

[ -n "$VCF" ] || { echo "ERROR: -v <input.vcf> is required" >&2; exit 2; }
[ -n "$FAI" ] || { echo "ERROR: -f <reference.fai> is required" >&2; exit 2; }
[ -n "$OUT" ] || { echo "ERROR: -o <out.vcf> is required" >&2; exit 2; }

for f in "$VCF" "$FAI" ${TARGET_VCF:+"$TARGET_VCF"} ${REJECT_VCF:+"$REJECT_VCF"}; do
    [ -e "$f" ] || { echo "ERROR: file not found: $f" >&2; exit 2; }
done

# Work in a scratch dir so we don't clobber inputs; clean up on exit
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "[info] bcftools: $(bcftools --version | head -n1)"
echo "[info] scratch dir: $WORKDIR"

CUR="$WORKDIR/cur.vcf.gz"

# reheader writes to STDOUT in the INPUT's format
prep() {
    # $1 = input vcf(.gz), $2 = output bgzip path
    bcftools reheader --fai "$FAI" "$1" \
        | bcftools sort -Oz -o "$2"
    bcftools index -f -t "$2"
}

echo "[step] normalising input (reheader + sort + bgzip + index)"
prep "$VCF" "$CUR"

# VCF "A": tag matching variants TARGET
if [ -n "$TARGET_VCF" ]; then
    echo "[step] tagging TARGET from: $TARGET_VCF"
    prep "$TARGET_VCF" "$WORKDIR/target.vcf.gz"
    bcftools annotate \
        -a "$WORKDIR/target.vcf.gz" \
        -m TARGET \
        -c CHROM,POS,REF,ALT \
        "$CUR" -Oz -o "$WORKDIR/next.vcf.gz"
    mv "$WORKDIR/next.vcf.gz" "$CUR"
    bcftools index -f -t "$CUR"
else
    echo "[skip] no TARGET VCF provided"
fi

# VCF "B": tag matching variants REJECT, then drop them
if [ -n "$REJECT_VCF" ]; then
    echo "[step] tagging REJECT from: $REJECT_VCF (then dropping matches)"
    prep "$REJECT_VCF" "$WORKDIR/reject.vcf.gz"
    bcftools annotate \
        -a "$WORKDIR/reject.vcf.gz" \
        -m REJECT \
        -c CHROM,POS,REF,ALT \
        "$CUR" -Oz -o "$WORKDIR/tagged.vcf.gz"
    bcftools index -f -t "$WORKDIR/tagged.vcf.gz"
    bcftools view \
        -e 'INFO/REJECT=1' \
        "$WORKDIR/tagged.vcf.gz" -Oz -o "$WORKDIR/next.vcf.gz"
    mv "$WORKDIR/next.vcf.gz" "$CUR"
    bcftools index -f -t "$CUR"
else
    echo "[skip] no REJECT VCF provided"
fi

echo "[step] writing plain VCF to: $OUT"
bcftools view "$CUR" -o "$OUT"

echo "[done] wrote $OUT"
echo "[info] variant count: $(grep -vc '^#' "$OUT")"
echo "[info] TARGET-tagged: $(grep -v '^#' "$OUT" | grep -c 'TARGET' || true)"
echo "[info] REJECT-tagged remaining (should be 0): $(grep -v '^#' "$OUT" | grep -c 'REJECT' || true)"