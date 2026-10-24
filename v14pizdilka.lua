-- TSB DELTA CLEAN v19 | compact, mobile-first, no external loaders.
-- Client-side actions are best-effort; the server controls combat, physics and cooldowns.
-- Controls: instant target TP / optional follow / two-skill random cycle /
-- speed assist (also while carrying a bin) / normal trash pickup and throw.
-- No player identity, private configuration, or external URLs are hardcoded.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local CFG = {
    behind = 4, speed = 42, speedOn = false, followInterval = 0.045,
    cd = {17, 20}, castGap = 1.6,
    pickupWait = 1.0, trashRetry = 1.4,
    -- Only a FALLBACK. Use "Запомнить центр" at the actual center for precision.
    center = Vector3.new(0, 5, 0), centerCalibrated = false,
}

-- Clean old instances before rebuilding the interface. Do not leave duplicate loops.
local env
pcall(function() if type(getgenv) == "function" then env = getgenv() end end)
if env then
    -- Shut down this version and the previous TSB release without copying
    -- any former project branding into the rebuilt script.
    for key, callback in pairs(env) do
        if type(key) == "string" and type(callback) == "function" and
            (key == "__TSB_DELTA_V19_SHUTDOWN" or key:sub(-9) == "_TSB_EXIT") then
            pcall(callback)
        end
    end
end
local live = true
local connections = {}
local function listen(signal, callback)
    local connection = signal:Connect(callback)
    connections[#connections + 1] = connection
    return connection
end
local function validVector(v)
    return v and v.X == v.X and v.Y == v.Y and v.Z == v.Z
        and math.abs(v.X) < 100000 and math.abs(v.Y) < 100000
        and math.abs(v.Z) < 100000
end
local function ownHumanoid()
    local c = LocalPlayer.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function ownRoot()
    local c = LocalPlayer.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function enemyRoot(p)
    if not p or p == LocalPlayer or not p.Parent then return nil end
    local c = p.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    local r = c and c:FindFirstChild("HumanoidRootPart")
    if not h or h.Health <= 0 or not r or not validVector(r.Position) then return nil end
    return r
end
local function able()
    local h, r = ownHumanoid(), ownRoot()
    if not live or not h or h.Health <= 0 or not r or r.Anchored then return false end
    local state = h:GetState()
    return not h.Sit and state ~= Enum.HumanoidStateType.Dead
        and state ~= Enum.HumanoidStateType.Ragdoll
        and state ~= Enum.HumanoidStateType.FallingDown
        and state ~= Enum.HumanoidStateType.PlatformStanding
        and state ~= Enum.HumanoidStateType.Physics
end
local function pivot(cf)
    local char, r = LocalPlayer.Character, ownRoot()
    if not char or not r or not able() or not validVector(cf.Position) then return false end
    local success = pcall(function()
        char:PivotTo(cf)
        r.AssemblyLinearVelocity = Vector3.zero
        r.AssemblyAngularVelocity = Vector3.zero
    end)
    return success
end
local function behindCF(p)
    local target = enemyRoot(p)
    if not target then return nil end
    local pos = target.Position
    local char = p.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local look = target.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    local state = hum and hum:GetState()
    local ragdolled = state == Enum.HumanoidStateType.Ragdoll
        or state == Enum.HumanoidStateType.FallingDown
        or state == Enum.HumanoidStateType.Physics
    if ragdolled and char then
        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
            or char:FindFirstChild("LowerTorso")
        if torso and validVector(torso.Position) then pos = torso.Position end
    end
    if ragdolled or flat.Magnitude < 0.1 then
        local me = ownRoot()
        local delta = me and (pos - me.Position) or Vector3.new(0, 0, -1)
        flat = Vector3.new(delta.X, 0, delta.Z)
    end
    if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
    local destination = pos - flat.Unit * CFG.behind
    destination = Vector3.new(destination.X, pos.Y, destination.Z)
    if ragdolled then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {char, LocalPlayer.Character}
        local hit = workspace:Raycast(destination + Vector3.new(0, 7, 0),
            Vector3.new(0, -23, 0), params)
        if hit then destination = Vector3.new(destination.X,
            math.max(destination.Y, hit.Position.Y + 3), destination.Z) end
    end
    if not validVector(destination) or
        destination.Y <= workspace.FallenPartsDestroyHeight + 10 then return nil end
    return CFrame.lookAt(destination, Vector3.new(pos.X, destination.Y, pos.Z))
end
local function teleportPlayer(p)
    local cf = behindCF(p)
    return cf ~= nil and pivot(cf)
end
local lastRandomId
local function randomEnemy()
    local candidates, fresh = {}, {}
    for _, p in ipairs(Players:GetPlayers()) do
        if enemyRoot(p) then
            candidates[#candidates + 1] = p
            if p.UserId ~= lastRandomId then fresh[#fresh + 1] = p end
        end
    end
    local pool = #fresh > 0 and fresh or candidates
    if #pool == 0 then return nil end
    local p = pool[math.random(1, #pool)]
    lastRandomId = p.UserId
    return p
end

-- Ground probe for the center: never build parts/platforms or disable collisions.
local lookedForCenter = false
local centerDummy
local function centerCFrame()
    -- The central training dummy is a useful landmark on the original TSB map.
    -- If it is absent (streaming / map update), origin fallback or manual marker applies.
    if not CFG.centerCalibrated and not lookedForCenter then
        lookedForCenter = true
        local dummy = workspace:FindFirstChild("Weakest Dummy", true)
        if dummy then
            local part = dummy:IsA("BasePart") and dummy
                or dummy:IsA("Model") and
                    (dummy.PrimaryPart or dummy:FindFirstChild("HumanoidRootPart")
                     or dummy:FindFirstChildWhichIsA("BasePart", true))
            if part and validVector(part.Position) then
                centerDummy = dummy
                CFG.center = part.Position + Vector3.new(7, 0, 0)
            end
        end
    end
    local r, h = ownRoot(), ownHumanoid()
    if not r or not h then return nil end
    local point = CFG.center
    local x, z = point.X, point.Z
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local excluded = {}
    if LocalPlayer.Character then excluded[#excluded + 1] = LocalPlayer.Character end
    if centerDummy then excluded[#excluded + 1] = centerDummy end
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character and p ~= LocalPlayer then excluded[#excluded + 1] = p.Character end
    end
    params.FilterDescendantsInstances = excluded
    local baseY = CFG.centerCalibrated and point.Y or r.Position.Y
    local hit = workspace:Raycast(Vector3.new(x, baseY + 24, z), Vector3.new(0, -115, 0), params)
    local y = hit and (hit.Position.Y + h.HipHeight + r.Size.Y * 0.5 + 0.45) or baseY
    if y <= workspace.FallenPartsDestroyHeight + 8 then return nil end
    local destination = Vector3.new(x, y, z)
    return validVector(destination) and CFrame.new(destination) or nil
end
local function teleportCenter()
    local cf = centerCFrame()
    return cf and pivot(cf) or false
end

-- GUI helpers. Avoid expensive avatars and heavyweight effect animations on mobile.
for _, container in ipairs({CoreGui, LocalPlayer:FindFirstChildOfClass("PlayerGui")}) do
    if container then
        pcall(function()
            for _, item in ipairs(container:GetChildren()) do
                if item:IsA("ScreenGui") and
                    (item.Name == "TSB_Delta_Clean" or item.Name:match("TSBv1[678]$")) then
                    item:Destroy()
                end
            end
        end)
    end
end
local gui = Instance.new("ScreenGui")
gui.Name = "TSB_Delta_Clean"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.DisplayOrder = 120
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local okay = pcall(function() gui.Parent = CoreGui end)
if not okay then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end

local function make(class, properties, parent)
    local obj = Instance.new(class)
    for k, v in pairs(properties) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local C = {
    bg = Color3.fromRGB(18, 24, 35), panel = Color3.fromRGB(30, 40, 55),
    edge = Color3.fromRGB(59, 83, 106), blue = Color3.fromRGB(49, 122, 175),
    green = Color3.fromRGB(26, 136, 98), red = Color3.fromRGB(148, 62, 67),
    muted = Color3.fromRGB(168, 194, 213), text = Color3.fromRGB(237, 248, 255),
}
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(420, 720)
local width = math.max(255, math.min(320, viewport.X - 18))
local height = math.max(295, math.min(408, viewport.Y - 35))
local frame = make("Frame", {
    Size = UDim2.fromOffset(width, height),
    Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true,
}, gui)
make("UICorner", {CornerRadius = UDim.new(0, 10)}, frame)
make("UIStroke", {Color = C.edge, Thickness = 1.4}, frame)
local titleBar = make("Frame", {
    Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = C.panel,
    BorderSizePixel = 0, Active = true,
}, frame)
make("UICorner", {CornerRadius = UDim.new(0, 8)}, titleBar)
make("TextLabel", {
    Size = UDim2.new(1, -78, 1, 0), Position = UDim2.fromOffset(10, 0),
    BackgroundTransparency = 1, Text = "TSB  ·  DELTA v19",
    Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = C.text,
}, titleBar)
local function button(parent, label, color, px, py, w, h)
    local b = make("TextButton", {
        Text = label, TextColor3 = C.text, Font = Enum.Font.GothamBold,
        TextSize = 12, BorderSizePixel = 0, BackgroundColor3 = color or C.blue,
        Position = UDim2.fromOffset(px, py), Size = UDim2.fromOffset(w, h),
        AutoButtonColor = true,
    }, parent)
    make("UICorner", {CornerRadius = UDim.new(0, 6)}, b)
    return b
end
local closeBtn = button(titleBar, "×", C.red, width - 35, 4, 30, 30)
local minBtn = button(titleBar, "−", C.edge, width - 69, 4, 30, 30)
local status = make("TextLabel", {
    Size = UDim2.new(1, -14, 0, 25), Position = UDim2.fromOffset(7, 40),
    Text = "Выбери игрока — TP выполняется сразу",
    BackgroundTransparency = 1, TextColor3 = C.muted,
    TextWrapped = true, Font = Enum.Font.Gotham, TextSize = 11,
}, frame)
local tabs = make("Frame", {Position = UDim2.fromOffset(7, 68),
    Size = UDim2.new(1, -14, 0, 31), BackgroundTransparency = 1}, frame)
local tabNames = {"ЦЕЛЬ", "ЦИКЛ", "СКОРОСТЬ"}
local pages, tabButtons = {}, {}
local tabGap = 4
local tabWidth = math.floor((width - 14 - tabGap * 2) / 3)
for i, name in ipairs(tabNames) do
    tabButtons[i] = button(tabs, name, C.panel, (i - 1) * (tabWidth + tabGap), 0, tabWidth, 30)
    pages[i] = make("ScrollingFrame", {
        Position = UDim2.fromOffset(7, 104),
        Size = UDim2.new(1, -14, 1, -111),
        ScrollBarThickness = 3, BorderSizePixel = 0,
        BackgroundColor3 = C.bg, CanvasSize = UDim2.fromOffset(0, 0),
        Visible = i == 1, ScrollingDirection = Enum.ScrollingDirection.Y,
    }, frame)
end
local function showPage(which)
    for i = 1, #pages do
        pages[i].Visible = i == which
        tabButtons[i].BackgroundColor3 = i == which and C.blue or C.panel
    end
end
for i, b in ipairs(tabButtons) do
    listen(b.Activated, function() showPage(i) end)
end
showPage(1)
local inner = width - 20
local half = math.floor((inner - 7) / 2)
local function note(parent, message, y, h)
    return make("TextLabel", {
        Position = UDim2.fromOffset(5, y), Size = UDim2.fromOffset(inner, h),
        Text = message, TextWrapped = true, TextColor3 = C.muted,
        BackgroundTransparency = 1, Font = Enum.Font.Gotham,
        TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
end
local function numeric(parent, label, value, x, y, fieldWidth)
    local group = make("Frame", {Position = UDim2.fromOffset(x, y),
        Size = UDim2.fromOffset(fieldWidth, 35), BackgroundColor3 = C.panel,
        BorderSizePixel = 0}, parent)
    make("UICorner", {CornerRadius = UDim.new(0, 6)}, group)
    make("TextLabel", {Position = UDim2.fromOffset(6, 0), Size = UDim2.new(0.6, -5, 1, 0),
        BackgroundTransparency = 1, Text = label, TextColor3 = C.muted,
        TextSize = 11, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left}, group)
    return make("TextBox", {Position = UDim2.new(0.6, 0, 0, 3),
        Size = UDim2.new(0.4, -4, 1, -6), Text = tostring(value),
        TextColor3 = C.text, BackgroundColor3 = C.bg, BorderSizePixel = 0,
        ClearTextOnFocus = false, Font = Enum.Font.GothamBold, TextSize = 12}, group)
end
local function readNumber(box, fallback, low, high)
    local n = tonumber(box.Text)
    if not n or n ~= n or n == math.huge or n == -math.huge then n = fallback end
    n = math.clamp(math.floor(n * 10 + 0.5) / 10, low, high)
    box.Text = tostring(n)
    return n
end
local function paintToggle(b, isOn, on, off)
    b.Text = isOn and on or off
    b.BackgroundColor3 = isOn and C.green or C.red
end

-- PAGE 1: target list / instant teleport / optional follow.
note(pages[1], "Нажми на игрока для мгновенного TP за спину.", 3, 35)
local list = make("ScrollingFrame", {
    Position = UDim2.fromOffset(5, 44), Size = UDim2.fromOffset(inner, 137),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, ScrollBarThickness = 3,
    CanvasSize = UDim2.fromOffset(0, 0),
}, pages[1])
make("UICorner", {CornerRadius = UDim.new(0, 6)}, list)
local layout = make("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, list)
local followBtn = button(pages[1], "СЛЕЖЕНИЕ: ВЫКЛ", C.red, 5, 190, inner, 34)
local onceBtn = button(pages[1], "TP К ЦЕЛИ", C.blue, 5, 230, half, 33)
local randomBtn = button(pages[1], "TP СЛУЧАЙНО", C.blue, 12 + half, 230, inner - half - 7, 33)
local distBox = numeric(pages[1], "Отступ", CFG.behind, 5, 272, inner)
note(pages[1], "Слежение поддерживает позицию за целью. Ручное перемещение рядом с целью сохраняется.", 312, 45)
pages[1].CanvasSize = UDim2.fromOffset(0, 370)

-- PAGE 2: automatic random-target two-ability loop.
local cycleStart = button(pages[2], "▶ ЗАПУСТИТЬ ЦИКЛ", C.green, 5, 8, half, 36)
local cycleStop = button(pages[2], "■ ОСТАНОВИТЬ", C.red, 12 + half, 8, inner - half - 7, 36)
local cd1Box = numeric(pages[2], "CD 1", CFG.cd[1], 5, 51, half)
local cd2Box = numeric(pages[2], "CD 2", CFG.cd[2], 12 + half, 51, inner - half - 7)
local cycleInfo = note(pages[2], "Цикл остановлен.", 95, 55)
cycleInfo.TextColor3 = C.text
local setCenter = button(pages[2], "◎ ЗАПОМНИТЬ ЦЕНТР", C.blue, 5, 160, inner, 34)
local goCenter = button(pages[2], "TP В ЦЕНТР", C.panel, 5, 200, inner, 32)
local centerLabel = note(pages[2], "Центр: поиск центрального манекена; запасной вариант X=0, Z=0. Точную точку можно сохранить выше.", 245, 57)
note(pages[2], "Алгоритм: случайный игрок → навык 1/2 → оба на CD → TP в центр → ожидание ОБОИХ → новый игрок.", 310, 61)
pages[2].CanvasSize = UDim2.fromOffset(0, 384)

-- PAGE 3: movement and trash; NO distance-throw slider or physics impulse.
local speedBtn = button(pages[3], "УСКОРЕНИЕ: ВЫКЛ", C.red, 5, 9, inner, 38)
local speedBox = numeric(pages[3], "Скорость", CFG.speed, 5, 57, inner)
note(pages[3], "Ускорение остаётся включённым с мусоркой в руках. Рывки и прыжки не притормаживаются.", 105, 63)
local trashAutoBtn = button(pages[3], "МУСОР: АВТО ВЫКЛ", C.red, 5, 176, inner, 37)
local pickupBtn = button(pages[3], "ВЗЯТЬ МУСОР И ВЕРНУТЬСЯ", C.blue, 5, 220, inner, 39)
local trashInfo = note(pages[3], "Обычный бросок M1, без искусственной дальности.", 271, 54)
note(pages[3], "Физика и ограничения передвижения могут корректироваться сервером игры.", 335, 43)
pages[3].CanvasSize = UDim2.fromOffset(0, 392)

local rowConnections = {}
local selected, following = nil, false
local cycle = {on = false, generation = 0, ready = {0, 0}, phase = "idle", centerWait = false, fails = 0}
local trash = {on = false, generation = 0, busy = false, indexed = {}, exclude = {}, scanAt = -1000}
local originalSpeed, boundHumanoid
local lastFollow = 0
local function setStatus(msg)
    if live and status.Parent then status.Text = msg end
end
local function setCycleStatus(msg)
    if live and cycleInfo.Parent and cycleInfo.Text ~= msg then cycleInfo.Text = msg end
end
local function stopFollow()
    following = false
    paintToggle(followBtn, false, "СЛЕЖЕНИЕ: ВКЛ", "СЛЕЖЕНИЕ: ВЫКЛ")
end
local function stopCycle()
    cycle.on = false
    cycle.generation = cycle.generation + 1
    cycle.phase = "idle"
    cycle.centerWait = false
    cycleStart.BackgroundColor3 = C.green
    setCycleStatus("Цикл остановлен.")
end
local function stopTrash()
    trash.on = false
    trash.generation = trash.generation + 1
    -- The active pickup operation will exit on its next cancellation check.
    paintToggle(trashAutoBtn, false, "МУСОР: АВТО ВКЛ", "МУСОР: АВТО ВЫКЛ")
end
local function setSelected(p)
    if not p or p == LocalPlayer then return end
    stopCycle()
    stopFollow()
    selected = p
    -- No yielding, avatar requests, list refresh or debounce before this TP.
    local ok = teleportPlayer(p)
    setStatus(ok and "TP отправлен мгновенно." or "Цель выбрана; TP сейчас недоступен.")
end
local function refreshList()
    if not live then return end
    for _, connection in ipairs(rowConnections) do connection:Disconnect() end
    rowConnections = {}
    for _, child in ipairs(list:GetChildren()) do
        if child:IsA("GuiButton") then child:Destroy() end
    end
    local others = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then others[#others + 1] = p end
    end
    table.sort(others, function(a, b) return a.Name:lower() < b.Name:lower() end)
    for i, p in ipairs(others) do
        local b = make("TextButton", {
            Name = "TargetRow", LayoutOrder = i, Size = UDim2.new(1, -9, 0, 30),
            BorderSizePixel = 0, Font = Enum.Font.Gotham,
            TextSize = 12, TextColor3 = C.text, TextTruncate = Enum.TextTruncate.AtEnd,
            TextXAlignment = Enum.TextXAlignment.Left,
            Text = "  " .. tostring(p.DisplayName),
            BackgroundColor3 = selected == p and C.green or C.bg,
        }, list)
        make("UICorner", {CornerRadius = UDim.new(0, 5)}, b)
        rowConnections[#rowConnections + 1] = b.Activated:Connect(function()
            setSelected(p)
            for _, row in ipairs(list:GetChildren()) do
                if row:IsA("GuiButton") then row.BackgroundColor3 = C.bg end
            end
            if b.Parent then b.BackgroundColor3 = C.green end
        end)
    end
    list.CanvasSize = UDim2.fromOffset(0, #others * 33 + 6)
    if #others == 0 then setStatus("Других игроков пока нет.") end
end
refreshList()
listen(Players.PlayerAdded, function() refreshList() end)
listen(Players.PlayerRemoving, function(p)
    if selected == p then selected = nil; stopFollow() end
    if cycle.on and cycle.phase == "attack" then cycle.phase = "search" end
    task.defer(function() if live then refreshList() end end)
end)
listen(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    if live then list.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 5) end
end)
listen(followBtn.Activated, function()
    if not following then
        if not selected or not enemyRoot(selected) then setStatus("Сначала выбери живую цель."); return end
        stopCycle()
        following = true
        teleportPlayer(selected)
    else following = false end
    paintToggle(followBtn, following, "СЛЕЖЕНИЕ: ВКЛ", "СЛЕЖЕНИЕ: ВЫКЛ")
end)
listen(onceBtn.Activated, function()
    if selected and teleportPlayer(selected) then setStatus("TP выполнен.")
    else setStatus("Нет доступной выбранной цели.") end
end)
listen(randomBtn.Activated, function()
    local p = randomEnemy()
    if p then setSelected(p); refreshList() else setStatus("Нет доступных игроков.") end
end)
listen(distBox.FocusLost, function()
    CFG.behind = readNumber(distBox, CFG.behind, 2.5, 8)
end)

-- Speed: MoveDirection first, PlayerModule's joystick vector as fallback when
-- a carried object suppresses Humanoid movement. Never steer an idle character.
local controls
local lastControlsProbe = -100
local function getControls()
    if controls then return controls end
    if os.clock() - lastControlsProbe < 1 then return nil end
    lastControlsProbe = os.clock()
    pcall(function()
        local scripts = LocalPlayer:FindFirstChild("PlayerScripts")
        local module = scripts and scripts:FindFirstChild("PlayerModule")
        if module then controls = require(module):GetControls() end
    end)
    return controls
end
local function movementDirection(h)
    if UserInputService:GetFocusedTextBox() then return Vector3.zero end
    local d = h.MoveDirection
    d = Vector3.new(d.X, 0, d.Z)
    if d.Magnitude > 0.045 then return d end
    local mobileControls = getControls()
    if mobileControls then
        local ok, raw = pcall(function() return mobileControls:GetMoveVector() end)
        if ok and raw and raw.Magnitude > 0.05 then
            local cam = workspace.CurrentCamera
            if cam then
                local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
                local forward = Vector3.new(look.X, 0, look.Z)
                local side = Vector3.new(right.X, 0, right.Z)
                if forward.Magnitude > 0.01 and side.Magnitude > 0.01 then
                    local result = side.Unit * raw.X - forward.Unit * raw.Z
                    if result.Magnitude > 0.05 then return result end
                end
            end
        end
    end
    return Vector3.zero
end
local function releaseSpeed()
    if boundHumanoid and boundHumanoid.Parent and originalSpeed then
        pcall(function()
            if math.abs(boundHumanoid.WalkSpeed - CFG.speed) < 0.2 then
                boundHumanoid.WalkSpeed = originalSpeed
            end
        end)
    end
    boundHumanoid, originalSpeed = nil, nil
end
local function applySpeed(dt)
    if not live or not CFG.speedOn then return end
    local h, r = ownHumanoid(), ownRoot()
    if not h or not r or not able() then return end
    if h ~= boundHumanoid then
        boundHumanoid, originalSpeed = h, h.WalkSpeed
    end
    if h.WalkSpeed ~= CFG.speed then
        pcall(function() h.WalkSpeed = CFG.speed end)
    end
    local dir = movementDirection(h)
    local strength = math.clamp(dir.Magnitude, 0, 1)
    if strength < 0.07 then return end
    local v = r.AssemblyLinearVelocity
    local flat = Vector3.new(v.X, 0, v.Z)
    local target = CFG.speed * strength
    -- Preserve external attack dash, knockback and other >target momentum.
    if flat.Magnitude > math.max(target * 1.3, 57) then return end
    local goal = dir.Unit * target
    local alpha = 1 - math.exp(-math.clamp(dt, 0.001, 0.075) * 23)
    local mixed = flat:Lerp(goal, alpha)
    pcall(function()
        r.AssemblyLinearVelocity = Vector3.new(mixed.X, v.Y, mixed.Z)
    end)
end
listen(speedBtn.Activated, function()
    CFG.speedOn = not CFG.speedOn
    if not CFG.speedOn then releaseSpeed() end
    paintToggle(speedBtn, CFG.speedOn, "УСКОРЕНИЕ: ВКЛ", "УСКОРЕНИЕ: ВЫКЛ")
end)
listen(speedBox.FocusLost, function()
    CFG.speed = readNumber(speedBox, CFG.speed, 16, 120)
end)

-- Skill 1 and 2 are Garou / Hero Hunter base skills; input names are fallback hints.
local moveNames = {"flowing water", "lethal whirlwind stream"}
local function mouseClick(x, y)
    return pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.055)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
end
local function screenPress(x, y)
    if UserInputService.TouchEnabled then
        local ok = pcall(function()
            VirtualInputManager:SendTouchEvent(6, 0, x, y)
            task.wait(0.055)
            VirtualInputManager:SendTouchEvent(6, 2, x, y)
        end)
        if ok then return true end
    end
    return mouseClick(x, y)
end
local function mobileSkill(slot)
    local ui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if not ui then return false end
    local name = moveNames[slot]
    for _, item in ipairs(ui:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            if tostring(item.Text):lower():find(name, 1, true) then
                local cur, hidden = item, false
                while cur and cur ~= ui do
                    if cur:IsA("GuiObject") and not cur.Visible then hidden = true; break end
                    if cur:IsA("ScreenGui") and not cur.Enabled then hidden = true; break end
                    cur = cur.Parent
                end
                if not hidden and item.AbsoluteSize.X > 10 and item.AbsoluteSize.Y > 10 then
                    local center = item.AbsolutePosition + item.AbsoluteSize * 0.5
                    return screenPress(math.floor(center.X), math.floor(center.Y))
                end
            end
        end
    end
    return false
end
local function useSkill(slot)
    if not able() then return false end
    -- Native equipped Tool activation often works when simulated input is blocked.
    local char = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local desired = moveNames[slot]
    for _, container in ipairs({char, backpack}) do
        if container then
            for _, obj in ipairs(container:GetChildren()) do
                if obj:IsA("Tool") and (obj.Name:lower() == desired or obj.Name == tostring(slot)) then
                    local ok = pcall(function()
                        if obj.Parent ~= char then
                            local h = ownHumanoid()
                            if h then h:EquipTool(obj) end
                        end
                        obj:Activate()
                    end)
                    if ok then return true end
                end
            end
        end
    end
    if UserInputService.TouchEnabled and mobileSkill(slot) then return true end
    local key = slot == 1 and Enum.KeyCode.One or Enum.KeyCode.Two
    local pressed = pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
    end)
    if pressed then
        task.wait(0.055)
        return pcall(function() VirtualInputManager:SendKeyEvent(false, key, false, game) end)
    end
    return false
end
local function stillCycle(token)
    return live and cycle.on and token == cycle.generation
end
local function cycleSleep(token, seconds)
    local deadline = os.clock() + math.max(0, seconds)
    while stillCycle(token) and os.clock() < deadline do
        task.wait(math.min(0.12, math.max(0.015, deadline - os.clock())))
    end
    return stillCycle(token)
end
local function startCycle()
    if cycle.on or not live then return end
    if not able() then setCycleStatus("Персонаж пока недоступен."); return end
    stopFollow()
    stopTrash()
    cycle.on = true
    cycle.generation = cycle.generation + 1
    cycle.phase = "search"
    cycle.centerWait = false
    cycle.fails = 0
    cycleStart.BackgroundColor3 = C.panel
    local token = cycle.generation
    setCycleStatus("Поиск цели…")
    task.spawn(function()
        while stillCycle(token) do
            if not able() then
                cycle.phase = "respawn"
                setCycleStatus("Ожидание восстановления персонажа…")
                if not cycleSleep(token, 0.35) then break end
            else
                local now = os.clock()
                local oneReady = now >= cycle.ready[1]
                local twoReady = now >= cycle.ready[2]
                if not oneReady and not twoReady then
                    if not cycle.centerWait then
                        local ok = teleportCenter()
                        cycle.centerWait = ok
                        cycle.phase = "center"
                        setCycleStatus(ok and "В центре. Жду оба навыка…" or "Не удалось найти центр. Проверь калибровку.")
                    end
                    local wait = math.max(0, math.max(cycle.ready[1], cycle.ready[2]) - now)
                    setCycleStatus((cycle.centerWait and "В центре" or "Центр недоступен")
                        .. " • оба навыка через ~" .. math.ceil(wait) .. " с")
                    if not cycleSleep(token, math.min(0.3, math.max(0.1, wait))) then break end
                elseif cycle.centerWait and not (oneReady and twoReady) then
                    -- After returning to center, wait for BOTH slots to recharge.
                    local wait = math.max(0, math.max(cycle.ready[1], cycle.ready[2]) - now)
                    setCycleStatus("В центре • полная готовность через ~" .. math.ceil(wait) .. " с")
                    if not cycleSleep(token, math.min(0.3, math.max(0.1, wait))) then break end
                else
                    cycle.centerWait = false
                    local p = randomEnemy()
                    if not p then
                        setCycleStatus("Нет живых противников. Ожидание…")
                        if not cycleSleep(token, 0.65) then break end
                    else
                        cycle.phase = "attack"
                        local slot = oneReady and 1 or 2
                        if not teleportPlayer(p) then
                            setCycleStatus("TP недоступен. Повторная попытка…")
                            if not cycleSleep(token, 0.35) then break end
                        else
                            -- Only automatic skill activation needs a brief network settle;
                            -- manual player-selection TP above is synchronous and has no delay.
                            if not cycleSleep(token, 0.11) then break end
                            if not enemyRoot(p) then
                                setCycleStatus("Цель выбыла. Ищу следующую…")
                            else
                                local sent = useSkill(slot)
                                if not stillCycle(token) then break end
                                if sent then
                                    cycle.ready[slot] = os.clock() + CFG.cd[slot]
                                    cycle.fails = 0
                                    setCycleStatus("Навык " .. slot .. " отправлен • CD ~" .. CFG.cd[slot] .. " с")
                                    if not cycleSleep(token, CFG.castGap) then break end
                                else
                                    cycle.fails = cycle.fails + 1
                                    cycle.ready[slot] = os.clock() + 1.8
                                    if cycle.fails >= 4 then
                                        setCycleStatus("Ввод навыков недоступен. Цикл остановлен.")
                                        cycle.on = false
                                        break
                                    end
                                    setCycleStatus("Ввод навыка " .. slot .. " недоступен, повторю.")
                                    if not cycleSleep(token, 0.4) then break end
                                end
                            end
                        end
                    end
                end
            end
        end
        if live and token == cycle.generation then
            cycle.on = false
            cycleStart.BackgroundColor3 = C.green
        end
    end)
end
listen(cycleStart.Activated, startCycle)
listen(cycleStop.Activated, stopCycle)
for index, box in ipairs({cd1Box, cd2Box}) do
    listen(box.FocusLost, function()
        CFG.cd[index] = readNumber(box, CFG.cd[index], 5, 90)
    end)
end
listen(setCenter.Activated, function()
    local r = ownRoot()
    if not r then setCycleStatus("Сначала дождись появления персонажа."); return end
    CFG.center = r.Position
    CFG.centerCalibrated = true
    centerLabel.Text = string.format("Центр сохранён: X=%.1f, Z=%.1f", CFG.center.X, CFG.center.Z)
    setCycleStatus("Центр откалиброван.")
end)
listen(goCenter.Activated, function()
    stopCycle()
    stopFollow()
    setStatus(teleportCenter() and "Перемещение в центр выполнено." or "Центр недоступен.")
end)

-- Trash: no custom force, no long-range physics impulses or guessed server remotes.
local function trashName(s)
    local lower = tostring(s):lower()
    return lower:find("trash", 1, true) or lower:find("garbage", 1, true)
        or lower:find("dustbin", 1, true)
end
local function trashPart(item)
    if not item or not item.Parent then return nil end
    if item:IsA("BasePart") then return item end
    if item:IsA("Model") then return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true) end
end
local function ownedByCharacter(item)
    local cursor = item
    while cursor and cursor ~= workspace do
        if cursor:IsA("Model") and cursor:FindFirstChildOfClass("Humanoid") then return true end
        cursor = cursor.Parent
    end
    return false
end
local function holdingTrash()
    local c = LocalPlayer.Character
    if not c then return false end
    for _, obj in ipairs(c:GetDescendants()) do
        if (obj:IsA("Tool") or obj:IsA("Model")) and trashName(obj.Name) then return true end
    end
    return false
end
local function indexTrash(token)
    local now = os.clock()
    if now - trash.scanAt < 11 then return end
    trash.scanAt = now
    for i, item in ipairs(workspace:GetDescendants()) do
        if not live or token ~= trash.generation then return end
        if (item:IsA("Model") or item:IsA("BasePart")) and trashName(item.Name)
            and not ownedByCharacter(item) and trashPart(item) then
            trash.indexed[item] = true
        end
        if i % 225 == 0 then task.wait() end
    end
end
local function nearestTrash()
    local root = ownRoot()
    if not root then return nil end
    local best, smallest = nil, math.huge
    for item in pairs(trash.indexed) do
        local part = trashPart(item)
        if not part or not part:IsDescendantOf(workspace) or ownedByCharacter(item) then
            trash.indexed[item] = nil
        elseif (trash.exclude[item] or 0) < os.clock() then
            local distance = (root.Position - part.Position).Magnitude
            if distance < smallest and distance < 1400 then
                best, smallest = item, distance
            end
        end
    end
    return best
end
local function mouseM1()
    local c = LocalPlayer.Character
    local tool = c and c:FindFirstChildOfClass("Tool")
    if tool and trashName(tool.Name) and pcall(function() tool:Activate() end) then return true end
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(1080, 720)
    local x, y = math.floor(vp.X * 0.87), math.floor(vp.Y * 0.45)
    return screenPress(x, y)
end
local function trashHeld(item)
    if holdingTrash() then return true end
    local char = LocalPlayer.Character
    if not char or not item or not item.Parent then return false end
    if item:IsDescendantOf(char) then return true end
    for _, joint in ipairs(item:GetDescendants()) do
        if joint:IsA("Weld") or joint:IsA("WeldConstraint") or joint:IsA("Motor6D") then
            local ok, attached = pcall(function()
                return (joint.Part0 and joint.Part0:IsDescendantOf(char))
                    or (joint.Part1 and joint.Part1:IsDescendantOf(char))
            end)
            if ok and attached then return true end
        end
    end
    return false
end
local function trashAllowed(token)
    return live and token == trash.generation and able()
end
local function pickupTrash(token, throwAfter)
    local originalChar = LocalPlayer.Character
    local originalCF = originalChar and originalChar:GetPivot()
    if holdingTrash() then return false, "Мусорка уже в руках; ускорение доступно." end
    trashInfo.Text = "Поиск мусорки…"
    indexTrash(token)
    if not trashAllowed(token) then return false, "Операция прервана." end
    local item = nearestTrash()
    if not item then return false, "Мусорка не найдена." end
    local part = trashPart(item)
    local r = ownRoot()
    if not part or not r then return false, "Мусорка недоступна." end
    local flat = r.Position - part.Position
    flat = Vector3.new(flat.X, 0, flat.Z)
    if flat.Magnitude < 0.1 then flat = Vector3.new(0, 0, 1) end
    local spot = part.Position + flat.Unit * 3
    spot = Vector3.new(spot.X, r.Position.Y, spot.Z)
    if not pivot(CFrame.lookAt(spot, Vector3.new(part.Position.X, spot.Y, part.Position.Z))) then
        return false, "Не удалось подойти к мусорке."
    end
    if not trashAllowed(token) then return false, "Операция прервана." end
    trashInfo.Text = "Попытка поднять мусорку…"
    if not mouseM1() then return false, "Команда поднятия недоступна." end
    local deadline = os.clock() + CFG.pickupWait
    while trashAllowed(token) and os.clock() < deadline and not trashHeld(item) do task.wait(0.07) end
    if not trashAllowed(token) then return false, "Операция прервана." end
    if not trashHeld(item) then
        trash.exclude[item] = os.clock() + 10
        return false, "Поднятие не подтверждено игрой."
    end
    trash.exclude[item] = os.clock() + 16
    if not throwAfter then
        if originalCF then pivot(originalCF) end
        return true, "Мусорка поднята. Скорость работает и с ней."
    end
    local opponent = randomEnemy()
    if not opponent then
        if originalCF then pivot(originalCF) end
        return false, "Нет живой цели; мусорка остаётся в руках."
    end
    if not teleportPlayer(opponent) then
        if originalCF then pivot(originalCF) end
        return false, "Не удалось перенестись к противнику."
    end
    task.wait(0.12)
    if not trashAllowed(token) then return false, "Операция прервана." end
    if not trashHeld(item) then return false, "Мусорка потеряна перед броском." end
    local sent = mouseM1()
    if not sent then return false, "Обычный бросок M1 недоступен." end
    local untilTime = os.clock() + 0.7
    while trashAllowed(token) and os.clock() < untilTime do
        if not trashHeld(item) then return true, "Обычный бросок отправлен, попадание не подтверждено." end
        task.wait(0.07)
    end
    return false, "Бросок не подтверждён игрой."
end
local function trashRun(throwAfter)
    if trash.busy then trashInfo.Text = "Предыдущая операция ещё выполняется."; return end
    trash.generation = trash.generation + 1
    local token = trash.generation
    trash.busy = true
    task.spawn(function()
        repeat
            if not live or token ~= trash.generation then break end
            if not able() then
                trashInfo.Text = "Ожидание персонажа…"
                task.wait(0.35)
            else
                local ok, success, msg = pcall(pickupTrash, token, throwAfter)
                if live and token == trash.generation then
                    trashInfo.Text = ok and msg or "Ошибка обработки мусорки."
                end
                if not throwAfter then break end
                if holdingTrash() and not success then
                    trashInfo.Text = "Мусорка осталась в руках. Брось вручную и повтори."
                    stopTrash()
                    break
                end
                local delayTime = success and 1.5 or CFG.trashRetry
                local deadline = os.clock() + delayTime
                while live and token == trash.generation and os.clock() < deadline do task.wait(0.12) end
            end
        until not trash.on or not live or token ~= trash.generation
        trash.busy = false
    end)
end
listen(trashAutoBtn.Activated, function()
    if trash.on then stopTrash(); return end
    if trash.busy then trashInfo.Text = "Заверши текущую операцию."; return end
    stopCycle(); stopFollow()
    trash.on = true
    paintToggle(trashAutoBtn, true, "МУСОР: АВТО ВКЛ", "МУСОР: АВТО ВЫКЛ")
    trashRun(true)
end)
listen(pickupBtn.Activated, function()
    if trash.on or trash.busy then trashInfo.Text = "Сначала останови авто-мусор."; return end
    stopCycle(); stopFollow()
    trashRun(false)
end)

-- One heartbeat connection: follow and movement, no runaway RenderStep binds.
listen(RunService.Heartbeat, function(dt)
    if not live then return end
    local now = os.clock()
    if CFG.speedOn then applySpeed(dt) end
    if following and selected and not trash.busy and not cycle.on
        and now - lastFollow >= CFG.followInterval then
        lastFollow = now
        local desired = behindCF(selected)
        local r = ownRoot()
        if not desired or not r or not able() then
            stopFollow()
        else
            local distance = (desired.Position - r.Position).Magnitude
            local h = ownHumanoid()
            local moving = h and movementDirection(h).Magnitude > 0.09
            if distance > (moving and 4.3 or 1.4) then pivot(desired) end
        end
    end
end)
listen(LocalPlayer.CharacterAdded, function()
    releaseSpeed()
    stopFollow()
    if cycle.on then
        cycle.phase = "respawn"
        -- The cycle checks the new character on its own.
    end
end)

local minimized = false
listen(minBtn.Activated, function()
    minimized = not minimized
    status.Visible, tabs.Visible = not minimized, not minimized
    for _, page in ipairs(pages) do page.Visible = not minimized and page == pages[1] end
    if not minimized then
        local activeTab = 1
        for i, b in ipairs(tabButtons) do
            if b.BackgroundColor3 == C.blue then activeTab = i end
        end
        showPage(activeTab)
    end
    frame.Size = UDim2.fromOffset(width, minimized and 38 or height)
    minBtn.Text = minimized and "+" or "−"
end)
local dragging, dragOrigin, frameOrigin
listen(titleBar.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = input
        dragOrigin = Vector2.new(input.Position.X, input.Position.Y)
        frameOrigin = frame.AbsolutePosition
    end
end)
listen(titleBar.InputEnded, function(input) if dragging == input then dragging = nil end end)
listen(UserInputService.InputChanged, function(input)
    if not dragging or not dragOrigin or not frameOrigin then return end
    if input ~= dragging and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - dragOrigin
    local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or viewport
    local size = frame.AbsoluteSize
    local x = math.clamp(frameOrigin.X + delta.X, 0, math.max(0, vp.X - size.X))
    local y = math.clamp(frameOrigin.Y + delta.Y, 0, math.max(0, vp.Y - size.Y))
    frame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end)
local shutdown
shutdown = function()
    if not live then return end
    live = false
    stopCycle()
    stopTrash()
    stopFollow()
    releaseSpeed()
    for _, c in ipairs(rowConnections) do pcall(function() c:Disconnect() end) end
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    if env and env.__TSB_DELTA_V19_SHUTDOWN == shutdown then env.__TSB_DELTA_V19_SHUTDOWN = nil end
    pcall(function() gui:Destroy() end)
end
listen(closeBtn.Activated, shutdown)
if env then env.__TSB_DELTA_V19_SHUTDOWN = shutdown end
