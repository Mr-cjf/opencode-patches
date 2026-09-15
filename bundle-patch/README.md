# Bundle Patch: `constructMessageRows` Diff 去重（性能修复）

## 用途

修复 OpenCode 1.17.20 打开包含大量文件 diffs 的会话时，renderer 进程卡死数秒的问题。当会话累积了数千个文件差异（diffs）时，`constructMessageRows` 函数使用 `reduceRight` + `Array.some` 进行查重，导致 O(d平方) 的时间复杂度，引发严重性能瓶颈。

## 原理

- **原始实现**：`reduceRight` 遍历 diff 数组时，对每个候选 diff 调用 `result.some((item) => item.file === diff.file)` 检查是否已存在。该操作对每个元素都遍历已积累的结果数组。
- **数据来源**：SolidJS Store Proxy 包装的会话数据，每次属性访问都会触发代理追踪。
- **性能灾难**：当 d 约等于 6,400 时，总代理读取约 2,000 万次（约等于 `sum_{i=1}^{d} i` 次 `Array.some` 调用）。
- **修复方式**：改用 `Set` 结构记录已出现的文件名，查重操作降为 O(1)，整体时间复杂度从 O(d平方) 降至 O(d)。语义完全等价 —— 保留每个文件最后一次出现的顺序（与原始 `reduceRight` 行为一致）。
- **上游确认**：OpenCode 官方在 1.18.30 版本中采用了相同的修复思路，引入了 `uniqueSummaryDiffs` 函数。

## 文件说明

| 文件 | 说明 |
|------|------|
| `main-Cpm5Nopr.patched.js` | 已打补丁的 renderer bundle 文件（替换 app.asar 内的对应文件） |
| `header.json` | app.asar 的 header 元数据（调试/验证用） |
| `patch_bundle.py` | 自动对已知 bundle 文件打补丁的脚本 |
| `repack_asar.py` | 从解包目录重新打包为 app.asar 的脚本 |
| `extract_asar.py` | 从 app.asar 提取指定文件到本地的工具 |
| `extract_asar2.py` | extract_asar.py 的另一种实现（处理 pickle 格式） |
| `parse_asar.py` | 解析 app.asar 头部结构并检视文件的工具 |
| `extract_bundle.js` | 使用 Node.js `@electron/asar` API 提取 bundle 的脚本 |
| `verify_equivalence.js` | 验证补丁前后行为等价性的工具（对比 Set 去重与原始实现的结果） |

## 使用方法

1. **备份原始 app.asar**
   ```
   cp /path/to/OpenCode/resources/app.asar /path/to/OpenCode/resources/app.asar.bak
   ```

2. **提取并打补丁**
   ```bash
   # 解压 app.asar 到临时目录
   python extract_asar.py
   
   # 将 patched bundle 放回解包目录的对应位置
   cp main-Cpm5Nopr.patched.js <extract-dir>/out/renderer/assets/main-Cpm5Nopr.js
   
   # 重新打包
   python repack_asar.py --input <extract-dir> --output app.asar
   ```

3. **替换并重启**
   ```
   cp app.asar /path/to/OpenCode/resources/app.asar
   ```

4. **验证等效性（可选）**
   ```bash
   node verify_equivalence.js --bundle main-Cpm5Nopr.patched.js
   ```
   使用 `--verify` 参数可对比补丁前后 `constructMessageRows` 对同一输入数据的输出是否完全一致。

## 注意事项

- 本补丁**仅匹配** OpenCode 1.17.20 版本的 renderer bundle（`main-Cpm5Nopr.js`）。其他版本 bundle 文件名和内部代码结构不同，切勿直接替换。
- 此应用**未启用** asar 完整性校验 fuse（`app.isPackaged` 为 false 时 integrity check 被跳过），因此修改后的 app.asar 仍可正常启动。
- 任何 OpenCode 应用更新都会覆盖修改后的 app.asar，需要重新应用补丁。
- 建议在应用更新后检查 `constructMessageRows` 函数是否已包含 Set 去重逻辑（1.18.30+ 版本官方已修复），如已修复则无需再打补丁。