# Intel Homebrew bottles

Build official `homebrew/core` formulae on GitHub Actions and install the resulting
Homebrew bottles on Intel macOS 15 Sequoia with Homebrew in `/usr/local`.
GitHub's standard `macos-15-intel` runner is free for public repositories.
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## Build LLVM

1. Put this project on the default branch of a public GitHub repository with Actions enabled.
2. Open **Actions → Build an Intel Homebrew bottle → Run workflow**. Leave the formula
   set to `llvm`, or enter another canonical core formula name such as `llvm@22`.
3. When the run succeeds, download and extract `llvm-sequoia-intel-bottle` from
   the run's **Artifacts** section. GitHub requires you to sign in for this download.
   The workflow requests 90 days of retention.
   [Downloading workflow artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

The workflow builds the stable formula from the core checkout on the runner.
It then pours the bottle back into Homebrew, checks dynamic linking, and for
LLVM compiles and runs a small C program before uploading the bottle.

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
dependency can require its own source build or compatible bottle. Repeat this
workflow for newer versions as needed and install by archive path. Plain
`brew install llvm` and `brew upgrade` continue to use upstream bottle metadata.
[Homebrew bottle documentation](https://docs.brew.sh/Bottles)

Homebrew plans to remove Intel support in or after September 2027.
[Homebrew support tiers](https://docs.brew.sh/Support-Tiers)
