FROM eclipse-temurin:17-jdk AS build
COPY ./back /src
WORKDIR /src
RUN chmod +x gradlew && ./gradlew build --no-daemon

FROM eclipse-temurin:17-jre
RUN groupadd -r appgroup && useradd -r -g appgroup appuser
WORKDIR /app
COPY --from=build --chown=appuser:appgroup /src/build/libs/microcrm-0.0.1-SNAPSHOT.jar /app/microcrm.jar
USER appuser
EXPOSE 8080
CMD ["java", "-jar", "/app/microcrm.jar"]
