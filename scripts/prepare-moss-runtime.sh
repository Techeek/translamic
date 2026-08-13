#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME_DIR="$ROOT_DIR/Sources/TranslaMicApp/Resources/MossTTS"
UV_PATH="$RUNTIME_DIR/uv"
UV_VERSION="0.11.7"
UV_SHA256="66e37d91f839e12481d7b932a1eccbfe732560f42c1cfb89faddfa2454534ba8"

if [[ -x "$UV_PATH" ]]; then
  exit 0
fi

ARCHIVE="$(mktemp "${TMPDIR:-/tmp}/translamic-uv.XXXXXX.tar.gz")"
EXTRACTED="$(mktemp -d "${TMPDIR:-/tmp}/translamic-uv.XXXXXX")"
trap 'rm -f "$ARCHIVE"; rm -rf "$EXTRACTED"' EXIT

curl -fL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-aarch64-apple-darwin.tar.gz" -o "$ARCHIVE"
ACTUAL_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
if [[ "$ACTUAL_SHA256" != "$UV_SHA256" ]]; then
  printf 'error: uv checksum mismatch\n' >&2
  exit 1
fi

tar -xzf "$ARCHIVE" -C "$EXTRACTED"
cp "$EXTRACTED/uv-aarch64-apple-darwin/uv" "$UV_PATH"
chmod 755 "$UV_PATH"
