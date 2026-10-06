#!/usr/bin/env python3
"""
Fetch the monthly carbon emission summary for one or more subscriptions from the
Azure Carbon Optimization API and consolidate it into the dashboard data files:

    <out>/index.json              manifest (fields not managed here are kept)
    <out>/<slug>/latest.json      { "value": [MonthlySummaryData, ...] }

The subscriptions passed (default: AZURE_SUBSCRIPTION_ID, i.e. the subscription of
the ClouDO instance running it) are aggregated by the API into a single series,
published under one slug. Subscription ids are never written to the output: the
site is public.

The API only serves a rolling window of recent months, so the published series is
merged, never replaced: months the API still returns are overwritten (Azure restates
them), months that have left the window are kept as last downloaded. Every record
carries `retrievedAt`, the day it was last refreshed from the API. --replace drops
the published history and keeps only what the API returns now.

Runs as a ClouDO runbook (monthly schedule in env/<env>/schedules.json.tpl) with
the ClouDO managed identity. All Azure access goes through DefaultAzureCredential:
the caller needs "Carbon Optimization Reader" on every subscription and, with
--storage-account, "Storage Blob Data Contributor" on the account (RBAC, no keys).

Local run, e.g. to preview the dashboard with fresh data (from src/carbon-dashboard/cdn_assets):

    pip install azure-identity azure-storage-blob
    python ../../cloudo/cloudo-core/runbooks/carbon/fetch_carbon_report.py <sub-id> [<sub-id> ...] --out public/data
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date, datetime, timezone
from pathlib import Path

from azure.identity import DefaultAzureCredential

ARM = "https://management.azure.com"
API_VERSION = "2025-04-01"
SCOPES = ["Scope1", "Scope2", "Scope3"]
# The API rejects monthly-summary ranges longer than a year.
MAX_MONTHS_PER_CALL = 12


def post(credential: DefaultAzureCredential, path: str, body: dict) -> dict:
    token = credential.get_token(f"{ARM}/.default").token
    req = urllib.request.Request(
        f"{ARM}{path}?api-version={API_VERSION}",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        sys.exit(f"{path}: HTTP {e.code}: {e.read().decode(errors='replace')}")


def parse_month(value: str) -> date:
    return date.fromisoformat(value[:10]).replace(day=1)


def add_months(d: date, months: int) -> date:
    m = d.month - 1 + months
    return date(d.year + m // 12, m % 12 + 1, 1)


def available_range(credential: DefaultAzureCredential) -> tuple[date, date]:
    r = post(credential, "/providers/Microsoft.Carbon/queryCarbonEmissionDataAvailableDateRange", {})
    return parse_month(r["startDate"]), parse_month(r["endDate"])


def fetch_monthly(credential: DefaultAzureCredential, subscriptions: list[str], start: date, end: date) -> list[dict]:
    """Every MonthlySummaryData record in [start, end], one per month, oldest first."""
    by_date: dict[str, dict] = {}
    chunk_start = start
    while chunk_start <= end:
        chunk_end = min(add_months(chunk_start, MAX_MONTHS_PER_CALL - 1), end)
        body = {
            "reportType": "MonthlySummaryReport",
            "subscriptionList": subscriptions,
            "carbonScopeList": SCOPES,
            "dateRange": {"start": chunk_start.isoformat(), "end": chunk_end.isoformat()},
        }
        while True:
            page = post(credential, "/providers/Microsoft.Carbon/carbonEmissionReports", body)
            for record in page.get("value", []):
                if record.get("dataType") == "MonthlySummaryData":
                    by_date[record["date"][:10]] = {**record, "date": record["date"][:10]}
            if not page.get("skipToken"):
                break
            body["skipToken"] = page["skipToken"]
        chunk_start = add_months(chunk_end, 1)
    return [by_date[d] for d in sorted(by_date)]


def merge_records(published: list[dict], fresh: list[dict], retrieved_at: str) -> list[dict]:
    """Published history overlaid with the freshly fetched months, oldest first."""
    by_date = {
        r["date"][:10]: r
        for r in published
        if r.get("dataType") == "MonthlySummaryData" and isinstance(r.get("date"), str)
    }
    for record in fresh:
        by_date[record["date"]] = {**record, "retrievedAt": retrieved_at}
    return [by_date[d] for d in sorted(by_date)]


def merge_manifest(manifest: dict, slug: str, name: str) -> dict:
    entry = {"slug": slug, "name": name, "file": f"{slug}/latest.json"}
    # "subscriptions" is the former name of "series": migrated on the next write.
    manifest = dict(manifest)
    previous = manifest.pop("subscriptions", [])
    others = [s for s in manifest.get("series", previous) if s.get("slug") != slug]
    return {
        **manifest,
        "generatedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "emissionsUnit": "kgCO2e",
        "carbonScope": ", ".join(SCOPES),
        "series": [entry, *others],
    }


def dumps(obj: dict) -> bytes:
    return (json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode()


def read_local(out: Path, slug: str) -> list[dict]:
    path = out / slug / "latest.json"
    return json.loads(path.read_text()).get("value", []) if path.exists() else []


def write_local(out: Path, slug: str, name: str, report: dict) -> None:
    index_path = out / "index.json"
    manifest = json.loads(index_path.read_text()) if index_path.exists() else {}
    (out / slug).mkdir(parents=True, exist_ok=True)
    (out / slug / "latest.json").write_bytes(dumps(report))
    index_path.write_bytes(dumps(merge_manifest(manifest, slug, name)))
    print(f"Written {out / slug / 'latest.json'} and {index_path}")


def web_container(credential: DefaultAzureCredential, account: str):
    from azure.storage.blob import BlobServiceClient

    return BlobServiceClient(f"https://{account}.blob.core.windows.net", credential=credential).get_container_client("$web")


def download_json(container, name: str) -> dict:
    from azure.core.exceptions import ResourceNotFoundError

    try:
        return json.loads(container.download_blob(name).readall())
    except ResourceNotFoundError:
        return {}


def read_remote(container, slug: str) -> list[dict]:
    return download_json(container, f"data/{slug}/latest.json").get("value", [])


def upload(container, account: str, slug: str, name: str, report: dict) -> None:
    from azure.storage.blob import ContentSettings

    manifest = download_json(container, "data/index.json")

    settings = ContentSettings(content_type="application/json; charset=utf-8")
    # Report first: the manifest must never point to a file that is not there yet.
    container.upload_blob(f"data/{slug}/latest.json", dumps(report), overwrite=True, content_settings=settings)
    container.upload_blob("data/index.json", dumps(merge_manifest(manifest, slug, name)), overwrite=True, content_settings=settings)
    print(f"Uploaded data/{slug}/latest.json and data/index.json to {account}/$web")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("subscriptions", nargs="*", metavar="SUBSCRIPTION_ID", help="default: AZURE_SUBSCRIPTION_ID")
    parser.add_argument("--slug", default="pagopa-platform")
    parser.add_argument("--name", default="pagoPA platform")
    parser.add_argument("--start", type=parse_month, help="first month, YYYY-MM-01 (default: oldest available)")
    parser.add_argument("--end", type=parse_month, help="last month, YYYY-MM-01 (default: newest available)")
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--out", type=Path, default=Path("data"), help="local data directory (default: ./data)")
    target.add_argument("--storage-account", help="write straight to the static website of this account")
    parser.add_argument("--replace", action="store_true", help="drop the published history instead of merging into it")
    args = parser.parse_args()
    subscriptions = args.subscriptions or [s for s in [os.environ.get("AZURE_SUBSCRIPTION_ID")] if s]
    if not subscriptions:
        parser.error("pass the subscription ids or set AZURE_SUBSCRIPTION_ID")
    print(f"Aggregating {len(subscriptions)} subscription(s)")

    credential = DefaultAzureCredential()

    first, last = available_range(credential)
    start, end = max(args.start or first, first), min(args.end or last, last)
    if start > end:
        sys.exit(f"No data in the requested range (available: {first} -> {last})")

    records = fetch_monthly(credential, subscriptions, start, end)
    if not records:
        sys.exit(f"The API returned no monthly records for {start} -> {end}")
    print(f"Fetched {len(records)} months, {records[0]['date']} -> {records[-1]['date']}")

    container = web_container(credential, args.storage_account) if args.storage_account else None
    published = [] if args.replace else (read_remote(container, args.slug) if container else read_local(args.out, args.slug))
    merged = merge_records(published, records, date.today().isoformat())
    kept = len(merged) - len(records)
    print(f"Publishing {len(merged)} months, {merged[0]['date']} -> {merged[-1]['date']} ({kept} kept from history)")

    report = {"value": merged}
    if container:
        upload(container, args.storage_account, args.slug, args.name, report)
    else:
        write_local(args.out, args.slug, args.name, report)
