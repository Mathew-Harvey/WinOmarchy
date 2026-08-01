-- Written by the Winmarchy theme engine. Do not edit by hand; this file is
-- overwritten on every theme change. Pattern ported verbatim from Omarchy's
-- per-theme neovim.lua (ref/omarchy/themes/tokyo-night/neovim.lua): a lazy.nvim
-- spec declaring the colourscheme plugin at priority 1000 and setting the
-- LazyVim colorscheme option.
return {
  {
    {{nvim_plugin_spec}},
    priority = 1000,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "{{nvim_colorscheme}}",
    },
  },
}
