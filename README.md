# YearWallpaper

A macOS wallpaper that shows your year as a grid of pixels — one cell per day, filled in as the year passes. Today's cell glows at half brightness. Past days are solid white. The rest is dark.

There's a small label in the top margin with the year on the left and the days remaining on the right.

```
2026                                                    54 days left

▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪     January
▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪▪        February
...
```

Rows are months, January at the top. Columns are days within the month. Short months leave their row ragged rather than padding with fake days, so the shape of the grid tells you the length of each month.

## Requirements

macOS and Apple's Command Line Tools (`xcode-select --install`). No Xcode, no dependencies, no network access. The whole program is one 158-line Swift file that draws with AppKit and CoreText.

## Build

```sh
./scripts/build.sh
```

This compiles `Sources/YearWallpaper.swift` to `bin/YearWallpaper` and prints a preview to `/tmp/year-wallpaper-preview.png` so you can see what it looks like before touching your desktop.

`build.sh` lives in `scripts/`; run it from the repo root or anywhere else, it resolves its own path.

## Run once

```sh
bin/YearWallpaper
```

This renders the current state of the year once per attached display, at that display's native pixel resolution, writes each PNG to `~/Library/Application Support/YearWallpaper/`, and sets it as the desktop picture. Run it again tomorrow and you get tomorrow's grid.

The program keeps the last 6 PNGs and deletes anything older. That's deliberate: if a display is mid-refresh when the old file disappears, you'd get a black or missing wallpaper. Six days of slack means the file the system is still holding always exists.

## Run daily (optional)

The binary has no scheduler inside it — it does one render and exits. If you want the wallpaper to actually advance each day, install the LaunchAgent:

```sh
./scripts/install-launchagent.sh          # daily at 00:05
./scripts/install-launchagent.sh 09:30    # daily at 09:30
```

This writes `~/Library/LaunchAgents/com.shivampwm2020.yearwallpaper.plist` and loads it. `RunAtLoad` is set, so it also fires once immediately as a smoke test. Because that first run happens inside the installer, the script warns you beforehand — if macOS asks for permission to change your desktop picture, allow it then. If your wallpaper changes within a few seconds, it's working.

If your Mac is asleep at the scheduled minute, launchd runs the job shortly after it wakes rather than skipping the day. Note that `StartCalendarInterval` in local time means a machine travelling across timezones will fire at the new local time.

To remove it:

```sh
./scripts/install-launchagent.sh --uninstall
```

That unloads the job and deletes the plist. Your current wallpaper stays where it is — it just stops changing.

Check it's registered and see when it last ran:

```sh
launchctl list | grep yearwallpaper
```

The exit code in the second column is `0` on success. Logs go to `/tmp/year-wallpaper.out.log` and `/tmp/year-wallpaper.err.log`.

## Preview without applying

```sh
bin/YearWallpaper --preview out.png                     # defaults to 3840x2160
bin/YearWallpaper --preview out.png --size 1920x1080
```

Useful for checking what a 4K render looks like from a laptop, or for generating the image to use somewhere other than your desktop.

## How it works

The interesting part is the geometry. The grid is sized so that its total width is 90% of the image width, then a cell size is solved for from that constraint and the number of days in the longest month:

```swift
let cell = gridWidth / (CGFloat(maxColumns) + CGFloat(maxColumns - 1) * gapFraction)
```

The gaps between cells are expressed as a fraction of the cell size (0.22), not as an absolute measurement, so the whole grid scales cleanly from a 1440p panel to a 5K one without the gutters looking wrong at either end. The grid is then centred by computing `left` and `top` offsets from the image bounds.

Each cell is a rounded rectangle with a corner radius of 6% of the cell size. Fills are: white for past days, white at 45% alpha for today, and grey 0.086 for future days — just enough to read as a cell against the black rather than a hole.

Rendering happens into a `CGContext` sized to `screen.frame * screen.backingScaleFactor`, which is why the output is pixel-perfect on Retina displays instead of being a 1x image upscaled.

The label font size is derived from the cell size (`cell * 0.62`), so the text stays proportional to the grid at any resolution.

## Layout

```
Sources/YearWallpaper.swift            the whole program
scripts/build.sh                       compile to bin/
scripts/install-launchagent.sh         daily schedule, install or uninstall
PUBLISH.sh                             create the private GitHub repo and push
```

Generated files — `bin/`, and the PNGs in `~/Library/Application Support/YearWallpaper/` — are not tracked by git.

## Troubleshooting

**`swiftc not found`** — run `xcode-select --install` and accept the prompt. It's about a 2 GB download but you don't need full Xcode.

**Wallpaper doesn't change when the job runs** — check `/tmp/year-wallpaper.err.log`. Under macOS 14+ a background agent may need permission to control your desktop; if prompted, allow it in System Settings → Privacy & Security.

**It only updates when you log in** — that's expected. LaunchAgents run in your GUI session, which only exists while you're logged in. If the Mac is at the login window, nothing fires. That's fine for a wallpaper, but worth knowing if you were expecting it to update on a headless machine.

**Multiple displays** — each screen gets its own PNG, suffixed with the screen index. Sizes are computed per-screen, so a laptop plus an external monitor at different resolutions both come out sharp.

## License

MIT — see [LICENSE](LICENSE).
