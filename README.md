# ECS → EKS / Kubernetes (On-Prem) Migration — Proof of Concept

## 1 Purpose  
Demonstrate two migration patterns—**planned downtime** and **zero-downtime**—for moving a simple **hello-world** service from **AWS ECS** to **Kubernetes** (AWS EKS or an on-prem cluster such as Minikube).  
This PoC shows architecture, pipelines, and traffic-cut-over techniques. It is **not** production-ready as-is.

---

## 2 Current vs. Target

| Layer   | Today (ECS) | Target (Kubernetes) |
|---------|-------------|---------------------|
| Runtime | ECS | EKS or on-prem |
| CI/CD   | GitHub Actions → ECS task | Same pipeline + Helm + Argo CD |
| **App URL** | <https://ecs-hello-world.alekspetkov.com> | <https://hello-world.alekspetkov.com> |
| **GitOps UI** | — | Argo CD: <https://argo.alekspetkov.com> (credentials on request) |

---

## 3 Migration Strategies

### 3.1 Planned Downtime  
1. Schedule a maintenance window.  
2. **Migrate shared services first** (DB, Redis, object storage, secrets).  
3. Deploy the app on Kubernetes; run smoke tests.  
4. Switch DNS 100 % to Kubernetes; shut down ECS tasks.

### 3.2 Zero-Downtime (Weighted DNS)  
1. Ensure all stateful components are **reachable from both ECS and K8s**.  
2. Deploy identical image/version to both platforms.  
3. Route 53 weighted records: start 95 % ECS / 5 % K8s; ramp K8s weight up.  
4. Monitor metrics & logs; roll back if SLOs degrade.  
5. Shift 100 % to K8s; delete ECS service.

> **Real-World Migration Disclaimer**  
> Zero-downtime cut-overs work **only if users can hit either backend without losing state**.  
> • Sessions, caches, and databases must be shared and reachable from both clusters.  
> • No sticky sessions, in-memory state, or node-local WebSocket affinity.  
> • Health checks must remove unhealthy targets automatically.  
> • Keep DNS TTL ≤ 60 s to enable fast traffic shifts or rollbacks.

---

## 4 Detailed Migration Workflow

| # | Step | Key Actions |
|---|------|-------------|
|1|**Discovery**|Export ECS task def, env vars, secrets, IAM caps, network mode.|
|2|**Prepare Registry**|Create (or reuse) ECR/private registry accessible by both platforms.|
|3|**Provision Cluster**|EKS via Terraform; on-prem: Minikube or prod K8s + automation script/Ansible.|
|4|**Install Add-ons**|Helm, Argo CD, Metrics Server, Ingress Controller (ALB, NGINX, Traefik).|
|5|**Translate Manifests**|Build Helm chart `helm/hello-world/` with overlays (`values.eks.yaml`, `values.onprem.yaml`).|
|6|**Build & Push Image**|GitHub Actions: dotnet publish → docker build → docker push.|
|7|**Wire GitOps**|Create Argo CD *Application* pointing at the Helm chart and cluster.|
|8|**Load / Perf Test**|k6 scripts simulate target TPS; capture baseline metrics.|
|9|**Choose Path**|Pick Planned-Downtime or Zero-Downtime (see §3).|
|10a|**Planned-Downtime Execution**|Freeze traffic → migrate services → deploy → validate → DNS cut-over.|
|10b|**Zero-Downtime Execution**|Deploy in parallel → ramp DNS weight → observe SLOs → full cut-over.|
|11|**Post-Cut Validation**|Functional checks, load-test replay, error-budget review.|
|12|**Decommission ECS**|Delete ECS service, task def, alarms, unused IAM roles.|
|13|**Cleanup & Docs**|Update runbooks, diagrams, architecture docs.|
|14|**Handoff**|Knowledge transfer to Ops/SRE; define rollback & DR drills.|

---

## 5 Live Demo — How to Trigger & Observe

1. **Edit the App**  
   *Change a string in `Program.cs` (e.g., greeting text). Commit & push to `main`.*

2. **Pipeline Runs Automatically**  
   * GitHub Actions builds the container, tags it, pushes to ECR.  
   * If `DEPLOY_ECS=true`, the ECS service is updated.  
   * If `UPDATE_HELM=true`, the Helm chart is version-bumped; Argo CD detects the change and syncs to Kubernetes.*

3. **Watch Parallel Deployments**  
   * **ECS endpoint:** <https://ecs-hello-world.alekspetkov.com>  
   * **K8s endpoint:** <https://hello-world.alekspetkov.com>  
   Open both pages—after the pipeline finishes you should see the new greeting in **both** environments.

4. **Monitor in Argo CD**  
   * Open <https://argo.alekspetkov.com> and log in.  
   * The `hello-world` application card turns from *OutOfSync* → *Synced* once the new chart is deployed.  
   * Pod status and container image tag are visible in the UI.

5. **Weighted DNS Switch (Zero-Downtime path)**  
   * In Route 53, adjust the weight on the `hello-world` record set (e.g., 50/50).  
   * Use a browser or `curl` loop to confirm some responses come from each backend.  
   * Increase to 100 % K8s once metrics are good; rollback by lowering the weight if errors appear.

---

## 6 CI/CD Controls

| Variable      | Effect                                               |
| ------------- | ---------------------------------------------------- |
| `DEPLOY_ECS`  | `true/false` — push image & update ECS service       |
| `UPDATE_HELM` | `true/false` — commit chart version & Argo CD sync   |

Toggle these in repo settings—no pipeline edits required.

---

## 7 Why Terraform, Helm, and Argo CD? — With vs. Without

| Tool      | Using the Tool (recommended) | Without the Tool (manual approach) |
|-----------|-----------------------------|------------------------------------|
| **Terraform** | *Idempotent*, version-controlled EKS provisioning; diff/plan; reusable modules. | Imperative `eksctl` or console clicks; drift; no reviewable history; hard to replicate. |
| **Helm**  | Parameterized, versioned charts; `helm rollback`; DRY YAML; per-env overrides. | Raw manifests; copy-paste divergence; manual edits; rollback via Git + `kubectl`. |
| **Argo CD** | GitOps reconciliation; drift detection; multi-cluster sync; visual UI. | `kubectl apply` in CI; state drifts outside Git; rollbacks need manual commands. |

---

## 8 ECS vs. EKS/Kubernetes Comparison

| Feature            | ECS                                    | EKS/K8s/Minikube                     |
|--------------------|----------------------------------------|--------------------------------------|
| **Platform**       | AWS only                               | Cloud-agnostic (AWS or on-prem)      |
| **Flexibility**    | AWS-managed, limited customization     | Fully extensible open-source stack   |
| **Portability**    | Tightly coupled to AWS services        | Migrate across clouds/on-prem easily |
| **Community**      | AWS ecosystem                          | Large open-source community          |
| **Migration Impact**| Re-platforming required for portability| Same workloads anywhere K8s runs     |

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
