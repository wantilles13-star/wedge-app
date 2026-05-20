# Tenant repo CI + guardrails kit

Copy this kit (or let k3s-onboarding seed it) into tenant-owned repositories so manifest quality and baseline security checks run before Argo CD syncs workloads.

See [17-tenant-repo-onboarding-runbook §4](../../platform/deploy/17-tenant-repo-onboarding-runbook.md#4-add-tenant-ci-guardrails) and [tenants/README.md](../../README.md).

## Copy checklist

| Source in this template | Destination in tenant repo |
|-------------------------|-----------------------------|
| `repo-ci/.github/workflows/*` | `.github/workflows/` |
| `repo-ci/.github/dependabot.yml` | `.github/dependabot.yml` |
| `repo-ci/policy/` | `policy/` |
| `repo-ci/homelab-tenant.yaml.example` | `homelab-tenant.yaml` (edit placeholders) |
| `repo-ci/.trivyignore` | `.trivyignore` (optional) |
| `repo-ci/scripts/render-manifests.sh` | `scripts/render-manifests.sh` |
| `repo-ci/scripts/validate-locally.sh` | `scripts/validate-locally.sh` (optional) |
| `k8s/*` + `Dockerfile` | `k8s/`, repo root (**full seed only**) |

## Seed modes

| Mode | Use when | Includes |
|------|----------|----------|
| **`full`** | New / empty tenant repos | `repo-ci` kit + `k8s/` splash workload + root `Dockerfile` |
| **`guardrails-only`** | Existing repos with mature manifests | `repo-ci` kit only (no splash manifests or Dockerfile) |

Guardrails-only mode never adds:

- `k8s/deployment.yaml`, `service.yaml`, `ingress.yaml`, `kustomization.yaml`
- `k8s/static/`
- `Dockerfile`

Guardrails-only mode still adds (if missing):

- `tenant-guardrails.yaml`, `repo-hygiene.yaml`, `policy/*.rego`, `.github/dependabot.yml`
- `homelab-tenant.yaml` with a render path aligned to existing repo layout
- `tenant-image.yaml` only when a root `Dockerfile` already exists
- Dependabot **docker** ecosystem only when a root `Dockerfile` exists (github-actions always)

## Manifest rendering

`tenant-guardrails` and `scripts/validate-locally.sh` call `scripts/render-manifests.sh`, which:

1. Uses `renderPath` from `homelab-tenant.yaml` when set (must match Argo `Application.spec.source.path`)
2. Otherwise auto-detects `k8s/` or `deploy/` when `kustomization.yaml` exists there
3. Renders via **kustomize** when `${renderPath}/kustomization.yaml` exists
4. Otherwise concatenates flat `*.yaml` files in `${renderPath}` (guardrails-only repos like `k8s/<slug>/`)
5. Falls back to Helm when `Chart.yaml` exists at repo root

## Workflows in this kit

| Workflow | Purpose |
|----------|---------|
| `tenant-guardrails.yaml` | Render manifests via `scripts/render-manifests.sh`, run kubeconform + conftest policies |
| `repo-hygiene.yaml` | Detect leaked secrets (gitleaks) and lint root Dockerfile (hadolint, skipped when no Dockerfile) |
| `tenant-image.yaml` | Build/push arm64 GHCR image and run Trivy config/image scans |

## Policy set

| File | Purpose |
|------|---------|
| `deny-risky-manifests.rego` | Forbid platform-owned resources and privileged pod settings |
| `require-psa-baseline.rego` | Enforce hardened pod defaults aligned with PSA baseline |
| `deny-secrets-in-git.rego` | Block plain Kubernetes Secret manifests in tenant repos |
| `validate-tenant-contract.rego` | Verify rendered manifests align with `homelab-tenant.yaml` |

## Tenant contract (`homelab-tenant.yaml`)

Example:

```yaml
tenantSlug: wedge-app
renderPath: k8s/wedge-app
ingressHost: wedge-app.reeves.racing
targetArch: arm64
ingressClass: nginx
```

`renderPath` must match Argo `Application.spec.source.path` exactly.

## Tool pins (CI)

`tenant-guardrails.yaml` installs fixed CLI versions (kubeconform, kustomize, helm, **conftest v0.46.0**). Policies use Rego syntax compatible with that pin; do not bump conftest without updating `policy/*.rego` and re-running CI.

## Verification gates

After pushing to the tenant repo default branch:

| GitHub check | Pass criteria |
|--------------|---------------|
| `repo-hygiene` | Workflow file valid; gitleaks clean; hadolint skipped when no root `Dockerfile` |
| `tenant-guardrails` | Render step succeeds; kubeconform strict; conftest policies pass |

Local parity (optional):

```bash
./scripts/validate-locally.sh
```

Requires `kustomize`, `helm`, `kubeconform`, and **conftest 0.46.x** on `PATH`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Invalid workflow: `hashFiles` unrecognized | Job-level `hashFiles` in `repo-hygiene` | Use post-checkout Dockerfile detection (current template) |
| `No kustomization.yaml in k8s/ or deploy/` | CI ignores `homelab-tenant.yaml` `renderPath` or missing `render-manifests.sh` | Sync kit from `tenants/templates/repo-ci/`; set `renderPath` to Argo source path |
| Dependabot docker `dependency_file_not_found` | Docker ecosystem without root `Dockerfile` | Remove docker block from `dependabot.yml` or add `Dockerfile` (full seed) |
| conftest `rego_parse_error` | conftest 0.56+ with legacy Rego rules | Pin conftest to **v0.46.0** in workflow or migrate policies to Rego v1 |
| conftest FAIL on Deployment | Manifest below PSA baseline | Harden pod/container `securityContext` and `resources.limits` |
| `tenant-image` Trivy **DS-0002** (no `USER` in Dockerfile) | Config scan requires explicit non-root `USER` | Seeded `tenants/templates/k8s/Dockerfile` includes `USER nginx` after `COPY` |

## GHCR authentication and security

| Mechanism | What it can do | Risk | Mitigation |
|-----------|----------------|------|------------|
| `GITHUB_TOKEN` in Actions | Push package tags for this repo (`packages: write`) | Compromised workflow on `main` could publish a malicious image tag | Branch protection, required checks, avoid `pull_request_target` writes, pin actions by SHA when desired |
| Optional `GHCR_TOKEN` PAT | Wider package push scope depending on token grants | Secret leak can impact more repos/packages | Use only when default token cannot push, keep minimal scopes, rotate |
| Namespace pull secret (`ghcr-credentials`) | Pull images in cluster | Stolen token enables image pull | Prefer public package for splash repos; otherwise use platform-managed secret workflow |

GHCR login does not expose cluster kubeconfigs or Argo admin credentials.

## Branch protection

Require at least these checks before enabling broad tenant write access:

- `tenant-guardrails`
- `repo-hygiene`

Optional hardening (future): protect `.github/workflows/**`, `policy/**`, and `homelab-tenant.yaml` with `CODEOWNERS` + branch rulesets so tenants cannot weaken guardrails without platform approval.
