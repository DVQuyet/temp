# W10 - Progressive Delivery with Analysis

GitOps setup for API deployment với Argo Rollouts + AnalysisTemplate.

## Concept

Deploy API với **canary strategy** và **automated analysis**:
- Rollout: 10% → 50% → 100%
- AnalysisTemplate query Prometheus để check success rate ≥ 95%
- Auto rollback nếu analysis fail
- AlertManager gửi email khi có SLO violation

## Requirements

- Docker Desktop
- kubectl
- minikube
- git

## Structure

```
w10/
├── app-api/              # API Rollout manifests
│   ├── rollout.yaml      # Argo Rollout với canary strategy
│   ├── service.yaml      # Service expose API
│   └── servicemonitor.yaml # Prometheus metrics scraper
├── app-analysis/         # Analysis manifests
│   └── analysis-template.yaml # Template phân tích success rate
├── app-alert/            # Alert manifests
│   ├── prometheus-rules.yaml # PrometheusRule cho SLO alerts
│   ├── email-secret.yaml # Gmail password (NOT COMMITTED)
│   └── README.md         # Alert setup guide
├── app-common/           # Common resources
│   └── demo-namespace.yaml # Namespace demo
├── src/                  # Source code
│   └── api/              # Flask API application
├── argocd/
│   ├── apps/             # ArgoCD Application manifests
│   │   ├── app-api.yaml  # Deploy API Rollout
│   │   ├── app-analysis.yaml # Deploy AnalysisTemplate
│   │   ├── app-alert.yaml # Deploy PrometheusRule
│   │   ├── app-common.yaml # Deploy common resources
│   │   ├── k8s-prometheus.yaml # Prometheus + AlertManager
│   │   └── k8s-rollout.yaml # Argo Rollouts controller
│   └── root.yaml         # App of Apps pattern
└── README.md
```

## Quick Start

### 1. Setup Cluster
```bash
minikube start -p w10 --driver=docker
kubectl config use-context w10
```

### 2. Install ArgoCD
```bash
kubectl create ns argocd
kubectl apply --server-side -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server
```

### 3. Access ArgoCD UI
```bash
# Port forward
kubectl -n argocd port-forward svc/argocd-server 8080:443 &

# Get password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 4. Deploy App of Apps
```bash
kubectl apply -f argocd/root.yaml
```

### 5. Setup Email Alert (Optional)
```bash
# Follow instructions in app-alert/README.md
cp app-alert/email-secret.yaml.example app-alert/email-secret.yaml
kubectl apply -f app-alert/email-secret.yaml
```

## Components

### Core
- **Argo Rollouts**: Progressive delivery controller
- **Prometheus Stack**: Metrics collection + AlertManager
- **API**: Flask application với metrics endpoint

### GitOps Applications
- `app-api`: API Rollout với canary strategy
- `app-analysis`: AnalysisTemplate cho automated validation
- `app-alert`: PrometheusRule cho runtime alerting
- `app-common`: Shared resources (namespace)
- `k8s-prometheus`: Monitoring stack
- `k8s-rollout`: Argo Rollouts controller

## Verify Deployment

### Check Rollout Status
```bash
# Watch rollout progress
kubectl get rollout api -n demo -w

# Check current state
kubectl get rollout api -n demo

# Check pods
kubectl get pods -n demo -l app=api
```

### Check AnalysisRun
```bash
# List analysis runs
kubectl get analysisrun -n demo

# Watch latest analysis
kubectl get analysisrun -n demo --sort-by=.metadata.creationTimestamp | tail -1

# Describe for detailed metrics
kubectl describe analysisrun -n demo <name>
```

### Query Prometheus Metrics
```bash
# Success rate metric
kubectl run test-query --image=curlimages/curl:latest --rm -i --restart=Never -n monitoring -- \
  curl -s 'http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/query?query=api:success_rate:5m'
```

## Test Scenarios (GitOps)

### Test 1: Successful Deployment (Success Rate ≥ 90%)
```bash
# Edit rollout to deploy with no errors
nano app-api/rollout.yaml
# Set: ERROR_RATE: "0"

git add app-api/rollout.yaml
git commit -m "test: deploy with 0% error rate"
git push origin main

# Watch AnalysisRun succeed
kubectl get analysisrun -n demo -w
```

### Test 2: Failed Deployment (Success Rate < 90%)
```bash
# Edit rollout to deploy with 15% error rate
nano app-api/rollout.yaml
# Set: ERROR_RATE: "0.15"

git add app-api/rollout.yaml
git commit -m "test: deploy with 15% error rate (should fail)"
git push origin main

# Watch AnalysisRun fail and auto rollback
kubectl get analysisrun -n demo -w
kubectl get rollout api -n demo
```

### Test 3: Trigger SLO Alert Email
```bash
# Edit rollout to set 10% error rate (triggers alert, but passes canary)
nano app-api/rollout.yaml
# Set: ERROR_RATE: "0.10"

git add app-api/rollout.yaml
git commit -m "test: deploy with 10% error rate (90% success)"
git push origin main

# Canary passes (≥90%) but SLO alert fires (below 95%)
# Wait 2-3 minutes, then check email inbox
```


## Configuration Reference

### Sync Waves
ArgoCD applications deploy in order:
- Wave -1: `app-common` (namespace)
- Wave 0: `k8s-prometheus`, `k8s-rollout` (infrastructure)
- Wave 1: `app-analysis`, `app-alert` (configuration)
- Wave 2: `app-api` (application)

## Cleanup

```bash
# Delete ArgoCD applications
kubectl delete -f argocd/root.yaml

# Wait for resources to be cleaned up
kubectl get all -n demo
kubectl get all -n monitoring

# Delete ArgoCD
kubectl delete ns argocd

# Stop minikube
minikube stop -p w10
minikube delete -p w10
```

## Multi-Tenant Challenge: Onboarding Payments Team

### Câu 1: Vì sao guardrail cũ tự áp dụng cho team B mà không cần viết luật mới?
1. **Gatekeeper Constraints**: Các chính sách bảo mật của Gatekeeper (như chặn chạy dưới quyền root, chặn tag `latest`, yêu cầu cấu hình limits) được áp dụng ở phạm vi toàn cụm (cluster-wide). Trong phần cấu hình `spec.match.excludedNamespaces`, chúng ta chỉ loại trừ các namespace hệ thống (`kube-system`, `argocd`, `monitoring`, `gatekeeper-system`). Do đó, bất kỳ namespace mới nào được tạo ra (bao gồm cả `payments`) đều mặc định chịu sự kiểm soát của các constraint này mà không cần viết thêm luật.
2. **Sigstore / Policy Controller**: Cơ chế xác thực chữ ký số được kích hoạt thông qua việc gắn nhãn (label) `policy.sigstore.dev/include: "true"` lên namespace. Khi namespace `payments` được tạo và gắn nhãn này, Sigstore Admission Webhook sẽ tự động đối chiếu tất cả image triển khai tại đây với `ClusterImagePolicy` đã có sẵn trên cụm, bảo vệ chuỗi cung ứng ứng dụng tự động.

### Câu 2: Role/RoleBinding khác ClusterRoleBinding ra sao để giữ cô lập?
* **Role & RoleBinding**: Là các tài nguyên có phạm vi namespace (namespaced resources). `Role` chỉ định nghĩa các quyền trong phạm vi một namespace nhất định, và `RoleBinding` liên kết ServiceAccount với Role đó trong cùng namespace. Điều này đảm bảo ServiceAccount `payments-dev` của team B chỉ có thể thao tác với các workload trong namespace `payments` và hoàn toàn bị chặn khi cố gắng truy cập tài nguyên của namespace khác (như `demo`).
* **ClusterRoleBinding**: Là tài nguyên phạm vi toàn cụm (cluster-wide resource). Nó liên kết một đối tượng với một `ClusterRole` và cấp quyền trên **tất cả** namespace của cụm. Nếu dùng ClusterRoleBinding, ServiceAccount `payments-dev` sẽ có quyền can thiệp vào tài nguyên của namespace `demo` (hoặc các namespace khác), phá vỡ nguyên lý cô lập đa người dùng (multi-tenant isolation).

