# W10 - Secure & Operate: RBAC, Admission Policy, Secrets Rotation & Supply Chain Security

GitOps setup for a secure Kubernetes cluster using ArgoCD, OPA Gatekeeper, External Secrets Operator (ESO), Cosign/Sigstore, and Prometheus monitoring.

## Concept

This repository demonstrates enterprise-grade security and operations on a Kubernetes cluster:
- **RBAC**: Multi-tenant isolation for team `payments` and standard roles (`developer` for Alice, `sre` for Bob, `viewer` for Carol).
- **Admission Policy**: OPA Gatekeeper constraint enforcement (blocks root users, prevents using `latest` image tags, mandates resource limits, blocks host network access, limits deployment replicas to max 5).
- **Secrets Rotation**: External Secrets Operator (ESO) integration with a mock provider (`fake-store`). Rotates secrets in under 10 seconds with zero-downtime (no pod restarts, mount via Volume).
- **Supply Chain Security**: Cosign key-based verification using Sigstore Policy Controller. Restricts deployment of unsigned images.
- **Progressive Delivery**: Argo Rollouts with automated canary analysis querying Prometheus.

---

## Workspace Structure

```
w10/
├── app-api/                # API Rollout manifests (Argo Rollouts)
├── app-analysis/           # AnalysisTemplate manifests
├── app-alert/              # AlertManager email notification rules
├── app-common/             # Namespace demo definition
├── apps/payments/          # Payments workload manifests (Deployment, Service)
├── argocd/                 # ArgoCD Applications (App of Apps pattern)
│   ├── apps/               # Individual ArgoCD app manifests
│   └── root.yaml           # Root ArgoCD App of Apps pattern
├── gatekeeper/             # OPA Gatekeeper ConstraintTemplates and Constraints
│   ├── templates/          # Reusable policy templates
│   └── constraints/        # Specific enforcement rules
├── gatekeeper-tests/       # Test cases validating OPA Gatekeeper policies
├── eso/                    # External Secrets Operator configuration
├── policies/               # Sigstore ClusterImagePolicy definition
├── rbac/                   # User Role & Binding definitions
├── signing/                # Public key for Cosign image signature verification
└── src/                    # Flask API source code
```

---

## Quick Start (Windows & Bash Compatible)

### 1. Setup Cluster
Launch Minikube with Docker driver and select the context:
```bash
minikube start -p w10 --driver=docker
kubectl config use-context w10
```

### 2. Install ArgoCD
Apply ArgoCD controller manifests server-side:
* **Bash (Linux/macOS):**
  ```bash
  kubectl create ns argocd
  kubectl apply --server-side -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl -n argocd rollout status deploy/argocd-server
  ```
* **PowerShell / Command Prompt (Windows):**
  ```cmd
  kubectl create ns argocd
  kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl -n argocd rollout status deploy/argocd-server
  ```

### 3. Access ArgoCD UI

**Port Forwarding (Mở một Terminal/PowerShell mới hoặc chạy nền):**
* **Bash (Linux/macOS):**
  ```bash
  kubectl -n argocd port-forward svc/argocd-server 8080:443 &
  ```
* **PowerShell (Windows):**
  ```powershell
  Start-Process kubectl -ArgumentList "-n argocd port-forward svc/argocd-server 8080:443" -NoNewWindow
  # Hoặc mở một Terminal mới và chạy:
  # kubectl -n argocd port-forward svc/argocd-server 8080:443
  ```
* **Command Prompt (Windows CMD):**
  ```cmd
  start kubectl -n argocd port-forward svc/argocd-server 8080:443
  # Hoặc mở một Command Prompt mới và chạy:
  # kubectl -n argocd port-forward svc/argocd-server 8080:443
  ```

**Get Initial Admin Password:**
* **Bash (Linux/macOS):**
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
  ```
* **PowerShell (Windows):**
  ```powershell
  kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}'
  ```
* **Command Prompt (Windows CMD):**
  ```cmd
  kubectl -n argocd get secret argocd-initial-admin-secret -o go-template="{{.data.password | base64decode}}"
  ```

### 4. Deploy App of Apps
Deploy the root application which automatically orchestrates the installation of all platform and workload apps:
```bash
kubectl apply -f argocd/root.yaml
```

### 5. Setup Email Alert (Optional)
Configure credentials for Alertmanager notifications:
* **Bash (Linux/macOS):**
  ```bash
  cp app-alert/email-secret.yaml.example app-alert/email-secret.yaml
  kubectl apply -f app-alert/email-secret.yaml
  ```
* **PowerShell (Windows):**
  ```powershell
  Copy-Item app-alert/email-secret.yaml.example app-alert/email-secret.yaml
  kubectl apply -f app-alert/email-secret.yaml
  ```
* **Command Prompt (Windows CMD):**
  ```cmd
  copy app-alert\email-secret.yaml.example app-alert\email-secret.yaml
  kubectl apply -f app-alert/email-secret.yaml
  ```

---

## Configuration Reference & Sync Waves

ArgoCD applications deploy in logical sync waves:
- **Wave -5**: `gatekeeper-controller` (OPA Gatekeeper operator installation)
- **Wave -4**: `external-secrets` & `policy-controller` (Operators for Secrets & Signatures)
- **Wave -3**: `eso-config` & `policies` (SecretStore, ClusterImagePolicy configuration)
- **Wave -2**: `gatekeeper-policies` & `payments-infra` (ConstraintTemplates, Namespace resource isolation)
- **Wave -1**: `app-common` (Namespace demo definition)
- **Wave 0**: `k8s-prometheus`, `k8s-rollout` & `rbac` (Telemetry stack, Rollout controller, User roles)
- **Wave 1**: `app-analysis` & `app-alert` (PrometheusRule and AnalysisTemplates)
- **Wave 2**: `app-api` (Canary rollout application deployment)
- **Wave 3**: `payments-app` (Payments API workload)

---

## Verification Guide (Windows Compatible)

### 1. Verify RBAC Roles
Validate the configured ClusterRoles and Roles:
* **Developer (Alice - Namespaced permissions in `demo`):**
  ```cmd
  kubectl auth can-i create deployments -n demo --as alice
  # Expected: yes
  kubectl auth can-i create deployments -n default --as alice
  # Expected: no
  ```
* **SRE (Bob - Cluster-wide logs & exec only):**
  ```cmd
  kubectl auth can-i get pods -A --as bob
  # Expected: yes
  kubectl auth can-i create deployments -n demo --as bob
  # Expected: no
  ```
* **Viewer (Carol - Cluster-wide read-only access):**
  ```cmd
  kubectl auth can-i get deployments --all-namespaces --as carol
  # Expected: yes
  kubectl auth can-i delete pods -n demo --as carol
  # Expected: no
  ```

### 2. Verify Admission Policies (OPA Gatekeeper)
Test constraint templates by trying to apply violating pods or deployments:
* **Block latest tag:**
  ```cmd
  kubectl apply -f gatekeeper-tests/pod-violate-latest.yaml
  # Expected: Rejected by validation webhook [block-latest]
  ```
* **Block root user:**
  ```cmd
  kubectl apply -f gatekeeper-tests/pod-violate-root.yaml
  # Expected: Rejected by validation webhook [block-root-user]
  ```
* **Enforce Resource Limits:**
  ```cmd
  kubectl apply -f gatekeeper-tests/pod-violate-limits.yaml
  # Expected: Rejected by validation webhook [required-limits]
  ```
* **Block Host Network:**
  ```cmd
  kubectl apply -f gatekeeper-tests/pod-violate-hostnetwork.yaml
  # Expected: Rejected by validation webhook [block-host-network]
  ```
* **Max Replicas Limit (Max 5):**
  ```cmd
  kubectl apply -f gatekeeper-tests/deployment-violate.yaml
  # Expected: Rejected by validation webhook [max-replicas]
  ```

### 3. Verify Secrets Rotation (ESO)
ESO pulls credentials from a simulated mock store and updates Kubernetes Secrets within 10 seconds:
1. View the current secret value:
   * **PowerShell:**
     ```powershell
     kubectl get secret db-secret -n demo -o go-template='{{.data.password | base64decode}}'
     ```
   * **Command Prompt:**
     ```cmd
     kubectl get secret db-secret -n demo -o go-template="{{.data.password | base64decode}}"
     ```
2. Modify the database password mock store value by editing `eso/secret-store.yaml` (change `value` on line 11). Apply the change:
   ```cmd
   kubectl apply -f eso/secret-store.yaml
   ```
3. Verify the secret rotates automatically within 10 seconds:
   * **PowerShell:**
     ```powershell
     kubectl get secret db-secret -n demo -o go-template='{{.data.password | base64decode}}'
     ```
   * **Command Prompt:**
     ```cmd
     kubectl get secret db-secret -n demo -o go-template="{{.data.password | base64decode}}"
     ```
4. Verify that the api deployment pod was NOT restarted during this secret rotation (Age of pods should remain identical):
   ```cmd
   kubectl get pods -n demo -l app=api
   ```

### 4. Verify Supply Chain Security (Cosign)
Sigstore Policy Controller validates container image signatures using the public key defined in `policies/cluster-image-policy.yaml`.
* Deploying signed payments API workload (`ghcr.io/dvquyet/w10-api:0.0.1` signed by public key):
  ```cmd
  kubectl get deployment payments-api -n payments
  # Expected: Pods should be in Running/Ready state since the signature is valid.
  ```
* Trying to run an unsigned image or an image signed with an untrusted key:
  ```cmd
  kubectl run unsigned-test --image=nginx:1.25.1 -n payments
  # Expected: Rejected by policy-controller validation webhook (failed signature verification).
  ```

### 5. Verify Progressive Delivery (Canary Rollout)
* Watch rollout progress:
  ```cmd
  kubectl get rollout api -n demo -w
  ```
* Watch latest analysis run:
  * **Bash:**
    ```bash
    kubectl get analysisrun -n demo --sort-by=.metadata.creationTimestamp | tail -1
    ```
  * **PowerShell:**
    ```powershell
    kubectl get analysisrun -n demo --sort-by=.metadata.creationTimestamp | Select-Object -Last 1
    ```
  * **Command Prompt (CMD):**
    ```cmd
    kubectl get analysisrun -n demo --sort-by=.metadata.creationTimestamp
    ```
* Query Prometheus metrics:
  * **Bash:**
    ```bash
    kubectl run test-query --image=curlimages/curl:latest --rm -i --restart=Never -n monitoring -- \
      curl -s 'http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=api:success_rate:5m'
    ```
  * **PowerShell / Command Prompt (Windows):**
    ```cmd
    kubectl run test-query --image=curlimages/curl:latest --rm -i --restart=Never -n monitoring -- curl -s "http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=api:success_rate:5m"
    ```

---

## Test Scenarios (GitOps)

### Test 1: Successful Deployment (Success Rate ≥ 90%)
* **Sửa cấu hình:** Mở file `app-api/rollout.yaml` bằng text editor (như VS Code hoặc Notepad) và sửa `ERROR_RATE: "0"`.
* **Commit & Push:**
  ```bash
  git add app-api/rollout.yaml
  git commit -m "test: deploy with 0% error rate"
  git push origin main
  ```
* **Theo dõi trạng thái:**
  ```cmd
  kubectl get analysisrun -n demo -w
  ```

### Test 2: Failed Deployment (Success Rate < 90%)
* **Sửa cấu hình:** Mở file `app-api/rollout.yaml` và sửa `ERROR_RATE: "0.15"`.
* **Commit & Push:**
  ```bash
  git add app-api/rollout.yaml
  git commit -m "test: deploy with 15% error rate (should fail)"
  git push origin main
  ```
* **Theo dõi trạng thái:**
  ```cmd
  kubectl get analysisrun -n demo -w
  kubectl get rollout api -n demo
  ```

### Test 3: Trigger SLO Alert Email
* **Sửa cấu hình:** Mở file `app-api/rollout.yaml` và sửa `ERROR_RATE: "0.10"`.
* **Commit & Push:**
  ```bash
  git add app-api/rollout.yaml
  git commit -m "test: deploy with 10% error rate (90% success)"
  git push origin main
  ```
* Canary pass (≥90%) nhưng SLO alert sẽ bắn email (vì success rate dưới 95%). Đợi 2-3 phút kiểm tra hòm thư.

---

## Cleanup

```cmd
# Delete ArgoCD applications
kubectl delete -f argocd/root.yaml

# Wait for resources to be cleaned up
kubectl get all -n demo
kubectl get all -n monitoring
kubectl get all -n payments

# Delete namespaces
kubectl delete ns argocd
kubectl delete ns external-secrets
kubectl delete ns gatekeeper-system
kubectl delete ns cosign-system

# Stop minikube
minikube stop -p w10
minikube delete -p w10
```

---

## Multi-Tenant Challenge: Onboarding Payments Team

### Câu 1: Vì sao guardrail cũ tự áp dụng cho team B mà không cần viết luật mới?
1. **Gatekeeper Constraints**: Các chính sách bảo mật của Gatekeeper (như chặn chạy dưới quyền root, chặn tag `latest`, yêu cầu cấu hình limits) được áp dụng ở phạm vi toàn cụm (cluster-wide). Trong phần cấu hình `spec.match.excludedNamespaces`, chúng ta chỉ loại trừ các namespace hệ thống (`kube-system`, `argocd`, `monitoring`, `gatekeeper-system`). Do đó, bất kỳ namespace mới nào được tạo ra (bao gồm cả `payments`) đều mặc định chịu sự kiểm soát của các constraint này mà không cần viết thêm luật.
2. **Sigstore / Policy Controller**: Cơ chế xác thực chữ ký số được kích hoạt thông qua việc gắn nhãn (label) `policy.sigstore.dev/include: "true"` lên namespace. Khi namespace `payments` được tạo và gắn nhãn này, Sigstore Admission Webhook sẽ tự động đối chiếu tất cả image triển khai tại đây với `ClusterImagePolicy` đã có sẵn trên cụm, bảo vệ chuỗi cung ứng ứng dụng tự động.

### Câu 2: Role/RoleBinding khác ClusterRoleBinding ra sao để giữ cô lập?
* **Role & RoleBinding**: Là các tài nguyên có phạm vi namespace (namespaced resources). `Role` chỉ định nghĩa các quyền trong phạm vi một namespace nhất định, và `RoleBinding` liên kết ServiceAccount với Role đó trong cùng namespace. Điều này đảm bảo ServiceAccount `payments-dev` của team B chỉ có thể thao tác với các workload trong namespace `payments` và hoàn toàn bị chặn khi cố gắng truy cập tài nguyên của namespace khác (như `demo`).
* **ClusterRoleBinding**: Là tài nguyên phạm vi toàn cụm (cluster-wide resource). Nó liên kết một đối tượng với một `ClusterRole` và cấp quyền trên **tất cả** namespace của cụm. Nếu dùng ClusterRoleBinding, ServiceAccount `payments-dev` sẽ có quyền can thiệp vào tài nguyên của namespace `demo` (hoặc các namespace khác), phá vỡ nguyên lý cô lập đa người dùng (multi-tenant isolation).
