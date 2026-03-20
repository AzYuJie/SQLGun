#!/bin/bash
# common.sh - sqlgun 公共函数库
# 供 execute-sql.sh 和 execute-sql-file.sh 调用

CONFIG_DIR="${HOME}/.config/sqlgun"
ENV_FILE="${CONFIG_DIR}/.env"
LOG_DIR="${CONFIG_DIR}/logs"
TIMEOUT=30

# 生成会话ID（用于日志文件名）
SESSION_ID="${CLAUDE_SESSION_ID:-$(date +%Y%m%d_%H%M%S)_$$_$RANDOM}"
LOG_FILE="${LOG_DIR}/$(date +%Y%m%d)_${SESSION_ID}.log"

# 创建日志目录
mkdir -p "${LOG_DIR}"

# ============================================
# 日志函数
# ============================================
write_log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "${LOG_FILE}"
}

log_start() {
    write_log "=== $1 Started ==="
    write_log "Connection: ${CONNECTION:-main}"
    write_log "Session ID: ${SESSION_ID}"
}

log_end() {
    write_log "=== $1 Ended ==="
}

# ============================================
# 环境变量加载
# ============================================
load_env_config() {
    if [[ -f "${ENV_FILE}" ]]; then
        set -a
        source "${ENV_FILE}"
        set +a
    else
        echo "[error] 配置文件不存在: ${ENV_FILE}"
        echo "[info] 请创建 ~/.config/sqlgun/.env"
        exit 1
    fi
}

# ============================================
# 连接配置解析
# ============================================
get_env_prefix() {
    local conn="$1"
    if [[ "${conn}" == "main" ]]; then
        echo "DB"
    else
        echo "$(echo "${conn}" | tr '[:lower:]' '[:upper:]')_DB"
    fi
}

load_connection_params() {
    local conn="$1"
    PREFIX=$(get_env_prefix "${conn}")

    USER_VAR="${PREFIX}_USER"
    PASS_VAR="${PREFIX}_PASS"
    HOST_VAR="${PREFIX}_HOST"
    PORT_VAR="${PREFIX}_PORT"
    NAME_VAR="${PREFIX}_NAME"
    DRIVER_VAR="${PREFIX}_DRIVER"

    USER="${!USER_VAR}"
    PASS="${!PASS_VAR}"
    HOST="${!HOST_VAR}"
    PORT="${!PORT_VAR:-5432}"
    NAME="${!NAME_VAR}"
    DRIVER="${!DRIVER_VAR:-postgres}"

    # 检查配置完整性
    if [[ -z "${USER}" ]] || [[ -z "${PASS}" ]] || [[ -z "${HOST}" ]] || [[ -z "${NAME}" ]]; then
        echo "[error] 连接 [${conn}] 的配置不完整"
        echo "[info] 需要设置: ${USER_VAR}, ${PASS_VAR}, ${HOST_VAR}, ${NAME_VAR}"
        exit 1
    fi
}

# ============================================
# URL 构建
# ============================================
build_url() {
    local driver="$1"
    case "${driver}" in
        postgres|postgres9|redshift|cockroach|pgx)
            echo "postgres://${USER}:${PASS}@${HOST}:${PORT}/${NAME}?sslmode=disable"
            ;;
        mysql|mysql2|mariadb|percona)
            echo "mysql://${USER}:${PASS}@${HOST}:${PORT}/${NAME}"
            ;;
        sqlserver|mssql)
            echo "sqlserver://${USER}:${PASS}@${HOST}:${PORT}/${NAME}"
            ;;
        sqlite)
            echo "sqlite:${NAME}"
            ;;
        *)
            echo "postgres://${USER}:${PASS}@${HOST}:${PORT}/${NAME}?sslmode=disable"
            ;;
    esac
}

# ============================================
# 过期日志检查
# ============================================
check_old_logs() {
    if [[ ! -d "${LOG_DIR}" ]]; then
        return
    fi

    local old_logs=$(find "${LOG_DIR}" -name "*.log" -mtime +30 2>/dev/null)
    local old_count=$(echo "${old_logs}" | wc -l | tr -d ' ')

    if [[ ${old_count} -gt 5 ]]; then
        echo "[info] 发现 ${old_count} 个超过30天的旧日志文件"
        echo "[info] 如需清理，请执行: rm ${LOG_DIR}/*.log -mtime +30"
        write_log "Info: Found ${old_count} log files older than 30 days"
    fi
}

# ============================================
# 参数解析
# ============================================
parse_connection_arg() {
    # 方式1: execute-sql.sh [prod] "SELECT ..."（显式指定连接名）
    if [[ "$1" =~ ^\[([a-zA-Z0-9_]+)\]$ ]]; then
        CONNECTION="${BASH_REMATCH[1]}"
        PARAMS_SHIFTED=1
    # 方式2: execute-sql.sh prod "SELECT ..."（直接用连接名）
    elif [[ -n "$1" ]] && [[ "$1" != \[* ]] && [[ -n "$2" ]]; then
        CONNECTION="$1"
        PARAMS_SHIFTED=1
    # 方式3: execute-sql.sh "SELECT ..."（默认 main）
    else
        CONNECTION="main"
        PARAMS_SHIFTED=0
    fi
}
