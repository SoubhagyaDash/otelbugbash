# Load Generator

High-performance HTTP load testing tool for generating traffic and measuring latency.

## Features

- Configurable request rate (requests per second)
- Configurable test duration
- Real-time progress reporting
- Detailed latency statistics (P50, P90, P95, P99)
- JSON report generation
- Error tracking and categorization
- Status code distribution
- Graceful shutdown on interrupt

## Building

```bash
go build -o load-generator .
```

## Usage

```bash
./load-generator \
  --url http://localhost:5000/api/process \
  --duration 10m \
  --rate 10 \
  --report-file /tmp/load-test-report.json \
  --timeout 30s
```

### Parameters

- `--url`: Target URL to test (required)
- `--duration`: How long to run the test (default: 1m)
  - Examples: `30s`, `5m`, `1h`, `90s`
- `--rate`: Requests per second (default: 10)
- `--report-file`: Path to save JSON report (optional)
- `--timeout`: HTTP request timeout (default: 30s)
- `--version`: Print version and exit

## Examples

### Basic Load Test

```bash
./load-generator --url http://localhost:5000/api/process --duration 5m --rate 20
```

### High Load Test

```bash
./load-generator --url http://localhost:5000/api/process --duration 1h --rate 100 --report-file results.json
```

### Quick Test

```bash
./load-generator --url http://localhost:5000/api/process --duration 30s --rate 5
```

## Report Format

The tool generates a detailed JSON report with:

```json
{
  "config": {
    "URL": "http://localhost:5000/api/process",
    "Duration": 600000000000,
    "RatePerSec": 10
  },
  "totalRequests": 6000,
  "successRequests": 5950,
  "failedRequests": 50,
  "latencyP50Ms": 45.23,
  "latencyP90Ms": 89.12,
  "latencyP95Ms": 112.45,
  "latencyP99Ms": 156.78,
  "latencyMinMs": 12.34,
  "latencyMaxMs": 234.56,
  "latencyMeanMs": 52.34,
  "requestsPerSec": 9.98,
  "statusCodeDistribution": {
    "200": 5950,
    "500": 50
  },
  "errorDetails": {
    "HTTP 500": 50
  }
}
```

## Progress Reporting

Every 10 seconds, the tool prints progress:

```
Progress: 10s elapsed | Requests: 100 | Success: 98 | Failed: 2
Progress: 20s elapsed | Requests: 200 | Success: 196 | Failed: 4
```

## Graceful Shutdown

Press Ctrl+C to stop the test early. The tool will:
1. Stop sending new requests
2. Wait for in-flight requests to complete (up to 2 seconds)
3. Generate and save the report with partial results

## Installation on VM

The Bicep template will install this tool to `/opt/load-generator/` on the VM.
