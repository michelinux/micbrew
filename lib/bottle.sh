# Shared by the workflow and the Homebrew wrapper.
bottle_identity() {
  local formula=$1 metadata=$2 source version digest
  source="$(jq -ce --arg name "$formula" '
    .formulae[0]
    | select(.name == $name and .versions.stable != null)
    | {version: .versions.stable, revision, version_scheme, source: .urls.stable}
  ' <<< "$metadata")" || return
  version="$(jq -r '.version + (if .revision > 0 then "_\(.revision)" else "" end)' <<< "$source")" || return
  digest="$(printf '%s' "$source" | shasum -a 256 | cut -c1-12)" || return
  printf '%s\t%s\n' "$version" "$formula-$version-$digest-sequoia-intel-bottle"
}
