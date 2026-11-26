# Intel Homebrew bottles

Build official `homebrew/core` formulae on GitHub Actions and install the resulting
Homebrew bottles on Intel macOS 15 Sequoia with Homebrew in `/usr/local`.
GitHub's standard `macos-15-intel` runner is free for public repositories.
[GitHub runner reference](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

## Scheduled builds

On the default branch of a GitHub repository with Actions enabled, the workflow
checks the stable formulae listed in [formulae.json](formulae.json) daily at
05:23 UTC. The list includes `go` and `llvm`. Add or remove canonical `homebrew/core`
names to control which packages GitHub builds. A formula builds when there is
no live bottle artifact for the current stable source and formula revision.
Failed builds retry at the next check, and expired artifacts can be rebuilt.
GitHub can disable scheduled workflows in public repositories after 60 days
without repository activity.
[GitHub schedule documentation](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)

To build immediately, open **Actions → Build an Intel Homebrew bottle → Run workflow**.
Enter a canonical core formula name such as `openssl@4` for a one-off build.
Leave the field empty to run the configured list.

The workflow skips formulae that already have a live bottle artifact up front
and topologically sorts the remaining formulae into dependency waves
([lib/plan-waves.py](lib/plan-waves.py)), so shared dependencies (such as `z3`,
`llvm`, and `rust`) finish and upload their bottles before downstream formulae
start. Dispatching a single formula also pulls in any missing transitive
dependencies tracked in [formulae.json](formulae.json) in earlier waves.
The workflow builds each stable formula from the core checkout on the runner.
Before building, it checks the repository's live GitHub bottle artifacts and
pours any exact-version dependency bottles (along with any available upstream
Homebrew bottles), falling back to source builds only for remaining
dependencies that lack both.
When a formula is already pre-installed on the runner (such as `openssl@3`), it
installs dependencies and fetches the source before uninstalling the existing
keg and clearing Homebrew's tool-selection cache, so runner tools linked
against that formula do not break downloads.
For LLVM it uses Homebrew's ordinary source-build settings, which omit
profile-guided and link-time optimization so the build can fit within GitHub's
six-hour job limit. [GitHub Actions limits](https://docs.github.com/en/actions/reference/limits)
For `python@*` formulae it removes preinstalled `Python.framework` symlinks in
`/usr/local/bin` for that version so Homebrew can link the built and verified
bottle cleanly. Before building any formula that does not declare `gettext` or
`gdbm` as a dependency, it unlinks those pre-installed libraries from
`/usr/local` so builds do not pick up undeclared runtime linkage.
It then pours the bottle back into Homebrew, checks dynamic linking, and for
LLVM compiles and runs a small C program before uploading the bottle.

After a build succeeds, download and extract the versioned bottle from the run's
**Artifacts** section. GitHub requires you to sign in for this download. The
workflow requests 90 days of retention.
[Downloading workflow artifacts](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## Install the bottle

### Automatic selection

On Intel macOS Sequoia with Homebrew in `/usr/local`, run the setup command to
install the wrapper under `~/.local/share/micbrew` and add it to your Zsh or
Bash startup file. Setup installs `gh` and `jq` if needed. GitHub requires
you to sign in to download Actions artifacts, so setup prompts you to sign in
if you run it in a terminal without an active GitHub CLI login.

```sh
curl -fsSL https://raw.githubusercontent.com/michelinux/micbrew/main/setup.sh | /bin/bash
```

Open a new terminal to use the wrapper. Run the same setup command again to
update it. If you're working from a checkout, you can activate that copy in
your current shell with `export PATH="$PWD/bin:$PATH"` from the project directory.

```sh
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
Formulae in `bottle-only.txt` require a verified GitHub bottle. Their
pending dependencies can use matching GitHub or upstream bottles. If a
required bottle is missing, the wrapper stops before starting a local build.
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
