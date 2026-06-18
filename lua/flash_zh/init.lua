local M = {}

local defaults = {
  labels = "1234567890",
}

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

  return function(match, state)
    vim.api.nvim_set_current_win(match.win)
    vim.api.nvim_win_set_cursor(match.win, { anchor[2], math.max(anchor[3] - 1, 0) })
    enter_visual(mode)

    if user_action then
      return user_action(match, state)
    end

    return jump.jump(match, state)
  end
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

function M.jump(opts)
  local config = vim.tbl_deep_extend("force", {}, M.config or defaults, opts or {})
  local flash_opts = require("flash_zh.matcher").opts(config)
  local mode = vim.fn.mode(true)

  if is_visual_mode(mode) then
    flash_opts.action = visual_action(vim.fn.getpos "v", mode, config.action)
  else
    flash_opts.action = config.action
  end

  return require("flash").jump(flash_opts)
end

return M
