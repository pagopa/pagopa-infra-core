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
- `200` with empty body on success, `400` for invalid input (empty fields, `;&=#` or newlines in values,
  `bp`/`target` outside `[A-Za-z0-9_.-]`, `<bp>.conf` not found - it is never created), `500` on internal errors
  (e.g. corrupted markers in the file).
- **Deviation from the original spec**: errors use the FastAPI format `{"detail": "..."}`,
  and malformed bodies return FastAPI's default `422`.

`GET /health` returns `{"status": "ok"}`.

## Configuration (environment)

| Variable        | Default                                                |
|-----------------|--------------------------------------------------------|
| `BP_CONFIG_DIR` | `/etc/icingaweb2/modules/businessprocess/processes/`   |
| `BP_API_HOST`   | `127.0.0.1`                                            |
| `BP_API_PORT`   | `8080`                                                 |

The service has **no authentication**: keep it internal-only (default bind is localhost; exposing it on other
interfaces must be network-restricted).

## Write strategy

The file is rewritten in place under `flock` (no temp file, since the service user only has write access to the
`<bp>.conf` file, not to the directory). A reader could theoretically see a partial file for a very short time.

## Terraform interaction

`02_vm_command.tf` writes the same `<bp>.conf` and replaces it completely on change: **every `terraform apply`
that changes the business process content wipes the API-written sections** until callers POST again.

## Deployment

`../03_bp_api.tf` installs it on the Icinga VM via `az vm run-command` (idempotent, re-run when sources change):
user `bp-api` (member of `icingaweb2`), venv in `/opt/bp-api`, `/etc/default/bp-api` (created once),
systemd unit `bp-api.service` (sandboxed), `<bp>.conf` set to `root:icingaweb2 0660`.
Requires `python3` with `venv` and PyPI access on the VM. Logs: `journalctl -u bp-api`.

## Development

```
python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt
.venv/bin/python -m pytest
BP_CONFIG_DIR=/tmp/bp .venv/bin/uvicorn app.main:app
```
