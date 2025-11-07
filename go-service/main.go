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
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.21.0"
	"go.opentelemetry.io/otel/trace"
)

var tracer trace.Tracer

type HealthResponse struct {
	Status    string `json:"status"`
	Service   string `json:"service"`
	Timestamp string `json:"timestamp"`
}

type ComputeResponse struct {
	Service        string  `json:"service"`
	Timestamp      string  `json:"timestamp"`
	ComputeTimeMs  int     `json:"computeTimeMs"`
	RandomValue    int     `json:"randomValue"`
	Result         float64 `json:"result"`
}

type ErrorResponse struct {
	Error     string `json:"error"`
	Service   string `json:"service"`
	Timestamp string `json:"timestamp"`
}

func initTracer() (*sdktrace.TracerProvider, error) {
	ctx := context.Background()

	// Get OTLP endpoint from environment
	otlpEndpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
	if otlpEndpoint == "" {
		otlpEndpoint = "localhost:4318"
	}

	// Create OTLP HTTP exporter
	exporter, err := otlptracehttp.New(ctx,
		otlptracehttp.WithEndpoint(otlpEndpoint),
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

func healthHandler(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	_, span := tracer.Start(ctx, "health-check")
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
	_, span := tracer.Start(ctx, "metrics")
	defer span.End()

	metrics := map[string]interface{}{
		"service":   "go-service",
		"timestamp": time.Now().UTC().Format(time.RFC3339),
		"uptime":    time.Now().Unix(),
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(metrics)
}

// Middleware to extract trace context from incoming requests
func tracingMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		ctx := otel.GetTextMapPropagator().Extract(r.Context(), propagation.HeaderCarrier(r.Header))
		r = r.WithContext(ctx)
		next(w, r)
	}
}

func main() {
	// Initialize OpenTelemetry
	tp, err := initTracer()
	if err != nil {
		log.Fatalf("Failed to initialize tracer: %v", err)
	}
	defer func() {
		if err := tp.Shutdown(context.Background()); err != nil {
			log.Printf("Error shutting down tracer provider: %v", err)
		}
	}()

	tracer = otel.Tracer("go-service")

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
	log.Printf("OTLP endpoint: %s", os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"))

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
