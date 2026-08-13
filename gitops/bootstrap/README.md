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

ArgoCD then discovers `gitops/apps/*.yaml`, which deploy the workload manifests
in `gitops/manifests/<app>/` into per-app namespaces.

## One-time substitutions (before first sync)

- **Ingress domain.** Each `gitops/manifests/<app>/ingress.yaml` host contains the
  placeholder `__INGRESS_DOMAIN__`. After the ALB exists, replace it once with
  your wildcard domain (`<alb-address>.nip.io` or a real domain) across all five
  ingress files and push.
- **Private repo credentials.** If the repo is private, ArgoCD needs a
  `argocd-repo-creds` secret or an SSH key. Documented in ArgoCD docs.
