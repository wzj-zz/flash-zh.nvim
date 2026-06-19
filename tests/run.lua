package.path = table.concat({
  "./lua/?.lua",
  "./lua/?/init.lua",
  package.path,
}, ";")

local flash_runtime = vim.fn.stdpath "data" .. "/lazy/flash.nvim"
if vim.fn.isdirectory(flash_runtime) == 1 then
  vim.opt.runtimepath:prepend(flash_runtime)
end

local function assert_equal(actual, expected, message)
  if actual ~= expected then
    error((message or "assert_equal failed") .. string.format("\nexpected: %s\nactual: %s", vim.inspect(expected), vim.inspect(actual)))
  end
end

local function assert_truthy(value, message)
  if not value then error(message or "assert_truthy failed") end
end

local function with_buffer_line(line, fn)
  vim.cmd.enew()
  vim.bo.buftype = "nofile"
  vim.bo.bufhidden = "wipe"
  vim.bo.swapfile = false
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  return fn(vim.api.nvim_get_current_win())
end

local matcher = require "flash_zh.matcher"
local init = require "flash_zh"

local function test_matcher_pinyin()
  with_buffer_line("文件搜索 文件收尾", function(win)
    local matches = matcher.opts({}).matcher(win, { pattern = function() return "sou" end })
    assert_equal(#matches, 1, "pinyin matcher should find one 搜")
    assert_equal(matches[1].pos[2], 6, "搜 byte position should match expected column")
  end)
end

local function test_matcher_ascii_and_space()
  with_buffer_line("foo ><& bar", function(win)
    local opts = matcher.opts({})
    assert_equal(#opts.matcher(win, { pattern = function() return " " end }), 2, "space should match two positions")
    assert_equal(#opts.matcher(win, { pattern = function() return ">" end }), 1, "> should match one position")
    assert_equal(#opts.matcher(win, { pattern = function() return "<&" end }), 1, "<& should match one position")
  end)
end

local function test_has_matches()
  with_buffer_line("代码跳转", function(win)
    assert_truthy(matcher.has_matches(win, "dm"), "dm should match 代码")
    assert_truthy(matcher.has_matches(win, "d-m"), "d-m should match 代码")
    assert_truthy(matcher.has_matches(win, "d m"), "d m should match 代码")
    assert_equal(matcher.has_matches(win, "dmx"), false, "dmx should not match")
  end)
end

local function extract_labels(state)
  local labels = {}
  for _, match in ipairs(state.results) do
    labels[#labels + 1] = match.label
  end
  return labels
end

local function test_smart_label_skip()
  init.setup()
  with_buffer_line("文件搜索 文件收尾", function()
    local state = require("flash.state").new(require("flash_zh.matcher").opts(init.config))
    state:update({ pattern = "so", force = true })
    local labels = extract_labels(state)
    assert_truthy(#labels > 0, "labels should be assigned")
    for _, label in ipairs(labels) do
      assert_equal(label == "u", false, "continuation label u should be skipped for pattern so")
    end
    state:hide()
  end)
end

local function test_label_reuse_across_updates()
  init.setup()
  with_buffer_line("文件搜索 文件收尾 文件书法", function()
    local captured
    local original = require("flash").jump
    require("flash").jump = function(opts)
      captured = opts
      return opts
    end
    init.jump()
    require("flash").jump = original

    local state = require("flash.state").new(captured)
    state:update({ pattern = "s", force = true })

    local labels_by_pos = {}
    for _, match in ipairs(state.results) do
      labels_by_pos[table.concat(match.pos, ":")] = match.label
    end

    state:update({ pattern = "so", force = true })
    for _, match in ipairs(state.results) do
      local key = table.concat(match.pos, ":")
      if labels_by_pos[key] then
        assert_equal(match.label, labels_by_pos[key], "labels should stay stable for surviving matches")
      end
    end

    state:update({ pattern = "sou", force = true })
    for _, match in ipairs(state.results) do
      local key = table.concat(match.pos, ":")
      if labels_by_pos[key] then
        assert_equal(match.label, labels_by_pos[key], "labels should remain stable across continuation filtering")
      end
    end

    state:hide()
  end)
end

local function test_letter_reuse_mode_is_all()
  local opts = matcher.opts({})
  assert_equal(opts.label.reuse, "all", "labels should reuse across case groups")
end

local function test_remote_opts()
  init.setup()
  local calls = {}
  local original = require("flash").jump
  require("flash").jump = function(opts)
    calls[#calls + 1] = opts
    return opts
  end

  local ok, err = pcall(function()
    init.remote()
  end)

  require("flash").jump = original

  if not ok then error(err) end
  assert_equal(#calls, 1, "remote should call flash.jump once")
  assert_equal(calls[1].mode, "remote", "remote mode should be forwarded")
  assert_equal(calls[1].remote_op.restore, true, "remote restore should be true")
  assert_equal(calls[1].remote_op.motion, true, "remote motion should be true")
end

local function test_matcher_opts_preserve_config()
  local opts = matcher.opts {
    labels = "xyz",
    search = { multi_window = true },
    jump = { autojump = true },
    mode = "remote",
  }

  assert_equal(opts.labels, "xyz", "custom labels should be preserved")
  assert_equal(opts.search.multi_window, true, "custom search config should be preserved")
  assert_equal(opts.jump.autojump, true, "custom jump config should be preserved")
  assert_equal(opts.mode, "remote", "extra flash opts should be forwarded")
end

local function test_label_order_default()
  init.setup()
  local opts = matcher.opts(init.config)
  assert_equal(
    opts.labels,
    "1234567890abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "default labels should prefer digits, then lowercase, then uppercase"
  )
  assert_equal(opts.label.uppercase, false, "explicit mixed-case labels should not rely on uppercase expansion")
end

local function test_jump_action_injection()
  init.setup()
  local calls = {}
  local original = require("flash").jump
  require("flash").jump = function(opts)
    calls[#calls + 1] = opts
    return opts
  end

  local ok, err = pcall(function()
    init.jump()
  end)

  require("flash").jump = original

  if not ok then error(err) end
  assert_equal(#calls, 1, "jump should call flash.jump once")
  assert_truthy(type(calls[1].labeler) == "function", "jump should inject custom labeler")
  assert_equal(calls[1].action, nil, "normal mode jump should not override action by default")
end

local tests = {
  test_matcher_pinyin,
  test_matcher_ascii_and_space,
  test_has_matches,
  test_smart_label_skip,
  test_label_reuse_across_updates,
  test_letter_reuse_mode_is_all,
  test_remote_opts,
  test_matcher_opts_preserve_config,
  test_label_order_default,
  test_jump_action_injection,
}

for _, test in ipairs(tests) do
  test()
end

print("flash-zh tests passed")
