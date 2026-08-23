---
title: Test Suite Evidence
description: Screenshots and console output from the automated verification suite, covering the assignment scenarios and the additional edge cases
author: Kong POC
ms.date: 2026-08-23
ms.topic: reference
keywords:
  - kong
  - testing
  - evidence
  - verification report
---

## Purpose

This page is the validation evidence for the assignment. Everything shown here was produced
by running the project, not written by hand. To reproduce it, run `docker-compose up` and
open `http://localhost:8090` when the pipeline finishes.

## How the evidence is produced

```text
docker-compose up
   |
   +-- starts backend, Kong, Jenkins and the report server
   +-- prints where everything is, then stops (no tests run here)

Run the kong-poc-pipeline job in Jenkins
   |
   +-- runs tests/test.sh against the running gateway
   +-- writes reports/index.html
   +-- nginx serves it at http://localhost:8090
```

Startup stays fast because the suite runs in the pipeline rather than during
`docker-compose up`. The job can be started from the Jenkins UI or with
`docker-compose --profile ci up pipeline`.

The suite is one script, so the same 33 scenarios run whether they are triggered by Jenkins
or by hand, and the report always reflects the run that just happened.

## Console output

The run finishes with a banner containing the report link.

```text
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS


###############################################################################
#
#   ALL TESTS PASSED
#
#   OPEN THE TEST REPORT:
#   http://localhost:8090
#
###############################################################################
```

Each scenario is also printed as it runs, with the command that was executed and the response
that came back:

```text
[A9] Missing x-environment returns HTTP 400 with a JSON error
      $ curl -i http://kong:8000/api/hello
      -> HTTP 400   (expected 400)
      {"error":"Missing x-environment header"}
      Requirement 4: missing header gives 400
      PASS
```

And it ends with a per-group summary:

```text
==============================================================================
  SUMMARY
==============================================================================
  Part A  Assignment Scenarios                   11/11 passed
  Part B  Edge Cases (beyond the assignment)     22/22 passed

  Passed 33   Failed 0   Skipped 0
```

## Report summary

Opening the link gives the same results as a page. The header shows the overall verdict and
the split between the two groups.

![Verification report summary showing all 33 scenarios passed, 11 of 11 in Part A and 22 of 22 in Part B](images/report-summary.png)

## Scenario detail

Every scenario is a card showing the exact command, the expected and actual status, and the
raw response body, so a reviewer can copy any command and reproduce it.

Assignment requirement 4, a missing header returning `400`:

![Report card for scenario A9 showing the curl command, expected and actual status of 400, and the JSON error body](images/report-scenario-missing-header.png)

An edge case beyond the brief, a header sent twice:

![Report card for scenario B5 showing duplicate x-environment headers rejected with 400 and a JSON error body](images/report-scenario-duplicate-header.png)

Rate limiting, where the response records how many requests were served and how many were
throttled:

![Report card for scenario A11 showing a burst of 40 requests producing 30 responses with 200 and 10 with 429](images/report-scenario-rate-limit.png)

## Full report

The complete page, both groups end to end:

![Full verification report showing all Part A and Part B scenario cards](images/report-full.png)

## What is covered

Part A maps one to one onto the assignment brief.

| ID      | Scenario                                                    | Requirement |
|---------|-------------------------------------------------------------|-------------|
| A1      | Dockerized app is deployed and reachable                    | 1           |
| A2      | Kong service and route proxy to the backend                 | 2           |
| A3-A5   | Key auth: valid key, no key, unknown key                    | 3           |
| A6-A8   | Custom plugin allows `DEV`, `UAT`, `PROD`                   | 4           |
| A9      | Missing `x-environment` returns `400` with a JSON error     | 4           |
| A10     | Invalid `x-environment` returns `403` with a JSON error     | 4           |
| A11     | Rate limiting throttles a burst with `429`                  | 3           |

Part B is everything covered on top of the brief.

| ID      | Scenario                                                                  |
|---------|---------------------------------------------------------------------------|
| B1-B3   | Lowercase, mixed case, and space-padded header values are accepted        |
| B4      | Header present but empty is treated as missing                            |
| B5      | Duplicate `x-environment` headers are rejected                            |
| B6-B7   | Numeric value and near miss `DEVELOPMENT` are rejected                    |
| B8      | A route without the plugin ignores a bad value, proving per-route scoping |
| B9      | Plugin errors are JSON, never an HTML error page                          |
| B10-B13 | Key via query string, empty key, second consumer, plugin independence     |
| B14-B16 | Unrouted path, wrong HTTP method, backend JSON 404                        |
| B17-B18 | Malformed JSON body, oversized request body                               |
| B19     | `RateLimit-*` headers are returned to the client                          |
| B20-B22 | Backend stopped gives 502, Kong stays healthy, traffic recovers           |

## Notes on reading the report

* A scenario marked `SKIP` means a flag was passed to skip it, for example `SKIP_RATELIMIT=1`.
  A normal `docker-compose up` run skips nothing, so a clean run reports 33 passed and 0 skipped.
* The report is regenerated on every run and is deliberately not committed, so what you open is
  always the run that just happened rather than a stale copy.
* The same report is archived as a Jenkins build artifact, so it can also be downloaded from
  the build page.
