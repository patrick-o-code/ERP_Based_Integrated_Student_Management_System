pipeline {
    agent { label 'agent-1' }

    stages {
        stage('code') {
            steps {
                echo 'pipeline check successfully'
                git url:"https://github.com/patrick-o-code/ERP_Based_Integrated_Student_Management_System.git", branch: 'main'
            }
        }

        stage('build') {
            steps {
                echo 'build stage running'
            }
        }

        stage('deploy') {
            steps {
                echo 'deploy stage running'
            }
        }
    }
}