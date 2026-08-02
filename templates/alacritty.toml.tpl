# Winmarchy Alacritty configuration, written when Omarchy mode is entered and
# removed again on the way back to Windows 11. Do not edit by hand; it is
# regenerated on every theme change.
#
# The colour mapping is ported verbatim from Omarchy's own
# default/themed/alacritty.toml.tpl (see ref/omarchy). Omarchy derives
# selection_background from selection and selection_foreground from
# bright_foreground, so those two are substituted directly here.

[window]
padding = { x = 10, y = 10 }
decorations = "none"
opacity = 1.0
dynamic_title = true

[font]
size = 11
normal = { family = "JetBrainsMono Nerd Font", style = "Regular" }
bold = { family = "JetBrainsMono Nerd Font", style = "Bold" }
italic = { family = "JetBrainsMono Nerd Font", style = "Italic" }

[colors.primary]
background = "{{background}}"
foreground = "{{foreground}}"

[colors.cursor]
text = "{{background}}"
cursor = "{{bright_foreground}}"

[colors.vi_mode_cursor]
text = "{{background}}"
cursor = "{{bright_foreground}}"

[colors.search.matches]
foreground = "{{background}}"
background = "{{yellow}}"

[colors.search.focused_match]
foreground = "{{background}}"
background = "{{red}}"

[colors.footer_bar]
foreground = "{{background}}"
background = "{{foreground}}"

[colors.selection]
text = "{{bright_foreground}}"
background = "{{selection}}"

[colors.normal]
black = "{{background}}"
red = "{{red}}"
green = "{{green}}"
yellow = "{{yellow}}"
blue = "{{blue}}"
magenta = "{{magenta}}"
cyan = "{{cyan}}"
white = "{{foreground}}"

[colors.bright]
black = "{{muted}}"
red = "{{bright_red}}"
green = "{{bright_green}}"
yellow = "{{bright_yellow}}"
blue = "{{bright_blue}}"
magenta = "{{bright_magenta}}"
cyan = "{{bright_cyan}}"
white = "{{bright_foreground}}"
