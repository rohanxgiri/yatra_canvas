"""Opt in real immutable DataFactory checks using the documented configuration."""

import os

import pytest
from sqlmodel import select
from test_integrated_auth_admin import headers

pytest_plugins = ("test_integrated_auth_admin",)

from app.models import AdminAuditEvent
from app.services.admin_city_lab import CityLabService

pytestmark = pytest.mark.skipif(
    not os.environ.get("DATAFACTORY_CHECKOUT")
    or not os.environ.get("ADMIN_RELEASE_ROOT"),
    reason="Configure existing immutable DataFactory releases to run adapter integration",
)


def test_real_research_validation_and_pack_build_preserve_canonical(setup, tmp_path):
    client, session, admin, *_ = setup
    service = CityLabService()
    row = next(
        r
        for r in service.releases()
        if r[3]["id"] == "jaipur" and r[1].name == "v5-offline-startpoints-01"
    )
    key, pack, *_ = row
    original = service.fingerprint(pack)
    tasks = client.get(
        "/api/admin/research/tasks",
        params={"city": key, "limit": 100},
        headers=headers(admin),
    )
    assert tasks.status_code == 200, tasks.text
    assert tasks.json()["total"] > 0
    validation = client.post(
        f"/api/admin/city-lab/cities/{key}/validate", headers=headers(admin)
    )
    assert validation.status_code == 200, validation.text
    build = client.post(f"/api/admin/city-packs/{key}/build", headers=headers(admin))
    assert build.status_code == 200, build.text
    result = build.json()
    assert result["published"] is False
    output = service.artifact_root() / "packs" / result["artifact_id"]
    verified = service.module("app_pack").validate_app_pack(output)
    assert verified["source_snapshot"] == original
    assert service.fingerprint(pack) == original
    # Validate our exported ZIP with the existing importer unpack contract.
    source = service.places(pack)[0]
    detail = client.get(
        f"/api/admin/city-lab/cities/{key}/places/{source['id']}",
        headers=headers(admin),
    ).json()
    correction = {
        "fingerprint": detail["fingerprint"],
        "status": "KEEP",
        "changes": {"description": "A human reviewed test correction."},
        "evidence_url": "https://example.org",
        "notes": "Disposable integration evidence",
    }
    assert (
        client.patch(
            f"/api/admin/city-lab/cities/{key}/places/{source['id']}",
            json=correction,
            headers=headers(admin),
        ).status_code
        == 200
    )
    exported = client.post(
        f"/api/admin/city-lab/cities/{key}/export-patch", headers=headers(admin)
    ).json()
    archive = tmp_path / "review.zip"
    archive.write_bytes(
        client.get(exported["download"], headers=headers(admin)).content
    )
    manifest, changes = service.module("citylab_patch").unpack_patch(
        archive, tmp_path / "unpacked"
    )
    assert manifest["source_pack_fingerprint"] == original and len(changes) == 1
    assert {e.action for e in session.exec(select(AdminAuditEvent))} >= {
        "CITY_VALIDATED",
        "CITY_PACK_BUILT",
        "CITY_PATCH_EXPORTED",
    }
    assert service.fingerprint(pack) == original
