local pinyin = require "flash_zh.pinyin"

local M = {}

local punctuation_aliases = {
  ["　"] = " ",
  ["、"] = "/",
  ["。"] = ".",
  ["“"] = '"',
  ["”"] = '"',
  ["‘"] = "'",
  ["’"] = "'",
  ["《"] = "<",
  ["〈"] = "<",
  ["》"] = ">",
  ["〉"] = ">",
  ["【"] = "[",
  ["「"] = "[",
  ["『"] = "[",
  ["】"] = "]",
  ["」"] = "]",
  ["』"] = "]",
  ["—"] = "-",
  ["–"] = "-",
  ["…"] = ".",
  ["·"] = ".",
  ["￥"] = "$",
}

local function punctuation_alias(char)
  local alias = punctuation_aliases[char]
  if alias then return alias end

  if char:byte(1) ~= 0xEF then return end

  local codepoint = vim.fn.char2nr(char, true)
  if codepoint >= 0xFF01 and codepoint <= 0xFF5E then
    return string.char(codepoint - 0xFEE0)
  end
end

local function normalize_text(text)
  return (text:gsub(".[\128-\191]*", function(char)
    return punctuation_alias(char) or char:lower()
  end))
end

local function normalize(pattern)
  return normalize_text(pattern)
end

local function is_cjk(codepoint)
  return (codepoint >= 0x3400 and codepoint <= 0x4DBF)
    or (codepoint >= 0x4E00 and codepoint <= 0x9FFF)
    or (codepoint >= 0xF900 and codepoint <= 0xFAFF)
end

local function is_visible_ascii(codepoint)
  return codepoint >= 0x20 and codepoint <= 0x7E
end

local function is_searchable_char(char)
  local codepoint = vim.fn.char2nr(char, true)
  return is_cjk(codepoint) or is_visible_ascii(codepoint) or punctuation_alias(char) ~= nil
end

local function char_at(line, index)
  return vim.fn.strcharpart(line, index, 1)
end

local function searchable_segments(line)
  local segments = {}
  local count = vim.fn.strchars(line)
  local start_index

  for index = 0, count - 1 do
    local char = char_at(line, index)
    if is_searchable_char(char) then
      start_index = start_index or index
    elseif start_index then
      segments[#segments + 1] = {
        start_index = start_index,
        text = vim.fn.strcharpart(line, start_index, index - start_index),
      }
      start_index = nil
    end
  end

  if start_index then
    segments[#segments + 1] = {
      start_index = start_index,
      text = vim.fn.strcharpart(line, start_index, count - start_index),
    }
  end

  return segments
end

local function split_chars(text)
  local chars = {}
  for char in text:gmatch(".[\128-\191]*") do
    chars[#chars + 1] = char
  end
  return chars
end

local function match_positions(segment_text, pattern)
  local positions = {}
  local chars = split_chars(segment_text)
  local normalized_chars = {}
  local normalized_offsets = {}
  local normalized_offset = 1
  local pinyin_pattern = pattern:gsub("[%s%-%_']+", "")

  for index, char in ipairs(chars) do
    normalized_chars[index] = punctuation_alias(char) or char:lower()
    normalized_offsets[index] = normalized_offset
    normalized_offset = normalized_offset + #normalized_chars[index]
  end

  local normalized_segment = table.concat(normalized_chars)

  for char_index = 1, #chars do
    local candidate = table.concat(chars, "", char_index)
    local normalized_index = normalized_offsets[char_index]
    local normalized_candidate = normalized_segment:sub(normalized_index)
    if
      normalized_segment:find(pattern, normalized_index, true) == normalized_index
      or (pinyin_pattern ~= "" and pinyin.match_prefix(normalized_candidate, pinyin_pattern))
    then
      positions[#positions + 1] = char_index
    end
  end
  return positions
end

local function visible_matches(win, pattern)
  local matches = {}
  local info = vim.fn.getwininfo(win)[1]
  if not info or not pattern or pattern == "" then return matches end

  local normalized = normalize(pattern)
  if normalized == "" then return matches end

  local buf = vim.api.nvim_win_get_buf(win)
  local lines = vim.api.nvim_buf_get_lines(buf, info.topline - 1, info.botline, false)

  for offset, line in ipairs(lines) do
    local lnum = info.topline + offset - 1
    for _, segment in ipairs(searchable_segments(line)) do
      for _, char_index in ipairs(match_positions(segment.text, normalized)) do
        local start_byte = vim.str_byteindex(line, segment.start_index + char_index - 1)
        matches[#matches + 1] = {
          win = win,
          pos = { lnum, start_byte },
          end_pos = { lnum, start_byte },
        }
      end
    end
  end

  return matches
end

function M.opts(config)
  local opts = {
    jump = { autojump = false },
    highlight = { matches = false },
    labels = (config and config.labels) or "abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    search = {
      multi_window = false,
      mode = "exact",
      trigger = "",
    },
    label = {
      uppercase = false,
      before = { 0, 0 },
      after = false,
      reuse = "all",
    },
    matcher = function(win, state)
      return visible_matches(win, state.pattern())
    end,
  }

  return vim.tbl_deep_extend("force", {}, opts, config or {})
end

function M.has_matches(win, pattern)
  return #visible_matches(win, pattern) > 0
end

return M
