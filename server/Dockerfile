# docker build -f server/Dockerfile -t monitoring-server:latest
# docker save monitoring-server:latest -o monitoring-server.tar
# docker run --rm -p 5050:5000 monitoring-server:latest

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY server/server.py /app/server.py
COPY server/templates /app/templates

RUN pip install --no-cache-dir flask gunicorn

EXPOSE 5000

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "server:app"]
