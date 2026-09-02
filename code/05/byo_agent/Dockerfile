FROM python:3.12-slim

ARG PIP_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple/
ENV PIP_INDEX_URL=${PIP_INDEX_URL} \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

LABEL org.kars.runtime.contract="v1"
LABEL org.opencontainers.image.title="forge-byo-copilot-claw"
LABEL org.opencontainers.image.description="Bounded KARS BYO runtime for GPT-5.6-Sol"

RUN groupadd --gid 1000 sandbox \
    && useradd --uid 1000 --gid 1000 --home-dir /sandbox --create-home sandbox

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt
COPY app.py workflow.py ./

USER 1000
EXPOSE 8080
ENTRYPOINT ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
