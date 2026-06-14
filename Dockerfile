FROM mcr.microsoft.com/playwright:v1.60.0-noble

WORKDIR /app
COPY get_forti_cookie.py .

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-pip python3-venv \
    && python3 -m venv /venv \
    && /venv/bin/pip install playwright==1.60.0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

VOLUME ["/output"]

ENTRYPOINT ["/venv/bin/python3", "get_forti_cookie.py"]
