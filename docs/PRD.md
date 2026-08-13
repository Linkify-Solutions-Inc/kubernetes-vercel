# System Requirements Specification (SRD/PRD)
## Mini-PaaS Learning Platform on Amazon EKS

| Field | Value |
|---|---|
| Document No. | LK-MP-PRD-001 |
| Revision | A |
| Date | 2026-08-12 |
| Document type | System Requirements Specification (serves as Product Requirements Document) |
| Standard basis | MIL-STD-498 System/Subsystem Specification (SSS/SyRS) family, cross-fertilized with IEEE Std 830-1998 |
| Classification | UNCLASSIFIED — internal exercise |
| Prepared for | Project Owner |

---

## 1. SCOPE

### 1.1 Identification

1.1.1 This document specifies the requirements for the **Mini-PaaS Learning Platform**, a self-hosted, Vercel/Render-like deployment platform built on Amazon EKS, constructed as a hands-on exercise in DevOps, Kubernetes, and AWS.

1.1.2 The system is an exercise artifact, not a production service. It is designed to operate for approximately thirty (30) days and then be destroyed completely.

### 1.2 System Overview

1.2.1 **Purpose.** The system shall demonstrate (a) how a modern deployment platform is assembled from AWS and Kubernetes primitives, and (b) how the components connect end to end. Capability is a means to demonstrating the architecture; it is not an end in itself.

1.2.2 **System context.** The system consists of:
   - a single Amazon EKS cluster provisioned entirely by Terraform/OpenTofu;
   - a CI/CD pipeline on GitHub Actions, authenticating to AWS via GitHub OIDC (no static credentials);
   - a GitOps delivery layer (ArgoCD) that is the actual "deployment engine";
   - a catalog of five demo applications that stand in for platform tenants;
   - per-tenant isolation (namespace, quota, limits, network policy);
   - pod-level autoscaling (HPA) and node-level autoscaling (Karpenter);
   - observability (Prometheus + Grafana).

1.2.3 **Operational scenario (solo player).** The platform must function correctly with zero external users. The operator is the sole tenant via the demo catalog. "Deploying an app" means: push code → pipeline builds → ArgoCD reconciles → a new namespace and live URL appear.

1.2.4 **System lifetime.** The system shall be brought up, exercised, and fully destroyed within approximately thirty (30) days. Teardown is a first-class requirement (see REQ-3.10), not a cleanup afterthought.

### 1.3 Document Overview

1.3.1 **Scope of this document.** This document states the *requirements* for the system and the *qualifying conditions* used to verify each requirement is met. It intentionally does not phase work into weeks or milestones; sequencing is owned by the companion documentation (see Appendix A).

1.3.2 **How to read requirements.** Each requirement in Section 3 is stated in the imperative ("shall"), carries a project-unique identifier (`REQ-<sec>.<sub>-<n>`), a **Priority** (P1 = must, P2 = should, P3 = nice-to-have), a **Rationale** (the design intent it serves), and a **Qualification** (how conformance is demonstrated). All P1 requirements must be satisfied for the end-to-end success demonstration (Appendix D) to pass.

1.3.3 **Document organization.** Section 2 lists references; Section 3 states system requirements by functional area; Sections 4–5 define internal and external interfaces; Sections 6–9 state security, resource, quality, and design constraints; Sections 10–12 cover components, precedence, and qualifying conditions; Section 13 records notes, assumptions, and risks; Appendices A–D provide traceability, catalog detail, the pitfall register, and the end-to-end demonstration.

---

## 2. REFERENCED DOCUMENTS

The following documents are referenced by this specification. The system shall conform to the cited tooling and standards; version-specific guidance is captured in the companion Setup documentation.

- MIL-STD-498, *Software Development and Documentation* (requirements-specification family structure)
- IEEE Std 830-1998, *IEEE Recommended Practice for Software Requirements Specifications*
- Terraform / OpenTofu documentation (AWS provider, `terraform-aws-eks` module, S3/DynamoDB state backend)
- Amazon EKS, VPC, ECR, IAM (IRSA), and AWS Load Balancer Controller documentation
- ArgoCD documentation (App-of-Apps, sync/self-heal/prune)
- Karpenter documentation (provisioner, node pools, consolidation)
- GitHub Actions + OIDC documentation
- Prometheus Operator / kube-prometheus-stack (Helm chart)
- Docker / OCI image building best practices

---

## 3. SYSTEM REQUIREMENTS

### 3.1 Cluster Provisioning (IaC)

**REQ-3.1-1 (P1) Sole IaC tool.** The system shall provision all AWS infrastructure using Terraform/OpenTofu as the sole infrastructure-as-code tool, with a remote state backend (S3 bucket + DynamoDB table for locking).
- *Rationale:* Establishes the state → plan → apply model and ensures no click-ops anywhere.
- *Qualification:* Inspection of the `infra/` repository; a clean `terraform plan` lists the full resource set; a second operator reproduces the cluster from the same repository.

**REQ-3.1-2 (P1) Network topology.** The system shall create a VPC in one region (default us-east-1) with public and private subnets, NAT for egress, and an EKS cluster whose worker nodes run in private subnets.
- *Rationale:* Ensures correct AWS networking: private worker nodes with NAT egress.
- *Qualification:* Inspection of VPC/subnet layout; worker nodes have no public IPs.

**REQ-3.1-3 (P1) Cluster bootstrap.** The system shall create the EKS cluster using the `terraform-aws-eks` module, and shall use Karpenter as the node-provisioning mechanism (a minimal managed node group is permitted only as a bootstrap seed).
- *Rationale:* Uses the battle-tested module and establishes real cluster autoscaling from day one.
- *Qualification:* `kubectl get nodes` shows ready nodes; Karpenter is the provisioner that adds nodes under load (REQ-3.7).

**REQ-3.1-4 (P1) Pod identity.** The system shall grant all pod-level AWS access via IRSA (IAM Roles for Service Accounts); no long-lived AWS access keys shall exist inside the cluster.
- *Rationale:* This is the anti-pattern that derailed the preceding streaming project at its deploy step; making IAM declarative is the fix.
- *Qualification:* A test pod assumes its role without keys; inspection shows no secrets containing access keys.

**REQ-3.1-5 (P1) Image registry.** The system shall provide private ECR repositories for the five demo application images.
- *Rationale:* Establishes registry-based image distribution and pull-through auth.
- *Qualification:* `docker pull` of a tagged image from a cluster node succeeds.

**REQ-3.1-6 (P1) Ingress controller.** The system shall install the AWS Load Balancer Controller to provide ingress capability.
- *Rationale:* ALB-based ingress is the standard AWS-native routing path.
- *Qualification:* Ingress resources create a working ALB (REQ-3.6).

**REQ-3.1-7 (P1) Bootstrap time.** From a clean laptop with only the documented prerequisites installed, a documented sequence shall bring the cluster to a ready state in under sixty (60) minutes with no manual AWS-console or IAM steps.
- *Rationale:* Low-friction bootstrap is a design principle; the preceding streaming project failed this and it must not recur.
- *Qualification:* Timed run following the Setup documentation.

### 3.2 CI/CD Pipeline

**REQ-3.2-1 (P1) CI authentication.** The system shall authenticate GitHub Actions to AWS using GitHub OIDC; no static AWS credentials shall be stored in the repository or its secrets.
- *Rationale:* Modern standard; also eliminates the credential-handling failure mode.
- *Qualification:* Inspection of the workflow and OIDC provider; a job assumes the role without stored keys.

**REQ-3.2-2 (P1) Pipeline flow.** On a push to a demo app, the pipeline shall: build the image → run a minimal automated check → push the image to ECR tagged immutably with the commit SHA → update the application manifest in the `gitops/` repository → push. ArgoCD shall perform the actual deployment.
- *Rationale:* This is the industry-standard CI → GitOps flow.
- *Qualification:* A pushed change produces a new immutable image tag and a manifest update.

**REQ-3.2-3 (P1) End-to-end deploy.** A change to any demo app shall become live at its URL with no manual steps between commit and rollout.
- *Rationale:* A push-to-deploy path is the platform's core behavior.
- *Qualification:* End-to-end run per Appendix D.

**REQ-3.2-4 (P2) Diagnosable failures.** Pipeline output shall be human-readable with clear pass/fail states such that an operator can diagnose a failure without external help.
- *Rationale:* Prevents the "an assistant debugged it" failure mode of the prior project.
- *Qualification:* A deliberately broken build produces a log an operator can read and fix alone.

### 3.3 GitOps Deployment

**REQ-3.3-1 (P1) GitOps controller.** The system shall deploy ArgoCD using the App-of-Apps pattern, with the `gitops/` repository as the single source of truth for cluster workloads.
- *Rationale:* GitOps *is* the deployment engine; keeps the "backend" of the platform to near zero.
- *Qualification:* All workloads trace to manifests in `gitops/`.

**REQ-3.3-2 (P1) Application definition.** Each demo app shall be defined as an ArgoCD Application covering namespace, quota, limits, deployment, service, ingress, and HPA.
- *Rationale:* One declarative definition per tenant is the platform's core abstraction.
- *Qualification:* Inspection of `gitops/`; each app appears as a healthy ArgoCD Application.

**REQ-3.3-3 (P1) Reconciliation.** The system shall use automated sync with self-heal and prune enabled, and auto-create namespaces.
- *Rationale:* Establishes declarative reconciliation in place of imperative kubectl.
- *Qualification:* Deleting a pod results in recreation; deleting a deployment results in restoration.

**REQ-3.3-4 (P1) Self-heal demonstration.** Manually deleting a running pod, and separately deleting an entire deployment, shall both result in automatic restoration by ArgoCD.
- *Rationale:* The controller loop must be observable in practice, not only in documentation.
- *Qualification:* Performed by the operator and observed in ArgoCD and `kubectl get pods`.

**REQ-3.3-5 (P1) GitOps rollback.** Reverting a bad image commit and syncing shall restore the previous healthy version.
- *Rationale:* Git is the undo button; rollback is a core operational skill.
- *Qualification:* Rollback exercise per REQ-3.9.

### 3.4 Multi-Tenancy and Isolation

**REQ-3.4-1 (P1) Per-tenant namespace.** Each demo app shall run in its own namespace named `app-<name>`.
- *Rationale:* Namespaces are the platform's tenancy boundary.
- *Qualification:* `kubectl get ns` shows five `app-*` namespaces.

**REQ-3.4-2 (P1) Resource bounds.** Each namespace shall be enforced with a ResourceQuota and a LimitRange.
- *Rationale:* Quota is the platform control that bounds tenant consumption.
- *Qualification:* A workload exceeding quota is rejected (REQ-3.4-4).

**REQ-3.4-3 (P1) Network isolation.** Each namespace shall be enforced with a NetworkPolicy (default-deny, allow same-namespace, allow ingress).
- *Rationale:* Isolation is the platform team's core responsibility.
- *Qualification:* Cross-tenant traffic is blocked (REQ-3.4-5).

**REQ-3.4-4 (P2) Quota rejection observed.** A workload that exceeds its namespace quota shall be rejected, and the cause shall be diagnosable by reading events, not logs.
- *Rationale:* Events-based diagnosis is a recurring production skill.
- *Qualification:* Operator performs the rejection and explains the event.

**REQ-3.4-5 (P2) Cross-tenant block.** Traffic from one tenant namespace to another tenant's pod shall be blocked by policy.
- *Rationale:* Proves the policy layer actually enforces isolation.
- *Qualification:* A curl from namespace A to a pod in namespace B times out.

### 3.5 Demo Application Catalog

**REQ-3.5-1 (P1) Five applications.** The system shall provide exactly five demo applications, all runnable concurrently: a Node/TypeScript API, a Node/TypeScript static site, a Node/TypeScript worker, a Python (FastAPI) API, and a Go API.
- *Rationale:* The catalog is the "solo player mode" — workloads that stand in for real tenants and prove the platform works without users.
- *Qualification:* All five healthy at their URLs simultaneously (Appendix D).

**REQ-3.5-2 (P1) Container hygiene.** Each application shall ship a Dockerfile, declared container resource requests/limits, and liveness/readiness probes.
- *Rationale:* Container correctness is a prerequisite for autoscaling to behave.
- *Qualification:* Inspection; probes pass; requests/limits present.

**REQ-3.5-3 (P1) Routing.** Each application shall be reachable at a distinct subdomain under the ingress domain.
- *Rationale:* Host-based routing is how platforms isolate tenants at the network edge.
- *Qualification:* Five distinct URLs respond (REQ-3.6).

**REQ-3.5-4 (P1) Load endpoint.** The Node/TS API shall expose a CPU-intensive endpoint (e.g., `GET /work?ms=<N>`) suitable for driving sustained CPU load.
- *Rationale:* Required to trigger HPA for the scaling demonstration.
- *Qualification:* The endpoint raises container CPU measurably (REQ-3.7).

**REQ-3.5-5 (P1) Load generator.** The system shall include a load generator (an in-cluster Job) able to direct sustained load at a target application.
- *Rationale:* Scaling must be provable and repeatable from inside the cluster.
- *Qualification:* The load generator drives the CPU endpoint for a sustained window.

**REQ-3.5-6 (P3) Worker shape.** At least one application (the worker) shall demonstrate a background/processing shape with scale-to-N behavior, distinct from request serving.
- *Rationale:* Workers scale by queue depth, not HTTP; a distinct, realistic pattern.
- *Qualification:* The worker runs at a configured replica count independently of web load.

### 3.6 Ingress, DNS, and TLS

**REQ-3.6-1 (P1) Host-based routing.** The system shall route traffic by hostname through the ALB ingress controller to the five application services.
- *Rationale:* Host-based Ingress is the standard multi-app routing mechanism.
- *Qualification:* Five host rules present and functional.

**REQ-3.6-2 (P1) Wildcard DNS.** The system shall use wildcard DNS resolving to the ALB address by default (nip.io/sslip.io), with an optional real domain documented for when one is available.
- *Rationale:* A real domain is not assumed; free wildcard DNS keeps the project self-contained.
- *Qualification:* `nslookup app.<domain>` resolves to the ALB.

**REQ-3.6-3 (P2) TLS.** The system shall provide TLS via cert-manager and Let's Encrypt when a real domain is in use; self-signed/HTTP is acceptable when using nip.io/sslip.io.
- *Rationale:* TLS matters in production but is not a blocker for the exercise.
- *Qualification:* HTTPS works under a real domain; otherwise documented as out of scope for the exercise.

**REQ-3.6-4 (P1) Routing verified.** All five subdomains shall resolve and serve their applications.
- *Rationale:* The "whole stack works" outcome depends on this.
- *Qualification:* `curl` of all five URLs returns the expected application response.

### 3.7 Autoscaling

**REQ-3.7-1 (P1) Pod scaling.** Each compute application shall be governed by an HPA targeting 50% CPU.
- *Rationale:* HPA is the canonical pod-level autoscaler.
- *Qualification:* `kubectl get hpa` shows all five; target percentages set.

**REQ-3.7-2 (P1) Node scaling.** Karpenter shall provision and remove nodes in response to pending pods.
- *Rationale:* Pod scaling alone is insufficient; the cluster must also grow.
- *Qualification:* Under load, node count increases; after load, it consolidates.

**REQ-3.7-3 (P1) Scale-up observed.** Under sustained load, the replica count shall increase (HPA) and new nodes shall appear (Karpenter), visible on Grafana in real time.
- *Rationale:* This is the core proof that the platform's scaling ability works.
- *Qualification:* Operator drives load, watches replica count rise, watches new nodes appear, on dashboards.

**REQ-3.7-4 (P1) Scale-down observed.** After load stops, replicas and nodes shall scale back down.
- *Rationale:* Downscaling is equally important and equally rarely demonstrated.
- *Qualification:* Replica count and node count return to baseline within a documented window.

**REQ-3.7-5 (P2) Metrics-backed reasoning.** Scaling behavior shall be explainable from metrics, so an operator can reason about *why* it happened rather than accept it on faith.
- *Rationale:* Metrics are required to reason about scaling rather than only observe it.
- *Qualification:* Operator explains a scale event citing HPA/CPU/node metrics.

### 3.8 Observability

**REQ-3.8-1 (P1) Metrics stack.** The system shall deploy Prometheus and Grafana via the kube-prometheus-stack Helm chart, including node exporters and kube-state-metrics.
- *Rationale:* Standard, low-effort way to stand up the industry observability baseline.
- *Qualification:* Stack healthy; targets being scraped.

**REQ-3.8-2 (P1) Dashboards.** The system shall provide Grafana dashboards for cluster nodes, pod CPU/memory, HPA behavior, and Karpenter activity.
- *Rationale:* Dashboards make scaling and health visible.
- *Qualification:* Each dashboard renders live data during the load test.

**REQ-3.8-3 (P1) Operator access.** The operator shall be able to access Grafana (via ingress with basic auth, or a documented port-forward) and correlate load with scaling behavior.
- *Rationale:* Access without friction; port-forward is itself a useful pattern.
- *Qualification:* Operator opens Grafana and observes the load-test correlation.

**REQ-3.8-4 (P2) Minimal alerts.** The system shall configure at least two simple Prometheus alerts (e.g., node down, pending pods) to exercise alerting concepts.
- *Rationale:* Alerting is part of the operating loop and is cheap to add.
- *Qualification:* Alerts defined and testable by firing one.

### 3.9 Rollback and Recovery

**REQ-3.9-1 (P1) Documented rollback.** The system shall provide a documented rollback procedure: revert the image change in git → push → ArgoCD sync → verify healthy.
- *Rationale:* Rollback is the operational skill that separates demos from operations.
- *Qualification:* Procedure exists in the Operations documentation; executed successfully.

**REQ-3.9-2 (P1) Broken-release exercise.** An operator shall deliberately introduce a broken image, observe the failure, roll back via GitOps, and verify recovery.
- *Rationale:* Controlled failure is the highest-value exercise in the project.
- *Qualification:* Appendix D step; recovery observed.

**REQ-3.9-3 (P1) Recovery time.** Recovery to a healthy state shall complete within ten (10) minutes of initiating rollback.
- *Rationale:* Bounds the exercise so it is instructive, not exhausting.
- *Qualification:* Timed run.

### 3.10 Teardown and Cost Hygiene

**REQ-3.10-1 (P1) Documented teardown.** The system shall provide a documented teardown procedure: disable/uninstall ArgoCD (so it cannot fight the destroy), remove workloads, then `terraform destroy`.
- *Rationale:* Ordering matters; an auto-syncing ArgoCD during `terraform destroy` is a known trap.
- *Qualification:* Procedure exists; followed cleanly.

**REQ-3.10-2 (P1) Post-teardown verification.** After teardown, no billable AWS resources shall remain, and the AWS bill impact shall return to baseline.
- *Rationale:* The exercise ends with a clean slate; verification prevents surprise bills.
- *Qualification:* Cloud console/CLI shows zero resources; cost dashboard at baseline.

**REQ-3.10-3 (P1) Cost ceiling.** The system's monthly cost shall not exceed $180/month, with a budget alarm configured and spot-instance usage documented as an option.
- *Rationale:* Bounded cost makes the exercise repeatable and the operator free to experiment.
- *Qualification:* Budget alarm active; cost projections documented.

**REQ-3.10-4 (P2) Credential revocation.** Any credentials created during the exercise shall be revoked at teardown.
- *Rationale:* Good hygiene; prevents orphaned credentials.
- *Qualification:* OIDC/secret resources deleted; verification documented.

---

## 4. SYSTEM INTERNAL INTERFACE REQUIREMENTS

This section defines the internal interfaces between system components. Each interface states direction and purpose; the Setup/Architecture documentation describes implementation details.

| ID | Interface | Direction | Purpose |
|---|---|---|---|
| 4.1 | `gitops/` repository → ArgoCD → EKS | GitOps controller sync | Workload state flows from the repo to the cluster (REQ-3.3) |
| 4.2 | GitHub Actions → ECR | image push | Built images published under immutable SHA tags (REQ-3.2) |
| 4.3 | GitHub Actions → `gitops/` repo | manifest update | Pipeline commits the new image reference (REQ-3.2) |
| 4.4 | ALB ingress → Service → Pod | north-south traffic | Host-routed requests reach tenant pods (REQ-3.6) |
| 4.5 | Prometheus → scrape targets | metrics pull | Node/pod/HPA metrics collected for dashboards (REQ-3.8) |
| 4.6 | Karpenter → EKS API → EC2 | node provisioning | Pending pods trigger node creation/removal (REQ-3.7) |
| 4.7 | Pod → AWS services (IRSA) | least-privilege AWS access | Pods assume scoped roles; no keys (REQ-3.1-4) |

---

## 5. SYSTEM EXTERNAL INTERFACE REQUIREMENTS

| ID | Interface | Entities | Notes |
|---|---|---|---|
| 5.1 | Code push | Operator ↔ GitHub | Pushes to the application and gitops repositories |
| 5.2 | Infrastructure control | Operator ↔ AWS (Terraform CLI, console/CLI verification) | The only write path to AWS infrastructure is Terraform |
| 5.3 | Observation | Operator ↔ Grafana | Metrics and dashboards via ingress or port-forward |
| 5.4 | Traffic | Operator machine → ALB | curl of the five application URLs; no external users exist |
| 5.5 | DNS resolution | Public resolver ↔ ingress domain | nip.io/sslip.io default; real domain optional |

---

## 6. REQUIREMENTS FOR SYSTEM SECURITY AND PRIVACY

**REQ-6-1 (P1) Closed cluster.** The system shall run as a closed cluster with no public registration and no external users. No authentication service is required; this is an explicit non-requirement.
- *Rationale:* Authentication is deliberately out of scope for a one-month exercise; the cluster is not exposed to the internet beyond the ingress.
- *Qualification:* Inspection; only the ingress is externally reachable.

**REQ-6-2 (P1) No arbitrary third-party code.** The cluster shall execute only the five vetted demo applications; no third-party code submissions are accepted.
- *Rationale:* Running arbitrary code is a security program, not an exercise; excluding it preserves scope.
- *Qualification:* Inspection of running workloads.

**REQ-6-3 (P1) No static credentials.** CI shall authenticate via GitHub OIDC and pods via IRSA; no long-lived AWS keys shall exist in the repository or cluster.
- *Rationale:* Eliminates the prior project's credential failure mode.
- *Qualification:* Inspection; secret scanning of the repository.

**REQ-6-4 (P1) Tenant enforcement.** ResourceQuota, LimitRange, and NetworkPolicy shall be enforced per namespace (REQ-3.4).
- *Rationale:* Platform-level controls bound what any tenant can do.
- *Qualification:* REQ-3.4-4/3.4-5 demonstrations.

**REQ-6-5 (P2) Least-privilege containers.** Demo containers shall run as a non-root user with read-only root filesystems where feasible.
- *Rationale:* Establishes container security context concepts.
- *Qualification:* Inspection of deployment manifests and container security contexts.

**REQ-6-6 (P1) No data at risk.** The system shall store no customer, personal, or business data.
- *Rationale:* Zero data footprint removes a whole class of concern from an exercise.
- *Qualification:* Inspection of persistent storage usage.

---

## 7. REQUIREMENTS FOR SYSTEM COMPUTER RESOURCES

**REQ-7-1 (P1) Region.** The system shall run in a single AWS region (default us-east-1).
- *Qualification:* Inspection of Terraform provider configuration.

**REQ-7-2 (P1) Nodes.** The system shall run on `t3.medium` nodes by default (2 vCPU / 4 GiB), with spot-instance usage documented as a cost option.
- *Rationale:* Smallest instance size on which node-scaling (Karpenter) triggers under demo load while the catalog and system pods fit; burstable T3 suits the bursty load-test profile; three nodes land the exercise under the cost ceiling.
- *Qualification:* Inspection; Karpenter provisioner limits.

**REQ-7-3 (P1) Node pool sizing.** The initial Karpenter node pool shall be sized to run the five applications concurrently (see Appendix B for per-app requests).
- *Qualification:* All five apps schedulable at baseline.

**REQ-7-4 (P1) Control plane.** The EKS control plane shall be AWS-managed.
- *Qualification:* Inspection of cluster configuration.

**REQ-7-5 (P1) Storage.** The system shall use EBS (gp3) for node volumes; no application requires persistent storage (stateless demo apps).
- *Qualification:* Inspection of storage classes and application design.

**REQ-7-6 (P1) Cost envelope.** Monthly cost shall not exceed $180 (REQ-3.10-3).

---

## 8. REQUIREMENTS FOR SYSTEM QUALITY FACTORS

| Factor | Requirement | Qualification |
|---|---|---|
| **Maintainability (P1)** | All infrastructure and workloads declared in code with documented conventions | Inspection of `infra/`, `apps/`, `gitops/` |
| **Reliability (P1)** | Recovery procedures (rollback, self-heal) demonstrable | REQ-3.3, REQ-3.9 demonstrations |
| **Performance (P1)** | Defined scaling behavior: up on load, down after | REQ-3.7 demonstrations |
| **Security (P1)** | Section 6 requirements satisfied | Section 6 qualifications |
| **Usability (P1)** | Bootstrap ≤ 60 min; every operation documented with a verification step | REQ-3.1-7; documentation review |

---

## 9. REQUIREMENTS FOR DESIGN AND CONSTRUCTION CONSTRAINTS

**REQ-9-1 (P1) IaC only.** All AWS infrastructure shall be managed by Terraform/OpenTofu; no console click-ops.
**REQ-9-2 (P1) Single region.** Single-region design (REQ-7-1).
**REQ-9-3 (P1) Locked tooling.** The toolset is fixed: Terraform/OpenTofu, EKS, Karpenter, ArgoCD, GitHub Actions, Helm, kube-prometheus-stack. Alternatives may be discussed but not substituted mid-exercise.
**REQ-9-4 (P1) Naming conventions.** Namespaces `app-<name>`; repositories `infra/`, `apps/`, `gitops/`, `docs/`.
**REQ-9-5 (P1) No time phasing in specs.** This specification and its companion documentation shall not phase work into weeks or milestones; sequencing is a property of the exercise playbook, not the requirements.
**REQ-9-6 (P1) Ephemeral by design.** Teardown is a first-class requirement (REQ-3.10).
**REQ-9-7 (P1) Verified steps.** Every documented operational step shall end with an explicit verification step the operator performs.
**REQ-9-8 (P1) Excluded scope.** The following are explicitly out of scope: user authentication, billing, public exposure, arbitrary third-party code, multi-region, service mesh, canary/progressive delivery. (Rationale: each excluded item is a project of its own and would consume the month.)

---

## 10. REQUIREMENTS FOR SYSTEM COMPONENTS (SUBORDINATE ELEMENTS)

**10.1 Demo applications.** Five components; see Appendix B for detail.

**10.2 Load generator.** One component; a Job-based tool that drives CPU load at a target application (REQ-3.5-5).

**10.3 ArgoCD.** GitOps controller; the deployment engine (REQ-3.3).

**10.4 Observability stack.** Prometheus + Grafana via kube-prometheus-stack (REQ-3.8).

**10.5 AWS Load Balancer Controller.** Ingress capability (REQ-3.1-6).

**10.6 Karpenter.** Node provisioning and consolidation (REQ-3.1-3, REQ-3.7).

**10.7 cert-manager.** Optional; TLS when a real domain is used (REQ-3.6-3).

**10.8 Terraform state.** S3 bucket + DynamoDB lock table (REQ-3.1-1).

---

## 11. REQUIREMENTS FOR PRECEDENCE AND CRITICALITY OF REQUIREMENTS

11.1 Priorities are P1 (must), P2 (should), P3 (nice-to-have), annotated on each requirement in Section 3.

11.2 The P1 set is the minimum required for the end-to-end success demonstration (Appendix D) to pass. P2 and P3 requirements may be deferred without failing the exercise.

11.3 In the event of conflict, P1 requirements take precedence over P2/P3. Unresolvable conflicts are escalated to the Project Owner.

---

## 12. QUALIFYING CONDITIONS (VERIFICATION)

12.1 Verification methods used: **demonstration** (running the system; primary), **inspection** (reviewing code/manifests/config), and **analysis** (reasoning from metrics/logs). Each Section 3 requirement lists its qualification.

12.2 The formal acceptance event for the system is the **End-to-End Success Demonstration** (Appendix D), which exercises the P1 set in sequence.

12.3 Each qualification shall be performed by the operator hands-on, not by an automated assistant executing on their behalf. Where an assistant is used, the operator shall reproduce the action themselves.

---

## 13. NOTES

### 13.1 Assumptions
- Single region (us-east-1); `t3.medium` nodes; cost ceiling ≤ $180/month; ~30-day lifetime; closed cluster; no external users.
- Operators are expected to have working knowledge of Docker and Kubernetes fundamentals.
- No real domain is assumed; nip.io/sslip.io wildcard DNS is the default.

### 13.2 Open Items
- Final decision: real domain vs. nip.io/sslip.io (default: nip.io/sslip.io).
- Final instance sizing and spot usage (default: `t3.medium`; spot optional).
- Whether one demo application is authored as an exercise (REQ-3.5-6 note).

### 13.3 Risks and Mitigations
| Risk | Likelihood | Mitigation |
|---|---|---|
| Cost overrun | Medium | Budget alarm (REQ-3.10-3); spot option; teardown drill before month end |
| Time overrun | Medium | Scope lock (REQ-9-8); P2/P3 explicitly deferrable; canary/service-mesh excluded |
| IAM friction (repeat of prior project) | High | IRSA + OIDC as the only identity paths (REQ-3.1-4, REQ-3.2-1); bootstrap ≤ 60 min (REQ-3.1-7) |
| Karpenter scale-up that never scales down | Medium | Consolidation verified (REQ-3.7-4); cost alarm catches it |
| ArgoCD vs. `terraform destroy` race | Medium | Ordered teardown procedure (REQ-3.10-1) |

---

## APPENDIX A — REQUIREMENTS TRACEABILITY MATRIX

Maps each requirement to the companion documentation and exercise that exercises it.

| Requirement(s) | Design intent | Companion docs / exercise |
|---|---|---|
| REQ-3.1-1 … 3.1-7 | IaC state/plan/apply; AWS networking; IAM without pain | Setup doc; Exercise 1 |
| REQ-3.2-1 … 3.2-4 | OIDC; CI/CD pipeline anatomy; diagnosable failures | Exercise 2 |
| REQ-3.3-1 … 3.3-5 | GitOps reconciliation; self-heal; git-as-undo | Exercise 3; Exercise 7 (rollback) |
| REQ-3.4-1 … 3.4-5 | Tenancy, quotas, limits, network policy | Exercise 4 |
| REQ-3.5-1 … 3.5-6 | Multi-language catalog; container hygiene; load generation | Exercises 2–6 |
| REQ-3.6-1 … 3.6-4 | Host-based ingress; wildcard DNS; the live URL outcome | Exercise 3; Exercise 5 |
| REQ-3.7-1 … 3.7-5 | HPA; Karpenter; the scaling proof | Exercise 6 |
| REQ-3.8-1 … 3.8-4 | Metrics stack; dashboards; alerting concepts | Exercise 6 |
| REQ-3.9-1 … 3.9-3 | Controlled failure; rollback; recovery | Exercise 7 |
| REQ-3.10-1 … 3.10-4 | Ordered teardown; cost hygiene | Exercise 8 |
| REQ-6-1 … 6-6 | Security posture for platforms | throughout |
| REQ-9-1 … 9-8 | Design constraints and scope lock | throughout |

## APPENDIX B — DEMO APPLICATION CATALOG DETAIL

| # | App | Language | Image | Route | Purpose | Load endpoint | HPA | Requests / Limits |
|---|---|---|---|---|---|---|---|---|
| 1 | `api-node` | Node/TS | `api-node` | `api.<domain>` | Primary scaling demo | `GET /work?ms=<N>` (CPU burn) | HPA, 50% CPU | 50m / 128Mi → 250m / 256Mi |
| 2 | `web-node` | Node/TS | `web-node` | `web.<domain>` | Static serving; no scaling needed | — | none (replicas 1) | 50m / 128Mi → 200m / 256Mi |
| 3 | `worker-node` | Node/TS | `worker-node` | `worker.<domain>` | Background/queue shape; scale-to-N | built-in CPU loop | HPA, 50% CPU | 50m / 128Mi → 250m / 256Mi |
| 4 | `py-api` | Python/FastAPI | `py-api` | `py.<domain>` | Language diversity | `GET /work?ms=<N>` | HPA, 50% CPU | 50m / 128Mi → 250m / 256Mi |
| 5 | `go-api` | Go | `go-api` | `go.<domain>` | Language diversity; concurrency | `GET /work?ms=<N>` | HPA, 50% CPU | 50m / 128Mi → 250m / 256Mi |
| — | `loadgen` | tool (e.g., hey/vegeta or Node script) | `loadgen` | Job only | Drives load at a target app | targets `api-node` | none (Job) | bounded |

Request/limit values are chosen so that the load endpoint measurably raises CPU (triggering HPA) while quota stays meaningful.

## APPENDIX C — PITFALL REGISTER (WARNINGS AND CAUTIONS)

**WARNING — IAM/ARN drift.** The prior project stalled because deployment required manual ARN and IAM gymnastics. In this system, identity is IRSA (pods) and OIDC (CI) and *nothing else*. If a step asks you to copy an ARN into a secret, stop — the design is wrong. Report the deviation before proceeding.

**CAUTION — Karpenter scale-up that never scales down.** A sustained load test left running will keep the cluster scaled out and the bill climbing. Every scaling session ends with load stopped and both HPA and Karpenter consolidating back to baseline. Do not end a session mid-load.

**CAUTION — ArgoCD vs. `terraform destroy`.** An auto-syncing ArgoCD can recreate resources and namespaces while Terraform is tearing the cluster down, producing a messy, partial destroy. Teardown ordering (REQ-3.10-1) is mandatory: disable/uninstall ArgoCD first.

**CAUTION — Namespace deletion is irreversible.** Deleting a namespace deletes everything in it with no undo. Verify you are targeting the intended namespace before deleting.

**NOTE — Quota rejection is an event, not a log.** When a workload is rejected for quota, the diagnosis is in `kubectl describe` / events, not the pod logs. Read the events.

**WARNING — Cost alarm is not a suggestion.** If the budget alarm fires, stop the load test and scale down or destroy. This is an exercise; a surprise AWS bill is the one failure that cannot be rolled back.

## APPENDIX D — END-TO-END SUCCESS DEMONSTRATION

The formal acceptance event. Performed by the operator, hands-on, in this order. Each step ends with a verification the operator performs themselves.

1. **Clean bootstrap.** From a clean laptop, follow the Setup documentation; cluster ready in ≤ 60 minutes.
   - *Verify:* `kubectl get nodes` → all ready; `kubectl get ns` → no `app-*` namespaces yet.
2. **Cluster sanity.** Confirm ECR repos, ALB controller, Karpenter, ArgoCD are installed and healthy.
   - *Verify:* `kubectl get pods -n kube-system` and ArgoCD UI show healthy components.
3. **Deploy the catalog.** Deploy all five demo apps through the pipeline (GitOps path).
   - *Verify:* `curl https://<app>.<domain>` returns the expected response for all five URLs; ArgoCD shows five healthy Applications.
4. **Multi-tenant isolation.** Inspect namespaces, quotas, limits, network policies.
   - *Verify:* quota rejection demo (REQ-3.4-4) and cross-tenant block (REQ-3.4-5).
5. **Scaling proof.** Start the load generator against `api-node`; watch on Grafana.
   - *Verify:* replica count rises (HPA), new nodes appear (Karpenter), dashboards show it in real time.
6. **Scale-down.** Stop load; watch both autoscalers return to baseline.
   - *Verify:* replicas and nodes return to starting counts.
7. **Rollback exercise.** Introduce a broken image; observe failure; revert in git; ArgoCD rolls back; recovery ≤ 10 minutes.
   - *Verify:* application healthy again; operator explains what happened citing metrics and git history.
8. **Observability review.** Walk the dashboards; explain the load-test correlation; note the two alerts.
9. **Teardown.** Follow REQ-3.10-1 ordering; `terraform destroy`.
   - *Verify:* no billable AWS resources remain; bill returns to baseline.
10. **Explain the stack.** An operator produces and delivers a one-page architecture explanation of the whole path — repo → CI → ECR → gitops → ArgoCD → cluster → ingress → app → autoscaler → metrics — without notes. This is the final success criterion.

---

*End of document — Revision A, 2026-08-12.*
