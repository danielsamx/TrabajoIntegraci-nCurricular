# Simulador de mano protésica / Prosthetic hand simulator
# Python 3.13 + FastAPI. Un solo proceso: el estado vive en memoria.
# Python 3.13 + FastAPI. A single process: state lives in memory.

FROM python:3.13-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /srv
COPY requirements.txt .
RUN pip install -r requirements.txt

# --- pruebas / tests: docker compose --profile test run --rm tests
FROM base AS test
COPY requirements-dev.txt .
RUN pip install -r requirements-dev.txt
COPY pytest.ini .
COPY app ./app
COPY static ./static
COPY tests ./tests
CMD ["python", "-m", "pytest", "-q"]

# --- ejecución / runtime
FROM base AS runtime
COPY app ./app
COPY static ./static
RUN useradd --system --uid 10001 --no-create-home sim
USER sim
EXPOSE 8000
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/state', timeout=2).status == 200 else 1)"]
# --workers 1: con más procesos habría varias manos. / more processes = several hands.
# --no-access-log: no se registran ejecuciones. / executions are not logged.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log", "--ws-ping-interval", "20"]
