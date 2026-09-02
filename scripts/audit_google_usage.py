"""
Audit YatraCanvas for Google-related runtime dependencies.

Usage:
    python scripts/audit_google_usage.py .

Creates:
    google_usage_audit.md

This script DOES NOT modify the project.
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()

OUTPUT = ROOT / "google_usage_audit.md"


# Directories we should never scan.
IGNORE_DIRS = {
    ".git",
    ".idea",
    ".vscode",
    ".dart_tool",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "__pycache__",
    "build",
    "dist",
    "node_modules",
    "venv",
    ".venv",
    "env",
    ".env",
}


# Avoid scanning actual secrets.
IGNORE_FILES = {
    ".env",
    ".env.local",
    ".env.development",
    ".env.production",
    ".env.test",
}


TEXT_EXTENSIONS = {
    ".py",
    ".dart",
    ".yaml",
    ".yml",
    ".json",
    ".toml",
    ".ini",
    ".cfg",
    ".sql",
    ".md",
    ".txt",
    ".gradle",
    ".kts",
    ".xml",
    ".properties",
}


PATTERNS = {
    "GOOGLE_PLACES": [
        r"\bGooglePlaces",
        r"\bGooglePlace",
        r"\bgoogle_places\b",
        r"\bgoogle_place_id\b",
        r"\bGOOGLE_PLACES_API_KEY\b",
        r"places\.googleapis\.com",
        r"GoogleCitySuggestion",
        r"GooglePlaceDetails",
        r"discover_places",
        r"nearbySearch",
        r"places:autocomplete",
    ],
    "GOOGLE_ROUTES": [
        r"\bGoogleRoutes",
        r"\bgoogle_routes\b",
        r"\bGOOGLE_ROUTES_API_KEY\b",
        r"routes\.googleapis\.com",
        r"computeRouteMatrix",
        r"RouteMatrix",
    ],
    "GOOGLE_MAPS_SDK": [
        r"google_maps_flutter",
        r"com\.google\.android\.gms\.maps",
        r"maps\.googleapis\.com/maps",
        r"GoogleMap\(",
        r"MapsInitializer",
    ],
    "OTHER_GOOGLE": [
        r"\bgoogle\b",
        r"googleapis\.com",
    ],
}


def should_scan(path: Path) -> bool:
    relative_parts = path.relative_to(ROOT).parts

    if any(part in IGNORE_DIRS for part in relative_parts):
        return False

    if path.name in IGNORE_FILES:
        return False

    # Explicitly allow example env files.
    if path.name in {".env.example", "env.example"}:
        return True

    return path.suffix.lower() in TEXT_EXTENSIONS


def classify_location(path: Path) -> str:
    parts = {part.lower() for part in path.parts}

    if "tests" in parts or "test" in parts:
        return "TEST"

    if "docs" in parts or path.suffix.lower() == ".md":
        return "DOCUMENTATION"

    if "scripts" in parts:
        return "SCRIPT"

    if "backend" in parts or "lib" in parts:
        return "RUNTIME"

    return "OTHER"


def safe_line(line: str) -> str:
    """
    Prevent accidentally printing secret values.

    Example:
        GOOGLE_PLACES_API_KEY=abc123
    becomes:
        GOOGLE_PLACES_API_KEY=<redacted>
    """

    stripped = line.strip()

    env_match = re.match(
        r"^([A-Z][A-Z0-9_]*(?:KEY|SECRET|TOKEN|PASSWORD)[A-Z0-9_]*)\s*=\s*(.*)$",
        stripped,
    )

    if env_match:
        return f"{env_match.group(1)}=<redacted>"

    return stripped[:300]


def scan() -> dict[str, list[dict]]:
    results: dict[str, list[dict]] = defaultdict(list)

    compiled = {
        category: [re.compile(pattern, re.IGNORECASE) for pattern in patterns]
        for category, patterns in PATTERNS.items()
    }

    for path in ROOT.rglob("*"):
        if not path.is_file() or not should_scan(path):
            continue

        try:
            content = path.read_text(
                encoding="utf-8",
                errors="ignore",
            )
        except OSError:
            continue

        relative = path.relative_to(ROOT)

        for line_number, line in enumerate(content.splitlines(), start=1):
            categories_found = []

            for category, regexes in compiled.items():
                if any(regex.search(line) for regex in regexes):
                    categories_found.append(category)

            # Prefer the most specific category.
            if "GOOGLE_PLACES" in categories_found:
                category = "GOOGLE_PLACES"

            elif "GOOGLE_ROUTES" in categories_found:
                category = "GOOGLE_ROUTES"

            elif "GOOGLE_MAPS_SDK" in categories_found:
                category = "GOOGLE_MAPS_SDK"

            elif "OTHER_GOOGLE" in categories_found:
                category = "OTHER_GOOGLE"

            else:
                continue

            results[category].append(
                {
                    "file": str(relative),
                    "line": line_number,
                    "code": safe_line(line),
                    "location": classify_location(relative),
                }
            )

    return results


def write_report(results: dict[str, list[dict]]) -> None:
    sections = []

    sections.append("# YatraCanvas Google Dependency Audit\n")

    sections.append(
        "Generated by `scripts/audit_google_usage.py`.\n\n"
        "This is a static repository scan. A match does not automatically "
        "mean the code executes at runtime.\n"
    )

    for category in [
        "GOOGLE_PLACES",
        "GOOGLE_ROUTES",
        "GOOGLE_MAPS_SDK",
        "OTHER_GOOGLE",
    ]:
        hits = results.get(category, [])

        sections.append(f"\n## {category}\n")
        sections.append(f"\nTotal matches: **{len(hits)}**\n")

        grouped = defaultdict(list)

        for hit in hits:
            grouped[hit["location"]].append(hit)

        for location in [
            "RUNTIME",
            "TEST",
            "SCRIPT",
            "DOCUMENTATION",
            "OTHER",
        ]:
            location_hits = grouped.get(location, [])

            if not location_hits:
                continue

            sections.append(f"\n### {location}\n")

            for hit in location_hits:
                sections.append(
                    f"- `{hit['file']}:{hit['line']}`\n" f"  `{hit['code']}`\n"
                )

    # Runtime-specific summary.
    sections.append("\n# Runtime Summary\n")

    for category in [
        "GOOGLE_PLACES",
        "GOOGLE_ROUTES",
        "GOOGLE_MAPS_SDK",
    ]:
        runtime_hits = [
            hit for hit in results.get(category, []) if hit["location"] == "RUNTIME"
        ]

        sections.append(f"- {category}: {len(runtime_hits)} runtime references\n")

    OUTPUT.write_text(
        "".join(sections),
        encoding="utf-8",
    )


def print_summary(results: dict[str, list[dict]]) -> None:
    print("\nYatraCanvas Google dependency audit\n")

    for category in [
        "GOOGLE_PLACES",
        "GOOGLE_ROUTES",
        "GOOGLE_MAPS_SDK",
        "OTHER_GOOGLE",
    ]:
        hits = results.get(category, [])

        runtime = sum(1 for hit in hits if hit["location"] == "RUNTIME")

        tests = sum(1 for hit in hits if hit["location"] == "TEST")

        docs = sum(1 for hit in hits if hit["location"] == "DOCUMENTATION")

        print(
            f"{category:<20} "
            f"runtime={runtime:<4} "
            f"tests={tests:<4} "
            f"docs={docs:<4} "
            f"total={len(hits)}"
        )

    print(f"\nReport written to:\n{OUTPUT}")


def main() -> None:
    results = scan()
    write_report(results)
    print_summary(results)


if __name__ == "__main__":
    main()
