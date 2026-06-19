# flash-zh.nvim

`flash.nvim` 的中文增强插件，提供：

- 中文拼音全拼匹配
- 中文拼音首字母匹配
- 英文/数字 ASCII 实时混合搜索
- 面向当前可见屏幕内容的轻量跳转

当前设计目标是作为 `flash.nvim` 的扩展层使用，而不是独立 fuzzy finder。

## 安装

- Neovim
- `folke/flash.nvim`

### `lazy.nvim`

如果你之前没有单独给 `flash.nvim` 配过 `s` / `r`，直接照下面的配置抄就可以开箱即用。

如果你已经在自己的 `flash.nvim` 配置里保留了原生 `s` / `r` 映射，那想让 `flash-zh.nvim` 接管这两个键时，就需要移除或覆盖原来的同名映射。

```lua
return {
  {
    "wzj-zz/flash-zh.nvim",
    dependencies = { "folke/flash.nvim" },
    opts = {},
    config = function(_, opts)
      require("flash_zh").setup(opts)
    end,
    keys = {
      {
        "s",
        mode = { "n", "x" },
        function() require("flash_zh").jump() end,
        desc = "Flash Zh",
      },
      {
        "r",
        mode = "o",
        function() require("flash_zh").remote() end,
        desc = "Remote Flash Zh",
      },
    },
  },
}
```

## 使用

- 触发后实时筛选当前屏幕可见范围内的连续可搜索串
- 支持中文拼音、首字母、英文/数字混合搜索
- 支持用键盘 ASCII 标点匹配常见中文/全角标点，例如 `:` 匹配 `：`，`<h` 匹配 `《海...`
- 拼音匹配可跨过文本中的空格、`-`、`_`、`'` 等轻分隔符，例如 `yu zhou` 匹配 `宇 宙`
- 不自动跳转
- 默认优先使用小写字母标签，其次数字，最后才使用大写字母；会尽量避开与当前拼音续输冲突的字母标签
- 可选用 `require("flash_zh").remote()` 作为 operator-pending 的远程拼音跳转入口

## 数据

运行时依赖两类生成数据：

- `lua/flash_zh/data/pinyin_char_data.lua`
- `lua/flash_zh/data/pinyin_phrase_shards/*.txt`

数据来源：

- `Chaoses-Ib/pinyin-data`
- `mozillazg/phrase-pinyin-data`

## 维护

普通使用者不需要关心本节内容。

`scripts/generate-pinyin-data.mjs` 是维护者工具，用来在上游拼音数据更新后重新生成插件内置数据。

### 重新生成数据

```powershell
node "scripts/generate-pinyin-data.mjs"
```

### 运行测试

```powershell
nvim --headless -u NONE -c "lua dofile('tests/run.lua')" -c qa!
```

脚本默认从环境变量 `FLASH_ZH_TEMP_ROOT` 指定的临时目录读取上游仓库副本；未设置时使用本机默认临时目录：

- `<temp>/ib-pinyin-data`
- `<temp>/phrase-pinyin-data`

## 当前结构

- `lua/flash_zh/init.lua`: 对外入口
- `lua/flash_zh/matcher.lua`: `flash.nvim` 适配层
- `lua/flash_zh/pinyin.lua`: 拼音匹配核心
- `lua/flash_zh/data/`: 生成后的数据文件
- `scripts/generate-pinyin-data.mjs`: 数据生成脚本
