### Deployment plan

Rough plan for deploying the current build/serve container workflow to Azure.
Based on the current state of the repo:

- Two images: [src/build/Dockerfile](src/build/Dockerfile) (builds and saves
  `graph.obj`) and [src/serve/Dockerfile](src/serve/Dockerfile) (loads
  `graph.obj` and serves the OTP API/UI). Both pinned to
  `opentripplanner:2.8.1` and use `JAVA_OPTS=-Xmx8G`.
- Build image requires `INPUT_OSM_PATH`, `OUTPUT_GRAPH_DIR`, and at least one
  of `INPUT_GTFS_PATH` / `INPUT_NETEX_PATH` (see
  [src/build/start-build.sh](src/build/start-build.sh)).
- Serve image requires `OTP_GRAPH_DIR` pointing at a directory containing
  `graph.obj` (see [src/serve/start-serve.sh](src/serve/start-serve.sh)).
- **NeTEx import is currently broken** (see note in [readme.md](readme.md)) —
  deploy with GTFS only until that's fixed.
- The GTFS dedup step and the `jq`-based `build-config.json` trimming in
  `start-build.sh` are both flagged as temporary workarounds (`TODO`
  comments)

#### 1. Core resources

- Resource group.
- Azure Container Registry (ACR) — hosts `otp-build` and `otp-serve` images.
- Storage account with an Azure Files share, e.g. `otp-data`, with two
  directories: `input/` (OSM + GTFS/NeTEx source files) and `output/graph/`
  (build output, `graph.obj`) — mirrors the local `local-test/input` and
  `local-test/output/graph` layout used for local podman runs.
- Implemented as Bicep in [infra/main.bicep](infra/main.bicep) (subscription
  scope, creates the resource group) with modules
  [infra/modules/acr.bicep](infra/modules/acr.bicep) and
  [infra/modules/storage.bicep](infra/modules/storage.bicep). Parameters in
  [infra/main.bicepparam](infra/main.bicepparam). The share's `input/`,
  `output/`, and `output/graph/` directories aren't created by Bicep (ARM
  can't create subdirectories in a file share) — create them manually after
  first deploy.

#### 2. Build and push images

- `podman build -f src/build/Dockerfile -t <acr>.azurecr.io/otp-build:<tag> .`
- `podman build -f src/serve/Dockerfile -t <acr>.azurecr.io/otp-serve:<tag> .`
- Push both to ACR. Tag with OTP version + git SHA for traceability.

#### 3. One-off graph build job

- Azure Container Instance or Container Apps Job, running `otp-build`.
- Mount the Azure Files share: `input/` read-only, `output/graph/`
  read-write.
- Populate `input/` first (manually via `az storage file upload`, or a small
  fetch step using the URLs).
- Env vars: `INPUT_OSM_PATH`, `INPUT_GTFS_PATH`, `OUTPUT_GRAPH_DIR` mapped to
  the mounted paths (mirrors the local podman run command in the readme).
  Skip `INPUT_NETEX_PATH` until NeTEx import is fixed.
- Give the job enough memory for `-Xmx8G` (>= ~10-12 GB container memory). (TODO: verify actual requirements later)
- Output: `graph.obj` written to `output/graph/` on the share.
- Implemented as an Azure Container Instance in
  [infra/modules/build-job.bicep](infra/modules/build-job.bicep) (chose ACI
  over a Container Apps Job to avoid standing up a Container Apps
  Environment + Log Analytics for a single one-off run). Pulls from ACR via
  a user-assigned managed identity granted `AcrPull` in
  [infra/modules/acr-role-assignment.bicep](infra/modules/acr-role-assignment.bicep)
  — no admin credentials involved. The share is mounted twice (once
  read-only at `/mnt/otp-input`, once read-write at `/mnt/otp-output`) since
  ACI's Azure Files volume always mounts the whole share, not a
  subdirectory. `restartPolicy: Never` — re-run by re-deploying the module.
  - TODO: mounting the same share twice under different permissions is only
    enforced at the ACI mount level, not by the storage account itself —
    the "read-only" mount doesn't stop the container from writing to
    `input/` via the read-write mount path. Revisit with separate file
    shares/storage accounts for `input/` vs `output/graph/`, or move input
    data handling to blob storage with scoped SAS tokens, for real
    isolation.

#### 4. Serve container (Azure App Service for Containers, Linux)

- Web App for Containers using `otp-serve` from ACR.
- Mount the same Azure Files share's `output/graph/` directory into the app
  (Azure Storage Mounts), at the path used for `OTP_GRAPH_DIR`.
- App settings: `OTP_GRAPH_DIR=<mounted graph path>`, `WEBSITES_PORT=8080`.
- Enable "Always On" (graph load time is non-trivial; avoid idling out).
- Lowered `JAVA_OPTS` from `-Xmx8G` to `-Xmx2G` in
  [src/serve/Dockerfile](src/serve/Dockerfile) for cloud serving (the
  Estonia-sized graph doesn't need 8G), enabling a much cheaper App Service
  Plan tier.
- Implemented as an App Service Plan (Linux, Basic B2 — 2 vCPU/3.5 GiB) and
  Web App for Containers in
  [infra/modules/serve-app.bicep](infra/modules/serve-app.bicep). Pulls from
  ACR via a user-assigned managed identity granted `AcrPull` (same pattern
  as the build job) — no admin credentials involved. The whole Azure Files
  share is mounted read-write at `/mnt/otp-data` (App Service's classic
  storage-mounts feature has no read-only option), with
  `OTP_GRAPH_DIR=/mnt/otp-data/output/graph`.
  - TODO: the app only needs read access to `output/graph/`, but the mount
    is read-write over the whole share. Revisit with a separate
    share/storage account for graph output if tighter isolation is needed.
- Gated behind `deployServeApp` in [infra/main.bicep](infra/main.bicep),
  disabled by default — same `Microsoft.Authorization/roleAssignments/write`
  permission blocker as `deployBuildJob` (see Part 3). Re-enable once that
  permission is granted.
- Security: `httpsOnly: true`, `minTlsVersion: '1.2'`,
  `ftpsState: 'Disabled'` set in
  [infra/modules/serve-app.bicep](infra/modules/serve-app.bicep). The app is
  intentionally left publicly accessible with no auth/IP restriction (it's
  meant to be a usable public trip-planner demo) — a deliberate decision,
  not an oversight. The storage-key blast-radius TODO above is deferred for
  the same reason (see Part 3's matching TODO).

#### 5. Wiring build -> serve

- `start-serve.sh` copies `graph.obj` in at container start — there's no
  live-reload, so after a new build job completes, the App Service needs a
  restart/redeploy to pick up the new graph.
- Rough first pass: do this manually. Later: chain build job completion ->
  App Service restart in a pipeline.

#### 6. CI/CD (later)

- Pipeline 1: build & push both images to ACR on changes to `src/build`,
  `src/serve`, `build-config.json`, or `router-config.json`.
- Pipeline 2: run the one-off build job on a schedule or when feed data
  changes.
- Pipeline 3: restart/redeploy the App Service after pipeline 2 succeeds.

#### 7. Logging for the serve app (planned, not yet implemented)

Needed before making the serve app publicly accessible — currently there's
no visibility into traffic/errors on it.

- Lightweight option, no Log Analytics workspace needed: a blob container
  (e.g. `app-logs`) in the existing storage account
  ([infra/modules/storage.bicep](infra/modules/storage.bicep)), with HTTP
  request logs (IP, path, status, latency) and application/container
  stdout logs shipped there via a `Microsoft.Web/sites/config` `logs`
  resource on the web app
  ([infra/modules/serve-app.bicep](infra/modules/serve-app.bicep)), with a
  bounded retention (e.g. 7 days).
- Use a scoped account SAS token (blob service only, container+object
  resources, no read permission) for the log shipping config, rather than
  handing out the full storage account key.
  - Caveat: SAS tokens expire and aren't auto-rotated by Bicep — would need
    either a redeploy before expiry (e.g. default to 1 year out) or a
    separate rotation mechanism, or log shipping silently stops.
- Not planned for now: Application Insights — would need the Java agent
  added to [src/serve/Dockerfile](src/serve/Dockerfile) for real
  request/exception tracing, plus ongoing cost. Blob logs are likely enough
  to spot abuse/errors on a demo; revisit if richer telemetry/alerting is
  needed later.
