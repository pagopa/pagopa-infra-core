#!/usr/bin/env python3
"""
Purge old images from one or more Azure Container Registries

Rules (same as `acr purge --ago <ago-days> --keep <keep> --untagged`):
  - the --keep most recent tagged images of each repository are always kept;
  - beyond those, tagged images older than --ago-days are deleted;
  - untagged images older than --ago-days are deleted;
  - locked manifests (deleteEnabled = false) are never touched;
  - the platform manifests of a multi-arch image follow their index.

Default is DRY-RUN: it only prints what would be deleted. Pass --execute to delete.
Deletion is by digest (`az acr manifest delete`), so a deleted manifest loses all its tags.

Runs as a ClouDO runbook (schedule in env/<env>/schedules.json.tpl) with the ClouDO
managed identity, which needs AcrPull and AcrDelete on every registry.

Local run:
    python3 acr_purge.py --registry pagopadcommonacr,pagopaditncoreacr --keep 2 --ago-days 1 [--repo-filter '^pagopa'] [--execute]
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

AZ = shutil.which("az") or "az"
INDEX_MEDIA_TYPES = {
    "application/vnd.docker.distribution.manifest.list.v2+json",
    "application/vnd.oci.image.index.v1+json",
}
# no per-command log files and no telemetry cache under ~/.azure: the runbook makes hundreds of az calls
AZ_ENV = {**os.environ, "AZURE_LOGGING_ENABLE_LOG_FILE": "false", "AZURE_CORE_COLLECT_TELEMETRY": "false"}


def az(*args):
    res = subprocess.run([AZ, *args, "--only-show-errors", "--output", "json"],
                         capture_output=True, text=True, env=AZ_ENV)
    if res.returncode != 0:
        lines = (res.stderr or "").strip().splitlines()
        raise RuntimeError(lines[-1] if lines else f"exit code {res.returncode}")
    out = res.stdout.strip()
    return json.loads(out) if out else None


def az_login():
    try:
        az("account", "show")
    except RuntimeError:
        client_id = os.getenv("AZURE_CLIENT_ID")
        az("login", "--identity", *(["--client-id", client_id] if client_id else []))


def parse_time(s):
    # ACR returns 7 fractional digits, fromisoformat (< 3.11) accepts at most 6
    if not s:
        return None
    try:
        dt = datetime.fromisoformat(re.sub(r"(\.\d{6})\d+", r"\1", s.replace("Z", "+00:00")))
    except ValueError:
        return None
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def plan_repo(registry, repo, cutoff, keep, workers):
    """Return the manifests of `repo` to delete and the number of manifests in it."""
    mans = [m for m in az("acr", "manifest", "list-metadata", "--registry", registry, "--name", repo) or []
            if m.get("digest")]
    by_digest = {m["digest"]: m for m in mans}

    indexes = [d for d, m in by_digest.items() if m.get("mediaType") in INDEX_MEDIA_TYPES]
    with ThreadPoolExecutor(max_workers=workers) as ex:
        contents = ex.map(lambda d: az("acr", "manifest", "show", "--registry", registry, "--name", f"{repo}@{d}"),
                          indexes)
        children_of = {d: [c["digest"] for c in (content or {}).get("manifests", []) if c.get("digest")]
                       for d, content in zip(indexes, contents)}
    children = {c for cs in children_of.values() for c in cs}

    def locked(d):
        return (by_digest.get(d, {}).get("changeableAttributes") or {}).get("deleteEnabled") is False

    def closure(roots):
        seen, stack = set(), list(roots)
        while stack:
            d = stack.pop()
            if d not in seen:
                seen.add(d)
                stack.extend(children_of.get(d, []))
        return seen

    keep_roots, del_roots, tagged = set(), set(), []
    for d, m in by_digest.items():
        if d in children:
            continue
        dt = parse_time(m.get("lastUpdateTime"))
        if locked(d) or dt is None:
            keep_roots.add(d)
        elif m.get("tags"):
            tagged.append((dt, d))
        elif dt < cutoff:
            del_roots.add(d)
        else:
            keep_roots.add(d)

    tagged.sort(reverse=True)
    for i, (dt, d) in enumerate(tagged):
        (keep_roots if i < keep or dt >= cutoff else del_roots).add(d)

    kept = closure(keep_roots)
    deleted = [by_digest[d] for d in closure(del_roots) - kept if d in by_digest and not locked(d)]
    deleted.sort(key=lambda m: m.get("lastUpdateTime") or "", reverse=True)
    return deleted, len(mans)


def purge_registry(registry, args, cutoff):
    """Purge one registry. Return the list of errors: failures on single repositories or
    manifests are logged and skipped, they never stop the purge of the other ones."""
    repo_re = re.compile(args.repo_filter)
    repos = sorted(r for r in az("acr", "repository", "list", "--name", registry) or [] if repo_re.search(r))

    print(f"{'EXECUTE' if args.execute else 'DRY-RUN'} on {registry}: --keep {args.keep} "
          f"--ago-days {args.ago_days:g} (before {cutoff:%Y-%m-%d %H:%M} UTC), {len(repos)} repositories")

    plan, errors = [], []
    for repo in repos:
        try:
            deleted, total = plan_repo(registry, repo, cutoff, args.keep, args.workers)
        except Exception as e:
            errors.append(f"{registry}/{repo}: {e}")
            print(f"{repo}: ERROR, skipped ({e})")
            continue
        if deleted:
            size = sum(m.get("imageSize") or 0 for m in deleted) / 1024 ** 3
            print(f"{repo}: {len(deleted)}/{total} to delete (~{size:,.2f} GB)")
            for m in deleted:
                print(f"   {(m.get('lastUpdateTime') or '')[:16]}  {m['digest'][:19]}  {' '.join(m.get('tags') or []) or '-'}")
        plan.extend((repo, m) for m in deleted)

    print(f"{registry} TOTAL: {len(plan)} manifests to delete in {len(repos)} repositories")

    if args.execute and plan:
        def delete(item):
            repo, m = item
            try:
                az("acr", "manifest", "delete", "--registry", registry, "--name", f"{repo}@{m['digest']}", "--yes")
            except Exception as e:
                if "MANIFEST_UNKNOWN" not in str(e) and "not found" not in str(e).lower():
                    return f"{registry}/{repo}@{m['digest']}: {e}"

        # multi-arch indexes first, so no index is ever left pointing to a deleted platform manifest
        indexes = [p for p in plan if p[1].get("mediaType") in INDEX_MEDIA_TYPES]
        others = [p for p in plan if p[1].get("mediaType") not in INDEX_MEDIA_TYPES]
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            failed = [e for phase in (indexes, others) for e in ex.map(delete, phase) if e]
        errors += failed
        print(f"{registry} deleted: {len(plan) - len(failed)} | Errors: {len(failed)}")
    elif not args.execute:
        print(f"{registry} DRY-RUN: nothing deleted, pass --execute to delete.")
    return errors


def main():
    ap = argparse.ArgumentParser(description="Purge old ACR images (default: dry-run).")
    ap.add_argument("--registry", required=True, help="registry name, or comma-separated list of registries")
    ap.add_argument("--keep", type=int, default=10, help="most recent tagged images to keep per repository")
    ap.add_argument("--ago-days", type=float, default=1, help="minimum age in days to delete an image")
    ap.add_argument("--repo-filter", default=".*", help="regex on repository names (default: all)")
    ap.add_argument("--workers", type=int, default=8, help="parallel az calls")
    ap.add_argument("--execute", action="store_true", help="really delete (otherwise dry-run)")
    args = ap.parse_args()
    registries = list(dict.fromkeys(r.strip() for r in args.registry.split(",") if r.strip()))
    if not registries:
        ap.error("--registry must contain at least one registry name")
    if args.keep < 0 or args.ago_days < 0:
        ap.error("--keep and --ago-days must be >= 0")

    az_login()
    cutoff = datetime.now(timezone.utc) - timedelta(days=args.ago_days)

    # errors on single repositories/manifests are only reported, the runbook fails only
    # when a whole registry cannot be read (wrong name, missing permissions, ...)
    warnings, failed_registries = [], []
    for registry in registries:
        try:
            warnings += purge_registry(registry, args, cutoff)
        except Exception as e:
            failed_registries.append(f"{registry}: {e}")
            print(f"{registry}: ERROR, registry skipped ({e})")

    for w in warnings:
        print(f"WARNING {w}")
    for e in failed_registries:
        print(f"ERROR {e}")
    print(f"Registries: {len(registries) - len(failed_registries)}/{len(registries)} processed | "
          f"Warnings: {len(warnings)}")
    return 1 if failed_registries else 0


if __name__ == "__main__":
    sys.exit(main())
