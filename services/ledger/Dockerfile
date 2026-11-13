# Oneova ledger on Cloud Run. No secrets in the image: DATABASE_URL and the
# auth settings come from Cloud Run env / Secret Manager at deploy time.
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8080
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY ledger ./ledger
COPY migrations ./migrations
COPY config ./config
RUN useradd --system --uid 10001 ledger
USER ledger
CMD exec uvicorn ledger.api:app --host 0.0.0.0 --port ${PORT} --workers 2
