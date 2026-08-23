# Kong API Gateway - POC Project

A minimal Kong API Gateway setup with a tiny Node.js Express backend, a custom plugin that validates an `x-environment` header, key authentication, and rate limiting.

## Overview

- **Backend** - Node.js Express app with 4 endpoints (`app/server.js`)
- **Kong Gateway** - routes traffic to the backend and applies plugins
- **Custom Plugin** - `x-environment-validator`, checks for `DEV`, `UAT`, or `PROD`
- **Key Authentication** - protects `/api/data` with an API key
- **Rate Limiting** - applied per route
- **Jenkinsfile** - builds, boots, and tests the stack in CI

Kong runs in **DB-less (declarative) mode** — no Postgres container. All services, routes, consumers, and plugins are defined once in [kong/kong.yml](kong/kong.yml) and loaded on startup. This is intentional: the assignment only asks for service/route/consumer/plugin configuration, not a database-backed Kong setup, so declarative mode keeps the project simpler and fully reproducible with a single `docker-compose up`.

For the full write-up of what was implemented, the design decisions behind it, problems solved, and verification results, see [docs/implementation-report.md](docs/implementation-report.md).

## Architecture

```
Client
  │
  ▼
Kong Gateway (port 8000 proxy, 8001 admin)
  - x-environment-validator (custom plugin)
  - key-auth
  - rate-limiting
  │
  ▼
Express Backend (port 5000)
  - /health
  - /api/ping
  - /api/hello
  - /api/data
```

## Project Structure

```
kong-poc/
├── app/
│   ├── server.js           # Express backend
│   ├── package.json        # Node dependencies
│   └── Dockerfile          # Backend image
├── kong/
│   ├── kong.yml             # Kong declarative config (services, routes, consumers, plugins)
│   └── plugins/
│       └── x-environment-validator/
│           ├── handler.lua # Plugin logic
│           └── schema.lua  # Plugin config schema
├── jenkins/
│   ├── Dockerfile           # Jenkins image with Docker CLI + git baked in
│   ├── plugins.txt          # Jenkins plugins installed at build time
│   └── casc.yaml            # Auto-creates the kong-poc-pipeline job on boot
├── tests/
│   ├── Dockerfile           # Small runner image (bash, curl, docker CLI)
│   └── trigger-pipeline.sh  # Waits for Jenkins and runs the pipeline on startup
├── reports/                 # Pipeline writes index.html here, served on :8090
├── Dockerfile               # Kong image (bundles the custom plugin)
├── docker-compose.yml       # backend + kong + jenkins + pipeline + report
├── run.ps1 / run.sh         # One command: start stack, run pipeline, open report
├── test.sh                  # Full scenario + edge case suite (Linux/macOS)
├── test.ps1                 # Same suite for Windows PowerShell
├── .env                     # Port overrides
├── Jenkinsfile              # CI pipeline
└── README.md
```

## Prerequisites

- Docker and Docker Compose
- curl (or any HTTP client) for testing

## Setup: Steps to Test After Pulling the Repo

Run these in order from the project root.

```bash
# 1. Clone/pull and enter the project
git clone <repo-url>
cd kong-poc

# 2. Build and start everything
docker-compose up
```

That single command does the whole flow:

1. Builds the backend, Kong, and Jenkins images
2. Starts Kong and the backend, and waits until both report healthy
3. Starts Jenkins with the `kong-poc-pipeline` job already created
4. **Triggers the pipeline automatically**, which builds, boots, and runs every test scenario
5. Streams the pipeline output into your terminal
6. Prints the report link

The last thing you see is:

```text
###############################################################################
#
#   ALL TESTS PASSED
#
#   OPEN THE TEST REPORT:
#   http://localhost:8090
#
###############################################################################
```

In the foreground, that banner is printed by the `kong-pipeline` service, so it appears
among the Jenkins startup logs. If you would rather see only the pipeline output, start
detached and follow that one container:

```bash
docker-compose up -d
docker logs -f kong-pipeline
```

Open the URL and you get the full HTML report: every scenario with the exact command
that ran, the expected and actual status, and the response body, split into assignment
scenarios and edge cases.

The stack stays running afterwards, so Kong is still available on port 8000 for manual
testing and Jenkins on port 8080 (`admin` / `admin`).

### If you want the browser to open by itself

A container cannot launch a browser on your machine, so use the wrapper instead. It does
exactly the same thing and then opens the report for you.

```powershell
.\run.ps1        # Windows
```

```bash
./run.sh         # Linux / macOS
```

### If you prefer to drive it manually

```bash
docker-compose up -d          # start in the background
docker-compose ps             # confirm containers are healthy
curl http://localhost:5000/health
curl http://localhost:8001/status
.\test.ps1                    # or ./test.sh, run the suite yourself
```

### Ports

| Port | Service |
|---|---|
| 8000 | Kong proxy (send your API requests here) |
| 8001 | Kong admin API |
| 5000 | Backend, exposed for direct testing |
| 8080 | Jenkins (`admin` / `admin`) |
| 8090 | Verification report |

All are overridable in `.env`.

## Test Commands and Expected Results

### Valid request (x-environment header present and correct)

```bash
curl -i -H "x-environment: DEV" http://localhost:8000/api/hello
```

Expected: `200 OK` with `{"message":"Hello, World!","status":"ok"}`

### Missing header

```bash
curl -i http://localhost:8000/api/hello
```

Expected: `400 Bad Request` with `{"error":"Missing x-environment header"}`

### Invalid header value

```bash
curl -i -H "x-environment: STAGING" http://localhost:8000/api/hello
```

Expected: `403 Forbidden` with `{"error":"Invalid x-environment header. Allowed values: DEV, UAT, PROD"}`

### Key authentication

```bash
# Valid key
curl -i -H "apikey: demo-api-key-12345" http://localhost:8000/api/data

# No key -> 401 Unauthorized
curl -i http://localhost:8000/api/data
```

### Rate limiting

```bash
# ping-endpoint allows 100 requests/minute; the 101st returns 429
for i in $(seq 1 101); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/api/ping; done
```

PowerShell equivalent:

```powershell
1..101 | ForEach-Object { curl.exe -s -o NUL -w "%{http_code}`n" http://localhost:8000/api/ping }
```

## Automated Test Suite

One command runs every scenario and prints the exact curl command, the HTTP status, and
the real response body for each. Start the stack in one terminal, run the script in another.

```bash
# Terminal 1
docker-compose up

# Terminal 2 - Linux / macOS / Git Bash
chmod +x test.sh
./test.sh

# Terminal 2 - Windows PowerShell
.\test.ps1
```

Results are split into two groups so it is obvious what the brief asked for and what was
added on top:

**Part A - Assignment Scenarios (11)** — the scenarios explicitly required by the brief.

| ID | Scenario | Requirement |
|---|---|---|
| A1 | Dockerized app is deployed and reachable | 1 |
| A2 | Kong service and route proxy to the backend | 2 |
| A3-A5 | Key auth: valid key → 200, no key → 401, unknown key → 401 | 3 |
| A6-A8 | Custom plugin allows `DEV`, `UAT`, `PROD` | 4 |
| A9 | Missing `x-environment` → 400 JSON error | 4 |
| A10 | Invalid `x-environment` → 403 JSON error | 4 |
| A11 | Rate limiting throttles a burst with 429 | 3 |

**Part B - Edge Cases (22)** — everything covered beyond the brief.

| ID | Scenario |
|---|---|
| B1-B3 | Lowercase, mixed case, and space-padded header values are accepted |
| B4 | Header present but empty is treated as missing (400) |
| B5 | Duplicate `x-environment` headers rejected (400) |
| B6-B7 | Numeric value and near-miss `DEVELOPMENT` rejected (403) |
| B8 | A route without the plugin ignores a bad value (proves per-route scoping) |
| B9 | Plugin errors are JSON, never an HTML error page |
| B10-B13 | Key via query string, empty key, second consumer, plugin independence |
| B14-B16 | Unrouted path, wrong HTTP method, backend JSON 404 |
| B17-B18 | Malformed JSON → 400, oversized body → 413 |
| B19 | `RateLimit-*` headers are returned to the client |
| B20-B22 | Backend stopped → 502, Kong stays healthy, traffic recovers on restart |

### HTML report

Every run writes a self-contained page showing each scenario as a card with its command,
expected vs actual status, and response body, grouped into Part A and Part B with a pass/fail
summary at the top.

When the pipeline runs it as part of `docker-compose up`, the report is written to
`reports/index.html` and served by the `report` container, so you get a real clickable URL:

```text
  Open the test report:  http://localhost:8090
```

It is also archived as a Jenkins build artifact, so you can download it from the build page.

When you run the script yourself on the host it writes `test-report.html` next to the script
and prints a `file://` link instead. Either way you can have it opened automatically:

```bash
OPEN=1 ./test.sh
```

```powershell
.\test.ps1 -Open
```

The Jenkins pipeline runs the same script and archives the report as a build artifact.

### Flags

```bash
SKIP_RESILIENCE=1 ./test.sh                  # don't stop/start the backend container
SKIP_RATELIMIT=1 ./test.sh                   # don't burn the rate limit quota
NO_REPORT=1 ./test.sh                        # console only, no HTML
OPEN=1 ./test.sh                             # open the report when finished
KONG_URL=http://kong:8000 ./test.sh          # run from inside another container
REPORT_PATH=/tmp/report.html ./test.sh       # write the report elsewhere
```

```powershell
.\test.ps1 -SkipResilience -SkipRateLimit
.\test.ps1 -NoReport
.\test.ps1 -Open
.\test.ps1 -KongUrl http://localhost:8000 -ReportPath C:\temp\report.html
```

Both scripts exit non-zero if any scenario fails, so they double as a CI gate.

Note: A11 deliberately uses up the `/api/data` quota, which is why it runs last. If you
re-run the script immediately, wait a minute or pass the skip flag.

## Available Endpoints

| Path         | Method | Auth    | Rate Limit | Notes                        |
|--------------|--------|---------|------------|-------------------------------|
| `/health`    | GET    | none    | -          | No plugins, used for health checks |
| `/api/ping`  | GET    | none    | 100/min    | Rate limiting only            |
| `/api/hello` | GET    | x-env   | 50/min     | Requires `x-environment` header |
| `/api/data`  | GET    | API key | 30/min     | Requires `apikey` header      |

Demo API keys (defined in `kong/kong.yml`): `demo-api-key-12345`, `test-api-key-67890`.

## Custom Plugin: x-environment-validator

Located at `kong/plugins/x-environment-validator/`.

- Reads the header named by `header_name` (default `x-environment`)
- Compares it against `allowed_environments` (default `DEV,UAT,PROD`), case-insensitive
- Missing header → `400` with `{"error":"Missing x-environment header"}`
- Invalid value → `403` with `{"error":"Invalid x-environment header. Allowed values: DEV, UAT, PROD"}`
- Valid value → request passes through to the backend

Edge cases it handles explicitly:

| Input | Result | Why |
|---|---|---|
| `x-environment: dev` / `Dev` | 200 | Comparison is case-insensitive |
| `x-environment:   PROD  ` | 200 | Value is trimmed before comparing |
| Header sent twice with different values | 400 `Duplicate ...` | The intended environment is ambiguous, so it is rejected rather than silently picking the first |
| Header present but empty | 400 `Missing ...` | Treated the same as absent |
| `allowed_environments` configured empty | 500 | Fails closed instead of letting every request through |
| Non-default `header_name` / `allowed_environments` | Error text follows the config | The message is built from the actual allowed list, not hardcoded |

It uses `kong.response.exit()` from the Kong PDK, so error bodies are always
serialized JSON with the right content type — never a raw string or an HTML error page.

## Error Handling and Resilience

### Backend

- Every failure path returns JSON. Express's default HTML error page is never exposed.
- Malformed JSON body → `400 {"error":"Malformed JSON body"}`
- Body larger than 10 kB → `413 {"error":"Payload too large"}` (the limit also caps memory use per request)
- Unknown path → `404 {"error":"Not Found"}`
- `SIGTERM`/`SIGINT` trigger a graceful shutdown: the server stops accepting new connections, lets in-flight requests finish, then exits — with a 10s forced-exit backstop. This matters for rolling restarts and scale-down, where an abrupt exit would drop live requests.
- `node` is started directly (not via `npm start`) so it is PID 1 and actually receives those signals.
- The container runs as the non-root `node` user.

### Gateway

- If the backend is down, Kong returns `502` rather than hanging or leaking a stack trace, and Kong itself stays healthy. The test suite verifies this by stopping and restarting the backend container.
- Kong retries a failed upstream request (`retries: 5`, Kong's default) before giving up.
- `fault_tolerant: true` on the rate limiter means a limiter storage failure lets traffic through instead of failing every request.
- Both containers declare healthchecks, so orchestrators can detect and replace an unhealthy instance.

## Scaling Notes

Things that would need attention before this ran in production:

- **Rate limiting is per Kong node.** The plugins use `policy: local`, which keeps counters in each Kong process's memory. Run three Kong replicas behind a load balancer and the effective limit becomes roughly 3× the configured value. For real multi-node enforcement, switch the rate-limiting plugins to `policy: redis` and add a Redis instance.
- **DB-less config is immutable at runtime.** `kong.yml` is baked into the image, so a config change means rebuild and restart. That is a feature for reproducibility and GitOps, but it means you cannot hot-add a route via the Admin API. If runtime mutability is required, switch to a Postgres-backed Kong (see the Admin API section below for what that setup would look like).
- **API keys are committed in plain text.** Fine for a POC; in production they belong in a secret store, and Kong supports referencing them via `{vault://...}`.
- **The backend is stateless**, so it scales horizontally as-is. Kong load balances across upstream targets, but this project defines a single `url` rather than an upstream with multiple targets — that would be the next step for real horizontal scaling.
- **No resource limits are set** on the containers. Under real load you would add `deploy.resources.limits` so one runaway service cannot starve the host.

## Admin API Equivalents

This project defines everything declaratively in `kong/kong.yml`. If Kong were running in DB mode instead, the same setup would be created at runtime with these Admin API calls:

```bash
# Service
curl -i -X POST http://localhost:8001/services \
  --data name=backend-service \
  --data url=http://backend:5000

# Routes
curl -i -X POST http://localhost:8001/services/backend-service/routes \
  --data name=health-check --data paths[]=/health --data methods[]=GET --data strip_path=false

curl -i -X POST http://localhost:8001/services/backend-service/routes \
  --data name=ping-endpoint --data paths[]=/api/ping --data methods[]=GET --data strip_path=false

curl -i -X POST http://localhost:8001/services/backend-service/routes \
  --data name=hello-endpoint --data paths[]=/api/hello --data methods[]=GET --data strip_path=false

curl -i -X POST http://localhost:8001/services/backend-service/routes \
  --data name=data-endpoint --data paths[]=/api/data --data methods[]=GET --data strip_path=false

# Plugins per route
curl -i -X POST http://localhost:8001/routes/ping-endpoint/plugins \
  --data name=rate-limiting --data config.minute=100

curl -i -X POST http://localhost:8001/routes/hello-endpoint/plugins \
  --data name=x-environment-validator \
  --data config.allowed_environments=DEV,UAT,PROD \
  --data config.header_name=x-environment

curl -i -X POST http://localhost:8001/routes/hello-endpoint/plugins \
  --data name=rate-limiting --data config.minute=50

curl -i -X POST http://localhost:8001/routes/data-endpoint/plugins \
  --data name=key-auth --data config.key_names[]=apikey

curl -i -X POST http://localhost:8001/routes/data-endpoint/plugins \
  --data name=rate-limiting --data config.minute=30

# Consumer + API key
curl -i -X POST http://localhost:8001/consumers --data username=demo-user
curl -i -X POST http://localhost:8001/consumers/demo-user/key-auth --data key=demo-api-key-12345
```

Running these against a DB-backed Kong would produce the exact same routing, auth, and rate-limiting behavior documented above.

## Docker Compose Commands

```bash
docker-compose up --build   # build and start
docker-compose logs -f      # tail logs
docker-compose ps           # check container status
docker-compose down -v      # stop and remove everything
```

## Jenkins Pipeline

`docker-compose up` starts three services: `backend`, `kong`, and `jenkins`. Jenkins comes up with the `kong-poc-pipeline` job **already created** (via Jenkins Configuration-as-Code, see `jenkins/casc.yaml`) — no manual "New Item" step needed. Jenkins is bind-mounted at `/workspace` and shares the host's Docker socket, so its pipeline builds/starts the *same* `backend` and `kong` containers you already have, rather than a second conflicting copy; it never touches its own `jenkins` container.

What the pipeline does, stage by stage:

1. **Checkout** - Jenkins clones the repo (from the bind-mounted `/workspace`, which is a real git repo) to read the `Jenkinsfile`
2. **Build** - runs `docker build` for the backend image and the Kong image against `/workspace`, same Dockerfiles used above
3. **Start Services** - runs `docker compose -p kong-poc up -d --no-deps backend kong` (jenkins is excluded on purpose)
4. **Wait for Services** - polls `backend:5000/health` and `kong:8001/status` (service names on the shared `kong-net` network, not `localhost`) until both respond
5. **Test: Valid Request** - `curl` against `kong:8000/api/hello` with a correct `x-environment: DEV` header, expects 200
6. **Test: Missing Header** - same URL with no header, expects 400
7. **Test: Invalid Header** - same URL with `x-environment: INVALID`, expects 403
8. **Verify Setup** - prints `docker compose ps` and Kong's `/services` list as evidence
9. **post { failure / always }** - on failure it dumps backend/kong logs; either way it removes just the `backend`/`kong` containers, leaving Jenkins running

To trigger a build once the stack is up:

1. Open `http://localhost:8080` and log in with `admin` / `admin` (change this if you expose Jenkins beyond your own machine)
2. Open the **kong-poc-pipeline** job
3. Click **Build Now**
4. Watch the console output for the 8 stages above

You can also trigger it from the command line:

```bash
curl -u admin:admin -X POST "http://localhost:8080/job/kong-poc-pipeline/build"
```

If you'd rather point a separate, external Jenkins server at this repo instead of using the bundled one, the same `Jenkinsfile` also works from **New Item → Pipeline → Pipeline script from SCM**, script path `Jenkinsfile` — no changes needed, since `checkout scm` and the `backend`/`kong` service names work the same way there too, as long as that Jenkins agent also has Docker access and joins the same compose network.

## Troubleshooting

| Symptom | Check |
|---|---|
| `docker-compose build` fails on backend | Confirm build context is `./app` in `docker-compose.yml` |
| Kong container restarts in a loop | `docker-compose logs kong` — usually a `kong.yml` schema error |
| All routes return 404 from the backend's own handler | Route is missing `strip_path: false` in `kong.yml` |
| Port already in use | Change `BACKEND_PORT` / `KONG_PROXY_PORT` / `KONG_ADMIN_PORT` in `.env` |

## References

- [Kong Docs](https://docs.konghq.com/)
- [Kong Plugin Development](https://docs.konghq.com/gateway/latest/plugin-development/)
- [Docker Compose](https://docs.docker.com/compose/)

## License

Educational and demonstration use only.

