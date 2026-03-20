---
name: sqlgun
description: "通过 usql 执行 SQL 查询,支持单条SQL和SQL文件执行,自动记录日志。支持PostgreSQL/MySQL/SQLServer/SQLite多数据库。
WHEN: 用户需要(1)执行数据库查询,(2)数据导入导出,(3)结构变更(DDL),(4)批量数据修改时使用。
触发词: 执行SQL,查询数据库,run SQL,query database,sql,导入数据,导出数据,建表,删表,修改表结构"
---

# sqlgun Skill

## 前置依赖

- **usql**: `brew install usql` 或 `go install github.com/knq/usql/cmd/usql@latest`
- **配置文件**: `~/.config/sqlgun/.env`

## 配置文件格式

**路径**: `~/.config/sqlgun/.env`（必须先创建目录和文件）

```bash
# 默认连接 → main，前缀: DB_
DB_USER=username
DB_PASS=password
DB_HOST=localhost
DB_PORT=5432
DB_NAME=mydb
DB_DRIVER=postgres

# 生产库 → prod，前缀: PROD_DB_
PROD_DB_USER=prod_user
PROD_DB_PASS=prod_password
PROD_DB_HOST=192.168.1.100
PROD_DB_NAME=prod_db
PROD_DB_DRIVER=postgres

# 测试库 → test，前缀: TEST_DB_
TEST_DB_USER=test_user
TEST_DB_PASS=test_password
TEST_DB_HOST=192.168.1.200
TEST_DB_NAME=test_db
TEST_DB_DRIVER=postgres
```

**AI 连接选择**: 读取配置后，根据用户描述（"生产库"/"测试库"/"主库"）映射到对应连接名。

**首次使用**:
```bash
mkdir -p ~/.config/sqlgun
touch ~/.config/sqlgun/.env
# 编辑 .env 添加连接配置
```

## 安全规则

**执行前问自己** (修改数据前必问):
1. **readonly?** SELECT 只读，DELETE/UPDATE 会修改数据
2. **full-scan?** 大数据表无 LIMIT 可能 OOM 或阻塞网络
3. **transaction?** DROP/TRUNCATE/多步修改需要事务保护
4. **影响范围?** 预估影响行数，先用 LIMIT 100 测试
5. **可逆性?** 是否有备份/快照，是否需要先备份

**NEVER**:
- 禁止命令行明文传递密码 → 环境变量读取，`ps aux` 或 `history` 可暴露
- 禁止无 WHERE 的 DELETE/UPDATE → usql 默认自动提交，执行即生效，无法 ROLLBACK
  - 如必须执行：先 `SELECT * WHERE ... LIMIT 1` 确认目标，再移除 WHERE
- 禁止无 LIMIT 的全表 SELECT → 大数据表导致内存溢出或网络阻塞
- 禁止 TRUNCATE 无条件执行 → TRUNCATE 是 DDL，auto-commit 后无法回滚，且不触发 trigger
  - 如必须执行：先用 `DELETE FROM table` 替代（可回滚）
- 禁止 DROP 无 WHERE/IF EXISTS → 物理删除，永久丢失，无回滚
  - 如必须执行：先 `SELECT * FROM table` 确认内容

## 工具选择

| 场景 | 命令 | 说明 |
|------|------|------|
| 单条 SQL (只读) | `execute-sql.sh [连接名] "SQL"` | SELECT等只读操作 |
| 单条 SQL (修改) | `execute-sql.sh [连接名] "SQL"` + 自行保证 | DELETE/UPDATE/INSERT需严格检查WHERE |
| SQL 文件执行 | `execute-sql-file.sh [连接名] /path/to/file.sql` | 单事务执行（usql `-1` flag），失败自动回滚 |

**MANDATORY - READ BEFORE USE**: 使用前必须读取 [`common.sh`](scripts/common.sh) 理解:
- URL构建逻辑 (`build_url` 函数)
- 连接参数解析 (`load_connection_params` 函数)
- 错误处理模式

**决策树**:
```
用户请求 → 是数据修改?
  ├─ 是(增删改) → 使用 execute-sql-file.sh（事务保护）
  │   └─ 复杂逻辑 → 写入 .sql 文件执行
  └─ 否(只读) → execute-sql.sh
      └─ 大数据表 → 必须加 LIMIT
```

**Fallback机制** (usql连接失败时):
1. 检查网络: `ping ${HOST}` 确认可达
2. 检查端口: `nc -zv ${HOST} ${PORT}` 确认端口开放
3. 检查服务: `ps aux | grep usql` 确认本地进程
4. 检查配置: 确认 `.env` 中 HOST/PORT/USER/PASS 正确
5. 验证密码: `usql "postgres://user:pass@host:port/db" -c "SELECT 1"`

**超时保护**:
- 单条SQL: 30秒超时（防止大查询挂起）
- SQL文件: 60秒超时
- macOS 使用 perl 实现（跨平台兼容）

**SQL 文件执行细节**:
- 多语句文件：SQL 语句以 `;` 结尾，`execute-sql-file.sh` 自动单事务执行
- SQL Server 批处理：使用 `GO` 分隔符的文件，需用 `usql [连接名] -f file.sql`（不用 `-1` flag）

## 事务控制

| 场景 | 命令 |
|------|------|
| 单事务（推荐） | `execute-sql-file.sh [连接名] /path/to/file.sql` |
| 交互模式 | `usql [连接名]` → `\begin` / `\commit` / `\rollback` |

**usql 交互命令**: `\begin`(开始事务) `\commit`(提交) `\rollback`(回滚) `\q`(退出)

**usql 特定行为**: 默认自动提交（autocommit），与标准 SQL 客户端不同。

## 日志记录

- 路径: `~/.config/sqlgun/logs/`
- 格式: `{日期}_{session_id}.log`
- 清理规则: 30天前日志超过 5 个时提示清理

## 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| 连接超时 | 网络或 HOST/PORT 错误 | 检查 `.env` 配置，使用 `nc -zv host port` 验证端口 |
| 认证失败 | 密码错误或为空 | 确认 `DB_PASS` 配置，或用 `usql "postgres://..." -c "SELECT 1"` 测试 |
| 权限不足 | 用户无操作权限 | 确认用户是否有所需schema的GRANT权限 |
| 执行慢 | 无索引或全表扫描 | 使用 `EXPLAIN ANALYZE` 分析查询计划 |
| 字符乱码 | 编码不一致 | PostgreSQL 加 `?sslmode=disable&encoding=utf8` |
| 日志过多 | 长期未清理 | `rm ~/.config/sqlgun/logs/*.log -mtime +30` |
| 执行超时 | 大数据量查询或SQL文件执行 | 单SQL: 加LIMIT或优化索引; SQL文件: 拆分文件分批执行 |
| 事务锁定 | 并发修改冲突 | 检查长事务是否未提交，使用 `\l` 查看连接状态 |
| 超时信号 | alarm触发(EXIT_CODE=142) | 脚本已自动处理,会提示优化建议 |

## 驱动与 URL 格式

| 驱动 | URL 格式 | 特殊参数 |
|------|---------|---------|
| postgres | `postgres://user:pass@host:port/db` | `?sslmode=disable` |
| mysql | `mysql://user:pass@host:port/db` | 无 sslmode |
| sqlserver | `sqlserver://user:pass@host:port/db` | 无 sslmode |
| sqlite | `sqlite:dbname` | 无 host/port/user/pass |
