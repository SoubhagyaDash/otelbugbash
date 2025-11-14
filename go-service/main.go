package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net/http"
	"os"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetrichttp"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/metric"
	"go.opentelemetry.io/otel/propagation"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

var (
	tracer       trace.Tracer
	meter        metric.Meter
	cowsSold     metric.Int64Counter
	requestCount metric.Int64Counter
)

type HealthResponse struct {
	Status    string `json:"status"`
	Service   string `json:"service"`
	Timestamp string `json:"timestamp"`
}

type ComputeResponse struct {
	Service       string  `json:"service"`
	Timestamp     string  `json:"timestamp"`
	ComputeTimeMs int     `json:"computeTimeMs"`
	RandomValue   int     `json:"randomValue"`
	Result        float64 `json:"result"`
}

type ErrorResponse struct {
	Error     string `json:"error"`
	Service   string `json:"service"`
	Timestamp string `json:"timestamp"`
}

func initTracer() (*sdktrace.TracerProvider, error) {
	ctx := context.Background()

	// Create OTLP HTTP exporter
	// Will use OTEL_EXPORTER_OTLP_ENDPOINT or OTEL_EXPORTER_OTLP_TRACES_ENDPOINT env var
	exporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithInsecure(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP exporter: %w", err)
	}

	// Create resource
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("go-service"),
			semconv.ServiceVersion("1.0.0"),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	// Create tracer provider
	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(exporter),
		sdktrace.WithResource(res),
	)

	otel.SetTracerProvider(tp)
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
		propagation.TraceContext{},
		propagation.Baggage{},
	))

	return tp, nil
}

func initMeter() (*sdkmetric.MeterProvider, error) {
	ctx := context.Background()

	// Create OTLP HTTP metrics exporter
	// Will use OTEL_EXPORTER_OTLP_ENDPOINT or OTEL_EXPORTER_OTLP_METRICS_ENDPOINT env var
	exporter, err := otlpmetrichttp.New(ctx,
		otlpmetrichttp.WithInsecure(),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create OTLP metrics exporter: %w", err)
	}

	// Create resource
	res, err := resource.New(ctx,
		resource.WithAttributes(
			semconv.ServiceName("go-service"),
			semconv.ServiceVersion("1.0.0"),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("failed to create resource: %w", err)
	}

	// Create meter provider
	mp := sdkmetric.NewMeterProvider(
		sdkmetric.WithReader(sdkmetric.NewPeriodicReader(exporter)),
		sdkmetric.WithResource(res),
	)

	otel.SetMeterProvider(mp)

	return mp, nil
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	_, span := tracer.Start(ctx, "health-check",
		trace.WithSpanKind(trace.SpanKindServer),
	)
	defer span.End()

	response := HealthResponse{
		Status:    "healthy",
		Service:   "go-service",
		Timestamp: time.Now().UTC().Format(time.RFC3339),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func computeHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	ctx, span := tracer.Start(ctx, "compute-request",
		trace.WithSpanKind(trace.SpanKindServer),
		trace.WithAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("http.url", r.URL.String()),
		),
	)
	defer span.End()

	// Check for error parameter
	errorParam := r.URL.Query().Get("error")
	if errorParam == "true" {
		span.SetAttributes(attribute.Bool("error.requested", true))
		span.RecordError(fmt.Errorf("requested error triggered"))

		errorResponse := ErrorResponse{
			Error:     "Requested error triggered in Go service",
			Service:   "go-service",
			Timestamp: time.Now().UTC().Format(time.RFC3339),
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusInternalServerError)
		json.NewEncoder(w).Encode(errorResponse)
		return
	}

	// Simulate computation
	computeTime := rand.Intn(100) + 20
	span.AddEvent("Starting computation",
		trace.WithAttributes(attribute.Int("compute.duration_ms", computeTime)),
	)

	time.Sleep(time.Duration(computeTime) * time.Millisecond)

	randomValue := rand.Intn(10000)
	result := float64(randomValue) * 3.14159

	span.SetAttributes(
		attribute.Int("compute.random_value", randomValue),
		attribute.Float64("compute.result", result),
	)

	span.AddEvent("Computation completed")

	response := ComputeResponse{
		Service:       "go-service",
		Timestamp:     time.Now().UTC().Format(time.RFC3339),
		ComputeTimeMs: computeTime,
		RandomValue:   randomValue,
		Result:        result,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func metricsHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	_, span := tracer.Start(ctx, "metrics",
		trace.WithSpanKind(trace.SpanKindServer),
	)
	defer span.End()

	metrics := map[string]interface{}{
		"service":   "go-service",
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"uptime":    time.Now().Unix(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(metrics)
}

// Middleware to extract trace context from incoming requests and increment metrics
func tracingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
		r = r.WithContext(ctx)

		// Increment cows_sold counter on every request
		cowsSold.Add(ctx, 1, metric.WithAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("http.route", r.URL.Path),
		))

		// Increment request counter
		requestCount.Add(ctx, 1, metric.WithAttributes(
			attribute.String("http.method", r.Method),
			attribute.String("http.route", r.URL.Path),
		))

		next(w, r)
	}
}

func main() {
	// Initialize OpenTelemetry tracing
	tp, err := initTracer()
	if err != nil {
		log.Fatalf("Failed to initialize tracer: %v", err)
	}
	defer func() {
		if err := tp.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	// Initialize OpenTelemetry metrics
	mp, err := initMeter()
	if err != nil {
		log.Fatalf("Failed to initialize meter: %v", err)
	}
	defer func() {
		if err := mp.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down meter provider: %v", err)
		}
	}()

	tracer = otel.Tracer("go-service")
	meter = otel.Meter("go-service")

	// Create metrics instruments
	cowsSold, err = meter.Int64Counter(
		"cows_sold",
		metric.WithDescription("The number of cows sold (increments on every request)"),
		metric.WithUnit("{cows}"),
	)
	if err != nil {
		log.Fatalf("Failed to create cows_sold counter: %v", err)
	}

	requestCount, err = meter.Int64Counter(
		"http.server.request.count",
		metric.WithDescription("The number of HTTP requests received"),
		metric.WithUnit("{requests}"),
	)
	if err != nil {
		log.Fatalf("Failed to create request counter: %v", err)
	}

	// Seed random number generator
	rand.Seed(time.Now().UnixNano())

	// Register handlers with tracing middleware
	http.HandleFunc("/health", tracingMiddleware(healthHandler))
	http.HandleFunc("/api/compute", tracingMiddleware(computeHandler))
	http.HandleFunc("/api/metrics", tracingMiddleware(metricsHandler))

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Go service starting on port %s", port)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
