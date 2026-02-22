# mailserver-docker/roundcube/Dockerfile
FROM php:8.2-fpm-alpine

ARG ROUNDCUBE_VERSION=1.6.6
RUN apk add --no-cache nginx curl jq openssl gettext \
    php82-gd php82-xml php82-mbstring php82-intl php82-zip php82-curl php82-imap php82-pdo_mysql && \
    curl -sL "https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz" | tar xz -C /var/www && \
    mv /var/www/roundcubemail-${ROUNDCUBE_VERSION} /var/www/roundcube && \
    chown -R www-data:www-data /var/www/roundcube && \
    rm -rf /var/www/roundcube/installer

COPY conf/nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /
RUN chmod +x /start.sh

EXPOSE 80 443
WORKDIR /var/www/roundcube
ENTRYPOINT ["/start.sh"]