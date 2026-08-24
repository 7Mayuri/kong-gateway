---
title: Kong API Gateway POC
description: Local Node.js application secured by Kong and delivered through Docker and Jenkins.
---

## Project

Node.js app registered behind the Kong gateway for security, rate limiting, and gateway features.
Jenkins provides a structured pipeline for build and test, and Docker hosts the application stack.

Documentation: [Implementation report](docs/implementation-report.md)

Kong runs in DB-less mode, which means it does not use a separate database to store its
configuration. At startup, Kong loads `kong/kong.yml`. This file defines the backend service,
routes, consumers, and plugins, so the application is registered behind the gateway from one
version-controlled configuration file. The Kong Admin API is available for status and inspection,
but it is not used to create these objects at runtime.

## Prerequisites

Install Docker Desktop or Docker Engine with Docker Compose v2 (`docker compose`).

Node.js, Kong, Jenkins, Nginx, and the test runner are pulled as Docker images, so no separate
installation of these tools is required.

## Local Setup

Build the Docker images and start the stack:

```bash
docker compose up --build
```

The `kong-info` service prints this status when the stack is ready:

```text
##############################################################################
#
#   STACK IS UP
#
#   Kong proxy    http://localhost:8000
#   Kong admin    http://localhost:8001
#   Backend       http://localhost:5000
#   Jenkins       http://localhost:8080   (admin / admin)
#
#   TEST REPORT   http://localhost:8090
#
#   Run the kong-poc-pipeline job in Jenkins to generate the report,
#   or run:  docker-compose --profile ci up pipeline
#
##############################################################################
```

## Useful Links

Kong proxy: http://localhost:8000/  
Kong admin: http://localhost:8001/  
Backend: http://localhost:5000/  
Jenkins: http://localhost:8080/  
Test report: http://localhost:8090/

## Technology Stack

* Express and Node.js
* Kong Gateway
* Jenkins
* Docker
