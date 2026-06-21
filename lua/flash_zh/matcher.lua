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

local function is_pinyin_separator(char)
  return char == " " or char == "\t" or char == "-" or char == "_" or char == "'"
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

local function split_chars(text)
  local chars = {}
  for char in text:gmatch(".[\128-\191]*") do
    chars[#chars + 1] = char
  end
  return chars
end

local segment_cache = {}
local window_cache = {}

local function prepared_segment(segment_text)
  local cached = segment_cache[segment_text]
  if cached then return cached end

  local chars = split_chars(segment_text)
  local normalized_chars = {}
  local normalized_offsets = {}
  local normalized_offset = 1
  local pinyin_chars = {}
  local pinyin_offsets = {}
  local pinyin_matchable = {}
  local pinyin_offset = 1

  for index, char in ipairs(chars) do
    local normalized_char = punctuation_alias(char) or char:lower()
    normalized_chars[index] = normalized_char
    normalized_offsets[index] = normalized_offset
    normalized_offset = normalized_offset + #normalized_char

    pinyin_offsets[index] = pinyin_offset
    if is_pinyin_separator(normalized_char) then
      pinyin_chars[index] = ""
      pinyin_matchable[index] = false
    else
      pinyin_chars[index] = normalized_char
      pinyin_matchable[index] = true
      pinyin_offset = pinyin_offset + #normalized_char
    end
  end

  cached = {
    chars = chars,
    normalized_segment = table.concat(normalized_chars),
    normalized_offsets = normalized_offsets,
    pinyin_segment = table.concat(pinyin_chars),
    pinyin_offsets = pinyin_offsets,
    pinyin_matchable = pinyin_matchable,
  }
  segment_cache[segment_text] = cached
  return cached
end

local function snapshot_key(win)
  local info = vim.fn.getwininfo(win)[1]
  if not info then return end

  local buf = vim.api.nvim_win_get_buf(win)
  local changedtick = vim.api.nvim_buf_get_changedtick(buf)
  return table.concat({ buf, changedtick, info.topline, info.botline }, ":"), info
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

local function match_at(segment_text, char_index, pattern, pinyin_pattern)
  local segment = prepared_segment(segment_text)
  local normalized_index = segment.normalized_offsets[char_index]
  local pinyin_index = segment.pinyin_offsets[char_index]

  return segment.normalized_segment:find(pattern, normalized_index, true) == normalized_index
    or (
      segment.pinyin_matchable[char_index]
      and pinyin_pattern ~= ""
      and pinyin.match_prefix(segment.pinyin_segment:sub(pinyin_index), pinyin_pattern)
    )
end

local function match_positions(segment_text, pattern, pinyin_pattern)
  local positions = {}
  local segment = prepared_segment(segment_text)

  for char_index = 1, #segment.chars do
    if match_at(segment_text, char_index, pattern, pinyin_pattern) then
      positions[#positions + 1] = char_index
    end
  end
  return positions
end

local function visible_matches(win, pattern)
  local matches = {}
  local snapshot, info = snapshot_key(win)
  if not info or not pattern or pattern == "" then return matches end

  local normalized = normalize(pattern)
  if normalized == "" then return matches end
  local pinyin_pattern = normalized:gsub("[%s%-%_']+", "")

  local cached = window_cache[win]
  local candidates

  if cached and cached.snapshot == snapshot and normalized:sub(1, #cached.pattern) == cached.pattern then
    candidates = {}
    for _, candidate in ipairs(cached.candidates) do
      if match_at(candidate.segment_text, candidate.char_index, normalized, pinyin_pattern) then
        candidates[#candidates + 1] = candidate
      end
    end
  else
    candidates = {}
    local buf = vim.api.nvim_win_get_buf(win)
    local lines = vim.api.nvim_buf_get_lines(buf, info.topline - 1, info.botline, false)

    for offset, line in ipairs(lines) do
      local lnum = info.topline + offset - 1
      for _, segment in ipairs(searchable_segments(line)) do
        for _, char_index in ipairs(match_positions(segment.text, normalized, pinyin_pattern)) do
          local start_byte = vim.str_byteindex(line, segment.start_index + char_index - 1)
          candidates[#candidates + 1] = {
            win = win,
            pos = { lnum, start_byte },
            end_pos = { lnum, start_byte },
            segment_text = segment.text,
            char_index = char_index,
          }
        end
      end
    end
  end

  window_cache[win] = {
    snapshot = snapshot,
    pattern = normalized,
    candidates = candidates,
  }

  for _, candidate in ipairs(candidates) do
    matches[#matches + 1] = {
      win = candidate.win,
      pos = candidate.pos,
      end_pos = candidate.end_pos,
    }
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
