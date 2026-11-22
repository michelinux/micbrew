# Intel Homebrew bottles

Build official `homebrew/core` formulae on GitHub Actions and install the resulting
Homebrew bottles on Intel macOS 15 Sequoia with Homebrew in `/usr/local`.
GitHub's standard `macos-15-intel` runner is free for public repositories.
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## Automatic LLVM builds

On the default branch of a GitHub repository with Actions enabled, the workflow
checks the latest stable LLVM formula daily at 05:23 UTC. It builds when there
is no live bottle artifact for the current stable source and formula revision.
Failed builds retry at the next check, and expired artifacts can be rebuilt.
GitHub can disable scheduled workflows in public repositories after 60 days
without repository activity.
[GitHub schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

To build immediately, open **Actions → Build an Intel Homebrew bottle → Run workflow**.
Leave the formula set to `llvm`, or enter another canonical core formula name such as
`llvm@22`.

The workflow builds the stable formula from the core checkout on the runner.
For LLVM it uses Homebrew's ordinary source-build settings, which omit
profile-guided and link-time optimization so the build can fit within GitHub's
six-hour job limit. [GitHub Actions limits](https://docs.github.com/en/actions/reference/limits)
It then pours the bottle back into Homebrew, checks dynamic linking, and for
LLVM compiles and runs a small C program before uploading the bottle.

After a build succeeds, download and extract the versioned bottle from the run's
**Artifacts** section. GitHub requires you to sign in for this download. The
workflow requests 90 days of retention.
[Downloading workflow artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## Install the bottle

From inside the extracted artifact directory, verify the SHA-256 checksum and
install the archive.

```sh
shasum -a 256 -c SHA256SUMS && brew install ./llvm--*.sequoia.bottle.tar.gz
```

If the same version is already installed and you want to replace it with this
bottle, use `brew reinstall` with the same archive path. LLVM is keg-only.
Invoke it with `"$(brew --prefix llvm)/bin/clang"`.

The archive installs under the original core formula name and version, with a
Homebrew receipt. Homebrew still resolves dependencies normally, so a missing
dependency can require its own source build or compatible bottle. Install newer
LLVM bottles by archive path when the workflow produces them. Plain
`brew install llvm` and `brew upgrade` continue to use upstream bottle metadata.
[Homebrew bottle documentation](https://docs.brew.sh/Bottles)

Homebrew plans to remove Intel support in or after September 2027.
[Homebrew support tiers](https://docs.brew.sh/Support-Tiers)
