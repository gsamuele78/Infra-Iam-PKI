# Kubernetes Deployment Overview (RKE2)

## 1. Executive Summary

This directory (`kubernetes-deploy/`) contains the production-ready Kubernetes manifests for the `Infra-Iam-PKI` infrastructure. It directly translates the pessimistic, zero-trust Docker Compose architecture into cloud-native Kubernetes paradigms, targeting the **RKE2 (Rancher Kubernetes Engine 2)** distribution.

The Kubernetes architecture guarantees high availability, strictly enforces container resource limits, and ensures data persistence across node failures via native `StorageClasses` and `PersistentVolumeClaims`.

## 2. Directory Structure

The deployment is segmented into logical layers that must be applied sequentially to satisfy dependency constraints:

* **`00-core/`**: Defines the namespace isolation (`pki`, `iam`, `ood`) and enforce default-deny `NetworkPolicies` across the cluster.
* **`01-pki/`**: Deploys the Smallstep CA and PostgreSQL database as `StatefulSet`s, ensuring cryptographic data persistence. Exposes the CA API via a `NodePort` mapping.
* **`02-iam/`**: Deploys the Keycloak Identity Provider and its PostgreSQL database. Crucially, it replaces the docker-socket-proxy with a zero-trust `CronJob` using RBAC `RoleBindings` to renew certificates.
* **`03-ood/`**: Deploys the Open OnDemand portal. It injects the custom BiGeA UI theme natively via `ConfigMap` resources instead of host volume mounts.

## 3. Kubernetes Paradigms & Constraints (PRD Compliant)

This deployment strictly adheres to **Pessimistic System Engineering** constraints:

### 3.1 Zero-Trust Networking

* All namespaces (`iam`, `pki`, `ood`) are strictly isolated via `NetworkPolicy` manifestations.
* Ingress traffic is denied by default. Explicit paths (e.g., Ingress-NGINX to Keycloak `8080`, or OOD to PKI `9000`) are explicitly whitelisted.

### 3.2 Resource Constrains (Anti-OOM)

* No container operates unbounded. Every deployment, database, and sidecar script defines strict `resources.requests` and `resources.limits` for both CPU (`cpus`) and RAM (`memory`).
* This ensures the Kubelet's OOM killer will terminate rogue processes *before* they can destabilize the hosting node or disrupt neighboring pods.

### 3.3 RBAC vs. Docker Socket

* The original architecture utilized a `tecnativa/docker-socket-proxy` to allow the renewer script to restart Keycloak upon certificate renewal.
* In K8s, mounting `/var/run/docker.sock` is a severe security vulnerability. Instead, the renewer runs as a `CronJob` bound to a deeply restricted `ServiceAccount`. It is granted *only* the `patch` verb targeting specifically the `keycloak` `Deployment` resource.

### 3.4 Decoupled Initialization (InitContainers)

* Optimistic "wait-for-it" scripts are removed. We utilize Kubernetes `initContainers` to aggressively poll dependencies.
* Keycloak will absolutely not start until its `pg_isready` InitContainer returns successfully.
* OOD and IAM will not launch main UI threads until the API call to `step-ca.pki.svc.cluster.local:9000` succeeds and the Root CA `.crt` is injected into the Pod's local trust store.

## 4. UI/UX Theming Integration

The **University of Bologna (BiGeA)** UI themes are abstracted away from the container images. The CSS (`bigea-theme.css`) and Configuration files (`ood_portal.yml`) are stored as pure Kubernetes `ConfigMap` resources. This guarantees exact PRD compliance (Unibo Red, Glassmorphism, Inter font) while maintaining container immutability.
