#!/bin/bash

# --- 公共函数库 ---
# 包含颜色变量、通用函数、错误处理等

# --- 颜色变量 ---
export GREEN='\033[0;32m'
export RED='\033[0;31m'
export YELLOW='\033[1;33m'
export CYAN='\033[0;36m'
export BLUE='\033[0;34m'
export NC='\033[0m'
export BOLD='\033[1m'

# --- 配置变量 ---
export PROJECT_NAME="MailWeaver"
export VERSION="v1.7"
export CONFIG_FILE=".env"
export BUILD_DIR="build"
export LOG_DIR="logs"

# --- 日志函数 ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_debug() { [[ "$DEBUG" == "1" ]] && echo -e "${BLUE}[DEBUG]${NC} $1" || true; }

# --- 错误处理 ---
set_error_trap() {
    local lineno=$1
    local command=$2
    log_error "执行出错: 命令 '$command' 在第 $lineno 行失败"
    log_error "如需帮助，请查看: https://github.com/bbttca23/MailWeaver/wiki/Troubleshooting"
    exit 1
}

trap 'set_error_trap $LINENO "$BASH_COMMAND"' ERR

# --- 等待服务就绪 ---
wait_for_service() {
    local container=$1
    local service_name=${2:-$container}
    local max_attempts=${3:-30}
    local interval=${4:-2}
    
    log_info "等待 $service_name 服务就绪..."
    local attempt=1
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    while [[ $attempt -le $max_attempts ]]; do
        if $compose_cmd exec -T "$container" echo "ok" &>/dev/null; then
            log_info "$service_name 已就绪"
            return 0
        fi
        echo -n "."
        sleep $interval
        ((attempt++))
    done
    echo
    log_error "$service_name 启动超时 (等待 ${max_attempts} 次)"
    return 1
}

wait_for_mariadb() {
    local max_attempts=60
    local attempt=1
    log_info "等待 MariaDB 服务就绪..."
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    while [[ $attempt -le $max_attempts ]]; do
        if $compose_cmd exec -T mariadb mysqladmin ping -h localhost --silent &>/dev/null; then
            log_info "MariaDB 已就绪"
            return 0
        fi
        echo -n "."
        sleep 2
        ((attempt++))
    done
    echo
    log_error "MariaDB 启动超时"
    return 1
}

# --- 用户输入函数 ---
prompt_for_input() {
    local var_name="$1"
    local prompt_text="$2"
    local default_value="$3"
    local input_value=""
    
    if [[ -n "$default_value" ]]; then
        read -p "$prompt_text [$default_value]: " input_value
        [[ -z "$input_value" ]] && input_value="$default_value"
    else
        read -p "$prompt_text: " input_value
    fi
    
    # 使用间接引用赋值，避免 eval
    declare -g "$var_name=$input_value"
}

prompt_for_password() {
    local var_name="$1"
    local prompt_text="$2"
    local password=""
    
    read -s -p "$prompt_text: " password
    echo
    declare -g "$var_name=$password"
}

prompt_for_password_with_confirm() {
    local var_name="$1"
    local prompt_text="$2"
    local password=""
    local confirm=""
    
    while true; do
        read -s -p "$prompt_text: " password
        echo
        read -s -p "请再次输入密码确认: " confirm
        echo
        if [[ "$password" == "$confirm" ]]; then
            break
        else
            log_warn "两次输入的密码不一致，请重试"
        fi
    done
    
    declare -g "$var_name=$password"
}

prompt_yes_no() {
    local prompt_text="$1"
    local default="${2:-n}"
    local choice=""
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$prompt_text [Y/n]: " choice
            choice=${choice:-y}
        else
            read -p "$prompt_text [y/N]: " choice
            choice=${choice:-n}
        fi
        
        case "$choice" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) log_warn "请输入 y 或 n" ;;
        esac
    done
}

# --- 密码工具 ---
generate_random_string() {
    local length=${1:-16}
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$length"
}

generate_strong_password() {
    local length=${1:-16}
    openssl rand -base64 "$length" | tr -dc 'A-Za-z0-9' | head -c "$length"
}

validate_password_strength() {
    local p="$1"
    if [[ ${#p} -lt 12 ]]; then
        log_error "密码长度必须至少 12 位"
        return 1
    fi
    if [[ ! "$p" =~ [0-9] ]]; then
        log_error "密码必须包含数字"
        return 1
    fi
    if [[ ! "$p" =~ [a-z] ]]; then
        log_error "密码必须包含小写字母"
        return 1
    fi
    if [[ ! "$p" =~ [A-Z] ]]; then
        log_error "密码必须包含大写字母"
        return 1
    fi
    if [[ ! "$p" =~ [[:punct:]] ]]; then
        log_error "密码必须包含特殊字符"
        return 1
    fi
    return 0
}

# --- URL 编码 ---
urlencode() {
    local s="${1}"
    local encoded=""
    local c
    for (( i=0; i<${#s}; i++ )); do
        c=${s:$i:1}
        case "$c" in
            [-_.a-zA-Z0-9]) encoded+="$c" ;;
            *) printf -v o '%%%02x' "'$c"; encoded+="$o" ;;
        esac
    done
    echo "$encoded"
}

# --- SQL 转义 ---
escape_sql() {
    printf '%s' "$1" | sed "s/'/''/g"
}

# --- 检查依赖 ---
check_dependencies() {
    local missing=()
    
    if ! command -v docker &>/dev/null; then
        missing+=("docker")
    fi
    
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        missing+=("docker-compose")
    fi
    
    if ! command -v envsubst &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            log_info "正在安装 gettext-base..."
            sudo apt-get update >/dev/null 2>&1
            sudo apt-get install -y gettext-base >/dev/null 2>&1 || missing+=("gettext-base")
        else
            missing+=("gettext-base")
        fi
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "缺少必要依赖: ${missing[*]}"
        log_error "请安装后再运行"
        exit 1
    fi
}

check_prerequisites() {
    if [[ $EUID -eq 0 ]]; then
        log_warn "建议不要使用 root 用户运行此脚本"
    fi
    
    if ! command -v docker &>/dev/null; then
        log_error "Docker 未安装"
        log_error "请先安装 Docker: https://docs.docker.com/install/"
        exit 1
    fi
    
    if ! docker info &>/dev/null; then
        log_error "Docker 守护进程未运行"
        log_error "请运行: sudo systemctl start docker"
        exit 1
    fi
    
    if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
        log_error "Docker Compose 未安装"
        exit 1
    fi
    
    log_info "环境检查通过"
}

# --- 数据库操作 ---
db_exec() {
    local sql="$1"
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    $compose_cmd exec -T mariadb mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e "$sql" 2>/dev/null
}

db_exec_ignore_error() {
    local sql="$1"
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    $compose_cmd exec -T mariadb mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" -e "$sql" 2>/dev/null || true
}

# --- 备份相关 ---
create_backup() {
    local backup_dir="${1:-backups}"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${backup_dir}/mailserver_backup_${timestamp}.tar.gz"
    
    mkdir -p "$backup_dir"
    
    log_info "正在创建备份..."
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    # 备份数据库
    $compose_cmd exec -T mariadb mysqldump -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" > "${backup_dir}/db_dump_${timestamp}.sql"
    
    # 备份数据目录
    tar -czf "$backup_file" -C "$(dirname "$PWD")" "$(basename "$PWD")/data" 2>/dev/null || true
    
    log_info "备份完成: $backup_file"
    echo "$backup_file"
}

restore_backup() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        log_error "备份文件不存在: $backup_file"
        return 1
    fi
    
    log_warn "此操作将覆盖现有数据，是否继续?"
    if ! prompt_yes_no "确认恢复备份"; then
        log_info "已取消"
        return 1
    fi
    
    log_info "正在恢复备份..."
    
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    # 停止服务
    $compose_cmd down
    
    # 恢复数据
    local backup_dir=$(dirname "$backup_file")
    local timestamp=$(basename "$backup_file" .tar.gz | sed 's/mailserver_backup_//')
    tar -xzf "$backup_file" -C "$(dirname "$PWD")" || true
    
    # 恢复数据库
    if [[ -f "${backup_dir}/db_dump_${timestamp}.sql" ]]; then
        $compose_cmd up -d mariadb
        wait_for_mariadb
        $compose_cmd exec -T mariadb mysql -u"${DB_USER}" -p"${DB_PASS}" "${DB_NAME}" < "${backup_dir}/db_dump_${timestamp}.sql"
    fi
    
    # 重启服务
    $compose_cmd up -d
    
    log_info "备份恢复完成"
}

# --- 版本检查 ---
check_for_updates() {
    local current_version="$VERSION"
    local repo_url="https://api.github.com/repos/bbttca23/MailWeaver/releases/latest"
    
    if command -v curl &>/dev/null; then
        local latest_version=$(curl -s "$repo_url" | grep '"tag_name"' | sed 's/.*"v\([0-9.]*\)".*/\1/')
        
        if [[ "$current_version" != "$latest_version" ]] && [[ -n "$latest_version" ]]; then
            log_warn "有新版本可用: v$latest_version (当前: $current_version)"
            log_info "更新: git pull && ./master_installer.sh"
        else
            log_info "已是最新版本"
        fi
    fi
}

# --- 加载 .env 文件 ---
load_env() {
    local env_file="${1:-.env}"
    if [[ -f "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi
}

# --- 确认危险操作 ---
confirm_dangerous_operation() {
    local operation="$1"
    log_warn "警告: $operation"
    log_warn "此操作不可撤销，是否继续?"
    if ! prompt_yes_no "确认执行"; then
        log_info "操作已取消"
        exit 0
    fi
}

# --- Docker Compose 命令检测 ---
get_compose_cmd() {
    if docker compose version &>/dev/null; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# --- 容器健康检查 ---
check_container_health() {
    local container_name="$1"
    local max_attempts="${2:-30}"
    local interval="${3:-2}"
    
    log_info "检查 $container_name 健康状态..."
    local attempt=1
    while [[ $attempt -le $max_attempts ]]; do
        local health_status
        health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "no-health")
        
        case "$health_status" in
            healthy)
                log_info "$container_name: ${GREEN}健康${NC}"
                return 0
                ;;
            unhealthy)
                log_warn "$container_name: ${YELLOW}不健康${NC}"
                return 1
                ;;
            no-health)
                local running_status
                running_status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "not-found")
                if [[ "$running_status" == "running" ]]; then
                    log_info "$container_name: ${GREEN}运行正常 (无健康检查)${NC}"
                    return 0
                fi
                ;;
        esac
        
        echo -n "."
        sleep "$interval"
        ((attempt++))
    done
    echo
    log_error "$container_name 健康检查超时"
    return 1
}

check_all_containers() {
    local compose_cmd
    compose_cmd=$(get_compose_cmd)
    
    log_info "检查所有容器状态..."
    
    local containers
    containers=$($compose_cmd ps -q 2>/dev/null || true)
    
    if [[ -z "$containers" ]]; then
        log_error "未找到运行中的容器"
        return 1
    fi
    
    local all_ok=true
    for container in $containers; do
        local container_name
        container_name=$(docker inspect --format='{{.Name}}' "$container" 2>/dev/null | sed 's|/||')
        
        if ! check_container_health "$container_name" 15 2; then
            all_ok=false
        fi
    done
    
    if $all_ok; then
        log_info "所有容器检查通过"
        return 0
    else
        log_error "部分容器存在健康问题"
        return 1
    fi
}

# --- 进度显示 ---
show_progress() {
    local message="$1"
    local current="$2"
    local total="$3"
    local percentage=$((current * 100 / total))
    
    local bars=40
    local filled=$((percentage * bars / 100))
    local empty=$((bars - filled))
    
    printf "\r${CYAN}%-20s${NC} [" "$message"
    for ((i=0; i<filled; i++)); do printf "="; done
    for ((i=0; i<empty; i++)); do printf " "; done
    printf "] %3d%%" "$percentage"
    
    if [[ $current -eq $total ]]; then
        echo
    fi
}

show_spinner() {
    local message="$1"
    local pid=$2
    
    local spin="|/-\\"
    local i=0
    
    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i + 1) % 4 ))
        printf "\r${CYAN}%-30s${NC} %c" "$message" "${spin:$i:1}"
        sleep 0.1
    done
    printf "\r${GREEN}%-30s${NC} ${GREEN}✓${NC}\n" "$message"
}