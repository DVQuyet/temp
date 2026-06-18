# Runbook: Image Signature Verification Failures

This runbook explains how to diagnose and troubleshoot deployment failures caused by the Sigstore Policy Controller admission webhook rejecting unsigned or invalidly signed container images.

## Overview

Our cluster enforces supply chain security using Sigstore Policy Controller. When a namespace is labeled with `policy.sigstore.dev/include=true`, the controller validates that all container images deployed to that namespace (matching `ghcr.io/dvquyet/**`) have been signed using our trusted Cosign private key.

---

## 1. Symptoms of Signature Rejection

If a deployment uses an unsigned image, the pod creation will fail. You will see an error in the ReplicaSet or deployment description:

```bash
kubectl describe deploy api -n demo
# Or check the events in the namespace:
kubectl get events -n demo --sort-by='.metadata.creationTimestamp'
```

### Typical Error Message
```text
Error creating: Internal error occurred: admission webhook "policy.sigstore.dev" denied the request: validation failed: image ghcr.io/dvquyet/w10-api:latest does not have any valid signatures
```

---

## 2. Diagnostics & Troubleshooting Steps

### Step A: Verify Namespace Labeling
Check if the namespace is active for policy enforcement:
```bash
kubectl get ns demo -o jsonpath='{.metadata.labels}'
# Look for: "policy.sigstore.dev/include": "true"
```
*If missing, the policy is NOT being enforced on this namespace.*

### Step B: Inspect ClusterImagePolicies
Verify that the `ClusterImagePolicy` exists and is configured with the correct public key:
```bash
kubectl get clusterimagepolicy
kubectl describe clusterimagepolicy ghcr-image-signature-policy
```

### Step C: Verify the Signature Manually
Run `cosign verify` to inspect if the image has a valid signature matching our public key:
```bash
# Using local cosign.exe and the committed public key
./cosign.exe verify --key signing/cosign.pub ghcr.io/dvquyet/w10-api:<version>
```
- **If it succeeds**: The signature is valid. The issue might be a network/latency issue between the policy controller and the container registry.
- **If it fails**: The image was either never signed in CI, or was signed using a different key.

### Step D: Inspect Policy Controller Logs
If the signature is valid but deployment is still blocked, inspect the admission controller logs:
```bash
kubectl get pods -n cosign-system
kubectl logs -n cosign-system -l app.kubernetes.io/name=policy-controller -c webhook
```

---

## 3. Resolution Steps

1. **Verify GitHub Actions Workflow**: Check the run history of the `.github/workflows/build-push.yml` workflow. Ensure the `Sign the published Docker image` step ran successfully.
2. **Secret Configuration**: Ensure that the `COSIGN_PRIVATE_KEY` secret is properly set in the GitHub repository's secrets.
3. **Local Manual Signing (Fallback)**:
   If CI failed and you need to sign an image manually:
   ```bash
   # Set the private key env variable and sign the image
   $env:COSIGN_PRIVATE_KEY="<private-key-content>"
   ./cosign.exe sign --key env://COSIGN_PRIVATE_KEY ghcr.io/dvquyet/w10-api:<version>
   ```
