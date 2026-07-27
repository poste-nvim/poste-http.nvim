# Poste HTTP Neovim Plugin

A Neovim plugin for executing HTTP requests from `.http` files.

**Standalone** — no external dependencies. Requires `curl` on your system.

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "beyondlex/poste-http.nvim",
  dependencies = {
    "folke/snacks.nvim",
  },
  config = function()
    require("poste-http").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "beyondlex/poste-http.nvim",
  config = function()
    require("poste-http").setup()
  end,
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'beyondlex/poste-http.nvim'
```

Then add to your init.vim:
```vim
lua require("poste-http").setup()
```

## Usage

### Commands

- `:PosteRun` - Execute the request at the current cursor position
- `:PosteEnv` - Show the current environment
- `:PosteEnv <name>` - Switch to the specified environment

### Keymaps (in .http files)

- `<CR>` - Run request at cursor
- `]]` - Jump to next request separator (`###`)
- `[[` - Jump to previous request separator (`###`)
- `gd` - Go to variable/request definition

### Response Buffer

- Responses open in a vertical split (default 80 columns)
- Press `q` in the response buffer to close it
- All normal Vim operations work (yank, visual select, search, etc.)

## Configuration

```lua
require("poste-http").setup({
  default_env = "dev", -- Default environment
  default_view = "body", -- Initial response tab: "body" or "verbose"
  split_direction = "vertical", -- "vertical" or "horizontal"
  split_size = 80, -- Split size (columns for vertical, rows for horizontal)
})
```

## Requirements

- Neovim 0.10 or later
- `curl` available in PATH
- [snacks.nvim](https://github.com/folke/snacks.nvim) — used for the prompt/picker UI (variable selectors, environment switching, etc.)

## License

MIT