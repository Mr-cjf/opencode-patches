# 数据库 time 字段兼容修复

## 背景

从 OpenCode Desktop v1.18.x 降级到 v1.17.20 后，打开旧会话（在 v1.18.x 中创建或使用过的会话）时控制台报错：

```
Cannot read properties of undefined (reading 'time')
```

原因是 v1.17.20 的代码在访问 `part.data.time` 时假设该字段始终存在，而 v1.18.x 在写入 `part` 表时未填充该字段（v1.18.x 部分代码路径已改用 `data.time_created` / `data.time_updated`）。

## 修复方法

对 SQLite 数据库 `opencode.db` 的 `part` 表执行数据修复：用行内已有的 `time_created` 和 `time_updated` 字段，通过 `json_set` 给 `data` JSON 补上顶层 `time` 字段。

### 受影响的行数

共 **540,320 行**（数据规模因使用情况而异）。

### SQL 脚本

```sql
-- 备份数据库后再执行！
UPDATE part
SET data = json_set(
  data,
  '$.time',
  json_object(
    'start', time_created,
    'end',   time_updated
  )
)
WHERE json_extract(data, '$.type') IN (
  'step-finish', 'text', 'patch', 'agent', 'file', 'compaction'
)
AND json_extract(data, '$.time') IS NULL;
```

注意 `step-start` 类型的 part 只应补 `start`，因为其语义上只有开始时间：

```sql
UPDATE part
SET data = json_set(
  data,
  '$.time',
  json_object('start', time_created)
)
WHERE json_extract(data, '$.type') = 'step-start'
AND json_extract(data, '$.time') IS NULL;
```

## 操作步骤

1. 完全关闭 OpenCode Desktop（确保进程退出，可通过任务管理器确认）。
2. 找到数据库文件位置（通常为 `%APPDATA%\anomalyco\opencode\opencode.db`）。
3. 备份数据库：将 `opencode.db` 复制为 `opencode.db.backup`。
4. 使用 SQLite 命令行工具（或其他 SQLite 客户端）连接到该数据库，依次执行上述两个 UPDATE 语句。
5. 重新打开 OpenCode Desktop，验证报错已消失。

## 说明

- 此修复为**数据修复**，与性能补丁（`uniqueSummaryDiffs`）完全独立。如果未出现 time 字段缺失的报错，无需执行此修复。
- 此修复不会影响 v1.18.x 下的数据——v1.18.x 本就不依赖 `data.time`。