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
├── Dockerfile               # Kong image (bundles the custom plugin)
├── docker-compose.yml       # Runs backend + kong together
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

# 2. Build both images (backend + Kong with the custom plugin)
docker-compose build

# 3. Start both containers
docker-compose up -d

# 4. Confirm both containers are healthy
docker-compose ps

# 5. Confirm the backend is reachable directly
curl http://localhost:5000/health

# 6. Confirm Kong is reachable
curl http://localhost:8001/status
```

If step 4 shows both containers as `Up`, and steps 5-6 return JSON, the stack is ready to test through Kong.

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
for i in {1..101}; do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/api/ping; done
```

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

`docker-compose up` never touches Jenkins — Jenkins is not one of the services in `docker-compose.yml` and nothing here starts it automatically. The `Jenkinsfile` is a separate script that only runs *inside a Jenkins server*, and that server is the one calling `docker-compose` on your behalf, the same way you'd call it by hand from a terminal.

What the pipeline does, stage by stage:

1. **Checkout** - Jenkins pulls this repository (`checkout scm`)
2. **Build** - runs `docker build` for the backend image and the Kong image, same Dockerfiles used above
3. **Start Services** - runs `docker-compose up -d` to boot both containers
4. **Wait for Services** - polls `/health` and `/status` until both containers respond
5. **Test: Valid Request** - `curl` with a correct `x-environment: DEV` header, expects 200
6. **Test: Missing Header** - `curl` with no header, expects 400
7. **Test: Invalid Header** - `curl` with `x-environment: INVALID`, expects 403
8. **Verify Setup** - prints `docker-compose ps` and Kong's `/services` list as evidence
9. **post { failure / always }** - on failure it dumps `docker-compose logs`; either way it runs `docker-compose down -v` to tear everything down

To actually run it, you need a Jenkins instance (local install, Docker container running Jenkins, or a hosted one) with **Docker available to the Jenkins agent**, since the pipeline itself shells out to `docker` and `docker-compose`. Steps:

1. Install/start Jenkins (e.g. `docker run -p 8080:8080 -v /var/run/docker.sock:/var/run/docker.sock jenkins/jenkins`, so the Jenkins container can reach the host's Docker daemon)
2. In Jenkins: **New Item → Pipeline**
3. Under "Pipeline", choose **Pipeline script from SCM**, point it at this repo, and set the script path to `Jenkinsfile`
4. Click **Build Now** — Jenkins then runs the 8 stages above and shows pass/fail per stage in its console output

If you don't have a Jenkins server, the `Jenkinsfile` is still evidence of the CI design (it is not required to actually execute for the manual test commands in this README to work — those you can always run directly with the `docker-compose` commands above).

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

