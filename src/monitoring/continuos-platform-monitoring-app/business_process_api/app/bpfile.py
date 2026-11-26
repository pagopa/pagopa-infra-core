import fcntl
import re
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
FORBIDDEN_VALUE_CHARS = set(";&=#\n\r")
# "<node> = <expression>" (display/info_url/... lines have no "=" right after the name)
ASSIGNMENT_RE = re.compile(r"^\s*([A-Za-z0-9_.-]+)\s*=(.*)$")
OPERATORS_RE = re.compile(r"[&|+!%^]")
MIN_OF_RE = re.compile(r"^\s*\d+(?::\d+)?\s*of:")


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


def locate_section(lines: list[str], target: str) -> tuple[int, int] | None:
    """Index of the begin and end marker lines of the target section, None if absent."""
    begin = f"# begin {target} section"
    end = f"# end {target} section"
    starts = [i for i, l in enumerate(lines) if l.strip() == begin]
    if not starts:
        if any(l.strip() == end for l in lines):
            raise BpFileCorrupted(f"'{end}' found without '{begin}'")
        return None
    if len(starts) > 1:
        raise BpFileCorrupted(f"multiple '{begin}' markers found")
    s = starts[0]
    e = next((i for i in range(s + 1, len(lines)) if lines[i].strip() == end), None)
    if e is None:
        raise BpFileCorrupted(f"'{begin}' found without '{end}'")
    return s, e


def referenced_nodes(content: str, target: str) -> set[str]:
    """Nodes "<target>_*" referenced outside the target section (e.g. by the
    domains written by Terraform). The parser of the businessprocess module fails
    on a referenced node that is not defined, so each of them must be defined."""
    lines = content.splitlines()
    pos = locate_section(lines, target)
    if pos is not None:
        lines = lines[: pos[0]] + lines[pos[1] + 1 :]
    prefix = f"{target}_"
    refs = set()
    for line in lines:
        m = ASSIGNMENT_RE.match(line)
        if not m or line.lstrip().startswith("#"):
            continue
        value = MIN_OF_RE.sub("", m.group(2))
        for token in OPERATORS_RE.split(value):
            token = token.strip()
            if token.startswith(prefix) and NAME_RE.fullmatch(token):
                refs.add(token)
    return refs


def build_section(
    target: str, host: str, blocks: list[tuple[str, str]], placeholders: set[str] = frozenset()
) -> str:
    by_domain: dict[str, list[str]] = {}
    for domain, name in blocks:
        pair = f"{host};{name}"
        pairs = by_domain.setdefault(domain, [])
        if pair not in pairs:
            pairs.append(pair)
    lines = [f"# begin {target} section"]
    lines += [f"{target}_{d} = {' & '.join(p)}" for d, p in by_domain.items()]
    defined = {f"{target}_{d}" for d in by_domain}
    # referenced but without blocks in this request: empty node (state EMPTY,
    # does not affect the parent) so the business process stays valid
    lines += [f"{n} =" for n in sorted(set(placeholders) - defined)]
    lines.append(f"# end {target} section")
    return "\n".join(lines) + "\n"


def replace_section(content: str, target: str, section: str) -> str:
    lines = content.splitlines(keepends=True)
    pos = locate_section(lines, target)
    if pos is None:
        base = content if not content or content.endswith("\n") else content + "\n"
        return base + ("\n" if base else "") + section
    s, e = pos
    return "".join(lines[:s]) + section + "".join(lines[e + 1 :])


def update_bp_file(
    config_dir: Path, bp: str, target: str, host: str, blocks: list[tuple[str, str]]
) -> None:
    path = config_dir / f"{bp}.conf"
    if not path.is_file():
        raise BpFileNotFound(f"business process '{bp}' not found")
    # in-place rewrite: the service only has write access to the file itself
    with open(path, "r+", encoding="utf-8") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            content = f.read()
            section = build_section(target, host, blocks, referenced_nodes(content, target))
            new = replace_section(content, target, section)
            f.seek(0)
            f.write(new)
            f.truncate()
            f.flush()
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
