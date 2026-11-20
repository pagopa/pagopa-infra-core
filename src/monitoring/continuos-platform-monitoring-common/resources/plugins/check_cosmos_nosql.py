#!/usr/bin/env python3
# usage: check_cosmos_nosql -H <host> -m <MSI client id> [-w <ms>] [-c <ms>]
# Cosmos DB for NoSQL: authenticated round trip on the gateway (GET /dbs, list of
# the databases) with an Entra ID token of the managed identity of the VM. The
# identity only has readMetadata on the account (data-plane role created by
# continuos-platform-monitoring-app): it lists the databases, it can't read data.
# The thresholds apply to the time of the request (TLS included, token excluded)
import argparse
import json
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from email.utils import formatdate

OK, WARNING, CRITICAL, UNKNOWN = 0, 1, 2, 3
STATES = ["OK", "WARNING", "CRITICAL", "UNKNOWN"]

API_VERSION = "2018-12-31"
TIMEOUT_S = 10

HOST_RE = re.compile(r"^[a-z0-9-]{3,44}\.documents\.azure\.com$")


def finish(status, message, perfdata=""):
    print(f"{STATES[status]} - {message}" + (f" | {perfdata}" if perfdata else ""))
    sys.exit(status)


def token(client_id):
    """Entra ID token for Cosmos DB, UNKNOWN on failure: a monitoring problem, not a Cosmos one"""
    try:
        query = urllib.parse.urlencode({
            "api-version": "2018-02-01",
            "resource": "https://cosmos.azure.com",
            "client_id": client_id,
        })
        req = urllib.request.Request(
            f"http://169.254.169.254/metadata/identity/oauth2/token?{query}",
            headers={"Metadata": "true"},
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.load(r)["access_token"]
    except urllib.error.HTTPError as e:
        finish(UNKNOWN, f"cannot get a token from the identity endpoint: HTTP {e.code}")
    except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
        finish(UNKNOWN, f"cannot get a token from the identity endpoint: {e}")


def error_message(e):
    """message of a Cosmos error response, first line only"""
    try:
        body = json.loads(e.read().decode())
        message = str(body.get("message", "")).splitlines()[0]
    except (ValueError, AttributeError, IndexError, OSError):
        message = ""
    return f"HTTP {e.code}" + (f": {message[:300]}" if message else "")


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-H", dest="host", required=True)
    parser.add_argument("-m", dest="client_id", required=True)
    parser.add_argument("-w", dest="warning", type=int, default=500)
    parser.add_argument("-c", dest="critical", type=int, default=2000)
    try:
        args = parser.parse_args()
    except SystemExit:
        finish(UNKNOWN, "usage: check_cosmos_nosql -H <host> -m <MSI client id> [-w <ms>] [-c <ms>]")

    if not HOST_RE.match(args.host):
        finish(UNKNOWN, f"invalid host: {args.host}")

    req = urllib.request.Request(
        f"https://{args.host}/dbs",
        headers={
            "Authorization": urllib.parse.quote(f"type=aad&ver=1.0&sig={token(args.client_id)}", safe=""),
            "x-ms-date": formatdate(usegmt=True),
            "x-ms-version": API_VERSION,
            "Accept": "application/json",
        },
    )

    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_S) as r:
            body = json.load(r)
            charge = r.headers.get("x-ms-request-charge", "")
        elapsed_ms = (time.monotonic() - start) * 1000
        databases = int(body.get("_count", len(body.get("Databases", []))))
    except urllib.error.HTTPError as e:
        # 401: role not assigned (yet), 403: VM not allowed by the firewall or missing permission
        finish(CRITICAL, f"{args.host}: {error_message(e)}")
    except (urllib.error.URLError, OSError, ValueError) as e:
        finish(CRITICAL, f"{args.host}: {e}")

    if elapsed_ms >= args.critical:
        status = CRITICAL
    elif elapsed_ms >= args.warning:
        status = WARNING
    else:
        status = OK

    perfdata = f"time={elapsed_ms:.0f}ms;{args.warning};{args.critical};0"
    try:
        perfdata += f" request_charge={float(charge):.2f};;;0"
    except ValueError:
        pass
    finish(status, f"{args.host}: {databases} databases, {elapsed_ms:.0f} ms", perfdata)


main()
