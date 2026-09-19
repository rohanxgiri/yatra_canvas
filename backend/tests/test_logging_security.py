import logging

from app import main  # noqa: F401 - importing installs the production log policy


def test_provider_http_loggers_do_not_emit_sensitive_urls_at_info() -> None:
    assert logging.getLogger("httpx").getEffectiveLevel() >= logging.WARNING
    assert logging.getLogger("httpcore").getEffectiveLevel() >= logging.WARNING
