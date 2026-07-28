FROM docker.io/opentripplanner/opentripplanner:2.8.1

WORKDIR /var/opentripplanner

ENV JAVA_OPTS="-Xmx8G"

COPY router-config.json /var/opentripplanner/router-config.json

COPY src/serve/start-serve.sh /usr/local/bin/start-serve.sh
RUN chmod +x /usr/local/bin/start-serve.sh

ENTRYPOINT ["/usr/local/bin/start-serve.sh"]
