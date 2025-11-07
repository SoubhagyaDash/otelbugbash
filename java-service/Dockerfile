FROM gradle:8.5-jdk17 AS build
WORKDIR /app

COPY build.gradle settings.gradle ./
COPY src ./src

RUN gradle build --no-daemon -x test

FROM eclipse-temurin:17-jre

WORKDIR /app

# Download OpenTelemetry Java agent for auto-instrumentation
ARG OTEL_AGENT_VERSION=1.32.0
ADD https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v${OTEL_AGENT_VERSION}/opentelemetry-javaagent.jar /app/opentelemetry-javaagent.jar

COPY --from=build /app/build/libs/*.jar ./

EXPOSE 8080

# Run with OpenTelemetry Java agent
ENV JAVA_TOOL_OPTIONS="-javaagent:/app/opentelemetry-javaagent.jar"
ENV OTEL_SERVICE_NAME="java-service"
ENV OTEL_TRACES_EXPORTER="otlp"
ENV OTEL_EXPORTER_OTLP_PROTOCOL="http/protobuf"
ENV OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4318"

ENTRYPOINT ["java", "-jar", "java-service-1.0.0.jar"]
