#!/opt/icinga-plugins/venv/bin/python3
# Python of the plugins virtualenv, with pymongo (icinga-configure.sh)
# usage: check_cosmos_mongo -i <resource id> -H <host> -m <MSI client id> [-w <ms>] [-c <ms>]
# Connects to the Mongo endpoint (TLS, port 10255) with the read-only key of the
# account, then runs ping and listDatabases. The thresholds apply to the query
# time (listDatabases) only: connect (TLS, replica set discovery, SCRAM) is paid
# by every check, a new client each time, and is reported as perfdata only.
# The key is read from ARM with the managed identity and cached for CACHE_TTL, a
# cached key rejected by Cosmos (rotated) is read again once
import argparse
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import warnings

OK, WARNING, CRITICAL, UNKNOWN = 0, 1, 2, 3
STATES = ["OK", "WARNING", "CRITICAL", "UNKNOWN"]

CACHE_DIR = "/var/cache/icinga2/cosmos-check"
CACHE_TTL = 6 * 3600
ARM_API_VERSION = "2024-11-15"
TIMEOUT_MS = 10000
# authentication failed / unauthorized
AUTH_ERROR_CODES = {13, 18}

ID_RE = re.compile(
    r"^/subscriptions/[0-9a-f-]{36}/resourceGroups/[A-Za-z0-9._()-]+"
    r"/providers/Microsoft\.DocumentDB/databaseAccounts/([a-z0-9-]{3,44})$",
    re.IGNORECASE,
)


def finish(status, message, perfdata=""):
    print(f"{STATES[status]} - {message}" + (f" | {perfdata}" if perfdata else ""))
    sys.exit(status)


# printed by pymongo on stderr for every Cosmos host, Icinga would show it in the output
warnings.filterwarnings("ignore", message="You appear to be connected to a CosmosDB cluster")

try:
    from pymongo import MongoClient
    from pymongo.errors import ConfigurationError, OperationFailure, PyMongoError
except ImportError:
    finish(UNKNOWN, "pymongo is not installed in the plugins virtualenv")


def cache_path(resource_id):
    return os.path.join(CACHE_DIR, hashlib.sha256(resource_id.lower().encode()).hexdigest())


def cached_key(resource_id):
    path = cache_path(resource_id)
    try:
        if time.time() - os.path.getmtime(path) < CACHE_TTL:
            with open(path) as f:
                return f.read().strip() or None
    except OSError:
        pass
    return None


def arm_key(resource_id, client_id):
    """read-only key from ARM, UNKNOWN on failure: a monitoring problem, not a Cosmos one"""
    try:
        query = urllib.parse.urlencode({
            "api-version": "2018-02-01",
            "resource": "https://management.azure.com/",
            "client_id": client_id,
        })
        req = urllib.request.Request(
            f"http://169.254.169.254/metadata/identity/oauth2/token?{query}",
            headers={"Metadata": "true"},
        )
        with urllib.request.urlopen(req, timeout=10) as r:
            token = json.load(r)["access_token"]

        req = urllib.request.Request(
            f"https://management.azure.com{resource_id}/readonlykeys?api-version={ARM_API_VERSION}",
            data=b"",
            method="POST",
            headers={"Authorization": f"Bearer {token}"},
        )
        with urllib.request.urlopen(req, timeout=20) as r:
            key = json.load(r)["primaryReadonlyMasterKey"]
    except urllib.error.HTTPError as e:
        finish(UNKNOWN, f"cannot read the read-only key from {e.url.split('?')[0]}: HTTP {e.code}")
    except (urllib.error.URLError, OSError, ValueError, KeyError) as e:
        finish(UNKNOWN, f"cannot read the read-only key: {e}")

    # without cache the key is read at every check
    try:
        tmp = f"{cache_path(resource_id)}.{os.getpid()}"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(key)
        os.replace(tmp, cache_path(resource_id))
    except OSError:
        pass
    return key


def round_trip(host, account, key):
    """connect + ping and listDatabases times in ms, number of databases"""
    client = MongoClient(
        host,
        10255,
        username=account,
        password=key,
        tls=True,
        replicaSet="globaldb",
        retryWrites=False,
        appName=f"@{account}@",
        serverSelectionTimeoutMS=TIMEOUT_MS,
        connectTimeoutMS=TIMEOUT_MS,
        socketTimeoutMS=TIMEOUT_MS,
    )
    try:
        start = time.monotonic()
        # server selection, TLS handshake and authentication happen here
        client.admin.command("ping")
        connected = time.monotonic()
        databases = client.list_database_names()
        end = time.monotonic()
    finally:
        client.close()
    return (connected - start) * 1000, (end - connected) * 1000, len(databases)


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-i", dest="resource_id", required=True)
    parser.add_argument("-H", dest="host", required=True)
    parser.add_argument("-m", dest="client_id", required=True)
    parser.add_argument("-w", dest="warning", type=int, default=500)
    parser.add_argument("-c", dest="critical", type=int, default=2000)
    try:
        args = parser.parse_args()
    except SystemExit:
        finish(UNKNOWN, "usage: check_cosmos_mongo -i <resource id> -H <host> -m <MSI client id> [-w <ms>] [-c <ms>]")

    match = ID_RE.match(args.resource_id)
    if not match or not re.match(r"^[a-z0-9.-]+$", args.host):
        finish(UNKNOWN, "invalid resource id or host")
    account = match.group(1).lower()

    key = cached_key(args.resource_id)
    from_cache = key is not None
    if not from_cache:
        key = arm_key(args.resource_id, args.client_id)

    try:
        try:
            connect_ms, query_ms, databases = round_trip(args.host, account, key)
        except OperationFailure as e:
            if not (from_cache and e.code in AUTH_ERROR_CODES):
                raise
            # key rotated since it was cached
            key = arm_key(args.resource_id, args.client_id)
            connect_ms, query_ms, databases = round_trip(args.host, account, key)
    except ConfigurationError as e:
        # e.g. server version not supported by the driver: a monitoring problem
        finish(UNKNOWN, f"{args.host}: {str(e).splitlines()[0][:300]}")
    except PyMongoError as e:
        finish(CRITICAL, f"{args.host}: {str(e).splitlines()[0][:300]}")

    total_ms = connect_ms + query_ms
    if query_ms >= args.critical:
        status = CRITICAL
    elif query_ms >= args.warning:
        status = WARNING
    else:
        status = OK
    finish(
        status,
        f"{args.host}: {databases} databases, query {query_ms:.0f} ms (connect {connect_ms:.0f} ms, total {total_ms:.0f} ms)",
        f"query={query_ms:.0f}ms;{args.warning};{args.critical};0 connect={connect_ms:.0f}ms;;;0 total={total_ms:.0f}ms;;;0",
    )


main()
