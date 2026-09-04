"""In-memory circuit breaker for external POI providers."""

from __future__ import annotations

import logging
import time
from enum import Enum

logger = logging.getLogger(__name__)


class CircuitState(str, Enum):
    CLOSED = "closed"
    OPEN = "open"
    HALF_OPEN = "half_open"


class ProviderCircuitBreaker:
    """Lightweight deterministic circuit breaker for bounding provider failure penalties."""

    def __init__(
        self,
        name: str,
        *,
        failure_threshold: int = 3,
        cooldown_seconds: float = 60.0,
    ) -> None:
        self.name = name
        self.failure_threshold = failure_threshold
        self.cooldown_seconds = cooldown_seconds
        self._failure_count = 0
        self._state = CircuitState.CLOSED
        self._last_state_change: float = 0.0

    @property
    def state(self) -> CircuitState:
        now = time.monotonic()
        if self._state == CircuitState.OPEN:
            if now - self._last_state_change >= self.cooldown_seconds:
                self._state = CircuitState.HALF_OPEN
                self._last_state_change = now
                logger.info(
                    "Circuit breaker %s entered HALF_OPEN state after %.1fs cooldown",
                    self.name,
                    self.cooldown_seconds,
                )
        return self._state

    def allow_request(self) -> bool:
        """Return True if a request to the provider is allowed."""
        return self.state in (CircuitState.CLOSED, CircuitState.HALF_OPEN)

    def record_success(self) -> None:
        """Reset failure counter and return circuit to CLOSED."""
        if self._state != CircuitState.CLOSED:
            logger.info("Circuit breaker %s recovered to CLOSED state", self.name)
        self._state = CircuitState.CLOSED
        self._failure_count = 0
        self._last_state_change = time.monotonic()

    def record_failure(self, error: Exception | None = None) -> None:
        """Increment failure counter and transition to OPEN if threshold reached."""
        self._failure_count += 1
        now = time.monotonic()
        if self._state == CircuitState.HALF_OPEN or self._failure_count >= self.failure_threshold:
            self._state = CircuitState.OPEN
            self._last_state_change = now
            logger.warning(
                "Circuit breaker %s tripped to OPEN (failures=%d, error=%s). Skipping provider for %.1fs.",
                self.name,
                self._failure_count,
                error,
                self.cooldown_seconds,
            )

    def reset(self) -> None:
        """Reset breaker to clean initial state (useful for tests)."""
        self._failure_count = 0
        self._state = CircuitState.CLOSED
        self._last_state_change = 0.0
