--- Reusable column-aligned list layout component.
---
--- Formats rows of cells into display-width-aligned lines and reports
--- per-cell byte ranges so callers can place extmarks without re-deriving
--- column offsets.
---
--- Column specs (array of tables, one per column):
---   align    "left" (default) | "right"
---   width    fixed column width; cells are padded and truncated
---   max      column uses its natural width, capped at max; cells truncated
---   flex     column stretches to fill the remaining line width (requires
---            opts.width); optional min/max act as bounds on the stretched width
---   lead     leading spaces before this column (default: opts.gap, or 0 for
---            the first column) — allows non-uniform gaps between columns
---   pad      pad cells to the column width (default true; false renders the
---            visible text only, no trailing/leading spaces — use on the last
---            column to avoid trailing whitespace; column width still caps
---            truncation)
---   ellipsis truncate over-long cells with "..." (default true; false = hard cut)
---   hl      default highlight group for every cell in this column (optional;
---            per-cell override via row value `{ text, hl }` takes precedence)
---
--- opts:
---   width    total display width of each line (required when any column has
---            flex = true)
---   gap      default spaces between columns (default 1)
---   pad      pad character (default " ")
---
--- Truncation and padding are display-width aware (vim.fn.strdisplaywidth), so
--- wide characters (CJK) stay aligned and are never split.
---
--- @param rows table[]  each row is an array of cell values (string|number|nil)
--- @param cols table[]  column specs, see above
--- @param opts table|nil
--- @return string[] lines — one formatted line per row
--- @return table[][] cells — cells[row][col] = { text, col, end_col, width, hl }
---   text is the visible (truncated) cell text; col/end_col are byte offsets
---   suitable for nvim_buf_set_extmark. hl is the resolved highlight group
---   (per-cell override, or column default, or nil).
local M = {}

local function disp_width(s)
  return vim.fn.strdisplaywidth(s)
end

local function char_part(s, idx, len)
  return vim.fn.strcharpart(s, idx, len)
end

--- Cut text so its display width is at most max_width.
--- @param text string
--- @param max_width number
--- @param ellipsis boolean  append "..." when truncating
local function truncate(text, max_width, ellipsis)
  if disp_width(text) <= max_width then return text end
  if ellipsis and max_width > 3 then
    local budget = max_width - 3
    local kept = {}
    local used = 0
    local n = vim.fn.strchars(text)
    for i = 0, n - 1 do
      local ch = char_part(text, i, 1)
      local w = disp_width(ch)
      if used + w > budget then break end
      used = used + w
      kept[#kept + 1] = ch
    end
    return table.concat(kept) .. "..."
  end
  -- Hard cut to max_width display width.
  local kept = {}
  local used = 0
  local n = vim.fn.strchars(text)
  for i = 0, n - 1 do
    local ch = char_part(text, i, 1)
    local w = disp_width(ch)
    if used + w > max_width then break end
    used = used + w
    kept[#kept + 1] = ch
  end
  return table.concat(kept)
end

local function cell_text(v)
  if v == nil then return "", nil end
  if type(v) == "table" then
    return v.text ~= nil and tostring(v.text) or "", v.hl
  end
  return tostring(v), nil
end

--- @param rows table[]
--- @param cols table[]
--- @param opts table|nil
--- @return string[], table[][]
function M.render(rows, cols, opts)
  opts = opts or {}
  local gap = opts.gap or 1
  local pad = opts.pad or " "
  local pad_byte = #pad
  local ncols = #cols

  -- Normalize specs.
  local specs = {}
  for c = 1, ncols do
    local spec = cols[c] or {}
    specs[c] = {
      align = spec.align or "left",
      width = spec.width,
      max = spec.max,
      flex = spec.flex,
      min = spec.min,
      ellipsis = spec.ellipsis ~= false,
      lead = spec.lead or (c == 1 and 0 or gap),
      pad = spec.pad ~= false,
      hl = spec.hl,
    }
  end

  -- Cell texts and natural widths.
  local texts = {}
  local natural = {}
  for c = 1, ncols do
    natural[c] = 0
  end
  for r = 1, #rows do
    texts[r] = {}
    local row = rows[r] or {}
    for c = 1, ncols do
      local text = cell_text(row[c])
      texts[r][c] = text
      local w = disp_width(text)
      if w > natural[c] then natural[c] = w end
    end
  end

  -- Final column widths.
  local widths = {}
  local flex_idxs = {}
  local fixed_total = 0
  local lead_total = 0
  for c = 1, ncols do
    local spec = specs[c]
    lead_total = lead_total + spec.lead
    if spec.width then
      widths[c] = spec.width
      fixed_total = fixed_total + spec.width
    elseif spec.max then
      widths[c] = math.min(natural[c], spec.max)
      fixed_total = fixed_total + widths[c]
    elseif spec.flex then
      flex_idxs[#flex_idxs + 1] = c
      widths[c] = natural[c]
    else
      widths[c] = natural[c]
      fixed_total = fixed_total + natural[c]
    end
  end

  if #flex_idxs > 0 then
    if not opts.width then
      error("columns.render: opts.width is required when a column has flex = true", 2)
    end
    local remaining = opts.width - fixed_total - lead_total
    if remaining < 0 then remaining = 0 end
    local slice = math.floor(remaining / #flex_idxs)
    local extra = remaining % #flex_idxs
    for i, c in ipairs(flex_idxs) do
      local spec = specs[c]
      local w = slice + (i <= extra and 1 or 0)
      if spec.min then w = math.max(w, spec.min) end
      if spec.max then w = math.min(w, spec.max) end
      widths[c] = w
    end
  end

  -- Build lines and per-cell ranges.
  local lines = {}
  local cells = {}
  for r = 1, #rows do
    local segs = {}
    local row_cells = {}
    local byte_offset = 0
    for c = 1, ncols do
      local spec = specs[c]
      local w = widths[c]
      local text, cell_hl = cell_text(rows[r] and rows[r][c])
      local vis = truncate(text, w, spec.ellipsis)
      local padn = spec.pad and math.max(0, w - disp_width(vis)) or 0
      local lead_sp = string.rep(" ", spec.lead)
      local pad_sp = string.rep(pad, padn)
      local cell = { text = vis, width = w }
      -- Precedence: per-cell override > column default > nil
      cell.hl = cell_hl or spec.hl
      if spec.align == "right" then
        segs[#segs + 1] = lead_sp .. pad_sp .. vis
        cell.col = byte_offset + spec.lead + pad_byte * padn
      else
        segs[#segs + 1] = lead_sp .. vis .. pad_sp
        cell.col = byte_offset + spec.lead
      end
      cell.end_col = cell.col + #vis
      row_cells[c] = cell
      byte_offset = byte_offset + spec.lead + pad_byte * padn + #vis
    end
    lines[r] = table.concat(segs)
    cells[r] = row_cells
  end

  return lines, cells
end

return M
