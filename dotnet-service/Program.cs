using Microsoft.AspNetCore.Mvc;
using OpenTelemetry;
using OpenTelemetry.Logs;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using System.Diagnostics;

var builder = WebApplication.CreateBuilder(args);

// Get OTLP endpoint configuration
var otlpTracesLogsEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") 
    ?? "http://localhost:4319";
var otlpMetricsEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT") 
    ?? "http://localhost:4317";

// Configure OpenTelemetry
builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: "dotnet-service", serviceVersion: "1.0.0"))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(otlpTracesLogsEndpoint);
            options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(otlpMetricsEndpoint);
            options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
        }));

// Configure logging with OpenTelemetry
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
    logging.AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri(otlpTracesLogsEndpoint);
        options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.Grpc;
    });
});

builder.Services.AddHttpClient();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

// Activity source for custom spans
var activitySource = new ActivitySource("dotnet-service");

app.MapGet("/health", () => Results.Ok(new { status = "healthy", service = "dotnet-service" }));

app.MapGet("/api/process", async ([FromServices] IHttpClientFactory httpClientFactory, 
                                   [FromQuery] bool error = false) =>
{
    using var activity = activitySource.StartActivity("ProcessRequest", ActivityKind.Server);
    activity?.SetTag("custom.operation", "process");
    activity?.SetTag("error.requested", error);

    try
    {
        var javaServiceUrl = Environment.GetEnvironmentVariable("JAVA_SERVICE_URL") 
            ?? "http://java-service:8080";
        
        var httpClient = httpClientFactory.CreateClient();
        
        activity?.AddEvent(new ActivityEvent("Calling Java Service"));
        activity?.SetTag("downstream.service", "java-service");
        activity?.SetTag("downstream.url", javaServiceUrl);

        var response = await httpClient.GetAsync($"{javaServiceUrl}/api/calculate?error={error}");
        
        response.EnsureSuccessStatusCode();
        var result = await response.Content.ReadAsStringAsync();

        activity?.AddEvent(new ActivityEvent("Java Service Response Received"));
        activity?.SetTag("response.success", true);

        return Results.Ok(new
        {
            service = "dotnet-service",
            timestamp = DateTime.UtcNow,
            javaServiceResponse = result,
            traceId = Activity.Current?.TraceId.ToString()
        });
    }
    catch (Exception ex)
    {
        activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
        activity?.RecordException(ex);
        
        return Results.Problem(
            title: "Error processing request",
            detail: ex.Message,
            statusCode: 500
        );
    }
});

app.MapGet("/api/metrics", () =>
{
    return Results.Ok(new
    {
        service = "dotnet-service",
        uptime = Environment.TickCount64,
        timestamp = DateTime.UtcNow
    });
});

app.Run();
