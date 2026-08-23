# Bakes the custom plugin and declarative config into the Kong image.
FROM kong:3.4

USER root

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY ./plugins/x-environment-validator /usr/local/share/lua/5.1/kong/plugins/x-environment-validator
COPY ./kong.yml /etc/kong/kong.yml

ENV KONG_DATABASE=off
ENV KONG_DECLARATIVE_CONFIG=/etc/kong/kong.yml
ENV KONG_PROXY_LISTEN=0.0.0.0:8000
ENV KONG_ADMIN_LISTEN=0.0.0.0:8001
ENV KONG_LOG_LEVEL=info

USER kong

EXPOSE 8000 8001

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:8001/status || exit 1

CMD ["kong", "start"]

