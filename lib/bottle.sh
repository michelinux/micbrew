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

bottle_catalog() {
  local repo=$1 result
  if command -v gh >/dev/null; then
    if result="$(gh api --method GET --paginate --slurp \
      "repos/$repo/actions/artifacts" -f per_page=100 |
      jq -c '[.[].artifacts[] | select(.expired == false and (.name | endswith("-sequoia-intel-bottle")))]')"; then
      printf '%s\n' "$result"
      return 0
    fi
    printf 'micbrew: GitHub bottles are unavailable. Using Homebrew.\n' >&2
  fi
  printf '[]\n'
}

formula_metadata() {
  local arg=$1 name=${1#homebrew/core/} metadata
  if [[ ! "$name" =~ ^[a-z0-9][a-z0-9+_.-]*(@[0-9][0-9.]*)?$ ]] ||
    ! metadata="$("$brew_path" info --formula --json=v2 "$arg" 2>/dev/null)" ||
    ! jq -e --arg name "$name" '.formulae[0] | .name == $name and .tap == "homebrew/core" and .versions.stable != null' \
      <<< "$metadata" >/dev/null; then
    return 1
  fi
  printf '%s\n' "$metadata"
}

artifact_run() {
  jq -r --arg name "$1" '
    map(select(.name == $name and .workflow_run.head_repository_id == .workflow_run.repository_id)
        | select(.workflow_run.id != null))
    | max_by(.created_at) | .workflow_run.id // empty
  ' <<< "$catalog"
}

upstream_bottle_available() {
  jq -e '
    .formulae[0].bottle.stable.files // {}
    | keys | any(test("^(all|sequoia|sonoma|ventura|monterey|big_sur|catalina|mojave|high_sierra|sierra|el_capitan|yosemite)$"))
  ' <<< "$1" >/dev/null
}

download_bottle() {
  local name=$1 version=$2 artifact=$3 run_id=$4 destination file digest
  [[ -n "$run_id" ]] || return 0

  destination="$(mktemp -d "$work_dir/$name.XXXXXX")" || return
  if ! gh run download "$run_id" --repo "$repository" --name "$artifact" --dir "$destination" >&2; then
    printf 'micbrew: download failed for %s. Using Homebrew.\n' "$artifact" >&2
    return 0
  fi

  file="$name--$version.sequoia.bottle.tar.gz"
  if ! digest="$(awk -v file="./$file" '$2 == file {print $1}' "$destination/SHA256SUMS")" ||
    [[ ! "$digest" =~ ^[a-f0-9]{64}$ ]] ||
    ! printf '%s  %s\n' "$digest" "$destination/$file" | shasum -a 256 -c --status; then
    printf 'micbrew: checksum verification failed for %s.\n' "$file" >&2
    return 1
  fi
  printf '%s\n' "$destination/$file"
}

run_brew() {
  local directory=$1
  shift
  if [[ -n "$directory" ]]; then
    (cd "$directory" && HOMEBREW_DEVELOPER=1 "$brew_path" "$@")
  else
    "$brew_path" "$@"
  fi
}

prepare_dependencies() {
  [[ "$catalog" != '[]' ]] || return 0
  local command=$1 directory=$2 ancestors=$3 strict=$4 plan dependencies name version
  shift 4
  # Reinstall has no dry-run, but the install planner can show just its dependencies.
  if [[ "$command" == reinstall ]]; then
    command=install
    set -- --only-dependencies "$@"
  fi
  if ! plan="$(HOMEBREW_NO_COLOR=1 run_brew "$directory" "$command" --dry-run --no-ask "$@" 2>&1)"; then
    if [[ "$strict" == true ]]; then
      printf 'micbrew: unable to verify the bottle-only dependency plan.\n%s\n' "$plan" >&2
      return 1
    fi
    return 0
  fi
  dependencies="$(awk '
    /^==>/ {
      in_dependencies = /^==> Would (install|upgrade) [0-9]+ dependenc(y|ies)( for [^:]+)?:$/
      next
    }
    in_dependencies && (NF == 2 || (NF == 4 && $3 == "->")) {
      entry = $1 " " $NF
      if (!seen[entry]++) print entry
    }
  ' <<< "$plan")"
  while read -r name version; do
    [[ -n "$name" ]] || continue
    install_dependency_bottle "$name" "$version" "$ancestors" "$strict"
  done <<< "$dependencies"

  if [[ "$strict" == true ]] &&
    grep -Eq '^==> Would (install|upgrade) [0-9]+ dependenc(y|ies)( for [^:]+)?:$' <<< "$plan"; then
    plan="$(HOMEBREW_NO_COLOR=1 run_brew "$directory" "$command" --dry-run --no-ask "$@")"
    if grep -Eq '^==> Would (install|upgrade) [0-9]+ dependenc(y|ies)( for [^:]+)?:$' <<< "$plan"; then
      printf 'micbrew: the following plan still requires dependencies. Waiting for matching bottles.\n%s\n' "$plan" >&2
      return 1
    fi
  fi
}

install_dependency_bottle() {
  local arg=$1 planned_version=$2 ancestors=$3 strict=$4 name=${1#homebrew/core/}
  local metadata identity version artifact run_id bottle_path directory= reference="$arg"
  [[ " $ancestors " != *" $name "* ]] || return 0
  if [[ "$strict" != true ]]; then
    jq -e --arg prefix "$name-" 'any(.name | startswith($prefix))' <<< "$catalog" >/dev/null || return 0
  fi
  metadata="$(formula_metadata "$arg")" || return 0
  identity="$(bottle_identity "$name" "$metadata")"
  IFS=$'\t' read -r version artifact <<< "$identity"
  [[ "$version" == "$planned_version" ]] || return 0
  jq -e --arg version "$version" '
    .formulae[0] | (.pinned | not) and (.installed | all(.version != $version))
  ' <<< "$metadata" >/dev/null || return 0

  run_id="$(artifact_run "$artifact")"
  bottle_path="$(download_bottle "$name" "$version" "$artifact" "$run_id")"
  if [[ -n "$bottle_path" ]]; then
    directory="${bottle_path%/*}"
    reference="./${bottle_path##*/}"
  elif [[ "$strict" != true ]] || ! upstream_bottle_available "$metadata"; then
    return 0
  fi
  # A bottle can need another bottle even when the parent plan lists installs before upgrades.
  local options=(--as-dependency)
  if [[ "$strict" == true ]]; then
    options+=(--force-bottle)
  fi
  prepare_dependencies install "$directory" "$ancestors $name" "$strict" "${options[@]}" "$reference"
  if [[ -n "$bottle_path" ]]; then
    printf 'micbrew: using a GitHub bottle for dependency %s %s.\n' "$name" "$version"
  fi
  run_brew "$directory" install "${options[@]}" "$reference"
}

install_build_dependencies() {
  local repository=$1 formula=$2 target=$3
  local brew_path=${MICBREW_REAL_BREW:-$(command -v brew)}
  local catalog work_dir=
  catalog="$(bottle_catalog "$repository")"
  if [[ "$catalog" != '[]' ]]; then
    work_dir="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/micbrew-deps.XXXXXX")"
    prepare_dependencies install "" "$formula" false --only-dependencies --build-from-source "$target" || {
      rm -rf -- "$work_dir"
      return 1
    }
    rm -rf -- "$work_dir"
  fi
  "$brew_path" install --only-dependencies --build-from-source "$target"
}
