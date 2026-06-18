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
