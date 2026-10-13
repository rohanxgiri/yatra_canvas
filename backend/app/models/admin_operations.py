"""Backend owned review overlays and append only privileged audit history."""

from datetime import datetime, timezone
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import JSON, Column, DateTime, UniqueConstraint
from sqlmodel import Field, SQLModel


class AdminAuditEvent(SQLModel, table=True):
    __tablename__ = "admin_audit_events"
    id: UUID = Field(default_factory=uuid4, primary_key=True)
    timestamp: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        sa_column=Column(DateTime(timezone=True), nullable=False, index=True),
    )
    admin_user_id: UUID = Field(index=True)
    action: str = Field(max_length=80, index=True)
    entity_type: str = Field(max_length=40, index=True)
    entity_id: str = Field(max_length=200, index=True)
    city_id: str | None = Field(default=None, max_length=200, index=True)
    before: dict[str, Any] = Field(
        default_factory=dict, sa_column=Column(JSON, nullable=False)
    )
    after: dict[str, Any] = Field(
        default_factory=dict, sa_column=Column(JSON, nullable=False)
    )
    reason: str = Field(default="", max_length=1000)


class AdminReview(SQLModel, table=True):
    __tablename__ = "admin_reviews"
    __table_args__ = (
        UniqueConstraint(
            "release_key", "entity_type", "entity_id", name="uq_admin_review_entity"
        ),
    )
    id: UUID = Field(default_factory=uuid4, primary_key=True)
    release_key: str = Field(max_length=200, index=True)
    entity_type: str = Field(max_length=40)
    entity_id: str = Field(max_length=200)
    city_id: str = Field(max_length=200, index=True)
    base_fingerprint: str = Field(max_length=128)
    status: str = Field(default="NEEDS_RESEARCH", max_length=40)
    changes: dict[str, Any] = Field(
        default_factory=dict, sa_column=Column(JSON, nullable=False)
    )
    base_values: dict[str, Any] = Field(
        default_factory=dict, sa_column=Column(JSON, nullable=False)
    )
    notes: str = Field(default="", max_length=4000)
    evidence_url: str | None = Field(default=None, max_length=1000)
    updated_by: UUID
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc),
        sa_column=Column(DateTime(timezone=True), nullable=False),
    )
