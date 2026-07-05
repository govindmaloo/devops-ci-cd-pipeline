pipeline {
    agent any

    environment {
        STAGING_DIR = '/var/lib/jenkins/flask-staging'
        MONGO_URI   = 'mongodb://localhost:27017/studentDB'
        SECRET_KEY  = 'staging-secret-key'
    }

    triggers {
        // Poll GitHub every 2 minutes (works without webhook setup)
        pollSCM('H/2 * * * *')
    }

    stages {
        stage('Build') {
            steps {
                echo 'Installing Python dependencies...'
                sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip
                    pip install -r requirements.txt
                '''
            }
        }

        stage('Test') {
            steps {
                echo 'Running pytest...'
                sh '''
                    . venv/bin/activate
                    cat > .env << EOF
MONGO_URI=${MONGO_URI}
SECRET_KEY=${SECRET_KEY}
EOF
                    pytest test_app.py -v --tb=short
                '''
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                echo 'Deploying to staging environment...'
                sh 'bash scripts/deploy-staging.sh'
            }
        }
    }

    post {
        success {
            echo 'Pipeline succeeded!'
            mail to: "${env.NOTIFICATION_EMAIL ?: 'govind.maloo@gmail.com'}",
                 subject: "✅ SUCCESS: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: """Pipeline completed successfully.

Job:    ${env.JOB_NAME}
Build:  #${env.BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
URL:    ${env.BUILD_URL}
"""
        }
        failure {
            echo 'Pipeline failed!'
            mail to: "${env.NOTIFICATION_EMAIL ?: 'govind.maloo@gmail.com'}",
                 subject: "❌ FAILED: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
                 body: """Pipeline failed. Please check the logs.

Job:    ${env.JOB_NAME}
Build:  #${env.BUILD_NUMBER}
Branch: ${env.BRANCH_NAME}
URL:    ${env.BUILD_URL}
"""
        }
    }
}
