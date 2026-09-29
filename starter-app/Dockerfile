# =========================
# Etape 3                
# =========================
# Stage 1 : builder
# =========================
FROM python:3.12 AS builder

WORKDIR /app

COPY requirements.txt .

RUN python -m venv /opt/venv \
    && /opt/venv/bin/pip install --upgrade pip \
    && /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# =========================
# Stage 2 : runtime
# =========================
FROM python:3.12-slim AS runtime

ENV PATH="/opt/venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

RUN useradd \
    --create-home \
    --shell /usr/sbin/nologin \
    appuser

COPY --from=builder /opt/venv /opt/venv

COPY --chown=appuser:appuser . .

USER appuser

EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:5000/health', timeout=2)"

CMD ["gunicorn", "--bind", "0.0.0.0:5000", "app:app"]

# =========================
# Etape 2                
# =========================
# FROM python:3.12

# WORKDIR /app

# COPY requirements.txt .

# RUN pip install --no-cache-dir -r requirements.txt

# RUN useradd \
#     --create-home \
#     --shell /usr/sbin/nologin \
#     appuser

# COPY --chown=appuser:appuser . .

# USER appuser

# EXPOSE 5000

# CMD ["flask", "--app", "app", "run", "--host=0.0.0.0", "--port=5000"]
