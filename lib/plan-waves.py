#!/usr/bin/env python3
"""Plan dependency-ordered build waves for Intel Homebrew bottles."""

import argparse
import hashlib
import json
import re
import sys

FORMULA_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9+_.-]*(@[0-9][0-9.]*)?$")


def validate_formula_name(name: str) -> str:
    if not isinstance(name, str) or not FORMULA_NAME_RE.match(name):
        raise ValueError(f"Invalid canonical homebrew/core formula name: {name!r}")
    return name


def resolve_sequoia_formula(formula_obj: dict | None) -> dict:
    """Overlay Intel Sequoia variation fields over top-level Homebrew API metadata."""
    if not formula_obj:
        return {}
    variation = (formula_obj.get("variations") or {}).get("sequoia")
    if not isinstance(variation, dict):
        return formula_obj
    merged = dict(formula_obj)
    merged.update(variation)
    if isinstance(formula_obj.get("urls"), dict) and isinstance(variation.get("urls"), dict):
        merged_urls = dict(formula_obj["urls"])
        merged_urls.update(variation["urls"])
        merged["urls"] = merged_urls
    if isinstance(formula_obj.get("versions"), dict) and isinstance(variation.get("versions"), dict):
        merged_versions = dict(formula_obj["versions"])
        merged_versions.update(variation["versions"])
        merged["versions"] = merged_versions
    return merged


def bottle_artifact_name(formula_obj: dict) -> str | None:
    """Compute the exact artifact name matching lib/bottle.sh's bottle_identity."""
    resolved = resolve_sequoia_formula(formula_obj)
    name = resolved.get("name")
    versions = resolved.get("versions") or {}
    stable = versions.get("stable")
    urls = resolved.get("urls") or {}
    stable_url = urls.get("stable")
    if not name or stable is None or stable_url is None:
        return None
    revision = resolved.get("revision") or 0
    version_scheme = resolved.get("version_scheme") or 0
    source = {
        "version": stable,
        "revision": revision,
        "version_scheme": version_scheme,
        "source": stable_url,
    }
    compact = json.dumps(source, separators=(",", ":"), ensure_ascii=False)
    digest = hashlib.sha256(compact.encode("utf-8")).hexdigest()[:12]
    version = f"{stable}_{revision}" if revision > 0 else str(stable)
    return f"{name}-{version}-{digest}-sequoia-intel-bottle"


def formula_deps(formula_obj: dict | None) -> set[str]:
    resolved = resolve_sequoia_formula(formula_obj)
    if not resolved:
        return set()
    deps = set(resolved.get("dependencies") or [])
    deps.update(resolved.get("build_dependencies") or [])
    return deps


def plan_waves(
    configured: list[str],
    api_by_name: dict[str, dict],
    live_artifacts: set[str],
    requested_formula: str = "",
    skip_existing: bool = True,
    max_waves: int = 6,
    durations: dict[str, float] | None = None,
) -> dict:
    configured_set = {validate_formula_name(n) for n in configured}
    durations = durations or {}
    skipped: list[str] = []

    def wave_sort_key(name: str) -> tuple[float, str]:
        return (-float(durations.get(name, 0) or 0), name)

    def has_live_bottle(name: str) -> bool:
        obj = api_by_name.get(name)
        if not obj:
            return False
        artifact = bottle_artifact_name(obj)
        return artifact is not None and artifact in live_artifacts

    if requested_formula:
        req = validate_formula_name(requested_formula)
        to_build: set[str] = {req}
        # Pull in transitive missing dependencies that are tracked in formulae.json.
        stack = list(formula_deps(api_by_name.get(req)))
        visited: set[str] = {req}
        while stack:
            dep = stack.pop()
            if dep in visited:
                continue
            visited.add(dep)
            if dep in configured_set:
                if has_live_bottle(dep):
                    skipped.append(dep)
                else:
                    to_build.add(dep)
            stack.extend(formula_deps(api_by_name.get(dep)) - visited)
    else:
        to_build = set()
        for name in sorted(configured_set):
            if skip_existing and has_live_bottle(name):
                skipped.append(name)
            else:
                to_build.add(name)

    # Build dependency graph restricted to to_build:
    # edge u -> v means v depends on u (so u must be in an earlier wave than v).
    dependents: dict[str, set[str]] = {n: set() for n in to_build}
    in_degree: dict[str, int] = {n: 0 for n in to_build}

    # Include transitive reachability through formulas outside to_build too!
    # For example, if A depends on B (not in to_build) and B depends on C (in to_build),
    # then C must still be built before A.
    reachable_cache: dict[str, set[str]] = {}

    def reachable_in_build(node: str) -> set[str]:
        if node in reachable_cache:
            return reachable_cache[node]
        seen: set[str] = set()
        found: set[str] = set()
        stack = list(formula_deps(api_by_name.get(node)))
        while stack:
            cur = stack.pop()
            if cur in seen or cur == node:
                continue
            seen.add(cur)
            if cur in to_build:
                found.add(cur)
            else:
                stack.extend(formula_deps(api_by_name.get(cur)) - seen)
        reachable_cache[node] = found
        return found

    for node in to_build:
        for dep in reachable_in_build(node):
            dependents[dep].add(node)
            in_degree[node] += 1

    # Kahn's algorithm grouped by wave, ordered longest historical build first.
    waves: list[list[str]] = []
    remaining = set(to_build)
    while remaining:
        ready = sorted((n for n in remaining if in_degree[n] == 0), key=wave_sort_key)
        if not ready:
            # Cycle fallback: emit remaining nodes longest-first in the next wave.
            waves.append(sorted(remaining, key=wave_sort_key))
            break
        waves.append(ready)
        for n in ready:
            remaining.remove(n)
            for child in dependents[n]:
                in_degree[child] -= 1

    # Cap to max_waves by folding overflow waves into the last wave in order.
    if len(waves) > max_waves:
        merged_last: list[str] = []
        for w in waves[max_waves - 1 :]:
            merged_last.extend(w)
        waves = waves[: max_waves - 1] + [merged_last]

    while len(waves) < max_waves:
        waves.append([])

    return {
        "waves": waves,
        "skipped": sorted(set(skipped)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--formulae-file", required=True)
    parser.add_argument("--api-file", required=True)
    parser.add_argument("--artifacts-file", required=True)
    parser.add_argument("--requested-formula", default="")
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--max-waves", type=int, default=6)
    parser.add_argument("--durations-file", default="")
    args = parser.parse_args()

    with open(args.formulae_file, encoding="utf-8") as fh:
        configured = json.load(fh)
    if not isinstance(configured, list):
        raise ValueError("formulae.json must contain a JSON array")

    with open(args.api_file, encoding="utf-8") as fh:
        api_list = json.load(fh)
    api_by_name = {
        item["name"]: item
        for item in api_list
        if isinstance(item, dict) and "name" in item
    }

    with open(args.artifacts_file, encoding="utf-8") as fh:
        live_artifacts = set(json.load(fh))

    durations: dict[str, float] = {}
    if args.durations_file:
        with open(args.durations_file, encoding="utf-8") as fh:
            raw_durations = json.load(fh)
        if isinstance(raw_durations, dict):
            durations = {k: float(v) for k, v in raw_durations.items() if isinstance(v, (int, float))}

    result = plan_waves(
        configured=configured,
        api_by_name=api_by_name,
        live_artifacts=live_artifacts,
        requested_formula=args.requested_formula.strip(),
        skip_existing=args.skip_existing,
        max_waves=args.max_waves,
        durations=durations,
    )

    total = sum(len(w) for w in result["waves"])
    print(
        f"Planned {total} formulae across "
        f"{sum(1 for w in result['waves'] if w)} wave(s) "
        f"(skipped {len(result['skipped'])} already-bottled).",
        file=sys.stderr,
    )
    for idx, wave in enumerate(result["waves"]):
        if wave:
            formatted = [
                f"{n} (~{int(durations[n] // 60)}m)" if durations.get(n, 0) >= 60 else n
                for n in wave
            ]
            print(f"  wave-{idx} ({len(wave)}): {', '.join(formatted)}", file=sys.stderr)

    print(json.dumps(result, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
