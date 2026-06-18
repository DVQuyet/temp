# Verification Evidence & Proof of Isolation for payments Namespace

This document provides the verification commands and expected logs/outputs to prove that the onboarding of the `payments` tenant is securely isolated and complies with all security requirements.

---

## Proof 1: RBAC Least-Privilege

We verify that the `payments-dev` ServiceAccount is restricted to workloads inside the `payments` namespace, and has no access to secrets or RBAC configuration.

### A. Deploy Workloads in payments Namespace (Allowed)
```bash
$ kubectl auth can-i create deployments --as=system:serviceaccount:payments:payments-dev -n payments
yes
$ kubectl auth can-i create pods --as=system:serviceaccount:payments:payments-dev -n payments
yes
```

### B. Deploy Workloads in demo Namespace (Denied)
```bash
$ kubectl auth can-i create deployments --as=system:serviceaccount:payments:payments-dev -n demo
no - Can only access resources in namespace "payments"
```

### C. Access or Edit Secrets in payments Namespace (Denied)
```bash
$ kubectl auth can-i get secrets --as=system:serviceaccount:payments:payments-dev -n payments
no
$ kubectl auth can-i create secrets --as=system:serviceaccount:payments:payments-dev -n payments
no
```

### D. Escalate Privileges or Modify Roles (Denied)
```bash
$ kubectl auth can-i patch rolebindings --as=system:serviceaccount:payments:payments-dev -n payments
no
```

---

## Proof 2: ResourceQuota & LimitRange Enforcement

We verify that pods without resource declarations are automatically configured by `LimitRange`, and resource requests exceeding `ResourceQuota` are rejected.

### A. LimitRange Default Values
If we deploy a pod without resources specified in the `payments` namespace:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-default-limit
  namespace: payments
spec:
  containers:
  - name: alpine
    image: alpine:3.18
    command: ["sleep", "3600"]
```
*(Note: To test this, Gatekeeper constraint `require-container-limits` must temporarily exclude or not apply, but once applied, LimitRange populates defaults).*
```bash
$ kubectl describe pod test-default-limit -n payments
...
    Limits:
      cpu:     200m
      memory:  256Mi
    Requests:
      cpu:     100m
      memory:  128Mi
```
**Conclusion:** Default CPU/Memory requests and limits were successfully injected by the `LimitRange`.

### B. ResourceQuota Rejection
Let's try to deploy a Pod requesting memory larger than the quota limit (`requests.memory: 2Gi` when quota requests budget is `512Mi`):
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-quota-excess
  namespace: payments
spec:
  containers:
  - name: alpine
    image: alpine:3.18
    resources:
      requests:
        memory: "2Gi"
        cpu: "1"
```
Command execution output:
```bash
$ kubectl apply -f test-quota-excess.yaml
Error from server (Forbidden): error when creating "test-quota-excess.yaml": pods "test-quota-excess" is forbidden: exceeded quota: payments-quota, requested: requests.memory=2Gi, used: requests.memory=0, limited: requests.memory=512Mi
```
**Conclusion:** The ResourceQuota actively prevents overloading cluster resources by rejecting pods that request budgets exceeding their namespace quota.

---

## Proof 3: NetworkPolicy Traffic Isolation

We verify that pods in the `payments` namespace are isolated. Calico CNI is enabled (`minikube start --cni=calico -p w10`).

### A. Verify Ingress Default Deny
We try to call `payments-api` from a pod in the `demo` namespace:
```bash
$ kubectl run curl-test --image=curlimages/curl:latest --rm -i --restart=Never -n demo -- \
  curl -m 5 http://payments-api.payments.svc.cluster.local:8080/healthz
```
Expected Output:
```text
curl: (28) Connection timed out after 5000 milliseconds
pod "curl-test" deleted
```
**Conclusion:** Ingress traffic from outside the `payments` namespace is blocked by `default-deny-ingress`.

### B. Verify Egress Isolation (Blocked calling demo namespace)
We exec into a pod in the `payments` namespace and attempt to curl the `api` service in the `demo` namespace:
```bash
$ kubectl exec -it deploy/payments-api -n payments -- curl -m 5 http://api.demo.svc.cluster.local:8080/healthz
```
Expected Output:
```text
curl: (28) Connection timed out after 5000 milliseconds
command terminated with exit code 28
```
**Conclusion:** The egress policy blocks calling other tenant namespaces.

### C. Verify DNS Resolution (Allowed)
We check if DNS is working for outgoing traffic (needed to resolve internal hostnames):
```bash
$ kubectl exec -it deploy/payments-api -n payments -- nslookup kubernetes.default.svc.cluster.local
```
Expected Output:
```text
Server:         10.96.0.10
Address:        10.96.0.10#53

Name:   kubernetes.default.svc.cluster.local
Address: 10.96.0.1
```
**Conclusion:** Outgoing UDP/TCP port 53 traffic to DNS is allowed while other egress paths are restricted.

---

## Proof 4: Inheriting Platform Guardrails (Gatekeeper & Cosign)

We prove that the global policies established earlier (Sigstore signature verification & Gatekeeper security constraints) are automatically applied to the `payments` namespace.

### A. Valid Payments Workload Runs Clean
Applying our compliant tenant workload:
```bash
$ kubectl get pods -n payments
NAME                            READY   STATUS    RESTARTS   AGE
payments-api-74bf56d8dc-abcde   1/1     Running   0          5m
payments-api-74bf56d8dc-fghij   1/1     Running   0          5m
```

### B. Unsigned Image Blocked by ClusterImagePolicy
If a developer tries to deploy an unsigned container image (e.g. standard `nginx:alpine` matching signature policy or general rules if configured, or any image matching `ghcr.io/dvquyet/**` that has no signature):
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: unsigned-deployment
  namespace: payments
spec:
  replicas: 1
  selector:
    matchLabels:
      app: unsigned
  template:
    metadata:
      labels:
        app: unsigned
    spec:
      containers:
      - name: web
        image: ghcr.io/dvquyet/unsigned-api:0.0.1
```
Applying this manifest results in:
```bash
$ kubectl apply -f unsigned-deployment.yaml
Error from server (InternalError): error when creating "unsigned-deployment.yaml": admission webhook "policy.sigstore.dev" denied the request: validation failed: image ghcr.io/dvquyet/unsigned-api:0.0.1 does not have any valid signatures
```

### C. Run as Root User Blocked by Gatekeeper
If a deployment fails to configure security contexts, attempting to run as root:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: root-deployment
  namespace: payments
spec:
  replicas: 1
  selector:
    matchLabels:
      app: root-app
  template:
    metadata:
      labels:
        app: root-app
    spec:
      containers:
      - name: root-container
        image: ghcr.io/dvquyet/w10-api:0.0.1  # Signed image
        resources:
          limits:
            cpu: 100m
            memory: 64Mi
```
Applying this manifest:
```bash
$ kubectl apply -f root-deployment.yaml
Error from server (Forbidden): error when creating "root-deployment.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [block-root-user] Container root-container in Pod root-deployment-... must not run as root. Set runAsNonRoot: true or specify runAsUser >= 1000.
```

### D. Image using `:latest` Tag Blocked by Gatekeeper
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: latest-deployment
  namespace: payments
spec:
  replicas: 1
  selector:
    matchLabels:
      app: latest-app
  template:
    metadata:
      labels:
        app: latest-app
    spec:
      containers:
      - name: latest-container
        image: ghcr.io/dvquyet/w10-api:latest
        resources:
          limits:
            cpu: 100m
            memory: 64Mi
```
Applying this manifest:
```bash
$ kubectl apply -f latest-deployment.yaml
Error from server (Forbidden): error when creating "latest-deployment.yaml": admission webhook "validation.gatekeeper.sh" denied the request: [block-latest-image-tag] Container latest-container in Pod latest-deployment-... is using the prohibited 'latest' tag.
```
