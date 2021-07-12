FROM jenkins/jenkins:2.289.2-lts-centos7
RUN jenkins-plugin-cli --plugins kubernetes slack blueocean git multibranch-scan-webhook-trigger configuration-as-code pipeline-utility-steps workflow-aggregator sonar
