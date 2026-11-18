import fcntl
import re
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
FORBIDDEN_VALUE_CHARS = set(";&=#\n\r")


class BpFileNotFound(Exception):
    pass


class BpFileCorrupted(Exception):
    pass


def validate_identifier(value: str, what: str) -> None:
    if not NAME_RE.fullmatch(value) or value in (".", ".."):
        raise ValueError(f"invalid {what}: allowed characters are A-Z a-z 0-9 _ . -")


def validate_value(value: str, what: str) -> None:
    if not value or not value.strip():
        raise ValueError(f"{what} must not be empty")
    if any(c in FORBIDDEN_VALUE_CHARS for c in value):
        raise ValueError(f"{what} must not contain any of ; & = # or newlines")


def build_section(target: str, host: str, blocks: list[tuple[str, str]]) -> str:
    by_domain: dict[str, list[str]] = {}
    for domain, name in blocks:
        pair = f"{host};{name}"
        pairs = by_domain.setdefault(domain, [])
        if pair not in pairs:
            pairs.append(pair)
    lines = [f"# begin {target} section"]
    lines += [f"{target}_{d} = {' & '.join(p)}" for d, p in by_domain.items()]
    lines.append(f"# end {target} section")
    return "\n".join(lines) + "\n"


def replace_section(content: str, target: str, section: str) -> str:
    begin = f"# begin {target} section"
    end = f"# end {target} section"
    lines = content.splitlines(keepends=True)
    starts = [i for i, l in enumerate(lines) if l.strip() == begin]
    if not starts:
        if any(l.strip() == end for l in lines):
            raise BpFileCorrupted(f"'{end}' found without '{begin}'")
        base = content if not content or content.endswith("\n") else content + "\n"
        return base + ("\n" if base else "") + section
    if len(starts) > 1:
        raise BpFileCorrupted(f"multiple '{begin}' markers found")
    s = starts[0]
    e = next((i for i in range(s + 1, len(lines)) if lines[i].strip() == end), None)
    if e is None:
        raise BpFileCorrupted(f"'{begin}' found without '{end}'")
    return "".join(lines[:s]) + section + "".join(lines[e + 1 :])


def update_bp_file(
    config_dir: Path, bp: str, target: str, host: str, blocks: list[tuple[str, str]]
) -> None:
    path = config_dir / f"{bp}.conf"
    if not path.is_file():
        raise BpFileNotFound(f"business process '{bp}' not found")
    section = build_section(target, host, blocks)
    # in-place rewrite: the service only has write access to the file itself
    with open(path, "r+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            new = replace_section(f.read(), target, section)
            f.seek(0)
            f.write(new)
            f.truncate()
            f.flush()
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
