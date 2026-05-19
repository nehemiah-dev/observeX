"""
FastAPI demo app — instrumented with OpenTelemetry.
Emits traces to Tempo via OTel Collector, logs to stdout (picked up by OTel Collector → Loki),
and exposes Prometheus metrics via prometheus-fastapi-instrumentator.
"""

import logging
import random
import time

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_fastapi_instrumentator import Instrumentator

# ── Logging (structured, picked up by OTel Collector → Loki) ──────────────────
logging.basicConfig(
    level=logging.INFO,
    format='{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","message":"%(message)s","trace_id":"%(otelTraceID)s","span_id":"%(otelSpanID)s"}',
)
log = logging.getLogger("demo-app")

# ── OpenTelemetry tracing setup ───────────────────────────────────────────────
resource = Resource.create({"service.name": "demo-app", "service.version": "1.0.0"})
tracer_provider = TracerProvider(resource=resource)
otlp_exporter = OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True)
tracer_provider.add_span_processor(BatchSpanProcessor(otlp_exporter))
trace.set_tracer_provider(tracer_provider)
tracer = trace.get_tracer("demo-app")

# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(title="LGTM Demo App", version="1.0.0")

# Expose /metrics for Prometheus
Instrumentator().instrument(app).expose(app)

# Auto-instrument all routes with OTel spans
FastAPIInstrumentor.instrument_app(app)


# ── Routes ────────────────────────────────────────────────────────────────────


@app.get("/")
def root():
    log.info("root endpoint hit")
    return {"status": "ok", "service": "demo-app"}


@app.get("/items/{item_id}")
def get_item(item_id: int):
    """Simulates a DB lookup with realistic latency."""
    with tracer.start_as_current_span("db.query") as span:
        span.set_attribute("db.system", "postgresql")
        span.set_attribute("db.statement", f"SELECT * FROM items WHERE id={item_id}")
        latency = random.uniform(0.01, 0.15)
        time.sleep(latency)
        if item_id > 900:
            log.warning("item_id out of range", extra={"item_id": item_id})
            raise HTTPException(status_code=404, detail="Item not found")
    log.info(
        "item fetched",
        extra={"item_id": item_id, "latency_ms": round(latency * 1000, 2)},
    )
    return {
        "item_id": item_id,
        "name": f"Item {item_id}",
        "latency_ms": round(latency * 1000, 2),
    }


@app.get("/slow")
def slow_endpoint():
    """Intentionally slow — used in latency injection game-day scenario."""
    with tracer.start_as_current_span("slow.operation") as span:
        delay = random.uniform(0.5, 2.0)
        span.set_attribute("simulated.delay_ms", round(delay * 1000))
        time.sleep(delay)
    log.warning("slow response", extra={"delay_ms": round(delay * 1000, 2)})
    return {"status": "slow", "delay_ms": round(delay * 1000, 2)}


@app.get("/error")
def error_endpoint():
    """Returns 5xx — used to drive up error rate / CFR metrics."""
    log.error("simulated application error")
    raise HTTPException(status_code=500, detail="Simulated server error")


@app.get("/health")
def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8080)
