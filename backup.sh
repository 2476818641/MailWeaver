#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

print_banner() {
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}===          邮件服务器备份脚本              ===${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo
}

get_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

backup_diy() {
    local backup_dir="${1:-backups}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [[ ! -d "build" ]]; then
        log_error "未找到 build 目录，请先安装邮件服务器"
        exit 1
    fi
    
    cd build
    
    load_env .env
    
    mkdir -p "$backup_dir"
    
    local backup_name="mailserver_backup_${timestamp}"
    local backup_path="../${backup_dir}/${backup_name}"
    
    log_info "正在创建备份..."
    
    log_info "备份数据库..."
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    $compose_cmd exec -T mariadb mysqldump -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" > "../${backup_dir}/db_dump_${timestamp}.sql" 2>/dev/null || {
        log_error "数据库备份失败"
        exit 1
    }
    
    log_info "备份邮件数据..."
    if [[ -d "data/vmail" ]]; then
        tar -czf "${backup_path}_mail.tar.gz" -C data vmail 2>/dev/null || true
    fi
    
    if [[ -d "data/certs" ]]; then
        tar -czf "${backup_path}_certs.tar.gz" -C data certs 2>/dev/null || true
    fi
    
    log_info "备份配置文件..."
    cp docker-compose.yml "../${backup_dir}/docker-compose_${timestamp}.yml" 2>/dev/null || true
    cp .env "../${backup_dir}/env_${timestamp}.bak" 2>/dev/null || true
    
    cat > "../${backup_dir}/backup_info_${timestamp}.txt" <<EOF
Backup Date: $(date)
Hostname: ${SERVER_HOSTNAME:-Unknown}
Backup Type: DIY Mail Server
EOF
    
    cd ..
    
    log_info "备份完成!"
    echo
    echo -e "${GREEN}备份文件:${NC}"
    ls -lh "${backup_dir}" | grep "$timestamp"
    echo
    echo -e "${CYAN}提示:${NC} 建议将备份文件保存到安全的位置"
}

backup_mailu() {
    local backup_dir="${1:-backups}"
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)
    
    if [[ ! -d "mailu_build" ]]; then
        log_error "未找到 Mailu 安装目录"
        exit 1
    fi
    
    mkdir -p "$backup_dir"
    
    local backup_path="${backup_dir}/mailu_backup_${timestamp}"
    
    log_info "正在备份 Mailu..."
    
    cd mailu_build
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    log_info "备份数据库..."
    $compose_cmd exec -T mariadb mysqldump mailu > "../${backup_path}_db.sql" 2>/dev/null || {
        log_error "数据库备份失败"
        exit 1
    }
    
    log_info "备份数据目录..."
    sudo tar -czf "../${backup_path}_data.tar.gz" -C / mailu 2>/dev/null || true
    
    cd ..
    
    log_info "备份完成!"
    ls -lh "${backup_dir}" | grep "mailu_backup_${timestamp}"
}

restore_diy() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        log_error "请指定备份文件"
        exit 1
    fi
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        exit 1
    fi
    
    if [[ ! -d "build" ]]; then
        log_error "未找到 build 目录"
        exit 1
    fi
    
    confirm_dangerous_operation "恢复备份 (将覆盖现有数据)"
    
    cd build
    
    load_env .env
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    log_info "正在停止服务..."
    $compose_cmd down
    
    local backup_dir
    backup_dir=$(dirname "$(realpath "$backup_file")")
    local backup_name
    backup_name=$(basename "$backup_file" .tar.gz | sed 's/_mail$//')
    
    log_info "恢复邮件数据..."
    if [[ -f "${backup_dir}/${backup_name}_mail.tar.gz" ]]; then
        tar -xzf "${backup_dir}/${backup_name}_mail.tar.gz" -C data/ 2>/dev/null || true
    fi
    
    log_info "恢复证书..."
    if [[ -f "${backup_dir}/${backup_name}_certs.tar.gz" ]]; then
        tar -xzf "${backup_dir}/${backup_name}_certs.tar.gz" -C data/ 2>/dev/null || true
    fi
    
    log_info "启动服务..."
    $compose_cmd up -d mariadb
    
    wait_for_mariadb
    
    log_info "恢复数据库..."
    if [[ -f "${backup_dir}/db_dump_${timestamp}.sql" ]]; then
        local timestamp
        timestamp=$(echo "$backup_name" | sed 's/mailserver_backup_//')
        $compose_cmd exec -T mariadb mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < "${backup_dir}/db_dump_${timestamp}.sql" 2>/dev/null || true
    fi
    
    $compose_cmd up -d
    
    log_info "恢复完成"
}

show_help() {
    echo -e "${CYAN}用法:${NC} $0 <命令> [参数]"
    echo
    echo "命令:"
    echo -e "  ${GREEN}backup${NC} [目录]     备份邮件服务器 (默认: backups)"
    echo -e "  ${GREEN}restore${NC} <文件>    恢复备份"
    echo -e "  ${GREEN}list${NC}              列出可用备份"
    echo
    echo "示例:"
    echo -e "  $0 backup           # 备份到 backups 目录"
    echo -e "  $0 backup /tmp      # 备份到 /tmp 目录"
    echo -e "  $0 restore backups/mailserver_backup_20240101.tar.gz"
    echo
}

list_backups() {
    local backup_dir="${1:-backups}"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_info "暂无备份"
        return
    fi
    
    echo -e "${CYAN}可用备份:${NC}"
    ls -lh "$backup_dir" 2>/dev/null || log_info "目录为空"
}

main() {
    print_banner
    
    local command="${1:-}"
    local arg="${2:-}"
    
    case "$command" in
        backup)
            if [[ -d "build" ]]; then
                backup_diy "$arg"
            elif [[ -d "mailu_build" ]]; then
                backup_mailu "$arg"
            else
                log_error "未找到邮件服务器安装目录"
                exit 1
            fi
            ;;
        restore)
            restore_diy "$arg"
            ;;
        list)
            list_backups "$arg"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            show_help
            exit 1
            ;;
    esac
}

main "$@"