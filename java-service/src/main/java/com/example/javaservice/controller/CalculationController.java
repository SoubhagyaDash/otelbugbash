package com.example.javaservice.controller;

import com.example.javaservice.model.CalculationResponse;
import com.example.javaservice.model.HealthResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.client.RestTemplate;

import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Random;

@RestController
@RequestMapping("/api")
public class CalculationController {

    @Value("${go.service.url:http://go-service:8080}")
    private String goServiceUrl;

    private final RestTemplate restTemplate = new RestTemplate();
    private final Random random = new Random();

    @GetMapping("/health")
    public ResponseEntity<HealthResponse> health() {
        HealthResponse response = new HealthResponse();
        response.setStatus("healthy");
        response.setService("java-service");
        response.setTimestamp(Instant.now().toString());
        return ResponseEntity.ok(response);
    }

    @GetMapping("/calculate")
    public ResponseEntity<?> calculate(@RequestParam(defaultValue = "false") boolean error) {
        
        if (error) {
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", "Requested error triggered in Java service");
            errorResponse.put("service", "java-service");
            errorResponse.put("timestamp", Instant.now().toString());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }

        try {
            // Simulate some processing
            int processingTime = random.nextInt(50) + 10;
            Thread.sleep(processingTime);

            // Call Go service
            String goUrl = goServiceUrl + "/api/compute?error=" + error;
            ResponseEntity<String> goResponse = restTemplate.getForEntity(goUrl, String.class);

            CalculationResponse response = new CalculationResponse();
            response.setService("java-service");
            response.setTimestamp(Instant.now().toString());
            response.setProcessingTimeMs(processingTime);
            response.setRandomValue(random.nextInt(1000));
            response.setGoServiceResponse(goResponse.getBody());
            
            return ResponseEntity.ok(response);

        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", "Processing interrupted");
            errorResponse.put("service", "java-service");
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        } catch (Exception e) {
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", "Error calling Go service: " + e.getMessage());
            errorResponse.put("service", "java-service");
            errorResponse.put("timestamp", Instant.now().toString());
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(errorResponse);
        }
    }

    @GetMapping("/metrics")
    public ResponseEntity<Map<String, Object>> metrics() {
        Map<String, Object> metrics = new HashMap<>();
        metrics.put("service", "java-service");
        metrics.put("uptime", System.currentTimeMillis());
        metrics.put("timestamp", Instant.now().toString());
        metrics.put("javaVersion", System.getProperty("java.version"));
        return ResponseEntity.ok(metrics);
    }
}
