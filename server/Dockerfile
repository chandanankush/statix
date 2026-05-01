# Image is published to Docker Hub as chandanankush/statix
# Build locally: docker build -t chandanankush/statix server/
# Run locally:   docker run -d -p 5050:5000 -v statix_data:/app/data chandanankush/statix

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
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
