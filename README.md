# ECS → AWS EKS / Kubernetes (On-Prem) Migration — Proof of Concept

## 1 Purpose  
Demonstrate three migration patterns for moving a simple **hello-world** service from **AWS ECS** to **Kubernetes**:  
* **Planned downtime** (maintenance window)  
* **Zero-downtime with DNS weighting**  
* **Zero-downtime with shared ALB weighting (ECS → AWS EKS only)**  

This PoC shows architecture, pipelines, and traffic-cut-over techniques. It is **not** production-ready as-is.

---

## 2 Current vs. Target

| Layer   | Today (ECS) | Target (Kubernetes) |
|---------|-------------|---------------------|
| Runtime | AWS ECS | **AWS EKS** or on-prem K8s |
| CI/CD   | GitHub Actions → ECS task | Same pipeline + Helm + Argo CD |
| **App URL** | <https://ecs-hello-world.alekspetkov.com> | <https://hello-world.alekspetkov.com> |
| **GitOps UI** | — | Argo CD: <https://argo.alekspetkov.com> (credentials on request) |
| Ingress | **Application Load Balancer** (ALB) | Same ALB† (AWS EKS path) or new ingress controller (on-prem) |

† The ALB already fronts ECS; with AWS Load Balancer Controller we attach EKS Pods via **TargetGroupBinding** so both back-ends share one listener.

---

## 3 Migration Strategies

### 3.1 Planned Downtime  
1. Schedule a maintenance window.  
2. **Migrate shared services first** (DB, Redis, object storage, secrets).  
3. Deploy the app on AWS EKS/on-prem; run smoke tests.  
4. Switch DNS 100 % to Kubernetes (or repoint ALB); shut down ECS tasks.

### 3.2 Zero-Downtime (DNS Weighted)  
1. Ensure all stateful components are **reachable from both ECS and Kubernetes**.  
2. Deploy identical image/version to both platforms.  
3. Route 53 weighted record: start 95 % ECS / 5 % K8s; ramp K8s weight up.  
4. Monitor SLOs; roll back if needed.  
5. Shift 100 % to Kubernetes; delete ECS service.

### 3.3 Zero-Downtime (Shared ALB Weighted) — *ECS → AWS EKS*  
1. ECS service already registered in **ALB Target Group A**.  
2. Install **AWS Load Balancer Controller** in AWS EKS.  
3. Add a `TargetGroupBinding` resource: Pods register into **Target Group B** on the *same* ALB listener.  
4. Adjust **listener rule weights** (e.g., 95 % A / 5 % B) with the AWS Console, CLI, or IaC.  
5. Ramp weight toward B (Kubernetes) while observing CloudWatch dashboards.  
6. Shift to 100 % Target Group B; destroy ECS service and Target Group A.

> **Real-World Migration Disclaimer**  
> Zero-downtime paths work **only if users can hit either backend without losing state**.  
> • Sessions, caches, and databases must be shared and reachable from both clusters.  
> • No sticky sessions, in-memory state, or node-local WebSocket affinity.  
> • Health checks must remove unhealthy targets automatically.  
> • For DNS weighting: keep TTL ≤ 60 s. For ALB weighting: ensure listener health checks and fast rollback automation.

---

## 4 Detailed Migration Workflow

| # | Step | Key Actions |
|---|------|-------------|
|1|**Discovery**|Export ECS task def, env vars, secrets, IAM caps, network mode.|
|2|**Prepare Registry**|Create (or reuse) ECR/private registry accessible by both platforms.|
|3|**Provision Cluster**|AWS EKS via Terraform;<br>on-prem: Minikube or prod K8s + automation script/Ansible.|
|4|**Install Add-ons**|Helm, Argo CD, Metrics Server; <br>Ingress: existing ALB + AWS Load Balancer Controller (AWS EKS) or NGINX/Traefik (on-prem).|
|5|**Translate Manifests**|Build Helm chart `helm/hello-world/` with overlays (`values.eks.yaml`, `values.onprem.yaml`).|
|6|**Build & Push Image**|GitHub Actions: dotnet publish → docker build → docker push.|
|7|**Wire GitOps**|Create Argo CD *Application* pointing at the Helm chart and cluster.|

*(steps 8-14 unchanged; omitted here for brevity—see previous version)*

---

## 5 Live Demo — How to Trigger & Observe

1. **Edit the App** (hello-world string in `Program.cs`), commit & push.  
2. **Pipeline** builds → pushes → updates ECS and/or Helm.  
3. **Watch Endpoints**  
   * ECS: <https://ecs-hello-world.alekspetkov.com>  
   * AWS EKS/on-prem: <https://hello-world.alekspetkov.com>  
   * New greeting appears on both.  
4. **Observe in Argo CD** (`hello-world` card turns *Synced*).  
5. **Traffic Shift**  
   * **DNS path**: adjust Route 53 weights.  
   * **ALB path** (AWS EKS): edit ALB listener rule weights between Target Group A (ECS) and B (EKS).

---

## 6 CI/CD Controls

| Variable      | Effect                                               |
| ------------- | ---------------------------------------------------- |
| `DEPLOY_ECS`  | `true/false` — push image & update ECS service       |
| `UPDATE_HELM` | `true/false` — commit chart version & Argo CD sync   |

Toggle in repo settings—no pipeline edits required.

---

## 7 Why Terraform, Helm, and Argo CD? — With vs. Without

| Tool      | Using the Tool (recommended) | Without the Tool (manual approach) |
|-----------|-----------------------------|------------------------------------|
| **Terraform** | *Idempotent*, version-controlled AWS EKS provisioning; diff/plan; reusable modules. | Imperative `eksctl` or console clicks; drift; no review history; hard to replicate. |
| **Helm**  | Parameterized, versioned charts; `helm rollback`; DRY YAML; per-env overrides. | Raw manifests; copy-paste divergence; manual edits; rollback via Git + `kubectl`. |
| **Argo CD** | GitOps reconciliation; drift detection; multi-cluster sync; visual UI. | `kubectl apply` in CI; state drifts outside Git; rollbacks need manual commands. |

---

## 8 ECS vs. AWS EKS/Kubernetes Comparison

| Feature            | ECS                                    | AWS EKS / On-Prem K8s               |
|--------------------|----------------------------------------|-------------------------------------|
| **Platform**       | AWS only                               | Cloud-agnostic (AWS EKS or on-prem) |
| **Flexibility**    | AWS-managed, limited customization     | Fully extensible open-source stack  |
| **Portability**    | Tightly coupled to AWS services        | Migrate across clouds/on-prem easily|
| **Community**      | AWS ecosystem                          | Large open-source community         |
| **Migration Impact**| Re-platform required for portability   | Same workloads anywhere K8s runs    |

---

## 9 Included in PoC
* GitHub Actions workflows (build, ECS deploy, Helm package).  
* Helm chart (`helm/hello-world/`).  
* Structurizr DSL diagrams → rendered in `docs/diagrams/`.  
* Minimal ASP.NET Core **hello-world** service.

---

## 10 Out of Scope (Prod Hardening)

* Automated cluster creation  
* Centralized logging/metrics (Prometheus, Loki, CloudWatch)  
* Secrets encryption (KMS, Sealed Secrets, Vault)  
* Autoscaling, network policies, PodDisruptionBudgets  
* DR, cross-region standby, backup plans

---

## 11 Demo & Prerequisites Checklist

- [ ] Kubernetes cluster + Helm + Argo CD installed  
- [ ] GitHub Actions pushes image to registry  
- [ ] Helm chart deploys via Argo CD with correct values file  
- [ ] `DEPLOY_ECS` / `UPDATE_HELM` toggles verified  
- [ ] Weighted DNS (for zero-downtime) configured and tested  
- [ ] Rollback validated (shift DNS back or redeploy previous chart)  
- [ ] Logs & metrics visible for both clusters  
- [ ] Argo CD UI reachable with read-only RBAC for stakeholders  

---

## 12 Summary

This PoC walks through migrating an ECS workload to Kubernetes using **planned downtime** or **zero-downtime** (weighted DNS). Harden IaC, security, observability, and stateful components before production rollout.

---

*Contributions welcome — open a PR with improvements or questions.*
