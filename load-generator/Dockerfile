FROM golang:1.21-alpine AS build

WORKDIR /app

COPY go.mod ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -o load-generator .

FROM alpine:latest

RUN apk --no-cache add ca-certificates

WORKDIR /opt/load-generator

COPY --from=build /app/load-generator .

ENTRYPOINT ["./load-generator"]
