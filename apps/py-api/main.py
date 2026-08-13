import os
import time

from fastapi import FastAPI

app = FastAPI(title="py-api", version="0.1.0")

PORT = int(os.environ.get("PORT", "3000"))


@app.get("/")
def root():
    return {"app": "py-api", "message": "Mini-PaaS demo API (FastAPI)"}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/work")
def work(ms: int = 2000):
    """CPU burn for the autoscaling demo. `ms` caps at 10s."""
    ms = min(ms, 10000)
    end = time.monotonic() + ms / 1000.0
    while time.monotonic() < end:
        pass  # busy loop
    return {"app": "py-api", "burned": ms, "pid": os.getpid()}
