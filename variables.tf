variable "github_username" {
  type = string
  description = "github username for jenkins"
}
variable "github_password" {
  type = string
  description = "github password"
}
variable "jenkins_update_center" {
  default = "https://updates.jenkins-ci.org/"
  type = string
}

variable "grafana_host" {
  type = string
  description = "host name for grafana. e.g grafana.example.com"
}
variable "jenkins_host" {
  type = string
  description = "host name for jenkins. e.g jenkins.example.com"
}
variable "dashboard_host" {
  type = string
  description = "host name for kubernetes ui dashboard. e.g dashboard.example.com"
}
