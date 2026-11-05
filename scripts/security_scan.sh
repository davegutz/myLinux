#!/usr/bin/env bash
# scripts/security_scan.sh - Entrypoint wrapper for sys-security-scan
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "$DIR/common/.local/bin/sys-security-scan" "$@"
