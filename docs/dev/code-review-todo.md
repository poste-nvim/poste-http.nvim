# Code Review 2026-08-13 修复跟踪

> 基准：`e0db389` | 来源：`docs/dev/code-review-2026-08-13.md`

## 第一优先级（用户可见的正确性）

- [x] F01: 失败请求渲染为成功 — 修 `parse_error` status + `parse_headers_file` 空文件默认
- [x] F02: orchestration 缺 `state` require
- [x] F03+F06: TS 查询层崩溃 (`collect_matches`) + `get_node_text` 不存在
- [x] F05: 异步回调错误兜底 + `_busy` 复位（含 F22）

## 第二优先级（文档/配置对齐）

- [x] F09+D01: `require("poste")` → `require("poste-http")`（README + keymaps.md）
- [x] F10: 修 `default_env` 同步，删 `poste_binary`/`split_size`
- [x] D02-D17: 文档漂移清单逐项修

## 第三优先级（测试基建）

- [ ] F23: 新增 `curl_exec_spec.lua`（stub jobstart）
- [ ] F24: 契约测试改名 `contract_spec.lua`
- [ ] F25: 删除 SQL 孤儿文件
- [ ] F27: `run.sh` 加 `-u NONE` + 参数化 plenary 路径 + CI

## 第四优先级（结构性重构）

- [ ] F12: 块边界收敛到 `describe` 单一来源
- [ ] F15: nav 双实现合一
- [ ] F20: import.lua 拆分 + importer 交互流去重
- [ ] F08: 缓存失效策略（changedtick-only + import 索引独立缓存）