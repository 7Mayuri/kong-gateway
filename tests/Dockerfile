# Add tools used by the test runner.
FROM alpine:3.20

RUN apk add --no-cache bash curl docker-cli

COPY trigger-pipeline.sh /usr/local/bin/trigger-pipeline
RUN chmod +x /usr/local/bin/trigger-pipeline

WORKDIR /workspace

CMD ["trigger-pipeline"]
