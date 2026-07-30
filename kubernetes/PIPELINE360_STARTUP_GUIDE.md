# Pipeline360 — Startup and Access Guide

This guide explains how to start and access the Pipeline360 environment after restarting the Windows computer.

## Current Local Environment

- Windows 11 with Docker Desktop
- WSL2 Ubuntu
- Kind cluster: `pipeline360-cluster`
- Kubernetes context: `kind-pipeline360-cluster`
- Application namespace: `hotel-system`
- ArgoCD namespace: `argocd`
- Frontend URL: `http://hotel.local:3000`
- Mongo Express URL: `http://localhost:8085`
- ArgoCD URL: `https://localhost:8081`

> The Kind cluster currently maps host port `3000` to port `80` on the Kind control-plane node. Therefore, the application is opened with `:3000`.

---

## 1. Start Docker Desktop

Open **Docker Desktop** in Windows and wait until it displays:

```text
Engine running
```

Do not continue until Docker Desktop is fully running.

---

## 2. Open WSL

Open Ubuntu/WSL from Windows Terminal, or run:

```powershell
wsl
```

Move to the project directory:

```bash
cd ~/Pipeline360
```

---

## 3. Verify the Kubernetes Context

Run:

```bash
kubectl config current-context
```

Expected result:

```text
kind-pipeline360-cluster
```

If another context is active, switch to the Pipeline360 context:

```bash
kubectl config use-context kind-pipeline360-cluster
```

---

## 4. Verify the Kind Cluster

Run:

```bash
kind get clusters
```

Expected cluster:

```text
pipeline360-cluster
```

Check the Kubernetes node:

```bash
kubectl get nodes
```

Expected result:

```text
pipeline360-cluster-control-plane   Ready
```

### If the Kubernetes API is unavailable

Check whether the Kind container exists:

```bash
docker ps -a --filter name=pipeline360-cluster-control-plane
```

If the container exists but is stopped, start it:

```bash
docker start pipeline360-cluster-control-plane
```

Wait approximately 20 seconds and check again:

```bash
kubectl get nodes
```

> Do not delete or recreate the Kind cluster unless the cluster data has been backed up and recreation is intentionally required. Deleting the cluster also deletes the Kubernetes resources, ArgoCD installation, and cluster-local MongoDB storage.

---

## 5. Verify All Application Pods

Run:

```bash
kubectl get pods -n hotel-system
```

The expected healthy state is:

- 5 Backend Pods: `1/1 Running`
- 5 Frontend Pods: `1/1 Running`
- 3 MongoDB Pods: `1/1 Running`
- 1 Mongo Express Pod: `1/1 Running`

For a clearer workload summary, run:

```bash
kubectl get deployments,statefulsets -n hotel-system
```

Expected replica counts:

```text
backend-deployment    5/5
frontend-deployment   5/5
mongo-express         1/1
mongo                 3/3
```

### If Pods are still starting

Wait and watch them:

```bash
kubectl get pods -n hotel-system -w
```

Press `Ctrl+C` when all Pods are ready.

### If a Deployment is unhealthy

Check its rollout status:

```bash
kubectl rollout status deployment/backend-deployment -n hotel-system --timeout=180s
kubectl rollout status deployment/frontend-deployment -n hotel-system --timeout=180s
```

Inspect logs before making changes:

```bash
kubectl logs -n hotel-system deployment/backend-deployment --tail=100
kubectl logs -n hotel-system deployment/frontend-deployment --tail=100
```

Because ArgoCD has self-healing enabled, permanent Kubernetes changes must be committed to Git rather than applied manually with `kubectl set image` or direct manifest edits in the cluster.

---

## 6. Verify ArgoCD Status

Run:

```bash
kubectl get application pipeline360 -n argocd \
-o custom-columns='SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
```

Expected state:

```text
Synced   Healthy
```

If ArgoCD is using stale Git data, request a hard refresh:

```bash
kubectl annotate application pipeline360 \
-n argocd \
argocd.argoproj.io/refresh=hard \
--overwrite
```

Then check its state again after approximately 10 seconds:

```bash
sleep 10
kubectl get application pipeline360 -n argocd \
-o custom-columns='SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
```

> Current environment note: the live ArgoCD Application has been configured to track the `dev` branch. The project assignment describes `main` as the deployment branch. This should be reviewed before final submission.

---

## 7. Verify the Local Hostname

The application Ingress expects this hostname:

```text
hotel.local
```

On Windows, open **Notepad as Administrator** and open:

```text
C:\Windows\System32\drivers\etc\hosts
```

Ensure the following line exists:

```text
127.0.0.1 hotel.local
```

Save the file. Then open PowerShell and clear the Windows DNS cache:

```powershell
ipconfig /flushdns
```

Verify the hostname:

```powershell
ping hotel.local
```

It should resolve to:

```text
127.0.0.1
```

---

## 8. Open the Frontend Application

The Kind cluster maps local port `3000` to the Ingress Controller path.

Open this URL in the Windows browser:

```text
http://hotel.local:3000
```

No `kubectl port-forward` command is required for the frontend.

### Test the Frontend from WSL

```bash
curl -I -H "Host: hotel.local" http://127.0.0.1:3000/
```

Expected result:

```text
HTTP/1.1 200 OK
```

### Test the Backend through the same Ingress

```bash
curl -i -H "Host: hotel.local" \
http://127.0.0.1:3000/api/reservations/hotels
```

Expected result: HTTP `200 OK` with the hotel list in JSON format.

---

## 9. Open Mongo Express

Mongo Express is exposed inside Kubernetes by the ClusterIP service:

```text
mongo-express-service:8081
```

A local port-forward is therefore required.

### Start Mongo Express access in the foreground

```bash
kubectl port-forward service/mongo-express-service \
-n hotel-system \
8085:8081
```

Keep that terminal open and browse to:

```text
http://localhost:8085
```

Stop the foreground port-forward with `Ctrl+C`.

### Start Mongo Express access in the background

First, prevent duplicate port-forwards:

```bash
pkill -f "kubectl port-forward service/mongo-express-service" 2>/dev/null || true
```

Start it in the background:

```bash
nohup kubectl port-forward service/mongo-express-service \
-n hotel-system \
8085:8081 \
> /tmp/pipeline360-mongo-express.log 2>&1 &
```

Verify it:

```bash
ss -ltnp | grep ':8085'
cat /tmp/pipeline360-mongo-express.log
```

Open:

```text
http://localhost:8085
```

> Mongo Express currently has basic authentication disabled. Keep it local and do not expose it publicly without adding authentication and storing credentials in a Kubernetes Secret.

---

## 10. Open the ArgoCD Web Interface

ArgoCD is exposed inside Kubernetes by the `argocd-server` service. Start a port-forward.

### Start ArgoCD access in the foreground

```bash
kubectl port-forward service/argocd-server \
-n argocd \
8081:443
```

Keep that terminal open and browse to:

```text
https://localhost:8081
```

The browser may display a local certificate warning. For this local environment, continue to the site.

### Start ArgoCD access in the background

First, prevent duplicate port-forwards:

```bash
pkill -f "kubectl port-forward service/argocd-server" 2>/dev/null || true
```

Start it in the background:

```bash
nohup kubectl port-forward service/argocd-server \
-n argocd \
8081:443 \
> /tmp/pipeline360-argocd.log 2>&1 &
```

Verify it:

```bash
ss -ltnp | grep ':8081'
cat /tmp/pipeline360-argocd.log
```

Open:

```text
https://localhost:8081
```

### Retrieve the Initial ArgoCD Admin Password

Username:

```text
admin
```

Retrieve the initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
-o jsonpath='{.data.password}' | base64 -d; echo
```

If the initial secret no longer exists, use the password that was previously configured for the `admin` account.

---

## 11. Start Both Web Port-Forwards Together

Use these commands after every restart to open Mongo Express and ArgoCD in the background:

```bash
pkill -f "kubectl port-forward service/mongo-express-service" 2>/dev/null || true
pkill -f "kubectl port-forward service/argocd-server" 2>/dev/null || true

nohup kubectl port-forward service/mongo-express-service \
-n hotel-system \
8085:8081 \
> /tmp/pipeline360-mongo-express.log 2>&1 &

nohup kubectl port-forward service/argocd-server \
-n argocd \
8081:443 \
> /tmp/pipeline360-argocd.log 2>&1 &
```

Verify both ports:

```bash
ss -ltnp | grep -E ':8081|:8085'
```

Then open:

```text
Frontend:      http://hotel.local:3000
Mongo Express: http://localhost:8085
ArgoCD:        https://localhost:8081
```

---

## 12. Quick Startup Checklist

After restarting the computer:

```bash
cd ~/Pipeline360

kubectl config use-context kind-pipeline360-cluster
kubectl get nodes
kubectl get pods -n hotel-system
kubectl get application pipeline360 -n argocd

pkill -f "kubectl port-forward service/mongo-express-service" 2>/dev/null || true
pkill -f "kubectl port-forward service/argocd-server" 2>/dev/null || true

nohup kubectl port-forward service/mongo-express-service \
-n hotel-system \
8085:8081 \
> /tmp/pipeline360-mongo-express.log 2>&1 &

nohup kubectl port-forward service/argocd-server \
-n argocd \
8081:443 \
> /tmp/pipeline360-argocd.log 2>&1 &

ss -ltnp | grep -E ':8081|:8085'
```

Open in the browser:

```text
http://hotel.local:3000
http://localhost:8085
https://localhost:8081
```

---

## Troubleshooting

### `The connection to the server ... was refused`

1. Confirm Docker Desktop is running.
2. Check the Kind container:

```bash
docker ps -a --filter name=pipeline360-cluster-control-plane
```

3. Start it if necessary:

```bash
docker start pipeline360-cluster-control-plane
```

4. Verify the context and node:

```bash
kubectl config use-context kind-pipeline360-cluster
kubectl get nodes
```

### Frontend URL does not open

Verify the Kind port mapping:

```bash
docker inspect pipeline360-cluster-control-plane \
--format '{{json .HostConfig.PortBindings}}'
```

The current environment should contain a mapping similar to:

```text
Host 127.0.0.1:3000 -> Kind node port 80
```

Check the Ingress and controller:

```bash
kubectl get ingress -n hotel-system
kubectl get pods -n ingress-nginx
```

Test the request directly:

```bash
curl -I -H "Host: hotel.local" http://127.0.0.1:3000/
```

### Mongo Express or ArgoCD port is already in use

Identify the process:

```bash
ss -ltnp | grep -E ':8081|:8085'
ps -ef | grep "kubectl port-forward"
```

Stop only the relevant port-forward and restart it. Avoid killing unrelated processes.

### Check background port-forward logs

```bash
cat /tmp/pipeline360-mongo-express.log
cat /tmp/pipeline360-argocd.log
```

### Check ArgoCD-managed application health

```bash
kubectl get application pipeline360 -n argocd \
-o custom-columns='SYNC:.status.sync.status,HEALTH:.status.health.status,REVISION:.status.sync.revision'
```

### Check Backend readiness

```bash
kubectl get pods -n hotel-system -l app=backend
kubectl logs -n hotel-system deployment/backend-deployment --tail=100
```

### Check Frontend readiness

```bash
kubectl get pods -n hotel-system -l app=frontend
kubectl logs -n hotel-system deployment/frontend-deployment --tail=100
```
