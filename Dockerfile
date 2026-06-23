FROM docker.io/opentripplanner/opentripplanner:latest

WORKDIR /otp

RUN apt-get update && \
    apt-get install -y curl && \
    rm -rf /var/lib/apt/lists/*

ENV JAVA_TOOL_OPTIONS="-Xmx8G"

COPY . /var/opentripplanner/

COPY ./.zscalerrootca.pem /tmp/zscalerrootca.pem

RUN keytool -importcert -noprompt \
  -alias zscalerrootca \
  -file /tmp/zscalerrootca.pem \
  -keystore "$JAVA_HOME/lib/security/cacerts" \
  -storepass changeit

# Download the data using URL's not working currently because of timeout


RUN mkdir -p /var/opentripplanner/data/osm

COPY ./osm/ /var/opentripplanner/data/osm

RUN mkdir -p /opt/otp-data/transit /opt/otp-data/osm && \
    curl --cacert /tmp/zscalerrootca.pem -L \
      "https://mobility.mobility-database.fintraffic.fi/static/napcorexgtfs.zip" \
      -o /opt/otp-data/transit/napcorexgtfs.zip && \
    curl --cacert /tmp/zscalerrootca.pem -L \
      "https://mobility.mobility-database.fintraffic.fi/static/Napcorex.zip" \
      -o /opt/otp-data/transit/Napcorex.zip

# Build the graph when the container starts
CMD ["--build", "--save"]
