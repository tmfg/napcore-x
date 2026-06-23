## Set Up

Opentripplanner jar-file: https://repo1.maven.org/maven2/org/opentripplanner/otp-shaded/2.8.1/

Jar-tiedosto lis„t„„n projektin kantaan jonka j„lkeen opentripplanner k„ynnistet„„n alla olevilla komennoilla.

### OpenTripPlanner / Terminaalista ajo

OTP docs: https://docs.opentripplanner.org/en/latest/Basic-Tutorial/

simple-step-server:

'$ java -Xmx4G -jar otp-shaded-2.8.1.jar --build --serve .'
http://localhost:8080/

Graafin tallennus ja valmiista graafista k„ynnistys:

Graafin tallennus:
'$ java -Xmx4G -jar otp-shaded-2.8.1.jar --build --save .'

Valmiista graafista k„ynnistys:
'$ java -Xmx4G -jar otp-shaded-2.8.1.jar --load .'

### NeTEx

NeTEx data tools: https://data4pt.org/w/index.php/NeTEX

### OSM

OSM: https://www.openstreetmap.org/#map=8/59.115/25.009&layers=D
--> Yl„kulman "navigointi -> export" saa ladattua alueen. T„m„ vain pienille alueille (yksitt„iset kaupungit)

Suuremmat alueet: https://download.geofabrik.de/europe.html
Geofabrikista voi ladata suuremman alueen (esim. Viro) ja t„t„ aluetta voidaan konvertoida pienemm„ksi osmconvert toolilla.

osmconvert:
'sudo apt install osmctools'
'osmconvert <originalOSM.osm.pbf> -b=<Bounding tool coordinates> --complete-ways -o=<konvertoituOSM>.pbf'

OSM Bounding tool: https://boundingbox.klokantech.com/
Vasemmalta alakulmasta CSV-formaatti tarjoaa valmiiksi oikean muodon osmconvert komennossa k„ytett„v„lle parametrille.

### Data

Data on t„ll„ hetkell„ jaettu GTFS, OSM ja NeTEx kansioihin, joista Build-config.json tiedostossa m„„ritell„„n datojen sijainti. T„ss„ on ehk„ mahdollisuus k„ytt„„ Jaakon tarjoamia https linkkej„ datan saavuttamiseen. Nyt Zip paketit ladattuna ja sijoitettuna aiemmin mainittuihin kansioihin.

### DOCKER

Build image Dockerfilen pohjalta:

podman build -t my-otp .

Kontin k„ynnistys
podman run -d --name my-otp-container -p 8080:8080 localhost/my-otp

Kontin bash:
podman exec -it my-otp-container /bin/bash
