"""Explicit safe field allowlists keep credentials out of audit payloads."""

from app.models.admin_operations import AdminAuditEvent


def snapshot(entity, fields):
    return {field: getattr(entity, field) for field in fields}


def record(
    session,
    actor,
    action,
    entity_type,
    entity_id,
    before=None,
    after=None,
    reason="",
    city_id=None,
):
    event = AdminAuditEvent(
        admin_user_id=actor.id,
        action=action,
        entity_type=entity_type,
        entity_id=str(entity_id),
        before=before or {},
        after=after or {},
        reason=reason[:1000],
        city_id=str(city_id) if city_id is not None else None,
    )
    session.add(event)
    return event
