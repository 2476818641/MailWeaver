#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

find_build_dir() {
    if [[ -d "build" ]]; then
        echo "build"
    elif [[ -d "mailu_build" ]]; then
        echo "mailu_build"
    else
        log_error "未找到邮件服务器安装目录"
        exit 1
    fi
}

show_logs() {
    local build_dir
    build_dir=$(find_build_dir)
    local service="${1:-}"
    local lines="${2:-100}"
    
    cd "$build_dir"
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    if [[ -n "$service" ]]; then
        log_info "查看 $service 日志 (最后 $lines 行)..."
        $compose_cmd logs --tail="$lines" -f "$service"
    else
        log_info "查看所有服务日志 (最后 $lines 行)..."
        $compose_cmd logs --tail="$lines" -f
    fi
}

show_help() {
    echo -e "${CYAN}用法:${NC} $0 [服务] [行数]"
    echo
    echo "服务 (可选):"
    echo -e "  ${GREEN}postfix${NC}    - SMTP 服务"
    echo -e "  ${GREEN}dovecot${NC}   - IMAP/POP3 服务"
    echo -e "  ${GREEN}roundcube${NC} - Webmail"
    echo -e "  ${GREEN}mariadb${NC}   - 数据库"
    echo -e "  ${GREEN}vimbadmin${NC} - 管理面板"
    echo -e "  ${GREEN}acme${NC}      - SSL 证书服务"
    echo
    echo "示例:"
    echo -e "  $0                    # 查看所有日志"
    echo -e "  $0 postfix            # 查看 Postfix 日志"
    echo -e "  $0 dovecot 200        # 查看最近 200 行 Dovecot 日志"
}

main() {
    local service="${1:-}"
    local lines="${2:-100}"
    
    case "$service" in
        help|--help|-h)
            show_help
            ;;
        *)
            show_logs "$service" "$lines"
            ;;
    esac
}

main "$@"