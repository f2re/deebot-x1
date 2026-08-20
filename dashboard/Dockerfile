FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --system --uid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin deebot
COPY app.py .
COPY static ./static
ENV PYTHONUNBUFFERED=1
USER 10001:10001
CMD ["python", "/app/app.py"]
