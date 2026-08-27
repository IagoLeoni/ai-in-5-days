# syntax=docker/dockerfile:1.7
###############################################################################
# StackScribe agent container.
#
# Multi-stage so the runtime image carries no build toolchain, and runs as a
# non-root user. No secret is ever baked in: credentials are resolved at runtime
# from Secret Manager using the Cloud Run service account's workload identity.
###############################################################################

FROM python:3.12-slim AS builder

ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

# Dependency layer first, so a source-only change does not invalidate it.
COPY pyproject.toml README.md ./
COPY stack_scribe/__init__.py stack_scribe/__init__.py

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install ".[gcp]"

COPY stack_scribe/ stack_scribe/
RUN /opt/venv/bin/pip install --no-deps .


###############################################################################
# Runtime
###############################################################################
FROM python:3.12-slim AS runtime

# Non-root: a container that can publish to a public blog should not also be
# able to rewrite its own filesystem.
RUN groupadd --system --gid 1001 stackscribe \
    && useradd --system --uid 1001 --gid stackscribe --create-home stackscribe

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # Vertex AI via workload identity: no API key in the image or the env.
    GOOGLE_GENAI_USE_VERTEXAI=1 \
    STACKSCRIBE_ENABLE_CLOUD_TRACE=1 \
    STACKSCRIBE_SESSION_BACKEND=database \
    # The human-in-the-loop publish gate ships on. config.py additionally
    # refuses to boot in prod with it disabled.
    STACKSCRIBE_REQUIRE_PUBLISH_CONFIRMATION=1 \
    PORT=8080

COPY --from=builder /opt/venv /opt/venv
COPY --chown=stackscribe:stackscribe stack_scribe/ /app/stack_scribe/

WORKDIR /app
USER stackscribe

EXPOSE 8080

# Fail fast and loudly if the agent tree cannot be constructed, rather than
# serving a broken revision.
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD python -c "from stack_scribe.agent import app; assert app.root_agent" || exit 1

# `adk api_server` serves the agent over HTTP. `--host 0.0.0.0` is required for
# Cloud Run to route traffic to the container.
CMD ["sh", "-c", "adk api_server --host 0.0.0.0 --port ${PORT} /app"]
