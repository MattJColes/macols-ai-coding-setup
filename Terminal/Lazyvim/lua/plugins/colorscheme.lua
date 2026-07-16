return {
  {
    "Shatur/neovim-ayu",
    lazy = false,
    priority = 1000,
    opts = {
      overrides = {},
    },
    config = function()
      require("ayu").setup({ mirage = false })
      vim.cmd("colorscheme ayu-dark")
    end,
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "ayu-dark" } },
}
