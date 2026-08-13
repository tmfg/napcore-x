# Napcore x demo

## Install requirements

Azure CLI and Bicep for deployment.

Docker or Podman for running containers locally.

## Local testing (build + serve images)

These commands test the split build/serve container workflow locally. Replace
the placeholder file names below with your own downloaded files.

Data files for local testing will be located in local-test directory.

### Create local folders

> mkdir -p local-test/input/osm local-test/input/transit local-test/output/graph

### Download test data

> curl -L "\<osm-extract-url\>" -o local-test/input/osm/\<osm-extract\>.pbf
>
> curl -L "\<gtfs-feed-url\>" -o local-test/input/transit/\<gtfs-feed\>.zip
>
> curl -L "\<netex-feed-url\>" -o local-test/input/transit/\<netex-feed\>.zip

### Build the builder image

> podman build -f src/build/Dockerfile -t otp-build .

### Run the builder image with GTFS + NeTEx

> podman run --rm \\
> -v "$(pwd)/local-test/input:/mnt/input:ro" \\
>  -v "$(pwd)/local-test/output/graph:/mnt/output" \\
> -e INPUT_OSM_PATH=/mnt/input/osm/\<osm-extract\>.pbf \\
> -e INPUT_GTFS_PATH=/mnt/input/transit/\<gtfs-feed\>.zip \\
> -e INPUT_NETEX_PATH=/mnt/input/transit/\<netex-feed\>.zip \\
> -e OUTPUT_GRAPH_DIR=/mnt/output \\
> otp-build

NOTE: Can run with either netex, gtfs or both.

INPUT_GTFS_PATH and INPUT_NETEX_PATH are each optional, but at least one must be set.

### Build the serve image

> podman build -f src/serve/Dockerfile -t otp-serve .

### Run the serve image against the built graph

> podman run --rm -p 8080:8080 \\
> -v "$(pwd)/local-test/output/graph:/mnt/graph:ro" \\
> -e OTP_GRAPH_DIR=/mnt/graph \\
> otp-serve

Open http://localhost:8080/ once the server has started.

## Azure infra deployment (Bicep)

Infra lives in [infra/](infra/) and deploys at subscription scope via [infra/main.bicep](infra/main.bicep) (creates its own resource group).

Some default parameters are defined in [infra/main.bicepparam](infra/main.bicepparam) but it does not contain all of the parameters and can't be used directly for deployment. Parameters for image tags, input filenames, secrets (none currently) should not be committed to git but instead defined in `infra/main.local.bicepparam`.

`infra/main.local.bicepparam` template:

```
using './main.bicep'
extends './main.bicepparam'

param buildJobImageTag = '<otp-version>-<git-sha>'
param serveAppImageTag = '<otp-version>-<git-sha>'
param osmFileName = '<osm-file>.pbf'
param gtfsFileName = '<gtfs-file>.zip'
```

Override any of `main.bicepparam`'s shared values here too if a particular deploy needs something different.

Image tags come from [scripts/build-and-push-images.sh](scripts/build-and-push-images.sh) output, e.g. `2.8.1-1234abc`.

### Deploy instructions

There are some additional steps when deploying to an empty subscription. If deploying to an empty subscription, start from step 1. If updating an existing deployment, skip to step 5.

TODO: describe what to do if only data changes, or only OTP images need to be updated.

#### 1. Create the base deployment

TODO: flag to create partial base deployment

#### 2. Create the necessary file share directories

Create directories in the file share `otp-data` (defined in [infra/modules/storage.bicep](infra/modules/storage.bicep)): /input, /output, /output/graph
TODO: cli method was not working before so I used the web portal

#### 3. Upload OTP input data

TODO: current method is to use web portal to add data packages to the file share `otp-data`.

GTFS/NeTEx data under /input/transit and OSM data under /input/osm

The filenames of the packages need to be in pp params. TODO: only one file per type supported from now

#### 4. Update container images in container registry

Whenever changes are made to the container images (otp-build, otp-serve), new images need to be created and pushed to AZ.

Login to Azure CLI:

> az login

Build and push images. This will use your Azure credentials to push to ACR, so need access. By default it will be given to Owner/Contributor of the ACR.

> ./scripts/build-and-push-images.sh

The script will output the new image tags, which will need to be updated to `infra/main.local.bicepparam`. The tag contains current git commit hash, as well as -dirty suffix if there are unstaged changes.

#### 5. Deploy all resources

Preview changes:

> az deployment sub what-if --location swedencentral --template-file infra/main.bicep --parameters infra/main.local.bicepparam

Deploy:

> az deployment sub create --location swedencentral --template-file infra/main.bicep --parameters infra/main.local.bicepparam --name napcorexdemo-$(date +%Y%m%d%H%M)

NOTE: on a fresh deployment there could be permission problems if the User Managed Identity permissions propagate too slowly. If that happens, try again.

When a new deployment is made, the OTP build script will run and the serve app will start serving the graph. TODO: a better way to generate graph when only data changes?

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
