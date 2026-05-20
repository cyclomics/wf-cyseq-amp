#!/usr/bin/env bash

set -euo pipefail

# Usage check
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <input.bam> <regions.bed> <output.yaml>" >&2
    exit 1
fi

bam="$1"
bed="$2"
yaml_out="$3"

# Count mapped primary alignments
# Secondary: 0x100, Supplementary: 0x800, Unmapped: 0x4
# NB: For all alignments, do 0x900 instead of 0x904
total=$(samtools view -c -F 0x904 "$bam")
on_target=$(samtools view -c -F 0x904 -L "$bed" "$bam")
off_target=$(( total - on_target ))

# Calculate on-target rate
if [[ "$total" -gt 0 ]]; then
    on_target_rate=$(awk -v on="$on_target" -v tot="$total" \
        'BEGIN { printf "%.1f", 100 * on / tot }')
else
    on_target_rate=0.0
fi

on_target_rate=

cat > "$yaml_out" <<EOF
total_reads: $total
on_target_reads: $on_target
off_target_reads: $off_target
cards:
  on_target_rate: $on_target_rate
EOF
