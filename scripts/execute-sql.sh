#!/bin/bash
# execute-sql.sh - 通过 usql 执行 SQL（支持多数据库）
# 用法: execute-sql.sh [connection_name] "SQL"
#   或: execute-sql.sh "SQL"  (使用默认连接 main)

set -o pipefail

# 加载公共函数库
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/common.sh"

# 重置连接名和SQL变量
CONNECTION=""
SQL=""

# 加载环境变量
load_env_config

# 解析参数
parse_connection_arg "$@"
# 根据解析结果决定是否移位
if [[ "${PARAMS_SHIFTED}" == "1" ]]; then
    shift
fi
SQL="$*"

# 检查 SQL 是否为空
if [[ -z "${SQL}" ]]; then
    echo "[error] 未提供 SQL 语句"
    echo "[info] 用法: execute-sql.sh [连接名] \"SQL\""
    exit 1
fi

# 加载连接参数
load_connection_params "${CONNECTION}"

# 构建URL并记录日志
URL=$(build_url "${DRIVER}")
write_log "SQL: ${SQL}"

# 执行 SQL 并计时
START_TIME=$(date +%s.%N)

# 使用 perl 实现跨平台 timeout（macOS 默认无 timeout 命令）
ERROR_OUTPUT=$(perl -e 'alarm 30; exec @ARGV' usql "${URL}" -c "${SQL}" 2>&1)
EXIT_CODE=$?
END_TIME=$(date +%s.%N)
EXEC_TIME=$(echo "${END_TIME} - ${START_TIME}" | bc)

# 处理超时信号（EXIT_CODE=142 表示 alarm 触发）
if [[ ${EXIT_CODE} -eq 142 ]]; then
    echo "[error] 执行超时（30秒）"
    echo "[info] 建议: (1)添加LIMIT限制返回行数,(2)优化查询条件,(3)检查是否缺索引"
    write_log "Result: TIMEOUT (30s exceeded)"
    exit 1
fi

# 输出结果
DIVIDER="----------------------------------------"
echo "${DIVIDER}"
echo "[${CONNECTION}] > ${SQL}"
echo "${DIVIDER}"

if [[ ${EXIT_CODE} -eq 0 ]]; then
    if [[ -z "${ERROR_OUTPUT}" ]]; then
        echo "[info] 查询成功，无返回结果"
        ROWS=0
    else
        echo "${ERROR_OUTPUT}"
        ROWS=$(echo "${ERROR_OUTPUT}" | wc -l | tr -d ' ')
    fi
    echo "${DIVIDER}"
    echo "[success] 执行成功 | 影响行数: ${ROWS} | 耗时: ${EXEC_TIME}s"
    write_log "Result: SUCCESS | Rows: ${ROWS} | Time: ${EXEC_TIME}s"
else
    echo "[error] 执行失败"
    echo "${ERROR_OUTPUT}"
    echo "${DIVIDER}"
    echo "[warning] 检查项:"
    echo "  - SQL 语法是否正确"
    echo "  - 连接配置是否正确 (${HOST}:${PORT})"
    echo "  - 数据库是否可访问"
    write_log "Result: FAILED | Error: ${ERROR_OUTPUT}"
    exit ${EXIT_CODE}
fi

# 性能警告
EXEC_SECONDS=$(echo "${EXEC_TIME}" | cut -d. -f1)
if [[ ${EXEC_SECONDS} -gt 10 ]]; then
    echo "[warning] 执行时间较长 (>10s)，建议优化查询"
    write_log "Warning: Execution time > 10s"
fi

log_end "SQL Execution"
check_old_logs

exit 0
