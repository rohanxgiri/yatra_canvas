"""Stage timing and provider outcome diagnostics for live POI discovery."""

from __future__ import annotations

import logging
import time
from contextlib import contextmanager
from dataclasses import dataclass, field
from enum import Enum
from typing import Generator

logger = logging.getLogger(__name__)


class ProviderOutcome(str, Enum):
    SUCCESS = "success"
    TIMEOUT = "timeout"
    NETWORK_ERROR = "network_error"
    RATE_LIMITED = "rate_limited"
    PROVIDER_ERROR = "provider_error"
    SKIPPED_CACHE_SUFFICIENT = "skipped_cache_sufficient"
    CIRCUIT_OPEN = "circuit_open"


@dataclass
class DiscoveryDiagnostics:
    destination: str
    stage_timings_ms: dict[str, float] = field(default_factory=dict)
    provider_outcomes: dict[str, ProviderOutcome] = field(default_factory=dict)
    _start_time: float = field(default_factory=time.monotonic)

    @contextmanager
    def measure(self, stage_name: str) -> Generator[None, None, None]:
        t0 = time.monotonic()
        try:
            yield
        finally:
            elapsed_ms = (time.monotonic() - t0) * 1000.0
            self.stage_timings_ms[stage_name] = round(elapsed_ms, 1)

    def record_outcome(self, provider_key: str, outcome: ProviderOutcome) -> None:
        self.provider_outcomes[provider_key] = outcome

    def finalize(self) -> str:
        total_elapsed_ms = (time.monotonic() - self._start_time) * 1000.0
        self.stage_timings_ms["total"] = round(total_elapsed_ms, 1)

        timings_str = " ".join(
            f"{k}={v:.0f}ms" for k, v in self.stage_timings_ms.items() if k != "total"
        )
        outcomes_str = " ".join(
            f"{k}={v.value}" for k, v in self.provider_outcomes.items()
        )
        summary = (
            f"destination={self.destination} "
            f"{timings_str} "
            f"{outcomes_str} "
            f"total={self.stage_timings_ms['total']:.0f}ms"
        ).strip()
        logger.info("Discovery diagnostics: %s", summary)
        return summary
