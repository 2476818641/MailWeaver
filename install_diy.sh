#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

print_banner() {
    echo -e "${CYAN}===========================================================${NC}"
    echo -e "${CYAN}===  DIY 邮件服务器 & ViMbAdmin 管理面板 安装向导   ===${NC}"
    echo -e "${CYAN}===========================================================${NC}"
    echo
}

check_existing_build() {
    if [[ -d "build" ]]; then
        log_warn "检测到已存在的 'build' 目录"
        if prompt_yes_no "重新运行将覆盖所有配置，确定要继续吗"; then
            log_info "将继续安装..."
        else
            log_info "安装已取消"
            exit 0
        fi
    fi
}

collect_config() {
    echo -e "${CYAN}--- 1. 基础信息配置 ---${NC}"
    prompt_for_input SERVER_HOSTNAME "请输入服务器的 FQDN" ""
    while [[ -z "$SERVER_HOSTNAME" ]]; do
        log_error "主机名不能为空"
        prompt_for_input SERVER_HOSTNAME "请输入服务器的 FQDN" ""
    done
    
    prompt_for_input LETS_ENCRYPT_EMAIL "请输入用于 Let's Encrypt 的邮箱地址" ""
    while [[ -z "$LETS_ENCRYPT_EMAIL" ]]; do
        log_error "邮箱不能为空"
        prompt_for_input LETS_ENCRYPT_EMAIL "请输入用于 Let's Encrypt 的邮箱地址" ""
    done
    
    echo
    echo -e "${CYAN}--- 2. Cloudflare API ---${NC}"
    prompt_for_input CF_Email "请输入 Cloudflare 登录邮箱" ""
    while [[ -z "$CF_Email" ]]; do
        log_error "邮箱不能为空"
        prompt_for_input CF_Email "请输入 Cloudflare 登录邮箱" ""
    done
    
    prompt_for_password CF_Key "请输入 Cloudflare Global API Key"
    while [[ -z "$CF_Key" ]]; do
        log_error "API Key 不能为空"
        prompt_for_password CF_Key "请输入 Cloudflare Global API Key"
    done
    
    echo
    echo -e "${CYAN}--- 3. 数据库密码 ---${NC}"
    prompt_for_password_with_confirm DB_ROOT_PASSWORD "请输入新的 MariaDB root 密码"
    while ! validate_password_strength "$DB_ROOT_PASSWORD"; do
        log_warn "密码强度不足，请重新输入"
        prompt_for_password_with_confirm DB_ROOT_PASSWORD "请输入新的 MariaDB root 密码"
    done
    
    prompt_for_password_with_confirm DB_PASS_PLAIN "请输入邮件数据库用户(mailadmin)的密码"
    while ! validate_password_strength "$DB_PASS_PLAIN"; do
        log_warn "密码强度不足，请重新输入"
        prompt_for_password_with_confirm DB_PASS_PLAIN "请输入邮件数据库用户(mailadmin)的密码"
    done
    
    echo
    echo -e "${CYAN}--- 4. ViMbAdmin 管理面板设置 ---${NC}"
    prompt_for_password_with_confirm VIMBADMIN_ADMIN_PASS "请输入 ViMbAdmin 后台的超级管理员密码"
    while ! validate_password_strength "$VIMBADMIN_ADMIN_PASS"; do
        log_warn "密码强度不足，请重新输入"
        prompt_for_password_with_confirm VIMBADMIN_ADMIN_PASS "请输入 ViMbAdmin 后台的超级管理员密码"
    done
    
    log_info "信息收集完毕，准备生成配置文件..."
}

prepare_build_dir() {
    log_info "正在准备工作目录 'build'..."
    rm -rf build && mkdir -p build
    cd build
}

generate_env_file() {
    log_info "正在生成 .env 文件..."
    DB_PASS_ENCODED=$(urlencode "$DB_PASS_PLAIN")
    DES_KEY=$(openssl rand -base64 24 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 24)
    
    cat > .env <<EOF
SERVER_HOSTNAME=${SERVER_HOSTNAME}
LETS_ENCRYPT_EMAIL=${LETS_ENCRYPT_EMAIL}
CF_Email=${CF_Email}
CF_Key=${CF_Key}
MYSQL_ROOT_PASSWORD=${DB_ROOT_PASSWORD}
DB_NAME=mailserver
DB_USER=mailadmin
DB_PASS=${DB_PASS_PLAIN}
DB_PASS_ENCODED=${DB_PASS_ENCODED}
DES_KEY=${DES_KEY}
VMAIL_UID=205
VMAIL_GID=205
VIMBADMIN_ADMIN_PASS=${VIMBADMIN_ADMIN_PASS}
EOF
}

generate_docker_compose() {
    log_info "正在生成 docker-compose.yml..."
    
    cat > docker-compose.yml <<'EOF'
services:
  mariadb:
    image: mariadb:10.11
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${DB_NAME}
      MYSQL_USER: ${DB_USER}
      MYSQL_PASSWORD: ${DB_PASS}
    volumes:
      - ./data/mariadb:/var/lib/mysql
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - mail-network
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      timeout: 5s
      retries: 5

  postfix:
    build: ../postfix
    restart: always
    hostname: ${SERVER_HOSTNAME}
    environment:
      SERVER_HOSTNAME: ${SERVER_HOSTNAME}
      DB_USER: ${DB_USER}
      DB_PASS: ${DB_PASS}
      DB_NAME: ${DB_NAME}
      VMAIL_UID: ${VMAIL_UID}
      VMAIL_GID: ${VMAIL_GID}
    volumes:
      - ./data/certs:/certs
      - ./data/vmail:/var/mail/vhosts
      - ./data/postfix-spool:/var/spool/postfix
    ports:
      - "25:25"
      - "465:465"
      - "587:587"
    depends_on:
      mariadb:
        condition: service_healthy
    labels:
      - "acme.sh.reload.container=postfix"
    networks:
      - mail-network

  dovecot:
    build: ../dovecot
    restart: always
    environment:
      SERVER_HOSTNAME: ${SERVER_HOSTNAME}
      DB_USER: ${DB_USER}
      DB_PASS: ${DB_PASS}
      DB_NAME: ${DB_NAME}
      VMAIL_UID: ${VMAIL_UID}
      VMAIL_GID: ${VMAIL_GID}
    volumes:
      - ./data/certs:/certs
      - ./data/vmail:/var/mail/vhosts
    ports:
      - "993:993"
      - "995:995"
    depends_on:
      mariadb:
        condition: service_healthy
    labels:
      - "acme.sh.reload.container=dovecot"
    networks:
      - mail-network

  roundcube:
    build: ../roundcube
    restart: always
    environment:
      SERVER_HOSTNAME: ${SERVER_HOSTNAME}
      DB_USER: ${DB_USER}
      DB_PASS_ENCODED: ${DB_PASS_ENCODED}
      DB_NAME: ${DB_NAME}
      DES_KEY: ${DES_KEY}
    volumes:
      - ./data/certs:/certs
    ports:
      - "80:80"
      - "443:443"
    depends_on:
      mariadb:
        condition: service_healthy
    labels:
      - "acme.sh.reload.container=roundcube"
    networks:
      - mail-network

  vimbadmin:
    image: ghcr.io/vimbadmin/vimbadmin:latest
    restart: always
    environment:
      VIMBADMIN_DB_HOST: mariadb
      VIMBADMIN_DB_USERNAME: ${DB_USER}
      VIMBADMIN_DB_PASSWORD: ${DB_PASS}
      VIMBADMIN_DB_DATABASE: ${DB_NAME}
      VIMBADMIN_SUPERUSER_PASSWORD: ${VIMBADMIN_ADMIN_PASS}
      VIMBADMIN_SERVER_HOSTNAME: ${SERVER_HOSTNAME}
    ports:
      - "8080:80"
    depends_on:
      mariadb:
        condition: service_healthy
    networks:
      - mail-network

  acme:
    image: neilpang/acme.sh
    restart: always
    environment:
      CF_Email: ${CF_Email}
      CF_Key: ${CF_Key}
    volumes:
      - ./data/certs:/acme.sh
      - /var/run/docker.sock:/var/run/docker.sock
    command: daemon
    networks:
      - mail-network

networks:
  mail-network:
    driver: bridge
EOF
}

generate_init_sql() {
    log_info "正在生成数据库 Schema..."
    
    cat > init.sql <<'EOF'
CREATE TABLE IF NOT EXISTS `admins` (
    `id` int(10) unsigned NOT NULL auto_increment,
    `username` varchar(255) NOT NULL,
    `password` varchar(255) NOT NULL,
    `super` tinyint(1) NOT NULL DEFAULT '0',
    `active` tinyint(1) NOT NULL DEFAULT '1',
    `created` datetime NOT NULL,
    `modified` datetime NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `domains` (
    `id` int(10) unsigned NOT NULL auto_increment,
    `domain` varchar(255) NOT NULL,
    `description` varchar(255) NOT NULL,
    `aliases` int(10) NOT NULL DEFAULT '0',
    `mailboxes` int(10) NOT NULL DEFAULT '0',
    `max_quota` bigint(20) NOT NULL DEFAULT '0',
    `quota` bigint(20) NOT NULL DEFAULT '0',
    `transport` varchar(255) NOT NULL DEFAULT 'virtual',
    `backup_mx` tinyint(1) NOT NULL DEFAULT '0',
    `active` tinyint(1) NOT NULL DEFAULT '1',
    `created` datetime NOT NULL,
    `modified` datetime NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `domain` (`domain`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `mailboxes` (
    `id` int(10) unsigned NOT NULL auto_increment,
    `username` varchar(255) NOT NULL,
    `password` varchar(255) NOT NULL,
    `name` varchar(255) NOT NULL,
    `maildir` varchar(255) NOT NULL,
    `quota` bigint(20) NOT NULL DEFAULT '0',
    `domain_id` int(10) unsigned NOT NULL,
    `active` tinyint(1) NOT NULL DEFAULT '1',
    `created` datetime NOT NULL,
    `modified` datetime NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `username` (`username`),
    KEY `domain_id` (`domain_id`),
    CONSTRAINT `mailboxes_ibfk_1` FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `aliases` (
    `id` int(10) unsigned NOT NULL auto_increment,
    `address` varchar(255) NOT NULL,
    `goto` text NOT NULL,
    `domain_id` int(10) unsigned NOT NULL,
    `active` tinyint(1) NOT NULL DEFAULT '1',
    `created` datetime NOT NULL,
    `modified` datetime NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `address` (`address`),
    KEY `domain_id` (`domain_id`),
    CONSTRAINT `aliases_ibfk_1` FOREIGN KEY (`domain_id`) REFERENCES `domains` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
EOF
}

prepare_dockerfiles() {
    log_info "正在准备 Dockerfiles 和启动脚本..."
    
    mkdir -p postfix dovecot roundcube/conf
    
    cp ../postfix/Dockerfile ./postfix/
    cp ../dovecot/Dockerfile ./dovecot/
    cp ../roundcube/Dockerfile ./roundcube/
    cp ../roundcube/conf/nginx.conf.template ./roundcube/conf/
    
    cat > ./postfix/start.sh <<'POSTFIX_START'
#!/bin/bash
set -e

groupadd -g ${VMAIL_GID} vmail 2>/dev/null || true
useradd -u ${VMAIL_UID} -g vmail -d /var/mail/vhosts -s /usr/sbin/nologin vmail 2>/dev/null || true
chown -R vmail:vmail /var/mail/vhosts

cat > /etc/postfix/mysql-virtual-domains-maps.cf <<EOF
user = ${DB_USER}
password = ${DB_PASS}
hosts = mariadb
dbname = ${DB_NAME}
query = SELECT 1 FROM domains WHERE domain='%s' AND active = 1
EOF

cat > /etc/postfix/mysql-virtual-mailbox-maps.cf <<EOF
user = ${DB_USER}
password = ${DB_PASS}
hosts = mariadb
dbname = ${DB_NAME}
query = SELECT 1 FROM mailboxes WHERE username='%s' AND active = 1
EOF

cat > /etc/postfix/mysql-virtual-alias-maps.cf <<EOF
user = ${DB_USER}
password = ${DB_PASS}
hosts = mariadb
dbname = ${DB_NAME}
query = SELECT goto FROM aliases WHERE address='%s' AND active = 1
EOF

chmod 640 /etc/postfix/mysql-*.cf
chgrp postfix /etc/postfix/mysql-*.cf

postconf -e "myhostname = ${SERVER_HOSTNAME}"
postconf -e "virtual_mailbox_domains = proxy:mysql:/etc/postfix/mysql-virtual-domains-maps.cf"
postconf -e "virtual_mailbox_maps = proxy:mysql:/etc/postfix/mysql-virtual-mailbox-maps.cf"
postconf -e "virtual_alias_maps = proxy:mysql:/etc/postfix/mysql-virtual-alias-maps.cf"
postconf -e "virtual_transport = lmtp:unix:private/dovecot-lmtp"
postconf -e "virtual_mailbox_base = /var/mail/vhosts"

postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"

postconf -e "smtpd_tls_cert_file = /certs/${SERVER_HOSTNAME}/fullchain.cer"
postconf -e "smtpd_tls_key_file = /certs/${SERVER_HOSTNAME}/privkey.pem"
postconf -e "smtpd_tls_security_level = may"

postconf -M submission/inet="submission inet n - y - - smtpd"
postconf -P "submission/inet/smtpd_tls_security_level=encrypt"
postconf -P "submission/inet/smtpd_sasl_auth_enable=yes"

postconf -M smtps/inet="smtps inet n - y - - smtpd"
postconf -P "smtps/inet/smtpd_tls_wrappermode=yes"
postconf -P "smtps/inet/smtpd_sasl_auth_enable=yes"

exec /usr/sbin/postfix start-fg
POSTFIX_START
    
    cat > ./dovecot/start.sh <<'DOVECOT_START'
#!/bin/bash
set -e

cat > /etc/dovecot/dovecot-sql.conf.ext <<EOF
driver = mysql
connect = host=mariadb dbname=${DB_NAME} user=${DB_USER} password=${DB_PASS}
password_query = SELECT username as user, password FROM mailboxes WHERE username = '%u' AND active = 1
user_query = SELECT maildir, ${VMAIL_UID} AS uid, ${VMAIL_GID} AS gid FROM mailboxes WHERE username = '%u' AND active = 1
EOF

chmod 640 /etc/dovecot/dovecot-sql.conf.ext

sed -i 's/^#*!include auth-system.conf.ext/!include auth-sql.conf.ext/' /etc/dovecot/conf.d/10-auth.conf
sed -i "s|^#*mail_location.*|mail_location = maildir:/var/mail/vhosts/%d/%n|" /etc/dovecot/conf.d/10-mail.conf
sed -i "s|^#*ssl_cert = .*|ssl_cert = </certs/${SERVER_HOSTNAME}/fullchain.cer|" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^#*ssl_key = .*|ssl_key = </certs/${SERVER_HOSTNAME}/privkey.pem|" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s/^#*ssl = .*/ssl = required/" /etc/dovecot/conf.d/10-ssl.conf

cat > /etc/dovecot/conf.d/10-master.conf <<'EOF'
service imap-login {
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}

service pop3-login {
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}

service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0660
    user = postfix
    group = postfix
  }
}

service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF

chown -R vmail:dovecot /etc/dovecot
chmod -R o-rwx /etc/dovecot

exec /usr/sbin/dovecot -F
DOVECOT_START
    
    cat > ./roundcube/start.sh <<'ROUNDCUBE_START'
#!/bin/bash
set -e

mkdir -p /var/www/roundcube/config

cat > /var/www/roundcube/config/config.inc.php <<EOF
<?php
\$config = [];
\$config['db_dsnw'] = 'mysql://${DB_USER}:${DB_PASS_ENCODED}@mariadb/${DB_NAME}';
\$config['default_host'] = 'ssl://${SERVER_HOSTNAME}';
\$config['smtp_server'] = 'ssl://${SERVER_HOSTNAME}';
\$config['smtp_port'] = 465;
\$config['smtp_user'] = '%u';
\$config['smtp_pass'] = '%p';
\$config['product_name'] = 'Webmail';
\$config['des_key'] = '${DES_KEY}';
\$config['plugins'] = ['password', 'archive', 'zipdownload'];
\$config['enable_html'] = true;
\$config['draft_autosave'] = 60;
\$config['login_lc'] = 2;
EOF

chown www-data:www-data /var/www/roundcube/config/config.inc.php
chmod 640 /var/www/roundcube/config/config.inc.php

envsubst '${SERVER_HOSTNAME}' < /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf

php-fpm &
exec nginx -g 'daemon off;'
ROUNDCUBE_START
    
    chmod +x postfix/start.sh dovecot/start.sh roundcube/start.sh
}

request_ssl_certificate() {
    local cert_path="./data/certs/${SERVER_HOSTNAME}/fullchain.cer"
    
    if [[ -f "$cert_path" ]]; then
        log_info "证书已存在，跳过申请"
        return 0
    fi
    
    log_info "正在申请 SSL 证书..."
    rm -rf ./data/certs
    mkdir -p ./data/certs
    
    if ! docker run --rm \
        -v "$(pwd)/data/certs:/acme.sh" \
        --env CF_Key="${CF_Key}" \
        --env CF_Email="${CF_Email}" \
        neilpang/acme.sh:latest \
        --issue --dns dns_cf \
        -d "${SERVER_HOSTNAME}" \
        --server letsencrypt \
        --quiet 2>&1; then
        log_error "SSL 证书申请失败"
        rm -rf ./data/certs
        exit 1
    fi
    
    log_info "SSL 证书申请成功"
}

build_and_start() {
    log_info "正在构建并启动所有服务..."
    docker-compose up -d --build
    
    log_info "等待 MariaDB 就绪..."
    wait_for_mariadb
    
    log_info "正在初始化数据库..."
    sleep 5
    
    local escaped_domain
    escaped_domain=$(printf '%s' "$SERVER_HOSTNAME" | sed 's/"/\\"/g')
    
    docker-compose exec -T mariadb mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" \
        -e "INSERT IGNORE INTO domains (domain, description, transport, created, modified) VALUES ('${escaped_domain}', 'Default Domain', 'virtual', NOW(), NOW());" 2>/dev/null || true
}

print_completion() {
    rm -f .env
    
    echo
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}    DIY Mail Server with ViMbAdmin 安装完成！    ${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo
    echo -e "Roundcube Webmail:   ${CYAN}https://${SERVER_HOSTNAME}${NC}"
    echo -e "ViMbAdmin 管理后台:  ${CYAN}http://${SERVER_HOSTNAME}:8080${NC}"
    echo
    echo -e "${YELLOW}[!!] 重要：请立即登录 ViMbAdmin 管理后台 [!!]${NC}"
    echo
    echo -e "  用户名: ${CYAN}superadmin@local${NC}"
    echo -e "  密码:    (您在安装时设置的密码)"
    echo
    echo -e "${CYAN}提示:${NC}"
    echo -e "  1. 登录后，在 'Domains' 页面激活域名"
    echo -e "  2. 然后在 'Mailboxes' 页面创建邮箱"
    echo -e "  3. 配置 DNS 记录 (A, MX, SPF, DMARC)"
    echo
    echo -e "${CYAN}管理命令:${NC}"
    echo -e "  cd build && docker-compose ps        # 查看状态"
    echo -e "  cd build && docker-compose logs -f   # 查看日志"
    echo -e "  cd build && ./mail-admin.sh add      # 添加邮箱"
    echo
}

main() {
    print_banner
    check_existing_build
    collect_config
    prepare_build_dir
    generate_env_file
    generate_docker_compose
    generate_init_sql
    prepare_dockerfiles
    request_ssl_certificate
    build_and_start
    print_completion
}

main "$@"