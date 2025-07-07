# ECS → AWS EKS / Kubernetes (On-Prem) Migration — Proof of Concept

## 1 Purpose  
This PoC uses a tiny **hello-world** service to walk through the **entire migration life-cycle** from **AWS ECS** to **Kubernetes**—both **AWS EKS** and an **on-prem Minikube** cluster—while the old and new stacks run **side-by-side**.

**What it proves**

* **Build once, deploy twice**  
  * **ECS** receives its usual **rolling-update**.  
  * **Kubernetes** is updated through a **Helm** chart that Argo CD automatically syncs into Minikube (GitOps).  

* **Three cut-over styles**  
  1. **Planned downtime** (maintenance window).  
  2. **Zero-downtime via DNS weighting** − ECS → on-prem K8s.  
  3. **Zero-downtime via ALB listener weighting** − ECS → AWS EKS in the **same account**, re-using the existing ALB with `TargetGroupBinding`.  

* **Reusable patterns** — Terraform modules, Helm templating, and Argo CD GitOps show how to keep IaC, CI/CD, and traffic shifting declarative and reviewable.

> **Scope note**  The focus is on mechanics: parallel deployment, traffic shifting, and rollback safety.  
> Security, observability, capacity, DR, and other production concerns need additional work before go-live.

---

## 2 Current vs. Target

| Layer   | Today (ECS) | Target (Kubernetes) |
|---------|-------------|---------------------|
| Runtime | AWS ECS | **AWS EKS** or on-prem K8s |
| CI/CD   | GitHub Actions → ECS task | Same pipeline + Helm + Argo CD |
| **App URL** | <https://ecs-hello-world.alekspetkov.com> | <https://hello-world.alekspetkov.com> |
| **GitOps UI** | — | Argo CD: <https://argo.alekspetkov.com> (credentials on request) |
| Ingress | **Application Load Balancer** (ALB) | Same ALB† (AWS EKS path) or new ingress controller (on-prem) |

† On the AWS EKS path we attach Pods via **TargetGroupBinding** with the AWS Load Balancer Controller so ECS and EKS share one listener.

---

## 3 Migration Strategies

### 3.1 Planned Downtime — *ECS → on-prem Kubernetes*  
1. Schedule a maintenance window.  
2. **Migrate shared services first** (DB, Redis, object storage, secrets) to on-prem.  
3. Deploy the app on on-prem K8s; run smoke tests.  
4. Switch DNS 100 % to on-prem K8s (or point the ALB/ingress to on-prem); shut down ECS tasks.

> **Downtime Disclaimer** – Users see a short outage during the cut-over. Prepare comms and rollback steps.

---

### 3.2 Zero-Downtime — DNS Weighted (*ECS → on-prem Kubernetes*)  
1. Ensure **all stateful components are reachable from both clusters**.  
2. Deploy the same image/version to ECS and on-prem K8s.  
3. Create a Route 53 weighted record: start 95 % ECS / 5 % on-prem; ramp up on-prem weight.  
4. Monitor SLOs; roll back if errors rise.  
5. Shift 100 % to on-prem; delete the ECS service.

> **DNS Disclaimer** – Works only if sessions and data are shared. Keep TTL ≤ 60 s; rely on Route 53 health checks.

---

### 3.3 Zero-Downtime — Shared ALB Weighted (*ECS → AWS EKS, same account*)  
1. ECS service is already in **Target Group A** on the ALB.  
2. Install **AWS Load Balancer Controller** in AWS EKS.  
3. Add a `TargetGroupBinding`; Pods register into **Target Group B** on the **same listener**.  
4. Adjust **listener rule weights** (e.g., 95 % A / 5 % B).  
5. Ramp toward B while watching CloudWatch dashboards.  
6. Shift to 100 % B; remove ECS service and Target Group A.

> **ALB Disclaimer** – Needs shared state and robust health checks; automate quick rollback of weights on errors.

---

## 4 Detailed Migration Workflow (Steps 1 – 14)

| # | Step | Key Actions |
|---|------|-------------|
| 1 | **Discovery** | Export ECS task def, env vars, secrets, IAM roles, networking. |
| 2 | **Prepare Registry** | Ensure an ECR/private registry reachable from both clusters. |
| 3 | **Provision Cluster** | *AWS EKS*: Terraform modules.<br>*On-prem*: Minikube or prod K8s via Ansible/scripts. |
| 4 | **Install Add-ons** | Helm, Argo CD, Metrics Server.<br>Ingress: existing ALB + AWS LBC (EKS) **or** NGINX/Traefik (on-prem). |
| 5 | **Translate Manifests** | Create Helm chart `helm/hello-world/` with `values.eks.yaml` & `values.onprem.yaml`. |
| 6 | **Build & Push Image** | GitHub Actions: `dotnet publish → docker build → docker push`. |
| 7 | **Wire GitOps** | Create an Argo CD *Application* pointing at the Helm chart & cluster. |
| 8 | **Load / Perf Test** | k6 scripts simulate target TPS; collect baseline metrics. |
| 9 | **Choose Path** | Pick §3.1, §3.2, or §3.3 based on SLAs. |
| 10a | **Planned-Downtime Execution** | Freeze traffic → migrate services → deploy on-prem → validate → DNS/ALB cut-over. |
| 10b | **DNS Weighted Execution** | Deploy in parallel → ramp Route 53 weight → observe SLOs → full cut-over. |
| 10c | **ALB Weighted Execution** | Deploy in parallel → ramp ALB weights → observe dashboards → full cut-over. |
| 11 | **Post-Cut Validation** | Functional checks, load-test replay, error-budget review. |
| 12 | **Decommission ECS** | Delete ECS service, task def, alarms, unused IAM roles/Target Group A. |
| 13 | **Cleanup & Docs** | Update runbooks, diagrams, architecture docs. |
| 14 | **Handoff** | Knowledge transfer to Ops/SRE; plan DR drills & rollback tests. |

---

## 5 Live Demo — How to Trigger & Observe

1. **Edit the App** — change a greeting in `Program.cs`, commit & push.  
2. **CI/CD Pipeline** auto-builds, tags, pushes.  
3. **Endpoints**  
   * ECS: <https://ecs-hello-world.alekspetkov.com>  
   * AWS EKS / on-prem: <https://hello-world.alekspetkov.com>  
   Both display the new greeting post-deploy.  
4. **Argo CD** — open <https://argo.alekspetkov.com>; `hello-world` turns **Synced**.  
5. **Traffic Shift**  
   * **DNS path**: change Route 53 weights.  
   * **ALB path**: edit listener rule weights between TG A & TG B.

---

## 6 CI/CD Controls

| Variable      | Effect                                               |
| ------------- | ---------------------------------------------------- |
| `DEPLOY_ECS`  | `true/false` — update ECS service                    |
| `UPDATE_HELM` | `true/false` — bump chart version & Argo CD sync     |

---

## 7 Why Terraform, Helm, and Argo CD? — With vs. Without

| Tool      | Using the Tool (recommended) | Without the Tool (manual approach) |
|-----------|-----------------------------|------------------------------------|
| **Terraform** | *Idempotent* AWS EKS provisioning; `plan`/`apply`; reusable modules. | Imperative `eksctl` or console clicks; drift; no audit trail. |
| **Helm**  | Versioned, parameterized charts; `helm rollback`; DRY YAML. | Raw manifests; copy-paste divergence; manual edits. |
| **Argo CD** | GitOps reconciliation; drift detection; multi-cluster view. | `kubectl apply` in CI; state drifts outside Git; manual rollbacks. |

---

## 8 ECS vs. AWS EKS / Kubernetes Comparison

| Feature            | ECS                                    | AWS EKS / On-Prem K8s               |
|--------------------|----------------------------------------|-------------------------------------|
| **Platform**       | AWS only                               | Cloud-agnostic (AWS EKS or on-prem) |
| **Flexibility**    | AWS-managed, limited customization     | Fully extensible open-source stack  |
| **Portability**    | Tightly coupled to AWS services        | Runs everywhere Kubernetes runs     |
| **Community**      | AWS ecosystem                          | Large open-source community         |
| **Migration Impact**| Re-platform effort required            | Re-use workloads across clouds      |

---

## 9 Included in PoC
* GitHub Actions workflows (build, ECS deploy, Helm package).  
* Helm chart (`helm/hello-world/`).  
* Structurizr DSL diagrams → rendered in `docs/diagrams/`.  
* Minimal ASP.NET Core **hello-world** service.

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
- [ ] Route 53 or ALB weighting configured and tested (zero-downtime paths)  
- [ ] Rollback validated (weights → ECS or redeploy previous chart)  
- [ ] Logs & metrics visible in CloudWatch / Prometheus  
- [ ] Argo CD UI reachable with read-only RBAC for stakeholders  

---

## 12 Summary

This PoC covers **three** migration flows—from a full outage window to two zero-downtime options (DNS-based and ALB-based).  
Use it as a blueprint, then add production-grade IaC, security, observability, and state-management before go-live.

---

*Contributions welcome — open a PR with improvements or questions.*
