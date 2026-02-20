FROM node:20-alpine AS build
COPY ./front /src
WORKDIR /src
# Use relative API URL so Caddy can reverse-proxy to backend
RUN sed -i 's|API_BASE_URL = "http://localhost:8080"|API_BASE_URL = ""|' src/app/config.ts
RUN npm ci && npx ng build --configuration production

FROM alpine:3.19
RUN apk add --no-cache caddy && mkdir -p /var/log/caddy
COPY --from=build /src/dist/microcrm/browser /app/front
COPY ./misc/docker/Caddyfile /app/Caddyfile
COPY ./misc/docker/caddy-entrypoint.sh /caddy-entrypoint.sh
RUN chmod +x /caddy-entrypoint.sh
WORKDIR /app
EXPOSE 80
# Caddy binding to :80 requires root; run as root in isolated container
ENTRYPOINT ["/caddy-entrypoint.sh"]
