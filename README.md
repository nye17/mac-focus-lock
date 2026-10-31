# Focus Lock 4.0 — input gate

This version removes the refocus watchdog completely.

It NEVER:

- moves the mouse pointer;
- calls `window:focus()` after the lock starts;
- calls `application:activate()`;
- hides or minimizes other windows;
- moves or resizes windows.

Instead, it records the currently focused window and uses a Hammerspoon
`hs.eventtap` as an input gate.

While locked:

- mouse movement is free;
- Skim remains visible and can keep refreshing;
- scroll events are allowed;
- a mouse click on Skim or any other non-target window is deleted;
- mouse clicks inside the locked Vim/Terminal window work normally;
- common keyboard shortcuts for app/window/Space switching are deleted.

There is no code that can "snap" the pointer back to the target window.

## Upgrade

    ./install.sh

Then:

    Hammerspoon menu -> Reload Config

Verify:

    focus-status

The popup should show:

    4.0-input-gate
    event tap: enabled

## Use

    focus-lock 50

Emergency unlock:

    Ctrl + Option + Cmd + Esc

## If an outside click still changes focus

Run:

    focus-status

If it says:

    event tap: DISABLED

then macOS has disabled the event tap or Hammerspoon lacks the required
Accessibility/Input Monitoring permission. Check:

    System Settings
      -> Privacy & Security
      -> Accessibility
      -> Hammerspoon

and, on macOS versions that expose it:

    System Settings
      -> Privacy & Security
      -> Input Monitoring
      -> Hammerspoon

Then restart Hammerspoon and reload the config.

This is a concentration tool, not a security boundary.
