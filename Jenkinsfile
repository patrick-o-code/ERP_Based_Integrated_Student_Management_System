pipeline {
    agent { label 'agent-1' }

    stages {
        stage('code') {
            steps {
                echo 'pipeline check successfully'
                git url:"https://github.com/patrick-o-code/ERP_Based_Integrated_Student_Management_System.git", branch: 'main'
            }
        }

        stage('push to docker hub') {
            steps {
                echo 'this is pushing the image to docker '
                sh "docker build -t erp_system-php:latest ."
                withCredentials([ usernamePassword(
                        credentialsId: 'dockerHubCred',
                        usernameVariable: 'dockerHubUser',
                        passwordVariable: 'dockerHubPass')]){
                sh "docker login -u ${env.dockerHubUser} -p ${env.dockerHubPass} "
                sh "docker image tag erp_system-php:latest ${env.dockerHubUser}/erp_system-php:latest"
                sh "docker push ${env.dockerHubUser}/erp_system-php:latest"
                }
            }
        }

        stage('deploy') {
            steps {
                echo 'deploy stage running'
            }
        }
    }
}