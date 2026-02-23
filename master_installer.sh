#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

print_banner() {
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}===   ${PROJECT_NAME} 邮件服务器安装脚本 ${VERSION}    ===${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo
}

check_requirements() {
    if [[ ! -d "./templates" ]] || [[ ! -f "./install_diy.sh" ]]; then
        log_error "关键文件或目录未找到"
        exit 1
    fi
    
    check_dependencies
}

install_mailu() {
    echo -e "${CYAN}--- 开始 Mailu 安装向导 ---${NC}"
    
    show_progress "收集配置信息" 1 8
    prompt_for_input MAILU_DOMAIN "请输入您的【主邮件域名】" ""
    while [[ -z "$MAILU_DOMAIN" ]]; do
        log_error "域名不能为空"
        prompt_for_input MAILU_DOMAIN "请输入您的【主邮件域名】" ""
    done
    
    local default_hostnames="mail.${MAILU_DOMAIN}"
    prompt_for_input MAILU_HOSTNAMES "请输入服务器的【完整主机名】" "$default_hostnames"
    prompt_for_input MAILU_POSTMASTER "请输入 Postmaster 用户名" "admin"
    prompt_for_input MAILU_WEBSITE "请输入关联网站 URL" "https://${MAILU_HOSTNAMES}"
    
    echo
    echo -e "${CYAN}--- Cloudflare API (用于 DNS 验证申请证书) ---${NC}"
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
    
    local SECRET_KEY=$(generate_random_string 16)
    local API_TOKEN=$(generate_random_string 32)
    local INITIAL_ADMIN_PASSWORD=$(generate_strong_password 16)
    
    show_progress "创建目录结构" 2 8
    local build_dir="mailu_build"
    rm -rf "$build_dir" && mkdir -p "$build_dir"
    
    sudo mkdir -p /mailu/{redis,data,dkim,certs,filter,mail,mailqueue,overrides,webmail}
    sudo chown -R 10000:10000 /mailu
    
    echo
    show_progress "申请 SSL 证书" 3 8
    sudo rm -rf /mailu/certs/*
    
    if ! sudo docker run --rm \
        -v "/mailu/certs:/acme.sh" \
        --env CF_Key="${CF_Key}" \
        --env CF_Email="${CF_Email}" \
        neilpang/acme.sh:latest \
        --issue --dns dns_cf \
        -d "${MAILU_HOSTNAMES}" \
        --server letsencrypt \
        --quiet 2>&1 | tee /tmp/acme.log; then
        log_error "SSL 证书申请失败！请检查 Cloudflare API Key 和域名"
        log_error "详细日志: /tmp/acme.log"
        sudo rm -rf /mailu/certs/*
        exit 1
    fi
    
    local cert_dir=$(sudo ls /mailu/certs/ | grep "${MAILU_HOSTNAMES}" | head -1)
    if [[ -z "$cert_dir" ]]; then
        log_error "证书目录未找到"
        exit 1
    fi
    
    sudo mv "/mailu/certs/${cert_dir}/fullchain.cer" "/mailu/certs/cert.pem" 2>/dev/null || true
    sudo mv "/mailu/certs/${cert_dir}/privkey.pem" "/mailu/certs/key.pem" 2>/dev/null || true
    sudo rm -rf /mailu/certs/"${cert_dir}"
    log_info "SSL 证书申请成功"
    
    show_progress "生成配置文件" 4 8
    cat > "${build_dir}/mailu.env" <<EOF
MAILU_DOMAIN=${MAILU_DOMAIN}
MAILU_HOSTNAMES=${MAILU_HOSTNAMES}
MAILU_POSTMASTER=${MAILU_POSTMASTER}
WEBSITE=${MAILU_WEBSITE}
SITENAME=${MAILU_HOSTNAMES}
SECRET_KEY=${SECRET_KEY}
API_TOKEN=${API_TOKEN}
TLS_FLAVOR=cert
CF_Email=${CF_Email}
CF_Key=${CF_Key}
EOF
    
    TLS_FLAVOR=cert envsubst < "templates/mailu/docker-compose.yml.template" > "${build_dir}/docker-compose.yml"
    log_info "已生成 ${build_dir}/docker-compose.yml"
    
    cp "templates/mailu/mailu.env.template" "${build_dir}/mailu.env.template"
    sed -i "s|\${MAILU_DOMAIN}|${MAILU_DOMAIN}|g" "${build_dir}/mailu.env"
    sed -i "s|\${MAILU_HOSTNAMES}|${MAILU_HOSTNAMES}|g" "${build_dir}/mailu.env"
    sed -i "s|\${MAILU_POSTMASTER}|${MAILU_POSTMASTER}|g" "${build_dir}/mailu.env"
    sed -i "s|\${WEBSITE}|${WEBSITE}|g" "${build_dir}/mailu.env"
    sed -i "s|\${SITENAME}|${MAILU_HOSTNAMES}|g" "${build_dir}/mailu.env"
    sed -i "s|\${SECRET_KEY}|${SECRET_KEY}|g" "${build_dir}/mailu.env"
    sed -i "s|\${API_TOKEN}|${API_TOKEN}|g" "${build_dir}/mailu.env"
    sed -i "s|TLS_FLAVOR=.*|TLS_FLAVOR=cert|g" "${build_dir}/mailu.env"
    sed -i "s|CF_Email=.*|CF_Email=${CF_Email}|g" "${build_dir}/mailu.env"
    sed -i "s|CF_Key=.*|CF_Key=${CF_Key}|g" "${build_dir}/mailu.env"
    
    log_info "已生成 ${build_dir}/mailu.env"
    
    show_progress "配置自动续期" 5 8
    log_info "正在注入自动续订服务..."
    
    cd "$build_dir"
    
    log_info "正在注入自动续订服务..."
    cat >> docker-compose.yml <<'EOF'

  acme:
    image: neilpang/acme.sh
    restart: always
    environment:
      - CF_Email=${CF_Email}
      - CF_Key=${CF_Key}
    volumes:
      - /mailu/certs:/acme.sh
      - /var/run/docker.sock:/var/run/docker.sock
    command: >
      sh -c "acme.sh --cron --home /acme.sh && 
             acme.sh --install-cert -d ${MAILU_HOSTNAMES} 
             --fullchain-file /acme.sh/cert.pem 
             --key-file /acme.sh/key.pem 
             --reloadcmd 'cd /path/to/mailu_build && docker-compose -p mailu restart front'"
    networks:
      - default
EOF
    
    show_progress "启动 Mailu 服务" 6 8
    echo
    log_info "正在启动 Mailu 服务..."
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    $compose_cmd -p mailu up -d
    
    show_progress "等待服务就绪" 7 8
    echo
    log_info "等待服务启动中..."
    sleep 5
    
    log_info "检查容器健康状态..."
    cd mailu_build
    if $compose_cmd ps &>/dev/null; then
        $compose_cmd ps
    else
        log_warn "无法获取服务状态"
    fi
    cd ..
    
    show_progress "安装完成" 8 8
    echo
    
    echo
    echo -e "${GREEN}======================================================${NC}"
    echo -e "${GREEN}           Mailu 安装完成！${NC}"
    echo -e "${GREEN}======================================================${NC}"
    echo
    echo -e "Web 管理界面: ${CYAN}https://${MAILU_HOSTNAMES}/admin${NC}"
    echo
    echo -e "${YELLOW}[!!] 重要：请立即执行以下命令来创建管理员账户 [!!]${NC}"
    echo
    echo -e "  管理员邮箱: ${CYAN}${MAILU_POSTMASTER}@${MAILU_DOMAIN}${NC}"
    echo -e "  管理员密码: ${CYAN}${INITIAL_ADMIN_PASSWORD}${NC}"
    echo
    echo -e "请复制并运行以下命令:${NC}"
    echo
    echo -e "  ${YELLOW}cd mailu_build && docker compose -p mailu exec admin flask mailu admin ${MAILU_POSTMASTER} ${MAILU_DOMAIN} '${INITIAL_ADMIN_PASSWORD}'${NC}"
    echo
    echo -e "${CYAN}提示: 首次登录后，请在后台获取 DNS 记录并配置${NC}"
    echo
    echo -e "${CYAN}证书 automatically 续期:${NC}"
    echo -e "  已配置自动续期，每天 自动检查"
    echo
    echo -e "${CYAN}管理命令:${NC}"
    echo -e "  cd mailu_build && docker compose -p mailu ps      # 查看状态"
    echo -e "  cd mailu_build && docker compose -p mailu logs -f # 查看日志"
    echo
}

main_menu() {
    print_banner
    
    echo -e "请选择您要安装的邮件服务器方案:${NC}"
    echo
    echo -e "  [${CYAN}1${NC}] ${YELLOW}Mailu${NC} (推荐)"
    echo -e "       功能强大，带现代化 Web 管理后台和 API"
    echo
    echo -e "  [${CYAN}2${NC}] ${YELLOW}DIY Mail Server${NC}"
    echo -e "       轻量级、透明，通过命令行管理"
    echo
    echo -e "  [${CYAN}3${NC}] ${YELLOW}检查更新${NC}"
    echo
    echo -e "  [${CYAN}q${NC}] 退出"
    echo
    
    read -p "请输入您的选择 [1]: " choice
    choice=${choice:-1}
    
    case "$choice" in
        1) install_mailu ;;
        2)
            echo -e "${CYAN}--- 正在调用 DIY Mail Server 安装脚本 ---${NC}"
            if [[ ! -f "./install_diy.sh" ]]; then
                log_error "'install_diy.sh' 脚本未找到"
                exit 1
            fi
            chmod +x ./install_diy.sh
            ./install_diy.sh
            ;;
        3)
            check_for_updates
            exit 0
            ;;
        q|Q)
            echo "安装已取消"
            exit 0
            ;;
        *)
            log_error "无效的选择"
            main_menu
            ;;
    esac
}

main() {
    check_requirements
    main_menu
}

main "$@"