# Focus Lock v5 — interaction lock

This version implements a different policy from v4:

> **You may look anywhere, but you may interact only with the locked window.**

## While locked

| Action | Locked window | Other window, same Space | Other Space |
|---|---:|---:|---:|
| Move pointer | yes | yes | yes |
| Left/right/middle click | yes | **blocked** | **blocked** |
| Type / app keyboard shortcuts | yes | **blocked** | **blocked** |
| Vertical scroll | yes | yes | yes |
| Horizontal browser-navigation scroll | yes | **blocked** | **blocked** |
| Space swipe | yes | yes | yes |
| Ctrl-Left / Ctrl-Right Space switching | yes | yes | yes |
| Pinch / smart zoom / rotate outside target | — | **blocked** | **blocked** |

This means you can switch to a Space containing Skim, move the pointer over the PDF,
and scroll through it. You cannot click Skim. You can switch to a Space containing
Firefox and scroll a page, but you cannot click links, middle-click to open a tab,
use Cmd-T, type into the browser, or use horizontal trackpad history navigation.

## Dynamic resize/move

The clickable region is **not cached**. Every attempted click reads the locked
window's current `win:frame()`. If you resize or move the target window, its allowed
interaction rectangle follows immediately.

## Space awareness

v5 also checks `hs.spaces.windowSpaces()` against `hs.spaces.activeSpaceOnScreen()`.
If the locked window is on Desktop 1 while you are looking at Desktop 2, all clicks
are blocked even if the pointer happens to occupy the same screen coordinates as
the target window on Desktop 1.

v5 never moves your mouse, calls `window:focus()`, activates an application, or
forces you back to a Space.

## Install / upgrade

```bash
./install.sh
```

Then:

```text
Hammerspoon menu -> Reload Config
```

Verify:

```bash
focus-status
```

The popup should contain:

```text
5.0-interaction-lock
```

Use:

```bash
focus-lock 50
```

The second optional argument is the countdown before locking:

```bash
focus-lock 50 6
```

## Emergency unlock

```text
Ctrl + Option + Cmd + Esc
```

Manual unlock from the shell:

```bash
focus-unlock
```

## Diagnostics

`focus-status` reports whether the event tap is enabled and counts blocked clicks,
keys, deliberate horizontal scrolls, and application-level gestures.

If Firefox still reacts to an ordinary click while the status says zero blocked
clicks, macOS/Hammerspoon is not delivering that click to the event tap. Check:

```text
System Settings
  -> Privacy & Security
  -> Accessibility
  -> Hammerspoon
```

and, if present on your macOS version:

```text
System Settings
  -> Privacy & Security
  -> Input Monitoring
  -> Hammerspoon
```

Then restart Hammerspoon and reload its config.

## Deliberate limitation

Clicking Mission Control/Desktop thumbnails is blocked because those are clicks
outside the target. Switch Spaces using a trackpad Space swipe or Ctrl-Left/Right.
This avoids creating a special exception that would also allow clicking arbitrary
windows in Mission Control.

This is a concentration aid, not a security boundary.
