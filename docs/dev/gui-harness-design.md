# GUI 耦合模块测试 Harness 设计

## 1. 问题

`tests/http/zero_coverage_smoke_spec.lua:1-14` 列出的 12 个模块因与 Neovim GUI 深度绑定，无法用纯单元测试覆盖：

| 模块 | 路径 | 绑定原因 |
|------|------|----------|
| `buffer_setup` | `lua/poste-http/buffer_setup.lua` | 注册 keymap、autocmd、namespace |
| `commands` | `lua/poste-http/commands.lua` | 注册 `:Poste*` 用户命令 |
| `help` | `lua/poste-http/help.lua` | 打开浮动窗口 |
| `install` | `lua/poste-http/install.lua` | 执行 shell 命令、编辑文件 |
| `highlights` | `lua/poste-http/http/highlights.lua` | 设置 `nvim_set_hl` |
| `outline` | `lua/poste-http/http/outline.lua` | 管理浮动窗口、buffer |
| `textobj` | `lua/poste-http/http/textobj.lua` | 注册 textobj |
| `lua_docs` | `lua/poste-http/http/lua_docs.lua` | 打开浮动窗口 |
| `script_snippet` | `lua/poste-http/http/script_snippet.lua` | 编辑 buffer |
| `curl` | `lua/poste-http/http/curl.lua` | 粘贴到寄存器 |
| `copy` | `lua/poste-http/http/copy.lua` | 使用 `vim.fn.setreg` |
| `folding` | `lua/poste-http/http/folding.lua` | 注册 `foldexpr` |

现有 `mock_nvim.lua`（`tests/helpers/mock_nvim.lua`）提供了 Neovim API 的桩函数，但：
- 纯函数调用桩，不维护真实状态（buffer 内容、window 树、option 值等）
- 无 `nvim_list_wins`/`nvim_win_get_buf` 等窗口遍历
- 无 `vim.o`/`vim.wo`/`vim.bo` 模拟
- 无 autocmd 触发机制
- 无 `vim.fn` 函数（如 `setreg`、`systemlist`）的全覆盖

## 2. 目标

1. 为 12 个 GUI 耦合模块提供可维护的、隔离的单元测试
2. 保持与现有 `mock_nvim.lua` 的兼容性（不破坏现有测试）
3. 最小化 mock 工作量——只 mock 模块实际使用的 API
4. 测试应在 headless Neovim 中运行（plenary busted），无需额外依赖

## 3. 非目标

- 不是完整的 Neovim 模拟器（不模拟 UI 渲染、事件循环等）
- 不替代集成测试（集成测试验证真实 Neovim 行为，harness 测试验证逻辑正确性）
- 不追求 100% 行覆盖——优先覆盖核心逻辑路径和错误处理

## 4. 架构设计

### 4.1 分层结构

```
tests/helpers/
├── mock_nvim.lua          # 现有：基础 API 桩（函数调用记录）
├── gui_harness.lua        # 新增：高层测试工具
│   ├── 自动注入 mock_nvim
│   ├── Buffer 模拟（内容、option、filetype）
│   ├── Window 模拟（父子关系、尺寸、option）
│   ├── Autocmd 触发（手动触发已注册 autocmd）
│   ├── Keymap 记录（捕获已注册 keymap）
│   └── 回滚（teardown 时清理）
```

### 4.2 核心抽象

#### Buffer 模型

```lua
-- gui_harness 内部维护的 buffer 状态
local _buffers = {
  [1001] = {
    lines = { "line1", "line2" },
    options = { filetype = "poste_http", modifiable = true, buftype = "" },
    valid = true,
    ns_extmarks = { [42] = { { line = 0, col = 0, ... } } },
  },
}
```

- 所有 `nvim_create_buf`/`nvim_buf_set_lines` 等操作读写此状态
- `nvim_get_current_buf()` 返回最后操作的 buffer

#### Window 模型

```lua
local _windows = {
  [2001] = {
    buf = 1001,
    options = { winbar = "", foldmethod = "manual", foldlevel = 99 },
    width = 80,
    height = 24,
    cursor = { 1, 0 },
    valid = true,
  },
}
```

- `nvim_get_current_win()` 返回最后操作的 window
- `nvim_list_wins()` 返回所有 window 列表

#### Autocmd 触发

```lua
-- harness 提供手动触发 autocmd 的方法
harness.fire_autocmd("BufDelete", { buf = 1001 })
harness.fire_autocmd("TextChanged", { buf = 1001 })
```

- 内部遍历 `nvim_create_autocmd` 注册的回调，匹配条件后执行
- 不依赖 Neovim 事件循环

#### Keymap 记录

```lua
-- harness 捕获 keymap 注册，供断言
local kms = harness.get_keymaps(buf)
assert.equals("run_request", kms["n"]["<CR>"])
```

### 4.3 模块测试策略

每个模块按以下维度分析：

| 维度 | 做法 |
|------|------|
| 依赖的 Neovim API | 在 `gui_harness.lua` 中 mock |
| 依赖的 poste-http 模块 | 直接 require，harness 确保状态干净 |
| 副作用（文件、剪贴板等） | mock 或 stub |
| 测试模式 | 纯函数路径 + 状态断言 + 调用记录断言 |

### 4.4 模块级分析

#### `buffer_setup.lua`

**依赖 API**: `nvim_create_namespace`, `nvim_create_augroup`, `nvim_create_autocmd`, `nvim_buf_clear_namespace`, `nvim_buf_set_extmark`, `nvim_buf_get_lines`, `nvim_buf_is_valid`, `vim.keymap.set`, `vim.defer_fn`

**依赖 poste 模块**: `state`, `indicators`, `nav`, `run`, `curl`, `copy`, `symbols`, `env`, `history`, `help`

**测试策略**: 创建 mock buffer，调用 `setup_buffer_keymaps(buf)`，断言 keymap 已注册、autocmd 已创建、fileref extmark 已放置。

**关键测试场景**:
- `setup_buffer_keymaps` 调用后 keymap 条目正确
- `TextChanged` 触发时清除 indicator namespace
- `BufDelete` 触发时删除 augroup
- fileref 标记在 file 行正确放置，在 script 行跳过

#### `commands.lua`

**依赖 API**: `nvim_create_user_command`

**依赖 poste 模块**: 多个（`run`, `history`, `env`, `jq`, `curl`, `session`, `boundary_indicator`）

**测试策略**: 记录 `nvim_create_user_command` 调用，断言命令名和回调注册正确。

**关键测试场景**:
- 所有 `:Poste*` 命令注册完成
- 命令描述非空

#### `help.lua`

**依赖 API**: `nvim_open_win`, `nvim_buf_set_lines`, `nvim_win_set_buf`, `nvim_buf_set_name`, `nvim_buf_set_option`, `nvim_win_set_option`

**测试策略**: 创建 mock window，调用 `open()`，断言窗口、buffer 创建和内容正确。

**关键测试场景**:
- 打开帮助窗口后 buffer 内容正确
- 关闭帮助窗口清理资源

#### `install.lua`

**依赖 API**: `vim.fn.systemlist`, `vim.fn.executable`, `vim.fn.stdpath`, `io.open`, `os.execute`

**依赖 poste 模块**: 无

**测试策略**: mock `vim.fn.systemlist`/`executable`，断言检测逻辑正确。

**关键测试场景**:
- curl 安装检测
- C 编译器检测
- 目录创建

#### `highlights.lua`

**依赖 API**: `nvim_set_hl`, `nvim_get_hl`

**依赖 poste 模块**: 无

**测试策略**: 记录 `nvim_set_hl` 调用，断言所有 highlight 组已定义。

**关键测试场景**:
- 所有 `Poste*` highlight 组定义
- 颜色值正确

#### `outline.lua`

**依赖 API**: `nvim_open_win`, `nvim_win_set_buf`, `nvim_buf_set_lines`, `nvim_buf_set_keymap`, `nvim_win_set_cursor`, `nvim_list_wins`, `nvim_win_get_width`

**依赖 poste 模块**: `tree-sitter`, `describe`, `symbols`

**测试策略**: mock window/buffer 创建，调用 `show_symbols()`，断言浮动窗口打开、内容正确。

**关键测试场景**:
- 打开 outline 后窗口创建
- 关闭后窗口清理
- 按键绑定（j/k/ESC/Enter）

#### `textobj.lua`

**依赖 API**: 无（纯 Neovim textobj 注册）

**依赖 poste 模块**: 无

**测试策略**: 直接调用函数，断言返回范围正确。

**关键测试场景**:
- `ai`（内块）文本对象
- `ii`（内缩进）文本对象

#### `lua_docs.lua`

**依赖 API**: `nvim_open_win`, `nvim_buf_set_lines`, `nvim_win_set_buf`

**依赖 poste 模块**: `data`（API 文档数据）

**测试策略**: mock window/buffer，调用文档生成函数，断言内容正确。

**关键测试场景**:
- 打开文档窗口
- 内容包含 API 签名和描述
- 关闭窗口

#### `script_snippet.lua`

**依赖 API**: `nvim_buf_set_lines`, `nvim_buf_get_lines`, `nvim_buf_is_valid`

**依赖 poste 模块**: 无

**测试策略**: 创建 buffer，调用 snippet 插入函数，断言 buffer 内容。

**关键测试场景**:
- 插入脚本模板
- 插入断言模板

#### `curl.lua`

**依赖 API**: `vim.fn.setreg`

**依赖 poste 模块**: `cache`, `describe`

**测试策略**: mock `setreg`，断言复制到正确寄存器。

**关键测试场景**:
- 复制 curl 命令到注册器
- IPv6 URL 正确处理

#### `copy.lua`

**依赖 API**: `vim.fn.setreg`

**依赖 poste 模块**: `cache`, `describe`, `data`

**测试策略**: mock `setreg`，断言复制到正确寄存器。

**关键测试场景**:
- 复制为 curl 命令
- 复制为 HTTP 请求

#### `folding.lua`

**依赖 API**: `nvim_buf_set_option`, `vim.wo`

**依赖 poste 模块**: `cache`

**测试策略**: 创建 buffer，设置 fold 相关 option，调用 `foldexpr`，断言折叠结果。

**关键测试场景**:
- 折叠表达式正确
- 缓存键控正确

## 5. 实现计划

### Phase 1: `gui_harness.lua` 核心（估计 1 天）

- `Buffer` 对象：创建、内容读写、option、namespace、extmark
- `Window` 对象：创建、buffer 关联、option、尺寸、cursor
- `Autocmd` 注册库：存储回调，支持手动触发
- `Keymap` 注册库：存储 keymap，支持查询
- `UserCommand` 注册库：存储命令，支持查询
- `vim.o`/`vim.wo`/`vim.bo` 模拟：option 读写代理
- 集成 `teardown`：清理所有 mock 状态

### Phase 2: 首批模块测试（估计 2-3 天）

按依赖复杂度排序：

1. `highlights` — 最轻量，仅 `nvim_set_hl`
2. `textobj` — 纯函数，无状态
3. `commands` — 仅 `nvim_create_user_command`
4. `folding` — 少量 buffer op
5. `curl` / `copy` — 仅 `vim.fn.setreg`
6. `script_snippet` — 少量 buffer op
7. `help` — 窗口 + buffer
8. `lua_docs` — 窗口 + buffer

### Phase 3: 复杂模块测试（估计 3-4 天）

1. `buffer_setup` — 多依赖，但核心逻辑已大部分覆盖（`buffer_setup_spec.lua`）
2. `install` — 外部命令 mock
3. `outline` — 多窗口 + buffer + 事件

### Phase 4: 集成到 CI + 更新 `zero_coverage_smoke_spec.lua`（估计 0.5 天）

- 确保新测试在 `run.sh` 中通过
- 更新 `zero_coverage_smoke_spec.lua` 注释，标记已覆盖的模块

## 6. 成功标准

1. 每个 GUI 耦合模块至少有 1 个 `describe` 块和 ≥3 个 `it` 测试用例
2. 所有测试在 headless Neovim 中通过（`bash tests/run.sh`）
3. 核心逻辑路径覆盖率 ≥ 80%（乐观估计，不强制）
4. 不破坏现有测试
5. `zero_coverage_smoke_spec.lua` 注释反映真实覆盖状态

## 7. 风险与缓解

| 风险 | 缓解 |
|------|------|
| `vim.bo`/`vim.wo`/`vim.o` 模拟与真实 Neovim 行为不一致 | 保持 mock 简单；复杂场景用集成测试覆盖 |
| autocmd 触发条件匹配复杂（pattern、buffer 等） | 先实现精确匹配，遗漏再补 |
| 模块间依赖链导致 mock 膨胀 | 只在必要时 mock 依赖模块；优先测试纯函数路径 |
| 测试维护成本高 | 每个模块的 test spec 独立，harness 变更不影响现有测试 |