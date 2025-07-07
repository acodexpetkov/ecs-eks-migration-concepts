# ECS → EKS / Kubernetes (On-Prem) Migration — Proof of Concept

## 1 Purpose
Demonstrate two migration patterns—**planned downtime** and **zero-downtime**—for moving a simple **hello-world** service from **AWS ECS** to **Kubernetes** (AWS EKS or an on-prem cluster such as Minikube).  
This PoC shows architecture, pipelines, and traffic-cutover techniques. It is **not** production-ready as-is.

---

## 2 Current vs. Target

| Layer            | Today (ECS)                        | Target (Kubernetes)                          |
| ---------------- | ---------------------------------- | -------------------------------------------- |
| Runtime          | ECS                                 | EKS or on-prem                                |
| CI/CD            | GitHub Actions → ECS task          | Same pipeline + Helm + Argo CD                |
| App URL          | `https://ecs.example.com`          | `https://k8s.example.com`                     |
| GitOps           | —                                  | Argo CD UI: `https://argo.example.com`        |

---

## 3 Migration Strategies

### 3.1 Planned Downtime
1. Schedule maintenance window.  
2. **Migrate shared services first** (DB, Redis, object storage, secrets).  
3. Deploy app on Kubernetes; run smoke tests.  
4. Switch DNS 100 % to Kubernetes; shut down ECS tasks.

### 3.2 Zero-Downtime (Weighted DNS)
1. Ensure all stateful components are **reachable from both ECS and K8s**.  
2. Deploy identical image/version to both platforms.  
3. Route 53 weighted records: start 95 % ECS / 5 % K8s; ramp K8s weight up.  
4. Monitor metrics & logs; roll back if SLOs degrade.  
5. Shift 100 % to K8s; delete ECS service.

> **Warning** Zero-downtime only works when the app is stateless or uses shared state (no sticky sessions).

---

## 4 Detailed Migration Workflow

| # | Step | Key Actions |
|---|------|-------------|
|1|**Discovery**|Export ECS task def, env vars, secrets, IAM caps, network mode.|
|2|**Prepare Registry**|Create (or reuse) ECR/private registry accessible by both platforms.|
|3|**Provision Cluster**|EKS via Terraform;<br>On-prem: Minikube or prod K8s + automation script/Ansible.|
|4|**Install Add-ons**|Helm, Argo CD, Metrics Server, Ingress Controller (ALB, NGINX, Traefik).|
|5|**Translate Manifests**|Build Helm chart `helm/hello-world/` with overlays (`values.eks.yaml`, `values.onprem.yaml`).|
|6|**Build & Push Image**|GitHub Actions: dotnet publish → docker build → docker push.|
|7|**Wire GitOps**|Create Argo CD `Application` pointing at the Helm chart and cluster.|
|8|**Load / Perf Test**|k6 scripts (`tests/`) simulate target TPS; capture baseline metrics.|
|9|**Choose Path**|Pick Planned-Downtime or Zero-Downtime (see §3).|
|10a|**Planned-Downtime Execution**|Freeze traffic → migrate services → deploy → validate → DNS cutover.|
|10b|**Zero-Downtime Execution**|Deploy in parallel → ramp DNS weight → observe SLOs → full cutover.|
|11|**Post-Cut Validation**|Functional checks, load-test replay, error-budget review.|
|12|**Decommission ECS**|Delete ECS service, task def, alarms, unused IAM roles.|
|13|**Cleanup & Docs**|Update runbooks, diagrams, architecture docs.|
|14|**Handoff**|Knowledge transfer to Ops/SRE; define rollback & DR drills.|

---

## 5 CI/CD Controls

| Variable      | Effect                                               |
| ------------- | ---------------------------------------------------- |
| `DEPLOY_ECS`  | `true/false` — push image & update ECS service       |
| `UPDATE_HELM` | `true/false` — commit chart version & Argo CD sync   |

No pipeline edits are needed; toggle these env vars in repo settings.

---

## 6 Why Terraform, Helm, and Argo CD? — With vs. Without

| Tool      | Using the Tool (recommended) | Without the Tool (manual approach) |
|-----------|-----------------------------|------------------------------------|
| **Terraform** | *Idempotent*, version-controlled EKS provisioning; diff/plan before apply; reusable modules. | Imperative `eksctl` or console clicks; prone to drift; no reviewable history; harder to replicate. |
| **Helm**  | Parameterized, versioned charts; `helm rollback`; DRY YAML; per-env overrides. | Raw manifests; copy-paste divergence; manual edits across files; rollback via Git and `kubectl`. |
| **Argo CD** | GitOps reconciliation; drift detection; visual UI; multi-cluster sync. | `kubectl apply` in CI; state mutates outside Git; drift unnoticed; rollbacks require manual commands. |

---

## 7 ECS vs. EKS/Kubernetes Comparison

| Feature            | ECS                                    | EKS/K8s/Minikube                     |
|--------------------|----------------------------------------|--------------------------------------|
| **Platform**       | AWS only                               | Cloud-agnostic (AWS or on-prem)      |
| **Flexibility**    | AWS-managed, limited customization     | Fully extensible open-source stack   |
| **Portability**    | Tightly coupled to AWS services        | Migrate easily across clouds/on-prem |
| **Community**      | AWS ecosystem                          | Large open-source community          |
| **Migration Impact**| Re-platforming required for portability| Same workloads anywhere Kubernetes runs |

---

## 8 Included in PoC
* GitHub Actions workflows (build, ECS deploy, Helm package).  
* Helm chart (`helm/hello-world/`).  
* Structurizr DSL diagrams → rendered in `docs/diagrams/`.  
* Minimal ASP.NET Core “hello-world” service with env-var support.

---

## 9 Out of Scope (Prod Hardening)

* Automated cluster creation  
* Centralized logging/metrics (Prometheus, Loki, CloudWatch)  
* Secrets encryption (KMS, Sealed Secrets, Vault)  
* Autoscaling, network policies, PodDisruptionBudgets  
* DR, cross-region standby, backup plans

---

## 10 Demo & Prerequisites Checklist

- [ ] Kubernetes cluster + Helm + Argo CD installed  
- [ ] GitHub Actions pushes image to registry  
- [ ] Helm chart deploys via Argo CD with correct values file  
- [ ] `DEPLOY_ECS` / `UPDATE_HELM` toggles verified  
- [ ] Weighted DNS (for zero-downtime) configured and tested  
- [ ] Rollback validated (shift DNS back or redeploy previous chart)  
- [ ] Logs & metrics visible for both clusters  
- [ ] Argo CD UI reachable with read-only RBAC for stakeholders  

---

## 11 Summary

This PoC gives a step-by-step path to move an ECS workload to Kubernetes via **planned downtime** (maintenance window) or **zero-downtime** (weighted DNS). Harden IaC, security, observability, and stateful components before production rollout.

---

*Contributions welcome — open a PR with improvements or questions.*
