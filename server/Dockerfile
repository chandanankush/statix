# Image is published to Docker Hub as midnightappcoder/statix
# Build locally: docker build -t midnightappcoder/statix server/
# Run locally:   docker run -d -p 5050:5000 -v statix_data:/app/data midnightappcoder/statix

FROM python:3.11-slim

# Git SHA injected by CI (or manual build) so the dashboard can detect stale clients/servers.
ARG GIT_SHA=dev
ENV STATIX_SERVER_VERSION=$GIT_SHA \
    STATIX_EXPECTED_CLIENT_VERSION=$GIT_SHA \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Build context is server/ so paths are relative to that directory
COPY server.py /app/server.py
COPY templates  /app/templates

RUN pip install --no-cache-dir flask gunicorn

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "server:app"]
