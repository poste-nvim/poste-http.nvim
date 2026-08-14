# Code Review 2026-08-13 修复跟踪

> 基准：`e0db389` | 来源：`docs/dev/code-review-2026-08-13.md`

## 第一优先级（用户可见的正确性）— 已完成

- [x] F01: 失败请求渲染为成功 — 修 `parse_error` status + `parse_headers_file` 空文件默认
- [x] F02: orchestration 缺 `state` require
- [x] F03+F06: TS 查询层崩溃 (`collect_matches`) + `get_node_text` 不存在
- [x] F05: 异步回调错误兜底 + `_busy` 复位（含 F22）

## 第二优先级（文档/配置对齐）— 已完成

- [x] F09+D01: `require("poste")` → `require("poste-http")`（README + keymaps.md）
- [x] F10: 修 `default_env` 同步，删 `poste_binary`/`split_size`
- [x] D02-D17: 文档漂移清单逐项修

## 第三优先级（测试基建）— 已完成

- [x] F23: 新增 `curl_exec_spec.lua`（stub jobstart）
- [x] F24: 契约测试改名 `contract_spec.lua`
- [x] F25: 删除 SQL 孤儿文件
- [x] F27: `run.sh` 加 `-u NONE` + 参数化 plenary 路径

## 第四优先级（结构性重构）— 已完成

- [x] F12: 块边界收敛到 `describe` 单一来源
- [x] F15: nav 双实现合一
- [x] F20: import.lua 拆分 + importer 交互流去重
- [x] F08: 缓存失效策略（changedtick-only）

---

## 第五优先级（P0 正确性缺陷）

- [x] F04: 依赖链状态跨请求泄漏 — `_chain_dep_set`/`_chain_dep_order`/`request_response_cache` 在 `M.resolve_content_dependencies` 入口重置
- [x] F07: 三个 importer 真实崩溃 — `next(example)` 对标量 schema、`table.concat` 接表、Postman `?` 翻倍、`gsub` 接数字

## 第六优先级（P1 功能损坏/性能）

- [x] F11: `:PosteJqFilter` 已从文档移除；`{{Name.res.body.X}}` 添加 `.res.` → `.response.` 别名
- [x] F13: 高亮四套实现漂移 — 已同步 `queries/` ← `tree-sitter-poste-http/queries/` 的 `highlights.scm`
- [x] F14: `select.lua` 浮窗加 `WinClosed` 兜底 + `Snacks` 安全 require
- [x] F16: 渲染层全量重渲染 — pending 定时器窗口可见性检查、outline/fileref 防抖
- [x] F17: `columns.lua` CJK 字节偏移 — 改用 `#lead_sp`/`#pad_sp` 累积，避免 `pad_byte` 漂移
- [x] F18: `sanitize_lines` 改用 `vim.split` 保留空行 — 空行后 extmark 不错行
- [ ] F19: 死代码 12 项 — `build_pending_request` 零调用、`code_str` 丢弃、XML/HTML 分支不可达等
- [ ] F21: history 纯内存 — 重启即丢，无磁盘读写

## 第七优先级（P2 测试体系）

- [ ] F26: 空测试与假测试 — 5 个空 `it()`、`variable_ref_spec` 测自己的副本
- [ ] F28: 覆盖缺口 — 21+ 模块零测试引用
- [ ] F29: 测试卫生 — 临时文件泄漏、`mock_nvim` 浅实现、无 CI、`grammar_spec.sh` 不在 `run.sh`

## 第八优先级（P3 安全与健壮性）

- [ ] §6: 安全与健壮性 29 项 — 明文日志、shell 转义缺 `[]`、路径拼接、gsub 陷阱等