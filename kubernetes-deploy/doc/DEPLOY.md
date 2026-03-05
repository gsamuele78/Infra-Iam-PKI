# Kubernetes Deployment Guide (RKE2)

## Prerequisites

1. A functioning Kubernetes cluster (preferably RKE2).
2. `kubectl` configured and communicating with the cluster.
3. A default `StorageClass` must be available in the cluster (e.g., `local-path` in RKE2, or `longhorn`) to automatically provision `PersistentVolumes` for databases.
4. An Ingress Controller (RKE2 provides NGINX Ingress by default).

## Execution Sequence

Due to the strict validation constraints (`initContainers` ensuring dependencies exist), the layers must be applied systematically.

### Step 1: Core Networking & Namespaces

This sets up the `pki`, `iam`, and `ood` namespaces and locks down the network.

```bash
kubectl apply -f kubernetes-deploy/00-core/
```

*(Verify: `kubectl get namespaces`)*

### Step 2: Public Key Infrastructure (PKI)

Deploy the foundational certificates authority and its PostgreSQL backend.

```bash
kubectl apply -f kubernetes-deploy/01-pki/
```

Wait for the PKI layer to become completely ready before proceeding to IAM or OOD:

```bash
kubectl wait --for=condition=ready pod -l app=step-ca -n pki --timeout=300s
```

*(Validation: PersistentVolumeClaims should be `Bound` in namespace `pki`)*

### Step 3: Identity & Access Management (IAM)

Deploy the PostgreSQL database, Keycloak Identity Provider, Ingress rules, and the RBAC-secured Certificate Renewer CronJob.

```bash
kubectl apply -f kubernetes-deploy/02-iam/
```

The Keycloak Pod relies on two `initContainers`. You can watch them execute:

```bash
# It will first wait for Postgres, then fetch the Step-CA root certificate
kubectl logs -f deployment/keycloak -n iam -c wait-for-db
kubectl logs -f deployment/keycloak -n iam -c fetch-pki-certs
```

### Step 4: Open OnDemand Portal (OOD)

Deploy the BiGeA themed frontend portal.

```bash
kubectl apply -f kubernetes-deploy/03-ood/
```

Like Keycloak, OOD has an `initContainer` to fetch the Step-CA root before launching Apache.

## Verification

Once all commands are run, review the state of the cluster across all namespaces:

```bash
kubectl get all -n pki
kubectl get all -n iam
kubectl get all -n ood
```

All Pods should report status `Running` (or `Completed` for Jobs), and no init containers should be hanging.

## Teardown (Destructive)

To completely remove the installation, including deleting all persistent data:

```bash
kubectl delete -f kubernetes-deploy/03-ood/
kubectl delete -f kubernetes-deploy/02-iam/
kubectl delete -f kubernetes-deploy/01-pki/
kubectl delete -f kubernetes-deploy/00-core/
```

*Warning: Deleting the `01-pki` persistent volume claims will destroy the CA database and keys permanently.*
