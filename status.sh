#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

get_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

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

show_status() {
    local build_dir
    build_dir=$(find_build_dir)
    
    cd "$build_dir"
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    echo -e "${CYAN}======================================================${NC}"
    echo -e "${CYAN}===              服务状态                      ===${NC}"
    echo -e "${CYAN}======================================================${NC}"
    echo
    
    $compose_cmd ps
    
    echo
    echo -e "${CYAN}=== 资源使用 ===${NC}"
    $compose_cmd stats --no-stream 2>/dev/null || true
    
    echo
    echo -e "${CYAN}=== 端口监听 ===${NC}"
    echo -e "${GREEN}SMTP:${NC}   25 (邮件发送), 465 (SMTPS), 587 (Submission)"
    echo -e "${GREEN}IMAP:${NC}   993 (IMAPS), 995 (POP3S)"
    echo -e "${GREEN}HTTP:${NC}   80 (HTTP), 443 (HTTPS)"
    echo -e "${GREEN}Admin:${NC}  8080 (ViMbAdmin)"
    echo
    
    echo -e "${CYAN}=== 快速检查 ===${NC}"
    
    local all_running=true
    local containers=$($compose_cmd ps -q)
    for container in $containers; do
        local status
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
        if [[ "$status" != "running" ]]; then
            all_running=false
            break
        fi
    done
    
    if $all_running && [[ -n "$containers" ]]; then
        echo -e "所有服务: ${GREEN}运行正常${NC}"
    else
        echo -e "服务状态: ${RED}存在问题${NC}"
    fi
}

show_help() {
    echo -e "${CYAN}用法:${NC} $0"
    echo
    echo "显示邮件服务器服务状态和资源使用情况"
    echo
    echo "示例:"
    echo -e "  $0    # 查看状态"
}

main() {
    case "${1:-}" in
        help|--help|-h)
            show_help
            ;;
        *)
            show_status
            ;;
    esac
}

main "$@"