--[[
    TSB DELTA v37 | MOTION CORE EDITION
    Keeps the v33/v34 controls without their overlapping movement/render loops.
    Local-only client script (executor with loadstring + HttpGet for external modules).
    Teleport, damage, and actual invisibility are subject to server authority.
    EXTERNAL SOURCES ARE USER-SUPPLIED AND NOT TRUST-VERIFIED.
]]

-- ==== BOOT / RE-EXECUTION ================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local CoreGui = game:GetService("CoreGui")
local Stats = game:GetService("Stats")
local StarterGui = game:GetService("StarterGui")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then return end

local env
pcall(function() if type(getgenv) == "function" then env = getgenv() end end)
if type(env) ~= "table" then env = _G end
for _, k in ipairs({"__TSB_DELTA_V37_SHUTDOWN", "__TSB_DELTA_V36_SHUTDOWN", "__TSB_DELTA_V35_SHUTDOWN", "__TSB_DELTA_V34_SHUTDOWN", "__TSB_DELTA_V33_SHUTDOWN",
    "__TSB_DELTA_V32_SHUTDOWN", "__TSB_DELTA_V31_SHUTDOWN", "__TSB_DELTA_V30_SHUTDOWN",
    "__TSB_DELTA_V29_SHUTDOWN", "__TSB_DELTA_V28_SHUTDOWN", "__TSB_DELTA_V27_SHUTDOWN",
    "__TSB_DELTA_V26_SHUTDOWN", "__TSB_DELTA_V25_SHUTDOWN", "__TSB_DELTA_V24_SHUTDOWN"}) do
    local old = rawget(env, k)
    if type(old) == "function" then pcall(old) end
end
-- Old versions could die during initialization before registering shutdown.
-- Remove their named render callbacks even when their UI was orphaned.
for _, suffix in ipairs({"V33", "V32", "V31", "V30", "V29", "V28", "V27", "V26"}) do
    for _, mode in ipairs({"AIM", "MOVE", "FOLLOW"}) do
        pcall(function() RunService:UnbindFromRenderStep("TSB_DELTA_" .. mode .. "_" .. suffix) end)
    end
end
-- If a previous build crashed before installing its cleanup callback,
-- still clear all known bindings before registering this build.
for _, ver in ipairs({"v35", "v36", "v37"}) do
    pcall(function() RunService:UnbindFromRenderStep("TSB_DELTA_" .. ver .. "_Follow") end)
    pcall(function() RunService:UnbindFromRenderStep("TSB_DELTA_" .. ver .. "_Aim") end)
end
-- (Already cleared by the loop above.)
local clean = {alive = true, connections = {}, instances = {}, bindings = {}, timers = {}}
function clean:connect(signal, callback)
    local c = signal:Connect(callback)
    self.connections[#self.connections + 1] = c
    return c
end
function clean:bind(name, priority, callback)
    pcall(function() RunService:UnbindFromRenderStep(name) end)
    RunService:BindToRenderStep(name, priority, callback)
    self.bindings[name] = true
end
function clean:unbind(name)
    if self.bindings[name] then
        pcall(function() RunService:UnbindFromRenderStep(name) end)
        self.bindings[name] = nil
    end
end
function clean:own(instance)
    self.instances[#self.instances + 1] = instance
    return instance
end

local SET = {
    distance = 3.0, aim = false, lead = true, ss = false,
    speed = false, speedValue = 42, safe = false, safeThreshold = 30,
    reset = false, wall = false, fps = false, culling = false, radius = 160,
}
local state = {
    target = nil, follow = false, resumeFollow = false, aimTarget = nil,
    safeActive = false, safeReturn = nil, safePart = nil,
    coordinate = false, coordReturn = nil, coordPart = nil,
    lastError = "", resetBusy = false, tpCount = 0,
}
local UI = {}
local C = {
    bg = Color3.fromRGB(12, 18, 32), panel = Color3.fromRGB(20, 31, 49),
    button = Color3.fromRGB(34, 50, 76), blue = Color3.fromRGB(30, 125, 190),
    green = Color3.fromRGB(20, 139, 111), red = Color3.fromRGB(152, 48, 80),
    white = Color3.fromRGB(236, 244, 253), muted = Color3.fromRGB(159, 186, 214),
    orange = Color3.fromRGB(247, 175, 113),
}
local function getChar(plr)
    plr = plr or LocalPlayer
    if not plr or plr.Parent ~= Players then return end
    local char = plr.Character
    if not char or not char.Parent then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root or not hum or hum.Health <= 0 then return end
    return char, hum, root
end
local function finite(v)
    return v == v and math.abs(v) < 1000000
end
local function validPos(p)
    return p and finite(p.X) and finite(p.Y) and finite(p.Z)
        and p.Y > workspace.FallenPartsDestroyHeight + 10
end
local function status(text, severity)
    if not clean.alive then return end
    state.lastError = severity == "error" and text or state.lastError
    if UI.status then
        UI.status.Text = tostring(text):sub(1, 240)
        UI.status.TextColor3 = severity == "error" and C.orange or (severity == "ok" and Color3.fromRGB(137, 241, 193) or C.muted)
    end
end
local function toggleLook(button, title, on)
    if not button then return end
    button.Text = title .. ": " .. (on and "ON" or "OFF")
    button.BackgroundColor3 = on and C.green or C.red
end
local function notify(text)
    pcall(function()
        StarterGui:SetCore("SendNotification", {Title = "TSB DELTA v37", Text = tostring(text):sub(1, 160), Duration = 5})
    end)
end

-- ==== UI BUILD (ONE INSTANCE / ONE SHUTDOWN) =============================
local uiParent
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok and result then uiParent = result end
end
if not uiParent then
    local ok = pcall(function() return CoreGui:GetChildren() end)
    if ok then uiParent = CoreGui end
end
if not uiParent then uiParent = LocalPlayer:FindFirstChildOfClass("PlayerGui") or LocalPlayer:WaitForChild("PlayerGui", 8) end
if not uiParent then error("TSB v37: UI parent unavailable") end
for _, rootGui in ipairs({CoreGui, LocalPlayer:FindFirstChildOfClass("PlayerGui"), uiParent}) do
    if rootGui then
        pcall(function()
            for _, obj in ipairs(rootGui:GetChildren()) do
                if obj:IsA("ScreenGui") and (obj.Name:match("^TSB_DELTA_v%d+$")
                    or obj.Name:match("^TSB_Delta_V%d+$") or obj.Name == "TSB_Delta_Clean") then
                    obj:Destroy()
                end
            end
        end)
    end
end
local gui = clean:own(Instance.new("ScreenGui"))
gui.Name = "TSB_DELTA_v37"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 153
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = uiParent
local cam = workspace.CurrentCamera
local view = cam and cam.ViewportSize or Vector2.new(430, 780)
-- Compact profile: maximum 305 px wide, height constrained by available viewport.
local W = math.clamp(view.X - 24, 218, 294)
local H = math.clamp(view.Y - 35, 295, 460)
local function create(class, parent, props)
    local o = Instance.new(class)
    for key, val in pairs(props or {}) do o[key] = val end
    o.Parent = parent
    return o
end
local function corner(obj, radius)
    create("UICorner", obj, {CornerRadius = UDim.new(0, radius or 8)})
    return obj
end
local function button(parent, text, y, height, color)
    local o = create("TextButton", parent, {
        Size = UDim2.new(1, -16, 0, height or 35), Position = UDim2.fromOffset(8, y),
        Text = text, TextSize = 12, Font = Enum.Font.GothamBold,
        TextColor3 = C.white, BackgroundColor3 = color or C.button,
        BorderSizePixel = 0, AutoButtonColor = true,
    })
    corner(o, 7)
    return o
end
local function label(parent, text, y, height, fontSize)
    return create("TextLabel", parent, {
        Position = UDim2.fromOffset(8, y), Size = UDim2.new(1, -16, 0, height or 38),
        BackgroundTransparency = 1, Text = text, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
        Font = Enum.Font.Gotham, TextSize = fontSize or 11, TextColor3 = C.muted,
    })
end
local function input(parent, val, y, placeholder)
    local o = create("TextBox", parent, {
        Position = UDim2.new(0.53, 0, 0, y), Size = UDim2.new(0.47, -8, 0, 33),
        BackgroundColor3 = C.button, BorderSizePixel = 0, Text = tostring(val),
        PlaceholderText = placeholder or "", ClearTextOnFocus = false,
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = C.white,
    })
    corner(o, 6)
    return o
end
local frame = create("Frame", gui, {
    Name = "Panel", Size = UDim2.fromOffset(W, H),
    Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
    BackgroundColor3 = C.bg, BorderSizePixel = 0,
    ClipsDescendants = true, Active = true,
})
corner(frame, 12)
create("UIStroke", frame, {Color = Color3.fromRGB(52, 109, 155), Thickness = 1.2})
local titlebar = create("Frame", frame, {
    Name = "TitleBar", Size = UDim2.new(1, 0, 0, 37),
    BackgroundColor3 = Color3.fromRGB(20, 48, 78), BorderSizePixel = 0,
    Active = true,
})
create("UIGradient", titlebar, {
    Color = ColorSequence.new(Color3.fromRGB(23, 62, 100), Color3.fromRGB(16, 39, 65)),
    Rotation = 0,
})
local title = label(titlebar, "⠿  TSB DELTA  /  v37", 0, 37, 12)
title.Position = UDim2.fromOffset(10, 0)
title.Size = UDim2.new(1, -87, 0, 37)
title.TextColor3 = Color3.fromRGB(162, 235, 254)
title.Font = Enum.Font.GothamBold
title.Active = true
local closeBtn = button(titlebar, "×", 3, 30, C.red)
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.Position = UDim2.new(1, -34, 0, 3)
closeBtn.TextSize = 18
local miniBtn = button(titlebar, "−", 3, 30, C.button)
miniBtn.Size = UDim2.fromOffset(30, 30)
miniBtn.Position = UDim2.new(1, -68, 0, 3)
miniBtn.TextSize = 18
UI.status = label(frame, "Цель не выбрана • перетащи за шапку", 39, 25, 10)
UI.status.TextTruncate = Enum.TextTruncate.AtEnd
UI.status.TextWrapped = false
local tabs = create("Frame", frame, {
    Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 67),
    BackgroundTransparency = 1,
})
local host = create("Frame", frame, {
    Size = UDim2.new(1, -16, 1, -107), Position = UDim2.fromOffset(8, 102),
    BackgroundTransparency = 1, ClipsDescendants = true,
})
local pages, tabsBtns = {}, {}
for i, name in ipairs({"ЦЕЛЬ", "ФУНКЦИИ", "ДОП."}) do
    local tb = create("TextButton", tabs, {
        Position = UDim2.new((i-1)/3, 2, 0, 0), Size = UDim2.new(1/3, -5, 1, 0),
        BackgroundColor3 = C.button, BorderSizePixel = 0, Text = name,
        TextColor3 = C.white, Font = Enum.Font.GothamBold, TextSize = 10,
    })
    corner(tb, 7)
    tabsBtns[i] = tb
    local pg = create("ScrollingFrame", host, {
        Name = "Page" .. i, BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.blue,
        Visible = i == 1, CanvasSize = UDim2.fromOffset(0, 760),
    })
    corner(pg, 8)
    pages[i] = pg
end
local function showPage(index)
    for i, pg in ipairs(pages) do
        pg.Visible = i == index
        tabsBtns[i].BackgroundColor3 = i == index and C.blue or C.button
    end
end
for i, tb in ipairs(tabsBtns) do clean:connect(tb.Activated, function() showPage(i) end) end
showPage(1)

-- TARGET PAGE: target only, START begins movement, zero automatic TP on selection.
label(pages[1], "ИГРОКИ", 4, 20, 11).TextColor3 = C.white
UI.roster = create("ScrollingFrame", pages[1], {
    Name = "Roster", Position = UDim2.fromOffset(8, 27),
    Size = UDim2.new(1, -16, 0, 183), BackgroundColor3 = C.bg,
    BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = C.blue, CanvasSize = UDim2.fromOffset(0, 0),
})
corner(UI.roster, 8)
UI.start = button(pages[1], "▶  START", 220, 42, C.green)
UI.stop = button(pages[1], "■  STOP", 267, 34, C.red)
UI.once = button(pages[1], "⚡  TP ONCE", 306, 34, C.blue)
label(pages[1], "ДИСТАНЦИЯ", 348, 32, 11)
UI.dist = input(pages[1], SET.distance, 348, "3.0")
UI.lead = button(pages[1], "", 390, 35)
UI.ss = button(pages[1], "", 432, 35)
pages[1].CanvasSize = UDim2.fromOffset(0, 481)

-- FEATURE PAGE: no explanatory text under functions.
label(pages[2], "БОЙ", 4, 22, 11).TextColor3 = C.white
UI.aim = button(pages[2], "", 29, 41)
label(pages[2], "УТИЛИТЫ", 78, 22, 11).TextColor3 = C.white
UI.invis = button(pages[2], "▶ INVIS • AIRBORNITE", 104, 40, C.blue)
UI.speed = button(pages[2], "", 152, 36)
label(pages[2], "СКОРОСТЬ", 198, 33, 11)
UI.speedInput = input(pages[2], SET.speedValue, 198, "42")
UI.safe = button(pages[2], "", 239, 35)
UI.reset = button(pages[2], "", 280, 35)
label(pages[2], "ГРАФИКА", 323, 22, 11).TextColor3 = C.white
UI.fps = button(pages[2], "", 351, 42, C.green)
create("UIStroke", UI.fps, {Color = Color3.fromRGB(71, 237, 191), Thickness = 1.4})
pages[2].CanvasSize = UDim2.fromOffset(0, 405)

-- EXTRA PAGE: grouped by purpose; no redundant descriptions.
label(pages[3], "ПЕРЕМЕЩЕНИЕ", 4, 22, 11).TextColor3 = C.white
UI.wall = button(pages[3], "", 31, 36)
UI.coord = button(pages[3], "TP К КООРДИНАТАМ", 76, 38, C.blue)
label(pages[3], "ОПТИМИЗАЦИЯ", 122, 23, 11).TextColor3 = C.white
UI.culling = button(pages[3], "", 149, 36)
label(pages[3], "РАДИУС", 193, 33, 11)
UI.radius = input(pages[3], SET.radius, 193, "160")
label(pages[3], "ВНЕШНИЕ МОДУЛИ", 241, 22, 11).TextColor3 = C.white
UI.hkg = button(pages[3], "▶ HKG VOID", 269, 40, C.blue)
UI.danger = button(pages[3], "☠  DANGER CORE  •  EXECUTE", 317, 51, C.red)
create("UIStroke", UI.danger, {Color = Color3.fromRGB(255, 112, 148), Thickness = 1.6})
create("UIGradient", UI.danger, {
    Color = ColorSequence.new(Color3.fromRGB(233, 81, 123), Color3.fromRGB(124, 27, 64)),
    Rotation = 0,
})
pages[3].CanvasSize = UDim2.fromOffset(0, 382)

-- Status messages use the single one-line bar above tabs, not sublabels.
UI.invisStatus = UI.status
UI.hkgStatus = UI.status
UI.dangerStatus = UI.status
UI.fpsStatus = {Text = ""}

-- Floating controls: no per-frame UI work and one global pointer handler.
local dock = button(gui, "≡", 0, 44, C.blue)
dock.Name = "Dock"
dock.Size = UDim2.fromOffset(40, 40)
dock.Position = UDim2.fromOffset(math.max(5, view.X - 52), math.floor(view.Y * 0.31))
dock.TextSize = 23
local aimHud = button(gui, "◎", 0, 44, C.button)
aimHud.Name = "AimSelect"
aimHud.Size = UDim2.fromOffset(44, 44)
aimHud.Position = UDim2.fromOffset(14, 112)
aimHud.TextSize = 26
aimHud.Visible = false
local hilite = clean:own(Instance.new("Highlight"))
hilite.Name = "TSB_DELTA_v37_AimHighlight"
hilite.DepthMode = Enum.HighlightDepthMode.Occluded
hilite.FillColor = Color3.fromRGB(18, 179, 232)
hilite.FillTransparency = 0.90
hilite.OutlineColor = Color3.fromRGB(40, 229, 255)
hilite.OutlineTransparency = 0.08
hilite.Enabled = false
hilite.Parent = workspace

local function screenView()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(430, 780)
end
local function moveInside(object, point)
    local viewport = screenView()
    local size = object.AbsoluteSize
    object.Position = UDim2.fromOffset(
        math.floor(math.clamp(point.X, 2, math.max(2, viewport.X - size.X - 2))),
        math.floor(math.clamp(point.Y, 2, math.max(2, viewport.Y - size.Y - 2))))
end
local drag, wasMoved = nil, false
local suppressed = setmetatable({}, {__mode = "k"})
local function beginDrag(handle, movable, input)
    if drag then return end -- Do not confuse simultaneous touch inputs.
    local typ = input.UserInputType
    if typ ~= Enum.UserInputType.MouseButton1 and typ ~= Enum.UserInputType.Touch then return end
    local pos = Vector2.new(input.Position.X, input.Position.Y)
    drag = {handle = handle, object = movable, start = pos,
        initial = movable.AbsolutePosition, pointer = input}
    wasMoved = false
end
-- Bind header text too: TextLabels can intercept touches on some executors.
for _, handle in ipairs({titlebar, title}) do
    clean:connect(handle.InputBegan, function(input) beginDrag(titlebar, frame, input) end)
end
for _, handle in ipairs({dock, aimHud}) do
    clean:connect(handle.InputBegan, function(input) beginDrag(handle, handle, input) end)
end
clean:connect(UserInputService.InputChanged, function(input)
    if not drag then return end
    local touch = drag.pointer.UserInputType == Enum.UserInputType.Touch
    if (touch and input ~= drag.pointer) or
        (not touch and input.UserInputType ~= Enum.UserInputType.MouseMovement) then return end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - drag.start
    if delta.Magnitude > 6 then wasMoved = true end
    if wasMoved then moveInside(drag.object, drag.initial + delta) end
end)
clean:connect(UserInputService.InputEnded, function(input)
    if not drag then return end
    local touch = drag.pointer.UserInputType == Enum.UserInputType.Touch
    if (touch and input ~= drag.pointer) or
        (not touch and input.UserInputType ~= Enum.UserInputType.MouseButton1) then return end
    if wasMoved then suppressed[drag.handle] = os.clock() + 0.22 end
    drag = nil
end)
local function wasDragged(object)
    return (suppressed[object] or 0) > os.clock()
end
local minimized = false
clean:connect(miniBtn.Activated, function()
    minimized = not minimized
    frame.Size = UDim2.fromOffset(minimized and 195 or W, minimized and 37 or H)
    for _, child in ipairs(frame:GetChildren()) do
        if child:IsA("GuiObject") and child ~= titlebar then child.Visible = not minimized end
    end
    miniBtn.Text = minimized and "+" or "−"
    moveInside(frame, frame.AbsolutePosition)
end)
clean:connect(dock.Activated, function()
    if not wasDragged(dock) then frame.Visible = not frame.Visible end
end)
-- If a user rotates the device, keep the controls reachable.
if cam then
    clean:connect(cam:GetPropertyChangedSignal("ViewportSize"), function()
        if not clean.alive then return end
        local viewport = screenView()
        W = math.clamp(viewport.X - 24, 218, 294)
        H = math.clamp(viewport.Y - 35, 295, 460)
        if not minimized then frame.Size = UDim2.fromOffset(W, H) end
        moveInside(frame, frame.AbsolutePosition)
        moveInside(dock, dock.AbsolutePosition)
        moveInside(aimHud, aimHud.AbsolutePosition)
    end)
end

-- ==== SINGLE MOTION CONTROLLER: TP and AIM never fight for Root.CFrame ====
local cachedPing, lastPing = 50, -1e9
local aimPositionFor, syncAutoRotate
local function pingSeconds()
    local now = os.clock()
    if now - lastPing >= 1.5 then
        lastPing = now
        local ok, value = pcall(function()
            return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
        end)
        if ok and type(value) == "number" and finite(value) then
            cachedPing = math.clamp(value, 0, 300)
        end
    end
    return cachedPing / 1000
end
local function horizontal(v)
    return Vector3.new(v.X, 0, v.Z)
end
local function predict(root, maxTime, maxDistance)
    local p = root.Position
    if not SET.lead then return p end
    local v = horizontal(root.AssemblyLinearVelocity)
    if v.Magnitude > 90 then v = v.Unit * 90 end
    local dt = math.min(maxTime, pingSeconds() * .35 + .018)
    local advance = v * dt
    if advance.Magnitude > maxDistance then advance = advance.Unit * maxDistance end
    return p + advance
end
local function behindFrame()
    local _, enemyHum, targetRoot = getChar(state.target)
    if not targetRoot then return nil, "Цель не готова" end
    local predicted = predict(targetRoot, SET.ss and .085 or .060, math.min(2, SET.distance * .55))
    if not validPos(predicted) then return nil, "Координаты цели недоступны" end
    local face = horizontal(targetRoot.CFrame.LookVector)
    if face.Magnitude < .06 then face = horizontal(targetRoot.AssemblyLinearVelocity) end
    if face.Magnitude < .06 then face = Vector3.new(0, 0, -1) end
    face = face.Unit
    if SET.ss then
        local angularY = targetRoot.AssemblyAngularVelocity.Y
        if math.abs(angularY) < 12 then
            local t = math.min(.07, pingSeconds() * .3 + .012)
            local turned = CFrame.Angles(0, angularY * t, 0):VectorToWorldSpace(face)
            if horizontal(turned).Magnitude > .05 then face = horizontal(turned).Unit end
        end
    end
    -- Behind the opponent (negative LookVector); keep height on their root.
    local destination = predicted - face * SET.distance
    destination = Vector3.new(destination.X, targetRoot.Position.Y, destination.Z)
    if not validPos(destination) then return nil, "TP заблокирован: неверная позиция" end
    local lookAt = Vector3.new(predicted.X, destination.Y, predicted.Z)
    if aimPositionFor and SET.aim and state.aimTarget then
        local aimPos = aimPositionFor(state.aimTarget)
        if aimPos then lookAt = Vector3.new(aimPos.X, destination.Y, aimPos.Z) end
    end
    if (lookAt - destination).Magnitude < .12 then lookAt = destination + face end
    return CFrame.lookAt(destination, lookAt)
end
local corrections, previousTp, previousTpAt = 0, nil, 0
local followStatusAt, motionErrorAt = 0, 0
local function teleport(force)
    if not clean.alive then return false, "Скрипт закрыт" end
    if state.safeActive or state.coordinate then return false, "Выключи SAFE/COORD" end
    if not state.target or state.target.Parent ~= Players then return false, "Выбери игрока" end
    local char, humanoid, root = getChar()
    if not char or not root then return false, "Персонаж не готов" end
    if humanoid.Sit then humanoid.Sit = false end
    if root.Anchored then return false, "Персонаж закреплён игрой" end
    local wanted, reason = behindFrame()
    if not wanted then return false, reason end
    local delta = (root.Position - wanted.Position).Magnitude
    local orientation = root.CFrame.LookVector:Dot(wanted.LookVector)
    if not force and delta < .13 and orientation > .9994 then return true, "У цели" end
    -- One CFrame write per tick. PivotTo is only a *fallback* on explicit START,
    -- not something that traverses the entire character on every frame.
    local ok, err = pcall(function() root.CFrame = wanted end)
    if force and (not ok or (root.Position - wanted.Position).Magnitude > .8) then
        ok, err = pcall(function() char:PivotTo(wanted) end)
    end
    if not ok or (root.Position - wanted.Position).Magnitude > 1.2 then
        return false, "Локальный TP не удался: " .. tostring(err):sub(1, 55)
    end
    previousTp, previousTpAt = wanted.Position, os.clock()
    state.tpCount = state.tpCount + 1
    return true, "TP применён локально"
end
local function paintFollow()
    local ready = state.target and state.target.Parent == Players
    UI.start.BackgroundColor3 = ready and C.green or C.button
    UI.start.Text = state.follow and "▶  FOLLOW: ON"
        or (ready and "▶  START" or "▶  ВЫБЕРИ ИГРОКА")
end
local function stopFollow(preserve)
    if not preserve then state.resumeFollow = false end
    state.follow = false
    previousTp = nil
    if syncAutoRotate then syncAutoRotate() end
    paintFollow()
end
local function startFollow()
    if not state.target or state.target.Parent ~= Players then
        status("Сначала выбери игрока", "error")
        return
    end
    if state.coordinate or state.safeActive then
        status("Выключи SAFE ZONA / COORD перед START", "error")
        return
    end
    state.follow, state.resumeFollow = true, true
    corrections, previousTp, previousTpAt = 0, nil, 0
    if syncAutoRotate then syncAutoRotate() end
    -- Immediate position write on button tap, never waits for a motion step.
    local ok, reason = teleport(true)
    status(ok and ("FOLLOW ▶ " .. state.target.Name) or ("TP: " .. tostring(reason)),
        ok and "ok" or "error")
    paintFollow()
end

-- ==== ROSTER / TARGET SELECTION ==========================================
local entries, rosterConnections = {}, {}
local thumbCache, thumbQueue, thumbWorkers = {}, {}, 0
local rosterRefreshPending = false
local function queueThumbnail(userId, imageLabel)
    if thumbCache[userId] then imageLabel.Image = thumbCache[userId]; return end
    thumbQueue[#thumbQueue + 1] = {id = userId, label = imageLabel}
    if thumbWorkers >= 2 then return end
    thumbWorkers = thumbWorkers + 1
    task.spawn(function()
        while clean.alive and #thumbQueue > 0 do
            local item = table.remove(thumbQueue, 1)
            if item.label and item.label.Parent then
                local ok, image = pcall(function()
                    return Players:GetUserThumbnailAsync(item.id,
                        Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                end)
                if ok and type(image) == "string" and image ~= "" then
                    thumbCache[item.id] = image
                    if clean.alive and item.label.Parent then item.label.Image = image end
                end
            end
            task.wait() -- Avoid burst thumbnail requests and UI stalls.
        end
        thumbWorkers = thumbWorkers - 1
    end)
end
local function rebuildRoster()
    rosterRefreshPending = false
    if not clean.alive then return end
    for _, connection in ipairs(rosterConnections) do pcall(function() connection:Disconnect() end) end
    rosterConnections = {}
    for _, child in ipairs(UI.roster:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    entries = {}
    local players = Players:GetPlayers()
    table.sort(players, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)
    local y = 5
    for _, enemy in ipairs(players) do
        if enemy ~= LocalPlayer then
            local row = button(UI.roster, "", y, 47, enemy == state.target and C.green or C.button)
            row.Name = "Target_" .. tostring(enemy.UserId)
            row.AutoButtonColor = true
            create("UIStroke", row, {
                Color = enemy == state.target and Color3.fromRGB(83, 220, 188) or Color3.fromRGB(41, 67, 100),
                Thickness = 1,
            })
            local display = create("TextLabel", row, {
                Position = UDim2.fromOffset(9, 4), Size = UDim2.new(1, -58, 0, 22),
                BackgroundTransparency = 1, Text = enemy.DisplayName,
                Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.white,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            create("TextLabel", row, {
                Position = UDim2.fromOffset(9, 26), Size = UDim2.new(1, -58, 0, 15),
                BackgroundTransparency = 1, Text = "@" .. enemy.Name,
                Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = C.muted,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTruncate = Enum.TextTruncate.AtEnd,
            })
            local avatar = create("ImageLabel", row, {
                Name = "Avatar", Position = UDim2.new(1, -43, 0, 5),
                Size = UDim2.fromOffset(37, 37),
                BackgroundColor3 = Color3.fromRGB(17, 34, 54), BorderSizePixel = 0,
                Image = "", ScaleType = Enum.ScaleType.Crop,
            })
            corner(avatar, 19)
            queueThumbnail(enemy.UserId, avatar)
            entries[enemy.UserId] = row
            rosterConnections[#rosterConnections + 1] = row.Activated:Connect(function()
                if not clean.alive or enemy.Parent ~= Players then return end
                -- Selecting is purely a UI operation: NO teleport and NO auto-aim.
                if state.follow or state.resumeFollow then stopFollow(false) end
                state.target = enemy
                corrections, previousTp = 0, nil
                for id, other in pairs(entries) do
                    local selected = id == enemy.UserId
                    other.BackgroundColor3 = selected and C.green or C.button
                    local stroke = other:FindFirstChildOfClass("UIStroke")
                    if stroke then stroke.Color = selected and Color3.fromRGB(83, 220, 188)
                        or Color3.fromRGB(41, 67, 100) end
                end
                paintFollow()
                status("Цель: @" .. enemy.Name .. " • нажми START для TP", "ok")
            end)
            y = y + 53
        end
    end
    if y == 5 then label(UI.roster, "На сервере пока нет других игроков", 5, 52) end
    UI.roster.CanvasSize = UDim2.fromOffset(0, y + 5)
end
local function scheduleRosterUpdate()
    if rosterRefreshPending or not clean.alive then return end
    rosterRefreshPending = true
    task.defer(function()
        if clean.alive then rebuildRoster() end
    end)
end
clean:connect(Players.PlayerAdded, scheduleRosterUpdate)
clean:connect(Players.PlayerRemoving, function(player)
    if state.target == player then
        state.target = nil
        stopFollow(false)
        status("Выбранный игрок вышел", "error")
    end
    if state.aimTarget == player then
        state.aimTarget = nil
        hilite.Enabled, hilite.Adornee = false, nil
        aimHud.Text, aimHud.BackgroundColor3 = "◎", C.button
        if syncAutoRotate then syncAutoRotate() end
    end
    scheduleRosterUpdate()
end)
clean:connect(UI.start.Activated, startFollow)
clean:connect(UI.stop.Activated, function()
    stopFollow(false)
    status("FOLLOW остановлен")
end)
clean:connect(UI.once.Activated, function()
    local ok, reason = teleport(true)
    status(ok and "TP ONCE: позиция изменена локально" or ("TP ONCE: " .. tostring(reason)),
        ok and "ok" or "error")
end)
clean:connect(UI.dist.FocusLost, function()
    local n = tonumber(UI.dist.Text)
    if n and finite(n) then SET.distance = math.clamp(math.floor(n * 10 + .5) / 10, 2.3, 8) end
    UI.dist.Text = tostring(SET.distance)
end)
clean:connect(UI.lead.Activated, function()
    SET.lead = not SET.lead
    toggleLook(UI.lead, "ОПЕРЕЖЕНИЕ", SET.lead)
end)
clean:connect(UI.ss.Activated, function()
    SET.ss = not SET.ss
    toggleLook(UI.ss, "TP SS+", SET.ss)
end)
toggleLook(UI.lead, "ОПЕРЕЖЕНИЕ", SET.lead)
toggleLook(UI.ss, "TP SS+", SET.ss)
paintFollow()

-- ==== AIM: CHARACTER ROTATION ONLY; NEVER MODIFY CurrentCamera ====
local savedRotate, savedHum = nil, nil
local function restoreRotation()
    if savedHum and savedHum.Parent and savedRotate ~= nil then
        pcall(function() savedHum.AutoRotate = savedRotate end)
    end
    savedHum, savedRotate = nil, nil
end
syncAutoRotate = function()
    local own = state.follow or (SET.aim and state.aimTarget ~= nil)
    local _, humanoid = getChar()
    if not own or not humanoid then restoreRotation(); return end
    if humanoid ~= savedHum then
        restoreRotation()
        savedHum, savedRotate = humanoid, humanoid.AutoRotate
    end
    if humanoid.AutoRotate then humanoid.AutoRotate = false end
end
local function aimUi()
    toggleLook(UI.aim, "AIM LOCK", SET.aim)
    aimHud.Visible = SET.aim
    local active = state.aimTarget and SET.aim
    aimHud.Text = active and "●" or "◎"
    aimHud.BackgroundColor3 = active and C.green or C.button
    local char = active and state.aimTarget.Character or nil
    hilite.Adornee = char
    hilite.Enabled = char ~= nil and active
end
aimPositionFor = function(plr)
    local _, _, targetRoot = getChar(plr)
    if not targetRoot then return nil end
    -- Small lead for directional aim; the target's current, replicated position
    -- is usually more reliable than extrapolating a whole ping interval.
    local pos = targetRoot.Position
    if SET.lead then
        local vel = horizontal(targetRoot.AssemblyLinearVelocity)
        if vel.Magnitude > 85 then vel = vel.Unit * 85 end
        local lead = vel * math.min(.035, pingSeconds() * .2 + .008)
        if lead.Magnitude > .9 then lead = lead.Unit * .9 end
        pos = pos + lead
    end
    return pos
end
local function pickTarget()
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local center = camera.ViewportSize * .5
    local radius = math.min(center.X, center.Y) * .55
    local winner, closest = nil, radius
    for _, candidate in ipairs(Players:GetPlayers()) do
        if candidate ~= LocalPlayer then
            local pos = aimPositionFor(candidate)
            if pos then
                local at, onScreen = camera:WorldToViewportPoint(pos)
                if onScreen and at.Z > 0 then
                    local delta = (Vector2.new(at.X, at.Y) - center).Magnitude
                    if delta < closest then winner, closest = candidate, delta end
                end
            end
        end
    end
    if not winner and state.target and aimPositionFor(state.target) then return state.target end
    return winner
end
local function rotateAvatarToAim()
    local target = state.aimTarget
    if not SET.aim or not target or target.Parent ~= Players then return end
    local _, humanoid, root = getChar()
    if not root or humanoid.Sit or root.Anchored then return end
    local point = aimPositionFor(target)
    if not point then
        if hilite.Enabled then hilite.Enabled = false end
        return
    end
    if hilite.Adornee ~= target.Character or not hilite.Enabled then
        hilite.Adornee, hilite.Enabled = target.Character, true
    end
    local direction = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z)
    if direction.Magnitude < .2 then return end
    local face = direction.Unit
    -- Immediate avatar-only yaw, no camera tracking, lerp or tween.
    if root.CFrame.LookVector:Dot(face) < .9993 then
        root.CFrame = CFrame.lookAt(root.Position, root.Position + face)
    end
end
local function switchAim(on)
    SET.aim = on == true
    if not SET.aim then state.aimTarget = nil end
    syncAutoRotate()
    aimUi()
end
clean:connect(UI.aim.Activated, function()
    switchAim(not SET.aim)
    status(SET.aim and "AIM включён • нажми ◎ для захвата" or "AIM выключен")
end)
clean:connect(aimHud.Activated, function()
    if not SET.aim or wasDragged(aimHud) then return end
    if state.aimTarget then
        state.aimTarget = nil
        status("AIM: захват снят")
    else
        state.aimTarget = (state.target and aimPositionFor(state.target) and state.target) or pickTarget()
        status(state.aimTarget and ("AIM: @" .. state.aimTarget.Name)
            or "AIM: выбери цель или наведи центр экрана", state.aimTarget and "ok" or "error")
    end
    syncAutoRotate()
    aimUi()
end)
aimUi()

-- Sole real-time motion loop. No RenderStep bindings, no per-frame camera edits.
clean:connect(RunService.PostSimulation, function()
    if not clean.alive or not state.follow and not (SET.aim and state.aimTarget) then return end
    local ok, err = pcall(function()
        syncAutoRotate()
        if state.follow then
            if not state.target or state.target.Parent ~= Players then
                stopFollow(false)
                status("Цель покинула сервер", "error")
                return
            end
            local now = os.clock()
            local localRoot = select(3, getChar())
            if previousTp and localRoot and now - previousTpAt < .45 then
                local goal = behindFrame()
                if goal and (localRoot.Position - previousTp).Magnitude > 9
                    and (localRoot.Position - goal.Position).Magnitude > 9 then
                    corrections = corrections + 1
                end
            end
            local success, reason = teleport(false)
            if now - followStatusAt >= 1.1 then
                followStatusAt = now
                if not success then status("FOLLOW: " .. tostring(reason), "error")
                elseif corrections > 12 then
                    status("TP сбрасывается игровым сервером", "error")
                    corrections = 0
                end
            end
        elseif SET.aim and state.aimTarget then
            syncAutoRotate()
            rotateAvatarToAim()
        end
    end)
    if not ok and os.clock() - motionErrorAt >= 2 then
        motionErrorAt = os.clock()
        warn("[TSB v37 Motion] " .. tostring(err))
        status("Ошибка движения: " .. tostring(err):sub(1, 65), "error")
    end
end)

-- ==== FAST OPTIONAL SPEED =================================================
local speedHum, oldSpeed, lastAppliedSpeed = nil, nil, nil
local function restoreSpeed()
    if speedHum and speedHum.Parent and lastAppliedSpeed and speedHum.WalkSpeed == lastAppliedSpeed then
        pcall(function() speedHum.WalkSpeed = oldSpeed end)
    end
    speedHum, oldSpeed, lastAppliedSpeed = nil, nil, nil
end
local function speedTick()
    if not clean.alive or not SET.speed then return end
    local _, hum = getChar()
    if not hum then return end
    if speedHum ~= hum then
        restoreSpeed()
        speedHum, oldSpeed = hum, hum.WalkSpeed
    end
    if hum.WalkSpeed ~= SET.speedValue then
        hum.WalkSpeed = SET.speedValue
        lastAppliedSpeed = SET.speedValue
    end
end
local function setSpeed(v)
    SET.speed = v
    toggleLook(UI.speed, "SPEED", SET.speed)
    if SET.speed then
        speedTick()
    else
        restoreSpeed()
    end
end
clean:connect(UI.speed.Activated, function() setSpeed(not SET.speed) end)
clean:connect(UI.speedInput.FocusLost, function()
    local n = tonumber(UI.speedInput.Text)
    if n and finite(n) then SET.speedValue = math.clamp(math.floor(n + .5), 8, 120) end
    UI.speedInput.Text = tostring(SET.speedValue)
    if SET.speed then speedTick() end
end)
local speedTimer = 0
clean:connect(RunService.Heartbeat, function(dt)
    if not SET.speed or not clean.alive then return end
    speedTimer = speedTimer + dt
    if speedTimer >= .09 then
        speedTimer = 0
        pcall(speedTick)
    end
end)
toggleLook(UI.speed, "SPEED", SET.speed)

-- ==== SAFE ZONE / DEATH ===================================================
local function exitSafe(returnBack)
    if returnBack and state.safeReturn then
        local char, _, root = getChar()
        if char and root then pcall(function() char:PivotTo(state.safeReturn) end) end
    end
    if state.safePart then pcall(function() state.safePart:Destroy() end) end
    state.safePart, state.safeReturn, state.safeActive = nil, nil, false
end
local function enterSafe()
    local char, hum, root = getChar()
    if not char or state.safeActive then return false end
    if state.follow then stopFollow(true) end
    state.safeReturn = root.CFrame
    local y = math.max(workspace.FallenPartsDestroyHeight + 18, -80)
    local part = create("Part", workspace, {
        Name = "TSB_v37_LocalSafeFloor", Size = Vector3.new(24, 2, 24),
        CFrame = CFrame.new(root.Position.X, y - 4, root.Position.Z),
        Anchored = true, CanCollide = true, CanTouch = false, CanQuery = false,
        Transparency = 1, CastShadow = false,
    })
    state.safePart = part
    char:PivotTo(CFrame.new(root.Position.X, y, root.Position.Z))
    state.safeActive = true
    status("SAFE ZONA: локальное перемещение", "ok")
    return true
end
local function setSafe(v)
    SET.safe = v
    toggleLook(UI.safe, "SAVE ZONA", SET.safe)
    if not v and state.safeActive then exitSafe(true) end
end
clean:connect(UI.safe.Activated, function() setSafe(not SET.safe) end)
clean:connect(UI.reset.Activated, function()
    SET.reset = not SET.reset
    toggleLook(UI.reset, "AUTO RESET", SET.reset)
end)
toggleLook(UI.safe, "SAVE ZONA", SET.safe)
toggleLook(UI.reset, "AUTO RESET", SET.reset)
local humHealthConn, humDiedConn
local function monitorCharacter(character)
    if humHealthConn then humHealthConn:Disconnect(); humHealthConn = nil end
    if humDiedConn then humDiedConn:Disconnect(); humDiedConn = nil end
    local hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
    if not clean.alive or not hum then return end
    humHealthConn = hum.HealthChanged:Connect(function(health)
        if SET.safe and not state.follow and not state.safeActive and not state.coordinate
            and health > 0 and health <= SET.safeThreshold then pcall(enterSafe) end
    end)
    humDiedConn = hum.Died:Connect(function()
        if state.follow then stopFollow(true) end
        if SET.reset then
            task.defer(function()
                if not clean.alive then return end
                for _, item in ipairs(character:GetDescendants()) do
                    if item:IsA("BasePart") then
                        pcall(function() item.LocalTransparencyModifier = 1 end)
                    elseif item:IsA("Decal") then
                        pcall(function() item.Transparency = 1 end)
                    end
                end
            end)
        end
    end)
end

-- ==== WALL PASS (BOUNDED LOCAL COLLISION CHANGES) =========================
local wallSaved = setmetatable({}, {__mode = "k"})
local wallRay = RaycastParams.new()
wallRay.FilterType = Enum.RaycastFilterType.Exclude
wallRay.IgnoreWater = true
local wallDirs = {
    Vector3.new(1,0,0), Vector3.new(-1,0,0), Vector3.new(0,0,1),
    Vector3.new(0,0,-1), Vector3.new(.707,0,.707), Vector3.new(-.707,0,-.707),
}
local function restoreWalls()
    for part, value in pairs(wallSaved) do
        if part.Parent then pcall(function() part.CanCollide = value end) end
        wallSaved[part] = nil
    end
end
local function wallTick()
    local char, _, root = getChar()
    if not SET.wall or not root then return end
    wallRay.FilterDescendantsInstances = {char}
    for _, direction in ipairs(wallDirs) do
        for _, offY in ipairs({-.6, 1}) do
            local hit = workspace:Raycast(root.Position + Vector3.new(0, offY, 0), direction * 4, wallRay)
            local part = hit and hit.Instance
            if part and part:IsA("BasePart") and part.Anchored and part.CanCollide
                and math.abs(hit.Normal.Y) < .4 then
                if wallSaved[part] == nil then wallSaved[part] = part.CanCollide end
                part.CanCollide = false
            end
        end
    end
    for part, val in pairs(wallSaved) do
        if not part.Parent or (part.Position - root.Position).Magnitude > math.max(part.Size.Magnitude, 18) then
            if part.Parent then pcall(function() part.CanCollide = val end) end
            wallSaved[part] = nil
        end
    end
end
local wallTimer = 0
clean:connect(RunService.Heartbeat, function(dt)
    if not clean.alive or not SET.wall then return end
    wallTimer = wallTimer + dt
    if wallTimer >= .14 then
        wallTimer = 0
        pcall(wallTick)
    end
end)
clean:connect(UI.wall.Activated, function()
    SET.wall = not SET.wall
    if not SET.wall then restoreWalls() end
    toggleLook(UI.wall, "WALL PASS", SET.wall)
end)
toggleLook(UI.wall, "WALL PASS", SET.wall)

-- ==== MANUAL COORDINATE TELEPORT =========================================
local TARGET_COORD = CFrame.new(-216.581772, -10000.0029, -145.716171,
    0.852498353, -1.00300547e-07, 0.522729933,
    6.29894217e-08, 1, 8.91515128e-08,
    -0.522729933, -4.30750616e-08, 0.852498353)
local function exitCoord(returnBack)
    if returnBack and state.coordReturn then
        local char = getChar()
        if char then pcall(function() char:PivotTo(state.coordReturn) end) end
    end
    if state.coordPart then pcall(function() state.coordPart:Destroy() end) end
    state.coordPart, state.coordReturn, state.coordinate = nil, nil, false
    UI.coord.Text = "TP К КООРДИНАТАМ Y=-10000"
end
clean:connect(UI.coord.Activated, function()
    if state.coordinate then
        exitCoord(true)
        status("Координатный режим выключен")
        return
    end
    local char, _, root = getChar()
    if not char then status("Персонаж не готов", "error"); return end
    stopFollow(false)
    exitSafe(false)
    state.coordReturn = root.CFrame
    -- BELOW FallenPartsDestroyHeight cannot safely be reached client-side.
    -- Keep the requested coordinate, but never promise it will survive physics.
    state.coordPart = create("Part", workspace, {
        Name = "TSB_v37_CoordFloor", Size = Vector3.new(26, 2, 26),
        Anchored = true, CanCollide = true, CanTouch = false, CanQuery = false,
        CFrame = CFrame.new(TARGET_COORD.Position - Vector3.new(0, 4, 0)),
        Transparency = 1,
    })
    local ok, err = pcall(function() char:PivotTo(TARGET_COORD) end)
    if not ok then
        exitCoord(false)
        status("TP к координатам: " .. tostring(err), "error")
        return
    end
    state.coordinate = true
    UI.coord.Text = "↩ ВЕРНУТЬСЯ С КООРДИНАТ"
    status("Координатный TP выполнен локально", "ok")
end)

-- ==== VISUAL FPS ULTRA (EFFECTS ONLY, REVERSIBLE) ========================
local visual = {
    running = false, generation = 0, changed = setmetatable({}, {__mode = "k"}),
    effects = setmetatable({}, {__mode = "k"}),
    candidates = {}, seen = setmetatable({}, {__mode = "k"}),
    distanceOriginal = setmetatable({}, {__mode = "k"}),
    objects = 0, skipped = 0, fx = 0, conn = nil, pending = {}, head = 1,
}
local function playerModel(obj)
    local model = obj:FindFirstAncestorOfClass("Model")
    while model do
        if model:FindFirstChildOfClass("Humanoid") then return true end
        model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model") or nil
    end
    return false
end
local function recordProperty(obj, prop, value)
    local ok, old = pcall(function() return obj[prop] end)
    if not ok or old == value then return end
    local properties = visual.changed[obj]
    if not properties then properties = {}; visual.changed[obj] = properties end
    if properties[prop] == nil then properties[prop] = old end
    pcall(function() obj[prop] = value end)
end
local fxClasses = {ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true, Sparkles = true}
local function decoration(obj)
    return obj:IsA("BasePart") and obj.Anchored and not obj.CanCollide and not obj.CanTouch
        and not playerModel(obj) and obj.Transparency < .96
end
local function processVisual(obj)
    if not visual.running or not obj or not obj.Parent then return end
    local kind = obj.ClassName
    -- Filter cheap object classes BEFORE ancestor queries (large maps have
    -- thousands of irrelevant constraints, scripts, folders, and attachments).
    if not fxClasses[kind] and kind ~= "PointLight" and kind ~= "SpotLight"
        and kind ~= "SurfaceLight" and not obj:IsA("PostEffect")
        and not obj:IsA("BasePart") then return end
    -- Don't interfere with player models, attack effects, or gameplay UI.
    if playerModel(obj) then visual.skipped = visual.skipped + 1; return end
    if fxClasses[kind] then
        recordProperty(obj, "Enabled", false)
        visual.effects[obj] = true
        if kind == "ParticleEmitter" or kind == "Trail" then pcall(function() obj:Clear() end) end
    elseif obj:IsA("PostEffect") then
        recordProperty(obj, "Enabled", false)
    elseif kind == "PointLight" or kind == "SpotLight" or kind == "SurfaceLight" then
        recordProperty(obj, "Enabled", false)
    elseif obj:IsA("BasePart") and decoration(obj) then
        recordProperty(obj, "CastShadow", false)
        if #visual.candidates < 1100 and not visual.seen[obj] then
            visual.seen[obj] = true
            visual.candidates[#visual.candidates + 1] = obj
        end
    end
    visual.objects = visual.objects + 1
end
local function restoreHidden()
    for part, orig in pairs(visual.distanceOriginal) do
        if part.Parent then pcall(function() part.LocalTransparencyModifier = orig end) end
        visual.distanceOriginal[part] = nil
    end
end
local function doCulling()
    if not SET.culling then return end
    local _, _, root = getChar()
    if not root then return end
    local p = root.Position
    local far = (SET.radius + 12)^2
    local near = (SET.radius - 12)^2
    local keep = {}
    for _, part in ipairs(visual.candidates) do
        if part.Parent and decoration(part) then
            keep[#keep + 1] = part
            local q = part.Position
            local d2 = (p.X-q.X)^2 + (p.Y-q.Y)^2 + (p.Z-q.Z)^2
            if d2 > far and visual.distanceOriginal[part] == nil then
                local old = part.LocalTransparencyModifier
                if old < .99 then
                    visual.distanceOriginal[part] = old
                    part.LocalTransparencyModifier = 1
                end
            elseif d2 < near and visual.distanceOriginal[part] ~= nil then
                part.LocalTransparencyModifier = visual.distanceOriginal[part]
                visual.distanceOriginal[part] = nil
            end
        else
            visual.seen[part] = nil
            visual.distanceOriginal[part] = nil
        end
    end
    visual.candidates = keep
end
local function stopVisual()
    visual.running = false
    visual.generation = visual.generation + 1
    if visual.conn then visual.conn:Disconnect(); visual.conn = nil end
    restoreHidden()
    for obj, props in pairs(visual.changed) do
        if obj.Parent then
            for prop, old in pairs(props) do pcall(function() obj[prop] = old end) end
        end
    end
    visual.changed, visual.effects = setmetatable({}, {__mode = "k"}), setmetatable({}, {__mode = "k"})
    visual.seen, visual.candidates = setmetatable({}, {__mode = "k"}), {}
    visual.objects, visual.fx, visual.pending, visual.head = 0, 0, {}, 1
end
local function scanVisual(token)
    local queue = workspace:GetChildren()
    for _, child in ipairs(Lighting:GetChildren()) do queue[#queue + 1] = child end
    local cursor, inspected = 1, 0
    while clean.alive and visual.running and visual.generation == token and cursor <= #queue and inspected < 35000 do
        local obj = queue[cursor]
        if obj and obj.Parent then
            pcall(processVisual, obj)
            if obj ~= workspace.CurrentCamera then
                for _, child in ipairs(obj:GetChildren()) do queue[#queue + 1] = child end
            end
        end
        cursor, inspected = cursor + 1, inspected + 1
        if inspected % 100 == 0 then task.wait() end
    end
end
local function startVisual()
    if visual.running then return end
    visual.running, visual.generation = true, visual.generation + 1
    local token = visual.generation
    recordProperty(Lighting, "GlobalShadows", false)
    visual.conn = workspace.DescendantAdded:Connect(function(obj)
        if visual.running and #visual.pending - visual.head < 1800 then
            visual.pending[#visual.pending + 1] = obj
        end
    end)
    task.spawn(scanVisual, token)
    -- Process at most 70 newly-added visual objects per batch, off event callbacks.
    task.spawn(function()
        while clean.alive and visual.running and visual.generation == token do
            local handled = 0
            while handled < 70 and visual.head <= #visual.pending do
                local obj = visual.pending[visual.head]
                visual.head = visual.head + 1
                if obj and obj.Parent then pcall(processVisual, obj) end
                handled = handled + 1
            end
            if visual.head > #visual.pending then
                visual.pending, visual.head = {}, 1
            end
            task.wait(0.08)
        end
    end)
    task.spawn(function()
        while clean.alive and visual.running and visual.generation == token do
            local total = 0
            for obj in pairs(visual.effects) do
                if obj.Parent then
                    total = total + 1
                    if total <= 800 and obj.Enabled then pcall(function() obj.Enabled = false end) end
                end
            end
            visual.fx = total
            pcall(doCulling)
            task.wait(2.8)
        end
    end)
end
local function paintVisual()
    toggleLook(UI.fps, "⚡ FPS ULTRA", SET.fps)
    toggleLook(UI.culling, "DISTANCE ECO", SET.culling)
    UI.fpsStatus.Text = SET.fps
        and ("FPS ULTRA: обработано " .. visual.objects .. " объектов; эффектов " .. visual.fx ..
            ". Графика клиента, без влияния на серверный пинг.")
        or "FPS ULTRA: OFF. Исходные свойства восстановлены."
end
clean:connect(UI.fps.Activated, function()
    SET.fps = not SET.fps
    if SET.fps then startVisual() else stopVisual() end
    paintVisual()
end)
clean:connect(UI.culling.Activated, function()
    SET.culling = not SET.culling
    if not SET.culling then restoreHidden() end
    paintVisual()
end)
clean:connect(UI.radius.FocusLost, function()
    local n = tonumber(UI.radius.Text)
    if n and finite(n) then SET.radius = math.clamp(math.floor(n + .5), 80, 300) end
    UI.radius.Text = tostring(SET.radius)
end)
task.spawn(function()
    while clean.alive do
        pcall(paintVisual)
        task.wait(8)
    end
end)

-- ==== REMOTE LOADER WITH TRACEABLE FAILURES ==============================
local SOURCES = {
    invis = {
        "https://raw.githubusercontent.com/Airbornite/tsb-scripts/refs/heads/main/InvisScript_loader.lua",
        "https://raw.githubusercontent.com/Airbornite/tsb-scripts/main/InvisScript_loader.lua",
    },
    hkg = {"https://raw.githubusercontent.com/pusahursahur-gif/HKG-hub./refs/heads/Lua/HKG-void"},
    danger = {"https://api.jnkie.com/api/v1/luascripts/public/e7272cc100526cce2983ec85de722d45e915a26117824385c78e0c30e61585f4/download"},
}
local requestFn
if type(request) == "function" then requestFn = request end
if not requestFn and type(http_request) == "function" then requestFn = http_request end
if not requestFn and type(syn) == "table" and type(syn.request) == "function" then requestFn = syn.request end
if not requestFn and type(http) == "table" and type(http.request) == "function" then requestFn = http.request end
local function downloadSource(url)
    local lastErr = "HTTP недоступен"
    -- First use exactly the command syntax supplied by the user. Retry with
    -- cache bypass only on errors, then fall back to executor request APIs.
    local ok, text = pcall(function() return game:HttpGet(url) end)
    if not ok then
        ok, text = pcall(function() return game:HttpGet(url, true) end)
    end
    if ok and type(text) == "string" and #text > 0 then
        local lower = text:sub(1, 220):lower()
        if lower:find("<!doctype", 1, true) or lower:find("<html", 1, true)
            or lower:find("404: not found", 1, true) then
            lastErr = "получен HTML / HTTP 404 вместо Lua"
        else
            return text
        end
    else
        lastErr = tostring(text)
    end
    if requestFn then
        local rqOK, result = pcall(requestFn, {Url = url, Method = "GET"})
        if rqOK and type(result) == "table" then
            local code = tonumber(result.StatusCode or result.Status or 0)
            local body = result.Body or result.body
            if (code == 200 or code == 0) and type(body) == "string" and #body > 0 then
                if body:sub(1, 50):lower():find("<html", 1, true)
                    or body:sub(1, 100):lower():find("404: not found", 1, true) then
                    lastErr = "получен HTML / 404"
                else return body end
            else lastErr = "HTTP " .. tostring(code) end
        elseif not rqOK then lastErr = tostring(result) end
    end
    return nil, lastErr
end
local moduleBusy, moduleStarted = {}, {}
local function runRemote(key, btn, field, caption)
    if not clean.alive or moduleBusy[key] then return end
    if type(loadstring) ~= "function" then
        field.Text = "Ошибка: исполнитель не поддерживает loadstring()"
        status(caption .. ": loadstring недоступен", "error")
        return
    end
    if moduleStarted[key] then
        field.Text = "Код уже выполнялся. Повторный запуск может создать дубли."
        return
    end
    moduleBusy[key] = true
    btn.Text = caption .. " • ЗАГРУЗКА..."
    field.Text = "Получаю внешний Lua-код..."
    task.spawn(function()
        local source, errorMsg
        for _, url in ipairs(SOURCES[key]) do
            source, errorMsg = downloadSource(url)
            if source then break end
        end
        if not clean.alive then moduleBusy[key] = false; return end
        if not source then
            moduleBusy[key] = false
            field.Text = "ОШИБКА ЗАГРУЗКИ: " .. tostring(errorMsg):sub(1, 190)
            btn.Text = "↻ ПОВТОРИТЬ " .. caption
            status(caption .. ": недоступен исходник", "error")
            warn("[TSB v37/" .. key .. "] " .. tostring(errorMsg))
            return
        end
        local okCompile, fn, why = pcall(loadstring, source)
        if not okCompile or type(fn) ~= "function" then
            moduleBusy[key] = false
            field.Text = "ОШИБКА КОМПИЛЯЦИИ LUA: " .. tostring(okCompile and why or fn):sub(1, 180)
            btn.Text = "↻ ПОВТОРИТЬ " .. caption
            return
        end
        -- Mark as running before entering an external chunk: a loader might yield forever.
        moduleStarted[key], moduleBusy[key] = true, false
        btn.Text = "▶ " .. caption .. " • ВЫПОЛНЯЕТСЯ"
        field.Text = "Код загружен. Передан на выполнение (эффект пока не проверен)."
        local okRun, result = pcall(fn)
        if not clean.alive then return end
        if okRun then
            btn.Text = "✓ " .. caption .. " • LUA ВЫПОЛНЕН"
            field.Text = "Внешний код завершился без Lua-ошибки. " ..
                "Работу функции в игре необходимо проверить отдельно."
            status(caption .. ": внешний Lua-код выполнен; эффект не подтверждён", "ok")
        else
            moduleStarted[key] = false
            btn.Text = "↻ ПОВТОРИТЬ " .. caption
            field.Text = "ОШИБКА ВЫПОЛНЕНИЯ: " .. tostring(result):sub(1, 185)
            status(caption .. ": ошибка запуска", "error")
            warn("[TSB v37/" .. key .. "] " .. tostring(result))
        end
    end)
end
clean:connect(UI.invis.Activated, function() runRemote("invis", UI.invis, UI.invisStatus, "INVIS") end)
clean:connect(UI.hkg.Activated, function() runRemote("hkg", UI.hkg, UI.hkgStatus, "HKG VOID") end)
clean:connect(UI.danger.Activated, function() runRemote("danger", UI.danger, UI.dangerStatus, "DANGER SCRIPT") end)

-- ==== RESPAWN / EXIT ======================================================
clean:connect(LocalPlayer.CharacterAdded, function(character)
    local follow = state.resumeFollow
    stopFollow(true)
    restoreSpeed()
    restoreRotation()
    exitSafe(false)
    exitCoord(false)
    monitorCharacter(character)
    if follow then
        task.spawn(function()
            local hum = character:WaitForChild("Humanoid", 9)
            local root = character:WaitForChild("HumanoidRootPart", 9)
            if clean.alive and state.resumeFollow and state.target and hum and root then
                startFollow()
            end
        end)
    end
end)
if LocalPlayer.Character then task.defer(monitorCharacter, LocalPlayer.Character) end

local function shutdown()
    if not clean.alive then return end
    clean.alive = false
    stopFollow(false)
    SET.aim = false
    restoreRotation()
    SET.speed = false
    restoreSpeed()
    SET.wall = false
    restoreWalls()
    stopVisual()
    exitSafe(false)
    exitCoord(false)
    if humHealthConn then pcall(function() humHealthConn:Disconnect() end) end
    if humDiedConn then pcall(function() humDiedConn:Disconnect() end) end
    for _, conn in ipairs(rosterConnections) do pcall(function() conn:Disconnect() end) end
    for name in pairs(clean.bindings) do clean:unbind(name) end
    for _, conn in ipairs(clean.connections) do pcall(function() conn:Disconnect() end) end
    for _, obj in ipairs(clean.instances) do pcall(function() obj:Destroy() end) end
    if env.__TSB_DELTA_V36_SHUTDOWN == shutdown then env.__TSB_DELTA_V36_SHUTDOWN = nil end
end
env.__TSB_DELTA_V36_SHUTDOWN = shutdown
clean:connect(closeBtn.Activated, shutdown)

rebuildRoster()
if SET.fps then startVisual() end
paintVisual()
status("v37 • выбери цель → START; AIM вращает персонажа", "ok")
