import argparse
import logging
import os
import re
import requests
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from datetime import datetime
from zoneinfo import ZoneInfo

ROME = ZoneInfo("Europe/Rome")
ENDPOINT = "/api/nodo-monitoring/cache/version"
SECRET_NAME = "nodo-technical-support-subkey"


def load_config():
  parser = argparse.ArgumentParser(description="Check NDP cache alignment")
  parser.add_argument("--base-url", required=True)
  base_url = parser.parse_known_args()[0].base_url.strip()
  env_short = (os.getenv("CLOUDO_ENVIRONMENT_SHORT") or "").strip()

  missing = []
  if not env_short:
    missing.append("env CLOUDO_ENVIRONMENT_SHORT")
  if not base_url:
    missing.append("--base-url")
  if missing:
    raise ValueError(f"missing required parameters: {', '.join(missing)}")
  return env_short, base_url.rstrip("/")


def get_subscription_key(env_short):
  kv_uri = f"https://pagopa-{env_short}-nodo-kv.vault.azure.net"
  client = SecretClient(vault_url=kv_uri, credential=DefaultAzureCredential())
  return client.get_secret(SECRET_NAME).value


def parse_timestamp(value, source):
  # Handles Java ZonedDateTime format ("...+01:00[Europe/Rome]") and a trailing "Z".
  if not isinstance(value, str) or not value:
    raise ValueError(f"{source}: missing timestamp")
  text = re.sub(r"\[[^\]]+\]$", "", value.strip())
  if text.endswith("Z"):
    text = text[:-1] + "+00:00"
  try:
    timestamp = datetime.fromisoformat(text)
  except ValueError as exc:
    raise ValueError(f"{source}: invalid timestamp {value!r}") from exc
  if timestamp.tzinfo is None:
    raise ValueError(f"{source}: timestamp must include an offset")
  return timestamp


def require(obj, key, source):
  value = obj.get(key)
  if not isinstance(value, str) or not value.strip():
    raise ValueError(f"{source}: missing or empty {key!r}")
  return value


def fetch_status(base_url, subscription_key):
  response = requests.get(base_url + ENDPOINT, headers={
    "Ocp-Apim-Subscription-Key": subscription_key}, timeout=(5, 15))
  response.raise_for_status()
  payload = response.json()
  if not isinstance(payload, dict):
    raise ValueError("expected a JSON object")
  return payload


def check(payload, execution_time):
  errors = []
  today = execution_time.date()

  cache = payload.get("cache")
  if not isinstance(cache, dict):
    raise ValueError("missing 'cache' object")
  nodes = payload.get("nodes")
  if not isinstance(nodes, list) or not nodes:
    raise ValueError("missing or empty 'nodes' list")

  if cache.get("outcome") != "OK":
    errors.append(f"cache: outcome={cache.get('outcome')!r}")

  cache_date = parse_timestamp(cache.get("timestamp"), "cache").astimezone(
    ROME).date()
  if cache_date != today:
    errors.append(
      f"cache: date {cache_date} differs from execution date {today} (Europe/Rome)"
    )

  cache_id = require(cache, "cacheId", "cache")

  for index, node in enumerate(nodes):
    if not isinstance(node, dict):
      errors.append(f"nodes[{index}]: expected an object")
      continue
    name = node.get("node") or f"nodes[{index}]"
    if node.get("outcome") != "OK":
      errors.append(f"{name}: outcome={node.get('outcome')!r}")
    if node.get("dbStatus") != "UP":
      errors.append(f"{name}: dbStatus={node.get('dbStatus')!r}")
    node_cache_id = node.get("cacheId")
    if node_cache_id != cache_id:
      errors.append(
        f"{name}: cacheId {node_cache_id!r} differs from cache {cache_id!r}")

  if errors:
    raise ValueError("; ".join(errors))

  logging.info(
    "Checks passed: date=%s, cacheId=%s, nodes=%s",
    today,
    cache_id,
    ", ".join(f"{n.get('node')}={n.get('version')}" for n in nodes),
  )


def main():
  env_short, base_url = load_config()
  execution_time = datetime.now(ROME)
  payload = fetch_status(base_url, get_subscription_key(env_short))
  check(payload, execution_time)
  print("SUCCESS: cache and nodes aligned (cacheId=" + payload["cache"][
    "cacheId"] + ")")


if __name__ == "__main__":
  logging.basicConfig(level=logging.INFO,
                      format="%(asctime)s %(levelname)s %(message)s")
  try:
    main()
  except Exception:
    logging.exception("Verification failed")
    raise SystemExit(1)
