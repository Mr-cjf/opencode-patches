# 官方修复分析（v1.18.30）

OpenCode Desktop v1.18.30 发布时包含了三处与 renderer 卡顿相关的重要改动。以下逐一分析。

## 三处改动

### 1. 抽出 `uniqueSummaryDiffs` 工具函数（核心修复）

将内联的 `reduceRight` + `some` 去重逻辑提取为独立的纯函数，并使用 `Set` 替代 `Array.some` 进行查重：

```typescript
function uniqueSummaryDiffs(diffs: ZCodeSummaryDiff[]): ZCodeSummaryDiff[] {
  const seen = new Set<string>()
  const result: ZCodeSummaryDiff[] = []
  for (let i = diffs.length - 1; i >= 0; i--) {
    const diff = diffs[i]
    if (!isSummaryDiff(diff)) continue
    if (seen.has(diff.file)) continue
    seen.add(diff.file)
    result.push(diff)
  }
  return result
}
```

- **语义等价**：从后往前遍历，保留每个 file 的最后出现
- **复杂度**：O(d) 时间 + O(d) 空间
- **调用处**：`constructMessageRows` 中直接用 `uniqueSummaryDiffs` 替换内联去重

### 2. `error` 查找从 `find()` 改为 `at(-1)`

原代码在消息行构建时通过 `diffs.find(d => d.isError)` 查找最后一个错误，改为 `diffs.at(-1)`。此改动与性能无关，属于语义修正——`find` 返回第一个而非最后一个错误，而逻辑意图是取最后一个。仅提及，不予移植。

### 3. 移除 `mapArray` per-message memo，改为整会话单次 memo

原代码为每条消息独立使用 SolidJS 的 `mapArray` 进行响应式记忆化。v1.18.30 改为在会话级别使用 `constructSessionMessageRows`，通过 `Map<string, ZCodeSummaryDiff>` 单遍构建整个会话的 turn → rows 映射：

```typescript
// 简化示意
function constructSessionMessageRows(messages: Message[]) {
  const turnMap = new Map<string, ZCodeSummaryDiff[]>()
  for (const msg of messages) {
    const turn = msg.turnId
    if (!turnMap.has(turn)) turnMap.set(turn, [])
    turnMap.get(turn)!.push(...uniqueSummaryDiffs(msg.diffs))
  }
  return turnMap
}
```

此改动结构较大，涉及组件树调整，移植风险较高。

## 本仓库的移植策略

| 改动 | 是否移植 | 理由 |
|---|---|---|
| ① `uniqueSummaryDiffs` | 是 | 最小改动、语义等价、直接命中 profiler 热点 |
| ② `find` → `at(-1)` | 否 | 语义修正，非性能问题 |
| ③ 会话级 memo | 否 | 结构改造风险大，需调整组件树 |

本仓库只移植改动 ①：在 `constructMessageRows` 中将内联的 `reduceRight` + `some` 替换为 `uniqueSummaryDiffs`。改动范围控制在单一函数内，编译/重打包后仅目标文件变化，验证通过（见 `docs/03-benchmark.md`）。