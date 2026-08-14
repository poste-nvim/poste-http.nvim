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
- [x] F19: 死代码 12 项 — 删零调用函数、合并重复分支、修 `format.lua` break 提前终止循环、修 jq 退出码分支不可达
- [x] F21: history 纯内存 — `add_entry`/`delete_entry` 序列化到 `stdpath("data")/poste-http/history.json`，`M.load()` 启动加载 + 恢复 id counter + 上限裁剪；`http_history_max`/`persist_history`/`history_file` 提为配置项

## 第七优先级（P2 测试体系）

- [x] F26: 空测试与假测试 — indicators_spec 5 个空 `it()` 全部实现；variable_ref_spec 改用真实 `request_deps.find_request_variable_refs`
- [ ] F28: 覆盖缺口 — 21+ 模块零测试引用（本轮已新增 `zero_coverage_smoke_spec.lua`，覆盖 nested_access/import_parser/三个 import_*/multipart/md5/file_include/prompt_vars/var_collector/format_file/constants 共 34 项冒烟测试，含 F07 崩溃回归；GUI 强耦合模块待后续 harness）
- [x] F29: 测试卫生 — `grammar_spec.sh`（修 `request_body`→`json_body` 陈旧断言）与 `injection_spec.sh`（重写：heredoc-in-`-c` 根本不可用、删硬编码 Homebrew 路径、修空 stdin grep、修 `request_body`→`json_body`/`json`→`poste_json`）已并入 `run.sh`；`dofile("./tests/helpers/mock_nvim.lua")` CWD 依赖改 `require("helpers.mock_nvim")`；`math.randomseed(42)` 固定种子；`test_http_completion_fixtures_spec` 补 `after_each` 清理临时目录（删从不调用的 `teardown_env_json`）；`http_image_preview_spec` 临时文件统一 `make_tmp_file` + `after_each` 删除；新增 `.github/workflows/ci.yml`（tree-sitter CLI + Neovim 0.10 + plenary，跑 `tests/run.sh`）；`vim.wait` 轮询与 `mock_nvim` 浅实现属深层重构，留待后续

## 第八优先级（P3 安全与健壮性）

- [ ] §6: 安全与健壮性 29 项 — 明文日志、shell 转义缺 `[]`、路径拼接、gsub 陷阱等