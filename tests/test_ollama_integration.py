"""Real-daemon integration test for the Ollama adapter.

Skipped by default per ``CONTRIBUTING.md`` -- run with ``pytest -m ollama``
after starting an Ollama daemon and pulling ``qwen2.5:7b``.
"""

from __future__ import annotations

import pytest

from orchestrator.config.settings import load_settings
from orchestrator.models.ollama_local import OllamaLocalAdapter


@pytest.mark.ollama
def test_load_verify_unload_cycle_against_real_daemon() -> None:
    settings = load_settings().ollama
    adapter = OllamaLocalAdapter(
        base_url=settings.base_url,
        request_timeout_s=settings.request_timeout_s,
        keep_alive=settings.keep_alive,
    )
    model = settings.reasoning_model
    try:
        adapter.load(model)
        assert adapter.verify_loaded(model) is True
        adapter.unload(model)
        assert adapter.verify_unloaded(model) is True
    finally:
        adapter.close()
