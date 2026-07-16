#!/usr/bin/env bash
# Set up grok build to run against Nebius Token Factory (no xAI subscription).
# - Installs config.toml to ~/.grok/config.toml (backing up any existing one)
# - Verifies NEBIUS_API_KEY / TAVILY_API_KEY are set
# - Smoke-tests the Nebius endpoint and the grok model catalog
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
grok_dir="$HOME/.grok"
config="$grok_dir/config.toml"

echo "==> Checking API keys"
missing=0
if [ -z "${NEBIUS_API_KEY:-}" ]; then
  echo "  NEBIUS_API_KEY is not set (get one at https://tokenfactory.nebius.com)"
  missing=1
fi
if [ -z "${TAVILY_API_KEY:-}" ]; then
  echo "  TAVILY_API_KEY is not set (get one at https://app.tavily.com) — web search won't work without it"
fi
if [ "$missing" = 1 ]; then
  echo "  Add the exports from env.example to your shell rc, reload, and re-run."
  exit 1
fi

echo "==> Installing config to $config"
mkdir -p "$grok_dir"
if [ -f "$config" ]; then
  backup="$config.bak.$(date +%Y%m%d%H%M%S)"
  cp "$config" "$backup"
  echo "  Existing config backed up to $backup"
  # Preserve a local installer marker if present (set by the grok installer)
  if grep -q '^installer' "$backup" && ! grep -q '^installer' "$here/config.toml"; then
    echo "  NOTE: your old config had an [cli] installer entry; re-add it manually if needed."
  fi
fi
cp "$here/config.toml" "$config"

echo "==> Verifying Nebius endpoint"
if ! curl -sf https://api.tokenfactory.nebius.com/v1/models \
    -H "Authorization: Bearer $NEBIUS_API_KEY" >/dev/null; then
  echo "  ERROR: could not list models — check NEBIUS_API_KEY"
  exit 1
fi
echo "  Nebius API reachable, key valid."

if command -v grok >/dev/null 2>&1; then
  echo "==> grok model catalog:"
  grok models || true
  echo
  echo "Done. Try:  grok -p \"What is 2+2?\" -m kimi-k2.7-code"
  echo "Then launch the TUI with:  grok   (no login screen should appear)"
else
  echo "grok binary not found on PATH — install it first:"
  echo "  curl -fsSL https://x.ai/cli/install.sh | bash"
fi
