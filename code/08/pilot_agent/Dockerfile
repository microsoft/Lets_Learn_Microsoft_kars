FROM ghcr.io/azure/kars-runtime-maf-python:v0.1.25

ARG PIP_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple/
ENV PIP_INDEX_URL=${PIP_INDEX_URL} \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

LABEL org.kars.runtime.contract="v1"
LABEL org.kars.runtime.kind="MicrosoftAgentFramework"
LABEL org.kars.runtime.language="python"
LABEL org.opencontainers.image.title="fabrikam-release-pilot"
LABEL org.opencontainers.image.description="OpenClaw-first MAF Builder for KARS"

USER root
WORKDIR /opt/fabrikam-agent
COPY requirements.txt .
RUN pip install --no-cache-dir --requirement requirements.txt
COPY --chown=1000:1000 app.py ./main.py
COPY --chown=1000:1000 controls.py workflow.py ./
COPY entrypoint.sh /usr/local/bin/fabrikam-maf-entrypoint.sh
RUN chmod 0755 /usr/local/bin/fabrikam-maf-entrypoint.sh

USER 1000
WORKDIR /tmp
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/fabrikam-maf-entrypoint.sh"]
CMD ["python3", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
