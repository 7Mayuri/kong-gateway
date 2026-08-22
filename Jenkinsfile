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

        // Only touches backend+kong; jenkins is never included so the pipeline can't recreate itself.
        stage('Start Services') {
            steps {
                dir('/workspace') {
                    sh 'docker compose -p kong-poc up -d --no-deps backend kong'
                }
            }
        }

        stage('Wait for Services') {
            steps {
                sh '''
                    for i in $(seq 1 30); do
                        curl -sf http://localhost:5000/health > /dev/null 2>&1 && break
                        sleep 1
                    done
                    for i in $(seq 1 30); do
                        curl -sf http://localhost:8001/status > /dev/null 2>&1 && break
                        sleep 1
                    done
                    sleep 3
                '''
            }
        }

        // x-environment-validator sits on /api/hello, not /api/ping.
        stage('Test: Valid Request') {
            steps {
                sh 'curl -i -H "x-environment: DEV" http://localhost:8000/api/hello'
            }
        }

        stage('Test: Missing Header') {
            steps {
                sh '''
                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/api/hello)
                    [ "$STATUS" = "400" ] || { echo "Expected 400, got $STATUS"; exit 1; }
                '''
            }
        }

        stage('Test: Invalid Header') {
            steps {
                sh '''
                    STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "x-environment: INVALID" http://localhost:8000/api/hello)
                    [ "$STATUS" = "403" ] || { echo "Expected 403, got $STATUS"; exit 1; }
                '''
            }
        }

        stage('Verify Setup') {
            steps {
                dir('/workspace') {
                    sh '''
                        docker compose -p kong-poc ps backend kong
                        curl -s http://localhost:8001/services
                    '''
                }
            }
        }
    }

    post {
        // Scoped to backend/kong only - jenkins keeps running so it can report this result.
        failure {
            dir('/workspace') {
                sh 'docker compose -p kong-poc logs backend kong || true'
            }
        }
        always {
            dir('/workspace') {
                sh 'docker compose -p kong-poc rm -fsv backend kong || true'
            }
        }
    }
}

