# 根因分析：渲染进程无响应（renderer unresponsive）

## 现象

在 OpenCode Desktop v1.17.20 中，打开包含大量文件 diffs 的会话时，Electron 渲染进程会冻结 1~15 秒，操作系统弹出 `renderer unresponsive` 提示。可稳定复现。

**触发条件**：会话中包含大量 `summary.diffs` 条目（由 Agent 批量生成文件时产生），实测最大数组长度为 **6,433 条**。

## Profiler 证据

通过 Electron DevTools Performance 面板采集采样栈，冻结期间 CPU 自洽地集中在以下调用路径：

```
Array.some ← Proxy.reduceRight ← constructMessageRows
```

其中 `constructMessageRows` 是 SolidJS 组件渲染路径上的关键函数。每次冻结都指向同一段去重逻辑。

## 问题代码

以下是问题的精确位置（位于消息行构建函数中）：

```typescript
(userMessage.summary?.diffs ?? []).reduceRight((result, diff) => {
  if (!isSummaryDiff(diff)) return result;
  if (result.some(item => item.file === diff.file)) return result;
  result.push(diff);
  return result;
}, [] as ZCodeSummaryDiff[])
```

逻辑本身正确：`reduceRight` 从后往前遍历，`some` 检查当前 `diff.file` 是否已存在于 `result` 中，从而实现"后出现的重复 file 覆盖前者"的语义。

**但性能是 O(d²)**。当 `d ≈ 6,400` 时，`some` 在累积过程中反复线性扫描 `result`，总比较次数约 `d²/2 ≈ 2,000` 万次。

## 关键洞察：SolidJS Store Proxy 放大效应

如果数据是普通 JavaScript 数组，2,000 万次比较在现代 V8 上仅需约 **5ms**，不足以造成卡顿。

但此处 `userMessage.summary` 来自 **SolidJS Store**——一个经过 Proxy 包裹的响应式状态树。每次 `item.file` 读取都会：

1. 经过 Proxy 的 `get` trap
2. 触发 SolidJS 的响应式依赖注册（`track`）
3. 在 Store 的嵌套路径上递归解析

实测对比（Node.js v20, d=6,400, 50% 重复）：

| 数据包装方式 | 耗时 | 备注 |
|---|---|---|
| 普通对象数组 | ~5 ms | 无代理开销 |
| `new Proxy` 包装（模拟 Store） | ~714 ms | **慢 142x** |
| 代理包装 + 全唯一 | ~184 ms | 仍受 Proxy 影响 |

更严重的是，每次读取不仅阻塞当前计算，还会在 SolidJS 的依赖图中注册大量无用节点——当该组件卸载时，`cleanNode` 回收这些依赖节点也会产生明显的额外开销。

**Proxy 将 O(d²) 的线性放大变成了不可忽视的用户体验问题。**

## 数据规模参考

为便于理解应用的整体数据量级，给出以下参考数字（脱敏处理）：

| 指标 | 数值 |
|---|---|
| `part` 表总行数 | 74 万 |
| `message` 表总行数 | 16.7 万 |
| 会话总数 | 1.2 万 |
| 单个会话最大 diffs 数组 | 6,433 条 |

这些数字表明 6,433 条 diffs 在应用中虽属极端情况，但并非不可能达到，尤其在使用 Agent 批量生成文件的场景下频繁出现。

## 教训

- **不要在 SolidJS Store Proxy 包裹的数据上执行 O(d²) 算法**——Proxy 的层层 trap 会放大常数因子 100 倍以上。
- 性能基准测试 **必须** 在与实际运行时一致的数据结构上执行。纯 JavaScript 数组测试会严重低估实际开销。
- 渲染路径上的数据去重应该使用 `Set`（或 `Map`），将 O(d²) 降为 O(d)。