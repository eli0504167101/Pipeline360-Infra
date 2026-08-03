# Pipeline360 Infrastructure

## Overview

The `infra-repo` directory contains the Kubernetes and Argo CD configuration used to deploy and operate Pipeline360.

The infrastructure follows GitOps principles:

- Kubernetes manifests define the desired application state.
- GitHub Actions updates versioned container image tags.
- Deployment changes are reviewed through Pull Requests.
- Argo CD monitors the `main` branch and synchronizes the cluster automatically.

---

## Infrastructure Stack

- Kubernetes
- Kind
- Argo CD
- NGINX Ingress Controller
- MongoDB StatefulSet
- Mongo Express
- Persistent Volume Claims
- ConfigMaps
- Kubernetes Secrets
- GitHub Actions
- Docker Hub

---

## Directory Structure

```text
infra-repo/
├── argocd/
│   ├── application.yaml
│   ├── backend-app.yaml
│   ├── frontend-app.yaml
│   └── platform-app.yaml
│
└── kubernetes/
    ├── backend/
    │   ├── deployment.yaml
    │   └── service.yaml
    │
    ├── frontend/
    │   ├── deployment.yaml
    │   └── service.yaml
    │
    ├── platform/
    │   ├── app-config.yaml
    │   ├── hotel-ingress.yaml
    │   ├── mongo-express.yaml
    │   ├── mongo-headless-service.yaml
    │   ├── mongo-service.yaml
    │   ├── mongo-statefulset.yaml
    │   └── namespace.yaml
    │
    ├── config/
    │   └── db.js
    │
    └── secrets/
        └── db-secrets.yaml.template
```

> `infra-repo/argocd/application.yaml` is the previous single-Application definition.  
> The active architecture uses the three separate Argo CD Applications described below.

---

## Kubernetes Namespace

Pipeline360 runs in the dedicated namespace:

```text
hotel-system
```

Namespace manifest:

```text
infra-repo/kubernetes/platform/namespace.yaml
```

Verify it with:

```bash
kubectl get namespace hotel-system
```

---

## Backend Resources

Managed from:

```text
infra-repo/kubernetes/backend/
```

Resources:

- `backend-deployment`
- `backend-service`

Desired replicas:

```text
5
```

Container port and Service port:

```text
3000
```

The Deployment uses:

- `/health` for liveness
- `/ready` for readiness
- `MONGO_URL` from the `app-config` ConfigMap
- `MONGO_URL` from the `app-config` ConfigMap
- Mongo Express Basic Authentication credentials from the
  `mongo-express-auth` Secret

Verify:

```bash
kubectl get deployment backend-deployment -n hotel-system
kubectl get service backend-service -n hotel-system
kubectl get pods -n hotel-system -l app=backend
```

---

## Frontend Resources

Managed from:

```text
infra-repo/kubernetes/frontend/
```

Resources:

- `frontend-deployment`
- `frontend-service`

Desired replicas:

```text
5
```

Container port:

```text
80
```

The frontend Deployment uses `/index.html` for readiness and liveness probes.

Verify:

```bash
kubectl get deployment frontend-deployment -n hotel-system
kubectl get service frontend-service -n hotel-system
kubectl get pods -n hotel-system -l app=frontend
```

---

## MongoDB Replica Set

MongoDB is deployed as a StatefulSet:

```text
infra-repo/kubernetes/platform/mongo-statefulset.yaml
```

StatefulSet name:

```text
mongo
```

Replica count:

```text
3
```

Expected Pods:

```text
mongo-0
mongo-1
mongo-2
```

MongoDB is started with:

```text
--replSet rs0
--bind_ip_all
```

Verify the StatefulSet:

```bash
kubectl get statefulset mongo -n hotel-system
```

Verify the Pods:

```bash
kubectl get pods -n hotel-system -l app=mongo
```

Check replica-set members:

```bash
kubectl exec -n hotel-system mongo-0 -- \
  mongosh --quiet --eval \
  'rs.status().members.map(member => ({
    name: member.name,
    state: member.stateStr
  }))'
```

Expected state:

- One `PRIMARY`
- Two `SECONDARY`

---

## Persistent Storage

Each MongoDB replica receives its own Persistent Volume Claim through the StatefulSet `volumeClaimTemplates`.

Expected PVCs:

```text
mongo-storage-mongo-0
mongo-storage-mongo-1
mongo-storage-mongo-2
```

Storage request per replica:

```text
1Gi
```

Access mode:

```text
ReadWriteOnce
```

Verify:

```bash
kubectl get pvc -n hotel-system
```

All three claims should be:

```text
Bound
```

Do not delete MongoDB PVCs without a verified backup and recovery plan.

---

## MongoDB Services

### Headless Service

Manifest:

```text
infra-repo/kubernetes/platform/mongo-headless-service.yaml
```

Resource:

```text
mongo-headless
```

Purpose:

- Stable StatefulSet DNS names
- MongoDB replica-set communication
- Direct addressing of `mongo-0`, `mongo-1`, and `mongo-2`

### Application Service

Manifest:

```text
infra-repo/kubernetes/platform/mongo-service.yaml
```

Resource:

```text
mongo
```

Purpose:

- Backend access to MongoDB through a stable Kubernetes Service name

Service port:

```text
27017
```

---

## Mongo Express

Manifest:

```text
infra-repo/kubernetes/platform/mongo-express.yaml
```

Resources:

- Deployment: `mongo-express`
- Service: `mongo-express-service`

Desired replicas:

```text
1
```

Service port:

```text
8081
```

Mongo Express connects to the MongoDB replica set using the internal StatefulSet DNS names.

Verify:

```bash
kubectl get deployment mongo-express -n hotel-system
kubectl get service mongo-express-service -n hotel-system
kubectl get pods -n hotel-system -l app=mongo-express
```

---

## ConfigMap

Manifest:

```text
infra-repo/kubernetes/platform/app-config.yaml
```

Resource name:

```text
app-config
```

Current configuration includes:

```text
environment
mongo-url
```

Verify keys without printing secret values:

```bash
kubectl get configmap app-config -n hotel-system
```

The backend reads `MONGO_URL` from the `mongo-url` key.

---

## Secret Management

Template:

```text
infra-repo/kubernetes/secrets/db-secrets.yaml.template
```

Live Secret used by Mongo Express:

```text
mongo-express-auth
```

Expected keys:

```text
username
password
```

The Secret protects access to the Mongo Express web interface through Basic
Authentication.

MongoDB internal database authentication is not enabled in the current local
Kind environment. The Backend connects using `MONGO_URL` from the `app-config`
ConfigMap.

Real credentials must not be committed to Git.

Verify that the Secret exists without displaying its values:

```bash
kubectl get secret mongo-express-auth -n hotel-system
```

Verify the expected key names:

```bash
kubectl get secret mongo-express-auth \
  -n hotel-system \
  -o go-template='{{range $key, $value := .data}}{{printf "%s\n" $key}}{{end}}'
```

Do not print, decode, or commit real secret values.

## NGINX Ingress

Manifest:

```text
infra-repo/kubernetes/platform/hotel-ingress.yaml
```

Ingress resource:

```text
hotel-ingress
```

Ingress class:

```text
nginx
```

Routes:

```text
hotel.local/       → frontend-service:80
hotel.local/api    → backend-service:3000
mongo.hotel.local/ → mongo-express-service:8081
```

Verify:

```bash
kubectl get ingress -n hotel-system
kubectl describe ingress hotel-ingress -n hotel-system
```

In the current Kind environment, access is available through:

```text
http://hotel.local:3000
http://mongo.hotel.local:3000
```

Windows hosts-file entries:

```text
127.0.0.1 hotel.local
127.0.0.1 mongo.hotel.local
```

---

## Argo CD Applications

Pipeline360 uses three separate Argo CD Applications.

### Backend Application

Manifest:

```text
infra-repo/argocd/backend-app.yaml
```

Application:

```text
pipeline360-backend
```

Managed path:

```text
infra-repo/kubernetes/backend
```

### Frontend Application

Manifest:

```text
infra-repo/argocd/frontend-app.yaml
```

Application:

```text
pipeline360-frontend
```

Managed path:

```text
infra-repo/kubernetes/frontend
```

### Platform Application

Manifest:

```text
infra-repo/argocd/platform-app.yaml
```

Application:

```text
pipeline360-platform
```

Managed path:

```text
infra-repo/kubernetes/platform
```

All three Applications use:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

Check their state:

```bash
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Expected state:

```text
NAME                   SYNC     HEALTH
pipeline360-backend    Synced   Healthy
pipeline360-frontend   Synced   Healthy
pipeline360-platform   Synced   Healthy
```

---

## CI/CD Integration

The infrastructure manifests are updated automatically by:

```text
.github/workflows/deploy-prep.yaml
```

After the CI Pipeline successfully builds and pushes new images, Deployment Preparation:

1. Checks out `main`
2. Updates the Backend image tag
3. Updates the Frontend image tag
4. Creates a deployment branch
5. Commits the manifest changes
6. Pushes the branch
7. Opens a Pull Request to `main`

Updated manifests:

```text
infra-repo/kubernetes/backend/deployment.yaml
infra-repo/kubernetes/frontend/deployment.yaml
```

After review and merge, Argo CD synchronizes the corresponding Applications.

---

## Deployment Verification

Check all Applications:

```bash
kubectl get applications -n argocd
```

Check Deployments and StatefulSets:

```bash
kubectl get deployments,statefulsets -n hotel-system
```

Check Pods:

```bash
kubectl get pods -n hotel-system
```

Check Services:

```bash
kubectl get services -n hotel-system
```

Check storage:

```bash
kubectl get pvc -n hotel-system
```

Check Ingress:

```bash
kubectl get ingress -n hotel-system
```

Check active container images:

```bash
kubectl get deployment backend-deployment frontend-deployment \
  -n hotel-system \
  -o custom-columns='NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas,DESIRED:.spec.replicas'
```

---

## Manifest Validation

Validate all Kubernetes manifests without changing the cluster:

```bash
kubectl apply \
  --dry-run=client \
  --recursive \
  -f infra-repo/kubernetes/
```

Validate the Argo CD Application manifests:

```bash
kubectl apply \
  --dry-run=client \
  -f infra-repo/argocd/backend-app.yaml

kubectl apply \
  --dry-run=client \
  -f infra-repo/argocd/frontend-app.yaml

kubectl apply \
  --dry-run=client \
  -f infra-repo/argocd/platform-app.yaml
```

---

## GitOps Operating Rules

For routine changes:

1. Modify files on `dev`.
2. Validate the manifests.
3. Commit only the intended files.
4. Push to `dev`.
5. Allow the CI Pipeline to complete.
6. Review the generated deployment Pull Request.
7. Merge approved changes into `main`.
8. Verify Argo CD health and synchronization.

Avoid routine live changes such as:

```text
kubectl set image
kubectl edit
kubectl apply
```

Changes made directly in the cluster may be reverted by Argo CD self-healing.

Do not use destructive operations without a verified recovery plan:

```text
kubectl delete pvc
kubectl delete namespace hotel-system
git push --force
git reset --hard
```

---

## Related Documentation

- `../README.md`
- `../PIPELINE360_STARTUP_GUIDE.md`
- `../backend-repo/README.md`
- `../frontend-repo/README.md`