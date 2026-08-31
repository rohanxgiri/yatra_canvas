"""Source-of-truth and configuration-documentation consistency tests."""

import re
from pathlib import Path

from app.core.config import Settings

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_OF_TRUTH = (
    REPOSITORY_ROOT / "docs" / "PROJECT_CONTEXT.md",
    REPOSITORY_ROOT / "docs" / "ARCHITECTURE.md",
    REPOSITORY_ROOT / "docs" / "API_AND_DATA_SOURCES.md",
    REPOSITORY_ROOT / "docs" / "DATA_MODEL.md",
    REPOSITORY_ROOT / "docs" / "ENVIRONMENT_VARIABLES.md",
    REPOSITORY_ROOT / "docs" / "ROADMAP.md",
    REPOSITORY_ROOT / "docs" / "DECISIONS.md",
)
LOCAL_LINK_PATTERN = re.compile(r"\[[^]]+\]\((?!https?://)([^)#]+)(?:#[^)]*)?\)")


def test_source_of_truth_has_review_date() -> None:
    for document in SOURCE_OF_TRUTH:
        assert document.is_file(), f"Missing source-of-truth document: {document}"
        assert "Last reviewed: 2026-08-31" in document.read_text(encoding="utf-8")


def test_all_runtime_configuration_is_documented() -> None:
    environment_document = (
        REPOSITORY_ROOT / "docs" / "ENVIRONMENT_VARIABLES.md"
    ).read_text(encoding="utf-8")
    settings_names = {
        field.validation_alias
        for field in Settings.model_fields.values()
        if isinstance(field.validation_alias, str)
    }

    for variable_name in settings_names | {"API_BASE_URL"}:
        assert f"`{variable_name}`" in environment_document


def test_source_of_truth_local_markdown_links_resolve() -> None:
    documents = SOURCE_OF_TRUTH + (
        REPOSITORY_ROOT / "README.md",
        REPOSITORY_ROOT / "AGENTS.md",
    )

    for document in documents:
        contents = document.read_text(encoding="utf-8")
        for target in LOCAL_LINK_PATTERN.findall(contents):
            resolved = (document.parent / target).resolve()
            assert resolved.exists(), f"Broken link in {document}: {target}"
