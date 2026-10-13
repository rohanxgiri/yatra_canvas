"""Browser clients must be able to read the Discover response metadata."""

import pytest
from fastapi.testclient import TestClient

from app.main import app


def test_browser_can_read_refresh_cursor_and_correlation_headers():
    origin = "http://localhost:62770"
    with TestClient(app) as client:
        response = client.get("/", headers={
            "Origin": origin, "X-Request-ID": "lucknow-browser-regression",
        })
    assert response.status_code == 200
    assert response.headers["Access-Control-Allow-Origin"] == origin
    exposed = {
        name.strip().lower()
        for name in response.headers.get("Access-Control-Expose-Headers", "").split(",")
    }
    assert {"x-refresh-state", "x-stale-categories", "x-next-cursor", "x-request-id"} <= exposed
    assert response.headers["X-Request-ID"] == "lucknow-browser-regression"
    assert "authorization" not in exposed


@pytest.mark.parametrize("origin", ["http://localhost.evil.example", "https://untrusted.example"])
def test_response_metadata_does_not_expand_allowed_origins(origin):
    with TestClient(app) as client:
        response = client.get("/", headers={"Origin": origin})
    assert "Access-Control-Allow-Origin" not in response.headers
    assert "Access-Control-Allow-Credentials" not in response.headers
