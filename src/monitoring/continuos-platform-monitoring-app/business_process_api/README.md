# Business Process API

REST API (FastAPI) that edits Icinga business process files (`<bp>.conf`).

## Endpoint

`POST /business-process/{bp}/block/{target}`

```json
{ "blocks": [{ "domain": "string", "name": "string" }], "host": "string" }
```

Blocks are grouped by `domain` (duplicate pairs removed, request order kept) and written to `<bp>.conf` as:

```
# begin <target> section
<target>_<domain> = <host>;<name> & <host>;<name>
# end <target> section
```

- First call for a target: the section is appended at the end of the file.
- Subsequent calls: the whole section is replaced; the rest of the file is untouched.
- `200` with empty body on success, `400` for invalid input, `500` on internal errors (e.g. corrupted markers in
  the file). Invalid input:
  - `bp`, `target` and `domain` (part of the node name `<target>_<domain>`) outside `[A-Za-z0-9_.-]`;
  - `host` and `name` outside `[A-Za-z0-9_.:-]{1,255}`: an allow-list, so no operator of the businessprocess syntax
    (`& | + ! % ^`, escape `\`; a mixed operator breaks the parsing of the **whole** file), no `; = #`, no line
    separator of any kind;
  - `<bp>.conf` not found, or not a regular file directly inside `BP_CONFIG_DIR` (symlinks pointing elsewhere
    included): it is never created.
- The file is split into lines on `\n` only, like the businessprocess parser (Python's `splitlines` would also
  split on ` `, used by Terraform in the node titles, `\x85`, ...).
- Path parameters are logged with line breaks escaped (no forged log lines).
- **Deviation from the original spec**: errors use the FastAPI format `{"detail": "..."}`,
  and malformed bodies return FastAPI's default `422`.

`GET /health` returns `{"status": "ok"}`.

- `500` responses carry only `{"detail": "internal error"}`: the details are in the log.
- No interactive docs nor OpenAPI schema (`/docs`, `/redoc`, `/openapi.json` return `404`).

## Configuration (environment)

| Variable        | Value                                                                       |
|-----------------|-----------------------------------------------------------------------------|
| `BP_CONFIG_DIR` | `/etc/icingaweb2/modules/businessprocess/processes/` (default in the code)  |
| `BP_API_HOST`   | `127.0.0.1` (`deploy/bp-api.conf`)                                          |
| `BP_API_PORT`   | `8080` (`deploy/bp-api.conf`)                                               |
| `BP_API_TOKEN`  | Bearer token of the clients (`/etc/bp-api/token`, from the key vault)       |

The service listens on localhost only. Clients reach it through the Apache reverse proxy of the Icinga VM
(`icinga-configure.sh`), over HTTPS with the Let's Encrypt certificate of Icinga Web:
`https://<icinga fqdn>/bp-api/<path>` is forwarded to `http://127.0.0.1:8080/<path>`, e.g.
`POST https://<icinga fqdn>/bp-api/business-process/<bp>/block/synthetic`.

## Authentication

`POST /business-process/...` requires `Authorization: Bearer <token>`, compared in constant time with
`BP_API_TOKEN`; `GET /health` is open.

- `401` (with `WWW-Authenticate: Bearer`) for a missing or wrong token, checked before the body is validated;
- `503` for every request when `BP_API_TOKEN` is not configured (fails closed).

The token is the key vault secret `icinga-bp-api-token` (created by hand, e.g. `openssl rand -hex 32`), read by
`../03_bp_api.tf` and by azure-synthetic-monitoring (`BP_API_TOKEN`). On the VM it is in `/etc/bp-api/token`
(`root`, `0600`), a second `EnvironmentFile` of the unit, read by systemd before dropping the privileges: the service
does not start without it. A network restriction (`Require ip` on the proxy) can still be added.

## Write strategy

The file is rewritten in place under `flock` (no temp file, since the service user only has write access to the
`<bp>.conf` file, not to the directory). A reader could theoretically see a partial file for a very short time.

## Terraform interaction

`02_vm_command.tf` writes the same `<bp>.conf` and replaces it completely on change: **every `terraform apply`
that changes the business process content wipes the API-written sections** until callers POST again.

Every domain node written by Terraform references `synthetic_<domain>` (`local.bp_synthetic_target`): the node is
defined by azure-synthetic-monitoring calling `POST /business-process/<bp>/block/synthetic` with the same domain
names. The businessprocess module fails to parse the whole file on a reference to an undefined node, so:

- Terraform writes the `synthetic` section with an empty node (`synthetic_<domain> =`, state EMPTY, does not affect
  the domain) for every domain;
- on every call the API also defines as empty every `<target>_*` node referenced outside its section but without
  blocks in the request.

## Deployment

`../03_bp_api.tf` installs it on the Icinga VM via `az vm run-command` (idempotent, re-run when sources or token change or the VM is recreated - `vmId` - after the business process file):
user `bp-api` (member of `icingaweb2`), venv in `/opt/bp-api`, `/etc/default/bp-api` (rewritten from `deploy/bp-api.conf`), `/etc/bp-api/token` (run command protected parameter),
systemd unit `bp-api.service` (sandboxed), `<bp>.conf` set to `root:icingaweb2 0660`.
Requires `python3` with `venv` (from the image) and PyPI access on the VM. Logs: `journalctl -u bp-api`.

Dependencies are pinned with hashes and installed with `pip install --require-hashes --no-deps --only-binary :all:`:
edit only the `.in` files, then regenerate (same Python as the VM, 3.14):

```
pip install pip-tools
pip-compile --generate-hashes --strip-extras --no-emit-index-url requirements.in
pip-compile --generate-hashes --strip-extras --no-emit-index-url requirements-dev.in
```

## Development

```
python3 -m venv .venv && .venv/bin/pip install --require-hashes -r requirements-dev.txt
.venv/bin/python -m pytest
BP_CONFIG_DIR=/tmp/bp .venv/bin/uvicorn app.main:app
```
