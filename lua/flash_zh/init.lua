local M = {}

local defaults = {
  labels = "abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ",
}

local continuation_separators = {
  [" "] = true,
  ["\t"] = true,
  ["!"] = true,
  ['"'] = true,
  ["#"] = true,
  ["$"] = true,
  ["%"] = true,
  ["&"] = true,
  ["'"] = true,
  ["("] = true,
  [")"] = true,
  ["*"] = true,
  ["+"] = true,
  [","] = true,
  ["-"] = true,
  ["."] = true,
  ["/"] = true,
  [":"] = true,
  [";"] = true,
  ["<"] = true,
  ["="] = true,
  [">"] = true,
  ["?"] = true,
  ["@"] = true,
  ["["] = true,
  ["\\"] = true,
  ["]"] = true,
  ["^"] = true,
  ["_"] = true,
  ["`"] = true,
  ["{"] = true,
  ["|"] = true,
  ["}"] = true,
  ["~"] = true,
}

local function case_variants(label)
  if not label:match "%a" then return { label } end
  local lower = label:lower()
  local upper = label:upper()
  if lower == upper then return { label } end
  if lower == label then return { lower, upper } end
  if upper == label then return { upper, lower } end
  return { label, lower, upper }
end

local function separator_continuations(matches, pattern)
  local reserved = {}
  if pattern:find("[%z\128-\255]") then return reserved end

  local pattern_len = #pattern
  local line_cache = {}

  local function reserve(win, label)
    reserved[win] = reserved[win] or {}
    for _, variant in ipairs(case_variants(label)) do
      reserved[win][variant] = true
    end
  end

  for _, match in ipairs(matches) do
    local win = match.win
    local win_lines = line_cache[win]
    if win_lines == nil then
      win_lines = {}
      line_cache[win] = win_lines
    end

    local lnum = match.pos[1]
    local line = win_lines[lnum]
    if line == nil then
      line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), lnum - 1, lnum, false)[1] or ""
      win_lines[lnum] = line
    end

    local after_pattern = line:sub(match.pos[2] + pattern_len + 1)
    local index = 1
    while index <= #after_pattern do
      local char = after_pattern:sub(index, index)
      if not continuation_separators[char] then break end
      index = index + 1
    end
    local label = after_pattern:sub(index, index)
    if label:match "%w" then
      reserve(win, label)
    end

    if pattern_len <= 2 then
      local suffix_index = index
      while suffix_index <= #after_pattern do
        local char = after_pattern:sub(suffix_index, suffix_index)
        if not char:match "%w" then break end
        reserve(win, char)
        suffix_index = suffix_index + 1
      end
    end
  end

  return reserved
end

local function zh_labeler()
  local flash_labeler = require "flash.labeler"
  local matcher = require "flash_zh.matcher"

  return function(_, state)
    state.flash_zh_labeler = state.flash_zh_labeler or flash_labeler.new(state)
    local labeler = state.flash_zh_labeler
    labeler:reset()

    if #state.pattern() < state.opts.label.min_pattern_length then return end

    local matches = labeler:filter()
    local current_match_ids = {}
    local continuation = {}
    local full_labels = vim.deepcopy(labeler.labels)
    local label_index = {}
    local pattern = state.pattern()
    local has_match_cache = {}
    local separator_reserved = separator_continuations(matches, pattern)

    for _, match in ipairs(matches) do
      current_match_ids[match.pos:id(match.win)] = true
    end

    for id in pairs(labeler.used) do
      if not current_match_ids[id] then
        labeler.used[id] = nil
      end
    end

    for index, label in ipairs(full_labels) do
      label_index[label] = index
    end

    local function has_continuation(win, label)
      local reserved = separator_reserved[win]
      if reserved and reserved[label] then
        return true
      end

      local cache_key = win .. "\0" .. label
      if has_match_cache[cache_key] == nil then
        has_match_cache[cache_key] = matcher.has_matches(win, pattern .. label)
      end
      return has_match_cache[cache_key]
    end

    for _, label in ipairs(labeler.labels) do
      if label:match "%a" then
        local variants = case_variants(label)
        local has_variant_continuation = false

        for _, win in ipairs(state.wins) do
          for _, variant in ipairs(variants) do
            if has_continuation(win, variant) then
              has_variant_continuation = true
              break
            end
          end
          if has_variant_continuation then break end
        end

        if has_variant_continuation then
          for _, variant in ipairs(variants) do
            continuation[variant] = true
          end
        end
      end
    end

    local assigned = {}

    local function is_assignable(label)
      return label and not continuation[label] and not assigned[label]
    end

    local function assign(match, label)
      match.label = label
      assigned[label] = true
      labeler.used[match.pos:id(match.win)] = label
    end

    local function assign_next_available(match, start_index)
      for index = start_index, #full_labels do
        local label = full_labels[index]
        if is_assignable(label) then
          assign(match, label)
          return true
        end
      end

      for index = 1, start_index - 1 do
        local label = full_labels[index]
        if is_assignable(label) then
          assign(match, label)
          return true
        end
      end

      return false
    end

    for _, match in ipairs(matches) do
      local reused = labeler.used[match.pos:id(match.win)]
      if is_assignable(reused) then assign(match, reused) end
    end

    for _, match in ipairs(matches) do
      if match.label == nil then
        local previous = labeler.used[match.pos:id(match.win)]
        local start_index = previous and label_index[previous] or 1
        assign_next_available(match, start_index)
      end
    end
  end
end

local function is_visual_mode(mode)
  local prefix = mode:sub(1, 1)
  return prefix == "v" or prefix == "V" or prefix == string.char(22)
end

local function enter_visual(mode)
  local prefix = mode:sub(1, 1)
  if prefix == "V" then
    vim.cmd "normal! V"
  elseif prefix == string.char(22) then
    vim.cmd("normal! \\<C-v>")
  else
    vim.cmd "normal! v"
  end
end

local function visual_action(anchor, mode, user_action)
  local jump = require "flash.jump"
  local is_block = mode:sub(1, 1) == string.char(22)

  return function(match, state)
    vim.schedule(function()
      vim.api.nvim_set_current_win(match.win)

      local anchor_row = anchor[2]
      local anchor_col = math.max(anchor[3] - 1, 0)

      if user_action then
        user_action(match, state)
        return
      end

      jump.open_folds(match)

      if is_block then
        vim.api.nvim_win_set_cursor(match.win, { anchor_row, anchor_col })
        enter_visual(mode)
        vim.api.nvim_win_set_cursor(match.win, match.pos)
      else
        vim.api.nvim_buf_set_mark(0, "<", anchor_row, anchor_col, {})
        vim.api.nvim_buf_set_mark(0, ">", match.pos[1], match.pos[2], {})
        vim.api.nvim_win_set_cursor(match.win, { match.pos[1], match.pos[2] })
        enter_visual(mode)
        vim.cmd "normal! gv"
      end

      jump.on_jump(state)
    end)

    return match
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  require("flash_zh.pinyin").warmup({ wins = vim.api.nvim_list_wins() })
end

function M.jump(opts)
  local config = vim.tbl_deep_extend("force", {}, M.config or defaults, opts or {})
  require("flash_zh.pinyin").warmup({ wins = vim.api.nvim_list_wins() })
  local flash_opts = require("flash_zh.matcher").opts(config)
  local mode = vim.fn.mode(true)
  flash_opts.labeler = zh_labeler()

  if is_visual_mode(mode) then
    flash_opts.action = visual_action(vim.fn.getpos "v", mode, config.action)
  else
    flash_opts.action = config.action
  end

  return require("flash").jump(flash_opts)
end

function M.remote(opts)
  local config = vim.tbl_deep_extend("force", {}, M.config or defaults, opts or {})
  return M.jump(vim.tbl_deep_extend("force", {}, config, {
    mode = "remote",
    remote_op = {
      restore = true,
      motion = true,
    },
  }))
end

return M
