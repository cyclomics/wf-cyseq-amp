#!/usr/bin/env bash

set -euo pipefail

# Usage check
if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <new_metrics.yaml> <existing_metrics.yaml> <output.yaml>" >&2
    exit 1
fi

new_yaml="$1"
published_yaml="$2"
output_yaml="$3"

# Read new values
new_total=$(awk '/total_reads:/ {print $2}' "$new_yaml")
new_on=$(awk '/on_target_reads:/ {print $2}' "$new_yaml")
new_off=$(awk '/off_target_reads:/ {print $2}' "$new_yaml")

# Read existing values if file exists
if [[ -f "$published_yaml" ]]; then
    old_total=$(awk '/total_reads:/ {print $2}' "$published_yaml")
    old_on=$(awk '/on_target_reads:/ {print $2}' "$published_yaml")
    old_off=$(awk '/off_target_reads:/ {print $2}' "$published_yaml")
else
    old_total=0
    old_on=0
    old_off=0
fi

# Accumulate counts
total_reads=$(( old_total + new_total ))
on_target_reads=$(( old_on + new_on ))
off_target_reads=$(( old_off + new_off ))

# Recompute rate
if [[ "$total_reads" -gt 0 ]]; then
    on_target_rate=$(awk \
        -v on="$on_target_reads" \
        -v tot="$total_reads" \
        'BEGIN { printf "%.1f", 100 * on / tot }')
else
    on_target_rate="0.0"
fi

# Write YAML
rm -f "$published_yaml"
cat > "$output_yaml" <<EOF
total_reads: $total_reads
on_target_reads: $on_target_reads
off_target_reads: $off_target_reads
cards:
  on_target_rate: $on_target_rate
EOF