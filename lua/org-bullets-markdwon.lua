local M = {}

local api = vim.api

local NAMESPACE = api.nvim_create_namespace("org-bullets-markdown")

---@class BulletsConfig
---@field public show_current_line boolean
---@field public symbols string[] | function(symbols: string[]): string[]
---@field public indent boolean
local defaults = {
  show_current_line = false,
  symbols = {
    -- mkd_bullets = { "⦿", "◎", "✺", "◌", "▶", "⤷" },
    mkd_bullets = { "◉", "○", "✸", "•", "◦" },
    -- mkd_bullets = { "•" },
    -- mkd_bullets = { "●", "○", "•", "✿" },
    -- checkboxes = { "", "" },
    checkboxes = { "˟", "✓" },
    -- checkboxes = { "", "" },
    -- checkboxes = { "", "" },
    -- checkboxes = { "", "✔", "✓" },
  },
  bullets_highlights = { "Function", "Number", "Keyword", "String" },
  -- bullets_highlights = { "DiagnosticInfo", "Number", "Keyword", "String" },
  -- checkbox_highlights = { "NoiceCompletionItemKindProperty", "NoiceCompletionItemKindConstant" },
  checkbox_highlights = { "Function", "Keyword" },
  indent = true,
  concealcursor = false,
}

local config = {}

---Merge a user config with the defaults
---@param user_config BulletsConfig
local function set_config(user_config)
  local headlines = vim.tbl_get(user_config, "symbols", "headlines")
  local default_headlines = defaults.symbols.headlines
  if headlines and type(headlines) == "function" then
    user_config.symbols.headlines = user_config.symbols(default_headlines) or default_headlines
  end
  config = vim.tbl_deep_extend("keep", user_config, defaults)
end

---Add padding to the given symbol
---@param symbol string
---@param padding_spaces number
---@param bullet boolean
local function add_symbol_padding(symbol, padding_spaces, bullet)
  if bullet then
    return string.rep(" ", padding_spaces - 1) .. symbol
  else
    return string.rep(" ", padding_spaces) .. symbol .. " "
  end
end

---Sets of pairs {pattern = handler}
---handler
local markers = {
  ---@param str string
  ---@param level BulletsConfig
  ---@return table { string symbol, string highlight_group }
  bullet = function(str, level)
    local symbols_value = #config.symbols.mkd_bullets
    local highlights_value = #config.bullets_highlights
    if level + 1 <= highlights_value then
      highlights_value = level + 1
    end
    if level + 1 <= symbols_value then
      symbols_value = level + 1
    end
    local symbol = add_symbol_padding(config.symbols.mkd_bullets[symbols_value], (#str - 1), true)
    return { { symbol, config.bullets_highlights[highlights_value] } }
  end,
  todo = function(str, status)
    local symbols_value = 1
    if status == "checked" then
      symbols_value = 2
    end
    local symbol = add_symbol_padding(config.symbols.checkboxes[symbols_value], #str, false)
    return { { symbol, config.checkbox_highlights[symbols_value] } }
  end,
}

---Set an extmark (safely)
---@param bufnr number
---@param virt_text string[][] a tuple of character and highlight
---@param lnum integer
---@param start_col integer
---@param end_col integer
---@param highlight string?
local function set_mark(bufnr, virt_text, lnum, start_col, end_col, highlight)
  local ok, result = pcall(api.nvim_buf_set_extmark, bufnr, NAMESPACE, lnum, start_col, {
    end_col = end_col,
    hl_group = highlight,
    virt_text = virt_text,
    virt_text_pos = "overlay",
    -- hl_mode = "combine",
    hl_mode = "blend",
    ephemeral = true,
  })
  if not ok then
    vim.schedule(function()
      vim.notify_once(result, vim.log.levels.ERROR, { title = "Markdown bullets" })
    end)
  end
end

--- Get the nested level of the list item
---@param node userdata
---@return integer nested level <= 3
local function get_list_level(node)
  local listNode = node:parent():parent()
  local listParent = listNode:parent():type()
  if listParent ~= "list_item" then
    return 0
  end
  return get_list_level(listNode) + 1
end

--- Create a position object
---@param bufnr number
---@param name string
---@param node userdata
---@return Position
local function create_position(bufnr, name, node)
  local type = node:type()
  local row1, col1, row2, col2 = node:range()
  return {
    name = name,
    type = type,
    item = vim.treesitter.get_node_text(node, bufnr),
    start_row = row1,
    start_col = col1,
    end_row = row2,
    end_col = col2,
    level = get_list_level(node),
  }
end

--- Get the position objects for each time of item we are concealing
---@param bufnr number
---@param start_row number
---@param end_row number
---@param root table treesitter root node
---@return Position[]
local function get_ts_positions(bufnr, start_row, end_row, root)
  local positions = {}
  local query = vim.treesitter.query.parse(
    "markdown",
    [[
			(list_marker_minus) @list_marker_minus
			(list_marker_plus) @list_marker_plus
			(list_marker_star) @list_marker_star
			(task_list_marker_checked) @task_list_marker_checked
			(task_list_marker_unchecked) @task_list_marker_unchecked
        ]]
  )
  for _, match, _ in query:iter_matches(root, bufnr, start_row, end_row) do
    for id, node in pairs(match) do
      local name = query.captures[id]
      -- if not vim.startswith(name, "_") then
      if vim.startswith(node:type(), "list_marker") or vim.startswith(node:type(), "task_list_marker") then
        positions[#positions + 1] = create_position(bufnr, name, node)
      end
    end
  end
  return positions
end

---@class Position
---@field start_row number
---@field start_col number
---@field end_row number
---@field end_col number
---@field item string

---Set a single line extmark
---@param bufnr number
---@param positions table<string, Position[]>
---@param conf BulletsConfig
local function set_position_marks(bufnr, positions, conf)
  for _, position in ipairs(positions) do
    local itemType = "bullet"
    local status = "unchecked"

    if vim.startswith(position.name, "task_list_marker") then
      itemType = "todo"
    end
    if position.name == "task_list_marker_checked" then
      status = "checked"
    end

    local str = position.item
    local start_row = position.start_row
    local start_col = position.start_col
    local end_col = position.end_col
    local handler = markers[itemType]
    local level = position.level

    -- Don't add conceal on the current cursor line if the user doesn't want it
    local is_concealed = true
    if not conf.concealcursor then
      local cursor_row = api.nvim_win_get_cursor(0)[1]
      is_concealed = start_row ~= (cursor_row - 1)
    end
    if is_concealed and start_col > -1 and end_col > -1 and handler then
      if itemType == "bullet" then
        set_mark(bufnr, handler(str, level), start_row, start_col, end_col)
      end
      if itemType == "todo" then
        set_mark(bufnr, handler(str, status), start_row, start_col - 2, end_col)
      end
    end
  end
end

local get_parser = (function()
  local parsers = {}
  return function(bufnr)
    if parsers[bufnr] then
      return parsers[bufnr]
    end
    parsers[bufnr] = vim.treesitter.get_parser(bufnr, "markdown", {})
    return parsers[bufnr]
  end
end)()

--- Get the position of the relevant items to conceal
---@param bufnr number
---@param start_row number
---@param end_row number
---@return Position[]
local function get_mark_positions(bufnr, start_row, end_row)
  local parser = get_parser(bufnr)
  local positions = {}
  parser:for_each_tree(function(tstree, _)
    local root = tstree:root()
    local root_start_row, _, root_end_row, _ = root:range()
    if root_start_row > start_row or root_end_row < start_row then
      return
    end
    positions = get_ts_positions(bufnr, start_row, end_row, root)
  end)
  return positions
end

local ticks = {}
---Save the user config and initialise the plugin
---@param conf BulletsConfig
function M.setup(conf)
  conf = conf or {}
  set_config(conf)
  api.nvim_set_decoration_provider(NAMESPACE, {
    on_start = function(_, tick)
      local buf = api.nvim_get_current_buf()
      if ticks[buf] == tick then
        return false
      end
      ticks[buf] = tick
      return true
    end,
    on_win = function(_, _, bufnr, topline, botline)
      if vim.bo[bufnr].filetype ~= "markdown" then
        return false
      end
      local positions = get_mark_positions(bufnr, topline, botline)
      set_position_marks(bufnr, positions, config)
    end,
    on_line = function(_, _, bufnr, row)
      local positions = get_mark_positions(bufnr, row, row + 1)
      set_position_marks(bufnr, positions, config)
    end,
  })
end

M.setup({})

function Get_ts_positions()
  local parser = get_parser(0)
  parser:for_each_tree(function(tstree, _)
    -- local positions = {}
    local nodes = {}
    local root = tstree:root()
    local query = vim.treesitter.query.parse(
      "markdown",
      [[
				(list_marker_minus) @list_marker_minus
			]]
    )
    for _, match, _ in query:iter_matches(root) do
      for id, node in pairs(match) do
        local name = query.captures[id]
        if vim.startswith(node:type(), "list_marker") then
          table.insert(
            nodes,
            { name = name, type = node:type(), item = vim.treesitter.get_node_text(node, 0) }
          )
          -- table.insert(nodes, get_list_level(node))
        end
      end
    end
    -- print(vim.inspect(positions))
    print(vim.inspect(nodes))
  end)
end
