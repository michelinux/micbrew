#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
source "$project_dir/lib/bottle.sh"

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/micbrew-plan-test.XXXXXX")"
trap 'rm -rf -- "$tmp_dir"' EXIT

cat >"$tmp_dir/api.json" <<'EOF'
[
  {
    "name": "z3",
    "versions": {"stable": "5.4.1"},
    "revision": 0,
    "version_scheme": 0,
    "urls": {"stable": {"url": "https://example.invalid/z3.tar.gz"}},
    "dependencies": [],
    "build_dependencies": []
  },
  {
    "name": "llvm",
    "versions": {"stable": "23.1.6"},
    "revision": 0,
    "version_scheme": 0,
    "urls": {"stable": {"url": "https://example.invalid/llvm.tar.gz"}},
    "dependencies": ["z3"],
    "build_dependencies": []
  },
  {
    "name": "rust",
    "versions": {"stable": "1.100.0"},
    "revision": 0,
    "version_scheme": 0,
    "urls": {"stable": {"url": "https://example.invalid/rust.tar.gz"}},
    "dependencies": ["llvm"],
    "build_dependencies": []
  },
  {
    "name": "helper",
    "versions": {"stable": "1.0"},
    "revision": 0,
    "version_scheme": 0,
    "urls": {"stable": {"url": "https://example.invalid/helper.tar.gz"}},
    "dependencies": ["rust"],
    "build_dependencies": []
  },
  {
    "name": "ripgrep",
    "versions": {"stable": "16.0.0"},
    "revision": 1,
    "version_scheme": 0,
    "urls": {"stable": {"url": "https://example.invalid/rg.tar.gz"}},
    "dependencies": [],
    "build_dependencies": ["helper"]
  }
]
EOF

cat >"$tmp_dir/formulae.json" <<'EOF'
["z3", "llvm", "rust", "ripgrep"]
EOF

# 1. Verify bottle_artifact_name matches lib/bottle.sh's bottle_identity exactly.
z3_id="$(bottle_identity z3 "$(jq -c '{formulae: [.[] | select(.name == "z3")]}' "$tmp_dir/api.json")" | cut -f2)"
llvm_id="$(bottle_identity llvm "$(jq -c '{formulae: [.[] | select(.name == "llvm")]}' "$tmp_dir/api.json")" | cut -f2)"
rg_id="$(bottle_identity ripgrep "$(jq -c '{formulae: [.[] | select(.name == "ripgrep")]}' "$tmp_dir/api.json")" | cut -f2)"

# 2. Full list with z3 and llvm already bottled -> wave_0=[rust], wave_1=[ripgrep] (transitive via helper!).
jq -nc --arg z3 "$z3_id" --arg llvm "$llvm_id" '[$z3, $llvm]' >"$tmp_dir/artifacts.json"
out="$(python3 "$project_dir/lib/plan-waves.py" \
  --formulae-file "$tmp_dir/formulae.json" \
  --api-file "$tmp_dir/api.json" \
  --artifacts-file "$tmp_dir/artifacts.json" \
  --skip-existing \
  --max-waves 4 2>/dev/null)"
jq -e '.waves == [["rust"], ["ripgrep"], [], []] and .skipped == ["llvm", "z3"]' <<<"$out" >/dev/null

# 3. Single-formula dispatch for ripgrep pulls in unbuilt configured dep rust, skips live z3/llvm,
#    and still builds ripgrep even if ripgrep already has a live bottle.
jq -nc --arg z3 "$z3_id" --arg llvm "$llvm_id" --arg rg "$rg_id" '[$z3, $llvm, $rg]' >"$tmp_dir/artifacts-rg.json"
out="$(python3 "$project_dir/lib/plan-waves.py" \
  --formulae-file "$tmp_dir/formulae.json" \
  --api-file "$tmp_dir/api.json" \
  --artifacts-file "$tmp_dir/artifacts-rg.json" \
  --requested-formula ripgrep \
  --skip-existing \
  --max-waves 4 2>/dev/null)"
jq -e '.waves == [["rust"], ["ripgrep"], [], []] and .skipped == ["llvm", "z3"]' <<<"$out" >/dev/null

# 4. Empty artifacts -> full 4-wave chain folded to max_waves=3: z3 -> llvm -> [rust, ripgrep].
echo '[]' >"$tmp_dir/empty.json"
out="$(python3 "$project_dir/lib/plan-waves.py" \
  --formulae-file "$tmp_dir/formulae.json" \
  --api-file "$tmp_dir/api.json" \
  --artifacts-file "$tmp_dir/empty.json" \
  --skip-existing \
  --max-waves 3 2>/dev/null)"
jq -e '.waves == [["z3"], ["llvm"], ["rust", "ripgrep"]] and .skipped == []' <<<"$out" >/dev/null

# 5. Historical durations sort each wave longest-first (with alphabetical tie-breaker).
cat >"$tmp_dir/parallel-api.json" <<'EOF'
[
  {"name": "alpha", "versions": {"stable": "1.0"}, "revision": 0, "version_scheme": 0, "urls": {"stable": {"url": "https://example.invalid/a.tgz"}}, "dependencies": [], "build_dependencies": []},
  {"name": "beta",  "versions": {"stable": "1.0"}, "revision": 0, "version_scheme": 0, "urls": {"stable": {"url": "https://example.invalid/b.tgz"}}, "dependencies": [], "build_dependencies": []},
  {"name": "gamma", "versions": {"stable": "1.0"}, "revision": 0, "version_scheme": 0, "urls": {"stable": {"url": "https://example.invalid/g.tgz"}}, "dependencies": [], "build_dependencies": []},
  {"name": "delta", "versions": {"stable": "1.0"}, "revision": 0, "version_scheme": 0, "urls": {"stable": {"url": "https://example.invalid/d.tgz"}}, "dependencies": [], "build_dependencies": []}
]
EOF
echo '["alpha", "beta", "gamma", "delta"]' >"$tmp_dir/parallel-formulae.json"
echo '{"gamma": 7200, "beta": 900}' >"$tmp_dir/durations.json"
out="$(python3 "$project_dir/lib/plan-waves.py" \
  --formulae-file "$tmp_dir/parallel-formulae.json" \
  --api-file "$tmp_dir/parallel-api.json" \
  --artifacts-file "$tmp_dir/empty.json" \
  --durations-file "$tmp_dir/durations.json" \
  --skip-existing \
  --max-waves 2 2>/dev/null)"
jq -e '.waves == [["gamma", "beta", "alpha", "delta"], []]' <<<"$out" >/dev/null

echo "plan-waves tests passed"
