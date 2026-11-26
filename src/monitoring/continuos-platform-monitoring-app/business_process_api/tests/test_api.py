import pytest
from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)
BODY = {
    "host": "h1",
    "blocks": [
        {"domain": "pay", "name": "svc1"},
        {"domain": "pay", "name": "svc2"},
        {"domain": "pay", "name": "svc1"},
        {"domain": "net", "name": "svc3"},
    ],
}


@pytest.fixture
def bp_dir(tmp_path, monkeypatch):
    monkeypatch.setenv("BP_CONFIG_DIR", str(tmp_path))
    (tmp_path / "bp.conf").write_text("# header\nfoo = a & b\n")
    return tmp_path


def post(target="t1", bp="bp", body=BODY):
    return client.post(f"/business-process/{bp}/block/{target}", json=body)


def test_appends_section(bp_dir):
    r = post()
    assert r.status_code == 200 and r.content == b""
    assert (bp_dir / "bp.conf").read_text() == (
        "# header\nfoo = a & b\n\n"
        "# begin t1 section\n"
        "t1_pay = h1;svc1 & h1;svc2\n"
        "t1_net = h1;svc3\n"
        "# end t1 section\n"
    )


def test_replaces_only_own_section(bp_dir):
    post("t1")
    post("t2")
    post("t1", body={"host": "h2", "blocks": [{"domain": "d", "name": "n"}]})
    text = (bp_dir / "bp.conf").read_text()
    assert text.count("# begin t1 section") == 1
    assert "t1_d = h2;n\n" in text and "h1;svc1" in text  # t2 untouched
    assert "t1_pay" not in text


def test_referenced_nodes_without_blocks_are_defined_empty(bp_dir):
    # domains written by Terraform reference t1_<domain>, with a placeholder section
    (bp_dir / "bp.conf").write_text(
        "pay = a & t1_pay\n"
        "net = 1 of: b + t1_net\n"
        "ops = c | t1_ops | h;t1_x\n"
        "display 1;pay;pay\n"
        "\n# begin t1 section\nt1_pay =\nt1_net =\nt1_ops =\n# end t1 section\n"
    )
    assert post(body={"host": "h1", "blocks": [{"domain": "pay", "name": "s"}]}).status_code == 200
    assert (bp_dir / "bp.conf").read_text().endswith(
        "# begin t1 section\n"
        "t1_pay = h1;s\n"
        "t1_net =\n"
        "t1_ops =\n"
        "# end t1 section\n"
    )


@pytest.mark.parametrize(
    "kwargs",
    [
        {"bp": "missing"},
        {"bp": "..", "target": "t"},
        {"target": "a b"},
        {"body": {"host": "", "blocks": [{"domain": "d", "name": "n"}]}},
        {"body": {"host": "h", "blocks": []}},
        {"body": {"host": "h", "blocks": [{"domain": "d", "name": "a & b"}]}},
        {"body": {"host": "h;x", "blocks": [{"domain": "d", "name": "n"}]}},
    ],
)
def test_bad_requests(bp_dir, kwargs):
    r = post(**kwargs)
    assert r.status_code in (400, 404) and "detail" in r.json()
    assert r.status_code == 400 or kwargs.get("bp") == ".."


def blocks_body(host="h", domain="d", name="n"):
    return {"body": {"host": host, "blocks": [{"domain": domain, "name": name}]}}


@pytest.mark.parametrize(
    "kwargs",
    [
        # operators of the businessprocess syntax: "Mixing operators is not allowed"
        # would break the whole file
        *[blocks_body(name=f"a{op}b") for op in "|+!%^&\\"],
        blocks_body(host="h|x"),
        # line separators seen by Python but not by the PHP parser
        *[blocks_body(name=f"a{sep}b") for sep in [" ", " ", "\x85", "\x0b", "\x0c", "\x1c"]],
        blocks_body(name="a # end t1 section junk"),
        blocks_body(name="a b"),
        blocks_body(name="x" * 256),
        # domain is part of the node name
        blocks_body(domain="a b"),
        blocks_body(domain="a|b"),
        blocks_body(domain=".."),
    ],
)
def test_bp_syntax_injection_rejected(bp_dir, kwargs):
    before = (bp_dir / "bp.conf").read_text()
    r = post(**kwargs)
    assert r.status_code == 400 and "detail" in r.json()
    assert (bp_dir / "bp.conf").read_text() == before


def test_allowed_values(bp_dir):
    r = post(body={"host": "pagopa-d.weu:x_1", "blocks": [{"domain": "a.b-c_1", "name": "app-api-aks"}]})
    assert r.status_code == 200
    assert "t1_a.b-c_1 = pagopa-d.weu:x_1;app-api-aks\n" in (bp_dir / "bp.conf").read_text()


def test_unicode_separators_in_file_are_not_lines(bp_dir):
    # Terraform titles contain U+2028: never a line (nor a marker) for the API
    (bp_dir / "bp.conf").write_text(
        "display 0;n;AKS # begin t1 section x\n"
        "dom = a & t1_dom\n"
    )
    assert post(body={"host": "h", "blocks": [{"domain": "dom", "name": "s"}]}).status_code == 200
    text = (bp_dir / "bp.conf").read_text()
    assert text.startswith("display 0;n;AKS # begin t1 section x\ndom = a & t1_dom\n")
    assert text.count("\n# begin t1 section\n") == 1 and "t1_dom = h;s\n" in text


def test_symlink_outside_config_dir_rejected(bp_dir, tmp_path_factory):
    outside = tmp_path_factory.mktemp("outside") / "target.conf"
    outside.write_text("x = y\n")
    (bp_dir / "evil.conf").symlink_to(outside)
    assert post(bp="evil").status_code == 400
    assert outside.read_text() == "x = y\n"


def test_symlink_inside_config_dir_allowed(bp_dir):
    (bp_dir / "alias.conf").symlink_to(bp_dir / "bp.conf")
    assert post(bp="alias").status_code == 200
    assert "# begin t1 section" in (bp_dir / "bp.conf").read_text()


def test_log_injection_escaped(bp_dir, caplog):
    caplog.set_level("WARNING", logger="bp-api")
    r = client.post("/business-process/bp%0Aresult=200%20forged/block/t1", json=BODY)
    assert r.status_code == 400
    messages = [rec.getMessage() for rec in caplog.records if rec.name == "bp-api"]
    assert messages and all("\n" not in m for m in messages)
    assert any("bp\\nresult=200 forged" in m for m in messages)


def test_missing_file_not_created(bp_dir):
    assert post(bp="other").status_code == 400
    assert not (bp_dir / "other.conf").exists()


def test_corrupted_file_is_500(bp_dir):
    (bp_dir / "bp.conf").write_text("# begin t1 section\nx = y\n")
    r = post()
    # generic message: the details (paths, markers) only in the log
    assert r.status_code == 500 and r.json() == {"detail": "internal error"}


def test_health():
    assert client.get("/health").json() == {"status": "ok"}


@pytest.mark.parametrize("path", ["/docs", "/redoc", "/openapi.json", "/docs/oauth2-redirect"])
def test_docs_disabled(path):
    assert client.get(path).status_code == 404
