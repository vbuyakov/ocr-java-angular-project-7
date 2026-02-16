FROM eclipse-temurin:17-jdk-alpine AS build
COPY ./back /src
WORKDIR /src
RUN chmod +x gradlew && ./gradlew build --no-daemon

FROM eclipse-temurin:17-jre-alpine
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
WORKDIR /app
COPY --from=build --chown=appuser:appgroup /src/build/libs/microcrm-0.0.1-SNAPSHOT.jar /app/microcrm.jar
USER appuser
EXPOSE 8080
CMD ["java", "-jar", "/app/microcrm.jar"]
