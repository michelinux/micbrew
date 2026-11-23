#!/bin/bash

main() (
  set -euo pipefail

  if [[ "$(uname -m)" != x86_64 || "$(sw_vers -productVersion)" != 15.* ]]; then
    printf 'micbrew setup requires an Intel Mac running macOS Sequoia.\n' >&2
    exit 1
  fi
  if [[ ! -x /usr/local/bin/brew ]]; then
    printf 'Install Homebrew in /usr/local before running micbrew setup.\n' >&2
    exit 1
  fi

  export PATH="/usr/local/bin:$PATH"
  set --
  for tool in gh jq; do
    if ! command -v "$tool" >/dev/null; then
      set -- "$@" "$tool"
    fi
  done
  if [[ $# -gt 0 ]]; then
    /usr/local/bin/brew install "$@" </dev/null
  fi

  repository=michelinux/micbrew
  revision="$(curl -fsSL --retry 3 -H 'Accept: application/vnd.github.sha' \
    "https://api.github.com/repos/$repository/commits/main")"
  if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
    printf 'Could not resolve the micbrew revision on GitHub.\n' >&2
    exit 1
  fi

  install_dir="$HOME/.local/share/micbrew"
  current="$install_dir/current"
  if [[ -e "$current" && ! -L "$current" ]]; then
    printf 'micbrew setup expected %s to be a symbolic link.\n' "$current" >&2
    exit 1
  fi
  installed_revision="$(readlink "$current" 2>/dev/null || true)"
  if [[ "$installed_revision" != "releases/$revision."* ||
        ! -x "$current/bin/brew" || ! -s "$current/lib/bottle.sh" || ! -f "$current/bottle-only.txt" ]]; then
    mkdir -p "$install_dir/releases"
    release="$(mktemp -d "$install_dir/releases/$revision.XXXXXX")"
    published=false
    trap 'if [[ "$published" == false ]]; then rm -rf -- "$release"; fi' EXIT

    mkdir -p "$release/bin" "$release/lib"
    for file in bin/brew lib/bottle.sh bottle-only.txt; do
      curl -fsSL --retry 3 "https://raw.githubusercontent.com/$repository/$revision/$file" -o "$release/$file"
    done
    /bin/bash -n "$release/bin/brew"
    /bin/bash -n "$release/lib/bottle.sh"
    chmod +x "$release/bin/brew"

    ln -s "releases/${release##*/}" "$release/current"
    mv -fh "$release/current" "$current"
    published=true
  fi

  profile=
  shell=${SHELL:-}
  case "${shell##*/}" in
    zsh) profile="${ZDOTDIR:-$HOME}/.zshrc" ;;
    bash)
      for profile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        [[ -r "$profile" ]] && break
      done
      if [[ ! -r "$profile" ]]; then
        profile="$HOME/.bash_profile"
      fi
      ;;
  esac

  if [[ -n "$profile" ]] && ! grep -Fqx '# micbrew wrapper' "$profile" 2>/dev/null; then
    mkdir -p "$(dirname "$profile")"
    cat >> "$profile" <<'PROFILE'

# micbrew wrapper
if [ "${PATH%%:*}" != "$HOME/.local/share/micbrew/current/bin" ]; then
  export PATH="$HOME/.local/share/micbrew/current/bin:$PATH"
fi
PROFILE
  fi

  if ! gh auth status --hostname github.com >/dev/null 2>&1; then
    if [[ -t 1 ]] && gh auth login --hostname github.com </dev/tty; then
      printf 'GitHub sign-in is ready.\n'
    else
      printf 'Sign in with gh auth login before using the wrapper.\n'
    fi
  fi

  printf 'Installed micbrew at %s.\n' "$current"
  if [[ -n "$profile" ]]; then
    printf 'Open a new terminal to use the wrapper.\n'
  else
    printf 'Put %s/bin first in your shell PATH.\n' "$current"
  fi
)

main "$@"
