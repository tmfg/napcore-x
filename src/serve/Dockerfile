ARG OTP_BASE_IMAGE=docker.io/opentripplanner/opentripplanner:2.9.0

FROM ${OTP_BASE_IMAGE}

WORKDIR /var/opentripplanner

# Fix for CVE-2026-114938: -XX:UseAVX=2
ENV JAVA_OPTS="-Xmx4G -XX:UseAVX=2"

COPY router-config.json /var/opentripplanner/router-config.json
COPY otp-config.json /var/opentripplanner/otp-config.json

COPY src/serve/start-serve.sh /usr/local/bin/start-serve.sh
RUN chmod +x /usr/local/bin/start-serve.sh

ENTRYPOINT ["/usr/local/bin/start-serve.sh"]
