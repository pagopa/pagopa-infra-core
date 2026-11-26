import logging
import os
from pathlib import Path

from fastapi import FastAPI, HTTPException, Response
from pydantic import BaseModel

from . import bpfile

DEFAULT_CONFIG_DIR = "/etc/icingaweb2/modules/businessprocess/processes/"

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s %(message)s")
logger = logging.getLogger("bp-api")
# no interactive docs nor OpenAPI schema: the service is reachable on the private IP
app = FastAPI(title="Icinga business process API", docs_url=None, redoc_url=None, openapi_url=None)


class Block(BaseModel):
    domain: str
    name: str


class BlocksRequest(BaseModel):
    blocks: list[Block]
    host: str


def config_dir() -> Path:
    return Path(os.environ.get("BP_CONFIG_DIR", DEFAULT_CONFIG_DIR))


def for_log(value: str) -> str:
    """Path parameters are logged also when invalid: escape line breaks so a
    request cannot forge log lines (log injection)"""
    return value.replace("\\", "\\\\").replace("\r", "\\r").replace("\n", "\\n")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/business-process/{bp}/block/{target}")
def put_block(bp: str, target: str, body: BlocksRequest) -> Response:
    try:
        bpfile.validate_identifier(bp, "bp")
        bpfile.validate_identifier(target, "target")
        bpfile.validate_value(body.host, "host")
        if not body.blocks:
            raise ValueError("blocks must not be empty")
        for b in body.blocks:
            # part of the node name "<target>_<domain>"
            bpfile.validate_identifier(b.domain, "domain")
            bpfile.validate_value(b.name, "name")
        bpfile.update_bp_file(
            config_dir(), bp, target, body.host, [(b.domain, b.name) for b in body.blocks]
        )
    except (ValueError, bpfile.BpFileNotFound) as e:
        logger.warning("bp=%s target=%s result=400 reason=%s", for_log(bp), for_log(target), e)
        raise HTTPException(status_code=400, detail=str(e))
    except Exception:
        logger.exception("bp=%s target=%s result=500", for_log(bp), for_log(target))
        # details only in the log, never in the response
        raise HTTPException(status_code=500, detail="internal error")
    # bp and target are validated here
    logger.info("bp=%s target=%s result=200 blocks=%d", bp, target, len(body.blocks))
    return Response(status_code=200)
