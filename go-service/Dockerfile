FROM golang:1.21-alpine AS build

WORKDIR /app

# Copy source code
COPY . .

# Download dependencies and generate go.sum
RUN go mod download && go mod tidy

# Build the application
RUN CGO_ENABLED=0 GOOS=linux go build -o go-service .

# Final stage
FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /app

COPY --from=build /app/go-service .

EXPOSE 8080

ENV PORT=8080
ENV OTEL_EXPORTER_OTLP_ENDPOINT="localhost:4318"

CMD ["./go-service"]
