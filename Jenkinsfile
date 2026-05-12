pipeline {
    agent any  // Run on any available Jenkins agent

    environment {
        // Internal Docker registry — update to match your environment
        REGISTRY     = "registry.company.internal"
        IMAGE_NAME   = "${REGISTRY}/portal"
        // Tag every image with the Jenkins build number for full traceability
        IMAGE_TAG    = "${BUILD_NUMBER}"
        DEPLOY_DIR   = "/opt/company/app"
    }

    stages {

        stage('Checkout') {
            steps {
                // Pull source code from the configured SCM (Bitbucket/GitHub)
                checkout scm
            }
        }

        stage('Build Image') {
            steps {
                // Build and tag Docker image with build number
                sh "docker build -t ${IMAGE_NAME}:${IMAGE_TAG} ."
            }
        }

        stage('Push to Registry') {
            steps {
                // Credentials stored in Jenkins — never hardcoded
                withCredentials([usernamePassword(
                    credentialsId: 'nexus-creds',
                    usernameVariable: 'REG_USER',
                    passwordVariable: 'REG_PASS'
                )]) {
                    sh """
                        echo ${REG_PASS} | docker login ${REGISTRY} -u ${REG_USER} --password-stdin
                        docker push ${IMAGE_NAME}:${IMAGE_TAG}
                    """
                }
            }
        }

        stage('Deploy') {
            steps {
                // Ansible handles secrets injection from Vault and container restart
                ansiblePlaybook(
                    playbook: 'deploy/ansible/deploy.yml',
                    inventory: 'deploy/ansible/inventory/prod',
                    extraVars: [
                        image_tag: "${IMAGE_TAG}"
                    ]
                )
            }
        }

        stage('Smoke Test') {
            steps {
                // Validate deployment health before marking build as success
                sh "bash deploy/scripts/smoke-test.sh"
            }
        }
    }

    post {
        failure {
            // Automatically roll back to previous build on any stage failure
            echo "Pipeline failed — triggering rollback"
            ansiblePlaybook(
                playbook: 'deploy/ansible/rollback.yml',
                inventory: 'deploy/ansible/inventory/prod',
                extraVars: [
                    rollback_tag: "${BUILD_NUMBER.toInteger() - 1}"
                ]
            )
        }
        success {
            echo "Deploy successful — build ${IMAGE_TAG} is live"
        }
    }
}