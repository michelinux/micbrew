# Intel Wget upgrade with bottled dependencies

Upgrade Wget from 1.25.0 to the Homebrew revision 1.25.0_2 on Intel macOS
Sequoia. The test passes when Homebrew pours Wget and its required dependency
bottles without compiling a package on the Mac.

## Dependency plan

| Package | Planned change | Bottle source |
| --- | --- | --- |
| `libunistring` | Upgrade 1.4.2 to 1.5 | Our GitHub workflow |
| `libpsl` | Install 0.23.3 | Homebrew's Intel Sonoma bottle |
| `ca-certificates` | Upgrade 2026-10-20 to 2026-11-05 | Homebrew's platform-independent bottle |
| `wget` | Upgrade 1.25.0 to 1.25.0_2 | Our GitHub workflow |

Homebrew's plan for building Wget from source also lists `pkgconf`. That
dependency belongs to the build on GitHub. The other runtime dependencies in
the Wget formula are already satisfied on this Mac.

## GitHub builds

GitHub built and verified `libunistring` 1.5 first, then built Wget
1.25.0_2. Both Intel Sequoia bottles passed the workflow's Homebrew
installation and linkage checks.
[libunistring bottle](https://github.com/michelinux/micbrew/actions/runs/45031073246/artifacts/14757822733)
[Wget bottle](https://github.com/michelinux/micbrew/actions/runs/45031759759/artifacts/14759001243)

On the Intel Mac, Homebrew's dry run against the Wget archive requested
exactly the three dependencies in the table. It would have built
`libunistring` from source on its own. The wrapper rehearsal used native
Homebrew dry runs and intercepted the install commands. It selected the
GitHub `libunistring` bottle and the two upstream dependency bottles before
Wget. Every install command used `--force-bottle`, and `pkgconf` was absent
from the plan.

## Local upgrade

The actual upgrade is pending.

From a shell with this project's wrapper first in `PATH`, require bottles
for this one upgrade. The wrapper prefers our GitHub bottles and can use a
matching Homebrew bottle for a dependency. It stops if the plan still needs
a package without a bottle.

```sh
MICBREW_BOTTLE_ONLY=wget brew upgrade wget
```

Verify the installed versions and Homebrew receipts after the upgrade.

```sh
brew list --versions wget libunistring libpsl ca-certificates
for formula in wget libunistring libpsl ca-certificates; do
  jq -e '.poured_from_bottle' "$(brew --prefix "$formula")/INSTALL_RECEIPT.json"
done
```
