---
title: Kong API Gateway Assignment - Implementation Report
description: Complete record of everything built for the Kong API Gateway assignment, including design decisions, problems solved, and verification results
author: Kong POC
ms.date: 2026-08-23
ms.topic: overview
keywords:
  - kong
  - api gateway
  - custom plugin
  - docker
  - jenkins
---

## Purpose

This document records every point delivered for the Kong API Gateway assignment: what was
built, why each decision was made, which problems came up during implementation, and how the
result was verified. Setup and usage instructions live in the root [README](../README.md);
this file is the implementation write-up.

## Assignment Requirements and Coverage

| # | Requirement                                                                     | Status | Where it lives                                                                                    |
|---|---------------------------------------------------------------------------------|--------|---------------------------------------------------------------------------------------------------|
| 1 | Dockerize and deploy a sample application with the required APIs                | Done   | `app/server.js`, `app/Dockerfile`                                                                 |
| 2 | Configure Kong: service, route, consumer, and plugin setup                      | Done   | `kong/kong.yml`                                                                                   |
| 3 | Implement Rate Limiting and Key Authentication plugins                          | Done   | `kong/kong.yml`                                                                                   |
| 4 | Custom plugin validating `x-environment` with proper error responses            | Done   | `kong/plugins/x-environment-validator/`                                                           |
| 5 | Jenkins pipeline automating build and test                                      | Done   | `Jenkinsfile`, `jenkins/`                                                                         |
| 6 | Containerization and security best practices                                    | Done   | `app/Dockerfile`, `docker-compose.yml`                                                            |
| 7 | Documentation, configuration files, test commands, and validation evidence      | Done   | `README.md`, this document, [test evidence](test-evidence.md), `tests/`                           |

## Architecture

```text
Client
  |
  v
Kong Gateway  (8000 proxy, 8001 admin)
  - x-environment-validator  (custom plugin)
  - key-auth
  - rate-limiting
  |
  v
Express Backend  (5000)
  /health   /api/ping   /api/hello   /api/data

Jenkins (8080) drives the same backend and kong containers over the shared network.
```

All three services run from a single `docker-compose up`.

## Point 1: Backend Application

A deliberately small Express service, chosen so the gateway behaviour stays the focus.

Endpoints implemented:

| Path         | Method | Purpose                                    |
|--------------|--------|--------------------------------------------|
| `/health`    | GET    | Liveness probe used by Docker and Kong     |
| `/api/ping`  | GET    | Returns `{"message":"hello from app"}`     |
| `/api/hello` | GET    | Accepts an optional `?name=` query string  |
| `/api/data`  | GET    | Returns a small sample collection          |

Implementation points:

* Single runtime dependency (`express`), so the image stays small and the attack surface small.
* Every response, including errors, is JSON. Express's default HTML error page is never exposed.
* The app was initially scaffolded in Python and Flask, then rebuilt in Node.js and Express.
  All Python artefacts (`app.py`, `requirements.txt`) and references were removed.

## Point 2: Dockerization

Two application images plus one CI image, all built by Compose.

Backend image (`app/Dockerfile`):

* Based on `node:18-alpine` to keep the image small.
* Dependencies installed with `npm install --omit=dev` so dev packages never reach the image.
* Runs as the built-in non-root `node` user.
* Starts with `CMD ["node", "server.js"]` rather than `npm start`, so Node is PID 1 and
  actually receives `SIGTERM`.
* Declares its own `HEALTHCHECK` using a Node HTTP probe, because the Alpine image has no curl.

Kong image (root `Dockerfile`):

* Based on `kong:3.4`.
* Copies the custom plugin into `/usr/local/share/lua/5.1/kong/plugins/` and `kong.yml` into
  `/etc/kong/`, so the running image is self-contained.
* Sets `KONG_DATABASE=off` and `KONG_DECLARATIVE_CONFIG` for DB-less mode.

Compose (`docker-compose.yml`):

* Defines `backend`, `kong`, and `jenkins` on a shared `kong-net` bridge network.
* Ports are parameterised through `.env` (`BACKEND_PORT`, `KONG_PROXY_PORT`, `KONG_ADMIN_PORT`,
  `JENKINS_PORT`) so they can be changed without editing the Compose file.
* `restart: unless-stopped` on the application services.
* Healthchecks are defined once in each Dockerfile rather than duplicated in Compose.

Supporting files:

* `.dockerignore` keeps the build context small and stops local artefacts entering images.
* `.gitattributes` forces LF endings on `.sh`, `.lua`, `.yml`, `Dockerfile`, and `Jenkinsfile`,
  so files checked out on Windows still run inside Linux containers.

## Point 3: Kong Configuration

Kong runs in DB-less declarative mode. Everything is defined in `kong/kong.yml` and loaded at
startup, which makes the configuration version controlled and reproducible with one command.

Service:

* `backend-service` pointing at `http://backend:5000`, resolved through Compose DNS.

Routes:

| Route            | Path         | Plugins applied                              |
|------------------|--------------|----------------------------------------------|
| `health-check`   | `/health`    | none (kept open for probes)                  |
| `ping-endpoint`  | `/api/ping`  | rate-limiting (100/min)                      |
| `hello-endpoint` | `/api/hello` | x-environment-validator, rate-limiting (50/min) |
| `data-endpoint`  | `/api/data`  | key-auth, rate-limiting (30/min)             |

Every route sets `strip_path: false` so the full path reaches the backend.

Consumers:

* `demo-user` with key `demo-api-key-12345`
* `test-user` with key `test-api-key-67890`

Plugin configuration points:

* Key authentication reads the `apikey` header (and query string, which is Kong's default).
* Rate limiting sets `policy: local` and `fault_tolerant: true` explicitly rather than relying
  on defaults, so the scaling behaviour is visible in the config.
* The custom plugin is enabled through `KONG_PLUGINS=bundled,x-environment-validator`.

### Why DB-less instead of Postgres

The assignment asks for service, route, consumer, and plugin configuration. It does not ask for
a database. DB-less mode satisfies every requirement while removing a Postgres container,
migration step, and startup ordering problem. The configuration is a single reviewable file
instead of live database state.

For completeness the README documents the equivalent Admin API calls that would create the same
objects on a Postgres-backed Kong, so both approaches are covered.

## Point 4: Custom Plugin (x-environment-validator)

Two files under `kong/plugins/x-environment-validator/`.

`schema.lua` declares two configuration fields:

| Field                  | Default          | Purpose                          |
|------------------------|------------------|----------------------------------|
| `allowed_environments` | `DEV,UAT,PROD`   | Comma separated list of accepted values |
| `header_name`          | `x-environment`  | Which header to validate         |

`handler.lua` implements the `access` phase with priority 900, so it runs before the request is
proxied upstream.

Required behaviour:

| Condition                    | Response                                                                     |
|------------------------------|------------------------------------------------------------------------------|
| Header missing               | `400` with `{"error":"Missing x-environment header"}`                        |
| Header value not allowed     | `403` with `{"error":"Invalid x-environment header. Allowed values: DEV, UAT, PROD"}` |
| Header value allowed         | Request proceeds to the backend                                              |

Edge cases handled beyond the base requirement:

| Input                                  | Result                     | Reasoning                                                     |
|----------------------------------------|----------------------------|----------------------------------------------------------------|
| `dev`, `Dev`, `DEV`                    | 200                        | Comparison is case-insensitive                                 |
| `x-environment:   PROD  `              | 200                        | Value is trimmed before comparison                             |
| Header sent twice with different values| 400 (duplicate)            | The intended environment is ambiguous, so it is rejected rather than silently taking the first |
| Header present but empty               | 400 (missing)              | An empty value carries no more meaning than an absent one      |
| `allowed_environments` set to empty    | 500                        | Fails closed instead of allowing every request through         |
| Non-default configuration              | Error text follows config  | The message is built from the real allowed list, not hardcoded |

Implementation points:

* Responses go through `kong.response.exit()` from the Kong PDK, which serialises JSON and sets
  the content type correctly. The first draft used raw `ngx.say` and `ngx.exit`, which is more
  fragile.
* Duplicate detection uses `kong.request.get_headers()`. The simpler `get_header()` returns only
  the first occurrence, so duplicates would pass silently.

## Point 5: Jenkins Pipeline

Jenkins is part of the Compose stack, so `docker-compose up` also brings up CI.

Image (`jenkins/`):

* `jenkins/Dockerfile` builds on `jenkins/jenkins:lts-jdk17` and adds the Docker CLI, the Compose
  plugin, and git, so pipeline stages can build and run containers.
* `jenkins/plugins.txt` pins the required plugins: git, workflow-aggregator, docker-workflow,
  configuration-as-code, job-dsl, timestamper.
* `jenkins/casc.yaml` uses Configuration as Code to create the `kong-poc-pipeline` job
  automatically at boot, so no manual job setup is needed.

Pipeline stages (`Jenkinsfile`):

1. Checkout
2. Build (backend and Kong images)
3. Start Services
4. Wait for Services
5. Test: Valid Request (expects 200)
6. Test: Missing Header (expects 400)
7. Test: Invalid Header (expects 403)
8. Full Test Suite (runs `tests/test.sh`, all 33 scenarios)
9. Verify Setup (prints container state and Kong services)

Post actions dump backend and Kong logs on failure, and always remove the `backend` and `kong`
containers afterwards.

Design points:

* The pipeline is scoped with `docker compose -p kong-poc ... backend kong`, so it reuses the
  running stack instead of creating a second conflicting copy, and it never touches its own
  `jenkins` container.
* Requests inside the pipeline use service names (`backend:5000`, `kong:8000`) because
  `localhost` inside the Jenkins container refers to Jenkins itself.

## Point 6: Error Handling and Resilience

Backend:

* Malformed JSON body returns `400` with `{"error":"Malformed JSON body"}`.
* Request bodies are capped at 10 kB; larger payloads return `413`. This also bounds per-request
  memory use.
* Unknown paths return a JSON `404`.
* `SIGTERM` and `SIGINT` trigger a graceful shutdown: the server stops accepting connections,
  lets in-flight requests finish, then exits, with a 10 second forced-exit backstop. This matters
  for rolling restarts and scale-down, where an abrupt exit would drop live requests.
* `unhandledRejection` is logged; `uncaughtException` triggers the same graceful shutdown path.

Gateway:

* If the backend is down, Kong returns `502` rather than hanging or leaking internals, and Kong
  itself stays healthy.
* Kong retries a failed upstream request before giving up (`retries: 5`, the default).
* `fault_tolerant: true` means a rate-limiter storage failure lets traffic through instead of
  failing every request.
* Both application containers declare healthchecks so an orchestrator can detect and replace an
  unhealthy instance.

## Point 7: Automated Test Suite

Two equivalent scripts, `tests/test.sh` (Linux and macOS) and `tests/test.ps1` (Windows
PowerShell), run after the stack is up and cover 33 scenarios split into two groups:
assignment scenarios and additional edge cases. Screenshots and console output from a real
run are in [test evidence](test-evidence.md).

| Section | Coverage                                                                            |
|---------|--------------------------------------------------------------------------------------|
| 1       | Preflight: backend and Kong admin API reachable                                      |
| 2       | Backend direct: all four endpoints plus a JSON 404, bypassing Kong                   |
| 3       | Backend error handling: malformed JSON, oversized payload                            |
| 4       | Kong routing: proxying, unrouted path, wrong HTTP method                             |
| 5       | Custom plugin: valid values, case handling, padding, missing, invalid, empty, duplicate, near-miss |
| 6       | Key authentication: valid keys, query-string key, missing, invalid, empty            |
| 7       | Upstream failure: stop the backend, expect 502, confirm Kong survives, restart and confirm recovery |
| 8       | Rate limiting: headers present, burst produces 429, 429 body is JSON                 |

Points of note:

* Both scripts exit non-zero on failure, so they double as a CI gate, which is exactly how the
  Jenkins pipeline consumes `tests/test.sh`.
* Base URLs are overridable, which is what allows the same script to run from the host
  (`localhost`) or from inside a container (`kong`, `backend`).
* Destructive sections can be skipped with `SKIP_RESILIENCE` and `SKIP_RATELIMIT`.

## Problems Encountered and Fixed

These were real failures hit during implementation, not hypothetical ones. Each was diagnosed
from logs or test output and then fixed.

| # | Symptom                                                        | Root cause                                                                        | Fix                                                        |
|---|----------------------------------------------------------------|-----------------------------------------------------------------------------------|------------------------------------------------------------|
| 1 | Backend image build failed on `COPY server.js`                 | Build context was the project root while the Dockerfile expected the app folder    | Set `context: ./app`                                        |
| 2 | `kong:3.4-alpine: not found`                                   | Kong stopped publishing Alpine images after 2.8                                    | Switched to `kong:3.4` and `apt-get` instead of `apk`       |
| 3 | Kong crash-looped on startup                                   | `kong.yml` used `description` and `case_sensitive`, which are not in the schema     | Removed the unsupported fields                              |
| 4 | Every proxied route returned the backend's own 404             | Kong strips the matched path by default                                            | Added `strip_path: false` to all routes                     |
| 5 | Duplicate `x-environment` headers were accepted                | `get_header()` returns only the first occurrence                                   | Switched to `get_headers()`                                 |
| 6 | Backend container permanently `unhealthy`                      | The Compose healthcheck overrode the Dockerfile one and called curl, absent in Alpine | Removed the override, kept the Dockerfile probe          |
| 7 | Healthcheck still failed with `ECONNREFUSED ::1:5000`          | `localhost` resolved to IPv6 while the server binds IPv4                           | Probe `127.0.0.1` explicitly                                |
| 8 | Healthcheck probe hung until timeout                           | The HTTP response body was never consumed, keeping the socket open                 | Call `r.resume()` and exit explicitly                       |
| 9 | Jenkins could not check out the repo                           | The git plugin blocks local-path checkouts by default                              | Enabled `ALLOW_LOCAL_CHECKOUT` for this trusted local repo  |
| 10| Git refused the bind-mounted repo                              | Ownership differs between host and container, triggering the dubious-ownership guard | Added a `safe.directory` entry                            |
| 11| Pipeline failed on `timestamps()` and on git                   | Timestamper plugin and git binary missing from the Jenkins image                    | Added both to the image build                               |
| 12| Pipeline could not reach the Docker daemon                     | The `jenkins` user had no access to the mounted socket                             | Ran the Jenkins container as root                           |
| 13| Pipeline collided with the already-running stack               | It started a second copy with the same container names and host ports              | Scoped to `-p kong-poc` and limited to `backend kong`       |
| 14| Kong failed to start when launched by Jenkins                  | Relative bind-mount paths do not resolve through a shared Docker socket            | Removed the mounts, since the image already contains them   |
| 15| Pipeline tests could not connect                               | `localhost` inside the Jenkins container is Jenkins, not its sibling containers     | Used Compose service names                                  |

## Verification

Results from the final run:

* Local suite: 41 passed, 0 failed.
* Jenkins pipeline: 41 passed, 0 failed, build result `SUCCESS`.
* Clean boot from an empty state (`docker-compose down -v` then `docker-compose up --build`)
  brings up all three services, with both application containers reporting `healthy`.

Representative output:

```text
$ curl -i -H "x-environment: DEV" http://localhost:8000/api/hello
HTTP/1.1 200 OK
RateLimit-Limit: 50
{"message":"Hello, World!","status":"ok"}

$ curl -i http://localhost:8000/api/hello
HTTP/1.1 400 Bad Request
{"error":"Missing x-environment header"}

$ curl -i -H "x-environment: STAGING" http://localhost:8000/api/hello
HTTP/1.1 403 Forbidden
{"error":"Invalid x-environment header. Allowed values: DEV, UAT, PROD"}

$ curl -i http://localhost:8000/api/data
HTTP/1.1 401 Unauthorized
{"message":"No API key found in request"}

$ 1..35 | ForEach-Object { curl -s -o /dev/null -w "%{http_code}" -H "apikey: demo-api-key-12345" http://localhost:8000/api/data }
200 x 29, 429 x 6
```

## Known Limitations and Next Steps

Honest notes on what would need attention before production use.

* Rate limiting uses `policy: local`, so counters live in each Kong node's memory. With several
  Kong replicas the effective limit multiplies per node. Real multi-node enforcement needs
  `policy: redis` and a Redis instance.
* DB-less configuration is immutable at runtime. Changing a route means rebuilding and
  restarting rather than calling the Admin API.
* API keys are committed in plain text, which is acceptable for a proof of concept but should
  move to a secret store, referenced through Kong's vault syntax.
* The service points at a single upstream URL. Horizontal backend scaling would use a Kong
  upstream with multiple targets.
* No CPU or memory limits are set on the containers.
* The bundled Jenkins runs as root with default credentials and mounts the Docker socket. This
  is a convenience for local evaluation and is not a production posture.
