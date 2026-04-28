# syntax=docker/dockerfile:1.7
# Production Dockerfile for the orchestrator (slim variant).
# Multi-stage build keeps the runtime layer free of build tooling.
# Build: docker build -t orchestrator:slim --target runtime .
# Target image size: < 250 MB compressed.

ARG PYTHON_VERSION=3.11

# ---------- Stage 1: builder ----------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# Build deps (kept only in this stage). git is needed by setuptools-scm
# to derive the version when building from a checkout.
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

COPY pyproject.toml README.md ./
COPY orchestrator ./orchestrator

# `--user` install lands everything under /root/.local so the runtime
# stage can copy it as a single self-contained tree.
RUN pip install --user --no-cache-dir .

# ---------- Stage 2: runtime ----------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS runtime

# OCI image labels (https://github.com/opencontainers/image-spec)
LABEL org.opencontainers.image.source="https://github.com/skgandikota/orchestrator" \
      org.opencontainers.image.title="orchestrator" \
      org.opencontainers.image.description="Local-first agent orchestrator (slim runtime image)." \
      org.opencontainers.image.licenses="CC-BY-NC-SA-4.0" \
      org.opencontainers.image.url="https://github.com/skgandikota/orchestrator" \
      org.opencontainers.image.documentation="https://github.com/skgandikota/orchestrator/blob/main/docs/DEPLOY.md"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/home/orchestrator/.local/bin:${PATH}" \
    ORCHESTRATOR_CONFIG=/etc/orchestrator/config.yaml \
    ORCHESTRATOR_DATA_DIR=/var/lib/orchestrator

# curl is needed for the HEALTHCHECK; tini gives us a proper PID 1.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl tini \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* \
    && groupadd --system --gid 1000 orchestrator \
    && useradd  --system --uid 1000 --gid 1000 --create-home --shell /usr/sbin/nologin orchestrator \
    && mkdir -p /etc/orchestrator /var/lib/orchestrator /app \
    && chown -R orchestrator:orchestrator /etc/orchestrator /var/lib/orchestrator /app

# Bring the installed package + console scripts from the builder.
COPY --from=builder --chown=orchestrator:orchestrator /root/.local /home/orchestrator/.local

WORKDIR /app

USER orchestrator

VOLUME ["/etc/orchestrator", "/var/lib/orchestrator"]

# OpenAI-compatible HTTP API. MCP-stdio is intentionally NOT exposed:
# attach via `docker exec -i` or `docker run -i ... mcp`.
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl --fail --silent http://localhost:8000/v1/models || exit 1

ENTRYPOINT ["tini", "--", "python", "-m", "orchestrator"]
CMD ["serve"]
