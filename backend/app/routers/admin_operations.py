"""Protected operational views and reviewed immutable release workflows."""

import hashlib
import json
import zipfile
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Annotated, Any
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, col, select

from app.core.auth import require_admin
from app.core.config import BACKEND_DIR
from app.database import get_session
from app.models import (
    CityCategoryCache,
    PlaceImageCache,
    PlaceRefreshJob,
    ProviderCooldown,
    User,
)
from app.models.admin_operations import AdminAuditEvent, AdminReview
from app.services.admin_audit import record
from app.services.admin_city_lab import CityLabService, read

router = APIRouter(
    prefix="/api/admin",
    tags=["admin-operations"],
    dependencies=[Depends(require_admin)],
)
SessionDep = Annotated[Session, Depends(get_session)]
AdminDep = Annotated[User, Depends(require_admin)]
Offset = Annotated[int, Query(ge=0)]
Limit = Annotated[int, Query(ge=1, le=100)]


def page(rows, offset, limit):
    return {
        "items": rows[offset : offset + limit],
        "total": len(rows),
        "has_more": len(rows) > offset + limit,
    }


def selected_releases(service):
    bundled = {}
    for path in (BACKEND_DIR.parent / "assets" / "citypacks").glob("*/manifest.json"):
        meta = read(path, {})
        identity = (meta.get("city_id"), meta.get("state"), meta.get("country"))
        bundled[identity] = meta.get("source_release")
    groups = {}
    for row in service.releases():
        identity = tuple(row[3].get(k) for k in ("id", "state", "country"))
        groups.setdefault(identity, []).append(row)
    result = []
    for identity, rows in groups.items():
        chosen = next((r for r in rows if r[1].name == bundled.get(identity)), None)
        if chosen is not None:
            selection = {"source": "BUNDLED_APP", "ambiguous": False}
        else:
            timestamp = max(str(r[2].get("generated_at", "")) for r in rows)
            tied = [r for r in rows if str(r[2].get("generated_at", "")) == timestamp]
            # Derivatives can retain identical timestamps. Stable ordering is not
            # evidence that one branch is newer or certified.
            chosen = min(tied, key=lambda r: r[1].name)
            selection = {"source": "MANIFEST_TIMESTAMP", "ambiguous": len(tied) > 1}
        result.append(
            (
                chosen,
                {**selection, "available_versions": sorted(r[1].name for r in rows)},
            )
        )
    return result


@router.get("/city-lab/summary")
def city_summary():
    service = CityLabService()
    rows = [row for row, _ in selected_releases(service)]
    cities = [service.city(row) for row in rows]
    quality = {
        k: sum(c["quality"][k] for c in cities)
        for k in (
            "missing_image",
            "missing_hours",
            "missing_description",
            "missing_website",
            "missing_coordinates",
            "suspicious_coordinates",
            "broken_gallery",
        )
    }
    research_count = None
    if service.settings.datafactory_checkout:
        try:
            research_count = sum(len(service.task_inventory(row[0])) for row in rows)
        except HTTPException:
            pass
    return {
        "configured": service.root is not None,
        "inventory_complete": not service.inventory_problems,
        "inventory_problems": service.inventory_problems,
        "city_count": len(cities),
        "published_places": sum(c["published_places"] for c in cities),
        "quality": quality,
        "research_tasks": research_count,
    }


@router.get("/city-lab/cities")
def cities(q: str = "", status: str = "", offset: Offset = 0, limit: Limit = 30):
    service = CityLabService()
    rows = [
        {**service.city(row), "release_selection": selection}
        for row, selection in selected_releases(service)
    ]
    rows = [
        r
        for r in rows
        if q.lower() in f"{r['name']} {r['state']}".lower()
        and (not status or r["status"] == status)
    ]
    result = page(sorted(rows, key=lambda r: r["name"]), offset, limit)
    result["configured"] = service.root is not None
    result["inventory_complete"] = not service.inventory_problems
    result["inventory_problems"] = service.inventory_problems
    return result


@router.get("/city-lab/cities/{key}")
def city_detail(key: str, session: SessionDep):
    service = CityLabService()
    result = service.city(service.release(key))
    result["research_tasks"] = None
    result["duplicate_groups"] = None
    if service.settings.datafactory_checkout:
        try:
            result["research_tasks"] = len(service.task_inventory(key))
            _, pack, _, _ = service.release(key)
            result["duplicate_groups"] = len(
                service.module("pipeline.identity_assurance").conflict_groups(
                    service.places(pack)
                )
            )
        except HTTPException:
            pass  # Missing runtime is capability-unavailable, never a fake zero.
    events = session.exec(
        select(AdminAuditEvent)
        .where(AdminAuditEvent.city_id == result["canonical_city_id"])
        .order_by(col(AdminAuditEvent.timestamp).desc())
        .limit(100)
    ).all()
    result["last_validation"] = next(
        (
            e.model_dump(mode="json")
            for e in events
            if e.entity_id == key
            and e.action in {"CITY_VALIDATED", "CITY_VALIDATION_FAILED"}
        ),
        None,
    )
    result["last_pack_build"] = next(
        (
            e.model_dump(mode="json")
            for e in events
            if e.action == "CITY_PACK_BUILT" and e.after.get("release") == key
        ),
        None,
    )
    result["last_publish"] = None
    return result


@router.get("/city-lab/cities/{key}/places")
def places(
    key: str,
    session: SessionDep,
    q: str = "",
    issue: str = "",
    status: str = "",
    sort: str = "name",
    offset: Offset = 0,
    limit: Limit = 30,
):
    service = CityLabService()
    _, pack, _, _ = service.release(key)
    reviews = {
        r.entity_id: r
        for r in session.exec(
            select(AdminReview).where(
                AdminReview.release_key == key, AdminReview.entity_type == "place"
            )
        )
    }
    result = []
    for source in service.places(pack):
        search = f"{source.get('name')} {source.get('classification', {}).get('category')} {source.get('external_ids', {})}".lower()
        issues = service.issues(pack, source)
        review = reviews.get(source["id"])
        qa = review.status if review else "UNREVIEWED"
        if (
            q.lower() not in search
            or (issue and issue not in issues)
            or (status and status != qa)
        ):
            continue
        result.append(
            {
                "id": source["id"],
                "name": source["name"],
                "category": source.get("classification", {}).get("category"),
                "issues": issues,
                "qa_status": qa,
                "quality": source.get("quality", {}),
                "tier": source.get("tier"),
                "updated_at": review.updated_at.isoformat() if review else None,
            }
        )
    if sort == "missing_fields":
        result.sort(key=lambda r: len(r["issues"]), reverse=True)
    elif sort == "confidence":
        result.sort(key=lambda r: r["quality"].get("overall", 0), reverse=True)
    elif sort == "recent":
        result.sort(key=lambda r: r["updated_at"] or "", reverse=True)
    elif sort == "priority":
        result.sort(key=lambda r: (r["tier"] != "core_destination", r["name"]))
    else:
        result.sort(key=lambda r: r["name"].lower())
    return page(result, offset, limit)


@router.get("/city-lab/cities/{key}/places/{place_id}")
def place_detail(key: str, place_id: str, session: SessionDep):
    service = CityLabService()
    _, pack, _, _ = service.release(key)
    source = next((p for p in service.places(pack) if p["id"] == place_id), None)
    if source is None:
        raise HTTPException(404, "Place not found.")
    review = session.exec(
        select(AdminReview).where(
            AdminReview.release_key == key,
            AdminReview.entity_type == "place",
            AdminReview.entity_id == place_id,
        )
    ).first()
    return {
        "source": source,
        "issues": service.issues(pack, source),
        "fingerprint": service.digest(pack),
        "review": review.model_dump(mode="json") if review else None,
    }


@router.get("/city-lab/cities/{key}/media")
def media(key: str, path: str):
    service = CityLabService()
    _, pack, _, _ = service.release(key)
    target = service.local_file(pack, path)
    # Only files explicitly referenced by canonical media are servable.
    refs = {
        image.get(k)
        for p in service.places(pack)
        for image in (
            [p.get("images", {}).get("primary") or {}]
            + p.get("images", {}).get("gallery", [])
        )
        for k in ("local_path", "thumbnail_path")
    }
    if (
        target is None
        or path not in refs
        or target.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp")
    ):
        raise HTTPException(404, "Referenced image unavailable.")
    return FileResponse(target)


class ReviewInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    fingerprint: str = Field(max_length=128)
    expected_updated_at: datetime | None = None
    status: str = Field(
        pattern=r"^(KEEP|NEEDS_RESEARCH|EXCLUDE|ACCEPTED|REJECTED|MANUAL_REVIEW|KEEP_BOTH)$"
    )
    changes: dict[str, Any] = Field(default_factory=dict)
    notes: str = Field(default="", max_length=4000)
    evidence_url: str | None = Field(
        default=None, max_length=1000, pattern=r"^https?://[^\s/]+"
    )


def save_review(service, key, entity_type, entity_id, source, payload, session, actor):
    _, pack, _, city = service.release(key)
    if payload.fingerprint != service.digest(pack):
        raise HTTPException(409, "Release changed. Reload before reviewing.")
    module = service.module("citylab_patch")
    try:
        for field, value in payload.changes.items():
            module.validate_value(field, value)
    except (ValueError, TypeError) as exc:
        raise HTTPException(
            422, "Correction failed DataFactory field validation."
        ) from exc
    if payload.changes and not payload.evidence_url:
        raise HTTPException(422, "Source evidence is required for corrections.")
    if "media" in payload.changes:
        raise HTTPException(
            422,
            "Media file import requires the existing City Lab image workflow. Mark it for research here.",
        )
    row = session.exec(
        select(AdminReview)
        .where(
            AdminReview.release_key == key,
            AdminReview.entity_type == entity_type,
            AdminReview.entity_id == entity_id,
        )
        .with_for_update()
    ).first()

    def utc(value):
        return (
            value.replace(tzinfo=timezone.utc)
            if value and value.tzinfo is None
            else value
        )

    if (row and utc(row.updated_at) != utc(payload.expected_updated_at)) or (
        row is None and payload.expected_updated_at is not None
    ):
        raise HTTPException(409, "Review changed. Reload before saving.")
    before = (
        {"status": row.status, "changes": row.changes, "notes": row.notes}
        if row
        else {}
    )
    if row is None:
        row = AdminReview(
            release_key=key,
            entity_type=entity_type,
            entity_id=entity_id,
            city_id=city["id"],
            base_fingerprint=payload.fingerprint,
            updated_by=actor.id,
        )
    row.status, row.changes, row.notes, row.evidence_url = (
        payload.status,
        payload.changes,
        payload.notes,
        payload.evidence_url,
    )
    row.base_values = {f: module.get_value(source, f) for f in payload.changes}
    row.updated_by, row.updated_at = actor.id, datetime.now(timezone.utc)
    session.add(row)
    record(
        session,
        actor,
        f"{entity_type.upper()}_REVIEWED",
        entity_type,
        entity_id,
        before,
        {
            "status": row.status,
            "changes": row.changes,
            "evidence_url": row.evidence_url,
        },
        payload.notes,
        city["id"],
    )
    try:
        session.commit()
    except IntegrityError as exc:
        session.rollback()
        raise HTTPException(409, "Review changed. Reload before saving.") from exc
    return row.model_dump(mode="json")


@router.patch("/city-lab/cities/{key}/places/{place_id}")
def review_place(
    key: str, place_id: str, payload: ReviewInput, session: SessionDep, actor: AdminDep
):
    if payload.status not in {"KEEP", "NEEDS_RESEARCH", "EXCLUDE", "KEEP_BOTH"}:
        raise HTTPException(422, "Unsupported place QA status.")
    source = place_detail(key, place_id, session)["source"]
    return save_review(
        CityLabService(), key, "place", place_id, source, payload, session, actor
    )


@router.get("/research/tasks")
def research(
    session: SessionDep,
    city: str,
    q: str = "",
    priority: str = "",
    type: str = "",
    status: str = "",
    offset: Offset = 0,
    limit: Limit = 30,
):
    service = CityLabService()
    reviews = {
        r.entity_id: r
        for r in session.exec(
            select(AdminReview).where(
                AdminReview.release_key == city, AdminReview.entity_type == "research"
            )
        )
    }
    rows = []
    for task in service.task_inventory(city):
        review = reviews.get(task["task_id"])
        task = {
            **task,
            "id": task["task_id"],
            "name": task["place"]["name"],
            "status": review.status if review else "OPEN",
            "review": review.model_dump(mode="json") if review else None,
        }
        if (
            q.lower() in task["name"].lower()
            and (not priority or priority == task["priority"])
            and (not type or type == task["type"])
            and (not status or status == task["status"])
        ):
            rows.append(task)
    return page(sorted(rows, key=lambda t: (t["priority"], t["name"])), offset, limit)


@router.post("/research/{task_id}/review")
def review_research(
    task_id: str, city: str, payload: ReviewInput, session: SessionDep, actor: AdminDep
):
    if payload.status not in {"ACCEPTED", "REJECTED", "MANUAL_REVIEW"}:
        raise HTTPException(422, "Unsupported research review status.")
    service = CityLabService()
    task = next(
        (t for t in service.task_inventory(city) if t["task_id"] == task_id), None
    )
    if task is None:
        raise HTTPException(404, "Research task not found.")
    allowed = {
        "OPENING_HOURS": {"opening_hours"},
        "DESCRIPTION": {"description"},
        "WEBSITE": {"website"},
        "COORDINATE_RESEARCH": {"latitude", "longitude", "address"},
        "IDENTITY_RESEARCH": {"name", "name_hi", "aliases", "category", "subcategory"},
        "REAL_PRIMARY_IMAGE": {"media"},
    }
    if set(payload.changes) - allowed.get(task["type"], set()):
        raise HTTPException(422, "Correction fields do not match this research task.")
    if payload.status == "ACCEPTED" and (
        not payload.changes or not payload.evidence_url
    ):
        raise HTTPException(
            422,
            "A suggested value and evidence are required. Acceptance records human review, not canonical publication.",
        )
    _, pack, _, _ = service.release(city)
    source = next(p for p in service.places(pack) if p["id"] == task["place_id"])
    return save_review(
        service, city, "research", task_id, source, payload, session, actor
    )


@router.get("/city-lab/cities/{key}/duplicates")
def duplicates(key: str, offset: Offset = 0, limit: Limit = 30):
    service = CityLabService()
    _, pack, _, _ = service.release(key)
    groups = service.module("pipeline.identity_assurance").conflict_groups(
        service.places(pack)
    )
    return page(groups, offset, limit)


@router.get("/city-packs")
def packs(offset: Offset = 0, limit: Limit = 30):
    service = CityLabService()
    return page([service.city(row) for row in service.releases()], offset, limit)


@router.post("/city-lab/cities/{key}/validate")
def validate(key: str, session: SessionDep, actor: AdminDep):
    service = CityLabService()
    _, pack, _, city = service.release(key)
    try:
        report = service.module("pipeline.validate").validate_release_package(pack)
    except (ValueError, OSError) as exc:
        record(
            session,
            actor,
            "CITY_VALIDATION_FAILED",
            "city",
            key,
            after={"status": "FAILED"},
            city_id=city["id"],
        )
        session.commit()
        raise HTTPException(
            422,
            "Release validation failed. Inspect the release artifacts in DataFactory.",
        ) from exc
    record(
        session, actor, "CITY_VALIDATED", "city", key, after=report, city_id=city["id"]
    )
    session.commit()
    return report


@router.post("/city-packs/{key}/build")
def build(key: str, session: SessionDep, actor: AdminDep):
    service = CityLabService()
    _, pack, _, city = service.release(key)
    module = service.module("app_pack")
    settings_module = service.module("config.settings")
    settings = settings_module.Settings(
        project_root=Path(service.settings.datafactory_checkout)
    )

    # Point reads at the configured canonical root; export only to backend artifacts.
    class ReadSettings:
        releases_dir = service.root

        def __getattr__(self, key):
            return getattr(settings, key)

    artifact_id = uuid4().hex
    output = service.artifact_root() / "packs" / artifact_id
    try:
        report = module.export_app_pack(
            city["name"],
            version=pack.name,
            state=city.get("state"),
            country=city.get("country"),
            output=output,
            settings=ReadSettings(),
        )
    except (ValueError, OSError) as exc:
        raise HTTPException(
            422, "City pack build failed validation. Canonical releases were preserved."
        ) from exc
    safe_report = {k: v for k, v in report.items() if k != "output"}
    record(
        session,
        actor,
        "CITY_PACK_BUILT",
        "pack",
        artifact_id,
        after={"release": key, "manifest": safe_report},
        city_id=city["id"],
    )
    session.commit()
    return {
        "artifact_id": artifact_id,
        "status": "BUILT",
        "manifest": safe_report,
        "published": False,
    }


@router.post("/city-lab/cities/{key}/export-patch")
def export_patch(key: str, session: SessionDep, actor: AdminDep):
    service = CityLabService()
    _, pack, _, city = service.release(key)
    reviews = session.exec(
        select(AdminReview).where(AdminReview.release_key == key)
    ).all()
    approved = [
        r
        for r in reviews
        if r.changes
        and (
            (r.entity_type == "place" and r.status in {"KEEP", "KEEP_BOTH"})
            or (r.entity_type == "research" and r.status == "ACCEPTED")
        )
    ]
    task_places = (
        {t["task_id"]: t["place_id"] for t in service.task_inventory(key)}
        if any(r.entity_type == "research" for r in approved)
        else {}
    )
    excluded = {
        r.entity_id
        for r in reviews
        if r.entity_type == "place" and r.status == "EXCLUDE"
    }
    combined = {}
    for r in approved:
        pid = r.entity_id if r.entity_type == "place" else task_places.get(r.entity_id)
        if not pid or pid in excluded:
            raise HTTPException(
                409,
                "An approved correction targets an unavailable or excluded place. Review again.",
            )
        change = combined.setdefault(
            pid,
            {
                "place_id": pid,
                "operation": "UPDATE",
                "changes": {},
                "before": {},
                "author": str(actor.id),
                "evidence": [],
            },
        )
        for field, value in r.changes.items():
            if field in change["changes"] and change["changes"][field] != value:
                raise HTTPException(
                    409, "Conflicting approved corrections. Resolve them before export."
                )
            change["changes"][field], change["before"][field] = (
                value,
                r.base_values[field],
            )
        change["evidence"].append(
            {"reviewer": str(r.updated_by), "notes": r.notes, "url": r.evidence_url}
        )
    changes = list(combined.values())
    if not changes:
        raise HTTPException(422, "No approved field corrections to export.")
    if any(r.base_fingerprint != service.digest(pack) for r in approved):
        raise HTTPException(409, "Correction base changed. Review again.")
    patch_id = uuid4().hex
    raw = json.dumps(changes, ensure_ascii=False).encode("utf-8")
    manifest = {
        "patch_schema_version": 1,
        "patch_id": patch_id,
        "city_id": city["id"],
        "city_name": city["name"],
        "state": city["state"],
        "country": city["country"],
        "source_pack_version": pack.name,
        "source_pack_fingerprint": service.fingerprint(pack),
        "change_count": len(changes),
        "media_count": 0,
        "checksums": {"changes.json": hashlib.sha256(raw).hexdigest()},
    }
    output = service.artifact_root() / "patches" / (patch_id + ".zip")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr("manifest.json", json.dumps(manifest))
        archive.writestr("changes.json", raw)
    record(
        session,
        actor,
        "CITY_PATCH_EXPORTED",
        "patch",
        patch_id,
        after={"changes": len(changes), "base": key},
        city_id=city["id"],
    )
    session.commit()
    return {
        "artifact_id": patch_id,
        "changes": len(changes),
        "download": f"/api/admin/artifacts/{patch_id}",
    }


@router.get("/artifacts/{artifact_id}")
def artifact(artifact_id: UUID):
    output = CityLabService().artifact_root() / "patches" / (artifact_id.hex + ".zip")
    if not output.is_file():
        raise HTTPException(404, "Artifact not found.")
    return FileResponse(output, filename=output.name, media_type="application/zip")


@router.get("/system-health")
def health(session: SessionDep):
    jobs = dict(
        session.exec(
            select(PlaceRefreshJob.state, func.count(PlaceRefreshJob.id)).group_by(
                PlaceRefreshJob.state
            )
        ).all()
    )
    return {
        "api": "responding",
        "database": "readable",
        "jobs": jobs,
        "cache_rows": session.exec(select(func.count(CityCategoryCache.id))).one(),
        "stale_cache_rows": session.exec(
            select(func.count(CityCategoryCache.id)).where(
                CityCategoryCache.expires_at < datetime.now(timezone.utc)
            )
        ).one(),
        "image_status": dict(
            session.exec(
                select(PlaceImageCache.status, func.count(PlaceImageCache.id)).group_by(
                    PlaceImageCache.status
                )
            ).all()
        ),
        "provider_cooldowns": [
            {"provider": r.provider_key, "cooldown_until": r.cooldown_until}
            for r in session.exec(select(ProviderCooldown))
        ],
        "providers": "Configuration and recorded cooldowns only. Connectivity has not been probed.",
        "city_lab_configured": CityLabService().root is not None,
    }


@router.get("/jobs")
def jobs(session: SessionDep, state: str = "", offset: Offset = 0, limit: Limit = 30):
    statement = select(PlaceRefreshJob)
    if state:
        statement = statement.where(PlaceRefreshJob.state == state)
    rows = session.exec(
        statement.order_by(
            col(PlaceRefreshJob.last_started_at).desc(), PlaceRefreshJob.id
        )
        .offset(offset)
        .limit(limit + 1)
    ).all()
    return {
        "items": [
            {
                **r.model_dump(mode="json", exclude={"lease_owner", "last_error"}),
                "last_error": "A refresh error was recorded. Inspect the protected worker diagnostics."
                if r.last_error
                else None,
            }
            for r in rows[:limit]
        ],
        "has_more": len(rows) > limit,
    }


@router.get("/audit-log")
def audit(
    session: SessionDep,
    q: str = "",
    action: str = "",
    city: str = "",
    entity_type: str = "",
    admin: UUID | None = None,
    since: date | None = None,
    offset: Offset = 0,
    limit: Limit = 30,
):
    statement = select(AdminAuditEvent)
    if q:
        statement = statement.where(AdminAuditEvent.entity_id.contains(q))
    if action:
        statement = statement.where(AdminAuditEvent.action == action)
    if city:
        statement = statement.where(AdminAuditEvent.city_id == city)
    if entity_type:
        statement = statement.where(AdminAuditEvent.entity_type == entity_type)
    if admin:
        statement = statement.where(AdminAuditEvent.admin_user_id == admin)
    if since:
        statement = statement.where(
            AdminAuditEvent.timestamp
            >= datetime.combine(since, datetime.min.time(), tzinfo=timezone.utc)
        )
    rows = session.exec(
        statement.order_by(col(AdminAuditEvent.timestamp).desc(), AdminAuditEvent.id)
        .offset(offset)
        .limit(limit + 1)
    ).all()
    return {
        "items": [r.model_dump(mode="json") for r in rows[:limit]],
        "has_more": len(rows) > limit,
    }
