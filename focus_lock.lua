-- focus_lock.lua
--
-- Focus Lock v5: interaction lock.
--
-- Goal:
--   You may LOOK anywhere, including other macOS Spaces, but you may only
--   INTERACT with the one locked window.
--
-- While locked:
--   * mouse pointer movement is unrestricted;
--   * switching Spaces is allowed (trackpad swipe, Ctrl-Left/Right);
--   * vertical scrolling is allowed everywhere (e.g. read a Skim PDF);
--   * clicks are allowed only inside the locked window's CURRENT frame;
--   * when the locked window is on another Space, all clicks are blocked;
--   * horizontal scrolling outside the target is blocked (browser back/forward);
--   * ordinary keyboard input is allowed only while the target window is
--     actually focused; elsewhere it is swallowed;
--   * application/window switching shortcuts and Spotlight are blocked;
--   * no code moves the pointer, refocuses a window, or forces a Space change.
--
-- The window frame is read at event time, so moving/resizing the target is OK.
--
-- Emergency unlock: Ctrl+Option+Cmd+Esc
-- Instant 50-minute lock: Ctrl+Option+Cmd+L
-- Manual unlock: Ctrl+Option+Cmd+U

local M = {}
M.VERSION = "5.0-interaction-lock"

local state = {
    active = false,
    targetWindow = nil,
    targetWindowID = nil,
    deadline = nil,
    timer = nil,
    inputTap = nil,
    pendingTimer = nil,
    blockedMouse = {
        left = false,
        right = false,
        other = false,
    },
    stats = {
        clicks = 0,
        keys = 0,
        horizontalScrolls = 0,
        gestures = 0,
    },
}

local E = hs.eventtap.event
local T = E.types
local P = E.properties

local KEY = {
    TAB    = 48,
    SPACE  = 49,
    GRAVE  = 50,
    ESCAPE = 53,
    LEFT   = 123,
    RIGHT  = 124,
}

local function notify(message, seconds)
    hs.alert.show(message, seconds or 1.5)
end

local function stopTimer(timer)
    if timer then
        pcall(function() timer:stop() end)
    end
end

local function resetMouseState()
    state.blockedMouse.left = false
    state.blockedMouse.right = false
    state.blockedMouse.other = false
end

local function resetStats()
    state.stats.clicks = 0
    state.stats.keys = 0
    state.stats.horizontalScrolls = 0
    state.stats.gestures = 0
end

local function clearState()
    stopTimer(state.timer)
    state.timer = nil

    if state.inputTap then
        pcall(function() state.inputTap:stop() end)
        state.inputTap = nil
    end

    resetMouseState()

    state.active = false
    state.targetWindow = nil
    state.targetWindowID = nil
    state.deadline = nil
end

function M.unlock(reason)
    if state.pendingTimer then
        stopTimer(state.pendingTimer)
        state.pendingTimer = nil
    end

    if not state.active then
        notify("Focus lock: not active")
        return
    end

    clearState()

    if reason and reason ~= "" then
        notify("Focus lock released\n" .. reason, 1.8)
    else
        notify("Focus lock released", 1.5)
    end
end

local function targetWindowStillValid()
    if not state.targetWindow or not state.targetWindowID then
        return false
    end

    local ok, windowID = pcall(function()
        return state.targetWindow:id()
    end)

    return ok and windowID == state.targetWindowID
end

local function targetFrame()
    if not targetWindowStillValid() then
        return nil
    end

    local ok, frame = pcall(function()
        return state.targetWindow:frame()
    end)

    if ok then
        return frame
    end

    return nil
end

local function targetIsOnActiveSpace()
    if not targetWindowStillValid() then
        return false
    end

    -- Ask hs.spaces rather than relying on screen coordinates. This prevents
    -- a click on another Space from being allowed merely because it happens
    -- to occupy the same coordinates as the locked window.
    local okSpaces, spaces = pcall(function()
        return hs.spaces.windowSpaces(state.targetWindowID)
    end)

    local okScreen, screen = pcall(function()
        return state.targetWindow:screen()
    end)

    if not okSpaces or not spaces or not okScreen or not screen then
        -- Fail closed. If Spaces information is unavailable, the only safe
        -- fallback is to treat the target as non-interactive.
        return false
    end

    local okActive, activeSpace = pcall(function()
        return hs.spaces.activeSpaceOnScreen(screen)
    end)

    if not okActive or not activeSpace then
        return false
    end

    for _, spaceID in ipairs(spaces) do
        if spaceID == activeSpace then
            return true
        end
    end

    return false
end

local function pointInFrame(point, frame)
    if not point or not frame then
        return false
    end

    return (
        point.x >= frame.x
        and point.x < frame.x + frame.w
        and point.y >= frame.y
        and point.y < frame.y + frame.h
    )
end

local function pointerIsInsideInteractiveTarget(event)
    if not targetIsOnActiveSpace() then
        return false
    end

    local frame = targetFrame()
    if not frame then
        return false
    end

    local ok, point = pcall(function()
        return event:location()
    end)

    if not ok or not point then
        return false
    end

    return pointInFrame(point, frame)
end

local function targetHasKeyboardFocus()
    if not targetIsOnActiveSpace() then
        return false
    end

    local ok, focused = pcall(function()
        return hs.window.focusedWindow()
    end)

    if not ok or not focused then
        return false
    end

    local okID, focusedID = pcall(function()
        return focused:id()
    end)

    return okID and focusedID == state.targetWindowID
end

local function scheduleUnlockIfTargetGone()
    if targetWindowStillValid() then
        return false
    end

    -- Do not mutate/stop the eventtap from inside its own callback. Schedule
    -- cleanup for immediately after the current event returns.
    hs.timer.doAfter(0, function()
        if state.active then
            M.unlock("target window closed")
        end
    end)

    return true
end

local function allowSpaceSwitchKey(event)
    local flags = event:getFlags()
    local code = event:getKeyCode()

    -- Native keyboard Space switching. Ctrl-Up/Down are intentionally not
    -- included: Mission Control can be opened with system gestures/keys, but
    -- selection clicks remain blocked by the interaction lock.
    return flags.ctrl
        and not flags.cmd
        and not flags.alt
        and (code == KEY.LEFT or code == KEY.RIGHT)
end

local function isEmergencyUnlock(event)
    local flags = event:getFlags()
    local code = event:getKeyCode()

    return flags.ctrl
        and flags.alt
        and flags.cmd
        and code == KEY.ESCAPE
end

local function globallyBlockedShortcut(event)
    local flags = event:getFlags()
    local code = event:getKeyCode()

    -- Application/window switching and Spotlight can create an interactive
    -- surface without leaving the current Space, so block them even while the
    -- target has keyboard focus.
    if flags.cmd and code == KEY.TAB then
        return true
    end

    if flags.cmd and code == KEY.GRAVE then
        return true
    end

    if flags.cmd and code == KEY.SPACE then
        return true
    end

    return false
end

local function handleKeyEvent(event)
    if scheduleUnlockIfTargetGone() then
        return true
    end

    if isEmergencyUnlock(event) then
        if event:getType() == T.keyDown then
            hs.timer.doAfter(0, function()
                if state.active then
                    M.unlock("emergency unlock")
                end
            end)
        end
        return true
    end

    if allowSpaceSwitchKey(event) then
        return false
    end

    if globallyBlockedShortcut(event) then
        state.stats.keys = state.stats.keys + 1
        return true
    end

    -- Ordinary keys are usable only when the locked target really owns
    -- keyboard focus. On Firefox/Skim/another Space, Cmd-T, typing, Return,
    -- shortcuts, etc. never reach that application.
    if not targetHasKeyboardFocus() then
        state.stats.keys = state.stats.keys + 1
        return true
    end

    return false
end

local function handleMouseDown(event, button)
    if scheduleUnlockIfTargetGone() then
        state.blockedMouse[button] = true
        return true
    end

    local block = not pointerIsInsideInteractiveTarget(event)
    state.blockedMouse[button] = block

    if block then
        state.stats.clicks = state.stats.clicks + 1
    end

    return block
end

local function handleMouseEvent(event)
    local etype = event:getType()

    if etype == T.leftMouseDown then
        return handleMouseDown(event, "left")

    elseif etype == T.leftMouseDragged then
        return state.blockedMouse.left

    elseif etype == T.leftMouseUp then
        local block = state.blockedMouse.left
        state.blockedMouse.left = false
        return block

    elseif etype == T.rightMouseDown then
        return handleMouseDown(event, "right")

    elseif etype == T.rightMouseDragged then
        return state.blockedMouse.right

    elseif etype == T.rightMouseUp then
        local block = state.blockedMouse.right
        state.blockedMouse.right = false
        return block

    elseif etype == T.otherMouseDown then
        return handleMouseDown(event, "other")

    elseif etype == T.otherMouseDragged then
        return state.blockedMouse.other

    elseif etype == T.otherMouseUp then
        local block = state.blockedMouse.other
        state.blockedMouse.other = false
        return block
    end

    return false
end

local function scrollDelta(event, property)
    local ok, value = pcall(function()
        return event:getProperty(property)
    end)

    if ok and value then
        return value
    end

    return 0
end

local function handleScrollEvent(event)
    if scheduleUnlockIfTargetGone() then
        return true
    end

    -- Inside the target, normal scrolling (including horizontal) is allowed.
    if pointerIsInsideInteractiveTarget(event) then
        return false
    end

    -- Outside the target, preserve vertical reading/scrolling but suppress a
    -- deliberate horizontal gesture. Firefox/Safari use horizontal trackpad
    -- scrolls for history navigation. Small horizontal jitter during a mostly
    -- vertical scroll is tolerated.
    local vertical = scrollDelta(event, P.scrollWheelEventPointDeltaAxis1)
    local horizontal = scrollDelta(event, P.scrollWheelEventPointDeltaAxis2)

    -- Some devices populate integer deltas more reliably than point deltas.
    if vertical == 0 and horizontal == 0 then
        vertical = scrollDelta(event, P.scrollWheelEventDeltaAxis1)
        horizontal = scrollDelta(event, P.scrollWheelEventDeltaAxis2)
    end

    local av = math.abs(vertical)
    local ah = math.abs(horizontal)

    if ah > 0 and ah >= math.max(2, av * 0.75) then
        state.stats.horizontalScrolls = state.stats.horizontalScrolls + 1
        return true
    end

    return false
end

local function handleGestureEvent(event)
    if scheduleUnlockIfTargetGone() then
        return true
    end

    if pointerIsInsideInteractiveTarget(event) then
        return false
    end

    local ok, specific = pcall(function()
        return event:getType(true)
    end)

    if not ok then
        -- Unknown gesture: do not risk blocking a system Space swipe.
        return false
    end

    -- Explicit swipe gestures are allowed so Space switching remains usable.
    if T.swipe and specific == T.swipe then
        return false
    end

    -- Outside the target, block application-level gestures that can change
    -- state (smart zoom, pinch, rotate, pressure/force-click). Generic touch
    -- events are allowed because normal scrolling may accompany them.
    local block = false

    if T.magnify and specific == T.magnify then
        block = true
    elseif T.smartMagnify and specific == T.smartMagnify then
        block = true
    elseif T.rotate and specific == T.rotate then
        block = true
    elseif T.pressure and specific == T.pressure then
        block = true
    end

    if block then
        state.stats.gestures = state.stats.gestures + 1
    end

    return block
end

local function startInputTap()
    local watched = {
        T.keyDown,
        T.keyUp,
        T.scrollWheel,

        T.leftMouseDown,
        T.leftMouseDragged,
        T.leftMouseUp,

        T.rightMouseDown,
        T.rightMouseDragged,
        T.rightMouseUp,

        T.otherMouseDown,
        T.otherMouseDragged,
        T.otherMouseUp,
    }

    if T.gesture then
        table.insert(watched, T.gesture)
    end

    state.inputTap = hs.eventtap.new(
        watched,
        function(event)
            if not state.active then
                return false
            end

            local etype = event:getType()

            if etype == T.keyDown or etype == T.keyUp then
                return handleKeyEvent(event)
            end

            if etype == T.scrollWheel then
                return handleScrollEvent(event)
            end

            if T.gesture and etype == T.gesture then
                return handleGestureEvent(event)
            end

            return handleMouseEvent(event)
        end
    )

    state.inputTap:start()
end

function M.lock(minutes)
    minutes = tonumber(minutes) or 50

    if minutes <= 0 then
        notify("Focus lock: minutes must be > 0", 2.0)
        return
    end

    if state.active then
        M.unlock("restarting")
    end

    local win = hs.window.focusedWindow()

    if not win or not win:id() then
        notify("Focus lock: no focused window", 2.0)
        return
    end

    state.active = true
    state.targetWindow = win
    state.targetWindowID = win:id()
    state.deadline = hs.timer.secondsSinceEpoch() + minutes * 60

    resetMouseState()
    resetStats()
    startInputTap()

    -- Release timer only. There is deliberately NO watchdog/refocus loop.
    state.timer = hs.timer.doAfter(
        minutes * 60,
        function()
            M.unlock("timer finished")
        end
    )

    local app = win:application()
    local title = win:title()

    if not title or title == "" then
        title = app and app:name() or "target window"
    end

    notify(
        string.format(
            "INTERACTION LOCK — %g min\n%s\nLook/scroll anywhere; interact only here\nEmergency: ⌃⌥⌘ Esc",
            minutes,
            title
        ),
        3.2
    )
end

function M.requestLock(minutes, delaySeconds)
    minutes = tonumber(minutes) or 50
    delaySeconds = tonumber(delaySeconds) or 0

    if state.pendingTimer then
        stopTimer(state.pendingTimer)
        state.pendingTimer = nil
    end

    if delaySeconds <= 0 then
        M.lock(minutes)
        return
    end

    notify(
        string.format(
            "Focus lock in %g sec\nClick the target window now",
            delaySeconds
        ),
        math.min(delaySeconds, 3.0)
    )

    state.pendingTimer = hs.timer.doAfter(
        delaySeconds,
        function()
            state.pendingTimer = nil
            M.lock(minutes)
        end
    )
end

function M.status()
    local tapStatus = "none"

    if state.inputTap then
        local ok, enabled = pcall(function()
            return state.inputTap:isEnabled()
        end)
        if ok then
            tapStatus = enabled and "enabled" or "DISABLED"
        end
    end

    if not state.active then
        notify(
            "Focus lock: OFF\n" .. M.VERSION,
            1.8
        )
        return false
    end

    local remaining = math.max(
        0,
        (state.deadline or hs.timer.secondsSinceEpoch())
            - hs.timer.secondsSinceEpoch()
    )

    local targetSpace = targetIsOnActiveSpace() and "active" or "other Space"
    local focus = targetHasKeyboardFocus() and "target focused" or "keyboard gated"

    notify(
        string.format(
            "Focus lock: ON — %.1f min\n%s | tap: %s\n%s, %s\nBlocked: %d clicks, %d keys, %d h-scrolls, %d gestures",
            remaining / 60,
            M.VERSION,
            tapStatus,
            targetSpace,
            focus,
            state.stats.clicks,
            state.stats.keys,
            state.stats.horizontalScrolls,
            state.stats.gestures
        ),
        3.5
    )

    return true
end

hs.urlevent.bind("focus-lock", function(_, params)
    local minutes = tonumber(params.minutes) or 50
    local delay = tonumber(params.delay) or 4
    M.requestLock(minutes, delay)
end)

hs.urlevent.bind("focus-unlock", function()
    M.unlock("manual")
end)

hs.urlevent.bind("focus-status", function()
    M.status()
end)

hs.hotkey.bind(
    {"ctrl", "alt", "cmd"},
    "escape",
    function()
        M.unlock("emergency unlock")
    end
)

hs.hotkey.bind(
    {"ctrl", "alt", "cmd"},
    "L",
    function()
        M.lock(50)
    end
)

hs.hotkey.bind(
    {"ctrl", "alt", "cmd"},
    "U",
    function()
        M.unlock("manual")
    end
)

return M
