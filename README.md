# Intel Homebrew bottles

Build official `homebrew/core` formulae on GitHub Actions and install the resulting
Homebrew bottles on Intel macOS 15 Sequoia with Homebrew in `/usr/local`.
GitHub's standard `macos-15-intel` runner is free for public repositories.
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## Scheduled builds

On the default branch of a GitHub repository with Actions enabled, the workflow
checks the stable formulae listed in [formulae.json](formulae.json) daily at
05:23 UTC. The list starts with `llvm`. Add or remove canonical `homebrew/core`
names to control which packages GitHub builds. A formula builds when there is
no live bottle artifact for the current stable source and formula revision.
Failed builds retry at the next check, and expired artifacts can be rebuilt.
GitHub can disable scheduled workflows in public repositories after 60 days
without repository activity.
[GitHub schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

To build immediately, open **Actions → Build an Intel Homebrew bottle → Run workflow**.
Enter a canonical core formula name such as `openssl@4` for a one-off build.
Leave the field empty to run the configured list.

The workflow builds the stable formula from the core checkout on the runner.
It then pours the bottle back into Homebrew, checks dynamic linking, and for
LLVM compiles and runs a small C program before uploading the bottle.

After a build succeeds, download and extract the versioned bottle from the run's
**Artifacts** section. GitHub requires you to sign in for this download. The
workflow requests 90 days of retention.
[Downloading workflow artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## Install the bottle

### Automatic selection

On an Intel Sequoia Mac with `jq` and an authenticated GitHub CLI, put this
checkout's `bin` directory before Homebrew in your `PATH`. From this directory,
run the following to try it in your current shell.

```sh
export PATH="$PWD/bin:$PATH"
brew update
brew install llvm
```

`brew update` refreshes Homebrew's metadata and reports matching GitHub bottles
for outdated installed formulae. `brew install` and `brew upgrade` prefer a
verified GitHub bottle matching the current stable source and revision.
If there is no match, a named formula install or upgrade uses an upstream
bottle when one is available and builds from source otherwise. A bare
`brew upgrade` tries matching GitHub bottles before the usual Homebrew upgrade.
The wrapper also checks Homebrew's plan for dependencies due to be installed or
upgraded. It installs exact-version GitHub matches with Homebrew's
`--as-dependency` flag and lets Homebrew resolve the remaining dependencies.
`brew upgrade go` requires a verified GitHub bottle for Go and matching
bottles for any pending dependencies. If a required bottle is missing, the
wrapper stops before starting a local build.
Use `brew reinstall llvm` to replace a local build of the same version.
Explicit options and local archive paths go straight to Homebrew.

### Manual download

From inside the extracted artifact directory, verify the SHA-256 checksum and
install the archive.

```sh
shasum -a 256 -c SHA256SUMS && HOMEBREW_DEVELOPER=1 brew install ./llvm--*.sequoia.bottle.tar.gz
```

If the same version is already installed and you want to replace it with this
bottle, use the same command with `reinstall`. LLVM is keg-only.
Invoke it with `"$(brew --prefix llvm)/bin/clang"`.

The archive installs under the original core formula name and version, with a
Homebrew receipt. Homebrew still resolves dependencies normally, so a missing
dependency can require its own source build or compatible bottle.
[Homebrew bottle documentation](https://docs.brew.sh/Bottles)

Homebrew plans to remove Intel support in or after September 2027.
[Homebrew support tiers](https://docs.brew.sh/Support-Tiers)
