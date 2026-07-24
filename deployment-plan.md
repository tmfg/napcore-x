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
  directories: `input/` (OSM + GTFS/NeTEx source files) and `graph/`
  (build output, `graph.obj`).

#### 2. Build and push images

- `podman build -f src/build/Dockerfile -t <acr>.azurecr.io/otp-build:<tag> .`
- `podman build -f src/serve/Dockerfile -t <acr>.azurecr.io/otp-serve:<tag> .`
- Push both to ACR. Tag with OTP version + git SHA for traceability.

#### 3. One-off graph build job

- Azure Container Instance or Container Apps Job, running `otp-build`.
- Mount the Azure Files share: `input/` read-only, `graph/` read-write.
- Populate `input/` first (manually via `az storage file upload`, or a small
  fetch step using the URLs).
- Env vars: `INPUT_OSM_PATH`, `INPUT_GTFS_PATH`, `OUTPUT_GRAPH_DIR` mapped to
  the mounted paths (mirrors the local podman run command in the readme).
  Skip `INPUT_NETEX_PATH` until NeTEx import is fixed.
- Give the job enough memory for `-Xmx8G` (>= ~10-12 GB container memory). (TODO: verify actual requirements later)
- Output: `graph.obj` written to `graph/` on the share.

#### 4. Serve container (Azure App Service for Containers, Linux)

- Web App for Containers using `otp-serve` from ACR.
- Mount the same Azure Files share's `graph/` directory into the app
  (Azure Storage Mounts), at the path used for `OTP_GRAPH_DIR`.
- App settings: `OTP_GRAPH_DIR=<mounted graph path>`, `WEBSITES_PORT=8080`.
- Enable "Always On" (graph load time is non-trivial; avoid idling out).

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

#### Known gaps to revisit

- Fix NeTEx file-pattern config (`sharedFilePattern`/`groupFilePattern`) in
  `build-config.json` before enabling NeTEx in the Azure build job.
- GTFS trip_id deduplication in `start-build.sh` is a lossy workaround for now
- `build-config.json` is mutated in place per build run via `jq` — works, but
  is implicit. Consider generating it from a template per environment.
- No IaC (Bicep/ARM/Terraform) exists yet — this plan should be translated
  into actual templates once the approach above is confirmed.
