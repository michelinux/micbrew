#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf -- "$test_dir"' EXIT
source "$root/lib/bottle.sh"

export MICBREW_TEST_DIR="$test_dir" HOMEBREW_NO_AUTO_UPDATE=1
export MICBREW_REAL_BREW="$test_dir/brew" PATH="$test_dir:$PATH"

for formula in parent runtime crypto mismatched pinned unrelated; do
  jq -nc --arg name "$formula" '{formulae: [{
    name: $name, tap: "homebrew/core", versions: {stable: "2.0"}, revision: 0,
    version_scheme: 0, urls: {stable: {checksum: "source"}},
    pinned: ($name == "pinned"), installed: []
  }]}' > "$test_dir/$formula.json"
done

for formula in runtime crypto mismatched pinned unrelated; do
  identity="$(bottle_identity "$formula" "$(cat "$test_dir/$formula.json")")"
  IFS=$'\t' read -r version artifact <<< "$identity"
  jq -nc --arg name "$artifact" '{
    name: $name, expired: false, workflow_run: {id: 1, head_repository_id: 1, repository_id: 1}
  }'
done | jq -s '[{artifacts: .}]' > "$test_dir/catalog.json"

cat > "$test_dir/uname" <<'MOCK'
#!/bin/bash
echo x86_64
MOCK
cat > "$test_dir/sw_vers" <<'MOCK'
#!/bin/bash
echo 15.7
MOCK
cat > "$test_dir/gh" <<'MOCK'
#!/bin/bash
set -eu
if [[ "$1" == api ]]; then
  cat "$MICBREW_TEST_DIR/catalog.json"
else
  artifact=$7
  destination=$9
  name=${artifact%%-*}
  file="$name--2.0.sequoia.bottle.tar.gz"
  (
    cd "$destination"
    printf '%s\n' "$file" > "$file"
    shasum -a 256 "./$file" > SHA256SUMS
  )
fi
MOCK

cat > "$test_dir/brew" <<'MOCK'
#!/bin/bash
set -eu
if [[ "$1" == outdated ]]; then
  printf '{"formulae":[]}\n'
elif [[ "$1" == info ]]; then
  name=${@: -1}
  name=${name#homebrew/core/}
  if [[ -f "$MICBREW_TEST_DIR/$name.installed" ]]; then
    jq '.formulae[0].installed = [{version: "2.0"}]' "$MICBREW_TEST_DIR/$name.json"
  else
    cat "$MICBREW_TEST_DIR/$name.json"
  fi
elif [[ "${2:-}" == --dry-run ]]; then
  case "${@: -1}" in
    parent|--no-ask)
      cat <<'PLAN'
==> Would upgrade 1 outdated package:
unrelated 1.0 -> 2.0
==> Would install 3 dependencies for parent:
runtime     2.0
mismatched  3.0
pinned      2.0
==> Would upgrade 1 dependency for parent:
crypto 1.0 -> 2.0
PLAN
      ;;
    ./runtime--*)
      printf '==> Would upgrade 1 dependency for runtime:\ncrypto 1.0 -> 2.0\n'
      ;;
  esac
else
  reference=${@: -1}
  case "$reference" in
    ./runtime--*|./crypto--*)
      [[ "${HOMEBREW_DEVELOPER:-}" == 1 && -f "$reference" ]]
      name=${reference#./}
      touch "$MICBREW_TEST_DIR/${name%%--*}.installed"
      ;;
  esac
  printf '%s\n' "$*" >> "$MICBREW_TEST_DIR/calls"
fi
MOCK
chmod +x "$test_dir/brew" "$test_dir/gh" "$test_dir/uname" "$test_dir/sw_vers"

"$root/bin/brew" install parent
diff -u - "$test_dir/calls" <<'EXPECTED'
install --as-dependency ./crypto--2.0.sequoia.bottle.tar.gz
install --as-dependency ./runtime--2.0.sequoia.bottle.tar.gz
install --build-from-source parent
EXPECTED

rm -- "$test_dir/crypto.installed" "$test_dir/runtime.installed"
: > "$test_dir/calls"
"$root/bin/brew" upgrade
diff -u - "$test_dir/calls" <<'EXPECTED'
install --as-dependency ./crypto--2.0.sequoia.bottle.tar.gz
install --as-dependency ./runtime--2.0.sequoia.bottle.tar.gz
upgrade
EXPECTED
