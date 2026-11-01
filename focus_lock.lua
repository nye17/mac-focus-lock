-- focus_lock.lua
--
-- Focus Lock: input gate, no refocusing.
--
-- This version NEVER moves the mouse and NEVER tries to refocus/activate
-- a window after the lock starts.
--
-- At lock time it records the currently focused window. While locked:
--   * mouse movement is untouched;
--   * scroll-wheel events are untouched;
--   * mouse clicks outside the target window are deleted;
--   * clicks inside the target window pass through normally;
--   * common keyboard app/window/Space switching shortcuts are deleted;
--   * other windows remain visible and continue updating.
--
-- Emergency unlock: Ctrl+Option+Cmd+Esc

local M = {}
M.VERSION = "FOCUS LOCK V4.0"

local state = {
    active = false,
    targetWindowID = nil,
    targetFrame = nil,
    timer = nil,
    inputTap = nil,
    pendingTimer = nil,
    blockedMouse = {
        left = false,
        right = false,
        other = false,
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
    DOWN   = 125,
    UP     = 126,
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

local function clearState()
    stopTimer(state.timer)
    state.timer = nil

    if state.inputTap then
        pcall(function() state.inputTap:stop() end)
        state.inputTap = nil
    end

    resetMouseState()

    state.active = false
    state.targetWindowID = nil
    state.targetFrame = nil
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

local function windowIDUnderMouse(event)
    -- Prefer the window that can handle the event.
    local ok1, wid1 = pcall(function()
        return event:getProperty(
            P.mouseEventWindowUnderMousePointerThatCanHandleThisEvent
        )
    end)

    if ok1 and wid1 and wid1 ~= 0 then
        return wid1
    end

    -- Fall back to the raw window underneath the pointer.
    local ok2, wid2 = pcall(function()
        return event:getProperty(
            P.mouseEventWindowUnderMousePointer
        )
    end)

    if ok2 and wid2 and wid2 ~= 0 then
        return wid2
    end

    return nil
end

local function clickIsInsideTarget(event)
    local wid = windowIDUnderMouse(event)

    if wid then
        return wid == state.targetWindowID
    end

    -- Defensive fallback if Quartz does not provide a window ID for this
    -- event: use the target frame captured when the lock started.
    local ok, point = pcall(function()
        return event:location()
    end)

    if ok then
        return pointInFrame(point, state.targetFrame)
    end

    -- If we cannot identify the click destination, block it.
    return false
end

local function handleMouseDown(event, button)
    local block = not clickIsInsideTarget(event)
    state.blockedMouse[button] = block
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

local function shouldBlockKey(event)
    local flags = event:getFlags()
    local code = event:getKeyCode()

    -- Emergency unlock must reach hs.hotkey.
    if flags.ctrl
        and flags.alt
        and flags.cmd
        and code == KEY.ESCAPE
    then
        return false
    end

    -- App/window switching.
    if flags.cmd and code == KEY.TAB then
        return true
    end

    if flags.cmd and code == KEY.GRAVE then
        return true
    end

    -- Spotlight.
    if flags.cmd and code == KEY.SPACE then
        return true
    end

    -- Mission Control / App Expose / keyboard Space switching.
    if flags.ctrl and (
        code == KEY.LEFT
        or code == KEY.RIGHT
        or code == KEY.UP
        or code == KEY.DOWN
    ) then
        return true
    end

    return false
end

local function startInputTap()
    local watched = {
        T.keyDown,

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

    -- Trackpad swipe gestures are grouped under "gesture" when exposed.
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

            if etype == T.keyDown then
                return shouldBlockKey(event)
            end

            if T.gesture and etype == T.gesture then
                -- If Hammerspoon exposes this as a swipe, block it so it
                -- cannot switch Spaces. Other gestures pass through.
                local ok, specific = pcall(function()
                    return event:getType(true)
                end)

                if ok and T.swipe and specific == T.swipe then
                    return true
                end

                return false
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

    if not win then
        notify("Focus lock: no focused window", 2.0)
        return
    end

    state.active = true
    state.targetWindowID = win:id()
    state.targetFrame = win:frame()

    resetMouseState()
    startInputTap()

    -- Only a release timer. There is deliberately NO focus watchdog.
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
            "FOCUS INPUT GATE — %g min\n%s\nOutside clicks blocked; pointer free\nEmergency: ⌃⌥⌘ Esc",
            minutes,
            title
        ),
        3.0
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

    if state.active then
        notify(
            "Focus lock: ON\n"
            .. M.VERSION
            .. "\nevent tap: "
            .. tapStatus,
            2.0
        )
        return true
    end

    notify(
        "Focus lock: OFF\n" .. M.VERSION,
        1.8
    )
    return false
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
