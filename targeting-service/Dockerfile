FROM ghcr.io/astral-sh/uv:python3.11-bookworm-slim AS builder
WORKDIR /app
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

FROM python:3.11-slim
ENV TZ=America/Sao_Paulo
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y tzdata postgresql-client && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /app/.venv /app/.venv
COPY app.py .
COPY db/init.sql .
COPY entrypoint.sh .
RUN chmod +x ./entrypoint.sh
ENV PATH="/app/.venv/bin:$PATH"
EXPOSE 8003
ENTRYPOINT ["./entrypoint.sh"]
