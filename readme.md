# Napcore x demo

## Install requirements

Azure CLI and Bicep are needed for deployment.

Docker or Podman is needed for running containers locally.

## Local testing (build + serve images)

These commands test the split build/serve container workflow locally. Replace
the placeholder file names below with your own downloaded files.

Data files for local testing will be located in local-test directory.

### Create local folders

> mkdir -p local-test/input/osm local-test/input/gtfs local-test/input/netex local-test/output/graph

### Download test data

> curl -L "\<osm-extract-url\>" -o local-test/input/osm/\<osm-extract\>.pbf
>
> curl -L "\<gtfs-feed-url\>" -o local-test/input/gtfs/\<gtfs-feed\>.zip
>
> curl -L "\<netex-feed-url\>" -o local-test/input/netex/\<netex-feed\>.zip

### Build the builder image

> podman build --build-arg OTP_BASE_IMAGE="$OTP_BASE_IMAGE" -f src/build/Dockerfile -t otp-build .

### Run the builder image with GTFS + NeTEx

> podman run --rm \
>  -v "$(pwd)/local-test/input:/mnt/input:ro" \
>  -v "$(pwd)/local-test/output/graph:/mnt/output" \
>  -e INPUT_OSM_DIR=/mnt/input/osm \
>  -e INPUT_GTFS_DIR=/mnt/input/gtfs \
>  -e INPUT_NETEX_DIR=/mnt/input/netex \
>  -e OUTPUT_GRAPH_DIR=/mnt/output \
>  otp-build

NOTE: Can run with any number of OSM, GTFS and/or NeTEx files - drop any
matching files into the respective local-test/input/osm, .../gtfs or
.../netex directory. INPUT_GTFS_DIR and INPUT_NETEX_DIR are each optional,
but at least one GTFS or NeTEx file must be found overall.

### Build the serve image

> podman build --build-arg OTP_BASE_IMAGE="$OTP_BASE_IMAGE" -f src/serve/Dockerfile -t otp-serve .

### Run the serve image against the built graph

> podman run --rm -p 8080:8080 \\
> -v "$(pwd)/local-test/output/graph:/mnt/graph:ro" \\
> -e OTP_GRAPH_DIR=/mnt/graph \\
> otp-serve

Open http://localhost:8080/ once the server has started.

## Scripts

### get-osm-test-data.sh

Downloads OSM PBF extracts, crops each to a per-region bounding box, and produces smaller local test files.

Ferry routes/terminals (which a bbox crop would otherwise drop, since they cross open water) are extracted from the full download and merged into each region's cropped output file.

Requires `osmconvert` (`apt install osmctools`) and `osmium` (`apt install osmium-tool`).

URLs, bounding boxes and output paths are hardcoded in the script; edit it directly to change the regions.

> scripts/get-osm-test-data.sh

## Azure infra deployment (Bicep)

Infra lives in [infra/](infra/) and deploys at subscription scope via [infra/main.bicep](infra/main.bicep) (creates its own resource group).

Some default parameters are defined in [infra/main.bicepparam](infra/main.bicepparam) but it does not contain all of the parameters and can't be used directly for deployment. Parameters for image tags, input filenames, secrets (none currently) should not be committed to git but instead defined in `infra/main.local.bicepparam`.

`infra/main.local.bicepparam` template:

```
using './main.bicep'
extends './main.bicepparam'

param environmentName = 'dev'
param buildJobImageTag = '<otp-version>-<git-sha>'
param serveAppImageTag = '<otp-version>-<git-sha>'
```

Override any of `main.bicepparam`'s shared values here too if a particular deploy needs something different.

Image tags come from [scripts/build-and-push-images.sh](scripts/build-and-push-images.sh) output, e.g. `2.8.1-1234abc`.

### Resources

- Container Registry (ACR): stores the otp-build and otp-serve Docker images.
- Storage Account + Azure Files share (otp-data): holds input data (OSM/GTFS/NeTEx files) and the built OTP graph output.
- Container Instance (ACI) "build job": one-off container that builds the OTP graph from input data.
- App Service (Linux, Web App for Containers): runs the otp-serve container, serving the routing API.
- Azure Front Door + WAF policy: public entry point in front of the App Service.

### Data flow

- OTP Docker images (otp-build, otp-serve) are built and pushed to ACR via build-and-push-images.sh.
- Input files (OSM extract, GTFS and NeTEx) are uploaded to the otp-data file share's input/ directory.
- The build job container reads the input files, builds an OTP graph, and writes it to the output/ directory on the same file share.
- The serve app mounts the file share, loads the graph, and serves routing requests through Front Door.

### Logging / monitoring

- Front Door/WAF access, health probe, and WAF logs, and App Service HTTP/console/platform logs are sent to the storage account (`insights-logs-*` blob containers).
- Logs older than 30 days are automatically deleted.

### Deploy instructions

There are some additional steps when deploying to an empty subscription. If deploying to an empty subscription, start from step 1. If updating an existing deployment, skip to step 4.

If only input data changes, start from step 3. In this case it is not necessary to do a full deployment: you can also manually trigger the build job and restart the serve app.

Need to login to az CLI for all of these:

> az login

#### 1. Create the base deployment

Only needed on an empty subscription, before any resources exist. Deploys just the resource group, ACR, and storage account/file share by setting `deployBaseOnly = true` (add this to `infra/main.local.bicepparam`, or pass it inline)

Check what is being created:

> az deployment sub what-if --location swedencentral --template-file infra/main.bicep --parameters infra/main.local.bicepparam --parameters deployBaseOnly=true

Deploy:

> az deployment sub create --location swedencentral --template-file infra/main.bicep --parameters infra/main.local.bicepparam --parameters deployBaseOnly=true --name napcorexdemo-$(date +%Y%m%d%H%M)

`buildJobImageTag`/`serveAppImageTag` still need some value in `infra/main.local.bicepparam` even though they're unused for a base-only deploy.

#### 2. Create the necessary file share directories

Create directories in the file share `otp-data` (defined in [infra/modules/storage.bicep](infra/modules/storage.bicep)): /input, /input/osm, /input/gtfs, /input/netex, /output, /output/graph
TODO: cli method was not working before so I used the web portal

#### 3. Upload OTP input data

TODO: current method is to use web portal to add data packages to the file share `otp-data`.

Any number of OSM files under /input/osm, GTFS files under /input/gtfs, and NeTEx files under /input/netex.

#### 4. Update container images in container registry

Whenever changes are made to the container images (otp-build, otp-serve), new images need to be created and pushed to AZ.

Build and push images. This will use your Azure credentials to push to ACR, so need access. By default it will be given to Owner/Contributor of the ACR.

> ACR_NAME="acr-name" ./scripts/build-and-push-images.sh

Note: if ACR_NAME is not given, it defaults to the dev default name acrnapcorexdemotest

Set `OTP_IMAGE` to use a custom-built base image (e.g. the output of
[scripts/build-custom-otp-image.sh](scripts/build-custom-otp-image.sh)) for
both otp-build and otp-serve, instead of the default official image:

> ACR_NAME="acr-name" OTP_IMAGE="localhost/otp-custom:latest" ./scripts/build-and-push-images.sh

The script will output the new image tags, which will need to be updated to `infra/main.local.bicepparam`. The tag contains current git commit hash, as well as -dirty suffix if there are unstaged changes.

#### 5. Deploy all resources

Preview changes:

> az deployment sub what-if --location swedencentral --template-file infra/main.bicep --parameters infra/main.local.bicepparam

Deploy:

> az deployment sub create --location swedencentral --template-file infra/main.bicep --parameters infra/main.local.bicepparam --name napcorexdemo-$(date +%Y%m%d%H%M)

NOTE: on a fresh deployment there could be permission problems if the User Managed Identity permissions propagate too slowly. If that happens, try again.

When a new deployment is made, the OTP build script will run and the serve app will start serving the graph.

#### 6. Restart the serve app after the build job finishes

The build job can take several minutes, depending on data size.

The build job and serve app deploy in parallel, so on a fresh deployment the serve app can start and try to load the graph before the build job has finished writing it. Wait for the build job container to finish, then restart the serve app (via the portal, or `az webapp restart`) to pick up the new graph.

### Create OTP image with our custom changes

We are doing a bit of a hacky solution to inject custom logo to OTP debug UI.

Clone desired version (Note: process only tested for v2.9.0) `git clone --branch v2.9.0 --depth 1 https://github.com/opentripplanner/OpenTripPlanner.git`

Add Napcore logo image to OTP_DIR/OpenTripPlanner/client/src/static/img. Logo is located in the home folder src/static

In OTP_DIR/OpenTripPlanner/client/src/components/SearchBar/LogoSection.tsx change import logo to `import logo from '../../static/img/napcore-logo.png';`

Change <img>-component to `<img alt="" src={logo} width="75" height="50" className="logo-image" />`

Change "logo-image" in `client/OpenTripPlanner/client/src/style.css` to

```
.logo-image {
  margin-right: 15px;
}
```

Note: recent version of node, npm, java, maven, podman needed.

Change directory to `OpenTripPlanner/client` (current) if you haven't already.

    npm install

Then you can test changes here

    npm run dev

If it looks good, run the script to build a custom otp image:

    OTP_DIR=/path/to/OpenTripPlanner TARGET_PLATFORM=<optional, defaults to linux/amd64> scripts/build-custom-otp-image.sh

This produces `localhost/otp-custom:latest` image that has the OTP debug client replaced with our changes. Note: it also edits the local OTP repo.

Build otp-serve image:

    podman build --build-arg OTP_BASE_IMAGE="localhost/otp-custom:latest" -f src/serve/Dockerfile -t otp-serve .

## Run OTP from jar

### Opentripplanner jar-file:

OpenTripPlanner jar-file: [OTP-jar](https://repo1.maven.org/maven2/org/opentripplanner/otp-shaded/2.8.1/)

Jar-tiedosto lisätään projektin kantaan jonka jälkeen opentripplanner käynnistetään alla olevilla komennoilla.

### OpenTripPlanner / Terminaalista ajo

OTP docs: [OpenTripPlanner](https://docs.opentripplanner.org/en/latest/Basic-Tutorial/)

### simple-step-server:

> '$ java -Xmx4G -jar otp-shaded-2.8.1.jar --build --serve .'

serveri aukeaa: http://localhost:8080/

### Graafin tallennus ja valmiista graafista käynnistys:

#### Graafin tallennus:

> '$ java -Xmx4G -jar otp-shaded-2.8.1.jar --build --save .'

#### Valmiista graafista käynnistys:

> '$ java -Xmx4G -jar otp-shaded-2.8.1.jar --load .'

## Useful tools

### NeTEx

NeTEx data tools: [Netex](https://data4pt.org/w/index.php/NeTEX)

### GTFS

GTFS data visualization tool: [GTFS](https://app.transit-lens.com/)

### OSM

OpenStreetMap: [OSM](https://www.openstreetmap.org/#map=8/59.115/25.009&layers=D)
--> Yläkulman "navigointi -> export" saa ladattua alueen. Tämä vain pienille alueille (yksittäiset kaupungit)

Suuremmat alueet: [Suuret OSM](https://download.geofabrik.de/europe.html)
Geofabrikista voi ladata suuremman alueen (esim. Viro) ja tätä aluetta voidaan konvertoida pienemmäksi osmconvert toolilla.

#### osmconvert:

> 'sudo apt install osmctools'
> 'osmconvert <originalOSM.osm.pbf> -b=<Bounding tool coordinates> --complete-ways -o=<konvertoituOSM>.pbf'

#### OSM Bounding tool:

OSM rajaustyökalu: [Bounding tool](https://boundingbox.klokantech.com/)

Vasemmalta alakulmasta CSV-formaatti tarjoaa valmiiksi oikean muodon osmconvert komennossa käytettävälle parametrille.
