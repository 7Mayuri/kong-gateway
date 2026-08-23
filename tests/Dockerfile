# Runner for test.sh: needs bash and curl, plus the docker CLI for the resilience scenarios.
FROM alpine:3.20

RUN apk add --no-cache bash curl docker-cli

WORKDIR /workspace

CMD ["bash", "test.sh"]
