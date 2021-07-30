current_dir = $(shell pwd)
deploy-jenkins :: build-jenkins jenkins
build-jenkins:
	docker build -t $(IMAGE):$(TAG) -f Dockerfile .
	docker push $(IMAGE):$(TAG)
jenkins:
	helm repo add jenkinsci https://charts.jenkins.io
	helm repo update
	helm upgrade --install --history-max=5 jenkins jenkinsci/jenkins -f jenkins-values.yaml --set controller.tag=$(TAG) --set=controller.image=$(IMAGE)
grafana:
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update
	helm upgrade --install --create-namespace --namespace kube-system grafana -f grafana.yaml grafana/grafana
sonarqube:
	[ -d helm-chart-sonarqube ] || git clone https://github.com/SonarSource/helm-chart-sonarqube
	cd helm-chart-sonarqube/charts/sonarqube && \
	helm dependency update && \
	helm upgrade --install --namespace sonarqube --create-namespace sonarqube -f $(current_dir)/sonarqube.yaml ./
keycloak:
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo update
	helm upgrade --install --namespace kube-system auth bitnami/keycloak -f keycloak.yaml
mysql:
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo update
	helm upgrade --install db bitnami/mysql -f mysql.yaml
nats:
	helm repo add nats https://nats-io.github.io/k8s/helm/charts/
	helm repo update
	helm upgrade --install nats nats/nats
	helm upgrade --install nats-streaming nats/stan --set stan.nats.url=nats://nats:4222 --set stan.clusterID=nats-streaming
keda:
	helm repo add kedacore https://kedacore.github.io/charts
	helm repo update
	helm upgrade --install --create-namespace keda kedacore/keda --namespace keda
