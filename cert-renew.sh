#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.lib.sh"

check_environment() {
    local build_dir=""
    
    if [[ -d "${SCRIPT_DIR}/build" ]]; then
        build_dir="${SCRIPT_DIR}/build"
    elif [[ -d "${SCRIPT_DIR}/mailu_build" ]]; then
        build_dir="${SCRIPT_DIR}/mailu_build"
    else
        log_error "未找到邮件服务器安装目录"
        exit 1
    fi
    
    cd "$build_dir"
    
    if [[ ! -f ".env" && "$build_dir" == *"build"* ]]; then
        log_error "未找到 .env 配置文件"
        exit 1
    fi
    
    echo "$build_dir"
}

renew_diy_certs() {
    log_info "检查 DIY 邮件服务器证书续期..."
    
    load_env .env
    
    local test_mode="${1:-false}"
    local acme_cmd="--cron"
    
    if [[ "$test_mode" == "true" ]]; then
        acme_cmd="--force"
        log_warn "测试模式：强制续期证书"
    fi
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    if $compose_cmd ps acme &>/dev/null; then
        log_info "运行 acme.sh 证书续期检查..."

        local log_file="${SCRIPT_DIR}/logs/cert-renew.log"
        mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

        # 记录证书目录修改时间
        local old_mtime
        if [[ -d "./data/certs/${SERVER_HOSTNAME}" ]]; then
            old_mtime=$(stat -c %Y "./data/certs/${SERVER_HOSTNAME}" 2>/dev/null || echo "0")
        else
            old_mtime="0"
        fi
        
        local log_file="${SCRIPT_DIR}/logs/cert-renew.log"
        mkdir -p "$(dirname "$log_file")" 2>/dev/null || true

        # 运行证书续期
        if $compose_cmd run --rm acme $acme_cmd -d "${SERVER_HOSTNAME}" --home /acme.sh 2>&1 | tee -a "$log_file"; then
            log_info "证书检查完成"
            
            # 检查证书是否更新（通过比较修改时间）
            local new_mtime=0
            if [[ -d "./data/certs/${SERVER_HOSTNAME}" ]]; then
                new_mtime=$(stat -c %Y "./data/certs/${SERVER_HOSTNAME}" 2>/dev/null || echo "0")
            fi
            
            if [[ "$new_mtime" -gt "$old_mtime" ]] && [[ "$old_mtime" != "0" ]]; then
                log_info "检测到证书更新，重新加载服务..."
                
                log_info "重新加载 Postfix..."
                $compose_cmd restart postfix || true
                
                log_info "重新加载 Dovecot..."
                $compose_cmd restart dovecot || true
                
                log_info "重新加载 Roundcube..."
                $compose_cmd restart roundcube || true
                
                log_info "服务重新加载完成"
                return 0
            elif [[ "$old_mtime" == "0" ]]; then
                log_info "首次证书检查，服务已配置"
                return 0
            else
                log_info "证书无需更新"
                return 0
            fi
        else
            log_error "证书续期检查失败"
            return 1
        fi
    else
        log_warn "acme 容器未运行，跳过证书续期"
        return 0
    fi
}

renew_mailu_certs() {
    log_info "检查 Mailu 证书续期..."

    local test_mode="${1:-false}"
    local compose_cmd
    compose_cmd=$(get_compose_cmd)

    local acme_running=false
    if $compose_cmd ps --format '{{.Service}}' 2>/dev/null | grep -q "^acme$"; then
        acme_running=true
    fi

    if $acme_running; then
        log_info "Mailu acme 服务自动续期已配置"

        if [[ "$test_mode" == "true" ]]; then
            log_warn "测试模式：手动触发证书续期"
            $compose_cmd exec acme sh -c "acme.sh --force --renew -d ${MAILU_HOSTNAMES:-}" || true
        fi

        return 0
    else
        log_warn "Mailu acme 容器未运行"
        return 0
    fi
}

show_help() {
    echo -e "${CYAN}用法:${NC} $0 [选项]"
    echo
    echo "选项:"
    echo -e "  ${GREEN}--test${NC}        测试模式（强制续期）"
    echo -e "  ${GREEN}--cron${NC}        设置 cron 任务（添加到 crontab）"
    echo -e "  ${GREEN}--help${NC}        显示帮助"
    echo
    echo "示例:"
    echo -e "  $0              # 正常检查证书续期"
    echo -e "  $0 --test       # 测试证书续期"
    echo -e "  $0 --cron       # 添加到 crontab（每天凌晨 2:00 执行）"
}

setup_cron() {
    local script_path="$0"
    local log_file="${SCRIPT_DIR}/logs/cert-renew.log"
    local cron_cmd="0 2 * * * $script_path >> ${log_file} 2>&1"

    log_info "设置证书自动续期 cron 任务..."

    if crontab -l 2>/dev/null | grep -q "cert-renew.sh"; then
        log_warn "cron 任务已存在"
        crontab -l | grep "cert-renew.sh"
        return 0
    fi

    (crontab -l 2>/dev/null; echo "$cron_cmd") | crontab -

    log_info "cron 任务已添加"
    log_info "每天凌晨 2:00 自动检查证书续期"
    log_info "日志文件: $log_file"
    echo
    log_info "查看 cron 任务: crontab -l"
    log_info "删除 cron 任务: crontab -e"
}

main() {
    mkdir -p "${SCRIPT_DIR}/logs"
    
    local action="check"
    local test_mode=false
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --test)
                test_mode=true
                shift
                ;;
            --cron)
                action="cron"
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ "$action" == "cron" ]]; then
        setup_cron
        exit 0
    fi
    
    log_info "========================================"
    log_info "MailWeaver 证书续期脚本 ${VERSION}"
    log_info "========================================"
    echo
    
    local build_dir
    build_dir=$(check_environment)
    
    if [[ "$build_dir" == *"diy"* ]] || [[ "$build_dir" == *"build"* ]]; then
        renew_diy_certs "$test_mode"
    elif [[ "$build_dir" == *"mailu"* ]]; then
        renew_mailu_certs "$test_mode"
    fi
    
    echo
    log_info "证书续期检查完成"
}

main "$@"
