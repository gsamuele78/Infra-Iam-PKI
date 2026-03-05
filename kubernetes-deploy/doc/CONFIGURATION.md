# Kubernetes Configuration Handling

Unlike the Docker Compose structure which relies heavily on centralized `.env` files distributed across the host filesystem, the Kubernetes architecture transitions completely to cluster-native `Secrets` and `ConfigMaps`.

## 1. Secrets Management

Passwords, API tokens, and cryptographic keys are decoupled from deployments.

* `01-pki/pki-secrets.yaml`
* `02-iam/iam-secrets.yaml`

**Production Warning:** The files provided in this repository are formatted as standard Kubernetes base64 `Secrets` containing placeholder plaintext like `"secure_keycloak_admin_password"`.
Before executing `kubectl apply` in a real PRD environment, you must edit these YAMLs and provide genuinely secure passwords.

*Future Architecture Path:* In enterprise environments, replace these static `Secret` YAML templates with the `ExternalSecretsOperator` pointing at HashiCorp Vault, or `SealedSecrets`, preventing passwords from being stored in Git.

## 2. Ingress & Routing

### Layer 7: Keycloak & OOD

Ingresses are provided for HTTP/HTTPS web dashboards.
Modify `host:` names in the following files to match your DNS records:

* `02-iam/iam-ingress.yaml`: Update `sso.bigea.unibo.it` to match your Keycloak SSO domain.
* `03-ood/ood-services-ingress.yaml`: Update `ood.bigea.unibo.it` to match your portal domain.

### Layer 4: PKI API

The Step-CA service operates on port `9000`. To emulate the Layer 4 proxying previously handled by Caddy in Docker Compose, the PKI API is exposed to external nodes via a `NodePort` mapping.

* `01-pki/pki-services.yaml` exposes port `30900` natively on all Kubernetes worker nodes.
If your cluster runs a cloud-provider load balancer (e.g., MetalLB or AWS ELB), change the `type: NodePort` to `type: LoadBalancer`.

## 3. Persistent Volumes

The provided manifests utilize standard `PersistentVolumeClaim` (PVC) resources requesting generic `ReadWriteOnce` capabilities.

Ensure your Kubernetes distribution possesses a default `StorageClass`. RKE2 provides this out-of-the-box (`local-path-provisioner`). If you utilize advanced SANs (like TrueNAS SCALE via CSI), ensure the Default Storage Class is assigned correctly via `kubectl get sc` before applying the manifests.

## 4. Environment Variables Mapping

All configuration logic (such as `KC_DB_URL`, `POSTGRES_USER`, and `DOCKER_STEPCA_INIT_NAME`) has been converted directly into the `env:` blocks inside their respective `StatefulSet` and `Deployment` templates.

For the Open OnDemand OIDC client configuration (`OIDC_CLIENT_ID`, `OIDC_ENDPOINT`), the variables are natively interpolated into the `ood-config` `ConfigMap` defined in `03-ood/ood-configmaps.yaml`.
