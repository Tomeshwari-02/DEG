#!/usr/bin/env bash
# Wrapper around `npx @redocly/cli respect` that runs the arazzo workflows
# either against the local stack (default) or against the public URL exposed
# by the over-internet docker compose + ngrok tunnel.
#
# Usage:
#   ./scripts/run-arazzo.sh                                # usecase1, local
#   ./scripts/run-arazzo.sh usecase2                       # usecase2, local
#   ./scripts/run-arazzo.sh usecase1 -w select-through-status
#
# Over-the-internet mode (matches scripts/test-workflow.sh):
#   PUBLIC_URL=https://your-domain.ngrok-free.dev ./scripts/run-arazzo.sh
#
# When PUBLIC_URL is set, the wrapper materialises a tmpdir with copies of the
# arazzo file and patched example payloads (docker-DNS bapUri/bppUri rewritten
# to the public URL) and runs respect against that, so the source examples on
# disk stay untouched. Server URLs (-S) are also flipped to the public URL.

set -euo pipefail

USECASE="${1:-usecase1}"
shift || true   # allow extra args after the usecase positional
DEVKIT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$DEVKIT_ROOT/$USECASE"

if [ ! -d "$SRC" ]; then
  echo "ERROR: usecase directory not found: $SRC" >&2
  exit 1
fi

RESPECT_ARGS=(--severity 'SCHEMA_CHECK=off' "$@")

if [ -z "${PUBLIC_URL:-}" ]; then
  echo "Mode: local docker (default x-serverUrl)"
  exec npx --yes @redocly/cli respect \
    "$SRC/workflows/data-exchange.arazzo.yaml" \
    "${RESPECT_ARGS[@]}"
fi

PUBLIC_URL="${PUBLIC_URL%/}"
echo "Mode: over-internet via $PUBLIC_URL (payloads patched in tmpdir)"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/data-exchange-arazzo-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/workflows" "$WORK/examples"

# Copy the arazzo file unchanged; $ref paths are relative so they will resolve
# against $WORK/examples once we drop the patched JSONs there.
cp "$SRC/workflows/data-exchange.arazzo.yaml" "$WORK/workflows/"

# Patch each example payload's docker-DNS bapUri/bppUri to the public URL,
# leaving any other URIs (external catalog/discovery endpoints) alone.
PUBLIC_URL="$PUBLIC_URL" python3 - "$SRC/examples" "$WORK/examples" <<'PY'
import json, os, sys, pathlib
src, dst = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
pub = os.environ['PUBLIC_URL']
for f in sorted(src.glob('*.json')):
    d = json.load(open(f))
    ctx = d.get('context', {})
    if ctx.get('bapUri') == 'http://onix-bap:8081/bap/receiver':
        ctx['bapUri'] = pub + '/bap/receiver'
    if ctx.get('bppUri') == 'http://onix-bpp:8082/bpp/receiver':
        ctx['bppUri'] = pub + '/bpp/receiver'
    json.dump(d, open(dst / f.name, 'w'), indent=2)
PY

exec npx --yes @redocly/cli respect \
  "$WORK/workflows/data-exchange.arazzo.yaml" \
  -S "beckn-bap-caller=$PUBLIC_URL/bap/caller" \
  -S "beckn-bpp-caller=$PUBLIC_URL/bpp/caller" \
  "${RESPECT_ARGS[@]}"
