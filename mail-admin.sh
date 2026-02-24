#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

check_requirements() {
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        log_error "docker-compose 未找到"
        exit 1
    fi
    
    if [[ ! -f .env ]]; then
        log_error "未找到 .env 配置文件。请先运行 install_diy.sh"
        exit 1
    fi
    
    load_env .env
    
    if [[ -z "${DB_USER:-}" ]] || [[ -z "${DB_PASS:-}" ]] || [[ -z "${DB_NAME:-}" ]]; then
        log_error ".env 文件配置不完整"
        exit 1
    fi
}

db_exec() {
    local sql="$1"
    $(get_compose_cmd) exec -T mariadb mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -N -e "$sql" 2>/dev/null
}

doveadm_exec() {
    $(get_compose_cmd) exec -T dovecot doveadm "$@"
}

add_user() {
    echo -e "${CYAN}--- 添加邮箱用户 ---${NC}"
    
    read -p "请输入邮箱前缀 (e.g., 'info'): " prefix
    while [[ -z "$prefix" ]]; do
        log_error "前缀不能为空"
        read -p "请输入邮箱前缀: " prefix
    done
    
    local email="${prefix}@${SERVER_HOSTNAME}"
    local escaped_email
    escaped_email=$(escape_sql "$email")
    
    read -s -p "请输入密码 (留空自动生成): " password
    echo
    
    if [[ -z "$password" ]]; then
        password=$(generate_strong_password 16)
        log_info "已生成随机密码: $password"
    fi
    
    local domain_id
    domain_id=$(db_exec "SELECT id FROM domains WHERE domain='$(escape_sql "$SERVER_HOSTNAME")' LIMIT 1")
    
    if [[ -z "$domain_id" ]]; then
        log_error "域名 ${SERVER_HOSTNAME} 不存在，请在 ViMbAdmin 中添加"
        exit 1
    fi
    
    local maildir="${SERVER_HOSTNAME}/${prefix}"
    local escaped_maildir
    escaped_maildir=$(escape_sql "$maildir")
    
    local encrypted_password
    encrypted_password=$(doveadm_exec pw -s SHA512-CRYPT -p "$password" 2>/dev/null)
    
    if [[ -z "$encrypted_password" ]]; then
        log_error "密码加密失败"
        exit 1
    fi
    
    local existing
    existing=$(db_exec "SELECT username FROM mailboxes WHERE username='${escaped_email}'")
    
    if [[ -n "$existing" ]]; then
        log_warn "用户 $email 已存在，将更新密码"
        db_exec "UPDATE mailboxes SET password='$(escape_sql "$encrypted_password")', modified=NOW() WHERE username='${escaped_email}'"
    else
        db_exec "INSERT INTO mailboxes (username, password, name, maildir, quota, domain_id, active, created, modified) VALUES ('${escaped_email}', '$(escape_sql "$encrypted_password")', '$(escape_sql "$prefix")', '${escaped_maildir}', 0, ${domain_id}, 1, NOW(), NOW())"
    fi
    
    echo
    log_info "邮箱添加成功!"
    echo -e "  邮箱: ${GREEN}$email${NC}"
    echo -e "  密码: ${GREEN}$password${NC}"
    echo -e "  请妥善保管密码，无法找回${NC}"
    log_operation "ADD_USER $email" "SUCCESS"
}

delete_user() {
    echo -e "${CYAN}--- 删除邮箱用户 ---${NC}"
    
    read -p "请输入要删除的完整邮箱地址: " email
    while [[ -z "$email" ]]; do
        log_error "邮箱地址不能为空"
        read -p "请输入要删除的邮箱地址: " email
    done
    
    local escaped_email
    escaped_email=$(escape_sql "$email")
    
    local existing
    existing=$(db_exec "SELECT username FROM mailboxes WHERE username='${escaped_email}'")
    
    if [[ -z "$existing" ]]; then
        log_warn "邮箱 $email 不存在"
        return 0
    fi
    
    if prompt_yes_no "确认删除邮箱 $email"; then
        db_exec "DELETE FROM mailboxes WHERE username='${escaped_email}'"
        log_info "邮箱 $email 已删除"
        log_operation "DELETE_USER $email" "SUCCESS"
    else
        log_info "操作已取消"
        log_operation "DELETE_USER $email" "CANCELLED"
    fi
}

list_users() {
    echo -e "${CYAN}--- 邮箱用户列表 (${SERVER_HOSTNAME}) ---${NC}"
    echo
    
    local users
    users=$(db_exec "SELECT username, name, quota, active, created FROM mailboxes ORDER BY created DESC")
    
    if [[ -z "$users" ]]; then
        log_info "暂无邮箱用户"
        return 0
    fi
    
    printf "%-30s %-15s %-10s %-8s %s\n" "邮箱" "显示名称" "配额" "状态" "创建时间"
    echo "------------------------------------------------------------------------------------"
    
    echo "$users" | while read -r line; do
        local username name quota active created
        username=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        quota=$(echo "$line" | awk '{print $3}')
        active=$(echo "$line" | awk '{print $4}')
        created=$(echo "$line" | awk '{print $5}')
        
        local status
        [[ "$active" == "1" ]] && status="${GREEN}正常${NC}" || status="${RED}禁用${NC}"
        
        local quota_display
        if [[ "$quota" == "0" ]]; then
            quota_display="无限制"
        else
            quota_display="$((quota / 1024 / 1024))MB"
        fi
        
        printf "%-30s %-15s %-10s %-8b %s\n" "$username" "$name" "$quota_display" "$status" "$created"
    done
}

change_password() {
    echo -e "${CYAN}--- 修改邮箱密码 ---${NC}"
    
    read -p "请输入邮箱地址: " email
    while [[ -z "$email" ]]; do
        log_error "邮箱地址不能为空"
        read -p "请输入邮箱地址: " email
    done
    
    local escaped_email
    escaped_email=$(escape_sql "$email")
    
    local existing
    existing=$(db_exec "SELECT username FROM mailboxes WHERE username='${escaped_email}'")
    
    if [[ -z "$existing" ]]; then
        log_error "邮箱 $email 不存在"
        exit 1
    fi
    
    read -s -p "请输入新密码: " password
    echo

    if ! validate_password_strength "$password"; then
        log_warn "密码强度不足，请重新输入"
        read -s -p "请输入新密码: " password
        echo
        while ! validate_password_strength "$password"; do
            log_warn "密码强度不足，请重新输入"
            read -s -p "请输入新密码: " password
            echo
        done
    fi
    
    local encrypted_password
    encrypted_password=$(doveadm_exec pw -s SHA512-CRYPT -p "$password" 2>/dev/null)
    
    if [[ -z "$encrypted_password" ]]; then
        log_error "密码加密失败"
        exit 1
    fi
    
    db_exec "UPDATE mailboxes SET password='$(escape_sql "$encrypted_password")', modified=NOW() WHERE username='${escaped_email}'"

    log_info "密码修改成功"
    log_operation "CHANGE_PASSWORD $email" "SUCCESS"
}

toggle_user_status() {
    echo -e "${CYAN}--- 启用/禁用邮箱用户 ---${NC}"
    
    read -p "请输入邮箱地址: " email
    while [[ -z "$email" ]]; do
        log_error "邮箱地址不能为空"
        read -p "请输入邮箱地址: " email
    done
    
    local escaped_email
    escaped_email=$(escape_sql "$email")
    
    local current_status
    current_status=$(db_exec "SELECT active FROM mailboxes WHERE username='${escaped_email}'")
    
    if [[ -z "$current_status" ]]; then
        log_error "邮箱 $email 不存在"
        exit 1
    fi
    
    local new_status
    if [[ "$current_status" == "1" ]]; then
        new_status=0
        log_info "正在禁用邮箱 $email"
    else
        new_status=1
        log_info "正在启用邮箱 $email"
    fi
    
    db_exec "UPDATE mailboxes SET active=${new_status}, modified=NOW() WHERE username='${escaped_email}'"

    local status_text
    [[ "$new_status" == "1" ]] && status_text="ENABLED" || status_text="DISABLED"
    [[ "$new_status" == "1" ]] && log_info "邮箱已启用" || log_info "邮箱已禁用"
    log_operation "TOGGLE_USER $email $status_text" "SUCCESS"
}

show_help() {
    echo -e "${CYAN}邮件服务器管理脚本${NC}"
    echo
    echo "用法: $0 <命令>"
    echo
    echo "命令:"
    echo -e "  ${GREEN}add${NC}                  添加邮箱用户"
    echo -e "  ${GREEN}delete${NC}               删除邮箱用户"
    echo -e "  ${GREEN}list${NC}                 列出所有邮箱用户"
    echo -e "  ${GREEN}passwd${NC}               修改邮箱用户密码"
    echo -e "  ${GREEN}toggle${NC}               启用/禁用邮箱用户"
    echo -e "  ${GREEN}logs${NC} [服务]          查看日志 (可选: postfix, dovecot, roundcube, mariadb)"
    echo -e "  ${GREEN}status${NC}               查看服务状态"
    echo -e "  ${GREEN}restart${NC} [服务]       重启服务"
    echo -e "  ${GREEN}help${NC}                 显示帮助"
    echo
}

show_logs() {
    local service="${1:-}"
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    if [[ -z "$service" ]]; then
        $compose_cmd logs -f --tail=100
    else
        $compose_cmd logs -f --tail=100 "$service"
    fi
}

show_status() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    echo -e "${CYAN}=== 服务状态 ===${NC}"
    $compose_cmd ps
    
    echo
    echo -e "${CYAN}=== 资源使用 ===${NC}"
    $compose_cmd stats --no-stream 2>/dev/null || true
}

restart_service() {
    local service="${1:-}"
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    if [[ -z "$service" ]]; then
        log_info "重启所有服务..."
        $compose_cmd restart
    else
        log_info "重启 $service 服务..."
        $compose_cmd restart "$service"
    fi
}

main() {
    check_requirements
    
    local command="${1:-}"
    
    case "$command" in
        add)
            add_user
            ;;
        delete)
            delete_user
            ;;
        list)
            list_users
            ;;
        passwd)
            change_password
            ;;
        toggle)
            toggle_user_status
            ;;
        logs)
            show_logs "${2:-}"
            ;;
        status)
            show_status
            ;;
        restart)
            restart_service "${2:-}"
            ;;
        help|--help|-h)
            show_help
            ;;
        "")
            show_help
            exit 1
            ;;
        *)
            log_error "未知命令: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"