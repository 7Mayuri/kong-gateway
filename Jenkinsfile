#!/usr/bin/env groovy

// Builds both images, boots the stack, and checks the x-environment plugin behavior.
pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 15, unit: 'MINUTES')
        timestamps()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // Runs against the bind-mounted /workspace (same files, same containers the host already sees)
        // so this never spins up a second, port-conflicting copy of the stack.
        stage('Build') {
            steps {
                dir('/workspace') {
                    sh '''
                        docker build -f app/Dockerfile -t kong-poc:backend app/
                        docker build -f Dockerfile -t kong-poc:kong .
                    '''
                }
            }
        }

        // Compose records its working directory on the containers, and that path differs
        // inside Jenkins, so an unconditional "up" would recreate containers that are already
        // running and detach them from the user's compose session. Only start what is missing.
        stage('Start Services') {
            steps {
                dir('/workspace') {
                    sh '''
                        if curl -sf -o /dev/null http://backend:5000/health && \
                           curl -sf -o /dev/null http://kong:8001/status; then
                            echo "backend and kong are already running, reusing them"
                        else
                            echo "starting backend and kong"
                            docker compose -p kong-poc up -d --no-deps backend kong
                        fi
                    '''
                }
            }
        }

        // Jenkins reaches these as sibling containers on kong-net, not via localhost.
        stage('Wait for Services') {
            steps {
                sh '''
                    for i in $(seq 1 30); do
                        curl -sf http://backend:5000/health > /dev/null 2>&1 && break
                        sleep 1
                    done
                    for i in $(seq 1 30); do
                        curl -sf http://kong:8001/status > /dev/null 2>&1 && break
                        sleep 1
                    done
                    sleep 3
                '''
            }
        }

        // x-environment-validator sits on /api/hello, not /api/ping.
        stage('Test: Valid Request') {
            steps {
                sh 'curl -i -H "x-environment: DEV" http://kong:8000/api/hello'
            }
        }

        stage('Test: Missing Header') {
            steps {
                sh '''
                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://kong:8000/api/hello)
                    [ "$STATUS" = "400" ] || { echo "Expected 400, got $STATUS"; exit 1; }
                '''
            }
        }

        stage('Test: Invalid Header') {
            steps {
                sh '''
                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "x-environment: INVALID" http://kong:8000/api/hello)
                    [ "$STATUS" = "403" ] || { echo "Expected 403, got $STATUS"; exit 1; }
                '''
            }
        }

        // The three stages above are quick smoke checks; this runs the full edge case suite.
        stage('Full Test Suite') {
            steps {
                dir('/workspace') {
                    // reports/ is bind-mounted from the project and served by the report container.
                    sh '''
                        KONG_URL=http://kong:8000 \
                        ADMIN_URL=http://kong:8001 \
                        BACKEND_URL=http://backend:5000 \
                        REPORT_PATH=/workspace/reports/index.html \
                        bash tests/test.sh
                    '''
                }
            }
            post {
                always {
                    sh 'cp /workspace/reports/index.html "$WORKSPACE/test-report.html" || true'
                    archiveArtifacts artifacts: 'test-report.html', allowEmptyArchive: true
                }
            }
        }

        stage('Verify Setup') {
            steps {
                dir('/workspace') {
                    sh '''
                        docker compose -p kong-poc ps backend kong
                        curl -s http://kong:8001/services
                    '''
                }
            }
        }
    }

    post {
        // Deliberately does not remove backend/kong: compose owns their lifecycle,
        // and tearing them down here would kill the stack the reviewer just started.
        failure {
            dir('/workspace') {
                sh 'docker compose -p kong-poc logs backend kong || true'
            }
        }
    }
}

