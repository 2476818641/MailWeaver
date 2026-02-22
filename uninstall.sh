#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

print_banner() {
    echo -e "${YELLOW}======================================================${NC}"
    echo -e "${YELLOW}===          邮件服务器卸载脚本              ===${NC}"
    echo -e "${YELLOW}======================================================${NC}"
    echo
}

uninstall_diy() {
    if [[ -d "build" ]]; then
        cd build
    else
        log_error "未找到 build 目录"
        exit 1
    fi
    
    log_warn "此操作将:"
    echo "  1. 停止并删除所有容器"
    echo "  2. 删除数据目录 (data/)"
    echo "  3. 删除所有配置文件"
    echo
    
    confirm_dangerous_operation "完全卸载邮件服务器"
    
    local compose_cmd
    if docker compose version &>/dev/null; then
        compose_cmd="docker compose"
    else
        compose_cmd="docker-compose"
    fi
    
    log_info "正在停止服务..."
    $compose_cmd down 2>/dev/null || true
    
    log_info "正在删除数据..."
    rm -rf data/
    
    cd ..
    log_info "正在删除配置文件..."
    rm -rf build/
    rm -f .env
    
    log_info "卸载完成"
}

uninstall_mailu() {
    if [[ ! -d "mailu_build" ]]; then
        log_error "未找到 Mailu 安装目录 (mailu_build)"
        exit 1
    fi
    
    cd mailu_build
    
    log_warn "此操作将:"
    echo "  1. 停止并删除所有 Mailu 容器"
    echo "  2. 删除 /mailu 目录下的所有数据"
    echo
    
    confirm_dangerous_operation "完全卸载 Mailu"
    
    local compose_cmd
    if docker compose version &>/dev/null; then
        compose_cmd="docker compose"
    else
        compose_cmd="docker-compose"
    fi
    
    log_info "正在停止服务..."
    $compose_cmd down 2>/dev/null || true
    
    cd ..
    log_info "正在删除数据目录 /mailu ..."
    sudo rm -rf /mailu
    
    log_info "正在删除配置..."
    rm -rf mailu_build/
    
    log_info "Mailu 卸载完成"
}

show_help() {
    echo -e "${CYAN}用法:${NC} $0 <方案>"
    echo
    echo "方案:"
    echo -e "  ${GREEN}diy${NC}    卸载 DIY 邮件服务器"
    echo -e "  ${GREEN}mailu${NC}  卸载 Mailu"
    echo
}

main() {
    print_banner
    
    local option="${1:-}"
    
    case "$option" in
        diy)
            uninstall_diy
            ;;
        mailu)
            uninstall_mailu
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            log_error "请指定要卸载的方案"
            show_help
            exit 1
            ;;
    esac
}

main "$@"