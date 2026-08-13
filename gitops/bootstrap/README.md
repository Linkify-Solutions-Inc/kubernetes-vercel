# GitOps bootstrap

ArgoCD is the deployment engine. Nothing here is "deployed" by hand — the repo is
the source of truth and ArgoCD reconciles it.

## Install ArgoCD (once, by hand — this is Exercise 2)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace
kubectl -n argocd get pods -w
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```

## Register the App-of-Apps

```bash
kubectl apply -f gitops/bootstrap/app-of-apps.yaml
argocd app list
```

ArgoCD discovers `gitops/apps/*.yaml` and deploys them in sync-wave order:
`crds` (wave 0 — the Prometheus/Alertmanager CRDs, applied server-side because
ArgoCD skips Helm charts' `crds/` directories), `karpenter` (wave 5 — the
NodePool/EC2NodeClass), then metrics-server / monitoring / the five tenants
(waves 10–15). Workload manifests live in `gitops/manifests/<app>/`.

## One-time substitutions (before first sync)

- **Ingress domain.** Each `gitops/manifests/<app>/ingress.yaml` host contains the
  placeholder `__INGRESS_DOMAIN__`. After the ALB exists, replace it once with
  your wildcard domain (`<alb-address>.nip.io` or a real domain) across all five
  ingress files and push.
- **Private repo credentials.** If the repo is private, ArgoCD needs a
  `argocd-repo-creds` secret or an SSH key. Documented in ArgoCD docs.
