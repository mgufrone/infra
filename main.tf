terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = ">= 2.0.0"
    }
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.0.1"
    }
  }
}

# Set the variable value in *.tfvars file
# or using -var="do_token=..." CLI option
//variable "do_token" {}

# Configure the DigitalOcean Provider
provider "digitalocean" {
//  token = var.do_token
}
provider "helm" {
  kubernetes {
    config_path = "${path.root}/kubeconfig"
  }
}
provider "kubernetes" {
  config_path = "${path.root}/kubeconfig"
}

# Create a web server
resource "digitalocean_kubernetes_cluster" "dev-cluster" {
  name    = "dev-cluster"
  region  = "sgp1"
  version = "1.21.2-do.2"
  auto_upgrade = true

  maintenance_policy {
    day = "sunday"
    start_time = "04:00"
  }

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-4gb"
    node_count = 1
    auto_scale = true
    min_nodes = 1
    max_nodes = 3
  }
}

resource "local_file" "kubeconfig" {
  depends_on = [digitalocean_kubernetes_cluster.dev-cluster]
  content = digitalocean_kubernetes_cluster.dev-cluster.kube_config[0].raw_config
  filename = "${path.root}/kubeconfig"
}

resource "helm_release" "nginx_ingress" {
  depends_on = [local_file.kubeconfig]
  name = "nginx-ingress-controller"
  namespace = "ingress"
  create_namespace = true
  chart = "nginx-ingress-controller"
  repository = "https://charts.bitnami.com/bitnami"
  set {
    name = "service.type"
    value = "LoadBalancer"
  }
  set {
    name = "podAnnotations"
    value = <<EOT
prometheus.io/scrape: "true"
prometheus.io/port: "10254"
prometheus.io/scheme: "http"
prometheus.io/path: "/metrics"
EOT
  }
  set {
    name = "metrics.enabled"
    value = "true"
  }
}

resource "helm_release" "cert_manager" {
  depends_on = [null_resource.cert_manager_provision]
  name = "cert-manager"
  namespace = "cert-manager"
  create_namespace = true
  chart = "cert-manager"
  repository = "https://charts.jetstack.io"
}

resource "helm_release" "kubernetes_dashboard" {
  depends_on = [helm_release.nginx_ingress]
  dependency_update = true
  name = "kubernetes-dashboard"
  chart = "kubernetes-dashboard"
  namespace = "dashboard"
  repository = "https://kubernetes.github.io/dashboard"
  create_namespace = true
  set {
    name = "ingress.enabled"
    value = true
  }
  set {
    name = "ingress.hosts.0"
    value = var.dashboard_host
  }
}

resource "helm_release" "metrics_server" {
  depends_on = [local_file.kubeconfig]
  dependency_update = true
  name = "kube-state-metrics"
  chart = "kube-state-metrics"
  namespace = "kube-system"
  repository = "https://prometheus-community.github.io/helm-charts"
  create_namespace = true
}

resource "null_resource" "cert_manager_provision" {
  depends_on = [digitalocean_kubernetes_cluster.dev-cluster]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.root}/kubeconfig apply -f https://github.com/jetstack/cert-manager/releases/download/v1.4.0/cert-manager.crds.yaml"
  }
}
resource "null_resource" "metric_server_provision" {
  depends_on = [digitalocean_kubernetes_cluster.dev-cluster]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.root}/kubeconfig apply -f  https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  }
}

resource "null_resource" "weave_provision" {
  depends_on = [helm_release.nginx_ingress]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.root}/kubeconfig apply -f \"https://cloud.weave.works/k8s/scope.yaml?k8s-version=$(kubectl version | base64 | tr -d '\n')\""
  }
}

resource "helm_release" "jenkins" {
  depends_on = [helm_release.nginx_ingress]
  chart = "jenkins"
  repository = "https://charts.jenkins.io"
  name = "jenkins"
  namespace = "default"
  set {
    name = "agent.podTemplates.deployment"
    value = <<EOT
- name: deployment
  label: jenkins-deployment
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:debug
    command: "sleep"
    args: "infinity"
    ttyEnabled: true
    privileged: false
  - name: helm
    image: alpine/helm:latest
    command: "sleep"
    args: "infinity"
    ttyEnabled: true
    privileged: false
  - name: kubectl
    image: bitnami/kubectl:1.21.2
    command: "sleep"
    args: "infinity"
    ttyEnabled: true
    privileged: false
EOT
  }
  set {
    name = "agent.podTemplates.composer"
    value = <<EOT
- name: composer
  label: jenkins-composer
  containers:
  - name: composer
    image: composer:2.1.3
    command: "sleep"
    args: "infinity"
    ttyEnabled: true
    privileged: false
    resourceRequestCpu: 400m
    resourceRequestMemory: 512Mi
    resourceLimitCpu: "1"
    resourceLimitMemory: "1024Mi"
EOT
  }
  set {
    name = "controller.installPlugins"
    value = "false"
  }
  set {
    name = "controller.ingress.enabled"
    value = "true"
  }
  set {
    name = "controller.ingress.hostName"
    value = var.jenkins_host
  }
  set {
    name = "controller.image"
    value = "mgufrone/jenkins-plugin"
  }
  set {
    name = "controller.tag"
    value = "1.1.0"
  }
  set {
    name = "controller.initContainerEnv[0].name"
    value = "JENKINS_UC"
  }
  set {
    name = "controller.initContainerEnv[0].value"
    value = var.jenkins_update_center
  }
  set {
    name = "controller.containerEnv[0].name"
    value = "JENKINS_UC"
  }
  set {
    name = "controller.containerEnv[0].value"
    value = var.jenkins_update_center
  }
  set_sensitive {
    name = "controller.JCasC.configScripts.jenkins-casc-configs"
    value = <<EOT
credentials:
  system:
    domainCredentials:
    - credentials:
      - usernamePassword:
          description: "github creds"
          id: "github"
          password: ${var.github_password}
          scope: GLOBAL
          username: ${var.github_username}
EOT
  }
}

resource "helm_release" "prometheus" {
  depends_on = [local_file.kubeconfig]
  dependency_update = true
  name = "prometheus"
  chart = "prometheus"
  namespace = "kube-system"
  repository = "https://prometheus-community.github.io/helm-charts"
  create_namespace = true
}
resource "helm_release" "grafana" {
  depends_on = [local_file.kubeconfig]
  dependency_update = true
  name = "grafana"
  chart = "grafana"
  namespace = "kube-system"
  repository = "https://grafana.github.io/helm-charts"
  create_namespace = true
  set {
    name = "ingress.enabled"
    value = "true"
  }
  set {
    name = "ingress.hosts[0]"
    value = var.grafana_host
  }
}
