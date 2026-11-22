# Intel Go bottle upgrade experiment

Upgrade the Go installation on Intel macOS 15 Sequoia from Homebrew's
`go` 1.27.1 to 1.27.4. The upgrade passes when Homebrew pours a bottle from
our GitHub workflow and no package compiles on the Mac.

## Dependencies

| Dependency | Where it is needed |
| --- | --- |
| Homebrew runtime formulae | None |
| Homebrew build formulae | None |
| Go 1.24.13 for Darwin amd64 | Precompiled bootstrap toolchain downloaded on the GitHub runner |

The build order contains only `go`. Homebrew's formula uses macOS Monterey or
later, and this Mac runs Sequoia. The Go bootstrap is a formula resource.
[Homebrew Go recipe](https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/g/go.rb)

## Build and upgrade

On November 22, 2026, GitHub Actions built Go 1.27.4 in 4 minutes 14 seconds
and poured the Intel Sequoia bottle into Homebrew on the runner. The receipt
and library linkage checks passed. On the Intel Mac, the archive's SHA-256
matched, its receipt listed zero runtime dependencies, and the extracted
binary printed `go version go1.27.4 darwin/amd64`.
[Go build run](https://github.com/michelinux/micbrew/actions/runs/45028316368) ·
[Verified bottle](https://github.com/michelinux/micbrew/actions/runs/45028316368/artifacts/14757340801)

In the project checkout, activate the wrapper for the current shell and check
that it comes first. The initial local dry run stopped because Homebrew requires
write access to `/usr/local/libexec`, which is owned by root on this Mac. Run
the upgrade after the local preflight passes.

```sh
export PATH="$PWD/bin:$PATH"
type -a brew
brew upgrade go
```

The Homebrew output should contain `Pouring go--1.27.4.sequoia.bottle.tar.gz`.
Verify the installed version and receipt.

```sh
go_prefix="$(brew --prefix go)"
"$go_prefix/bin/go" version
jq -e '.poured_from_bottle and .source.tap == "homebrew/core"' \
  "$go_prefix/INSTALL_RECEIPT.json"
```

## Future upgrades

`formulae.json` schedules Go builds for new stable versions and formula
revisions. `bottle-only.txt` makes the wrapper stop a Go upgrade while a
required bottle is missing. The wrapper skips automatic reverse-dependency
upgrades during this bottle-only operation to prevent incidental source
builds. If a later Go formula adds dependencies, build their missing
bottles first and then retry the Go upgrade. Run the wrapper without
additional flags to use this behavior.
