FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py ./

# Run as non-root (REQ-6-5): uid 65534 is the "nobody" user.
USER 65534

EXPOSE 3000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3000"]
# build 2026-08-13 v6
