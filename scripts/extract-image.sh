#!/usr/bin/env bash

set -e

OUTPUT_FILE="${1:-images.txt}"

kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].image}' \
  | tr ' ' '\n' \
  | sort -u \
  > "$OUTPUT_FILE"

echo "Extracted images written to $OUTPUT_FILE"