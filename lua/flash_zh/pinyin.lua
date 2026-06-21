local char_map = require "flash_zh.data.pinyin_char_data"

local M = {}
local phrase_shards = {}
local source = debug.getinfo(1, "S").source:sub(2)
local phrase_dir = vim.fs.joinpath(vim.fn.fnamemodify(source, ":p:h"), "data", "pinyin_phrase_shards")
local reading_cache = {}
local primary_cache = {}
local match_cache = {}
local warmup_done = false

local function is_cjk(codepoint)
  return (codepoint >= 0x3400 and codepoint <= 0x4DBF)
    or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
    or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
end

local function to_chars(str)
  local chars = {}
  local index = 1
  while index <= #str do
    local char = str:sub(index, index)
    local byte = string.byte(char)
    local size = 1
    if byte >= 240 then
      size = 4
    elseif byte >= 224 then
      size = 3
    elseif byte >= 192 then
      size = 2
    end
    chars[#chars + 1] = str:sub(index, index + size - 1)
    index = index + size
  end
  return chars
end

local function split_readings(value)
  local readings = {}
  if not value then return readings end
  for reading in value:gmatch("[^,]+") do
    readings[#readings + 1] = reading
  end
  return readings
end

local function reading_options(char)
  local readings = reading_cache[char]
  if readings then return readings end
  readings = split_readings(char_map[char])
  if #readings == 0 then readings[1] = char end
  reading_cache[char] = readings
  return readings
end

local function shard_name(char)
  return string.format("%05X", vim.fn.char2nr(char, true))
end

local function ensure_phrase_shard(char)
  local name = shard_name(char)
  if phrase_shards[name] then return phrase_shards[name] end

  local shard = {}
  local path = phrase_dir .. "/" .. name .. ".txt"
  if vim.fn.filereadable(path) == 1 then
    for _, line in ipairs(vim.fn.readfile(path)) do
      if line ~= "" then
        local phrase, raw_variants = unpack(vim.split(line, "\t", { plain = true }))
        local variants = {}
        if raw_variants then
          for _, item in ipairs(vim.split(raw_variants, ";", { plain = true })) do
            local full, abbr = unpack(vim.split(item, ",", { plain = true }))
            if full and abbr then variants[#variants + 1] = { full = full, abbr = abbr } end
          end
        end
        shard[phrase] = variants
      end
    end
  end

  phrase_shards[name] = shard
  return shard
end

local function phrase_branches(char_list, start_index)
  local phrases = ensure_phrase_shard(char_list[start_index])
  local branches = {}
  for stop_index = #char_list, start_index + 1, -1 do
    local phrase = table.concat(char_list, "", start_index, stop_index)
    local variants = phrases[phrase]
    if variants then
      for _, variant in ipairs(variants) do
        branches[#branches + 1] = {
          len = stop_index - start_index + 1,
          full = variant.full,
          abbr = variant.abbr,
        }
      end
    end
  end
  return branches
end

local function char_branches(char)
  local branches = {}
  for _, reading in ipairs(reading_options(char)) do
    branches[#branches + 1] = { len = 1, full = reading, abbr = reading:sub(1, 1) }
  end
  return branches
end

local function reading_branches(char_list, start_index)
  local branches = phrase_branches(char_list, start_index)
  for _, branch in ipairs(char_branches(char_list[start_index])) do
    branches[#branches + 1] = branch
  end
  return branches
end

local function primary(chars, separator)
  local cache_key = chars .. "\0" .. (separator or " ")
  local cached = primary_cache[cache_key]
  if cached then return cached.full, cached.abbr end

  separator = separator or " "
  local full = {}
  local abbr = {}
  local char_list = to_chars(chars)
  local index = 1
  while index <= #char_list do
    local best = reading_branches(char_list, index)[1]
    full[#full + 1] = best.full
    abbr[#abbr + 1] = best.abbr
    index = index + best.len
  end

  local full_text = table.concat(full, separator)
  local abbr_text = table.concat(abbr, separator)
  primary_cache[cache_key] = { full = full_text, abbr = abbr_text }
  return full_text, abbr_text
end

local function branch_matches(branch, remaining)
  if remaining:find(branch.full, 1, true) == 1 then return #branch.full, false end
  if branch.full:find(remaining, 1, true) == 1 then return 0, true end
  if remaining:find(branch.abbr, 1, true) == 1 then return #branch.abbr, false end
  if branch.abbr:find(remaining, 1, true) == 1 then return 0, true end
  return nil, false
end

function M.match_prefix(chars, pattern)
  local cache_key = chars .. "\0" .. pattern
  if match_cache[cache_key] ~= nil then return match_cache[cache_key] end

  local char_list = to_chars(chars)
  local cache = {}

  local function dfs(char_index, pattern_index)
    local key = char_index .. ':' .. pattern_index
    if cache[key] ~= nil then return cache[key] end
    if pattern_index > #pattern then return true end
    if char_index > #char_list then return false end

    local remaining = pattern:sub(pattern_index)
    for _, branch in ipairs(reading_branches(char_list, char_index)) do
      local consumed, partial = branch_matches(branch, remaining)
      if partial then cache[key] = true; return true end
      if consumed and dfs(char_index + branch.len, pattern_index + consumed) then
        cache[key] = true
        return true
      end
    end

    cache[key] = false
    return false
  end

  local matched = dfs(1, 1)
  match_cache[cache_key] = matched
  return matched
end

function M.warmup(opts)
  if warmup_done then return end

  opts = opts or {}
  local wins = opts.wins or vim.api.nvim_list_wins()
  local limit = opts.limit or 24
  local seen = {}
  local chars = {}

  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local info = vim.fn.getwininfo(win)[1]
      if info then
        local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), info.topline - 1, math.min(info.botline, info.topline + 2), false)
        for _, line in ipairs(lines) do
          for char in line:gmatch(".[\128-\191]*") do
            if #chars >= limit then break end
            local codepoint = vim.fn.char2nr(char, true)
            if is_cjk(codepoint) and not seen[char] then
              seen[char] = true
              chars[#chars + 1] = char
            end
          end
          if #chars >= limit then break end
        end
      end
    end
    if #chars >= limit then break end
  end

  if #chars == 0 then return end

  for _, char in ipairs(chars) do
    primary(char, " ")
  end

  warmup_done = true
end

local function pinyin(chars, isString, separator)
  if isString then return primary(chars, separator) end
  local full = {}
  local abbr = {}
  for _, char in ipairs(to_chars(chars)) do
    local branch = char_branches(char)[1]
    full[#full + 1] = branch.full
    abbr[#abbr + 1] = branch.abbr
  end
  return full, abbr
end

return setmetatable(M, { __call = function(_, chars, isString, separator) return pinyin(chars, isString, separator) end })
