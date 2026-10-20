# Pipeline360 Security Remediation Plan

**Status:** Reconstructed for review; no remediation or deployment is authorized by
this document.

**Scope:** MongoDB authentication, Replica Set safety, backup and restore, Kubernetes
network enforcement, traffic restrictions, secret handling, trusted proxies, and
coordinated GitOps rollout.

## 1. Evidence and confidence

This plan reconstructs the previously documented review findings and strategy. It
does not claim to reproduce the missing original audit or to validate the live
cluster.

### 1.1 Repository facts verified during this document recovery

The following observations were verified against the current local
`Pipeline360-Infra` worktree:

- The active branch is `dev`; the worktree was clean before this documentation change.
- `kubernetes/platform/mongo-statefulset.yaml` declares MongoDB `7`, three replicas,
  Replica Set `rs0`, and one `1Gi` PVC per member. The declared `mongod` arguments
  include `--replSet rs0` and `--bind_ip_all`; they do not include `--auth` or a
  keyfile configuration.
- `kubernetes/platform/app-config.yaml` declares
  `mongodb://mongo:27017/Pipeline360_PROD` as `mongo-url`.
- `kubernetes/backend/deployment.yaml` obtains `MONGO_URL` from that ConfigMap.
- `kubernetes/platform/mongo-express.yaml` declares a Mongo Express connection URI
  without database credentials. Its HTTP Basic Authentication username and password
  are sourced from Secret `mongo-express-auth`.
- `kubernetes/platform/hotel-ingress.yaml` routes host `mongo.hotel.local` to
  `mongo-express-service:8081`. No TLS stanza is declared in this manifest. This is
  a repository observation, not proof of live exposure or TLS behavior.
- No `NetworkPolicy` manifest was found in the inspected Infrastructure manifests.
- `argocd/platform-app.yaml` and `argocd/backend-app.yaml` target branch `main`,
  deploy to `hotel-system`, and declare automated sync with `prune` and `selfHeal`.
  The platform Application manages `kubernetes/platform`; the backend Application
  manages `kubernetes/backend`.
- The local Infrastructure branch is `dev`, while the checked-in Argo CD
  Applications target `main`. This plan does not change either reference.

Repository manifests describe intended configuration; they do not establish the
live cluster's state.

### 1.2 Previously documented review observations

The following statements are attributed to their recorded source. They are
historical reports or recommendations, not new live-environment verification.

- **Backend authentication rollout documentation:** It records that the Ingress
  declaration routes `hotel.local/api` directly to the Backend Service and notes
  that a Frontend proxy may also provide an `/api` route. It explicitly says the
  actual Ingress controller behavior, source IP preservation, TLS, and reachable
  paths were not verified.
- **Backend authentication rollout documentation:** It requires determining the
  Backend's actual TCP peer and supported proxy paths before configuring
  `AUTH_TRUSTED_PROXIES`. It recommends trusting only explicitly controlled proxy
  addresses or narrowly scoped CIDRs, and testing forwarded-header spoofing and
  client rate-limit behavior.
- **Backend authentication rollout documentation:** It proposes staging nonsecret
  authentication settings before adding Backend environment-variable references,
  synchronizing the platform Application before the Backend Application, and
  delivering any database credentials via an approved Secret mechanism. These are
  proposed rollout steps, not completed changes or deployment approval.
- **Previous audit summary relayed in this session:** It identified MongoDB
  authentication, Replica Set safety, backup/restore, NetworkPolicy enforcement,
  traffic restrictions, and approval gates as remediation topics. The original
  summary document is unavailable; no additional detailed audit evidence can be
  attributed to it here.
- **Earlier GitHub inspection recorded in this session:** Infrastructure PRs
  #50–#53 were reported as open. Their current GitHub state has not been checked for
  this document. They must not be modified or merged under this plan.

Repository facts independently verified during this recovery are listed in
Section 1.1 and are not represented here as audit-only findings.

### 1.3 Not verified and explicitly out of scope

No live Kubernetes API or MongoDB access was performed for this plan. The following
remain unknown unless separately verified with approval:

- Live MongoDB users, authentication settings, Replica Set health, PVC use, and
  stored data.
- Whether the live namespace is production, demonstration, or local-only.
- The live CNI, NetworkPolicy enforcement, Ingress controller configuration, TLS,
  and actual traffic reachability.
- Backup artifacts, backup destinations, encryption-key custody, restore history,
  retention requirements, Recovery Point Objective (RPO), and Recovery Time
  Objective (RTO).
- The exact original security audit findings; the original plan was unavailable
  when this document was prepared.

## 2. Objectives and safety boundaries

The immediate objective is to prepare a reviewable remediation and rehearsal
sequence. Implementation requires separate explicit approval.

All rehearsal validation must use a newly created, isolated environment, synthetic
data, disposable storage, and credentials and keyfiles created only for that
environment. Do not connect the rehearsal to `hotel-system`, existing MongoDB PVCs,
production database identities, or the existing Argo CD Applications.

This plan does not authorize:

- Changes to the live `hotel-system` namespace, MongoDB users, configuration,
  StatefulSet, or PVCs.
- Live Replica Set restarts, stepdowns, failovers, data export, or restore.
- Creating Kubernetes resources, Secrets, volumes, or NetworkPolicies.
- Deploying Frontend or Backend images or beginning Premium implementation.
- Modifying or merging Infrastructure PRs #50–#53.
- Committing credentials, keyfiles, or backup contents to Git.

## 3. MongoDB authentication

### 3.1 Target design

Rehearse authentication only in a separate disposable MongoDB Replica Set:

- Use a unique Replica Set name, namespace, Services, PVCs, database name, and
  identities. Do not reuse `rs0`, `Pipeline360_PROD`, or live credentials.
- Create a new keyfile for the rehearsal. Mount it read-only, restrict file access
  to the MongoDB process (for example, mode `0400`), and never store its contents in
  Git or logs.
- Enable MongoDB internal member authentication with the rehearsal keyfile and
  enable client authentication.
- Create a temporary administrative identity for setup and a separate application
  identity with only the permissions needed on the synthetic rehearsal database.
- Keep all credential material in an approved secret store or temporary isolated
  secret mechanism. Do not pass credentials in shell arguments, command history, or
  diagnostic output.

The exact MongoDB bootstrap and configuration sequence must be checked against the
selected MongoDB image version and approved before the rehearsal. This document does
not prescribe a live migration command.

### 3.2 Rehearsal checks

1. Verify that all three rehearsal members use the same keyfile and that the
   Replica Set can authenticate member-to-member.
2. Verify `rs.status()` shows the expected primary and two secondaries, with no
   sustained replication lag.
3. Connect using the rehearsal application identity and verify only the intended
   database permissions.
4. Verify connections with missing or incorrect credentials fail.
5. Verify access to an unrelated database is denied.
6. Confirm that credentials and keyfile values do not appear in Git, logs, shell
   history, process arguments, or backup manifests.

Do not copy this procedure to the live Replica Set. Any production authentication
migration requires a separate approved change plan, a rehearsed rollback, and
explicit operational approval.

### 3.3 Authentication rollback blocker

Before any authentication migration beyond the disposable rehearsal, a separate
rollback runbook must be written, reviewed, approved, and tested against the
intended MongoDB version and topology. At minimum, it must define decision owners,
observable stop conditions, safe recovery actions, data-preservation requirements,
and verification of Replica Set health and authorization after recovery.

Stop the rehearsal or a future approved rollout and do not proceed to the next
member or rollout stage if any of these conditions occurs:

- Replica Set health degrades, expected replication does not recover, or quorum is
  lost.
- Expected member-to-member or application authentication fails.
- A client or workload obtains access that is not explicitly authorized.
- The observed behavior differs from the approved procedure or data integrity is
  uncertain.

Do not disable authentication or revert member configuration as an improvised
response. Such actions may only be considered if they are explicitly described in
the separately approved and tested rollback runbook for that exact topology.

The rollback implementation, sequencing, and recovery commands remain unresolved
blockers. This document does not provide or authorize them.

## 4. Replica Set safety

Replica Set operations can affect availability and write durability. The rehearsal
must use only the new disposable Replica Set and PVCs.

- Do not restart, step down, reconfigure, or force a live member as part of this
  plan.
- In rehearsal, validate member health and quorum after each approved test action.
  Do not proceed if the intended primary or majority is unavailable.
- Test failover and quorum-loss behavior only in the isolated Replica Set, with
  synthetic data.
- Test ambiguous write acknowledgements and confirm the application does not assume
  that a failed response proves a write was rolled back.
- Record observed behavior, timing, and recovery conditions. Do not infer live
  availability or write safety from the repository manifest.

Production failover, stepdown, restart, or reconfiguration testing requires its own
explicit change approval and operational window.

## 5. Backup, encryption, retention, and restore

### 5.1 Rehearsal backup strategy

Use synthetic records in a dedicated rehearsal database. Establish a known baseline
of collection names, document counts, deterministic document digests, and index
definitions. Pause the synthetic writer while creating the test dump so the restore
has a defined consistency point.

The rehearsal can use `mongodump` archive output with compression. Credentials must
be supplied through a protected mechanism; do not include a credential-bearing URI
in Git, command-line arguments, or logs.

Encrypt the archive before it leaves the isolated worker. The proposed approach is
`age` with a dedicated public recipient and a private identity kept outside the
cluster. An approved KMS may be substituted after key custody, access, and recovery
procedures are reviewed. Store a SHA-256 checksum of the encrypted artifact. Do not
store backup contents or keys in Git.

The proposed rehearsal-only retention is one encrypted artifact for no more than
seven days, or until the review and cleanup are complete, whichever comes first.
This is a proposal, not an approved production retention policy.

### 5.2 Restore procedure and acceptance criteria

Restore only into a new, clean rehearsal Replica Set backed by disposable PVCs.
Never restore over the live database or a database that may contain newer writes.

The proposed `mongodump` operation is scoped to one application database. It does
not by itself restore the complete MongoDB authentication configuration, internal
member keyfile, or all users and roles, which may reside in the `admin` database or
be provisioned separately. Do not treat a successful data restore as proof that
authentication identities were restored.

Create the rehearsal administrative and application users and any required custom
roles separately through the approved isolated bootstrap procedure. Validate the
resulting role grants with positive and negative authorization tests before
accepting the restore. These identities must be newly created for the rehearsal;
do not export, restore, or recreate production identities or credentials.

Accept the rehearsal only when all of the following pass:

- The encrypted artifact checksum matches the checksum recorded at creation.
- The archive decrypts using the designated recovery identity.
- Per-collection document counts and deterministic digests match the baseline.
- Required index names and specifications match, including unique, TTL, and
  partial-index properties where applicable.
- The restored Replica Set reaches the expected healthy member state and completes
  replication without sustained lag.
- Synthetic read and write checks succeed with the intended write concern.
- Authentication and authorization checks pass after restore.
- No production identities or data are present.

This test covers a quiesced synthetic database dump. A backup under continuous
writes, point-in-time recovery, or `oplog` replay requires a separately approved
procedure and additional acceptance criteria.

### 5.3 Production policy blockers

Before any production backup or restore work, owners must approve the data scope,
RPO, RTO, retention, encryption and key-custody design, storage destination,
access logging, restore authorization, and deletion policy. No live application data
may be exported under this plan.

## 6. NetworkPolicy enforcement and traffic blocking

### 6.1 Isolated enforcement investigation

No NetworkPolicy manifest was found in the inspected Infrastructure configuration.
The live CNI and its enforcement behavior have not been verified.

Perform an initial enforcement test only in a separate cluster with a CNI known to
enforce Kubernetes NetworkPolicy. Do not attach the test to the production Argo CD
Applications or deploy policies to `hotel-system`.

Design and test policy rules to:

- Apply `default-deny` isolation separately for ingress and egress to the selected
  Pods, using policies whose selectors and scope are limited to the rehearsal.
- Add explicit allow rules for required DNS egress and any required health,
  metrics, or control-plane traffic.
- Add ingress and egress allowances for MongoDB port `27017` between the intended
  Backend test workload and MongoDB members, and between Replica Set members.
- Add only the ingress and egress exceptions needed by the approved rehearsal
  flows. In Kubernetes NetworkPolicy, rules are additive: traffic allowed by any
  applicable policy remains allowed. Standard Kubernetes NetworkPolicy does not
  provide explicit deny rules that override an allow from another policy.
- Limit Mongo Express access to an explicitly approved administrative path, or
  disable it in the rehearsal if it is not needed.
- Test allowed and isolated traffic from test Pods in both ingress and egress
  directions. A successfully applied policy is not evidence of enforcement;
  verify that unauthorized connection attempts fail with the selected CNI.

Determine the actual Ingress controller namespace, Pod labels, and network path
before writing selectors. Account for CNI behavior, DNS, and any required
monitoring traffic; do not assume that a broad namespace or node CIDR is safe.

### 6.2 Existing traffic paths requiring review

The repository declares `mongo.hotel.local` routing to `mongo-express-service:8081`.
The Mongo Express manifest uses Secret-backed HTTP Basic Authentication, but its
MongoDB connection URI has no database credentials. The Ingress manifest does not
declare TLS. These are repository facts only; actual reachability, TLS termination,
and live exposure have not been checked.

Before production policy work, verify whether this administrative route is required,
how it is protected, and whether it should be removed or restricted. NetworkPolicy
rules must not be treated as a substitute for application authentication or
Ingress/TLS review.

### 6.3 Argo CD impact

The platform Argo CD Application tracks `kubernetes/platform` and declares automated
sync, `prune`, and `selfHeal` to `hotel-system`. A NetworkPolicy added under that
path on the tracked branch may be applied automatically and later pruned or
self-healed. Do not add or test a policy there without a separate reviewed change
and explicit approval.

## 7. Secrets and credential handling

- Keep MongoDB application credentials and Replica Set keyfiles out of ConfigMaps,
  Git, container images, logs, and shell history.
- Use an approved secret-management mechanism. If Kubernetes Secrets are selected,
  separately review encryption at rest, RBAC access, backup handling, and key
  rotation.
- Use a dedicated least-privilege application identity. Do not use the temporary
  administrative identity at runtime.
- The existing `mongo-express-auth` template contains placeholders, not production
  credentials. Do not treat its presence as evidence that MongoDB itself requires
  authentication.
- The Backend `MONGO_URL` currently comes from `app-config`. A future authenticated
  URI must be sourced from a reviewed Secret reference, not added to the ConfigMap.
- Rehearsal credentials and keyfiles must be unique, temporary, and deleted during
  approved cleanup.

## 8. Trusted proxies and application traffic

The Backend authentication rollout documentation requires `AUTH_TRUSTED_PROXIES`
to be based on observed network peers and verified request paths. Do not infer
trusted addresses from broad Pod or node ranges.

Before configuring trusted proxies:

1. Observe the Backend TCP peer for each supported route, including Ingress,
   optional Frontend proxy, and any internal route.
2. Verify that the final trusted proxy removes or replaces untrusted forwarding
   headers and that clients cannot bypass that proxy through the Backend Service.
3. Trust only explicit controlled proxy IPs or narrowly scoped CIDRs.
4. Test forged `X-Forwarded-For` values, two genuine clients, IPv4 NAT, and IPv6
   `/64` grouping against the expected rate-limit behavior.

Do not use `true`, hop-count trust, `0.0.0.0/0`, or `::/0`. Leaving trusted proxies
unset is fail-closed against spoofed forwarding headers, but users behind a shared
proxy may share an IP rate-limit budget. That behavior is not an acceptable
production capacity decision without review.

The exact `AUTH_ENV` and `AUTH_ORIGIN` values must match the approved browser origin.
Use HTTPS for hosted demo and production. Do not invent a production hostname or
reuse the same hostname to isolate environments.

## 9. Coordinated GitOps rollout

Any later application authentication rollout must remain separate from this
documentation change and must follow reviewed Infrastructure PRs. The Backend
authentication rollout document records the proposed two-stage configuration
sequence:

1. **Configuration stage:** Add only approved nonsecret authentication settings to
   `kubernetes/platform/app-config.yaml` through a reviewed PR. Confirm that the
   platform Application has synchronized the ConfigMap.
2. **Backend reference stage:** In a separate reviewed PR, add the corresponding
   environment references to `kubernetes/backend/deployment.yaml`. If database
   credentials are needed, provision them through the approved Secrets process and
   use a reviewed `secretKeyRef`.
3. Preserve the approved image, replica count, resource settings, Service names,
   probes, and database target during configuration staging.
4. Do not rely on ordering across the platform and Backend Argo CD Applications.
   Verify the ConfigMap keys exist before applying Deployment references.
5. Treat application image release as a separate approval. Verify source commit,
   image tag or digest, and CI result. Do not perform a direct Kubernetes image
   update; use the approved GitOps path.
6. Do not expose new authentication routes during a mixed-version rollout. Verify
   that every intended Backend replica is updated and ready before enabling clients.

This reconstructed plan does not authorize a merge, sync, release, or deployment.
Infrastructure PRs #50–#53 remain outside scope and must not be modified or merged
under this plan. No Frontend or Backend image deployment is part of the rehearsal.

## 10. Rollback, abort, and cleanup

### Rehearsal abort

Stop the rehearsal and do not proceed to the next stage if Replica Set health
degrades, replication fails to recover, quorum is lost, expected member-to-member
or application authentication fails, or an unexpected client or workload obtains
access. Also stop if restore verification fails, data integrity is uncertain, or
observed behavior differs from the approved procedure.

Preserve sanitized diagnostic output and do not continue destructive operations
against a partially restored target. Any recovery or rebuild must follow a
separately approved and tested rehearsal procedure.

### Future production rollout

Before any production authentication or network-security rollout, require a
separate rollback runbook that is approved and tested for the exact MongoDB version,
Replica Set topology, authentication configuration, and GitOps workflow. It must
define owners and stop conditions; a safe, ordered recovery procedure; how to
preserve quorum, data, and credentials; verification of member health and access
controls; and criteria for resuming or aborting the change.

Do not manually deploy images, automatically revert manifests, disable
authentication, revert member configuration, disable readiness checks, weaken
write concern, remove indexes, or restore an older backup over newer writes unless
the exact action is explicitly authorized by that tested runbook. This plan does
not supply those rollback commands. The rollback implementation and validation
remain blockers. If a write request returns an error, do not assume that its
database write was rolled back or blindly replay it.

### Rehearsal cleanup

After approval and evidence capture, stop test workloads, delete only the
specifically named rehearsal resources and disposable PVCs, revoke or delete
rehearsal credentials and keyfiles, and delete the encrypted artifact according to
the approved rehearsal retention. Verify the cleanup target before deletion.
Never clean up `hotel-system`, existing PVCs, the existing Kind cluster, or any
production identity as part of rehearsal cleanup.

## 11. Approval gates and outstanding blockers

The following require explicit approval before implementation:

- Creating a dedicated rehearsal cluster, namespace, MongoDB members, PVCs, Secrets,
  or test workloads.
- Selecting and installing a NetworkPolicy-enforcing CNI for the isolated test.
- Creating temporary rehearsal identities and keyfiles.
- Selecting the backup destination, encryption-key custody, and artifact retention.
- Any production data access, backup, restore, MongoDB restart, stepdown, or
  configuration change. These are not authorized by this plan.
- Any NetworkPolicy or traffic restriction targeting `hotel-system`.
- Any GitOps manifest change, PR merge, Argo CD synchronization, or image release.

Outstanding blockers:

- The original Security Remediation Plan and complete original audit are unavailable.
  This document is a reconstruction, not a replacement audit or proof that all
  original findings have been captured.
- The live environment type, MongoDB state, NetworkPolicy enforcement, Ingress
  reachability, TLS behavior, and proxy network paths remain unverified.
- Production RPO/RTO, backup retention, encryption-key custody, and restore
  authorization are undefined.
- The Backend's current MongoDB URI is configured through a ConfigMap; a secure,
  approved credential-delivery design is still required before an authenticated
  application rollout.
- The current status of Infrastructure PRs #50–#53 must be checked before any later
  work involving them. This plan does not authorize changes to those PRs.

## 12. References

- Infrastructure overview: [`README.md`](../README.md)
- MongoDB StatefulSet: [`mongo-statefulset.yaml`](../kubernetes/platform/mongo-statefulset.yaml)
- MongoDB application configuration: [`app-config.yaml`](../kubernetes/platform/app-config.yaml)
- Backend Deployment: [`deployment.yaml`](../kubernetes/backend/deployment.yaml)
- Mongo Express and credentials reference: [`mongo-express.yaml`](../kubernetes/platform/mongo-express.yaml)
- Ingress routes: [`hotel-ingress.yaml`](../kubernetes/platform/hotel-ingress.yaml)
- Platform Argo CD Application: [`platform-app.yaml`](../argocd/platform-app.yaml)
- Backend Argo CD Application: [`backend-app.yaml`](../argocd/backend-app.yaml)
- Backend authentication rollout review: `Pipeline360-Backend/docs/authentication-rollout.md`
