# start-labs.ps1
# Script tu dong hoa khoi dong Minikube, kiem tra trang thai ArgoCD va mo ket noi.

$ErrorActionPreference = "Stop"

Write-Host "=== KHOI DONG MOI TRUONG LAB KUBERNETES ===" -ForegroundColor Cyan

# 1. Khoi dong Minikube
Write-Host "[1/3] Dang khoi dong Minikube (Profile: w10)..." -ForegroundColor Yellow
minikube start -p w10 --driver=docker
kubectl config use-context w10

# 2. Kiem tra xem ArgoCD da duoc cai dat chua
$nsExists = kubectl get ns argocd --ignore-not-found
if (-not $nsExists) {
    Write-Host "[2/3] Khong tim thay ArgoCD. Bat dau cai dat moi..." -ForegroundColor Yellow
    kubectl create ns argocd
    kubectl apply --server-side -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    Write-Host "Dang cho ArgoCD Server san sang..." -ForegroundColor Yellow
    kubectl -n argocd rollout status deploy/argocd-server
    
    Write-Host "Dang trien khai Root Application (App of Apps)..." -ForegroundColor Yellow
    kubectl apply -f argocd/root.yaml
} else {
    Write-Host "[2/3] ArgoCD da duoc cai dat tu truoc! Bo qua buoc cai dat lai." -ForegroundColor Green
}

# 3. Lay thong tin mat khau admin cua ArgoCD
$pwd = kubectl -n argocd get secret argocd-initial-admin-secret -o go-template='{{.data.password | base64decode}}' 2>$null

# 4. Don dep cac tien trinh kubectl dang chay ngam de tranh xung dot
Write-Host "Dang don dep cac tien trinh port-forward cu..." -ForegroundColor Yellow
Get-Process -Name "kubectl" -ErrorAction SilentlyContinue | Stop-Process -Force

# 5. Tim port hop le va con trong (bat dau tu 8080)
function Get-FreePort {
    param (
        [int]$startPort = 8080
    )
    $port = $startPort
    while ($port -lt 65535) {
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $port)
        try {
            $listener.Start()
            $listener.Stop()
            return $port
        }
        catch {
            $port++
        }
    }
    return 8080
}

$port = Get-FreePort -startPort 8080

if ($pwd) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Thong tin dang nhap ArgoCD:" -ForegroundColor White
    Write-Host "- URL: https://localhost:$port" -ForegroundColor Green
    Write-Host "- Username: admin" -ForegroundColor Green
    Write-Host "- Password: $pwd" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Cyan
}

# 6. Tu dong giu ket noi Port-Forwarding
Write-Host "[3/3] Dang mo ket noi Port-Forwarding toi ArgoCD..." -ForegroundColor Yellow
Write-Host "Ban co the truy cap ArgoCD tai dia chi: https://localhost:$port" -ForegroundColor Green
Write-Host "Nhan Ctrl+C trong cua so nay de tat ket noi." -ForegroundColor Red

while ($true) {
    try {
        kubectl -n argocd port-forward svc/argocd-server "${port}:443"
    }
    catch {
        Write-Host "Ket noi bi gian doan, dang thu lai sau 2 giay..." -ForegroundColor Red
        Start-Sleep -Seconds 2
    }
}
