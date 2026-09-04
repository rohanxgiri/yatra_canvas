"""Unit tests for ProviderCircuitBreaker."""

import time
from app.services.provider_circuit_breaker import CircuitState, ProviderCircuitBreaker


def test_circuit_breaker_starts_closed():
    cb = ProviderCircuitBreaker("test_provider", failure_threshold=3, cooldown_seconds=10.0)
    assert cb.state == CircuitState.CLOSED
    assert cb.allow_request() is True


def test_circuit_breaker_trips_to_open_after_threshold():
    cb = ProviderCircuitBreaker("test_provider", failure_threshold=3, cooldown_seconds=10.0)

    cb.record_failure(ValueError("err1"))
    assert cb.state == CircuitState.CLOSED
    assert cb.allow_request() is True

    cb.record_failure(ValueError("err2"))
    assert cb.state == CircuitState.CLOSED
    assert cb.allow_request() is True

    cb.record_failure(ValueError("err3"))
    assert cb.state == CircuitState.OPEN
    assert cb.allow_request() is False


def test_circuit_breaker_cooldown_to_half_open_and_recovery():
    cb = ProviderCircuitBreaker("test_provider", failure_threshold=2, cooldown_seconds=0.05)

    cb.record_failure(ValueError("err1"))
    cb.record_failure(ValueError("err2"))
    assert cb.state == CircuitState.OPEN
    assert cb.allow_request() is False

    # Wait for cooldown
    time.sleep(0.06)
    assert cb.state == CircuitState.HALF_OPEN
    assert cb.allow_request() is True

    # Successful probe restores CLOSED
    cb.record_success()
    assert cb.state == CircuitState.CLOSED
    assert cb.allow_request() is True


def test_circuit_breaker_half_open_failure_immediately_opens():
    cb = ProviderCircuitBreaker("test_provider", failure_threshold=2, cooldown_seconds=0.05)

    cb.record_failure(ValueError("err1"))
    cb.record_failure(ValueError("err2"))
    assert cb.state == CircuitState.OPEN

    time.sleep(0.06)
    assert cb.state == CircuitState.HALF_OPEN

    # Failure in HALF_OPEN trips immediately back to OPEN
    cb.record_failure(ValueError("err_probe"))
    assert cb.state == CircuitState.OPEN
    assert cb.allow_request() is False
