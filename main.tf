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
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.7.0"
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
    value = "ClusterIP"
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
    value = "dashboard.dev.mgufron.com"
  }
}

resource "helm_release" "vault" {
  depends_on = [digitalocean_kubernetes_cluster.dev-cluster]
  chart = "vault"
  repository = "https://helm.releases.hashicorp.com"
  name = "vault"
  namespace = "cert-manager"
  dependency_update = true
}


resource "null_resource" "cert_manager_provision" {
  depends_on = [digitalocean_kubernetes_cluster.dev-cluster]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.root}/kubeconfig apply -f https://github.com/jetstack/cert-manager/releases/download/v1.4.0/cert-manager.crds.yaml"
  }
}

resource "null_resource" "weave_provision" {
  depends_on = [helm_release.nginx_ingress]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.root}/kubeconfig apply -f \"https://cloud.weave.works/k8s/scope.yaml?k8s-version=$(kubectl version | base64 | tr -d '\n')\""
  }
}

resource "null_resource" "vault_unseal" {
  depends_on = [helm_release.vault]
  provisioner "local-exec" {
    command = "kubectl --kubeconfig=${path.root}/kubeconfig exec -n cert-manager $(kubectl --kubeconfig=${path.root}/kubeconfig get pods -n cert-manager --selector \"app.kubernetes.io/name=vault\" --output=name) vault operator init -recovery-shares=7 -recovery-threshold=4 -recovery-pgp-keys=\"keybase:gufy,keybase:jenkins\" -root-token-pgp-key=\"keybase:gufy\""
  }
}

resource "helm_release" "jenkins" {
  depends_on = [helm_release.nginx_ingress]
  chart = "jenkins"
  repository = "https://charts.jenkins.io"
  name = "jenkins"
  namespace = "default"
  dependency_update = true
  set {
    name = "agent.podTemplates.composer"
    value = <<EOT
- name: composer
  label: jenkins-composer
  containers:
  - name: composer
    image: composer:2.1.3
    command: "/bin/sh -c"
    args: "cat"
    ttyEnabled: true
    privileged: false
    resourceRequestCpu: 400m
    resourceRequestMemory: 512Mi
    resourceLimitCpu: "1"
    resourceLimitMemory: "1024Mi"
EOT

  }
  set {
    name = "controller.ingress.enabled"
    value = "true"
  }
  set {
    name = "controller.ingress.hostName"
    value = "jenkins.dev.mgufron.com"
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
          password: ${var.github_username}
          scope: GLOBAL
          username: ${var.github_password}
EOT
  }
}
