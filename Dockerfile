# syntax=docker/dockerfile:1.7
# ---- Builder Stage ----
FROM python:3.14-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /install

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt

# ---- Final Stage ----
FROM python:3.14-slim

# Pull in the latest debian security patches.
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH"

WORKDIR /immich_drop

# Copy static ffmpeg binaries
COPY --from=mwader/static-ffmpeg:7.1 /ffmpeg /usr/local/bin/ffmpeg
COPY --from=mwader/static-ffmpeg:7.1 /ffprobe /usr/local/bin/ffprobe

# Copy virtualenv from builder
COPY --from=builder /opt/venv /opt/venv

# Create a non-root user
RUN groupadd -g 1000 appuser && \
    useradd -u 1000 -g appuser -s /bin/bash -m appuser

# Copy app code
COPY . /immich_drop

# Create data directory and set permissions
RUN mkdir -p /data && \
    chown -R appuser:appuser /immich_drop /data

# Switch to non-root user
USER appuser

# Defaults (can be overridden via compose env)
ARG APP_VERSION
ENV APP_VERSION=${APP_VERSION} \
    HOST=0.0.0.0 \
    PORT=8080 \
    STATE_DB=/data/state.db

EXPOSE 8080

# Reads PORT so the check follows a non-default port; /api/config is a cheap
# JSON response that never redirects, unlike / which 302s to /login when the
# public upload page is disabled.
HEALTHCHECK --interval=30s --timeout=5s --retries=3 --start-period=10s \
  CMD python -c 'import os,urllib.request; urllib.request.urlopen("http://127.0.0.1:%s/api/config" % os.getenv("PORT","8080"), timeout=3).read()'

CMD ["python", "main.py"]
