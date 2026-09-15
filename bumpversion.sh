#!/usr/bin/env bash
# Called by semantic-release (@semantic-release/exec prepareCmd) BEFORE the
# release commit. Pins EVERY `amine2233/kotlin-ci-shared/...@<ref>` in
# examples/, README.md and docs/ to the new version, so copy-paste snippets
# always reference the release (handles @main, @1, @1.2, @1.2.3, ... alike).
# The rewritten files are committed by @semantic-release/git (.releaserc.json).
#
# Usage: bumpversion.sh <current version> <next version> <release type>

function log_info() {
  >&2 echo -e "[\\e[1;94mINFO\\e[0m] $*"
}

function log_error() {
  >&2 echo -e "[\\e[1;91mERROR\\e[0m] $*"
}

if [[ "$#" -le 2 ]]; then
  log_error "Missing arguments"
  log_error "Usage: $0 <current version> <next version> <release type>"
  exit 1
fi

curVer=$1
nextVer=$2
relType=$3

log_info "Pinning refs from \\e[33;1m${curVer:-<none>}\\e[0m to \\e[33;1m${nextVer}\\e[0m (release type: $relType)..."
for f in README.md docs/*.md examples/*.yml; do
  [[ -f "$f" ]] || continue
  sed -i.bak -E "s#(amine2233/kotlin-ci-shared[^[:space:]\"'\`]*@)[A-Za-z0-9._/-]+#\1${nextVer}#g" "$f"
  rm -f "$f.bak"
  log_info "  updated ${f}"
done
