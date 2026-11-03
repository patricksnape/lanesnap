-- lanesnap: Hyprland integration for Omarchy. Loaded from ~/.config/hypr/bindings.lua with
--   require("hypr.lanesnap")
-- (the installer adds that line). Everything here is replaced when lanesnap updates; your own
-- changes belong in bindings.lua, after the require.

-- Scrolling layout: keep a lone window at its zone width instead of filling the screen.
hl.config({ scrolling = { fullscreen_on_one_column = false } })

-- Zone overlay (picker and editor) and zones by number.
o.bind("SUPER + Z", "Snap zones overlay", "lanesnap-overlay")
for n = 1, 9 do
  o.bind("CTRL + ALT + " .. n, "Snap window to zone " .. n, "lanesnap-zone " .. n)
end

-- Drag-to-zone: hold SUPER+SHIFT, press the left mouse button on a window, move over a zone,
-- release to snap it. (Plain SUPER + left button stays Omarchy's normal window drag.)
o.bind("SUPER + SHIFT + mouse:272", "Drag window to a snap zone", "lanesnap-drag start")
o.bind("SUPER + SHIFT + mouse:272", nil, "lanesnap-drag drop", { release = true })

-- Flip the current workspace between scrolling (lanesnap) and dwindle.
o.bind("SUPER + SHIFT + Z", "Toggle scrolling / dwindle layout", "lanesnap-layout")

-- Omarchy's SUPER+J (toggle split) only exists in dwindle; this one adapts to the layout.
hl.unbind("SUPER + J")
o.bind("SUPER + J", "Toggle split / stack in column", "lanesnap-split")
