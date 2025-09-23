FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml setup.py README.md /app/
COPY system_stats /app/system_stats
COPY service /app/service

RUN pip install --no-cache-dir .

EXPOSE 5001

CMD ["system-stats-service"]
