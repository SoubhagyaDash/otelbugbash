FROM golang:1.23-alpine AS build

# Install git (required for go mod download)
RUN apk add --no-cache git

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

CMD ["./go-service"]
