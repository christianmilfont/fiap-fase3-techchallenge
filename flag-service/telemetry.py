import os

from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import (
    OTLPSpanExporter,
)

from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.logging import LoggingInstrumentor
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor


def setup_telemetry(app, service_name: str):
    resource = Resource.create({
        "service.name": service_name
    })

    provider = TracerProvider(resource=resource)

    exporter = OTLPSpanExporter(
        endpoint=os.getenv(
            "OTEL_EXPORTER_OTLP_ENDPOINT",
            "otel-collector:4317"
        ),
        insecure=True,
    )

    provider.add_span_processor(
        BatchSpanProcessor(exporter)
    )

    trace.set_tracer_provider(provider)
    print("OTEL CONFIGURADO:", trace.get_tracer_provider())
    FlaskInstrumentor().instrument_app(app)

    RequestsInstrumentor().instrument()

    BotocoreInstrumentor().instrument()

    LoggingInstrumentor().instrument(set_logging_format=True)