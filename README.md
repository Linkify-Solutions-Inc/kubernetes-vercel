# kubernetes-vercel — Mini-PaaS Learning Platform

A self-hosted, Vercel/Render-like deployment platform on Amazon EKS, built as a
hands-on exercise in DevOps, Kubernetes, and AWS. **Not a production service.**
It runs for ~30 days, then is destroyed completely (teardown is a first-class
requirement).

## The shape of it

- **`infra/`** — Terraform: VPC, EKS, Karpenter, ECR, IRSA, GitHub OIDC.
- **`apps/`** — five demo applications (Node/TS ×3, Python, Go) + a load generator.
- **`gitops/`** — ArgoCD source of truth: namespaces, quotas, policies, deployments, ingress, HPA.
- **`.github/workflows/`** — CI: build → test → push to ECR → commit manifest → ArgoCD deploys.
- **`docs/`** — `PRD.md` (requirements spec), and the two technical manuals.

## How it works (the 10-second version)

`git push` → GitHub Actions builds the image (OIDC, no keys) → ECR (immutable SHA tag)
→ manifest updated in `gitops/` → ArgoCD reconciles → a namespace + live URL appear,
isolated and quota-bound. HPA scales pods, Karpenter scales nodes, Prometheus/Grafana
show all of it. Then `terraform destroy` returns the account to zero.

## Documentation

| Doc | Purpose |
|---|---|
| `docs/PRD.md` | System Requirements Specification (MIL-STD-498 SSS / IEEE 830) — what the system must do |
| `docs/TM-001-experiments-playbook.html` | Hands-on experiments, commands, and changes (MIL-STD-38784) |
| `docs/TM-002-technical-explainer.html` | Theory of operation — how everything connects (MIL-STD-38784) |

> Order by design: the code comes first; the two manuals are **drafts** until they
> document a verified build, then they are regenerated from reality (same standard
> as the kubernetes-streaming TM pair).

## Status

- [x] PRD (Rev A)
- [x] infra/ Terraform foundation — `terraform validate` passes against v21 modules
- [x] apps/ demo catalog (5 apps + loadgen)
- [x] gitops/ manifests + ArgoCD bootstrap (48 manifests, YAML-validated)
- [x] .github/workflows/ CI (OIDC, ECR, gitops promotion)
- [x] scripts/ teardown + verify
- [ ] **Verify on AWS** (the hands-on loop: `./infra/bootstrap-state.sh` → plan → apply → build)
- [ ] Regenerate the two manuals from the verified build (they are drafts until then)
- [ ] Teardown (the last exercise)

## Cost

~$150–216/month while running (see `docs/TM-001-experiments-playbook.html` App. B).
Staying under the $180 ceiling requires spot nodes or a NAT instance.
