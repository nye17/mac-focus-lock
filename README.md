# Focus Lock

If your pointer could drift out of your work window to some other more entertaining windows (chatgpt dialog or some random youtube history channel), this is the tool for you. It will lock your focus on one particular window for as long as you wish and block your clicks anywhere else.


This is a concentration tool that uses Hammerspoon to confine your pointer...


For my application scenario, I want to work on my vim latex window while watching the skim viewer refreshing the pdf, and I don't want to do anything else while writing.


mac-focus-lock records the currently focused window and uses a Hammerspoon
`hs.eventtap` as an input gate to lock dat focus.

While locked:

- mouse movement is free;
- Skim remains visible and can keep refreshing;
- scroll events are allowed;
- a mouse click on Skim or any other non-target window is deleted;
- mouse clicks inside the locked Vim/Terminal window work normally;
- common keyboard shortcuts for app/window/Space switching are deleted.

## install

Install Hammerspoon first with

    brew install --cask hammerspoon

then you install mac-focus-lock to your ~/bin history using the installation script

    ./install.sh

finally, load the configuration in Hammerspoon

    Hammerspoon menu -> Reload Config

Verify:

    focus-status

The popup should show:

    4.0-input-gate
    event tap: enabled

## Use (lock for 50 minutes)

    focus-lock 50

manual unlock: 

    focus-unlock

Emergency unlock:

    Ctrl + Option + Cmd + Esc
