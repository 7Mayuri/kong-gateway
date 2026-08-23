---
title: Kong API Gateway POC
description: Local Node.js application secured by Kong and delivered through Docker and Jenkins.
---

## Project

Node.js app registered behind the Kong gateway for security, rate limiting, and gateway features.
Jenkins provides a structured pipeline for build and test, and Docker hosts the application stack.

## Local Setup

1. Build the Docker images:

   ```bash
   docker compose build
   ```

2. Start the stack:

   ```bash
   docker compose up
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
