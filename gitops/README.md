# GitOps layout for Flux

This tree is what Flux will reconcile. The initial objects are minimal and safe to apply; they only point Flux at this same repository so it can self-manage.

Structure:
- flux-system/ — Flux “root” objects (GitRepository + Kustomization) that tell Flux to watch this repo.
- clusters/management/ — Entry point for this Talos cluster; split into infra/apps layers.
- modules/{infrastructure,apps}/ — Place your actual manifests or kustomize overlays here. Keep CRDs/addons in infrastructure; workloads in apps.

Bootstrap flow (after Flux is installed on the cluster):
1) Apply the two manifests in flux-system/ (or have Ansible do it): `kubectl apply -f gitops/flux-system/`.
2) Flux will pull this repo (HTTPS) and reconcile `gitops/clusters/management/`.
3) Add manifests under modules/infrastructure or modules/apps and reference them from the corresponding kustomizations; commit and push. Flux will converge them automatically.
