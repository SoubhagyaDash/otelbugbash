package com.example.javaservice.model;

public class CalculationResponse {
    private String service;
    private String timestamp;
    private int processingTimeMs;
    private int randomValue;
    private String goServiceResponse;

    public String getService() {
        return service;
    }

    public void setService(String service) {
        this.service = service;
    }

    public String getTimestamp() {
        return timestamp;
    }

    public void setTimestamp(String timestamp) {
        this.timestamp = timestamp;
    }

    public int getProcessingTimeMs() {
        return processingTimeMs;
    }

    public void setProcessingTimeMs(int processingTimeMs) {
        this.processingTimeMs = processingTimeMs;
    }

    public int getRandomValue() {
        return randomValue;
    }

    public void setRandomValue(int randomValue) {
        this.randomValue = randomValue;
    }

    public String getGoServiceResponse() {
        return goServiceResponse;
    }

    public void setGoServiceResponse(String goServiceResponse) {
        this.goServiceResponse = goServiceResponse;
    }
}
