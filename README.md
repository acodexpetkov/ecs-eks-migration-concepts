# ECS to EKS/Kubernetes On-Prem Migration – PoC

## Introduction

This is a **Proof-of-Concept (PoC)** for migrating the `hello-world` app from **AWS ECS** to **Kubernetes** (AWS EKS or K8s/Minikube on-prem).  
It demonstrates architecture, pipelines, and migration patterns—**not a turnkey solution**.  
This PoC shows concepts and workflows that require adaptation to your specific environment, infrastructure, and organizational requirements.  
Do not expect this to deploy out-of-the-box in production without customization and rigorous validation.

---

## What Are We Simulating?

Currently, the `hello-world` application runs in **AWS ECS** [ecs-hello-world.alekspetkov.com](https://ecs-hello-world.alekspetkov.com).  
This PoC illustrates how to **translate** that deployment into **Kubernetes**, enabling you to run the same app on **AWS EKS** or on-premises Kubernetes, using Minikube for local development and testing.  
This is a foundational step for enabling true multi-environment portability and a cloud-agnostic deployment model.

---

## Migration Steps (abstract)

1. **Provision Kubernetes Cluster:**  
   - If using EKS (AWS), provision with **Terraform** or your preferred IaC tool following best practices to ensure repeatability and consistency.  
   - For on-premises deployments, use **Minikube** or a production-grade Kubernetes cluster. For multiple on-prem clusters, consider developing reusable scripting or automation blueprints to standardize provisioning.  
   - Prepare essential Kubernetes add-ons such as **Argo CD** for GitOps-driven deployment automation and **Helm** for package management.  
   - (See [Helm](https://helm.sh) and [Argo CD](https://argo-cd.readthedocs.io/en/stable/) for more details.)

2. **Translate the App:**  
   - Conduct a thorough discovery phase to fully understand the existing ECS deployment: task definitions, environment variables, networking, secrets, and service dependencies.  
   - Create a **Helm chart** (`helm/hello-world/`) that accurately reflects the ECS configuration and runtime environment, including ports, secrets, and environment variables.  
   - Ensure the Helm chart supports configuration for both EKS and on-prem clusters through values overlays.

3. **Load and Performance Testing:**  
   - Use tools like [k6.io](https://k6.io/) to perform stress and load testing on the app in the Kubernetes environment.  
   - Validate the app’s scalability and behavior under expected load to ensure readiness for production migration.

4. **Set Up CI/CD:**  
   - Implement GitHub Actions workflows that build and push container images.  
   - Use repository variables to control deployment targets, enabling selective or simultaneous deployments to ECS, EKS, or both environments.  
   - These workflows allow fine-grained control during migration, reducing risk by enabling incremental rollout.

5. **Dual Deployment:**  
   - Leverage the pipeline toggles to deploy the same application version concurrently to **ECS** and **EKS/Kubernetes** (including on-prem Minikube for testing).  
   - This enables validation in parallel environments without service interruption.  
   - You then have two live endpoints:  
     - **ECS:** [ecs-hello-world.alekspetkov.com](https://ecs-hello-world.alekspetkov.com)  
     - **K8s:** [hello-world.alekspetkov.com](https://hello-world.alekspetkov.com)  
     - **Argo CD UI:** [argo.alekspetkov.com](https://argo.alekspetkov.com) (User/password provided on request) — use this to monitor live deployments and sync status in real time.

---

## Live Demo & How to Trigger Deployments

- **Edit the app:** Modify visible output (e.g., a string in `Program.cs`) to verify deployment changes.  
- **Commit & Push:** The GitHub Actions pipeline automatically builds the image and deploys according to your repository variable settings.  
- **Observe Deployments:**  
  - Changes to the ECS deployment reflect at [ecs-hello-world.alekspetkov.com](https://ecs-hello-world.alekspetkov.com).  
  - Kubernetes deployment changes appear at [hello-world.alekspetkov.com](https://hello-world.alekspetkov.com).  
- The CI/CD pipeline manages image tagging, Helm chart versioning, and deployment targeting seamlessly.

---

## How Traffic Cutover Would Happen

In a real migration, **Route53** or another DNS provider would be configured to split traffic between ECS and Kubernetes backends without downtime:  

- Begin with a weighted DNS split sending 95% of traffic to ECS and 5% to Kubernetes.  
- Incrementally increase Kubernetes traffic share while monitoring application logs, performance, and error rates closely.  
- Once stability and performance are verified, route 100% of traffic to Kubernetes and safely decommission the ECS deployment.

This approach ensures a controlled, zero-downtime migration with the ability to quickly rollback if issues arise.

---

## Real-World Migration Disclaimer

> **Weighted DNS routing requires that users can interact with either ECS or EKS backends interchangeably without loss of data or session state.**  
> For this to be true:  
> - Stateful components (sessions, caches, databases) must be shared and accessible from both ECS and Kubernetes environments—e.g., a shared Redis or RDS instance.  
> - The application must not rely on ephemeral in-memory session or connection state local to pods or tasks.  
> - Health checks must be correctly configured for all weighted DNS targets, so traffic shifts away from unhealthy endpoints automatically.  
> - DNS TTL values should be kept low (≤ 60 seconds) to enable rapid traffic shifts and rollbacks.  
>
> This means weighted DNS alone is insufficient for zero-downtime migration if these conditions are unmet, such as with sticky sessions, WebSockets, or other stateful communication.

---

## CI/CD Control

- Deployment workflows to ECS and Kubernetes are toggled via repository variables—no code changes needed to switch targets.  
- This flexible toggle approach allows for incremental rollout, testing, and rollback without pipeline rewrites.  
- Repository variables include `DEPLOY_ECS` and `UPDATE_HELM`, controlling respective deployment steps.

---

## Why Helm?

- **Helm** is the de facto Kubernetes package manager, streamlining complex configuration management.  
- Helm charts keep deployment manifests and configuration consistent, version-controlled, and parameterized.  
- It enables easy upgrades, rollbacks, and environment-specific overrides, critical for migration scenarios spanning multiple clusters.

---

## Why Argo CD?

- **Argo CD** implements GitOps for Kubernetes, ensuring clusters reconcile to the exact desired state defined in Git repositories.  
- It provides automated sync, drift detection, and auditability—ensuring cluster consistency and enabling rapid rollback if needed.  
- Argo CD also supports multi-cluster management, making it ideal for managing on-prem and cloud environments uniformly.

---

## Why Terraform for EKS?

- **Terraform** offers infrastructure-as-code for reliable, repeatable EKS cluster provisioning and lifecycle management.  
- It allows you to declaratively define cluster networking, node groups, IAM roles, and add-ons in a version-controlled manner.  
- For on-premises Kubernetes, scripting or automation blueprints (e.g., Ansible playbooks) should be created to standardize cluster setup and ensure consistency across multiple clusters.

---

## ECS vs EKS/Kubernetes Comparison

| Feature           | ECS                               | EKS/K8s/Minikube                      |
|-------------------|----------------------------------|-------------------------------------|
| **Platform**      | AWS only                         | Cloud-agnostic (AWS or on-premises) |
| **Flexibility**    | AWS-managed, limited customization | Fully extensible open-source platform |
| **Portability**    | Tightly coupled to AWS services  | Easy to migrate across clouds & on-prem |
| **Community**      | AWS ecosystem                   | Large open-source community          |
| **Migration Impact** | Replatforming required for portability | Same workloads anywhere Kubernetes runs |

---

## What’s in this PoC

- **CI/CD Pipelines:** GitHub Actions workflows to build images, deploy to ECS, update Helm charts, and deploy to Kubernetes.  
- **Helm Chart:** Located in [`helm/hello-world/`](helm/hello-world/), representing Kubernetes deployment artifacts.  
- **Architecture Diagrams:** Written in Structurizr DSL (`docs/structure.dsl`) and automatically rendered to diagrams in [`docs/diagrams/`](docs/diagrams/).  
- **App:** A minimal `hello-world` ASP.NET Core example illustrating environment variables and network setup.

---

## What’s Out of Scope (for Production ready clusters)

- Automated provisioning of EKS or Minikube clusters.  
- Centralized logging, monitoring, and alerting infrastructure.  
- Secrets encryption and management (e.g., KMS, Sealed Secrets).  
- Advanced Kubernetes features such as node termination handlers, autoscaling, fine-grained RBAC, network policies.  
- Disaster recovery, backups, and failover strategies.

---

## Additional Considerations

- **Security:** Production environments require hardened IAM policies, encrypted secrets management, network policies, and RBAC enforcement, which are not covered in this PoC.  
- **Rollback Strategy:** While this PoC supports rollback via Helm and Argo CD, real-world rollback needs coordination across infrastructure, data, and application layers.  
- **Observability:** Metrics, centralized logging, and tracing are essential for production monitoring but are outside this PoC’s scope and must be implemented separately.  
- **Collaboration & Documentation:** Document your migration process and involve stakeholders early to ensure alignment and smooth rollout.  
- **Extensibility:** This PoC architecture can evolve to support multi-cluster Kubernetes deployments and hybrid cloud strategies.

---

## Summary

This PoC demonstrates the **conceptual approach** and pipeline architecture needed to migrate workloads from ECS to Kubernetes (cloud or on-prem), maintaining simultaneous deployments during migration and enabling controlled cutover.

**Important differences between this PoC and real-world production migration include:**

- Real applications are often stateful and require shared session or connection state, which complicates weighted DNS traffic splitting.  
- Production readiness requires extensive security, monitoring, backup, and recovery setups not included here.  
- Infrastructure provisioning must be automated and standardized with IaC for production reliability.  
- Operational concerns such as RBAC, network policies, and certificate management must be addressed.

---

### Demo & Prerequisites Checklist

- Kubernetes cluster provisioned with Helm and Argo CD installed and configured.  
- GitHub Actions pipelines build and push container images correctly.  
- Dual deployment toggles tested to deploy the app to ECS and Kubernetes environments.  
- Helm chart updates verified to trigger Argo CD sync and deployment.  
- Route53 or equivalent DNS weighted routing setup (demonstrable on request).  
- Failover and rollback scenarios tested via traffic weight adjustments (demonstrable on request).  
- Logs and metrics collection from ECS and Kubernetes deployments verified (demonstrable on request).  
- Argo CD UI accessible for deployment monitoring with appropriate user access configured (demonstrable on request).

---

_Questions or suggestions? Contributions welcome via pull requests!_
