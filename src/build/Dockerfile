ARG OTP_BASE_IMAGE=docker.io/opentripplanner/opentripplanner:2.9.0

FROM ${OTP_BASE_IMAGE}

WORKDIR /var/opentripplanner

ENV JAVA_OPTS="-Xmx10G"


# jq needed for parsing build-config.json, unzip and zip needed for removing duplicates from data
# TODO: both are temporary solutions?
RUN apt-get update && \
    apt-get install -y --no-install-recommends jq unzip zip && \
    rm -rf /var/lib/apt/lists/*

COPY build-config.json /var/opentripplanner/build-config.json

COPY src/build/start-build.sh /usr/local/bin/start-build.sh
RUN chmod +x /usr/local/bin/start-build.sh

ENTRYPOINT ["/usr/local/bin/start-build.sh"]
