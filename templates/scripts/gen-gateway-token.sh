#!/usr/bin/env bash
# Generates a random 256-bit Gateway token (64 hex chars) and prints the export line.
# Usage:  ./gen-gateway-token.sh            -> prints export line
#         ./gen-gateway-token.sh >> ~/.openclaw/.env   (then chmod 600 ~/.openclaw/.env)
set -euo pipefail
if command -v openssl >/dev/null 2>&1; then
  tok="$(openssl rand -hex 32)"
else
  tok="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
fi
printf 'OPENCLAW_GATEWAY_TOKEN=%s\n' "$tok"
