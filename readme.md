# Set Up

### Opentripplanner jar-file:

OpenTripPlanner jar-file: [OTP-jar](https://repo1.maven.org/maven2/org/opentripplanner/otp-shaded/2.8.1/)

Jar-tiedosto lisätään projektin kantaan jonka jälkeen opentripplanner käynnistetään alla olevilla komennoilla.

## OpenTripPlanner / Terminaalista ajo

OTP docs: [OpenTripPlanner](https://docs.opentripplanner.org/en/latest/Basic-Tutorial/)

### simple-step-server:

> '$ java -Xmx4G -jar otp-shaded-2.8.1.jar --build --serve .'

serveri aukeaa: http://localhost:8080/

### Graafin tallennus ja valmiista graafista käynnistys:

#### Graafin tallennus:

> '$ java -Xmx4G -jar otp-shaded-2.8.1.jar --build --save .'

#### Valmiista graafista käynnistys:

> '$ java -Xmx4G -jar otp-shaded-2.8.1.jar --load .'

## NeTEx

NeTEx data tools: [Netex](https://data4pt.org/w/index.php/NeTEX)

## GTFS

GTFS data visualization tool: [GTFS](https://app.transit-lens.com/)

## OSM

#### OSM:

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

# Data

Käytetään Jaakon tarjoamia URL-linkkejä datan saavuttamiseksi. Kontti noutaa tällä hetkellä datan ja tallentaa sen kontin sisälle. Build-config.json on määritelty keräämään data kontin sisältä (Dockerfile).

Zip paketit ovat olleet ladattuna ja sijoitettuna lokaaliin ympäristöön GTFS, OSM ja NeTEx kansioihin testausta varten

# DOCKER

### Build image Dockerfilen pohjalta:

> podman build -t my-otp .

### Kontin käynnistys

> podman run -d --name my-otp-container -p 8080:8080 localhost/my-otp

### Kontin bash:

> podman exec -it my-otp-container /bin/bash

# Mahdollisia Azure ratkaisuja

### Azure container service

Tässä mallissa OTP ajetaan Azure Container Instances -palvelussa.
Dataesikäsittely, graafin rakentaminen ja itse OTP-palvelu voidaan toteuttaa erillisinä kontteina.
Kaikki pysyvä data säilytetään Azure Filesissa.

GTFS / OSM Sources
│
▼
Preprocessing Container
│
▼
Azure Files
│
▼
Build Container
│
▼
Azure Files
│
▼
OTP Serve Container
│
▼
Users

### Haitat

ACI ei tarjoa valmiina:

- autoskaalausta
- deployment sloteja
- load balancingia
- custom domain -hallintaa

Nämä täytyy toteuttaa erikseen esimerkiksi:

- Azure Front Door
- Application Gateway
- Azure DNS

### Suositeltu käyttötapa

#### Soveltuu tilanteisiin joissa:

- käyttäjämäärä on pieni tai keskisuuri
- kustannukset halutaan minimoida
- graphien rakentaminen on merkittävä osa järjestelmää
- infrastruktuurin halutaan olevan mahdollisimman yksinkertainen

### Azure app services

Suositellaan jatkuasti käynnissä oleville web-palveluille

Tässä mallissa OpenTripPlanner (OTP) toimii jatkuvasti käynnissä olevana web-palveluna Azure App Servicessä. Reititysgraafin (graph.obj) rakentaminen on erotettu omaksi pipeline-vaiheekseen.

OTP-kontin vastuulla on ainoastaan valmiin graafin lataaminen ja API/UI:n tarjoaminen käyttäjille.

Azure files prosessoitujen tiedostojen tallentamiseen: [Azure files](https://learn.microsoft.com/en-us/azure/storage/files/storage-files-introduction)

GTFS / OSM Sources
│
▼
Build Pipeline
│
├─ Download data
├─ Preprocess data
├─ Build graph.obj
│
▼
Azure Files
│
▼
Azure App Service

##### Soveltuu tilanteisiin joissa:

- OTP on jatkuvasti käytössä
- käyttäjiä on paljon
- palvelun saatavuus on tärkeää
- halutaan minimoida ylläpitotyö
