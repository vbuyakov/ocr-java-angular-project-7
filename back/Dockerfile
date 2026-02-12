FROM gradle:jdk17 AS build
COPY ./back /src
WORKDIR /src
RUN chmod +x gradlew && ./gradlew build --no-daemon

FROM eclipse-temurin:21-jre-alpine
COPY --from=build /src/build/libs/microcrm-0.0.1-SNAPSHOT.jar /app/microcrm.jar
WORKDIR /app
EXPOSE 8080
CMD ["java", "-jar", "/app/microcrm.jar"]
