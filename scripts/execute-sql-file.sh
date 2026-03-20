#!/bin/bash
# execute-sql-file.sh - 以单事务执行 SQL 文件
# 用法: execute-sql-file.sh [连接名] /path/to/file.sql
#   或: execute-sql-file.sh /path/to/file.sql (使用默认连接 main)

set -o pipefail

# 加载公共函数库
SCRIPT_DIR="$(dirname "$0")"
source "${SCRIPT_DIR}/common.sh"

# 重置变量
CONNECTION=""
SQL_FILE=""

# 加载环境变量
load_env_config

# 解析参数
parse_connection_arg "$@"
# 根据解析结果决定是否移位
if [[ "${PARAMS_SHIFTED}" == "1" ]]; then
    shift
fi
SQL_FILE="$1"

# 检查参数
if [[ -z "${SQL_FILE}" ]]; then
    echo "[error] 未提供 SQL 文件路径"
    echo "[info] 用法: execute-sql-file.sh [连接名] /path/to/file.sql"
    exit 1
fi

if [[ ! -f "${SQL_FILE}" ]]; then
    echo "[error] SQL 文件不存在: ${SQL_FILE}"
    exit 1
fi

# 加载连接参数
load_connection_params "${CONNECTION}"

# 构建URL并记录日志
URL=$(build_url "${DRIVER}")
write_log "SQL File: ${SQL_FILE}"

# 显示执行信息
FILE_LINES=$(wc -l < "${SQL_FILE}")
DIVIDER="----------------------------------------"
echo "${DIVIDER}"
echo "[${CONNECTION}] > 文件: ${SQL_FILE} (${FILE_LINES} 行)"
echo "[${CONNECTION}] > 模式: 单事务执行 (-1)"
echo "${DIVIDER}"

# 检查是否包含危险操作(DROP/TRUNCATE 无条件执行)
if grep -qiE "^(DROP|TRUNCATE)" "${SQL_FILE}"; then
    echo "[warning] 检测到 DROP/TRUNCATE 操作，请确认已备份"
fi

# 执行 SQL 文件（单事务模式）
START_TIME=$(date +%s.%N)
# 使用 perl 实现跨平台 timeout（macOS 默认无 timeout 命令）
ERROR_OUTPUT=$(perl -e 'alarm 60; exec @ARGV' usql "${URL}" -1 -f "${SQL_FILE}" 2>&1)
EXIT_CODE=$?
END_TIME=$(date +%s.%N)
EXEC_TIME=$(echo "${END_TIME} - ${START_TIME}" | bc)

# 处理超时信号（EXIT_CODE=142 表示 alarm 触发）
if [[ ${EXIT_CODE} -eq 142 ]]; then
    echo "[error] 执行超时（60秒）"
    echo "[info] 建议: (1)将SQL拆分为多个文件分批执行,(2)优化SQL逻辑,(3)检查是否缺索引"
    write_log "Result: TIMEOUT (60s exceeded)"
    exit 1
fi

# 输出结果
echo "${DIVIDER}"

if [[ ${EXIT_CODE} -eq 0 ]]; then
    echo "[success] 事务执行成功 | 耗时: ${EXEC_TIME}s"
    echo "${DIVIDER}"
    write_log "Result: SUCCESS | Time: ${EXEC_TIME}s"
else
    echo "[error] 执行失败"
    echo "${ERROR_OUTPUT}"
    echo "${DIVIDER}"
    echo "[warning] 事务已自动回滚，数据未受影响"
    write_log "Result: FAILED | Error: ${ERROR_OUTPUT}"
    exit ${EXIT_CODE}
fi

# 性能警告
EXEC_SECONDS=$(echo "${EXEC_TIME}" | cut -d. -f1)
if [[ ${EXEC_SECONDS} -gt 10 ]]; then
    echo "[warning] 执行时间较长 (>10s)，建议优化 SQL 或分批执行"
    write_log "Warning: Execution time > 10s"
fi

log_end "SQL File Execution"
check_old_logs

exit 0
