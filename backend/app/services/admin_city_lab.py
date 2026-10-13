"""Read immutable releases; delegate research, identity and validation to DataFactory.

This adapter never writes into the configured release or DataFactory checkout.
Human corrections live in backend overlays and can be exported as base-bound patches.
"""

import hashlib
import importlib
import json
import math
import sys
from datetime import datetime
from functools import lru_cache
from pathlib import Path

from fastapi import HTTPException

from app.core.config import BACKEND_DIR, get_settings


@lru_cache(maxsize=32)
def read_json(path: str, modified: int):
    file = Path(path)
    if file.stat().st_size > 150_000_000:
        raise ValueError("Artifact exceeds the supported size")
    return json.loads(file.read_text(encoding="utf-8"))


def read(path: Path, default=None):
    return read_json(str(path), path.stat().st_mtime_ns) if path.is_file() else default


class CityLabService:
    def __init__(self):
        self.settings = get_settings()
        self.inventory_problems = []
        self.root = (
            Path(self.settings.admin_release_root).resolve()
            if self.settings.admin_release_root
            else None
        )

    def releases(self):
        self.inventory_problems = []
        if self.root is None or not self.root.is_dir():
            return []
        result = []
        # Canonical releases use country/state/city/version, never arbitrary paths.
        for manifest in self.root.glob("*/*/*/*/manifest.json"):
            pack = manifest.parent.resolve()
            if (
                not pack.is_relative_to(self.root)
                or not (pack / "places.json").is_file()
            ):
                continue
            key = hashlib.sha256(
                pack.relative_to(self.root).as_posix().encode()
            ).hexdigest()[:32]
            try:
                meta = read(manifest, {})
                city = read(pack / "city.json", {})
                if not isinstance(meta, dict) or not isinstance(city, dict) or not city.get("id"):
                    raise ValueError("Invalid release metadata")
            except (OSError, ValueError, TypeError):
                self.inventory_problems.append({"release_key": key, "reason": "Release metadata is unreadable or invalid. Check the release files and access permissions."})
                continue
            result.append((key, pack, meta, city))
        return result

    def release(self, key):
        for row in self.releases():
            if row[0] == key:
                return row
        raise HTTPException(status_code=404, detail="Canonical release not found.")

    def module(self, name):
        checkout = self.settings.datafactory_checkout
        if not checkout or not (Path(checkout).resolve() / "datafactory").is_dir():
            raise HTTPException(
                status_code=503,
                detail="Configure the DataFactory adapter to use this workflow.",
            )
        path = str(Path(checkout).resolve())
        if path not in sys.path:
            sys.path.insert(0, path)
        previous = sys.dont_write_bytecode
        sys.dont_write_bytecode = True
        try:
            # DataFactory's default lazy settings create checkout directories.
            # Seed a read settings instance so QA does not mutate that repository.
            config = importlib.import_module("datafactory.config.settings")
            if (
                config._settings is None
                or str(config._settings.project_root.resolve()) != path
            ):
                config._settings = config.Settings(project_root=Path(path))
            return importlib.import_module("datafactory." + name)
        except ImportError as exc:
            raise HTTPException(
                status_code=503,
                detail="DataFactory runtime dependencies are unavailable.",
            ) from exc
        finally:
            sys.dont_write_bytecode = previous

    def fingerprint(self, pack):
        names = (
            "places.json",
            "city.json",
            "media_assurance.json",
            "field_provenance.json",
            "checksums.json",
        )
        return {
            name: hashlib.sha256((pack / name).read_bytes()).hexdigest()
            for name in names
            if (pack / name).is_file()
        }

    def digest(self, pack):
        return hashlib.sha256(
            json.dumps(self.fingerprint(pack), sort_keys=True).encode()
        ).hexdigest()

    def artifact_root(self):
        path = Path(self.settings.admin_artifact_root)
        path = (path if path.is_absolute() else BACKEND_DIR / path).resolve()
        protected = [
            self.root,
            Path(self.settings.datafactory_checkout).resolve()
            if self.settings.datafactory_checkout
            else None,
        ]
        if any(root is not None and path.is_relative_to(root) for root in protected):
            raise HTTPException(
                503,
                "Admin artifacts must be outside canonical and DataFactory directories.",
            )
        return path

    def places(self, pack):
        rows = read(pack / "places.json", [])
        if not isinstance(rows, list):
            raise TypeError("Unsupported canonical records")
        return rows

    @staticmethod
    def local_file(pack, relative):
        if not isinstance(relative, str) or not relative or "\\" in relative:
            return None
        path = (pack / relative).resolve()
        return path if path.is_relative_to(pack.resolve()) and path.is_file() else None

    def issues(self, pack, place):
        issues = []
        image = place.get("images", {}).get("primary") or {}
        if not image or not self.local_file(pack, image.get("local_path")):
            issues.append("missing_image")
        if not place.get("opening_hours", {}).get("normalized"):
            issues.append("missing_hours")
        if not place.get("description"):
            issues.append("missing_description")
        if not place.get("contact", {}).get("website"):
            issues.append("missing_website")
        location = place.get("location", {})
        lat, lon = location.get("latitude"), location.get("longitude")
        if lat is None or lon is None or not -90 <= lat <= 90 or not -180 <= lon <= 180:
            issues.append("missing_coordinates")
        assurance = read(pack / "media_assurance.json", {}).get(place.get("id"), {})
        if assurance.get("coordinate", {}).get("status") in {"SUSPICIOUS", "CONFLICT"} or assurance.get("geography", {}).get("status") in {"INVALID", "OUTSIDE_REGION", "OUTSIDE_CITY"}:
            issues.append("suspicious_coordinates")
        for media in place.get("images", {}).get("gallery", []):
            if not self.local_file(
                pack, media.get("local_path")
            ) or not self.local_file(pack, media.get("thumbnail_path")):
                issues.append("broken_gallery")
                break
        return issues

    def city(self, row):
        key, pack, meta, city = row
        try:
            places = self.places(pack)
        except (OSError, ValueError, TypeError) as exc:
            raise HTTPException(503, "Canonical records are unreadable or invalid. Check the release files.") from exc
        counts = {
            issue: 0
            for issue in (
                "missing_image",
                "missing_hours",
                "missing_description",
                "missing_website",
                "missing_coordinates",
                "suspicious_coordinates",
                "broken_gallery",
            )
        }
        for place in places:
            for issue in self.issues(pack, place):
                counts[issue] += 1
        # Scores may ONLY come from an actual City Lab export for this version.
        lab, evidence_problem = self.lab_evidence(key, city, pack)
        return {
            "id": key,
            "canonical_city_id": city.get("id"),
            "name": city.get("name", meta.get("city_name", "Unknown city")),
            "state": city.get("state"),
            "country": city.get("country"),
            "pack_version": pack.name,
            "schema_version": meta.get("schema_version"),
            "published_places": len(places),
            "raw_counts": meta.get("counts", {}),
            "quality": counts,
            "coverage": {
                k: (len(places) - v) / len(places) if places else 0
                for k, v in counts.items()
            },
            "generated_at": meta.get("generated_at"),
            "fingerprint": self.digest(pack),
            "readiness": lab or None,
            "readiness_problem": evidence_problem,
            "readiness_scope": "City Lab exported evaluation, matched by city and version. The export has no canonical content fingerprint; it does not certify these canonical bytes.",
            "usability": read(pack / "usability.json", {}),
            "pipeline_health": meta.get("pipeline_health"),
            "data_quality": meta.get("data_quality"),
            "source_coverage": meta.get("source_coverage"),
            "reported_gate_status": lab.get("release_gate_status") if lab else None,
            "status": (
                lab["release_gate_status"].replace(" ", "_")
                if lab and lab["release_gate_status"] != "READY"
                else "NOT_CERTIFIED"
            ),
            "capabilities": {
                "validate": bool(self.settings.datafactory_checkout),
                "build": bool(self.settings.datafactory_checkout),
                "publish": False,
                "merge": False,
            },
        }

    def lab_evidence(self, key, city, pack):
        """Validate the real Lab export contract, never recompute Lab scores.

        CityPack Lab's schema 1 export has no source-content hash. Matching a
        version is sufficient for displaying a reported evaluation, not for
        claiming that the configured canonical release has been certified.
        """
        path = self.artifact_root() / "lab_reports" / key / "release.json"
        if not path.is_file():
            return {}, "City Lab has not supplied an evaluation for this release."
        try:
            lab = read(path, {})
            if not isinstance(lab, dict) or (
                type(lab.get("schema_version")) is not int
                or lab.get("schema_version") != 1
                or lab.get("release_source") != "citypack_lab"
                or lab.get("city_id") != city.get("id")
                or lab.get("pack_version") != pack.name
            ):
                raise ValueError("Unsupported or mismatched City Lab evaluation.")
            for field in ("data_quality_score", "travel_readiness_score"):
                value = lab.get(field)
                if type(value) not in (int, float) or not math.isfinite(value) or not 0 <= value <= 100:
                    raise ValueError("City Lab scores are missing or invalid.")
            reviewed = lab.get("manual_qa_reviewed_count")
            minimum = lab.get("manual_qa_minimum_required")
            critical = lab.get("criticalIssues")
            if type(reviewed) is not int or reviewed < 0 or type(minimum) is not int or minimum <= 0 or type(critical) is not int or critical < 0:
                raise ValueError("City Lab manual review evidence is invalid.")
            gate = lab.get("release_gate_status")
            if gate not in {"READY", "BLOCKED", "REVIEW REQUIRED", "REVIEW_REQUIRED"}:
                raise ValueError("City Lab gate status is unsupported.")
            checks = lab.get("validation_summary")
            if not isinstance(checks, dict) or not checks or any(type(v) is not bool for v in checks.values()):
                raise ValueError("City Lab gate checks are missing or invalid.")
            timestamp = lab.get("generated_at")
            if not isinstance(timestamp, str) or datetime.fromisoformat(timestamp.replace("Z", "+00:00")).tzinfo is None:
                raise ValueError("City Lab evaluation time is missing or invalid.")
            if gate == "READY" and (
                reviewed < minimum or lab.get("manual_qa_passed") is not True
                or critical != 0 or not all(checks.values())
                or lab.get("status") != "certified" or not lab.get("certified_at")
            ):
                raise ValueError("City Lab readiness contradicts its review or blocker evidence.")
            return lab, None
        except (ValueError, TypeError, KeyError, OSError):
            return {}, "City Lab evaluation is invalid, mismatched, or incomplete. Export it again from City Lab; no readiness score has been assumed."

    def task_inventory(self, key):
        _, pack, _, city = self.release(key)
        # The original DataFactory task generator owns priorities/evidence rules.
        return self.module("research.export").make_tasks(self.places(pack), city, pack)
