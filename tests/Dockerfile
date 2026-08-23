# Runner image: test.sh needs bash and curl, the trigger script talks to the Jenkins API,
# and the docker CLI is there for the resilience scenarios.
FROM alpine:3.20

RUN apk add --no-cache bash curl docker-cli

COPY trigger-pipeline.sh /usr/local/bin/trigger-pipeline
RUN chmod +x /usr/local/bin/trigger-pipeline

WORKDIR /workspace

CMD ["trigger-pipeline"]
