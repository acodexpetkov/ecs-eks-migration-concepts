# ECS → AWS EKS / Kubernetes (On-Prem) Migration — Proof of Concept

## 1 Purpose  
This PoC shows **how an application running on AWS ECS can be migrated to an on-prem Kubernetes cluster with no downtime** by operating both stacks in parallel and gradually shifting traffic.

* The existing **hello-world** service at **<https://ecs-hello-world.alekspetkov.com>** is re-packaged into a **Helm** chart and synced by **Argo CD** into an on-prem **Minikube** cluster, where it is exposed at **<https://hello-world.alekspetkov.com>**.  
* One image is built, then deployed twice: a rolling update on ECS and a Helm release on Kubernetes.  
* Weighted **DNS records** let you move traffic from 100 % ECS to 0 % ECS (or back) in fine increments, delivering a zero-downtime cut-over.
* Along the way the PoC demonstrates Helm templating, Argo CD GitOps, parallel deployment and DNS-based migration.

> **Scope note** – The PoC proves mechanics: parallel deploy, weighted traffic shift on request, and rollback safety. Hardening for security, observability, capacity, and DR is out of scope.

---

## 2 Current vs. Target

| Layer         | Today (ECS)                               | Target (Kubernetes)                            |
|---------------|-------------------------------------------|------------------------------------------------|
| Runtime       | AWS ECS                                   | **AWS EKS** or on-prem K8s                     |
| CI/CD         | GitHub Actions → ECS task                 | Same pipeline + Helm + Argo CD                 |
| App URL       | <https://ecs-hello-world.alekspetkov.com> | <https://hello-world.alekspetkov.com>          |
| GitOps UI     | —                                         | Argo CD UI: <https://argo.alekspetkov.com>     |
| Ingress       | Application Load Balancer (ALB)           | Same ALB † (AWS EKS path) or new ingress on-prem |

† On the AWS EKS path, Pods join the same ALB listener via **TargetGroupBinding** managed by the AWS Load Balancer Controller.

---

## 3 Migration Strategies (High Level Overview)

### 3.1 Planned Downtime — *ECS → on-prem Kubernetes*  
1. Schedule a maintenance window.  
2. **Migrate shared services first** (DB, Redis, object storage, secrets) to on-prem.  
3. Deploy the app on on-prem K8s and run stress tests.  
4. Switch DNS 100 % to on-prem K8s (or repoint the ALB/ingress); decommission ECS.

> **Downtime disclaimer** – Users see a brief outage during the cut-over; plan comms and rollback.

---

### 3.2 Zero-Downtime — DNS Weighted *ECS → on-prem Kubernetes*  
1. Ensure **all stateful components are reachable from both clusters**.  
2. Deploy the same image/version to ECS and on-prem K8s.  
3. Create a Route 53 weighted record: start 95 % ECS / 5 % on-prem, then ramp up on-prem.  
4. Monitor SLOs; roll back if errors rise.  
5. Shift 100 % to on-prem; delete the ECS service.

> *Works only if sessions and data are shared. Keep TTL ≤ 60 s and enable health checks.*

---

### 3.3 Zero-Downtime — Shared ALB Weighted *ECS → AWS EKS (same account)*  
1. ECS service is already in **Target Group A** on the ALB.  
2. Install **AWS Load Balancer Controller** in AWS EKS.  
3. Add a `TargetGroupBinding`; Pods register into **Target Group B** on the same listener.  
4. Adjust **listener rule weights** (e.g., 95 % A / 5 % B).  
5. Ramp toward B while watching CloudWatch dashboards.  
6. Shift to 100 % B; remove ECS service and Target Group A.

> *Requires shared state and robust health checks; automate quick rollback of weights.*

---

## 4 Detailed Migration Workflow (Steps 1 – 14)

| #  | Step                      | Key Actions                                                                          |
|----|---------------------------|--------------------------------------------------------------------------------------|
| 1  | **Discovery**             | Export ECS task def, env vars, secrets, IAM roles, networking.                       |
| 2  | **Prepare Registry**      | Ensure an ECR/private registry reachable from both clusters.                         |
| 3  | **Provision Cluster**     | **AWS EKS** via Terraform; on-prem Minikube or prod K8s via Ansible/scripts.          |
| 4  | **Install Add-ons**       | Helm, Argo CD, Metrics Server. Ingress: ALB + AWS LBC (EKS) or NGINX/Traefik (on-prem). |
| 5  | **Translate Manifests**   | Create Helm chart `helm/hello-world/` with `values.eks.yaml` & `values.onprem.yaml`. |
| 6  | **Build & Push Image**    | GitHub Actions: `dotnet publish → docker build → docker push`.                       |
| 7  | **GitOps**                | Create an Argo CD *Application* pointing at the Helm chart and cluster.              |
| 8  | **Load / Perf Test**      | k6 scripts simulate target TPS; capture baseline metrics.                            |
| 9  | **Choose Path**           | Pick strategy 3.1, 3.2, or 3.3 based on SLAs.                                        |
| 10a| **Planned-Downtime Execution** | Freeze traffic → migrate services → deploy on-prem → validate → DNS/ALB cut-over.    |
| 10b| **DNS-Weighted Execution** | Deploy in parallel → ramp Route 53 weight → observe SLOs → full cut-over.            |
| 10c| **ALB-Weighted Execution** | Deploy in parallel → ramp ALB weights → observe dashboards → full cut-over.          |
| 11 | **Post-Cut Validation**   | Functional checks, load-test replay,                                                 |
| 12 | **Decommission ECS**      | Delete ECS service, task def, alarms, unused IAM roles/Target Group A.               |
| 13 | **Cleanup & Docs**        | Update runbooks, diagrams, architecture docs.                                        |
| 14 | **Handoff**               | Knowledge transfer to Ops/SRE; plan DR drills & rollback tests.                      |

---

## 5 Live Demo — How to Trigger & Observe

1. **Edit the app** — change a greeting in `Program.cs`, commit & push.  
2. **Pipeline** builds, tags, and pushes the image.  
3. **Endpoints**  
   * ECS URL  : <https://ecs-hello-world.alekspetkov.com>  
   * K8s URL  : <https://hello-world.alekspetkov.com>  
   The new greeting appears on both once deployments finish.  
4. **Argo CD** — open <https://argo.alekspetkov.com>; `hello-world` application turns **Synced**.  
5. **Traffic shift only on request for demo**  
   * **DNS path** : update Route 53 weights.

---

## 6 CI/CD Controls

| Variable      | Effect                                             |
|---------------|----------------------------------------------------|
| `DEPLOY_ECS`  | `true/false` — update ECS service                  |
| `UPDATE_HELM` | `true/false` — bump chart version & Argo CD sync   |

---

## 7 Why Terraform, Helm, and Argo CD? — With vs Without

| Tool            | Using the Tool (recommended)                                                    | Without the Tool (manual)                      |
|-----------------|---------------------------------------------------------------------------------|-----------------------------------------------|
| **Terraform**   | *Idempotent* AWS EKS provisioning; `plan` / `apply`; reusable modules.          | Imperative `eksctl` or console clicks; drift. |
| **Helm**        | Versioned, parameterised charts; `helm rollback`; DRY YAML.                     | Raw manifests; copy-paste divergence.         |
| **Argo CD**     | GitOps reconciliation; drift detection; multi-cluster view.                     | `kubectl apply` in CI; state drifts in prod.  |

---

## 8 ECS vs. AWS EKS / Kubernetes Comparison

| Feature            | ECS                                    | AWS EKS / On-Prem K8s              |
|--------------------|----------------------------------------|------------------------------------|
| **Platform**       | AWS only                               | Cloud-agnostic (AWS EKS or on-prem)|
| **Flexibility**    | AWS-managed, limited customization     | Fully extensible open-source stack |
| **Portability**    | Tightly coupled to AWS services        | Runs anywhere Kubernetes runs      |
| **Community**      | AWS ecosystem                          | Large open-source community        |
| **Migration Impact**| Re-platform effort required            | Re-use workloads across clouds     |

---

## 9 Included in PoC
* GitHub Actions workflows (build, ECS deploy, Helm package)  
* Helm chart (`helm/hello-world/`)  
* Structurizr DSL diagrams rendered in `docs/diagrams/`  
* Minimal ASP.NET Core **hello-world** service

---

## 10 Out of Scope (Prod Hardening)

* Automated cluster creation  
* Centralised logging/metrics (Prometheus, Loki, CloudWatch)  
* Secrets encryption (KMS, Sealed Secrets, Vault)  
* Autoscaling, network policies, PodDisruptionBudgets  
* DR, cross-region standby, backup plans

---

## 11 Demo & Prerequisites Checklist

- [ ] Kubernetes cluster + Helm + Argo CD installed  
- [ ] GitHub Actions pushes image to registry  
- [ ] Helm chart deploys via Argo CD with correct values file  
- [ ] `DEPLOY_ECS` / `UPDATE_HELM` toggles verified  
- [ ] Route 53 or ALB weighting configured and tested  
- [ ] Rollback validated (weights → ECS or redeploy previous chart)  
- [ ] Logs & metrics visible in CloudWatch / Prometheus  
- [ ] Argo CD UI reachable with read-only RBAC for stakeholders  

---

## 12 Summary

The PoC proves an **image-once, deploy-twice** workflow, parallel operation of ECS and Kubernetes, and a **zero-downtime** migration path by weighted traffic shifting. 

---

*Contributions welcome — open a PR with improvements or questions.*
