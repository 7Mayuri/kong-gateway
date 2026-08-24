# Assignment Kong POC Implementation

## Overview

This project dockerizes a small Node.js application and places it behind Kong API Gateway.
Jenkins builds the images, starts the application services, runs the verification suite, and
publishes the generated HTML report. The setup is intended for local evaluation and is not a
production deployment.

## Assignment Coverage

| Requirement | Delivered | Main files |
| --- | --- | --- |
| Dockerize and deploy the sample application | Yes | `app/server.js`, `app/Dockerfile`, `docker-compose.yml` |
| Configure Kong service, routes, and consumers | Yes | `kong/kong.yml` |
| Configure Key Authentication and Rate Limiting | Yes | `kong/kong.yml` |
| Validate the `x-environment` header | Yes | `kong/plugins/x-environment-validator/` |
| Automate build and testing with Jenkins | Yes | `Jenkinsfile`, `jenkins/` |
| Apply containerization and security practices | Yes | Dockerfiles, Compose configuration, `.gitignore` |
| Provide documentation, commands, and evidence | Yes | `README.md`, this report, `tests/test.sh` |

## How It Works

```text
Client -> Kong proxy -> Express backend
             |
             +-- x-environment-validator
             +-- key-auth
             +-- rate-limiting

Jenkins runs the same test script against the Compose network.
```

The backend exposes `/health`, `/api/ping`, `/api/hello`, and `/api/data`. Kong runs in DB-less
mode and loads the version-controlled configuration from `kong/kong.yml`. The configured routes
are:

| Route | Protection |
| --- | --- |
| `/health` | Open for health checks |
| `/api/ping` | Rate limiting, 100 requests per minute |
| `/api/hello` | Environment validation and rate limiting, 50 requests per minute |
| `/api/data` | Key authentication and rate limiting, 30 requests per minute |

The registered consumers are `demo-user` and `test-user`.

## Custom Plugin and Error Handling

The `x-environment-validator` plugin accepts `DEV`, `UAT`, and `PROD`. Matching is
case-insensitive and surrounding spaces are removed. It returns JSON responses through the Kong
PDK, so plugin errors do not expose an HTML error page or an internal stack trace.

| Situation | Response |
| --- | --- |
| Header missing or empty | `400` with `Missing x-environment header` |
| Header value is invalid | `403` with the allowed values |
| Header is valid | Request continues to the backend |
| Header is sent more than once | `400`, because the intended environment is ambiguous |
| Invalid value on a route without the plugin | Route continues normally, proving route-level scope |

The backend returns JSON for unknown paths (`404`), malformed JSON (`400`), and request bodies
over 10 kB (`413`). If the backend is stopped, Kong returns an upstream `502` or `503` while the
gateway remains available; traffic recovers after the backend restarts.

## Run and Verify

Start the stack and run the automated checks:

```bash
docker compose up --build
docker compose --profile ci up --build --abort-on-container-exit pipeline
```

Useful checks:

```bash
curl http://localhost:8000/api/ping
curl -H "x-environment: DEV" http://localhost:8000/api/hello
curl http://localhost:8000/api/hello                 # 400
curl -H "apikey: demo-api-key-12345" http://localhost:8000/api/data
curl http://localhost:8000/api/data                  # 401
```

The test runner covers the required API-key, rate-limit, routing, and environment-header cases,
plus common error and backend-outage scenarios. A successful run produced:

```text
Part A  Assignment Scenarios                   11/11 passed
Part B  Edge Cases (beyond the assignment)     22/22 passed
Passed 33   Failed 0   Skipped 0
```

## Screenshot Evidence

[Open the full-size verification screenshot](images/full-console-test-output.png)

<img src="images/full-console-test-output.png" alt="Kong verification test results" width="1875">

## Reproduction

```bash
docker compose up --build -d
docker compose --profile ci up --build --abort-on-container-exit pipeline
```

Open the generated report at `http://localhost:8090/`. For setup, service links, and
troubleshooting steps, see the [project documentation in README.md](../README.md).
