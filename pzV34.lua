--[[
    TSB DELTA v38 / LITE
    Rebuilt from the user's v37. Only target TP, aim-on-TP, speed, and
    three original external modules remain: INVIS, HKG VOID, DANGER CORE.

    Client-side movement is NOT guaranteed to replicate or register hits.
    Third-party modules run with executor permissions; review/trust them first.
]]

-- SERVICES / SINGLE INSTANCE ----------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local me = Players.LocalPlayer
if not me then return end

local env = _G
pcall(function()
    if type(getgenv) == "function" and type(getgenv()) == "table" then
        env = getgenv()
    end
end)
-- v37 erroneously published its shutdown under the v36 key: include BOTH.
for version = 24, 38 do
    local key = "__TSB_DELTA_V" .. version .. "_SHUTDOWN"
    local stop = rawget(env, key)
    if type(stop) == "function" then
        pcall(stop)
        if rawget(env, key) == stop then env[key] = nil end
    end
end
for version = 26, 38 do
    for _, mode in ipairs({"AIM", "MOVE", "FOLLOW"}) do
        pcall(function()
            RunService:UnbindFromRenderStep("TSB_DELTA_" .. mode .. "_V" .. version)
        end)
    end
    for _, mode in ipairs({"Follow", "Aim"}) do
        pcall(function()
            RunService:UnbindFromRenderStep("TSB_DELTA_v" .. version .. "_" .. mode)
        end)
    end
end

local alive = true
local connections = {}
local function on(signal, fn)
    local conn = signal:Connect(fn)
    connections[#connections + 1] = conn
    return conn
end
local function make(class, parent, props)
    local obj = Instance.new(class)
    for key, val in pairs(props or {}) do obj[key] = val end
    obj.Parent = parent
    return obj
end
local function round(obj, radius)
    make("UICorner", obj, {CornerRadius = UDim.new(0, radius or 9)})
    return obj
end
local COL = {
    bg = Color3.fromRGB(12, 18, 29), card = Color3.fromRGB(19, 30, 47),
    btn = Color3.fromRGB(35, 52, 73), cyan = Color3.fromRGB(43, 142, 203),
    green = Color3.fromRGB(25, 151, 106), red = Color3.fromRGB(161, 49, 77),
    text = Color3.fromRGB(233, 243, 255), dim = Color3.fromRGB(157, 181, 202),
    warn = Color3.fromRGB(255, 190, 121),
}

local parent
if type(gethui) == "function" then
    local ok, target = pcall(gethui)
    if ok and target then parent = target end
end
if not parent then
    local ok = pcall(function() return CoreGui:GetChildren() end)
    if ok then parent = CoreGui end
end
if not parent then parent = me:FindFirstChildOfClass("PlayerGui") or me:WaitForChild("PlayerGui", 8) end
if not parent then error("TSB v38: GUI parent not found") end
for _, container in ipairs({parent, CoreGui, me:FindFirstChildOfClass("PlayerGui")}) do
    if container then
        pcall(function()
            for _, child in ipairs(container:GetChildren()) do
                if child:IsA("ScreenGui") and
                    (child.Name:match("^TSB_DELTA_v%d+$") or
                     child.Name:match("^TSB_Delta_V%d+$") or
                     child.Name == "TSB_Delta_Clean") then
                    child:Destroy()
                end
            end
        end)
    end
end

-- STATE / SHARED CHARACTER HELPERS ----------------------------------------
local target = nil
local following = false
local aimEnabled = true       -- applies ONLY during TP/FOLLOW, never in idle or Shift-lock
local desiredDistance = 4.0 -- studs behind target; actual attack reach is server-controlled
local speedEnabled = false
local desiredSpeed = 40
local speedHum, originalSpeed, lastSpeedSet
local rotateHum, originalRotate
local lastMotion = 0
local motionErrors = 0

local function characterInfo(player, allowDowned)
    if not player or player.Parent ~= Players then return end
    local char = player.Character
    if not char or not char.Parent then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root or not root:IsA("BasePart") then
        root = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
    end
    if not root or not root:IsA("BasePart") then return end
    if not allowDowned and (not hum or hum.Health <= 0) then return end
    return char, hum, root
end
local function goodPosition(pos)
    return pos and pos.X == pos.X and pos.Y == pos.Y and pos.Z == pos.Z
        and math.abs(pos.X) < 100000 and math.abs(pos.Y) < 100000 and math.abs(pos.Z) < 100000
        and pos.Y > workspace.FallenPartsDestroyHeight + 8
end
local function horizontal(vec)
    return Vector3.new(vec.X, 0, vec.Z)
end
local function restoreRotate()
    if rotateHum and rotateHum.Parent and originalRotate ~= nil then
        pcall(function() rotateHum.AutoRotate = originalRotate end)
    end
    rotateHum, originalRotate = nil, nil
end
local function setRotateLock()
    if not following or not aimEnabled then
        restoreRotate()
        return
    end
    local _, hum = characterInfo(me)
    if not hum then return end
    if rotateHum ~= hum then
        restoreRotate()
        rotateHum, originalRotate = hum, hum.AutoRotate
    end
    if hum.AutoRotate then hum.AutoRotate = false end
end
local function restoreSpeed()
    if speedHum and speedHum.Parent and originalSpeed ~= nil then
        if lastSpeedSet == nil or math.abs(speedHum.WalkSpeed - lastSpeedSet) < 0.01 then
            pcall(function() speedHum.WalkSpeed = originalSpeed end)
        end
    end
    speedHum, originalSpeed, lastSpeedSet = nil, nil, nil
end

-- COMPACT MOBILE GUI -------------------------------------------------------
local gui = make("ScreenGui", parent, {
    Name = "TSB_DELTA_v38", ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 160, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
})
local function viewport()
    local camera = workspace.CurrentCamera
    return camera and camera.ViewportSize or Vector2.new(420, 780)
end
local function dimensions()
    local size = viewport()
    return math.min(264, math.max(210, size.X - 20)), math.min(465, math.max(285, size.Y - 30))
end
local W, H = dimensions()
local panel = round(make("Frame", gui, {
    Name = "Panel", Size = UDim2.fromOffset(W, H),
    Position = UDim2.new(0.5, -W/2, 0.5, -H/2),
    BackgroundColor3 = COL.bg, BorderSizePixel = 0,
    ClipsDescendants = true, Active = true,
}), 12)
make("UIStroke", panel, {Thickness = 1.2, Color = Color3.fromRGB(62, 122, 158)})
local header = make("Frame", panel, {
    Name = "DragHandle", Size = UDim2.new(1, 0, 0, 36),
    BackgroundColor3 = Color3.fromRGB(20, 51, 78), BorderSizePixel = 0,
    Active = true,
})
make("UIGradient", header, {
    Color = ColorSequence.new(COL.cyan, Color3.fromRGB(21, 48, 72)), Rotation = 0,
})
local headText = make("TextLabel", header, {
    Size = UDim2.new(1, -76, 1, 0), Position = UDim2.fromOffset(10, 0),
    Text = "≡  TSB DELTA  v38", TextSize = 12, Font = Enum.Font.GothamBold,
    TextColor3 = COL.text, BackgroundTransparency = 1,
    TextXAlignment = Enum.TextXAlignment.Left, Active = true,
})
local function button(parentObj, title, pos, size, color)
    return round(make("TextButton", parentObj, {
        Position = pos, Size = size, Text = title, TextSize = 12,
        Font = Enum.Font.GothamBold, TextColor3 = COL.text,
        BackgroundColor3 = color or COL.btn, BorderSizePixel = 0,
        AutoButtonColor = true,
    }), 7)
end
local mini = button(header, "−", UDim2.new(1, -67, 0, 3), UDim2.fromOffset(29, 29), COL.btn)
local close = button(header, "×", UDim2.new(1, -34, 0, 3), UDim2.fromOffset(29, 29), COL.red)
mini.TextSize, close.TextSize = 19, 19
local statusText = make("TextLabel", panel, {
    Position = UDim2.fromOffset(9, 38), Size = UDim2.new(1, -18, 0, 24),
    BackgroundTransparency = 1, Text = "ВЫБЕРИ ЦЕЛЬ → START",
    Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = COL.dim,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
})
local function report(message, errorMode)
    if not alive then return end
    statusText.Text = tostring(message):sub(1, 180)
    statusText.TextColor3 = errorMode and COL.warn or COL.dim
    if errorMode then warn("[TSB v38] " .. tostring(message)) end
end
local scroll = round(make("ScrollingFrame", panel, {
    Position = UDim2.fromOffset(7, 66), Size = UDim2.new(1, -14, 1, -73),
    BackgroundColor3 = COL.card, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = COL.cyan,
    CanvasSize = UDim2.fromOffset(0, 580),
    ScrollingDirection = Enum.ScrollingDirection.Y,
}), 8)
local function textLabel(txt, y)
    return make("TextLabel", scroll, {
        Position = UDim2.fromOffset(9, y), Size = UDim2.new(1, -18, 0, 20),
        BackgroundTransparency = 1, Text = txt, TextSize = 10,
        TextColor3 = COL.dim, Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
    })
end
local function wideButton(txt, y, ht, color)
    return button(scroll, txt, UDim2.fromOffset(9, y), UDim2.new(1, -18, 0, ht), color)
end
textLabel("ИГРОКИ", 3)
local roster = round(make("ScrollingFrame", scroll, {
    Position = UDim2.fromOffset(9, 24), Size = UDim2.new(1, -18, 0, 148),
    BackgroundColor3 = COL.bg, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = COL.cyan,
    CanvasSize = UDim2.fromOffset(0, 0),
}), 7)
local start = button(scroll, "▶ START", UDim2.fromOffset(9, 180), UDim2.new(0.64, -10, 0, 39), COL.green)
local stop = button(scroll, "■ STOP", UDim2.new(0.64, 3, 0, 180), UDim2.new(0.36, -12, 0, 39), COL.red)
textLabel("ОТСТУП ОТ ЦЕЛИ", 227)
local dist = round(make("TextBox", scroll, {
    Position = UDim2.new(1, -89, 0, 224), Size = UDim2.fromOffset(80, 28),
    Text = tostring(desiredDistance), ClearTextOnFocus = false,
    BackgroundColor3 = COL.btn, BorderSizePixel = 0,
    Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = COL.text,
}), 6)
textLabel("БОЙ И ДВИЖЕНИЕ", 264)
local aim = wideButton("◎ AIM С TP: ON", 288, 36, COL.green)
local speed = button(scroll, "SPEED: OFF", UDim2.fromOffset(9, 330), UDim2.new(0.64, -10, 0, 36), COL.red)
local speedInput = round(make("TextBox", scroll, {
    Position = UDim2.new(0.64, 3, 0, 330), Size = UDim2.new(0.36, -12, 0, 36),
    Text = tostring(desiredSpeed), ClearTextOnFocus = false,
    BackgroundColor3 = COL.btn, BorderSizePixel = 0,
    Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = COL.text,
}), 6)
textLabel("СПЕЦИАЛЬНЫЕ СКРИПТЫ", 377)
local invis = wideButton("◉ INVIS", 401, 38, COL.cyan)
local hkg = wideButton("◈ HKG VOID", 446, 38, COL.cyan)
local danger = wideButton("☠ DANGER CORE", 491, 45, COL.red)
make("UIStroke", danger, {Color = Color3.fromRGB(255, 114, 157), Thickness = 1.5})
make("UIGradient", danger, {
    Color = ColorSequence.new(Color3.fromRGB(230, 70, 123), Color3.fromRGB(114, 27, 64)), Rotation = 0,
})
scroll.CanvasSize = UDim2.fromOffset(0, 547)

-- DRAG BY HEADER / FLOATING TOGGLE ----------------------------------------
local dock = button(gui, "≡", UDim2.fromOffset(math.max(3, viewport().X - 48), 112),
    UDim2.fromOffset(39, 39), COL.cyan)
dock.TextSize = 20
local activeDrag, recentlyDragged = nil, false
local function clampToView(item, position)
    local view = viewport()
    local size = item.AbsoluteSize
    local maxX = math.max(2, view.X - size.X - 2)
    local maxY = math.max(2, view.Y - size.Y - 2)
    item.Position = UDim2.fromOffset(
        math.floor(math.clamp(position.X, 2, maxX)),
        math.floor(math.clamp(position.Y, 2, maxY)))
end
local function beginDrag(item, input)
    if activeDrag then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 and
       input.UserInputType ~= Enum.UserInputType.Touch then return end
    activeDrag = {
        item = item, pointer = input,
        start = Vector2.new(input.Position.X, input.Position.Y),
        pos = item.AbsolutePosition, moved = false,
    }
end
on(header.InputBegan, function(input) beginDrag(panel, input) end)
on(headText.InputBegan, function(input) beginDrag(panel, input) end)
on(dock.InputBegan, function(input) beginDrag(dock, input) end)
on(UIS.InputChanged, function(input)
    local d = activeDrag
    if not d then return end
    if d.pointer.UserInputType == Enum.UserInputType.Touch then
        if input ~= d.pointer then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - d.start
    if delta.Magnitude > 5 then d.moved = true end
    if d.moved then clampToView(d.item, d.pos + delta) end
end)
on(UIS.InputEnded, function(input)
    local d = activeDrag
    if not d then return end
    if d.pointer.UserInputType == Enum.UserInputType.Touch then
        if input ~= d.pointer then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if d.item == dock and d.moved then recentlyDragged = true end
    activeDrag = nil
end)
on(dock.Activated, function()
    if recentlyDragged then recentlyDragged = false; return end
    panel.Visible = not panel.Visible
end)
local minimized = false
on(mini.Activated, function()
    minimized = not minimized
    mini.Text = minimized and "+" or "−"
    panel.Size = minimized and UDim2.fromOffset(170, 36) or UDim2.fromOffset(W, H)
    scroll.Visible, statusText.Visible = not minimized, not minimized
    clampToView(panel, panel.AbsolutePosition)
end)
local currentCamera = workspace.CurrentCamera
if currentCamera then
    on(currentCamera:GetPropertyChangedSignal("ViewportSize"), function()
        W, H = dimensions()
        if not minimized then panel.Size = UDim2.fromOffset(W, H) end
        clampToView(panel, panel.AbsolutePosition)
        clampToView(dock, dock.AbsolutePosition)
    end)
end

-- PLAYER LIST / THUMBNAILS (ONLY ON JOIN/LEAVE) ----------------------------
local rosterConns = {}
local thumbnails = {}
local worker = false
local thumbQueue = {}
local function queueThumb(player, imageObj)
    local cached = thumbnails[player.UserId]
    if cached then imageObj.Image = cached; return end
    thumbQueue[#thumbQueue + 1] = {player.UserId, imageObj}
    if worker then return end
    worker = true
    task.spawn(function()
        while alive and #thumbQueue > 0 do
            local item = table.remove(thumbQueue, 1)
            if item and item[2] and item[2].Parent then
                local ok, url = pcall(function()
                    return Players:GetUserThumbnailAsync(item[1], Enum.ThumbnailType.HeadShot,
                        Enum.ThumbnailSize.Size48x48)
                end)
                if ok and url and url ~= "" then
                    thumbnails[item[1]] = url
                    if alive and item[2].Parent then item[2].Image = url end
                end
            end
            task.wait()
        end
        worker = false
    end)
end
local function updateStart()
    start.Text = following and "▶ FOLLOWING" or "▶ START"
    start.BackgroundColor3 = target and COL.green or COL.btn
end
local function stopFollow()
    following = false
    motionErrors = 0
    lastMotion = 0
    restoreRotate()
    updateStart()
end
local function refreshRoster()
    for _, conn in ipairs(rosterConns) do pcall(function() conn:Disconnect() end) end
    rosterConns = {}
    for _, child in ipairs(roster:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    local list = Players:GetPlayers()
    table.sort(list, function(a, b) return a.Name:lower() < b.Name:lower() end)
    local y = 5
    for _, p in ipairs(list) do
        if p ~= me then
            local row = button(roster, "", UDim2.fromOffset(5, y),
                UDim2.new(1, -10, 0, 41), p == target and COL.green or COL.btn)
            make("TextLabel", row, {
                Position = UDim2.fromOffset(7, 3), Size = UDim2.new(1, -45, 1, -6),
                Text = p.Name, TextTruncate = Enum.TextTruncate.AtEnd,
                TextXAlignment = Enum.TextXAlignment.Left, TextSize = 11,
                Font = Enum.Font.GothamBold, TextColor3 = COL.text,
                BackgroundTransparency = 1,
            })
            local icon = round(make("ImageLabel", row, {
                Position = UDim2.new(1, -36, 0, 5), Size = UDim2.fromOffset(31, 31),
                BackgroundColor3 = COL.card, BorderSizePixel = 0,
                Image = "", ScaleType = Enum.ScaleType.Crop,
            }), 16)
            queueThumb(p, icon)
            rosterConns[#rosterConns + 1] = row.Activated:Connect(function()
                if not alive or p.Parent ~= Players then return end
                if following then stopFollow() end
                target = p
                for _, entry in ipairs(roster:GetChildren()) do
                    if entry:IsA("TextButton") then
                        entry.BackgroundColor3 = entry == row and COL.green or COL.btn
                    end
                end
                updateStart()
                report("Цель: @" .. p.Name .. "  •  START")
            end)
            y = y + 46
        end
    end
    roster.CanvasSize = UDim2.fromOffset(0, y + 4)
    if y == 5 then report("На сервере нет других игроков") end
end
on(Players.PlayerAdded, refreshRoster)
on(Players.PlayerRemoving, function(p)
    if p == target then
        stopFollow()
        target = nil
        report("Выбранный игрок вышел", true)
    end
    task.defer(function() if alive then refreshRoster() end end)
end)

-- TELEPORT / SINGLE MOTION WRITER -----------------------------------------
local function desiredFrame()
    if not target or target.Parent ~= Players then return nil, "Цель не выбрана" end
    local _, _, enemyRoot = characterInfo(target, true) -- permits ragdolled character
    if not enemyRoot then return nil, "У цели нет HumanoidRootPart / Torso" end
    local pos = enemyRoot.Position
    if not goodPosition(pos) then return nil, "Некорректные координаты цели" end
    local look = horizontal(enemyRoot.CFrame.LookVector)
    if look.Magnitude < 0.05 then look = horizontal(enemyRoot.AssemblyLinearVelocity) end
    if look.Magnitude < 0.05 then look = Vector3.new(0, 0, -1) end
    look = look.Unit
    -- Small bounded lead reduces perceived delay without over-predicting zigzags.
    local v = horizontal(enemyRoot.AssemblyLinearVelocity)
    if v.Magnitude > 65 then v = v.Unit * 65 end
    local lead = v * 0.025
    if lead.Magnitude > 1.2 then lead = lead.Unit * 1.2 end
    local aimAt = pos + lead
    local dest = aimAt - look * desiredDistance
    -- Stay at roughly the target's elevation, including when target is downed.
    dest = Vector3.new(dest.X, pos.Y, dest.Z)
    if not goodPosition(dest) then return nil, "Точка TP недоступна" end
    local forward = horizontal(aimAt - dest)
    if not aimEnabled or forward.Magnitude < .15 then
        local _, _, ownRoot = characterInfo(me)
        if ownRoot then forward = horizontal(ownRoot.CFrame.LookVector) end
    end
    if forward.Magnitude < .1 then forward = look end
    return CFrame.lookAt(dest, dest + forward.Unit)
end
local function applyTeleport(initial)
    local char, hum, root = characterInfo(me)
    if not char or not root then return false, "Персонаж ещё не готов" end
    if root.Anchored then return false, "Персонаж закреплён сервером" end
    if hum and hum.Sit then hum.Sit = false end
    local cf, reason = desiredFrame()
    if not cf then return false, reason end
    if not initial then
        local delta = (root.Position - cf.Position).Magnitude
        local yaw = horizontal(root.CFrame.LookVector)
        local wanted = horizontal(cf.LookVector)
        if delta < .09 and yaw.Magnitude > .1 and wanted.Magnitude > .1
           and yaw.Unit:Dot(wanted.Unit) > .999 then
            return true
        end
    end
    -- Only ONE controller moves the character; no camera CFrame edits.
    local ok, err = pcall(function()
        if initial then
            char:PivotTo(cf)
        else
            root.CFrame = cf
        end
    end)
    if not ok then return false, tostring(err) end
    if (root.Position - cf.Position).Magnitude > 2 then
        return false, "Локальный TP не применился"
    end
    return true
end
local function startFollow()
    if following then
        -- Re-tap = force immediate one-shot teleport, without a second loop.
        local ok, why = applyTeleport(true)
        report(ok and "TP обновлён" or tostring(why), not ok)
        return
    end
    if not target or target.Parent ~= Players then report("Сначала выбери игрока", true); return end
    local ok, why = applyTeleport(true)
    if not ok then
        report("TP: " .. tostring(why), true)
        return
    end
    following = true
    setRotateLock()
    updateStart()
    report("FOLLOW: @" .. target.Name)
end
on(start.Activated, startFollow)
on(stop.Activated, function()
    stopFollow()
    report("STOP • TP и AIM выключены")
end)
on(dist.FocusLost, function()
    local num = tonumber(dist.Text)
    if num and num == num then desiredDistance = math.clamp(num, 2.5, 7) end
    dist.Text = string.format("%.1f", desiredDistance)
end)
on(aim.Activated, function()
    aimEnabled = not aimEnabled
    aim.Text = "◎ AIM С TP: " .. (aimEnabled and "ON" or "OFF")
    aim.BackgroundColor3 = aimEnabled and COL.green or COL.red
    setRotateLock()
    report(aimEnabled and "AIM активен только при FOLLOW" or "AIM выключен")
end)
-- A single throttled simulation callback; no camera tracking or idle aim.
local accum = 0
on(RunService.PostSimulation, function(dt)
    if not alive or not following then return end
    accum = accum + dt
    if accum < 1/60 then return end
    accum = 0
    if not target or target.Parent ~= Players then
        stopFollow()
        report("Цель недоступна", true)
        return
    end
    local ok, reason = applyTeleport(false)
    if not ok then
        motionErrors = motionErrors + 1
        if os.clock() - lastMotion > 1.5 then
            lastMotion = os.clock()
            report("FOLLOW: " .. tostring(reason), true)
        end
        if motionErrors >= 20 then
            stopFollow()
            report("TP остановлен: сервер/физика отклоняет движение", true)
        end
    else
        motionErrors = 0
    end
end)

-- SPEED ------------------------------------------------------------------
local function tickSpeed()
    if not speedEnabled then return end
    local _, hum = characterInfo(me)
    if not hum then return end
    if speedHum ~= hum then
        restoreSpeed()
        speedHum, originalSpeed = hum, hum.WalkSpeed
    end
    if math.abs(hum.WalkSpeed - desiredSpeed) > .01 then
        hum.WalkSpeed = desiredSpeed
        lastSpeedSet = desiredSpeed
    end
end
on(speed.Activated, function()
    speedEnabled = not speedEnabled
    speed.BackgroundColor3 = speedEnabled and COL.green or COL.red
    speed.Text = "SPEED: " .. (speedEnabled and "ON" or "OFF")
    if speedEnabled then tickSpeed() else restoreSpeed() end
end)
on(speedInput.FocusLost, function()
    local n = tonumber(speedInput.Text)
    if n and n == n then desiredSpeed = math.clamp(math.floor(n + .5), 8, 120) end
    speedInput.Text = tostring(desiredSpeed)
    if speedEnabled then tickSpeed() end
end)
local speedElapsed = 0
on(RunService.Heartbeat, function(dt)
    if not alive or not speedEnabled then return end
    speedElapsed = speedElapsed + dt
    if speedElapsed >= .25 then speedElapsed = 0; pcall(tickSpeed) end
end)

-- ORIGINAL THREE REMOTE BUTTONS ------------------------------------------
local MODULES = {
    invis = {
        "https://raw.githubusercontent.com/Airbornite/tsb-scripts/refs/heads/main/InvisScript_loader.lua",
        "https://raw.githubusercontent.com/Airbornite/tsb-scripts/main/InvisScript_loader.lua",
    },
    hkg = {
        "https://raw.githubusercontent.com/pusahursahur-gif/HKG-hub./refs/heads/Lua/HKG-void",
    },
    danger = {
        "https://api.jnkie.com/api/v1/luascripts/public/e7272cc100526cce2983ec85de722d45e915a26117824385c78e0c30e61585f4/download",
    },
}
local loading, started = {}, {}
local function download(url)
    local ok, src = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(src) == "string" and #src > 0 then
        local prefix = src:sub(1, 150):lower()
        if not prefix:find("<html", 1, true) and not prefix:find("<!doctype", 1, true)
            and not prefix:find("404: not found", 1, true) then
            return src
        end
        return nil, "Вместо Lua пришла страница ошибки"
    end
    return nil, tostring(src)
end
local function runModule(key, btn, name)
    if not alive or loading[key] then return end
    if started[key] then report(name .. ": уже запускался"); return end
    if type(loadstring) ~= "function" then
        report(name .. ": loadstring() недоступен", true)
        return
    end
    loading[key] = true
    btn.Text = name .. " ..."
    task.spawn(function()
        local src, reason
        for _, url in ipairs(MODULES[key]) do
            src, reason = download(url)
            if src then break end
        end
        if not alive then return end
        if not src then
            loading[key] = false
            btn.Text = name .. " ↻"
            report(name .. ": " .. tostring(reason), true)
            return
        end
        local okCompile, fn = pcall(loadstring, src)
        if not okCompile or type(fn) ~= "function" then
            loading[key] = false
            btn.Text = name .. " ↻"
            report(name .. ": ошибка компиляции " .. tostring(fn), true)
            return
        end
        -- Execute with no false claim of confirmed invisibility / module effect.
        started[key] = true
        loading[key] = false
        btn.Text = name .. " ✓"
        local okRun, err = pcall(fn)
        if not alive then return end
        if not okRun then
            started[key] = false
            btn.Text = name .. " ↻"
            report(name .. ": " .. tostring(err), true)
        else
            report(name .. ": Lua выполнен (эффект зависит от модуля)")
        end
    end)
end
on(invis.Activated, function() runModule("invis", invis, "INVIS") end)
on(hkg.Activated, function() runModule("hkg", hkg, "HKG VOID") end)
on(danger.Activated, function() runModule("danger", danger, "DANGER") end)

-- RESPAWN / CLEAN SHUTDOWN ------------------------------------------------
on(me.CharacterAdded, function()
    -- Do not re-run START automatically on respawn or fight other spawn scripts.
    stopFollow()
    restoreSpeed()
    report("Респавн • выбери цель и нажми START")
end)
local shutdown
shutdown = function()
    if not alive then return end
    alive = false
    stopFollow()
    speedEnabled = false
    restoreSpeed()
    for _, conn in ipairs(rosterConns) do pcall(function() conn:Disconnect() end) end
    for _, conn in ipairs(connections) do pcall(function() conn:Disconnect() end) end
    pcall(function() gui:Destroy() end)
    if rawget(env, "__TSB_DELTA_V38_SHUTDOWN") == shutdown then
        env.__TSB_DELTA_V38_SHUTDOWN = nil
    end
end
env.__TSB_DELTA_V38_SHUTDOWN = shutdown
on(close.Activated, shutdown)

refreshRoster()
updateStart()
report("Выбери игрока → START • AIM только при TP")
