local M = {}

local defaults = {
  labels = "1234567890",
}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", {}, defaults, opts or {})
end

function M.jump(opts)
  local config = vim.tbl_deep_extend("force", {}, M.config or defaults, opts or {})
  return require("flash").jump(require("flash_zh.matcher").opts(config))
end

return M
