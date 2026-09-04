"""Place importance and prominence scoring service.

Normalizes multi-source prominence signals (Wikidata sitelinks and PageRank)
into bounded, explainable importance scores in [0.0, 1.0] without allowing
outliers to overwhelm trip purpose or user interests.
"""

from __future__ import annotations

import json
import logging
import math
from pathlib import Path
from typing import Any, ClassVar

logger = logging.getLogger(__name__)

# Bounded normalization constants derived from Audiala Indian places dataset:
# - sitelinks: median 7, p90 21, p95 30, p99 68, max 180. Capped at 100.
# - pagerank: median 1.085, p90 4.37, p95 7.19, p99 25.16, max 162.185. Capped at 25.
SITELINKS_MAX_REF = 100.0
PAGERANK_MAX_REF = 25.0

SITELINKS_LOG_DENOM = math.log10(SITELINKS_MAX_REF + 1.0)
PAGERANK_LOG_DENOM = math.log10(PAGERANK_MAX_REF + 1.0)

# Blending weights when both signals are present:
# 60% sitelinks (cross-lingual consensus) + 40% PageRank (network link centrality)
W_SITELINKS = 0.60
W_PAGERANK = 0.40


class PlaceImportanceScorer:
    """Computes bounded, explainable prominence scores from Wikidata and Audiala metadata."""

    _audiala_cache: ClassVar[dict[str, tuple[int, float]] | None] = None

    @staticmethod
    def normalize_sitelinks(sitelinks: int | float | None) -> float:
        """Log-normalize sitelinks into [0.0, 1.0], capped at 100 sitelinks."""
        if sitelinks is None:
            return 0.0
        try:
            val = float(sitelinks)
        except (ValueError, TypeError):
            return 0.0
        if val <= 0.0:
            return 0.0
        return min(1.0, max(0.0, math.log10(val + 1.0) / SITELINKS_LOG_DENOM))

    @staticmethod
    def normalize_pagerank(pagerank: float | None) -> float:
        """Log-normalize Wikidata PageRank into [0.0, 1.0], capped at 25.0 (99th percentile)."""
        if pagerank is None:
            return 0.0
        try:
            val = float(pagerank)
        except (ValueError, TypeError):
            return 0.0
        if val <= 0.0:
            return 0.0
        return min(1.0, max(0.0, math.log10(val + 1.0) / PAGERANK_LOG_DENOM))

    @classmethod
    def calculate_prominence(
        cls,
        sitelinks: int | float | None,
        pagerank: float | None,
    ) -> float:
        """Calculate a composite prominence score in [0.0, 1.0].

        Returns 0.0 (neutral) when neither signal is available.
        """
        norm_sl = cls.normalize_sitelinks(sitelinks)
        norm_pr = cls.normalize_pagerank(pagerank)

        if norm_sl > 0.0 and norm_pr > 0.0:
            score = W_SITELINKS * norm_sl + W_PAGERANK * norm_pr
        elif norm_sl > 0.0:
            score = norm_sl
        elif norm_pr > 0.0:
            score = norm_pr
        else:
            score = 0.0

        return round(min(1.0, max(0.0, score)), 4)

    @classmethod
    def extract_prominence_from_tags(cls, tags: Any) -> float:
        """Extract and score prominence from candidate tags (dict or set/list)."""
        if not tags:
            return 0.0

        if isinstance(tags, dict):
            tag_dict = tags
        elif isinstance(tags, (set, list, tuple)):
            tag_dict = {}
            for item in tags:
                if isinstance(item, str) and "=" in item:
                    k, v = item.split("=", 1)
                    tag_dict[k.strip()] = v.strip()
        else:
            return 0.0

        raw_sl = (
            tag_dict.get("audiala:sitelinks")
            or tag_dict.get("sitelinks")
        )
        raw_pr = (
            tag_dict.get("audiala:pagerank")
            or tag_dict.get("wikidata_pagerank")
            or tag_dict.get("pagerank")
        )

        sitelinks: int | None = None
        pagerank: float | None = None

        if raw_sl is not None:
            try:
                sitelinks = int(float(raw_sl))
            except (ValueError, TypeError):
                sitelinks = None

        if raw_pr is not None:
            try:
                pagerank = float(raw_pr)
            except (ValueError, TypeError):
                pagerank = None

        return cls.calculate_prominence(sitelinks=sitelinks, pagerank=pagerank)

    @classmethod
    def extract_metrics_from_tags(
        cls, tags: Any
    ) -> dict[str, str]:
        """Extract raw prominence metrics suitable for PlaceSource.social_identifiers."""
        if not tags:
            return {}

        if isinstance(tags, dict):
            tag_dict = tags
        elif isinstance(tags, (set, list, tuple)):
            tag_dict = {}
            for item in tags:
                if isinstance(item, str) and "=" in item:
                    k, v = item.split("=", 1)
                    tag_dict[k.strip()] = v.strip()
        else:
            return {}

        metrics: dict[str, str] = {}
        raw_sl = tag_dict.get("audiala:sitelinks") or tag_dict.get("sitelinks")
        raw_pr = (
            tag_dict.get("audiala:pagerank")
            or tag_dict.get("wikidata_pagerank")
            or tag_dict.get("pagerank")
        )

        if raw_sl is not None:
            try:
                metrics["sitelinks"] = str(int(float(raw_sl)))
            except (ValueError, TypeError):
                pass

        if raw_pr is not None:
            try:
                metrics["wikidata_pagerank"] = str(round(float(raw_pr), 4))
            except (ValueError, TypeError):
                pass

        return metrics

    @classmethod
    def explain_prominence(
        cls,
        sitelinks: int | float | None,
        pagerank: float | None,
    ) -> dict[str, Any]:
        """Return inspectable components of prominence scoring for explainability and tests."""
        norm_sl = cls.normalize_sitelinks(sitelinks)
        norm_pr = cls.normalize_pagerank(pagerank)
        prominence = cls.calculate_prominence(sitelinks, pagerank)

        signals_present: list[str] = []
        if norm_sl > 0.0:
            signals_present.append("sitelinks")
        if norm_pr > 0.0:
            signals_present.append("wikidata_pagerank")

        return {
            "prominence_score": prominence,
            "sitelinks_normalized": round(norm_sl, 4),
            "pagerank_normalized": round(norm_pr, 4),
            "raw_sitelinks": sitelinks,
            "raw_pagerank": pagerank,
            "signals_present": signals_present,
        }

    @classmethod
    def _get_audiala_lookup(cls) -> dict[str, tuple[int, float]]:
        """Lazy load Audiala dataset index by Wikidata QID."""
        if cls._audiala_cache is not None:
            return cls._audiala_cache

        lookup: dict[str, tuple[int, float]] = {}
        data_path = Path(__file__).resolve().parents[1] / "data" / "audiala_places.json"
        if data_path.exists():
            try:
                with open(data_path, "r", encoding="utf-8") as f:
                    records = json.load(f)
                for r in records:
                    qid = r.get("wikidata_id")
                    if qid:
                        sl = r.get("sitelinks") or 0
                        pr = r.get("wikidata_pagerank") or 0.0
                        lookup[qid.strip().upper()] = (int(sl), float(pr))
                logger.info("Indexed %d Audiala places by QID for prominence fallback", len(lookup))
            except Exception as exc:
                logger.warning("Failed to load Audiala dataset for prominence lookup: %s", exc)

        cls._audiala_cache = lookup
        return cls._audiala_cache

    @classmethod
    def lookup_audiala_prominence(cls, wikidata_id: str | None) -> float | None:
        """Look up prominence from Audiala dataset by Wikidata QID if available."""
        if not wikidata_id:
            return None
        clean_qid = wikidata_id.strip().upper()
        lookup = cls._get_audiala_lookup()
        if clean_qid in lookup:
            sl, pr = lookup[clean_qid]
            score = cls.calculate_prominence(sitelinks=sl, pagerank=pr)
            return score if score > 0.0 else None
        return None

    @classmethod
    def lookup_audiala_metrics(cls, wikidata_id: str | None) -> dict[str, str]:
        """Look up raw prominence metrics from Audiala dataset by Wikidata QID."""
        if not wikidata_id:
            return {}
        clean_qid = wikidata_id.strip().upper()
        lookup = cls._get_audiala_lookup()
        if clean_qid in lookup:
            sl, pr = lookup[clean_qid]
            return {
                "sitelinks": str(sl),
                "wikidata_pagerank": str(round(pr, 4)),
            }
        return {}
