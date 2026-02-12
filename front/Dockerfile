FROM node:20-alpine AS build
COPY ./front /src
WORKDIR /src
# Use relative API URL so Caddy can reverse-proxy to backend
RUN sed -i 's|API_BASE_URL = "http://localhost:8080"|API_BASE_URL = ""|' src/app/config.ts
RUN npm ci && npx ng build --configuration production

FROM alpine:3.19
RUN apk add --no-cache caddy
COPY --from=build /src/dist/microcrm/browser /app/front
COPY ./misc/docker/Caddyfile /app/Caddyfile
WORKDIR /app
EXPOSE 80
CMD ["caddy", "run", "--config", "/app/Caddyfile"]
