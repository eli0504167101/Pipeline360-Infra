# Pipeline360 Infrastructure

Infrastructure, Kubernetes and GitOps repository for the Pipeline360 hotel reservation platform.

Pipeline360 is implemented across three independent Git repositories:

| Repository | Responsibility |
|---|---|
| [Pipeline360-Frontend](https://github.com/eli0504167101/Pipeline360-Frontend) | Browser application, NGINX container and frontend CI |
| [Pipeline360-Backend](https://github.com/eli0504167101/Pipeline360-Backend) | Node.js REST API, Docker image and backend CI |
| [Pipeline360-Infra](https://github.com/eli0504167101/Pipeline360-Infra) | Kubernetes manifests, Argo CD applications and GitOps deployment state |

> [!IMPORTANT]
> `main` represents the production state. Development changes are made on `dev` and merged through reviewed Pull Requests.

---

## Table of Contents

- [Architecture](#architecture)
- [GitOps Deployment Flow](#gitops-deployment-flow)
- [Technology Stack](#technology-stack)
- [Repository Structure](#repository-structure)
- [Kubernetes Resources](#kubernetes-resources)
- [Argo CD](#argo-cd)
- [CI/CD Integration](#cicd-integration)
- [Image Versioning](#image-versioning)
- [Secrets and Configuration](#secrets-and-configuration)
- [Local Access](#local-access)
- [Startup and Verification](#startup-and-verification)
- [Manifest Validation](#manifest-validation)
- [Git Workflow](#git-workflow)
- [Recovery and Safety](#recovery-and-safety)
- [Related Repositories](#related-repositories)

---

## Architecture

![Pipeline360 Architecture](docs/architecture.png)

Pipeline360 uses a three-tier architecture:

```text
Browser
   |
   v
NGINX Ingress
   |
   +--------------------+
   |                    |
   v                    v
Frontend Service     Backend Service
   |                    |
   v                    v
Frontend Pods        Backend Pods
                         |
                         v
                MongoDB Replica Set
```

The delivery architecture is GitOps based:

```text
Developer
   |
   v
Push to application dev branch
   |
   v
GitHub Actions validation and Docker build
   |
   v
Docker Hub versioned image
   |
   v
Automated Pull Request to Pipeline360-Infra
   |
   v
Review and merge to main
   |
   v
Argo CD detects the desired-state change
   |
   v
Kubernetes RollingUpdate
```

---

## GitOps Deployment Flow

### Frontend

```text
Pipeline360-Frontend/dev
        |
        v
Frontend CI
        |
        +--> Validate JavaScript and required files
        |
        +--> Build and push hotel-frontend:frontend-N
        |
        v
Pull Request updates:
kubernetes/frontend/deployment.yaml
```

### Backend

```text
Pipeline360-Backend/dev
        |
        v
Backend CI
        |
        +--> Validate Node.js source and required files
        |
        +--> Build and push hotel-backend:backend-N
        |
        v
Pull Request updates:
kubernetes/backend/deployment.yaml
```

After the deployment Pull Request is reviewed and merged into `main`, Argo CD automatically synchronizes the corresponding application.

---

## Technology Stack

| Area | Technology |
|---|---|
| Frontend | HTML, CSS, JavaScript, NGINX |
| Backend | Node.js, Express, Mongoose |
| Database | MongoDB Replica Set |
| Database UI | Mongo Express |
| Containerization | Docker |
| Container Registry | Docker Hub |
| Orchestration | Kubernetes |
| Local Cluster | Kind |
| Ingress | NGINX Ingress Controller |
| CI/CD | GitHub Actions |
| GitOps | Argo CD |
| Development Environment | Windows, WSL2 Ubuntu, Docker Desktop, VS Code |

---

## Repository Structure

```text
Pipeline360-Infra/
├── argocd/
│   ├── backend-app.yaml
│   ├── frontend-app.yaml
│   ├── platform-app.yaml
│   └── crds/
│       └── applicationsets-crd-v3.4.5.yaml
│
├── docs/
│   ├── architecture.png
│   └── architecture.drawio
│
├── kubernetes/
│   ├── backend/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   │
│   ├── frontend/
│   │   ├── deployment.yaml
│   │   └── service.yaml
│   │
│   ├── platform/
│   │   ├── app-config.yaml
│   │   ├── hotel-ingress.yaml
│   │   ├── mongo-express.yaml
│   │   ├── mongo-headless-service.yaml
│   │   ├── mongo-service.yaml
│   │   ├── mongo-statefulset.yaml
│   │   └── namespace.yaml
│   │
│   ├── config/
│   │   └── db.js
│   │
│   └── secrets/
│       └── db-secrets.yaml.template
│
└── README.md
```

---

## Kubernetes Resources

Pipeline360 runs in the dedicated namespace:

```text
hotel-system
```

### Application workloads

| Resource | Name | Desired State |
|---|---|---:|
| Frontend Deployment | `frontend-deployment` | 5 replicas |
| Backend Deployment | `backend-deployment` | 5 replicas |
| MongoDB StatefulSet | `mongo` | 3 replicas |
| Mongo Express Deployment | `mongo-express` | 1 replica |

### Services

| Service | Port | Purpose |
|---|---:|---|
| `frontend-service` | 80 | Frontend access |
| `backend-service` | 3000 | Backend API |
| `mongo` | 27017 | Stable MongoDB service |
| `mongo-headless` | 27017 | Replica-set pod discovery |
| `mongo-express-service` | 8081 | Database administration UI |

### MongoDB persistent storage

The MongoDB StatefulSet creates one PVC per replica:

```text
mongo-storage-mongo-0
mongo-storage-mongo-1
mongo-storage-mongo-2
```

Each claim requests:

```text
1Gi
ReadWriteOnce
```

Verify:

```bash
kubectl get statefulset mongo -n hotel-system
kubectl get pods -n hotel-system -l app=mongo
kubectl get pvc -n hotel-system
```

Expected replica-set state:

```text
PRIMARY
SECONDARY
SECONDARY
```

Check it with:

```bash
kubectl exec -n hotel-system mongo-0 -- \
  mongosh --quiet --eval \
  'rs.status().members.map(member => ({
    name: member.name,
    state: member.stateStr,
    health: member.health
  }))'
```

---

## Argo CD

Argo CD runs in the dedicated namespace:

```text
argocd
```

Pipeline360 uses three independent Argo CD Applications:

| Application | Repository Path | Responsibility |
|---|---|---|
| `pipeline360-frontend` | `kubernetes/frontend` | Frontend Deployment and Service |
| `pipeline360-backend` | `kubernetes/backend` | Backend Deployment and Service |
| `pipeline360-platform` | `kubernetes/platform` | Namespace, MongoDB, Mongo Express, ConfigMap and Ingress |

All Applications monitor:

```text
Repository: Pipeline360-Infra
Revision: main
```

The Applications use automated synchronization:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

Verify:

```bash
kubectl get applications -n argocd \
  -o custom-columns='NAME:.metadata.name,REPO:.spec.source.repoURL,PATH:.spec.source.path,SYNC:.status.sync.status,HEALTH:.status.health.status'
```

Expected state:

```text
pipeline360-backend    Synced   Healthy
pipeline360-frontend   Synced   Healthy
pipeline360-platform   Synced   Healthy
```

### ApplicationSet CRD

The ApplicationSet CRD required by the installed Argo CD controller is stored at:

```text
argocd/crds/applicationsets-crd-v3.4.5.yaml
```

Install it during Argo CD bootstrap with:

```bash
kubectl apply \
  --server-side \
  --force-conflicts \
  -f argocd/crds/applicationsets-crd-v3.4.5.yaml
```

Verify:

```bash
kubectl get crd applicationsets.argoproj.io
kubectl api-resources | grep -i applicationset
```

---

## CI/CD Integration

Application delivery starts from the Frontend or Backend repository.

Each application workflow:

1. Runs on a push to `dev`.
2. Validates the application.
3. Builds a Docker image.
4. Pushes a versioned image and `latest` to Docker Hub.
5. Checks out `Pipeline360-Infra/main`.
6. Updates only its own Deployment manifest.
7. Creates a deployment branch.
8. Opens a Pull Request to `Pipeline360-Infra/main`.
9. Requires review and merge.
10. Allows Argo CD to deploy the approved desired state.

The Frontend workflow updates only:

```text
kubernetes/frontend/deployment.yaml
```

The Backend workflow updates only:

```text
kubernetes/backend/deployment.yaml
```

No application workflow writes directly to `main`.

---

## Image Versioning

Docker Hub repositories:

```text
eli0504167101/hotel-frontend
eli0504167101/hotel-backend
```

Frontend image tags:

```text
frontend-N
latest
```

Backend image tags:

```text
backend-N
latest
```

The Kubernetes manifests use immutable versioned tags rather than `latest`.

Check active images:

```bash
kubectl get deployment \
  frontend-deployment \
  backend-deployment \
  -n hotel-system \
  -o custom-columns='DEPLOYMENT:.metadata.name,IMAGE:.spec.template.spec.containers[0].image,READY:.status.readyReplicas,DESIRED:.spec.replicas'
```

---

## Secrets and Configuration

### ConfigMap

The Backend receives `MONGO_URL` from:

```text
ConfigMap: app-config
Key: mongo-url
```

Verify:

```bash
kubectl get configmap app-config -n hotel-system
```

### Mongo Express authentication

Mongo Express Basic Authentication uses:

```text
Secret: mongo-express-auth
Keys:
  username
  password
```

Verify only that the Secret exists:

```bash
kubectl get secret mongo-express-auth -n hotel-system
```

> [!WARNING]
> Never commit live passwords, Personal Access Tokens, Docker Hub tokens or decoded Kubernetes Secret values.

The repository includes a template only:

```text
kubernetes/secrets/db-secrets.yaml.template
```

MongoDB internal authentication is not enabled in the current local Kind environment.

---

## Local Access

The NGINX Ingress routes:

```text
hotel.local/       -> frontend-service:80
hotel.local/api    -> backend-service:3000
mongo.hotel.local/ -> mongo-express-service:8081
```

Windows hosts file:

```text
C:\Windows\System32\drivers\etc\hosts
```

Required entries:

```text
127.0.0.1 hotel.local
127.0.0.1 mongo.hotel.local
```

Current Kind access:

```text
http://hotel.local:3000
http://mongo.hotel.local:3000
```

Argo CD can be accessed using:

```bash
kubectl port-forward \
  svc/argocd-server \
  -n argocd \
  8081:443
```

Then open:

```text
https://localhost:8081
```

Mongo Express can also be accessed using:

```bash
kubectl port-forward \
  svc/mongo-express-service \
  -n hotel-system \
  8085:8081
```

Then open:

```text
http://localhost:8085
```

---

## Startup and Verification

After restarting the computer:

1. Start Docker Desktop.
2. Wait for the Docker Engine.
3. Open WSL.
4. Verify the Kubernetes context.
5. Verify the Kind node.
6. Verify Argo CD.
7. Verify Pipeline360 workloads.
8. Open the application.

Check the context:

```bash
kubectl config current-context
```

Expected:

```text
kind-pipeline360-cluster
```

Check the node:

```bash
kubectl get nodes
```

Check Argo CD:

```bash
kubectl get pods -n argocd
kubectl get applications -n argocd
```

Check Pipeline360:

```bash
kubectl get deployments,statefulsets -n hotel-system
kubectl get pods -n hotel-system
kubectl get services -n hotel-system
kubectl get ingress -n hotel-system
kubectl get pvc -n hotel-system
```

Check the website:

```bash
curl -I \
  -H "Host: hotel.local" \
  http://127.0.0.1:3000/
```

Expected:

```text
HTTP/1.1 200 OK
```

Check the API:

```bash
curl \
  -H "Host: hotel.local" \
  http://127.0.0.1:3000/api/reservations/hotels
```

---

## Manifest Validation

Validate application manifests without changing the cluster:

```bash
kubectl apply \
  --dry-run=client \
  --recursive \
  -f kubernetes/
```

Validate Argo CD Applications:

```bash
kubectl apply \
  --dry-run=client \
  -f argocd/backend-app.yaml \
  -f argocd/frontend-app.yaml \
  -f argocd/platform-app.yaml
```

Validate the ApplicationSet CRD with server-side dry run:

```bash
kubectl apply \
  --server-side \
  --force-conflicts \
  --dry-run=server \
  -f argocd/crds/applicationsets-crd-v3.4.5.yaml
```

---

## Git Workflow

All development work is performed on `dev`.

Before making changes:

```bash
git switch dev
git pull --ff-only origin dev
git status
```

Commit only intended files:

```bash
git add <specific-files>
git commit -m "Describe the change"
git push origin dev
```

Open a Pull Request:

```text
base: main
compare: dev
```

After merging:

```bash
git fetch origin --prune
git merge --ff-only origin/main
git push origin dev
```

Verify synchronization:

```bash
git rev-list --left-right --count origin/main...origin/dev
```

Expected:

```text
0  0
```

---

## Recovery and Safety

Routine deployments must be performed through Git and Argo CD.

Avoid routine live changes such as:

```text
kubectl edit
kubectl set image
kubectl apply
```

Argo CD self-healing may revert changes that do not exist in Git.

Do not run destructive commands without a verified backup and recovery plan:

```text
kubectl delete pvc
kubectl delete namespace
git reset --hard
git push --force
```

A forced Argo CD refresh should be used only for troubleshooting:

```bash
kubectl annotate application pipeline360-frontend \
  -n argocd \
  argocd.argoproj.io/refresh=hard \
  --overwrite
```

`kubectl rollout status` monitors a rollout; it does not initiate one:

```bash
kubectl rollout status \
  deployment/frontend-deployment \
  -n hotel-system \
  --timeout=180s
```

---

## Related Repositories

- [Pipeline360 Frontend](https://github.com/eli0504167101/Pipeline360-Frontend)
- [Pipeline360 Backend](https://github.com/eli0504167101/Pipeline360-Backend)
- [Pipeline360 Infrastructure](https://github.com/eli0504167101/Pipeline360-Infra)

---

## Author

**Eli Hildesheim**

DevOps Final Project — Pipeline360