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


def test_missing_file_not_created(bp_dir):
    assert post(bp="other").status_code == 400
    assert not (bp_dir / "other.conf").exists()


def test_corrupted_file_is_500(bp_dir):
    (bp_dir / "bp.conf").write_text("# begin t1 section\nx = y\n")
    r = post()
    assert r.status_code == 500 and "detail" in r.json()


def test_health():
    assert client.get("/health").json() == {"status": "ok"}
