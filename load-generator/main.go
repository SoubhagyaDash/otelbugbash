package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

type LoadTestConfig struct {
	URL          string
	Duration     time.Duration
	RatePerSec   int
	ReportFile   string
	Timeout      time.Duration
}

type RequestResult struct {
	Timestamp    time.Time
	Duration     time.Duration
	StatusCode   int
	Success      bool
	ErrorMessage string
}

type LoadTestReport struct {
	Config           LoadTestConfig    `json:"config"`
	StartTime        time.Time         `json:"startTime"`
	EndTime          time.Time         `json:"endTime"`
	TotalRequests    int64             `json:"totalRequests"`
	SuccessRequests  int64             `json:"successRequests"`
	FailedRequests   int64             `json:"failedRequests"`
	TotalDuration    string            `json:"totalDuration"`
	LatencyP50       float64           `json:"latencyP50Ms"`
	LatencyP90       float64           `json:"latencyP90Ms"`
	LatencyP95       float64           `json:"latencyP95Ms"`
	LatencyP99       float64           `json:"latencyP99Ms"`
	LatencyMin       float64           `json:"latencyMinMs"`
	LatencyMax       float64           `json:"latencyMaxMs"`
	LatencyMean      float64           `json:"latencyMeanMs"`
	RequestsPerSec   float64           `json:"requestsPerSec"`
	ErrorDetails     map[string]int    `json:"errorDetails"`
	StatusCodeDist   map[int]int64     `json:"statusCodeDistribution"`
}

type LoadGenerator struct {
	config         LoadTestConfig
	results        []RequestResult
	resultsMutex   sync.Mutex
	totalRequests  int64
	successCount   int64
	failedCount    int64
	client         *http.Client
}

func NewLoadGenerator(config LoadTestConfig) *LoadGenerator {
	return &LoadGenerator{
		config: config,
		results: make([]RequestResult, 0, 10000),
		client: &http.Client{
			Timeout: config.Timeout,
		},
	}
}

func (lg *LoadGenerator) makeRequest() RequestResult {
	start := time.Now()
	result := RequestResult{
		Timestamp: start,
	}

	resp, err := lg.client.Get(lg.config.URL)
	result.Duration = time.Since(start)

	if err != nil {
		result.Success = false
		result.ErrorMessage = err.Error()
		atomic.AddInt64(&lg.failedCount, 1)
	} else {
		defer resp.Body.Close()
		io.Copy(io.Discard, resp.Body) // Drain response body
		
		result.StatusCode = resp.StatusCode
		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			result.Success = true
			atomic.AddInt64(&lg.successCount, 1)
		} else {
			result.Success = false
			result.ErrorMessage = fmt.Sprintf("HTTP %d", resp.StatusCode)
			atomic.AddInt64(&lg.failedCount, 1)
		}
	}

	atomic.AddInt64(&lg.totalRequests, 1)
	
	lg.resultsMutex.Lock()
	lg.results = append(lg.results, result)
	lg.resultsMutex.Unlock()

	return result
}

func (lg *LoadGenerator) Run() {
	log.Printf("Starting load test...")
	log.Printf("  URL: %s", lg.config.URL)
	log.Printf("  Duration: %v", lg.config.Duration)
	log.Printf("  Rate: %d req/sec", lg.config.RatePerSec)

	startTime := time.Now()
	ticker := time.NewTicker(time.Second / time.Duration(lg.config.RatePerSec))
	defer ticker.Stop()

	stopChan := make(chan struct{})
	done := make(chan struct{})

	// Handle interrupts
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	// Progress reporter
	go func() {
		progressTicker := time.NewTicker(10 * time.Second)
		defer progressTicker.Stop()
		
		for {
			select {
			case <-progressTicker.C:
				elapsed := time.Since(startTime)
				log.Printf("Progress: %v elapsed | Requests: %d | Success: %d | Failed: %d",
					elapsed.Round(time.Second),
					atomic.LoadInt64(&lg.totalRequests),
					atomic.LoadInt64(&lg.successCount),
					atomic.LoadInt64(&lg.failedCount))
			case <-stopChan:
				return
			}
		}
	}()

	// Request generator
	go func() {
		timeout := time.After(lg.config.Duration)
		for {
			select {
			case <-ticker.C:
				go lg.makeRequest()
			case <-timeout:
				close(stopChan)
				return
			case <-sigChan:
				log.Println("Received interrupt signal, stopping...")
				close(stopChan)
				return
			}
		}
	}()

	<-stopChan
	
	// Wait a bit for in-flight requests to complete
	time.Sleep(2 * time.Second)
	close(done)

	log.Println("Load test completed")
	
	// Generate report
	report := lg.GenerateReport(startTime, time.Now())
	lg.PrintReport(report)
	
	if lg.config.ReportFile != "" {
		if err := lg.SaveReport(report); err != nil {
			log.Printf("Error saving report: %v", err)
		} else {
			log.Printf("Report saved to: %s", lg.config.ReportFile)
		}
	}
}

func (lg *LoadGenerator) GenerateReport(startTime, endTime time.Time) LoadTestReport {
	lg.resultsMutex.Lock()
	defer lg.resultsMutex.Unlock()

	report := LoadTestReport{
		Config:          lg.config,
		StartTime:       startTime,
		EndTime:         endTime,
		TotalRequests:   lg.totalRequests,
		SuccessRequests: lg.successCount,
		FailedRequests:  lg.failedCount,
		TotalDuration:   endTime.Sub(startTime).String(),
		ErrorDetails:    make(map[string]int),
		StatusCodeDist:  make(map[int]int64),
	}

	if len(lg.results) == 0 {
		return report
	}

	// Calculate latencies
	latencies := make([]float64, 0, len(lg.results))
	var totalLatency float64

	for _, result := range lg.results {
		latencyMs := float64(result.Duration.Microseconds()) / 1000.0
		latencies = append(latencies, latencyMs)
		totalLatency += latencyMs

		if !result.Success {
			report.ErrorDetails[result.ErrorMessage]++
		}
		if result.StatusCode > 0 {
			report.StatusCodeDist[result.StatusCode]++
		}
	}

	sort.Float64s(latencies)

	report.LatencyMin = latencies[0]
	report.LatencyMax = latencies[len(latencies)-1]
	report.LatencyMean = totalLatency / float64(len(latencies))
	report.LatencyP50 = percentile(latencies, 50)
	report.LatencyP90 = percentile(latencies, 90)
	report.LatencyP95 = percentile(latencies, 95)
	report.LatencyP99 = percentile(latencies, 99)

	duration := endTime.Sub(startTime).Seconds()
	if duration > 0 {
		report.RequestsPerSec = float64(lg.totalRequests) / duration
	}

	return report
}

func percentile(sorted []float64, p float64) float64 {
	if len(sorted) == 0 {
		return 0
	}
	index := int(float64(len(sorted)) * p / 100.0)
	if index >= len(sorted) {
		index = len(sorted) - 1
	}
	return sorted[index]
}

func (lg *LoadGenerator) PrintReport(report LoadTestReport) {
	fmt.Println("\n" + strings.Repeat("=", 70))
	fmt.Println("LOAD TEST REPORT")
	fmt.Println(strings.Repeat("=", 70))
	fmt.Printf("URL:              %s\n", report.Config.URL)
	fmt.Printf("Duration:         %s\n", report.TotalDuration)
	fmt.Printf("Target Rate:      %d req/sec\n", report.Config.RatePerSec)
	fmt.Printf("Actual Rate:      %.2f req/sec\n", report.RequestsPerSec)
	fmt.Println(strings.Repeat("-", 70))
	fmt.Printf("Total Requests:   %d\n", report.TotalRequests)
	fmt.Printf("Success:          %d (%.2f%%)\n", report.SuccessRequests, 
		float64(report.SuccessRequests)/float64(report.TotalRequests)*100)
	fmt.Printf("Failed:           %d (%.2f%%)\n", report.FailedRequests,
		float64(report.FailedRequests)/float64(report.TotalRequests)*100)
	fmt.Println(strings.Repeat("-", 70))
	fmt.Println("Latency Statistics (milliseconds):")
	fmt.Printf("  Min:     %8.2f ms\n", report.LatencyMin)
	fmt.Printf("  Mean:    %8.2f ms\n", report.LatencyMean)
	fmt.Printf("  P50:     %8.2f ms\n", report.LatencyP50)
	fmt.Printf("  P90:     %8.2f ms\n", report.LatencyP90)
	fmt.Printf("  P95:     %8.2f ms\n", report.LatencyP95)
	fmt.Printf("  P99:     %8.2f ms\n", report.LatencyP99)
	fmt.Printf("  Max:     %8.2f ms\n", report.LatencyMax)
	
	if len(report.StatusCodeDist) > 0 {
		fmt.Println(strings.Repeat("-", 70))
		fmt.Println("Status Code Distribution:")
		for code, count := range report.StatusCodeDist {
			fmt.Printf("  %d: %d\n", code, count)
		}
	}

	if len(report.ErrorDetails) > 0 {
		fmt.Println(strings.Repeat("-", 70))
		fmt.Println("Error Details:")
		for err, count := range report.ErrorDetails {
			fmt.Printf("  %s: %d\n", err, count)
		}
	}
	fmt.Println(strings.Repeat("=", 70))
}

func (lg *LoadGenerator) SaveReport(report LoadTestReport) error {
	data, err := json.MarshalIndent(report, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal report: %w", err)
	}

	return os.WriteFile(lg.config.ReportFile, data, 0644)
}

func parseDuration(s string) (time.Duration, error) {
	return time.ParseDuration(s)
}

func main() {
	var (
		url        = flag.String("url", "", "Target URL to test (required)")
		duration   = flag.String("duration", "1m", "Duration of the load test (e.g., 30s, 5m, 1h)")
		rate       = flag.Int("rate", 10, "Number of requests per second")
		reportFile = flag.String("report-file", "", "Path to save JSON report (optional)")
		timeout    = flag.String("timeout", "30s", "Request timeout")
		version    = flag.Bool("version", false, "Print version and exit")
	)

	flag.Parse()

	if *version {
		fmt.Println("Load Generator v1.0.0")
		return
	}

	if *url == "" {
		log.Fatal("Error: --url is required")
	}

	testDuration, err := parseDuration(*duration)
	if err != nil {
		log.Fatalf("Error parsing duration: %v", err)
	}

	timeoutDuration, err := parseDuration(*timeout)
	if err != nil {
		log.Fatalf("Error parsing timeout: %v", err)
	}

	config := LoadTestConfig{
		URL:          *url,
		Duration:     testDuration,
		RatePerSec:   *rate,
		ReportFile:   *reportFile,
		Timeout:      timeoutDuration,
	}

	generator := NewLoadGenerator(config)
	generator.Run()
}
