--[[
    TSB DELTA v35 | CLEAN REBUILD
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
for _, k in ipairs({"__TSB_DELTA_V35_SHUTDOWN", "__TSB_DELTA_V34_SHUTDOWN", "__TSB_DELTA_V33_SHUTDOWN",
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
pcall(function() RunService:UnbindFromRenderStep("TSB_DELTA_v35_Follow") end)
pcall(function() RunService:UnbindFromRenderStep("TSB_DELTA_v35_Aim") end)
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
    reset = false, wall = false, fps = true, culling = false, radius = 160,
}
local state = {
    target = nil, follow = false, resumeFollow = false, aimTarget = nil,
    safeActive = false, safeReturn = nil, safePart = nil,
    coordinate = false, coordReturn = nil, coordPart = nil,
    lastError = "", resetBusy = false, tpCount = 0,
}
local UI = {}
local C = {
    bg = Color3.fromRGB(15, 21, 33), panel = Color3.fromRGB(25, 34, 49),
    button = Color3.fromRGB(36, 55, 76), blue = Color3.fromRGB(26, 123, 159),
    green = Color3.fromRGB(17, 136, 100), red = Color3.fromRGB(137, 48, 68),
    white = Color3.fromRGB(235, 245, 252), muted = Color3.fromRGB(160, 186, 209),
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
        StarterGui:SetCore("SendNotification", {Title = "TSB DELTA v35", Text = tostring(text):sub(1, 160), Duration = 5})
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
if not uiParent then error("TSB v35: UI parent unavailable") end
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
gui.Name = "TSB_DELTA_v35"
gui.ResetOnSpawn = false
gui.DisplayOrder = 153
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = uiParent
local cam = workspace.CurrentCamera
local view = cam and cam.ViewportSize or Vector2.new(430, 780)
local W = math.clamp(view.X - 24, 240, 355)
local H = math.clamp(view.Y - 48, 300, 493)
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
corner(frame, 11)
create("UIStroke", frame, {Color = C.blue, Thickness = 1.3})
local titlebar = create("Frame", frame, {
    Name = "TitleBar", Size = UDim2.new(1, 0, 0, 33),
    BackgroundColor3 = Color3.fromRGB(23, 61, 82), BorderSizePixel = 0,
    Active = true,
})
local title = label(titlebar, "TSB DELTA v35  •  REBUILT", 0, 32, 12)
title.Size = UDim2.new(1, -79, 0, 33)
title.TextColor3 = Color3.fromRGB(142, 246, 255)
title.Font = Enum.Font.GothamBold
title.Active = true
local closeBtn = button(titlebar, "×", 1, 30, C.red)
closeBtn.Size = UDim2.fromOffset(30, 30)
closeBtn.Position = UDim2.new(1, -32, 0, 1)
closeBtn.TextSize = 18
local miniBtn = button(titlebar, "−", 1, 30, C.button)
miniBtn.Size = UDim2.fromOffset(30, 30)
miniBtn.Position = UDim2.new(1, -64, 0, 1)
miniBtn.TextSize = 18
UI.status = label(frame, "Выбери игрока в списке", 37, 25, 11)
UI.status.TextTruncate = Enum.TextTruncate.AtEnd
local tabs = create("Frame", frame, {
    Size = UDim2.new(1, -16, 0, 33), Position = UDim2.fromOffset(8, 65),
    BackgroundTransparency = 1,
})
local host = create("Frame", frame, {
    Size = UDim2.new(1, -16, 1, -108), Position = UDim2.fromOffset(8, 103),
    BackgroundTransparency = 1, ClipsDescendants = true,
})
local pages, tabsBtns = {}, {}
for i, name in ipairs({"ЦЕЛЬ", "ФУНКЦИИ", "ДОП."}) do
    local tb = create("TextButton", tabs, {
        Position = UDim2.new((i-1)/3, 2, 0, 0), Size = UDim2.new(1/3, -5, 1, 0),
        BackgroundColor3 = C.button, BorderSizePixel = 0, Text = name,
        TextColor3 = C.white, Font = Enum.Font.GothamBold, TextSize = 11,
    })
    corner(tb, 7)
    tabsBtns[i] = tb
    local pg = create("ScrollingFrame", host, {
        Name = "Page" .. i, BackgroundColor3 = C.panel, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = C.blue,
        Visible = i == 1, CanvasSize = UDim2.fromOffset(0, 760),
    })
    corner(pg, 6)
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

-- TARGET PAGE: fixed independent roster, never regenerates the outer controls.
label(pages[1], "ВЫБОР ИГРОКА", 8, 28, 12).TextColor3 = C.white
UI.refresh = button(pages[1], "↻ ОБНОВИТЬ ИГРОКОВ", 39, 30, C.blue)
UI.roster = create("ScrollingFrame", pages[1], {
    Name = "Roster", Position = UDim2.fromOffset(8, 78),
    Size = UDim2.new(1, -16, 0, 178), BackgroundColor3 = C.bg,
    BorderSizePixel = 0, ScrollBarThickness = 3,
    CanvasSize = UDim2.fromOffset(0, 0),
})
corner(UI.roster, 6)
UI.start = button(pages[1], "▶ START • FOLLOW", 266, 37, C.green)
UI.stop = button(pages[1], "■ STOP • FOLLOW", 310, 35, C.red)
UI.once = button(pages[1], "⚡ TP ONCE", 352, 35, C.blue)
label(pages[1], "ДИСТАНЦИЯ СЗАДИ (2.3–8 studs)", 392, 32)
UI.dist = input(pages[1], SET.distance, 425, "3.0")
UI.lead = button(pages[1], "", 467, 35)
UI.ss = button(pages[1], "", 510, 35)
label(pages[1], "Выбор игрока = один TP сразу. START = постоянное сопровождение. " ..
    "Реальность TP/ударов подтверждает только сервер игры.", 559, 75)
pages[1].CanvasSize = UDim2.fromOffset(0, 650)

-- FEATURES PAGE
UI.invis = button(pages[2], "▶ INVIS • AIRBORNITE", 12, 43, C.blue)
UI.invisStatus = label(pages[2], "INVIS не запускался", 62, 67)
UI.aim = button(pages[2], "", 146, 40)
label(pages[2], "AIM: выбери игрока, включи AIM, затем нажми ◉. " ..
    "Захват сохраняется при смене персонажа в дуэли.", 194, 60)
UI.speed = button(pages[2], "", 267, 37)
label(pages[2], "СКОРОСТЬ (8–120)", 309, 30)
UI.speedInput = input(pages[2], SET.speedValue, 345, "42")
UI.safe = button(pages[2], "", 394, 36)
UI.reset = button(pages[2], "", 438, 36)
UI.fps = button(pages[2], "", 485, 41, C.green)
UI.fpsStatus = label(pages[2], "FPS: инициализация...", 536, 82)
pages[2].CanvasSize = UDim2.fromOffset(0, 650)

-- EXTRA PAGE
UI.wall = button(pages[3], "", 13, 38)
UI.coord = button(pages[3], "TP К КООРДИНАТАМ Y=-10000", 59, 39, C.blue)
label(pages[3], "Координатный режим может привести к падению и откату сервером.", 105, 52)
UI.culling = button(pages[3], "", 173, 39)
label(pages[3], "РАДИУС ДЕКОРА (80–300)", 221, 30)
UI.radius = input(pages[3], SET.radius, 255, "160")
UI.hkg = button(pages[3], "▶ HKG VOID", 307, 40, C.blue)
UI.hkgStatus = label(pages[3], "Внешний модуль не запускался", 351, 58)
UI.danger = button(pages[3], "☠ DANGER SCRIPT", 427, 52, C.red)
UI.dangerStatus = label(pages[3], "Внешний модуль не запускался. Запускай на свой риск.", 488, 67)
label(pages[3], "Все внешние модули запускаются только по кнопке. " ..
    "FPS Ultra меняет только локальную графику.", 566, 64)
pages[3].CanvasSize = UDim2.fromOffset(0, 674)

-- Floating controls: single pair of global handlers rather than one per button.
local dock = button(gui, "≡", 0, 44, C.blue)
dock.Name = "Dock"
dock.Size = UDim2.fromOffset(42, 42)
dock.Position = UDim2.fromOffset(math.max(5, view.X - 55), math.floor(view.Y * 0.31))
dock.TextSize = 24
local aimHud = button(gui, "◎", 0, 44, C.button)
aimHud.Name = "AimSelect"
aimHud.Size = UDim2.fromOffset(45, 45)
aimHud.Position = UDim2.fromOffset(14, 112)
aimHud.TextSize = 27
aimHud.Visible = false
local hilite = clean:own(Instance.new("Highlight"))
hilite.Name = "TSB_DELTA_v35_AimHighlight"
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
    local v = screenView()
    local s = object.AbsoluteSize
    object.Position = UDim2.fromOffset(
        math.floor(math.clamp(point.X, 3, math.max(3, v.X - s.X - 3))),
        math.floor(math.clamp(point.Y, 3, math.max(3, v.Y - s.Y - 3))))
end
local dragging = nil
local dragged = false
local suppressed = setmetatable({}, {__mode = "k"})
for _, object in ipairs({titlebar, dock, aimHud}) do
    clean:connect(object.InputBegan, function(inputObj)
        local t = inputObj.UserInputType
        if t ~= Enum.UserInputType.MouseButton1 and t ~= Enum.UserInputType.Touch then return end
        local movable = object == titlebar and frame or object
        dragging = {
            handle = object, obj = movable, original = movable.AbsolutePosition,
            pointer = inputObj, origin = Vector2.new(inputObj.Position.X, inputObj.Position.Y),
        }
        dragged = false
    end)
end
clean:connect(UserInputService.InputChanged, function(inputObj)
    if not dragging then return end
    local d = dragging
    if d.pointer.UserInputType == Enum.UserInputType.Touch then
        if inputObj ~= d.pointer then return end
    elseif inputObj.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = Vector2.new(inputObj.Position.X, inputObj.Position.Y) - d.origin
    if delta.Magnitude > 7 then dragged = true end
    if dragged then moveInside(d.obj, d.original + delta) end
end)
clean:connect(UserInputService.InputEnded, function(inputObj)
    if not dragging then return end
    local d = dragging
    if d.pointer.UserInputType == Enum.UserInputType.Touch and inputObj ~= d.pointer then return end
    if d.pointer.UserInputType == Enum.UserInputType.MouseButton1 and
        inputObj.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if dragged then suppressed[d.handle] = os.clock() + 0.30 end
    dragging = nil
end)
local function wasDragged(object)
    return (suppressed[object] or 0) > os.clock()
end
local minimized = false
clean:connect(miniBtn.Activated, function()
    minimized = not minimized
    frame.Size = UDim2.fromOffset(minimized and 191 or W, minimized and 33 or H)
    for _, child in ipairs(frame:GetChildren()) do
        if child:IsA("GuiObject") and child ~= titlebar then child.Visible = not minimized end
    end
    miniBtn.Text = minimized and "+" or "−"
    moveInside(frame, frame.AbsolutePosition)
end)
clean:connect(dock.Activated, function()
    if wasDragged(dock) then return end
    frame.Visible = not frame.Visible
end)

-- ==== TARGET / TP =========================================================
local cachedPing, lastPing = 55, -1e9
local function pingMs()
    local now = os.clock()
    if now - lastPing < 1 then return cachedPing end
    lastPing = now
    local ok, val = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
    if ok and type(val) == "number" then cachedPing = math.clamp(val, 0, 400) end
    return cachedPing
end
local function desiredBehind()
    local _, _, their = getChar(state.target)
    if not their then return nil, "Цель не появилась / мертва" end
    local _, _, mine = getChar()
    if not mine then return nil, "Свой персонаж ещё не готов" end
    local rootPos = their.Position
    local humanoid = their.Parent and their.Parent:FindFirstChildOfClass("Humanoid")
    local torso = their.Parent and (their.Parent:FindFirstChild("UpperTorso") or their.Parent:FindFirstChild("Torso"))
    local ragdoll = false
    if humanoid then
        local s = humanoid:GetState()
        ragdoll = s == Enum.HumanoidStateType.Ragdoll or s == Enum.HumanoidStateType.FallingDown
            or s == Enum.HumanoidStateType.Physics or s == Enum.HumanoidStateType.PlatformStanding
    end
    if (ragdoll or not validPos(rootPos) or (torso and (torso.Position - rootPos).Magnitude > 7))
        and torso and validPos(torso.Position) then rootPos = torso.Position end
    if not validPos(rootPos) then return nil, "Недопустимая позиция цели" end
    local look = their.CFrame.LookVector
    local forward = Vector3.new(look.X, 0, look.Z)
    if forward.Magnitude < .15 or ragdoll then
        local away = rootPos - mine.Position
        forward = Vector3.new(away.X, 0, away.Z)
    end
    if forward.Magnitude < .05 then forward = Vector3.new(0, 0, -1) end
    forward = forward.Unit
    local lead = Vector3.zero
    if (SET.lead or SET.ss) and not ragdoll then
        local vel = their.AssemblyLinearVelocity
        local horizontal = Vector3.new(vel.X, 0, vel.Z)
        if horizontal.Magnitude > 85 then horizontal = horizontal.Unit * 85 end
        local horizon = math.clamp(pingMs() / 2000 + 0.012, .012, SET.ss and .115 or .085)
        lead = horizontal * horizon
        local maxLead = math.min(2.5, SET.distance * .7)
        if lead.Magnitude > maxLead then lead = lead.Unit * maxLead end
        if SET.ss then
            local omega = their.AssemblyAngularVelocity.Y
            if math.abs(omega) < 16 then
                local turn = CFrame.Angles(0, omega * horizon, 0):VectorToWorldSpace(forward)
                local horizontalTurn = Vector3.new(turn.X, 0, turn.Z)
                if horizontalTurn.Magnitude > .05 then forward = horizontalTurn.Unit end
            end
        end
    end
    local goal = rootPos + lead - forward * SET.distance
    goal = Vector3.new(goal.X, rootPos.Y, goal.Z)
    if not validPos(goal) then return nil, "Расчёт TP вне карты" end
    local face = Vector3.new(rootPos.X + lead.X, goal.Y, rootPos.Z + lead.Z)
    if (goal - face).Magnitude < .15 then return nil, "Позиции совпадают" end
    return CFrame.lookAt(goal, face)
end
local corrections, previousTp, previousTpAt = 0, nil, 0
local function teleport(force)
    if not clean.alive or state.safeActive or state.coordinate then return false, "Активна другая зона" end
    if not state.target or state.target.Parent ~= Players then return false, "Выбери игрока" end
    local char, hum, root = getChar()
    if not char or not root then return false, "Персонаж недоступен" end
    if root.Anchored then return false, "Персонаж закреплён игрой" end
    local goal, reason = desiredBehind()
    if not goal then return false, reason end
    local offset = (root.Position - goal.Position).Magnitude
    local aligned = root.CFrame.LookVector:Dot(goal.LookVector) > .998
    if not force and offset < .18 and aligned then return true, "у цели" end
    local ok, err = pcall(function() char:PivotTo(goal) end)
    if not ok or (root.Position - goal.Position).Magnitude > .7 then
        ok, err = pcall(function() root.CFrame = goal end)
    end
    if not ok or (root.Position - goal.Position).Magnitude > 1 then
        return false, "Локальный TP не принят: " .. tostring(err):sub(1, 60)
    end
    -- Only clear runaway velocity for large jumps; preserving local momentum
    -- during close-range follow prevents the dash/attack freeze from v34.
    if force and offset > 11 then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
    previousTp, previousTpAt = goal.Position, os.clock()
    state.tpCount = state.tpCount + 1
    return true, "позиция изменена локально"
end
local function rotateToTarget(plr)
    local _, hum, root = getChar()
    local _, _, enemyRoot = getChar(plr)
    if not root or not enemyRoot or root.Anchored or hum.Sit then return end
    local head = enemyRoot.Parent:FindFirstChild("UpperTorso") or enemyRoot.Parent:FindFirstChild("Torso")
    local pos = head and head.Position or enemyRoot.Position
    local look = Vector3.new(pos.X, root.Position.Y, pos.Z)
    if (look - root.Position).Magnitude > .5 then
        pcall(function() root.CFrame = CFrame.lookAt(root.Position, look) end)
    end
end
local function paintFollow()
    UI.start.BackgroundColor3 = state.follow and C.green or C.button
    UI.start.Text = state.follow and "▶ FOLLOW • АКТИВНО" or "▶ START • FOLLOW"
end
local function stopFollow(preserve)
    if not preserve then state.resumeFollow = false end
    state.follow = false
    clean:unbind("TSB_DELTA_v35_Follow")
    paintFollow()
end
local function followStep()
    if not clean.alive or not state.follow then return end
    if not state.target or state.target.Parent ~= Players then
        stopFollow(false)
        status("Цель вышла из игры", "error")
        return
    end
    local now = os.clock()
    -- This detects repeated large server corrections, without an extra task.
    if previousTp and now - previousTpAt < .5 then
        local _, _, myRoot = getChar()
        local goal = desiredBehind()
        if myRoot and goal and (myRoot.Position - previousTp).Magnitude > 18
            and (myRoot.Position - goal.Position).Magnitude > 16 then
            corrections = corrections + 1
            previousTp = nil
        end
    end
    local ok, msg = teleport(false)
    if now - (state.lastFollowStatus or 0) > .85 then
        state.lastFollowStatus = now
        if corrections >= 4 then status("Сервер исправляет позицию — реальный TP может не проходить", "error")
        else status(ok and ("FOLLOW: позиционирование активно (" .. state.tpCount .. ")")
            or ("FOLLOW: " .. tostring(msg)), ok and "ok" or "error") end
    end
end
local function startFollow()
    if not state.target then status("Сначала выбери игрока", "error"); return end
    if state.coordinate then status("Сначала вернись из координатной зоны", "error"); return end
    state.follow, state.resumeFollow = true, true
    corrections, previousTp = 0, nil
    local ok, msg = teleport(true)
    status(ok and "FOLLOW запущен: " .. msg or "FOLLOW ожидает: " .. tostring(msg), ok and "ok" or "error")
    clean:bind("TSB_DELTA_v35_Follow", Enum.RenderPriority.Character.Value + 2, function()
        local success, err = pcall(followStep)
        if not success then
            if os.clock() - (state.lastFollowError or 0) > 2 then
                state.lastFollowError = os.clock()
                warn("[TSB v35 FOLLOW] " .. tostring(err))
            end
        end
    end)
    paintFollow()
end

-- ==== ROSTER / TARGET SELECTION ==========================================
local entries = {}
local rosterConnections = {}
local function rebuildRoster()
    for _, conn in ipairs(rosterConnections) do pcall(function() conn:Disconnect() end) end
    rosterConnections = {}
    if not clean.alive then return end
    for _, child in ipairs(UI.roster:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    entries = {}
    local candidates = Players:GetPlayers()
    table.sort(candidates, function(a, b) return a.DisplayName:lower() < b.DisplayName:lower() end)
    local y = 4
    for _, enemy in ipairs(candidates) do
        if enemy ~= LocalPlayer then
            local b = button(UI.roster, "", y, 43, enemy == state.target and C.green or C.button)
            b.Name = "Target_" .. tostring(enemy.UserId)
            b.Text = "  " .. enemy.DisplayName .. "   (@" .. enemy.Name .. ")"
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.TextSize = 11
            entries[enemy.UserId] = b
            rosterConnections[#rosterConnections+1] = b.Activated:Connect(function()
                if not clean.alive or enemy.Parent ~= Players then return end
                state.target = enemy
                if SET.aim then
                    state.aimTarget = enemy
                    aimHud.Text = "●"
                    aimHud.BackgroundColor3 = C.green
                end
                corrections, previousTp = 0, nil
                for _, other in pairs(entries) do other.BackgroundColor3 = C.button end
                b.BackgroundColor3 = C.green
                local ok, reason = teleport(true)
                status(ok and ("Цель: @" .. enemy.Name .. " • TP применён локально")
                    or ("Цель @" .. enemy.Name .. ": " .. tostring(reason)), ok and "ok" or "error")
            end)
            y = y + 49
        end
    end
    if y == 4 then label(UI.roster, "В этом сервере нет других игроков", 4, 54) end
    UI.roster.CanvasSize = UDim2.fromOffset(0, y + 8)
end
clean:connect(UI.refresh.Activated, rebuildRoster)
clean:connect(Players.PlayerAdded, function()
    task.defer(rebuildRoster)
end)
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
    end
    task.defer(rebuildRoster)
end)
clean:connect(UI.start.Activated, startFollow)
-- Additional immediate positioning on an attack click (PC only).
clean:connect(UserInputService.InputBegan, function(inputObj, processed)
    if state.follow and not processed and inputObj.UserInputType == Enum.UserInputType.MouseButton1 then
        pcall(teleport, true)
    end
end)
clean:connect(UI.stop.Activated, function() stopFollow(false); status("FOLLOW остановлен") end)
clean:connect(UI.once.Activated, function()
    local ok, reason = teleport(true)
    status(ok and "TP ONCE: позиция изменена локально" or ("TP ONCE: " .. tostring(reason)), ok and "ok" or "error")
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

-- ==== AIM / DUEL CAMERA ===================================================
local savedRotate, savedHum = nil, nil
local function restoreRotation()
    if savedHum and savedHum.Parent and savedRotate ~= nil then
        pcall(function() savedHum.AutoRotate = savedRotate end)
    end
    savedHum, savedRotate = nil, nil
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
local function aimPoint(plr)
    local _, _, root = getChar(plr)
    if not root then return end
    local model = root.Parent
    local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
    return torso and torso.Position or root.Position
end
local function pickTarget()
    local camera = workspace.CurrentCamera
    if not camera then return nil end
    local center = camera.ViewportSize * .5
    local radius = math.min(center.X, center.Y) * .55
    local winner, closest = nil, radius
    for _, candidate in ipairs(Players:GetPlayers()) do
        if candidate ~= LocalPlayer then
            local pos = aimPoint(candidate)
            if pos then
                local at, onScreen = camera:WorldToViewportPoint(pos)
                if onScreen and at.Z > 0 then
                    local delta = (Vector2.new(at.X, at.Y) - center).Magnitude
                    if delta < closest then winner, closest = candidate, delta end
                end
            end
        end
    end
    -- For duels with camera cutscenes, fall back to the explicitly chosen player.
    if not winner and state.target and aimPoint(state.target) then return state.target end
    return winner
end
local function aimTick()
    if not clean.alive or not SET.aim then return end
    local target = state.aimTarget
    if not target or target.Parent ~= Players then return end
    local pos = aimPoint(target)
    if not pos then
        if hilite.Enabled then hilite.Enabled = false end
        return -- do not drop lock through respawn, especially during duels
    end
    if hilite.Adornee ~= target.Character or not hilite.Enabled then
        hilite.Adornee, hilite.Enabled = target.Character, true
    end
    local camera = workspace.CurrentCamera
    if camera and camera.CFrame then
        local origin = camera.CFrame.Position
        if (pos - origin).Magnitude > .1 then
            camera.CFrame = CFrame.lookAt(origin, pos)
        end
    end
    local _, hum = getChar()
    if hum then
        if hum ~= savedHum then
            restoreRotation()
            savedHum, savedRotate = hum, hum.AutoRotate
        end
        if hum.AutoRotate then hum.AutoRotate = false end
    end
    if not state.follow then rotateToTarget(target) end
end
local function switchAim(on)
    SET.aim = on == true
    if SET.aim and not state.aimTarget then
        -- One tap really enables AIM: first honor the roster selection,
        -- otherwise grab the closest on-screen opponent automatically.
        state.aimTarget = (state.target and aimPoint(state.target) and state.target) or pickTarget()
    end
    if not SET.aim then
        state.aimTarget = nil
        clean:unbind("TSB_DELTA_v35_Aim")
        restoreRotation()
    else
        clean:bind("TSB_DELTA_v35_Aim", Enum.RenderPriority.Last.Value - 1, function()
            local ok, err = pcall(aimTick)
            if not ok and os.clock() - (state.lastAimError or 0) > 3 then
                state.lastAimError = os.clock()
                warn("[TSB v35 AIM] " .. tostring(err))
            end
        end)
    end
    aimUi()
end
clean:connect(UI.aim.Activated, function()
    switchAim(not SET.aim)
    status(SET.aim and (state.aimTarget and ("AIM: захвачен @" .. state.aimTarget.Name)
        or "AIM включён • выбери игрока или нажми ◎") or "AIM выключен")
end)
clean:connect(aimHud.Activated, function()
    if not SET.aim or wasDragged(aimHud) then return end
    if state.aimTarget then
        state.aimTarget = nil
        restoreRotation()
        status("AIM: цель снята")
    else
        state.aimTarget = pickTarget()
        status(state.aimTarget and ("AIM захватил @" .. state.aimTarget.Name)
            or "AIM: наведи центр экрана на игрока или выбери его", state.aimTarget and "ok" or "error")
    end
    aimUi()
end)
aimUi()

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
        Name = "TSB_v35_LocalSafeFloor", Size = Vector3.new(24, 2, 24),
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
    humHealthConn = clean:connect(hum.HealthChanged, function(health)
        if SET.safe and not state.safeActive and not state.coordinate
            and health > 0 and health <= SET.safeThreshold then pcall(enterSafe) end
    end)
    humDiedConn = clean:connect(hum.Died, function()
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
        Name = "TSB_v35_CoordFloor", Size = Vector3.new(26, 2, 26),
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
    objects = 0, skipped = 0, fx = 0, conn = nil,
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
    visual.objects, visual.fx = 0, 0
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
        if visual.running then pcall(processVisual, obj) end
    end)
    task.spawn(scanVisual, token)
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
        task.wait(3)
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
            warn("[TSB v35/" .. key .. "] " .. tostring(errorMsg))
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
            warn("[TSB v35/" .. key .. "] " .. tostring(result))
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
    if env.__TSB_DELTA_V35_SHUTDOWN == shutdown then env.__TSB_DELTA_V35_SHUTDOWN = nil end
end
env.__TSB_DELTA_V35_SHUTDOWN = shutdown
clean:connect(closeBtn.Activated, shutdown)

rebuildRoster()
if SET.fps then startVisual() end
paintVisual()
status("v35 готов • цель → TP сразу • START → сопровождение", "ok")
