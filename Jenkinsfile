#!/usr/bin/env groovy

// Build, start, and test the stack.
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

        // Build images from the shared workspace.
        stage('Build') {
            steps {
                dir('/workspace') {
                    sh '''
                        docker build -f app/Dockerfile -t kong-poc:backend app/
                        docker build -f kong/Dockerfile -t kong-poc:kong kong/
                    '''
                }
            }
        }

        // Reuse healthy services when available.
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

        // Wait for services on the shared network.
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

        // Check a valid environment request.
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

        // Run the complete test suite.
        stage('Full Test Suite') {
            steps {
                dir('/workspace') {
                    // Write the report to the shared reports folder.
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
        // Show service logs when the pipeline fails.
        failure {
            dir('/workspace') {
                sh 'docker compose -p kong-poc logs backend kong || true'
            }
        }
    }
}

