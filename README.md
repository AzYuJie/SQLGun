# sqlgun

Agent Skill - SQL 查询武器库，通过 `usql` 执行 SQL，支持多数据库。

## 功能特性

- 单条 SQL 执行（30秒超时）
- SQL 文件事务执行（60秒超时）
- 自动日志记录
- 多数据库支持：PostgreSQL/MySQL/SQLServer/SQLite
- 危险操作检测（DROP/TRUNCATE 警告）
- 超时保护

## 前置依赖

### 1. 安装 usql

```bash
# macOS
brew install usql

# Linux
go install github.com/knq/usql/cmd/usql@latest
```

### 2. 配置数据库连接

```bash
mkdir -p ~/.config/sqlgun
touch ~/.config/sqlgun/.env
```

编辑 `~/.config/sqlgun/.env`：

```bash
# 默认连接
DB_USER=username
DB_PASS=password
DB_HOST=localhost
DB_PORT=5432
DB_NAME=mydb
DB_DRIVER=postgres

# 自定义连接示例
PROD_DB_USER=prod_user
PROD_DB_PASS=prod_password
PROD_DB_HOST=192.168.1.100
PROD_DB_NAME=prod_db
PROD_DB_DRIVER=postgres
```

## 安装

### 方式1: npx 安装（推荐）

```bash
# 从 GitHub 仓库安装
npx skills add AzYuJie/SQLGun

# 全局安装到所有 Agent
npx skills add AzYuJie/SQLGun -g -y

# 安装到指定 Agent
npx skills add AzYuJie/SQLGun -a claude-code -y
```

### 方式2: 手动安装到本地项目

```bash
# 克隆仓库
git clone https://github.com/AzYuJie/SQLGun.git

# 拷贝到 Claude Code skills 目录
cp -r sqlgun ~/.claude/skills/
```

### 方式3: 直接使用脚本

```bash
# 添加执行权限
chmod +x sqlgun/scripts/*.sh

# 使用
./sqlgun/scripts/execute-sql.sh "SELECT 1;"
```

## 使用方法

### 单条 SQL 查询

```bash
execute-sql.sh [连接名] "SQL"
```

示例：

```bash
# 默认连接
execute-sql.sh "SELECT * FROM users LIMIT 10;"

# 指定连接
execute-sql.sh prod "SELECT * FROM orders WHERE status = 'pending';"
```

### SQL 文件执行

```bash
execute-sql-file.sh [连接名] /path/to/file.sql
```

示例：

```bash
# 单事务执行
execute-sql-file.sh prod /tmp/migration.sql
```

### SQL 文件示例

```sql
-- /tmp/update.sql
BEGIN;
UPDATE users SET status = 'active' WHERE id = 123;
COMMIT;
```

## 安全规则

执行前必问：
1. **readonly?** SELECT 只读，DELETE/UPDATE 会修改数据
2. **full-scan?** 大数据表无 LIMIT 可能 OOM
3. **transaction?** DROP/TRUNCATE/多步修改需要事务保护
4. **影响范围?** 先用 LIMIT 100 测试
5. **可逆性?** 是否有备份

禁止操作：
- 无 WHERE 的 DELETE/UPDATE
- 无 LIMIT 的全表 SELECT
- TRUNCATE 无条件执行
- DROP 无 WHERE/IF EXISTS

## 驱动支持

| 驱动 | 值 |
|------|-----|
| PostgreSQL | `postgres` |
| MySQL | `mysql` |
| SQL Server | `sqlserver` |
| SQLite | `sqlite` |

## 日志

- 路径: `~/.config/sqlgun/logs/`
- 格式: `{日期}_{session_id}.log`
- 清理: `rm ~/.config/sqlgun/logs/*.log -mtime +30`

## 项目结构

```
sqlgun/
├── SKILL.md                 # Skill 定义
├── README.md                # 本文档
└── scripts/
    ├── common.sh           # 公共函数库
    ├── execute-sql.sh      # 单条SQL执行
    └── execute-sql-file.sh # SQL文件执行
```
