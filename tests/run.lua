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

local function test_matcher_punctuation_aliases()
  local opts = matcher.opts({})

  with_buffer_line("属性：值", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return ":" end }), 1, ": should match fullwidth colon")
    assert_equal(#opts.matcher(win, { pattern = function() return "属性:" end }), 1, "ASCII colon should match fullwidth colon in text")
  end)

  with_buffer_line("你好，世界。", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return "," end }), 1, ", should match fullwidth comma")
    assert_equal(#opts.matcher(win, { pattern = function() return "世界." end }), 1, "ASCII period should match Chinese period in text")
  end)

  with_buffer_line("列表、项目", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return "/" end }), 1, "/ should match Chinese enumeration comma")
  end)

  with_buffer_line("函数（参数）", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return "(" end }), 1, "( should match fullwidth left parenthesis")
    assert_equal(#opts.matcher(win, { pattern = function() return "参数)" end }), 1, ") should match fullwidth right parenthesis")
  end)

  with_buffer_line("《标题》", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return "<标" end }), 1, "< should match Chinese left title mark")
    assert_equal(#opts.matcher(win, { pattern = function() return "题>" end }), 1, "> should match Chinese right title mark")
  end)

  with_buffer_line("《海贼王》", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return "<h" end }), 1, "punctuation aliases should work with pinyin initials")
    assert_equal(#opts.matcher(win, { pattern = function() return "<ha" end }), 1, "punctuation aliases should work with partial pinyin")
    assert_equal(#opts.matcher(win, { pattern = function() return "<hai" end }), 1, "punctuation aliases should work with full pinyin")
  end)

  with_buffer_line("他说“好的”", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return '"好' end }), 1, "double quote should match Chinese left double quote")
    assert_equal(#opts.matcher(win, { pattern = function() return '的"' end }), 1, "double quote should match Chinese right double quote")
  end)

  with_buffer_line("甲——乙……丙·丁", function(win)
    assert_equal(#opts.matcher(win, { pattern = function() return "--" end }), 1, "-- should match Chinese dash sequence")
    assert_equal(#opts.matcher(win, { pattern = function() return ".." end }), 1, ".. should match Chinese ellipsis sequence")
    assert_equal(#opts.matcher(win, { pattern = function() return ".丁" end }), 1, ". should match Chinese middle dot")
  end)
end

local function test_matcher_pinyin_across_separators()
  with_buffer_line("宇 宙", function(win)
    local opts = matcher.opts({})
    assert_equal(#opts.matcher(win, { pattern = function() return "yu zhou" end }), 1, "pinyin should match across text spaces")
    assert_equal(#opts.matcher(win, { pattern = function() return "yuzhou" end }), 1, "continuous pinyin should match across text spaces")
    assert_equal(#opts.matcher(win, { pattern = function() return "yz" end }), 1, "pinyin initials should match across text spaces")
    assert_equal(#opts.matcher(win, { pattern = function() return "宇 宙" end }), 1, "literal space matching should still work")
  end)

  with_buffer_line("API 响 应", function(win)
    local opts = matcher.opts({})
    assert_equal(#opts.matcher(win, { pattern = function() return "api xy" end }), 1, "mixed ascii and pinyin initials should match across spaces")
    assert_equal(#opts.matcher(win, { pattern = function() return "api xiangying" end }), 1, "mixed ascii and full pinyin should match across spaces")
  end)

  with_buffer_line("星-际_旅'行", function(win)
    local opts = matcher.opts({})
    assert_equal(#opts.matcher(win, { pattern = function() return "xjlx" end }), 1, "pinyin initials should match across light separators")
    assert_equal(#opts.matcher(win, { pattern = function() return "xj-lx" end }), 1, "pinyin pattern separators should still be ignored")
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

local function test_ascii_separator_continuation_skips_case_pair()
  init.setup()
  with_buffer_line("M-a M-b M-c M-d M-e M-f M-g M-h M-i M-j M-k M-l M-m M-n M-o M-p M-q M-r M-s M-t M-u M-v M-w M-x M-y M-z M-X", function()
    local state = require("flash.state").new(require("flash_zh.matcher").opts(init.config))
    state:update({ pattern = "M-", force = true })

    local labels = extract_labels(state)
    assert_truthy(#labels > 0, "labels should be assigned for ascii continuation test")
    for _, label in ipairs(labels) do
      assert_equal(label == "x", false, "continuation label x should be skipped for pattern M-")
      assert_equal(label == "X", false, "continuation label X should be skipped for pattern M-")
    end

    state:hide()
  end)
end

local function test_angle_bracket_meta_continuation_skips_case_pair()
  init.setup()
  with_buffer_line("<M-B> <M-N> <M-P> <M-E> <M-L> <M-H> <M-V> <M-G> <M-Z> <M-T>", function()
    local state = require("flash.state").new(require("flash_zh.matcher").opts(init.config))
    state:update({ pattern = "<M-", force = true })

    local labels = extract_labels(state)
    assert_truthy(#labels > 0, "labels should be assigned for angle bracket meta continuation test")
    for _, label in ipairs(labels) do
      assert_equal(label == "n", false, "continuation label n should be skipped for pattern <M-")
      assert_equal(label == "N", false, "continuation label N should be skipped for pattern <M-")
      assert_equal(label == "p", false, "continuation label p should be skipped for pattern <M-")
      assert_equal(label == "P", false, "continuation label P should be skipped for pattern <M-")
    end

    state:hide()
  end)
end

local function test_m_prefix_reserves_separator_continuations()
  init.setup()
  with_buffer_line("M-x M-y M-z M-a M-b M-c M-d M-e M-f M-g M-h M-i M-j M-k M-l M-m M-n M-o M-p M-q M-r M-s M-t M-u M-v M-w M-X", function()
    local captured
    local original = require("flash").jump
    require("flash").jump = function(opts)
      captured = opts
      return opts
    end

    init.jump()

    require("flash").jump = original

    local state = require("flash.state").new(captured)
    state:update({ pattern = "M", force = true })

    local labels = extract_labels(state)
    assert_truthy(#labels > 0, "labels should be assigned for M-prefix reservation test")
    for _, label in ipairs(labels) do
      assert_equal(label == "x", false, "label x should be reserved for pattern M when M-x exists")
      assert_equal(label == "X", false, "label X should be reserved for pattern M when M-X exists")
    end

    state:hide()
  end)
end

local function assert_labels_do_not_include(pattern, line, forbidden_labels, message)
  init.setup()
  with_buffer_line(line, function()
    local state = require("flash.state").new(require("flash_zh.matcher").opts(init.config))
    state:update({ pattern = pattern, force = true })

    local labels = extract_labels(state)
    assert_truthy(#labels > 0, message .. ": labels should be assigned")
    for _, label in ipairs(labels) do
      for _, forbidden in ipairs(forbidden_labels) do
        assert_equal(label == forbidden, false, string.format("%s: label %s should be skipped for pattern %s", message, forbidden, pattern))
      end
    end

    state:hide()
  end)
end

local function test_ascii_literal_continuation_variants()
  assert_labels_do_not_include(
    "foo-",
    "foo-a foo-b foo-c foo-d foo-e foo-f foo-g foo-h foo-i foo-j foo-k foo-l foo-m foo-n foo-o foo-p foo-q foo-r foo-s foo-t foo-u foo-v foo-w foo-x foo-y foo-z foo-A",
    { "a", "A" },
    "ascii hyphen continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "bar-",
    "bar-a bar-b bar-c bar-d bar-e bar-f bar-g bar-h bar-i bar-j bar-k bar-l bar-m bar-n bar-o bar-p bar-q bar-r bar-s bar-t bar-u bar-v bar-w bar-x bar-y bar-z bar-X",
    { "x", "X" },
    "ascii uppercase continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "A-",
    "A-1 A-2 A-3 A-4 A-5 A-6 A-7 A-8 A-9 A-0",
    { "1" },
    "ascii numeric continuation should skip digit label"
  )

  assert_labels_do_not_include(
    "x_",
    "x_a x_b x_c x_d x_e x_f x_g x_h x_i x_j x_k x_l x_m x_n x_o x_p x_q x_r x_s x_t x_u x_v x_w x_x x_y x_z x_A",
    { "a", "A" },
    "ascii underscore continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "foo/",
    "foo/a foo/b foo/c foo/d foo/e foo/f foo/g foo/h foo/i foo/j foo/k foo/l foo/m foo/n foo/o foo/p foo/q foo/r foo/s foo/t foo/u foo/v foo/w foo/x foo/y foo/z foo/X",
    { "x", "X" },
    "ascii slash continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "it'",
    "it's it'sa it'sb it'sc it'sd it'se it'sf it'sg it'sh it'si it'sj it'sk it'sl it'sm it'sn it'so it'sp it'sq it'sr it'ss itst it'su it'sv it'sw it'sx it'sy it'sz it'sA",
    { "s", "S" },
    "ascii apostrophe continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "foo.",
    "foo.a foo.b foo.c foo.d foo.e foo.f foo.g foo.h foo.i foo.j foo.k foo.l foo.m foo.n foo.o foo.p foo.q foo.r foo.s foo.t foo.u foo.v foo.w foo.x foo.y foo.z foo.X",
    { "x", "X" },
    "ascii dot continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "mod:",
    "mod:a mod:b mod:c mod:d mod:e mod:f mod:g mod:h mod:i mod:j mod:k mod:l mod:m mod:n mod:o mod:p mod:q mod:r mod:s mod:t mod:u mod:v mod:w mod:x mod:y mod:z mod:A",
    { "a", "A" },
    "ascii colon continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "foo+",
    "foo+a foo+b foo+c foo+d foo+e foo+f foo+g foo+h foo+i foo+j foo+k foo+l foo+m foo+n foo+o foo+p foo+q foo+r foo+s foo+t foo+u foo+v foo+w foo+x foo+y foo+z foo+A",
    { "a", "A" },
    "ascii plus continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "bar=",
    "bar=a bar=b bar=c bar=d bar=e bar=f bar=g bar=h bar=i bar=j bar=k bar=l bar=m bar=n bar=o bar=p bar=q bar=r bar=s bar=t bar=u bar=v bar=w bar=x bar=y bar=z bar=X",
    { "x", "X" },
    "ascii equal continuation should skip case pair"
  )

  assert_labels_do_not_include(
    "ns::",
    "ns::a ns::b ns::c ns::d ns::e ns::f ns::g ns::h ns::i ns::j ns::k ns::l ns::m ns::n ns::o ns::p ns::q ns::r ns::s ns::t ns::u ns::v ns::w ns::x ns::y ns::z ns::A",
    { "a", "A" },
    "double colon continuation should skip case pair"
  )

  with_buffer_line(
    "arr[a arr[b arr[c arr[d arr[e arr[f arr[g arr[h arr[i arr[j arr[k arr[l arr[m arr[n arr[o arr[p arr[q arr[r arr[s arr[t arr[u arr[v arr[w arr[x arr[y arr[z arr[X",
    function()
      local state = require("flash.state").new(require("flash_zh.matcher").opts(init.config))
      state:update({ pattern = "arr[", force = true })

      local first = state.results[1]
      assert_truthy(first ~= nil, "bracket continuation should produce a first result")
      assert_equal(first.label == "a", false, "bracket continuation should not assign label a to arr[")
      assert_equal(first.label == "A", false, "bracket continuation should not assign label A to arr[")

      state:hide()
    end
  )

  with_buffer_line(
    "fn<a fn<b fn<c fn<d fn<e fn<f fn<g fn<h fn<i fn<j fn<k fn<l fn<m fn<n fn<o fn<p fn<q fn<r fn<s fn<t fn<u fn<v fn<w fn<x fn<y fn<z fn<X",
    function()
      local state = require("flash.state").new(require("flash_zh.matcher").opts(init.config))
      state:update({ pattern = "fn<", force = true })

      local first = state.results[1]
      assert_truthy(first ~= nil, "angle continuation should produce a first result")
      assert_equal(first.label == "a", false, "angle continuation should not assign label a to fn<")
      assert_equal(first.label == "A", false, "angle continuation should not assign label A to fn<")

      state:hide()
    end
  )
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
    "abcdefghijklmnopqrstuvwxyz1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "default labels should prefer lowercase, then digits, then uppercase"
  )
  assert_equal(opts.label.uppercase, false, "explicit mixed-case labels should not rely on uppercase expansion")
end

local function test_label_reuse_recyles_disappeared_matches()
  init.setup()
  with_buffer_line("class LinkAPIMonitor:", function()
    vim.api.nvim_buf_set_lines(0, 1, 1, false, {
      "class LinkAPIMonitor:",
      "class LinkAPIMonitor:",
      "class LinkAPIMonitor:",
    })

    local captured
    local original = require("flash").jump
    require("flash").jump = function(opts)
      captured = opts
      return opts
    end

    init.jump()

    require("flash").jump = original

    local state = require("flash.state").new(captured)
    state:update({ pattern = "l", force = true })

    local labels_l = {}
    for _, match in ipairs(state.results) do
      labels_l[table.concat(match.pos, ":")] = match.label
    end

    state:update({ pattern = "li", force = true })
    local labels_li = {}
    for _, match in ipairs(state.results) do
      labels_li[table.concat(match.pos, ":")] = match.label
    end

    state:update({ pattern = "lin", force = true })
    local labels_lin = {}
    for _, match in ipairs(state.results) do
      labels_lin[table.concat(match.pos, ":")] = match.label
    end

    assert_truthy(next(labels_l) ~= nil, "l should produce labels")
    assert_truthy(next(labels_li) ~= nil, "li should produce labels")
    assert_truthy(next(labels_lin) ~= nil, "lin should produce labels")

    local reused = false
    for pos, label in pairs(labels_li) do
      if labels_l[pos] == label then
        reused = true
        break
      end
    end
    assert_truthy(reused, "surviving matches should keep stable labels")

    local recycled = true
    for pos, label in pairs(labels_lin) do
      if labels_li[pos] == nil and label == nil then
        recycled = false
        break
      end
    end
    assert_truthy(recycled, "new surviving matches should not be left unlabeled after recycle")

    state:hide()
  end)
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
  test_matcher_punctuation_aliases,
  test_matcher_pinyin_across_separators,
  test_has_matches,
  test_smart_label_skip,
  test_ascii_separator_continuation_skips_case_pair,
  test_angle_bracket_meta_continuation_skips_case_pair,
  test_m_prefix_reserves_separator_continuations,
  test_ascii_literal_continuation_variants,
  test_label_reuse_across_updates,
  test_letter_reuse_mode_is_all,
  test_remote_opts,
  test_matcher_opts_preserve_config,
  test_label_order_default,
  test_label_reuse_recyles_disappeared_matches,
  test_jump_action_injection,
}

for _, test in ipairs(tests) do
  test()
end

print("flash-zh tests passed")
