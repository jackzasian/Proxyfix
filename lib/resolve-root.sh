#!/usr/bin/env bash
# Resolve real script directory even when invoked via symlink (~/.local/bin/proxyfix).
proxyfix_resolve_root() {
  local src=${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}
  while [[ -L $src ]]; do
    local dir
    dir=$(cd "$(dirname "$src")" && pwd)
    src=$(readlink "$src")
    [[ $src != /* ]] && src="${dir}/${src}"
  done
  cd "$(dirname "$src")" && pwd
}
