# Runbook: Secrets Rotation with External Secrets Operator (ESO)

This runbook describes how automated secret rotation is managed and verified on the Kubernetes cluster using the External Secrets Operator (ESO).

## Overview

We use ESO to periodically poll the secret provider (simulated by a `fake` provider or AWS Secrets Manager) and update a Kubernetes `Secret` called `db-secret` in the `demo` namespace. 
Because the secret is mounted as a volume directory under `/secrets` in the API container, Kubernetes dynamically updates the mounted files when the underlying Secret changes. The Flask application reads `/secrets/password` on every request to `/secret` to ensure zero-downtime, restart-free secret updates.

---

## 1. Verify Current Secret Status

Check that the ExternalSecret is active and the Kubernetes Secret exists:

```bash
# Verify ExternalSecret status
kubectl get externalsecret db-creds -n demo

# View current generated secret value (base64 decoded)
kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d
```

---

## 2. Simulate Secret Rotation

Since we are using the `fake` provider in the `SecretStore` to simulate AWS Secrets Manager, we can rotate the password by patching the `SecretStore` spec:

```bash
kubectl patch secretstore fake-store -n demo --type='json' -p='[{"op": "replace", "path": "/spec/provider/fake/data/0/value", "value": "new-rotated-password-456"}]'
```

---

## 3. Verify Synchronization (Within 10 Seconds)

ESO has a `refreshInterval` of `10s` configured. Within 10 seconds of patching the store:

1. **Verify K8s Secret is updated**:
   ```bash
   kubectl get secret db-secret -n demo -o jsonpath='{.data.password}' | base64 -d
   # Expected output: new-rotated-password-456
   ```

2. **Verify Pod updates dynamically**:
   Exec into one of the running API pods to verify the file `/secrets/password` contains the updated value:
   ```bash
   kubectl exec -it deployment/api -n demo -c api -- cat /secrets/password
   # Expected output: new-rotated-password-456
   ```

3. **Verify App dynamically retrieves it via HTTP**:
   Call the `/secret` API endpoint:
   ```bash
   kubectl exec -it deployment/api -n demo -c api -- curl http://localhost:8080/secret
   # Expected output: {"password":"new-rotated-password-456"}
   ```

4. **Verify No Pod Restart Occurred**:
   Check the `AGE` or restart count of the API pods:
   ```bash
   kubectl get pods -n demo -l app=api
   # The AGE of the pods should remain unchanged, and restarts should be 0.
   ```
