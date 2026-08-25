-- omarchy-applemusicplayer:start
-- Chromium's dedicated app id makes this rule independent of page titles.
o.window("^chrome-mini\\.applemusic\\.localhost__mini-Default$", {
  float = true,
  center = true,
  size = { 560, 720 },
  workspace = "special:applemusic silent",
  tag = "-default-opacity",
  opacity = "1 1",
})
-- omarchy-applemusicplayer:end
