# mailserver-docker/postfix/Dockerfile
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends postfix postfix-mysql procps && \
    rm -rf /var/lib/apt/lists/*

COPY ./start.sh /
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
CMD ["start-fg"]