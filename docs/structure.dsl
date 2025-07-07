workspace "CI/CD pipeline" {

  model {
    Dev = Person "Developer"

    GitHub = SoftwareSystem "GitHub Actions" {
      Build  = Container "Build & Push"
      Deploy = Container "Deploy to ECS"  "Runs only when variable DEPLOY_ECS=true"
      Helm   = Container "Update Helm"    "Runs only when variable UPDATE_HELM=true"
    }

    ECR  = SoftwareSystem "Amazon ECR"
    ECS  = SoftwareSystem "Amazon ECS"
    Argo = SoftwareSystem "Argo CD AutoSync ON"
    K8s  = SoftwareSystem "EKS Cluster"

    Dev   -> Build  "git push"
    Build -> ECR    "docker push"
    Build -> Deploy "pass tag"
    Build -> Helm   "commit tag"

    Deploy -> ECS   "force new rolling update deployment"

    Helm  -> Argo   "chart commit image update"
    Argo  -> K8s    "autosyncs manifests"
  }

  views {
    container GitHub pipeline {
      include *
      autolayout lr
    }

    styles {
      element "Container" {
        background "#8ecae6"
      }
      element "Software System" {
        background "#c6e6f9"
      }
      element "Person" {
        shape person
      }
    }
  }
}
