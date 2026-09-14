ARG OTP_BASE_IMAGE=docker.io/opentripplanner/opentripplanner:2.9.0

FROM ${OTP_BASE_IMAGE}

WORKDIR /var/opentripplanner

ENV JAVA_OPTS="-Xmx4G"

COPY router-config.json /var/opentripplanner/router-config.json
COPY otp-config.json /var/opentripplanner/otp-config.json

COPY src/serve/start-serve.sh /usr/local/bin/start-serve.sh
RUN chmod +x /usr/local/bin/start-serve.sh

ENTRYPOINT ["/usr/local/bin/start-serve.sh"]
