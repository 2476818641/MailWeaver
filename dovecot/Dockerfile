# mailserver-docker/dovecot/Dockerfile
FROM debian:12-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends dovecot-core dovecot-imapd dovecot-pop3d dovecot-lmtpd dovecot-mysql && \
    rm -rf /var/lib/apt/lists/*

COPY ./start.sh /
RUN chmod +x /start.sh

ENTRYPOINT ["/start.sh"]
CMD ["-F"]