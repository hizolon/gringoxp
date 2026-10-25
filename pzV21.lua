-- TSB DELTA v21 | restored complete feature set, mobile interface
-- Manual abilities only; persistent target chasing, optional external menu.
-- No server-side guarantees: simulated skill inputs may be rejected.
-- FPS optimization is reversible and disabled by default; no ESP/outline.
-- This file contains no personal branding or identifiers.

-- ============================================================
-- SERVICES
-- ============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local StarterGui = game:GetService("StarterGui")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local Player = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    BEHIND_STUDS = 2.9,
    POSITION_TOLERANCE = 0.32,
    VISUAL_RADIUS = 160, -- cosmetic local distance only, NOT real streaming
    VISUAL_DISTANCE_ENABLED = true,

    HEIGHT_OFFSET = 0,

    INVISIBLE = false,
    SAFE_ZONE = false,
    AUTO_RESET = false,
    RESET_THRESHOLD = 30,
    SAFE_DEPTH = 80,
    SAFE_HEIGHT = 130,

    PING_COMPENSATE = true, -- optional short prediction of moving targets
    MAX_LEAD_TIME = 0.085,

    SPEED_ENABLED = false,
    SPEED_VALUE = 42,
    -- These are attempts at local movement; game/server restrictions still apply.
    SPEED_ACCELERATION = 0.92,
    SPEED_UPDATE_INTERVAL = 0.016,
    TRASH_PICKUP_WAIT = 1.1,
    TRASH_THROW_WAIT = 0.5,
    TRASH_TARGET_DISTANCE = 8,
    TRASH_SCAN_INTERVAL = 12.0,
    TRASH_RETRY_WAIT = 1.4,
    TRASH_RETURN_PAUSE = 0.2,
    AIM_ENABLED = false,
    -- Approximations for Garou's normal (non-awakened) abilities.
    -- Client-side timers cannot observe authoritative server cooldowns.
    RANDOM_CD1 = 18,
    RANDOM_CD2 = 21,
    RANDOM_TARGET_RANGE = 2.9,
}

-- ============================================================
-- REVERSIBLE GRAPHICS + CONSERVATIVE COSMETIC DISTANCE CULLING
-- Roblox streaming is controlled by the experience/server: this does
-- NOT unload map geometry, physics, players or networked assets.
-- Only static non-collidable decoration can be locally hidden far away.
-- ============================================================
local Visual = {}
do
    local Lighting = game:GetService("Lighting")
    local state = {
        wanted=false, active=false, conn=nil, addedConn=nil,
        originals=setmetatable({}, {__mode="k"}),
        savedVisuals=setmetatable({}, {__mode="k"}),
        candidates={}, seen=setmetatable({}, {__mode="k"}),
        radius=CONFIG.VISUAL_RADIUS, distanceEnabled=CONFIG.VISUAL_DISTANCE_ENABLED,
        generation=0
    }
    local function remember(obj, property, target)
        local ok, old = pcall(function() return obj[property] end)
        if not ok or old == target then return end
        local original = state.originals[obj]
        if not original then original = {}; state.originals[obj] = original end
        if original[property] == nil then original[property] = old end
        pcall(function() obj[property] = target end)
    end
    local function optimizeEffect(obj)
        if obj:IsA("BloomEffect") or obj:IsA("BlurEffect")
           or obj:IsA("SunRaysEffect") or obj:IsA("DepthOfFieldEffect")
           or obj:IsA("ColorCorrectionEffect") then
            remember(obj, "Enabled", false)
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail")
           or obj:IsA("Beam") or obj:IsA("Fire")
           or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            -- Graphics-only change; keep combat bodies, hitboxes and physics.
            remember(obj, "Enabled", false)
        end
    end
    local function isCosmeticPart(part)
        if not part:IsA("BasePart") or not part.Anchored
            or part.CanCollide or part.CanTouch or part.Transparency >= 0.95 then return false end
        local current = part
        while current and current ~= workspace do
            if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then return false end
            local lower = current.Name:lower()
            if lower:find("combat",1,true) or lower:find("hitbox",1,true)
                or lower:find("projectile",1,true) or lower:find("effect",1,true)
                or lower:find("attack",1,true) or lower:find("weapon",1,true)
                or lower:find("dummy",1,true) or lower:find("npc",1,true)
                or lower:find("trash",1,true) then return false end
            current = current.Parent
        end
        return true
    end
    local function addCandidate(part)
        if #state.candidates >= 850 or state.seen[part] or not isCosmeticPart(part) then return end
        state.seen[part] = true
        table.insert(state.candidates, part)
    end
    local function restoreVisuals()
        for part, original in pairs(state.savedVisuals) do
            pcall(function()
                if part.Parent and part.LocalTransparencyModifier == 1 then
                    part.LocalTransparencyModifier = original
                end
            end)
        end
        state.savedVisuals = setmetatable({}, {__mode="k"})
    end
    local function updateDistances()
        if not state.distanceEnabled then
            restoreVisuals()
            return
        end
        local char = Player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local origin = root.Position
        local farSq = (state.radius + 16) ^ 2
        local nearSq = (state.radius - 10) ^ 2
        for _, part in ipairs(state.candidates) do
            if part.Parent and isCosmeticPart(part) then
                local p = part.Position
                local squared = (p.X-origin.X)^2 + (p.Y-origin.Y)^2 + (p.Z-origin.Z)^2
                if squared > farSq then
                    if state.savedVisuals[part] == nil then
                        local ok, prev = pcall(function() return part.LocalTransparencyModifier end)
                        if ok and prev < 1 then state.savedVisuals[part] = prev end
                    end
                    if state.savedVisuals[part] ~= nil then
                        pcall(function() part.LocalTransparencyModifier = 1 end)
                    end
                elseif squared < nearSq and state.savedVisuals[part] ~= nil then
                    local old = state.savedVisuals[part]
                    pcall(function() if part.LocalTransparencyModifier == 1 then part.LocalTransparencyModifier = old end end)
                    state.savedVisuals[part] = nil
                end
            elseif state.savedVisuals[part] ~= nil then
                local old = state.savedVisuals[part]
                pcall(function() if part.LocalTransparencyModifier == 1 then part.LocalTransparencyModifier = old end end)
                state.savedVisuals[part] = nil
            end
        end
    end
    local function scanGradually(token)
        -- Traverse incrementally; no full-map GetDescendants() allocation.
        local queue = workspace:GetChildren()
        local index, scanned = 1, 0
        while state.active and state.generation == token and index <= #queue
            and scanned < 16000 do
            local obj = queue[index]
            index = index + 1
            scanned = scanned + 1
            if obj and obj.Parent then
                if obj:IsA("BasePart") then
                    addCandidate(obj)
                    if isCosmeticPart(obj) then remember(obj, "CastShadow", false) end
                else
                    optimizeEffect(obj)
                end
                if obj ~= workspace.Terrain and obj ~= workspace.CurrentCamera then
                    for _, child in ipairs(obj:GetChildren()) do
                        queue[#queue + 1] = child
                    end
                end
            end
            if scanned % 160 == 0 then task.wait() end
        end
    end
    Visual.setRadius = function(value)
        state.radius = math.clamp(math.floor(value + 0.5), 80, 300)
    end
    Visual.setDistanceEnabled = function(enabled)
        state.distanceEnabled = enabled and true or false
        if not state.distanceEnabled then restoreVisuals() end
    end
    Visual.start = function()
        state.wanted = true
        if state.active then return end
        state.active = true
        state.generation = state.generation + 1
        local token = state.generation
        remember(Lighting, "GlobalShadows", false)
        for _, obj in ipairs(Lighting:GetDescendants()) do optimizeEffect(obj) end
        state.conn = Lighting.DescendantAdded:Connect(function(obj)
            if state.active then optimizeEffect(obj) end
        end)
        state.addedConn = workspace.DescendantAdded:Connect(function(obj)
            if not state.active then return end
            if obj:IsA("BasePart") then
                if state.distanceEnabled then addCandidate(obj) end
                if isCosmeticPart(obj) then remember(obj, "CastShadow", false) end
            else
                optimizeEffect(obj)
            end
        end)
        task.spawn(function() scanGradually(token) end)
        task.spawn(function()
            while state.active and state.generation == token do
                pcall(updateDistances)
                task.wait(2.4) -- never walks all candidates per frame
            end
        end)
    end
    Visual.stop = function()
        state.wanted = false
        state.active = false
        state.generation = state.generation + 1
        if state.conn then state.conn:Disconnect(); state.conn=nil end
        if state.addedConn then state.addedConn:Disconnect(); state.addedConn=nil end
        restoreVisuals()
        for obj, props in pairs(state.originals) do
            for property, previous in pairs(props) do
                pcall(function() obj[property] = previous end)
            end
        end
        state.originals = setmetatable({}, {__mode="k"})
        state.candidates = {}
        state.seen = setmetatable({}, {__mode="k"})
    end
    Visual.state = state
end

-- ============================================================
-- GUI SETUP
-- ============================================================
-- Previous v16 could crash during UI initialization and leave a dead overlay.
-- Destroy that orphaned GUI before constructing the new panel.
local sharedEnvironment = nil
pcall(function()
    if type(getgenv) == "function" then sharedEnvironment = getgenv() end
end)
if sharedEnvironment then
    for _, key in ipairs({"__TSB_DELTA_V21_SHUTDOWN", "__TSB_DELTA_V20_SHUTDOWN", "__TSB_DELTA_V19_SHUTDOWN", "__NEBULA_TSB_EXIT"}) do
        local old = rawget(sharedEnvironment, key)
        if type(old) == "function" then pcall(old) end
    end
end
local parentsToClean = {CoreGui}
local pg = Player:FindFirstChildOfClass("PlayerGui")
if pg then table.insert(parentsToClean, pg) end
if type(gethui) == "function" then
    local ok, ui = pcall(gethui)
    if ok and ui then table.insert(parentsToClean, ui) end
end
for _, container in ipairs(parentsToClean) do
    pcall(function()
        for _, gui in ipairs(container:GetChildren()) do
            if gui:IsA("ScreenGui") and (gui.Name == "NebulaTSBv16" or gui.Name == "NebulaTSBv17" or gui.Name == "NebulaTSBv18" or gui.Name == "TSB_Delta_Clean" or gui.Name == "TSB_Delta_V20" or gui.Name == "TSB_Delta_V21") then
                gui:Destroy()
            end
        end
    end)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TSB_Delta_V21"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 150
local guiOK = pcall(function() ScreenGui.Parent = CoreGui end)
if not guiOK then
    local alternate = Player:FindFirstChildOfClass("PlayerGui") or Player:WaitForChild("PlayerGui", 7)
    if not alternate then error("NEBULA: no UI parent") end
    ScreenGui.Parent = alternate
end
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(480, 680)
local PANEL_W = math.max(245, math.min(324, math.floor(viewport.X - 18)))
local PANEL_H = math.max(285, math.min(430, math.floor(viewport.Y - 30)))
MainFrame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
MainFrame.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
MainFrame.BackgroundColor3 = Color3.fromRGB(19, 22, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = false
MainFrame.Parent = ScreenGui

local MainFrameCorner = Instance.new("UICorner")
MainFrameCorner.CornerRadius = UDim.new(0, 9)
MainFrameCorner.Parent = MainFrame

local MainFrameStroke = Instance.new("UIStroke")
MainFrameStroke.Color = Color3.fromRGB(24, 211, 240)
MainFrameStroke.Thickness = 1.2
MainFrameStroke.Parent = MainFrame

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 32)
TitleBar.BackgroundColor3 = Color3.fromRGB(17, 44, 58)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame

local TitleBarCorner = Instance.new("UICorner")
TitleBarCorner.CornerRadius = UDim.new(0, 4)
TitleBarCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -77, 1, 0)
Title.BackgroundTransparency = 1
Title.Text = "TSB DELTA · v21"
Title.TextColor3 = Color3.fromRGB(134, 246, 255)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Position = UDim2.new(0, 9, 0, 0)
Title.Parent = TitleBar
Title.Active = true

local CloseButton = Instance.new("TextButton")
CloseButton.Position = UDim2.new(1, -32, 0, 1)
CloseButton.Size = UDim2.fromOffset(30, 30)
CloseButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
CloseButton.BorderSizePixel = 0
CloseButton.Text = "X"
CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseButton.Font = Enum.Font.SourceSansBold
CloseButton.TextSize = 15
CloseButton.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 4)
CloseCorner.Parent = CloseButton

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Name = "Minimize"
MinimizeButton.Position = UDim2.new(1, -64, 0, 1)
MinimizeButton.Size = UDim2.fromOffset(30, 30)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
MinimizeButton.BorderSizePixel = 0
MinimizeButton.Text = "-"
MinimizeButton.TextColor3 = Color3.new(1, 1, 1)
MinimizeButton.Font = Enum.Font.SourceSansBold
MinimizeButton.TextSize = 21
MinimizeButton.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 4)
MinCorner.Parent = MinimizeButton

-- Keep close/minimize operational even if a later feature fails to initialize.
local minimized = false
local Shutdown = nil
local closing = false
local TextService = game:GetService("TextService")
local okMeasure, measured = pcall(function()
    return TextService:GetTextSize(Title.Text, Title.TextSize, Title.Font, Vector2.new(500, 32)).X
end)
local COLLAPSED_W = math.min(PANEL_W, math.max(155, math.ceil(okMeasure and measured or 130) + 80))

local function hideOrShowMainChildren(visible)
    for _, child in ipairs(MainFrame:GetChildren()) do
        if child:IsA("GuiObject") and child ~= TitleBar then
            child.Visible = visible
        end
    end
end
local function ensurePanelOnscreen()
    if not MainFrame.Parent then return end
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    local position = MainFrame.AbsolutePosition
    local size = MainFrame.AbsoluteSize
    local nextX = math.clamp(position.X, 2, math.max(2, vp.X - size.X - 3))
    local nextY = math.clamp(position.Y, 2, math.max(2, vp.Y - size.Y - 3))
    local correction = Vector2.new(nextX-position.X, nextY-position.Y)
    if correction.Magnitude > 1 then
        local old = MainFrame.Position
        MainFrame.Position = UDim2.new(old.X.Scale, old.X.Offset + correction.X,
            old.Y.Scale, old.Y.Offset + correction.Y)
    end
end
MinimizeButton.Activated:Connect(function()
    if closing then return end
    minimized = not minimized
    MainFrame.Size = UDim2.fromOffset(minimized and COLLAPSED_W or PANEL_W,
        minimized and 32 or PANEL_H)
    MinimizeButton.Text = minimized and "+" or "−"
    hideOrShowMainChildren(not minimized)
    task.defer(ensurePanelOnscreen)
end)
local function emergencyClose()
    if closing then return end
    if Shutdown then
        Shutdown()
    else
        closing = true
        pcall(function() ScreenGui:Destroy() end)
    end
end
CloseButton.Activated:Connect(emergencyClose)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Position = UDim2.new(0, 7, 0, 28)
StatusLabel.Size = UDim2.new(1, -14, 0, 18)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Выбери игрока → START"
StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
StatusLabel.Font = Enum.Font.SourceSans
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = MainFrame

local SelectionFrame = Instance.new("Frame")
SelectionFrame.Position = UDim2.new(0, 7, 0, 49)
SelectionFrame.Size = UDim2.new(1, -14, 0, 140)
SelectionFrame.BackgroundColor3 = Color3.fromRGB(27, 31, 43)
SelectionFrame.BorderSizePixel = 0
SelectionFrame.Parent = MainFrame

local SelectionCorner = Instance.new("UICorner")
SelectionCorner.CornerRadius = UDim.new(0, 4)
SelectionCorner.Parent = SelectionFrame

local PlayerScrollFrame = Instance.new("ScrollingFrame")
PlayerScrollFrame.Position = UDim2.new(0, 4, 0, 4)
PlayerScrollFrame.Size = UDim2.new(1, -8, 1, -8)
PlayerScrollFrame.BackgroundTransparency = 1
PlayerScrollFrame.BorderSizePixel = 0
PlayerScrollFrame.ScrollBarThickness = 4
PlayerScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(255, 80, 80)
PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayerScrollFrame.Parent = SelectionFrame

local StartButton = Instance.new("TextButton")
StartButton.Position = UDim2.new(0, 7, 0, 196)
StartButton.Size = UDim2.new(0.5, -10, 0, 28)
StartButton.BackgroundColor3 = Color3.fromRGB(0, 180, 0)
StartButton.BorderSizePixel = 0
StartButton.Text = "START"
StartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StartButton.Font = Enum.Font.SourceSansBold
StartButton.TextSize = 12
StartButton.Parent = MainFrame

local StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 4)
StartCorner.Parent = StartButton

local StopButton = Instance.new("TextButton")
StopButton.Position = UDim2.new(0.5, 3, 0, 196)
StopButton.Size = UDim2.new(0.5, -10, 0, 28)
StopButton.BackgroundColor3 = Color3.fromRGB(180, 0, 0)
StopButton.BorderSizePixel = 0
StopButton.Text = "STOP"
StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StopButton.Font = Enum.Font.SourceSansBold
StopButton.TextSize = 12
StopButton.Parent = MainFrame

local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 4)
StopCorner.Parent = StopButton

local function makeToggle(name, x, width)
    local button = Instance.new("TextButton")
    button.Name = name:gsub(" ", "")
    button.Position = UDim2.new(0, x, 0, 231)
    button.Size = UDim2.new(0, width, 0, 21)
    button.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    button.BorderSizePixel = 0
    button.TextColor3 = Color3.fromRGB(255, 80, 80)
    button.Font = Enum.Font.SourceSansBold
    button.TextSize = 10
    button.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 4)
    corner.Parent = button
    return button
end

local SafeToggle = makeToggle("SAVE ZONA", 7, 94)
local ResetToggle = makeToggle("AUTO RESET", 108, 95)
local InvisToggle = makeToggle("INVIS", 7, 196)
InvisToggle.Position = UDim2.new(0, 7, 0, 258)

local function paintToggle(button, title, enabled)
    button.Text = title .. (enabled and ": ON" or ": OFF")
    button.TextColor3 = Color3.new(1, 1, 1)
    button.BackgroundColor3 = enabled and Color3.fromRGB(24, 125, 65) or Color3.fromRGB(150, 38, 48)
end

paintToggle(SafeToggle, "SAVE ZONA", CONFIG.SAFE_ZONE)
paintToggle(ResetToggle, "AUTO RESET", CONFIG.AUTO_RESET)
paintToggle(InvisToggle, "INVIS", CONFIG.INVISIBLE)

-- User-controlled movement speed. A numeric TextBox sits to the right of toggle.
local SpeedToggle = makeToggle("SPEED", 7, 94)
SpeedToggle.Position = UDim2.fromOffset(7, 289)
local SpeedInput = Instance.new("TextBox")
SpeedInput.Name = "SpeedValue"
SpeedInput.Position = UDim2.fromOffset(108, 289)
SpeedInput.Size = UDim2.fromOffset(95, 21)
SpeedInput.BackgroundColor3 = Color3.fromRGB(40, 46, 62)
SpeedInput.TextColor3 = Color3.fromRGB(255, 255, 255)
SpeedInput.PlaceholderText = "8-120"
SpeedInput.Text = tostring(CONFIG.SPEED_VALUE)
SpeedInput.ClearTextOnFocus = false
SpeedInput.Font = Enum.Font.SourceSansBold
SpeedInput.TextSize = 12
SpeedInput.Parent = MainFrame
local SpeedCorner = Instance.new("UICorner")
SpeedCorner.CornerRadius = UDim.new(0, 4)
SpeedCorner.Parent = SpeedInput

-- Auto Evade is automatic in v10: no separate toggle needed.
-- Distance is kept below SPEED and used only by the START positioner.
local DistanceLabel = Instance.new("TextLabel")
DistanceLabel.Position = UDim2.fromOffset(7, 317)
DistanceLabel.Size = UDim2.fromOffset(94, 21)
DistanceLabel.BackgroundColor3 = Color3.fromRGB(40, 46, 62)
DistanceLabel.BorderSizePixel = 0
DistanceLabel.Text = "DISTANCE"
DistanceLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
DistanceLabel.TextSize = 10
DistanceLabel.Font = Enum.Font.SourceSansBold
DistanceLabel.Parent = MainFrame
Instance.new("UICorner", DistanceLabel).CornerRadius = UDim.new(0, 4)

local DistanceInput = Instance.new("TextBox")
DistanceInput.Name = "DistanceValue"
DistanceInput.Position = UDim2.fromOffset(108, 317)
DistanceInput.Size = UDim2.fromOffset(95, 21)
DistanceInput.BackgroundColor3 = Color3.fromRGB(40, 46, 62)
DistanceInput.TextColor3 = Color3.new(1, 1, 1)
DistanceInput.Font = Enum.Font.SourceSansBold
DistanceInput.TextSize = 12
DistanceInput.ClearTextOnFocus = false
DistanceInput.PlaceholderText = "2.1-8"
DistanceInput.Text = tostring(CONFIG.BEHIND_STUDS)
DistanceInput.Parent = MainFrame
Instance.new("UICorner", DistanceInput).CornerRadius = UDim.new(0, 4)
paintToggle(SpeedToggle, "SPEED", CONFIG.SPEED_ENABLED)

-- Additional controls preserve v10 layout; placed underneath DISTANCE.
local TpOnceButton = makeToggle("TP ONCE", 7, 94)
TpOnceButton.Position = UDim2.fromOffset(7, 345)
TpOnceButton.Text = "TP ONCE"
TpOnceButton.TextColor3 = Color3.new(1, 1, 1)
TpOnceButton.BackgroundColor3 = Color3.fromRGB(22, 93, 148)

local RandomTPButton = makeToggle("RANDOM TP", 108, 95)
RandomTPButton.Position = UDim2.fromOffset(108, 345)
RandomTPButton.Text = "RANDOM TP"
RandomTPButton.TextColor3 = Color3.new(1, 1, 1)
RandomTPButton.BackgroundColor3 = Color3.fromRGB(22, 93, 148)

local TrashAutoButton = makeToggle("TRASH AUTO", 7, 94)
TrashAutoButton.Position = UDim2.fromOffset(7, 373)
TrashAutoButton.Text = "TRASH AUTO"
TrashAutoButton.TextColor3 = Color3.new(1, 1, 1)
TrashAutoButton.BackgroundColor3 = Color3.fromRGB(95, 66, 140)

local TrashInfo = Instance.new("TextLabel")
TrashInfo.Position = UDim2.fromOffset(7, 403)
TrashInfo.Size = UDim2.fromOffset(196, 44)
TrashInfo.BackgroundTransparency = 1
TrashInfo.TextWrapped = true
TrashInfo.TextYAlignment = Enum.TextYAlignment.Top
TrashInfo.TextXAlignment = Enum.TextXAlignment.Left
TrashInfo.Font = Enum.Font.SourceSans
TrashInfo.TextSize = 10
TrashInfo.TextColor3 = Color3.fromRGB(160, 185, 212)
TrashInfo.Text = "Мусор: обычное взятие и бросок. Ускорение доступно при переноске."
TrashInfo.Parent = MainFrame

-- V16 ROOT CAUSE: missing declarations below crashed relayout(nil, ...).
-- Create all controls before they are moved into tab pages.
local TrashReturnButton = makeToggle("TRASH RETURN", 7, 196)
TrashReturnButton.Text = "PICKUP + RETURN"
TrashReturnButton.BackgroundColor3 = Color3.fromRGB(68, 70, 135)
TrashReturnButton.TextColor3 = Color3.new(1, 1, 1)
local AimToggle = makeToggle("AIM LOCK", 7, 196)
paintToggle(AimToggle, "AIM LOCK", CONFIG.AIM_ENABLED)
local AutoStartButton = makeToggle("RANDOM START", 7, 94)
AutoStartButton.Text = "▶ START"
AutoStartButton.TextColor3 = Color3.new(1, 1, 1)
AutoStartButton.BackgroundColor3 = Color3.fromRGB(17, 143, 89)
local AutoStopButton = makeToggle("RANDOM STOP", 108, 95)
AutoStopButton.Text = "■ STOP"
AutoStopButton.TextColor3 = Color3.new(1, 1, 1)
AutoStopButton.BackgroundColor3 = Color3.fromRGB(151, 42, 54)
local AutoStatus = Instance.new("TextLabel")
AutoStatus.Name = "RandomCycleStatus"
AutoStatus.BackgroundColor3 = Color3.fromRGB(26, 49, 56)
AutoStatus.TextColor3 = Color3.fromRGB(191, 247, 246)
AutoStatus.Font = Enum.Font.SourceSansBold
AutoStatus.TextSize = 12
AutoStatus.TextWrapped = true
AutoStatus.Text = "ЦИКЛ: выключен"
AutoStatus.Parent = MainFrame
Instance.new("UICorner", AutoStatus).CornerRadius = UDim.new(0, 5)

local Refs = {}
do
-- ============================================================
-- NEBULA v16 | Compact mobile panel, four pages and draggable title
-- ============================================================
MainFrame.ClipsDescendants = true
Title.Text = "TSB DELTA · v21"
StatusLabel.Parent = MainFrame
StatusLabel.Position = UDim2.fromOffset(10, 38)
StatusLabel.Size = UDim2.new(1, -20, 0, 21)
StatusLabel.TextSize = 12
StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd

local TabsBar = Instance.new("Frame")
TabsBar.Name = "Tabs"
TabsBar.BackgroundTransparency = 1
TabsBar.Position = UDim2.fromOffset(7, 64)
TabsBar.Size = UDim2.new(1, -14, 0, 34)
TabsBar.Parent = MainFrame

local PageHost = Instance.new("Frame")
PageHost.Name = "PageHost"
PageHost.BackgroundTransparency = 1
PageHost.Position = UDim2.fromOffset(7, 103)
PageHost.Size = UDim2.new(1, -14, 1, -112)
PageHost.ClipsDescendants = true
PageHost.Parent = MainFrame

local pages, tabButtons = {}, {}
local tabNames = {"ЦЕЛЬ", "РАНДОМ", "ФУНКЦИИ", "ДОП."}
for index, tabName in ipairs(tabNames) do
    local button = Instance.new("TextButton")
    button.Name = "Tab" .. index
    button.Size = UDim2.new(0.25, -3, 1, 0)
    button.Position = UDim2.new((index-1)*0.25, index == 1 and 0 or 1, 0, 0)
    button.BackgroundColor3 = Color3.fromRGB(31, 40, 55)
    button.TextColor3 = Color3.fromRGB(220, 235, 248)
    button.Font = Enum.Font.SourceSansBold
    button.TextSize = 11
    button.Text = tabName
    button.BorderSizePixel = 0
    button.Parent = TabsBar
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 6)
    tabButtons[index] = button
    local page = Instance.new("Frame")
    page.Name = "Page" .. index
    page.BackgroundColor3 = Color3.fromRGB(24, 29, 41)
    page.BorderSizePixel = 0
    page.Size = UDim2.fromScale(1, 1)
    page.Visible = index == 1
    page.Parent = PageHost
    Instance.new("UICorner", page).CornerRadius = UDim.new(0, 6)
    pages[index] = page
end

local activePage = 1
local function showPage(index)
    activePage = index
    for i, page in ipairs(pages) do
        page.Visible = i == index
        tabButtons[i].BackgroundColor3 = i == index and Color3.fromRGB(15, 131, 158) or Color3.fromRGB(31, 40, 55)
        tabButtons[i].TextColor3 = i == index and Color3.new(1,1,1) or Color3.fromRGB(190, 210, 228)
    end
end
for i, tab in ipairs(tabButtons) do
    tab.Activated:Connect(function() showPage(i) end)
end
showPage(1)

local function relayout(obj, parent, x, y, w, h)
    obj.Parent = parent
    obj.Position = UDim2.fromOffset(x, y)
    obj.Size = UDim2.fromOffset(w, h)
end
local PAGE_W = PANEL_W - 14
local PAGE_H = PANEL_H - 112
local innerW = PAGE_W - 16
local halfW = math.floor((innerW - 8) / 2)
local rightX = 8 + halfW + 8
local rightW = innerW - halfW - 8
local function infoLabel(parent, message, y, h)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(157, 185, 204)
    label.Font = Enum.Font.SourceSans
    label.TextSize = 12
    label.TextWrapped = true
    label.TextYAlignment = Enum.TextYAlignment.Top
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Text = message
    relayout(label, parent, 8, y, innerW, h)
    return label
end

-- Target selection occupies a dedicated scroll; controls do not move when player list updates.
local TargetPage = pages[1]
local TargetScroll = Instance.new("ScrollingFrame")
TargetScroll.Name = "TargetControls"
TargetScroll.BackgroundTransparency = 1
TargetScroll.BorderSizePixel = 0
TargetScroll.Size = UDim2.fromScale(1, 1)
TargetScroll.ScrollBarThickness = 3
TargetScroll.ScrollingDirection = Enum.ScrollingDirection.Y
TargetScroll.Parent = TargetPage
local targetListHeight = math.max(112, PAGE_H - 175)
relayout(SelectionFrame, TargetScroll, 8, 8, innerW, targetListHeight)
PlayerScrollFrame.Size = UDim2.new(1, -8, 1, -8)
relayout(StartButton, TargetScroll, 8, targetListHeight + 16, halfW, 35)
relayout(StopButton, TargetScroll, rightX, targetListHeight + 16, rightW, 35)
StartButton.Text = "▶ START / TP"
StopButton.Text = "ОСТАНОВИТЬ"
StartButton.TextSize = 11
StopButton.TextSize = 11
relayout(TpOnceButton, TargetScroll, 8, targetListHeight + 58, halfW, 34)
relayout(RandomTPButton, TargetScroll, rightX, targetListHeight + 58, rightW, 34)
TpOnceButton.Text = "TP СЕЙЧАС"
RandomTPButton.Text = "TP РАНДОМ"
relayout(DistanceLabel, TargetScroll, 8, targetListHeight + 100, halfW, 34)
DistanceLabel.Text = "ДИСТАНЦИЯ"
relayout(DistanceInput, TargetScroll, rightX, targetListHeight + 100, rightW, 34)
local LeadToggle = Instance.new("TextButton")
LeadToggle.Name = "LeadToggle"
LeadToggle.BorderSizePixel = 0
LeadToggle.Font = Enum.Font.SourceSansBold
LeadToggle.TextSize = 12
LeadToggle.TextColor3 = Color3.new(1, 1, 1)
relayout(LeadToggle, TargetScroll, 8, targetListHeight + 142, innerW, 35)
Instance.new("UICorner", LeadToggle).CornerRadius = UDim.new(0, 6)
infoLabel(TargetScroll, "Выбери игрока (галочка), затем START. TP повторяется непрерывно; STOP прекращает. Автоатак нет.", targetListHeight + 185, 48)
TargetScroll.CanvasSize = UDim2.fromOffset(0, targetListHeight + 250)

-- Dedicated auto-cycle page: START/STOP and cooldowns always visible.
local CyclePage = pages[2]
local CycleScroll = Instance.new("ScrollingFrame")
CycleScroll.Name = "CycleScroll"
CycleScroll.BackgroundTransparency = 1
CycleScroll.BorderSizePixel = 0
CycleScroll.Size = UDim2.fromScale(1, 1)
CycleScroll.CanvasSize = UDim2.fromOffset(0, 426)
CycleScroll.ScrollBarThickness = 3
CycleScroll.ScrollingDirection = Enum.ScrollingDirection.Y
CycleScroll.Parent = CyclePage
relayout(AutoStatus, CycleScroll, 8, 8, innerW, 53)
AutoStatus.TextSize = 12
AutoStatus.TextWrapped = true
AutoStatus.Text = "Рандомный TP • способности только вручную"
relayout(AutoStartButton, CycleScroll, 8, 65, halfW, 39)
AutoStartButton.Text = "▶ START"
relayout(AutoStopButton, CycleScroll, rightX, 65, rightW, 39)
AutoStopButton.Text = "■ STOP"
local function newCycleInput(name, x, value, placeholder, width)
    local input = Instance.new("TextBox")
    input.Name = name
    input.Text = tostring(value)
    input.PlaceholderText = placeholder
    input.ClearTextOnFocus = false
    input.Font = Enum.Font.SourceSansBold
    input.TextSize = 14
    input.TextColor3 = Color3.fromRGB(245, 249, 255)
    input.BackgroundColor3 = Color3.fromRGB(41, 52, 69)
    relayout(input, CycleScroll, x, 159, width, 34)
    Instance.new("UICorner", input).CornerRadius = UDim.new(0, 6)
    return input
end
local SkillCD1Input = newCycleInput("CD1", 8, CONFIG.RANDOM_CD1, "Навык 1", halfW)
local SkillCD2Input = newCycleInput("CD2", rightX, CONFIG.RANDOM_CD2, "Навык 2", rightW)
local SkillOneButton = makeToggle("SKILL 1 USED", 8, halfW)
local SkillTwoButton = makeToggle("SKILL 2 USED", rightX, rightW)
relayout(SkillOneButton, CycleScroll, 8, 115, halfW, 35)
relayout(SkillTwoButton, CycleScroll, rightX, 115, rightW, 35)
SkillOneButton.Text = "ИСП. НАВЫК 1"
SkillTwoButton.Text = "ИСП. НАВЫК 2"
SkillOneButton.BackgroundColor3 = Color3.fromRGB(36, 102, 143)
SkillTwoButton.BackgroundColor3 = Color3.fromRGB(36, 102, 143)
local SaveCenterButton = makeToggle("SAVE CENTER", 8, innerW)
relayout(SaveCenterButton, CycleScroll, 8, 206, innerW, 36)
SaveCenterButton.Text = "ЗАПОМНИТЬ ЦЕНТР"
SaveCenterButton.BackgroundColor3 = Color3.fromRGB(36, 102, 143)
local GoCenterButton = makeToggle("GO CENTER", 8, innerW)
relayout(GoCenterButton, CycleScroll, 8, 249, innerW, 36)
GoCenterButton.Text = "TP В ЦЕНТР"
GoCenterButton.BackgroundColor3 = Color3.fromRGB(36, 102, 143)
local CDsLabel = infoLabel(CycleScroll, "Кнопки «исп.» отмечают твои нажатия, НЕ применяют способности. При двух CD — в центр; возврат к случайной цели после восстановления обеих.", 294, 90)

-- Feature page can scroll independently (all old buttons remain functional).
local ControlsScroll = Instance.new("ScrollingFrame")
ControlsScroll.Name = "FeatureScroll"
ControlsScroll.BackgroundTransparency = 1
ControlsScroll.BorderSizePixel = 0
ControlsScroll.Position = UDim2.fromOffset(3, 4)
ControlsScroll.Size = UDim2.new(1, -6, 1, -8)
ControlsScroll.CanvasSize = UDim2.fromOffset(0, 333)
ControlsScroll.ScrollBarThickness = 4
ControlsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
ControlsScroll.ScrollBarImageColor3 = Color3.fromRGB(24, 211, 240)
ControlsScroll.Parent = pages[3]
local function feature(obj, x, y, w, h)
    relayout(obj, ControlsScroll, x, y, w, h or 34)
    obj.TextSize = 12
end
feature(SafeToggle, 8, 8, halfW, 34)
feature(ResetToggle, rightX, 8, rightW, 34)
feature(InvisToggle, 8, 50, innerW, 34)
feature(SpeedToggle, 8, 92, halfW, 34)
feature(SpeedInput, rightX, 92, rightW, 34)
feature(TrashAutoButton, 8, 134, innerW, 34)
feature(TrashReturnButton, 8, 176, innerW, 34)
TrashReturnButton.Text = "ВЗЯТЬ МУСОР И ВЕРНУТЬСЯ"
feature(AimToggle, 8, 218, innerW, 34)
TrashInfo.Parent = ControlsScroll
TrashInfo.Position = UDim2.fromOffset(8, 265)
TrashInfo.Size = UDim2.fromOffset(innerW, 58)
TrashInfo.TextSize = 11

-- Extras: independent scroll preserves compact panel dimensions.
local ExtraPage = pages[4]
local ExtraScroll = Instance.new("ScrollingFrame")
ExtraScroll.Name = "ExtraScroll"
ExtraScroll.BackgroundTransparency = 1
ExtraScroll.BorderSizePixel = 0
ExtraScroll.Size = UDim2.fromScale(1, 1)
ExtraScroll.CanvasSize = UDim2.fromOffset(0, 462)
ExtraScroll.ScrollBarThickness = 3
ExtraScroll.ScrollingDirection = Enum.ScrollingDirection.Y
ExtraScroll.Parent = ExtraPage

local OptimizationToggle = Instance.new("TextButton")
OptimizationToggle.Name = "OptimizationToggle"
OptimizationToggle.BorderSizePixel = 0
OptimizationToggle.Font = Enum.Font.SourceSansBold
OptimizationToggle.TextSize = 14
OptimizationToggle.TextColor3 = Color3.new(1, 1, 1)
relayout(OptimizationToggle, ExtraScroll, 8, 9, innerW, 40)
Instance.new("UICorner", OptimizationToggle).CornerRadius = UDim.new(0, 6)
infoLabel(ExtraScroll, "Тени декора, частицы и тяжёлые эффекты: OFF. Игроки, физика, коллизии и интерфейс сохраняются. Можно отключить режим.", 57, 64)

local DistanceToggle = Instance.new("TextButton")
DistanceToggle.Name = "DistanceEcoToggle"
DistanceToggle.BorderSizePixel = 0
DistanceToggle.Font = Enum.Font.SourceSansBold
DistanceToggle.TextSize = 13
DistanceToggle.TextColor3 = Color3.new(1,1,1)
relayout(DistanceToggle, ExtraScroll, 8, 125, innerW, 36)
Instance.new("UICorner", DistanceToggle).CornerRadius = UDim.new(0, 6)

local RadiusLabel = infoLabel(ExtraScroll, "Радиус декора (80–300 studs):", 172, 33)
RadiusLabel.Size = UDim2.fromOffset(halfW + 20, 34)
local RadiusInput = Instance.new("TextBox")
RadiusInput.Name = "CullingRadius"
RadiusInput.Text = tostring(CONFIG.VISUAL_RADIUS)
RadiusInput.PlaceholderText = "160"
RadiusInput.ClearTextOnFocus = false
RadiusInput.Font = Enum.Font.SourceSansBold
RadiusInput.TextSize = 15
RadiusInput.TextColor3 = Color3.fromRGB(245,249,255)
RadiusInput.BackgroundColor3 = Color3.fromRGB(41,52,69)
relayout(RadiusInput, ExtraScroll, rightX, 172, rightW, 34)
Instance.new("UICorner", RadiusInput).CornerRadius = UDim.new(0, 6)
infoLabel(ExtraScroll, "Важно: скрипт не может включить серверный StreamingEnabled. Коллизии, физика, NPC и боевые объекты остаются. Изменения графики обратимы.", 217, 79)

local HKGButton = Instance.new("TextButton")
HKGButton.Name = "ExternalHKGVoid"
HKGButton.BorderSizePixel = 0
HKGButton.BackgroundColor3 = Color3.fromRGB(76, 75, 149)
HKGButton.TextColor3 = Color3.new(1, 1, 1)
HKGButton.Font = Enum.Font.SourceSansBold
HKGButton.TextSize = 15
HKGButton.Text = "▶ ЗАПУСТИТЬ HKG VOID"
relayout(HKGButton, ExtraScroll, 8, 311, innerW, 43)
Instance.new("UICorner", HKGButton).CornerRadius = UDim.new(0, 7)
local HKGStatus = infoLabel(ExtraScroll, "Дополнительное меню запускается отдельно. Внешний код не проверен — запуск на твой выбор.", 364, 72)

-- Minimize/restore and title-bar X are connected before feature pages.

-- Dragging only by the header avoids accidental movement during menu scrolling.
local dragStart, frameStart, dragInput = nil, nil, nil
Title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        frameStart = MainFrame.AbsolutePosition
    end
end)
Title.InputEnded:Connect(function(input)
    if dragInput == input then dragInput = nil end
end)
local moveConnection = UserInputService.InputChanged:Connect(function(input)
    if not dragInput or not dragStart or not frameStart then return end
    if input ~= dragInput and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
    local delta = Vector2.new(input.Position.X, input.Position.Y) - dragStart
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(900, 600)
    local size = MainFrame.AbsoluteSize
    local x = math.clamp(frameStart.X + delta.X, 1, math.max(1, vp.X-size.X-1))
    local y = math.clamp(frameStart.Y + delta.Y, 1, math.max(1, vp.Y-size.Y-1))
    MainFrame.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end)


Refs.AutoStatus = AutoStatus
Refs.AutoStartButton = AutoStartButton
Refs.AutoStopButton = AutoStopButton
Refs.SkillOneButton = SkillOneButton
Refs.SkillTwoButton = SkillTwoButton
Refs.SaveCenterButton = SaveCenterButton
Refs.GoCenterButton = GoCenterButton
Refs.LeadToggle = LeadToggle
Refs.SkillCD1Input = SkillCD1Input
Refs.SkillCD2Input = SkillCD2Input
Refs.OptimizationToggle = OptimizationToggle
Refs.DistanceToggle = DistanceToggle
Refs.RadiusInput = RadiusInput
Refs.HKGButton = HKGButton
Refs.HKGStatus = HKGStatus
Refs.moveConnection = moveConnection
end


-- Persistent left-side menu toggle. Does not affect camera or game scene.
local DockButton = Instance.new("TextButton")
DockButton.Name = "SideMenuToggle"
DockButton.Size = UDim2.fromOffset(43, 43)
DockButton.Position = UDim2.fromOffset(12, 168)
DockButton.BackgroundColor3 = Color3.fromRGB(25, 83, 110)
DockButton.BorderSizePixel = 0
DockButton.Text = "≡"
DockButton.TextSize = 28
DockButton.Font = Enum.Font.SourceSansBold
DockButton.TextColor3 = Color3.new(1, 1, 1)
DockButton.ZIndex = 25
DockButton.Parent = ScreenGui
Instance.new("UICorner", DockButton).CornerRadius = UDim.new(0, 10)
DockButton.Activated:Connect(function()
    if closing then return end
    MainFrame.Visible = not MainFrame.Visible
    DockButton.BackgroundColor3 = MainFrame.Visible
        and Color3.fromRGB(25, 83, 110) or Color3.fromRGB(24, 124, 86)
    if MainFrame.Visible then task.defer(ensurePanelOnscreen) end
end)

-- Touch-friendly circular AIM button, draggable and without target overlay.
local AimHud = Instance.new("TextButton")
AimHud.Name = "AimLockSelect"
AimHud.Size = UDim2.fromOffset(44, 44)
AimHud.Position = UDim2.fromOffset(16, 105)
AimHud.BackgroundColor3 = Color3.fromRGB(91, 96, 107)
AimHud.BackgroundTransparency = 0.12
AimHud.BorderSizePixel = 0
AimHud.Text = "◎"
AimHud.Font = Enum.Font.SourceSansBold
AimHud.TextSize = 27
AimHud.TextColor3 = Color3.fromRGB(230, 235, 240)
AimHud.Visible = false
AimHud.ZIndex = 20
AimHud.Parent = ScreenGui
Instance.new("UICorner", AimHud).CornerRadius = UDim.new(1, 0)
local AimHudStroke = Instance.new("UIStroke", AimHud)
AimHudStroke.Thickness = 2
AimHudStroke.Color = Color3.fromRGB(176, 183, 197)

-- ============================================================
-- VARIABLES
-- ============================================================
local StopRandomCycle = nil
local StartRandomCycle = nil
local StartBackstab = nil
local RandomCycle = {
    enabled = false, token = 0, phase = "off", target = nil, centered = false,
    followConnection = nil,
    readyAt = {[1] = 0, [2] = 0},

}
local SelectedTarget = nil
local PlayerButtons = {}
local BackstabActive = false
local FollowWanted = false -- stays armed during respawn until STOP
local PositionConnection = nil
local HealthConnection = nil
local SafePlatform = nil
local SafeReturn = nil
local SafeMode = nil
local PreviousAutoRotate = nil
local CharacterConnection = nil
local CleanupConnections = {}
local DeathConnection = nil
local ResetInProgress = false
local CurrentTrackedHumanoid = nil
local SafeTriggered = false
local InvisHardConnection = nil
local HiddenFolder = nil
local DescendantConnection = nil
local Evading = false -- compatibility guard only; never set true in v16
local OriginalWalkSpeed = nil
local SpeedHumanoid = nil
local CurrentSpeedWritten = nil
local SpeedLoopConnection = nil
local Active = true
local TrashBusy = false
local TrashAutoEnabled = false
local TrashToken = 0
local TrashPhase = "idle"
local AimTarget = nil
local AimRenderName = "TSB_DELTA_AIM_V21"
local TrashIndex = {}
local TrashBlacklist = {}
local TrashIndexReady = false
local TrashIndexConnection = nil
local LastTrashScanAt = 0
local CachedTrash = nil
local LastRealSpeed = 0
local MoveRenderName = "TSB_DELTA_MOVE_V21"

-- AIM joystick-style draggable button. Works with touch and mouse.
-- Ignore the click that follows a drag, so moving the button never drops the target.
local aimDragInput = nil
local aimDragOrigin = nil
local aimDragPosition = nil
local aimDragged = false
local aimSuppressClickUntil = 0

local function moveAimHud(inputPosition)
    if not aimDragOrigin or not aimDragPosition then return end
    local delta = Vector2.new(inputPosition.X, inputPosition.Y) - aimDragOrigin
    if delta.Magnitude >= 7 then aimDragged = true end
    if not aimDragged then return end
    local camera = workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(800, 600)
    local x = math.clamp(aimDragPosition.X + delta.X, 4, math.max(4, viewport.X - AimHud.AbsoluteSize.X - 4))
    local y = math.clamp(aimDragPosition.Y + delta.Y, 4, math.max(4, viewport.Y - AimHud.AbsoluteSize.Y - 4))
    AimHud.Position = UDim2.fromOffset(math.floor(x), math.floor(y))
end

table.insert(CleanupConnections, AimHud.InputBegan:Connect(function(input)
    if input.UserInputType ~= Enum.UserInputType.Touch
       and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    aimDragInput = input
    aimDragged = false
    aimDragOrigin = Vector2.new(input.Position.X, input.Position.Y)
    aimDragPosition = AimHud.AbsolutePosition
end))
table.insert(CleanupConnections, UserInputService.InputChanged:Connect(function(input)
    if not aimDragInput then return end
    if aimDragInput.UserInputType == Enum.UserInputType.Touch then
        if input ~= aimDragInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseMovement then
        return
    end
    moveAimHud(input.Position)
end))
table.insert(CleanupConnections, UserInputService.InputEnded:Connect(function(input)
    if not aimDragInput then return end
    if aimDragInput.UserInputType == Enum.UserInputType.Touch then
        if input ~= aimDragInput then return end
    elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
        return
    end
    if aimDragged then aimSuppressClickUntil = os.clock() + 0.35 end
    aimDragInput = nil
    aimDragOrigin = nil
    aimDragPosition = nil
end))


-- ============================================================
-- UTILITIES
-- ============================================================
local cachedPing, lastPingRead = 50, -1e9
local function getPing()
    if os.clock() - lastPingRead < 0.75 then return cachedPing end
    lastPingRead = os.clock()
    local ok, ping = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
    end)
    if ok and type(ping) == "number" then cachedPing = math.clamp(ping, 0, 500) end
    return cachedPing
end

local function isAlive(plr)
    if not plr or not plr.Character then return false end
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    return hum and hum.Health > 0
end

local function getHRP(plr)
    if not plr or not plr.Character then return nil end
    return plr.Character:FindFirstChild("HumanoidRootPart")
end

-- ============================================================
-- INVISIBILITY — client-side only
-- ============================================================
local Invisibility = {}
local OriginalPartState = setmetatable({}, {__mode = "k"})

local function storeAndHide(obj)
    if not obj then return end

    if obj:IsA("BasePart") then
        if OriginalPartState[obj] == nil then
            OriginalPartState[obj] = {
                Transparency = obj.Transparency,
                LocalTransparencyModifier = obj.LocalTransparencyModifier,
                CanCollide = obj.CanCollide,
                Anchored = obj.Anchored,
                Parent = obj.Parent,
            }
        end
        obj.Transparency = 1
        obj.LocalTransparencyModifier = 1
    elseif obj:IsA("Decal") or obj:IsA("Texture") then
        if OriginalPartState[obj] == nil then
            OriginalPartState[obj] = { Transparency = obj.Transparency }
        end
        obj.Transparency = 1
    elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
        or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
        if OriginalPartState[obj] == nil then
            OriginalPartState[obj] = { Enabled = obj.Enabled }
        end
        obj.Enabled = false
    elseif obj:IsA("Accessory") or obj:IsA("Hat") or obj:IsA("Accoutrement") then
        for _, d in ipairs(obj:GetDescendants()) do
            storeAndHide(d)
        end
        if OriginalPartState[obj] == nil then
            OriginalPartState[obj] = { Parent = obj.Parent }
        end
        pcall(function()
            if HiddenFolder then obj.Parent = HiddenFolder end
        end)
    elseif obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") or obj:IsA("Clothing") then
        if OriginalPartState[obj] == nil then
            OriginalPartState[obj] = { Parent = obj.Parent }
        end
        pcall(function()
            if HiddenFolder then obj.Parent = HiddenFolder end
        end)
    elseif obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
        if OriginalPartState[obj] == nil then
            OriginalPartState[obj] = { Enabled = obj.Enabled }
        end
        obj.Enabled = false
    end
end

local function forceHideCharacter(char)
    if not char then return end

    if not HiddenFolder or not HiddenFolder.Parent then
        HiddenFolder = Instance.new("Folder")
        HiddenFolder.Name = "NebulaHiddenVisuals"
        HiddenFolder.Parent = CoreGui
    end

    for _, obj in ipairs(char:GetDescendants()) do
        storeAndHide(obj)
    end

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        pcall(function()
            hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
            hum.NameDisplayDistance = 0
            hum.HealthDisplayDistance = 0
        end)
    end

    local head = char:FindFirstChild("Head")
    if head then
        for _, c in ipairs(head:GetChildren()) do
            if c:IsA("BillboardGui") or c:IsA("Decal") then
                storeAndHide(c)
            end
        end
    end
end

function Invisibility.apply()
    local char = Player.Character
    if not char then return end

    forceHideCharacter(char)
    probeAndFireHideRemotes(true)

    if DescendantConnection then DescendantConnection:Disconnect() end
    DescendantConnection = char.DescendantAdded:Connect(function(obj)
        if CONFIG.INVISIBLE then
            task.defer(storeAndHide, obj)
        end
    end)

    if InvisHardConnection then InvisHardConnection:Disconnect() end
    local start = os.clock()
    local lastHideCheck = 0
    InvisHardConnection = RunService.Heartbeat:Connect(function()
        if not CONFIG.INVISIBLE then return end
        local c = Player.Character
        if not c then return end
        local now = os.clock()
        if now - lastHideCheck < 0.65 then return end
        lastHideCheck = now
        if now - start < 3 or (math.floor(now * 2.5) % 2 == 0) then
            for _, obj in ipairs(c:GetDescendants()) do
                if obj:IsA("BasePart") then
                    obj.Transparency = 1
                    obj.LocalTransparencyModifier = 1
                elseif obj:IsA("Decal") or obj:IsA("Texture") then
                    obj.Transparency = 1
                end
            end
        end
    end)
end

function Invisibility.remove()
    if DescendantConnection then
        DescendantConnection:Disconnect()
        DescendantConnection = nil
    end
    if InvisHardConnection then
        InvisHardConnection:Disconnect()
        InvisHardConnection = nil
    end

    probeAndFireHideRemotes(false)

    for obj, state in pairs(OriginalPartState) do
        if obj then
            pcall(function()
                if state.Transparency ~= nil and obj.Parent then obj.Transparency = state.Transparency end
                if state.LocalTransparencyModifier ~= nil and obj.Parent then obj.LocalTransparencyModifier = state.LocalTransparencyModifier end
                if state.CanCollide ~= nil and obj.Parent then obj.CanCollide = state.CanCollide end
                if state.Anchored ~= nil and obj.Parent then obj.Anchored = state.Anchored end
                if state.Enabled ~= nil and obj.Parent then obj.Enabled = state.Enabled end
                if state.Parent ~= nil then obj.Parent = state.Parent end
            end)
        end
        OriginalPartState[obj] = nil
    end

    local char = Player.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            pcall(function()
                hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
                hum.NameDisplayDistance = 100
                hum.HealthDisplayDistance = 100
            end)
        end
    end
end

-- ============================================================
-- SAFE ZONE
-- ============================================================
local function removeSafeZone(restorePosition)
    if restorePosition and SafeReturn then
        local hrp = getHRP(Player)
        if hrp then
            hrp.CFrame = SafeReturn
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end
    end
    if SafePlatform then
        SafePlatform:Destroy()
        SafePlatform = nil
    end
    SafeReturn = nil
    SafeMode = nil
    SafeTriggered = false
end

local function createSafeZone(mode)
    local hrp = getHRP(Player)
    if not hrp then return false end
    if SafePlatform then
        SafePlatform:Destroy()
        SafePlatform = nil
    end

    SafeReturn = SafeReturn or hrp.CFrame
    SafeMode = mode or "below"

    local y
    if SafeMode == "below" then
        y = math.min(-CONFIG.SAFE_DEPTH, workspace.FallenPartsDestroyHeight + 5)
    else
        y = CONFIG.SAFE_HEIGHT
    end

    local destination = Vector3.new(hrp.Position.X, y, hrp.Position.Z)

    local platform = Instance.new("Part")
    platform.Name = "NebulaLocalSafeZone"
    platform.Size = Vector3.new(28, 2, 28)
    platform.Anchored = true
    platform.CanCollide = true
    platform.CanTouch = false
    platform.CanQuery = false
    platform.CastShadow = false
    platform.Material = Enum.Material.SmoothPlastic
    platform.Color = Color3.fromRGB(0, 0, 0)
    platform.Transparency = SafeMode == "below" and 1 or 0.65
    platform.CFrame = CFrame.new(destination)
    platform.Parent = workspace
    SafePlatform = platform

    hrp.CFrame = CFrame.new(destination + Vector3.new(0, 5, 0))
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
    SafeTriggered = true
    return true
end

-- ============================================================
-- AUTO RESET
-- ============================================================
local function vanishCorpse(character)
    if not character or not character.Parent then return end

    for _, obj in ipairs(character:GetDescendants()) do
        if obj:IsA("BasePart") then
            obj.Transparency = 1
            obj.LocalTransparencyModifier = 1
            obj.CanCollide = false
            obj.Anchored = true
            pcall(function()
                obj.AssemblyLinearVelocity = Vector3.zero
                obj.AssemblyAngularVelocity = Vector3.zero
            end)
        elseif obj:IsA("Decal") or obj:IsA("Texture") then
            obj.Transparency = 1
        elseif obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Beam")
            or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
            obj.Enabled = false
        elseif obj:IsA("Accessory") or obj:IsA("Hat") then
            pcall(function() obj:Destroy() end)
        elseif obj:IsA("Shirt") or obj:IsA("Pants") or obj:IsA("ShirtGraphic") or obj:IsA("Clothing") then
            pcall(function() obj:Destroy() end)
        elseif obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
            obj.Enabled = false
        end
    end

    local hrp = character:FindFirstChild("HumanoidRootPart")
    if hrp then
        local deepY = workspace.FallenPartsDestroyHeight - 80
        hrp.CFrame = CFrame.new(hrp.Position.X, deepY, hrp.Position.Z)
        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end

    task.delay(0.03, function()
        if character and character.Parent then
            pcall(function() character:Destroy() end)
        end
    end)
end

local StopBackstab

-- ============================================================
-- SPEED: independent of the camera and START target facing.
-- Only the player's own control direction drives it. Uses horizontal velocity
-- (no continuous PivotTo) to avoid shaking camera while walking or attacking.
-- TSB server can override character controls/abilities/trash restrictions.
-- ============================================================
local function speedHumanoid()
    local c = Player.Character
    return c and c:FindFirstChildOfClass("Humanoid") or nil
end

local function refreshSpeed()
    if not Active or not CONFIG.SPEED_ENABLED then return end
    local hum = speedHumanoid()
    if not hum or hum.Health <= 0 then return end
    if hum ~= SpeedHumanoid then
        SpeedHumanoid = hum
        OriginalWalkSpeed = hum.WalkSpeed
        CurrentSpeedWritten = nil
    end
    if hum.WalkSpeed ~= CONFIG.SPEED_VALUE then
        pcall(function()
            hum.WalkSpeed = CONFIG.SPEED_VALUE
            CurrentSpeedWritten = CONFIG.SPEED_VALUE
        end)
    end
end

local function releaseSpeed()
    local hum = SpeedHumanoid
    if hum and hum.Parent and CurrentSpeedWritten ~= nil
        and hum.WalkSpeed == CurrentSpeedWritten and OriginalWalkSpeed then
        pcall(function() hum.WalkSpeed = OriginalWalkSpeed end)
    end
    CurrentSpeedWritten = nil
    SpeedHumanoid = nil
    OriginalWalkSpeed = nil
end

local blockedStates = {
    [Enum.HumanoidStateType.Dead] = true,
    [Enum.HumanoidStateType.Seated] = true,
    [Enum.HumanoidStateType.PlatformStanding] = true,
    [Enum.HumanoidStateType.Ragdoll] = true,
    [Enum.HumanoidStateType.FallingDown] = true,
    [Enum.HumanoidStateType.Physics] = true,
}

local function intendedMove(hum)
    -- A focused TextBox should never count typed WASD as movement.
    if UserInputService:GetFocusedTextBox() then return Vector3.zero end
    local x, z = 0, 0
    if UserInputService:IsKeyDown(Enum.KeyCode.W)
        or UserInputService:IsKeyDown(Enum.KeyCode.Up) then z = z + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.S)
        or UserInputService:IsKeyDown(Enum.KeyCode.Down) then z = z - 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.D)
        or UserInputService:IsKeyDown(Enum.KeyCode.Right) then x = x + 1 end
    if UserInputService:IsKeyDown(Enum.KeyCode.A)
        or UserInputService:IsKeyDown(Enum.KeyCode.Left) then x = x - 1 end
    if x ~= 0 or z ~= 0 then
        local c = workspace.CurrentCamera
        if c then
            local look, right = c.CFrame.LookVector, c.CFrame.RightVector
            local forward = Vector3.new(look.X, 0, look.Z)
            local side = Vector3.new(right.X, 0, right.Z)
            if forward.Magnitude > 0.01 and side.Magnitude > 0.01 then
                return (forward.Unit * z + side.Unit * x).Unit
            end
        end
    end
    local raw = hum.MoveDirection  -- supports mobile joystick as far as Roblox exposes it
    return Vector3.new(raw.X, 0, raw.Z)
end

local function moveBlocked(hum)
    return not hum or hum.Health <= 0 or hum.Sit or blockedStates[hum:GetState()]
end

local function speedMovementAssist(dt)
    if not Active or not CONFIG.SPEED_ENABLED or Evading
        or SafeTriggered or ResetInProgress then return end
    local hum = speedHumanoid()
    local root = getHRP(Player)
    if not root or root.Anchored or moveBlocked(hum) then return end
    local raw = intendedMove(hum)
    local planarInput = Vector3.new(raw.X, 0, raw.Z)
    local strength = math.clamp(planarInput.Magnitude, 0, 1)
    if strength < 0.06 then return end
    local dir = planarInput.Unit
    local vel = root.AssemblyLinearVelocity
    local planar = Vector3.new(vel.X, 0, vel.Z)
    local targetSpeed = CONFIG.SPEED_VALUE * strength
    LastRealSpeed = planar:Dot(dir)

    -- Never brake natural dash/launch momentum. That would cause the very
    -- slowdown after dashing that the user reported.
    if planar.Magnitude > math.max(targetSpeed * 1.35, 45) then return end
    -- Maintain the y velocity for jumps and attacks. Only blend X/Z.
    local blend = math.clamp(dt * 34, 0.20, CONFIG.SPEED_ACCELERATION)
    local nextVel = planar:Lerp(dir * targetSpeed, blend)
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(nextVel.X, vel.Y, nextVel.Z)
    end)
end

-- Client movement override after the default input pass. Never forces an
-- ability to execute; merely requests movement when keyboard input exists.
RunService:BindToRenderStep(MoveRenderName, Enum.RenderPriority.Input.Value + 2, function()
    if not Active or not CONFIG.SPEED_ENABLED or Evading
       or SafeTriggered or ResetInProgress then return end
    local hum = speedHumanoid()
    if moveBlocked(hum) then return end
    local raw = intendedMove(hum)
    if raw.Magnitude > 0.06 then
        pcall(function() hum:Move(raw, false) end)
    end
end)

-- ============================================================
-- AUTO EVADE removed in v16. No animation, effect, or damage listeners trigger TP.
-- Manual SAFE ZONA (default OFF) remains a separate user-controlled feature.

local function monitorHealth(character)
    if HealthConnection then HealthConnection:Disconnect(); HealthConnection = nil end
    if DeathConnection then DeathConnection:Disconnect(); DeathConnection = nil end
    ResetInProgress = false
    SafeTriggered = false

    local hum = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
    if not hum then return end
    CurrentTrackedHumanoid = hum

    local function checkHealth(health)
        if CONFIG.SAFE_ZONE and not SafeTriggered and not ResetInProgress
            and not Evading and health > 0 and health <= CONFIG.RESET_THRESHOLD then
            createSafeZone("below")
            StatusLabel.Text = "SAFE ZONA: under map (" .. math.floor(health) .. " HP)"
            StatusLabel.TextColor3 = Color3.fromRGB(80, 220, 255)
        end
    end

    local lastHealth = hum.Health
    HealthConnection = hum.HealthChanged:Connect(function(newHealth)
        checkHealth(newHealth)
        lastHealth = newHealth
    end)

    DeathConnection = hum.Died:Connect(function()
        if BackstabActive and StopBackstab then StopBackstab(true) end
        if CONFIG.AUTO_RESET then
            StatusLabel.Text = "AUTO RESET: corpse vanished"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 140, 40)
            vanishCorpse(character)
        end
    end)
end

-- ============================================================
-- POSITIONER
-- ============================================================
local Positioner = {}

-- Read the currently replicated body location. During ragdoll the HRP can
-- be far from the torso or rotate onto its side: avoid teleporting into void.
local function validPoint(p)
    return p and p.X == p.X and p.Y == p.Y and p.Z == p.Z
        and math.abs(p.X) < 100000 and math.abs(p.Y) < 100000
        and math.abs(p.Z) < 100000
        and p.Y > workspace.FallenPartsDestroyHeight + 12
end
local function reliableTargetPose(targetRoot)
    if not targetRoot or not targetRoot.Parent then return nil end
    local char = targetRoot.Parent
    local hum = char:FindFirstChildOfClass("Humanoid")
    local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
        or char:FindFirstChild("LowerTorso")
    local rootPos = targetRoot.Position
    local torsoPos = torso and torso.Position
    local ragdolled = false
    if hum then
        local state = hum:GetState()
        ragdolled = state == Enum.HumanoidStateType.Ragdoll
            or state == Enum.HumanoidStateType.FallingDown
            or state == Enum.HumanoidStateType.Physics
            or state == Enum.HumanoidStateType.PlatformStanding
    end
    local useTorso = torsoPos and validPoint(torsoPos)
        and (not validPoint(rootPos) or (torsoPos-rootPos).Magnitude > 7 or ragdolled)
    local pos = useTorso and torsoPos or rootPos
    if not validPoint(pos) then return nil end
    local look = targetRoot.CFrame.LookVector
    local flat = Vector3.new(look.X, 0, look.Z)
    if ragdolled or flat.Magnitude < 0.4 then
        local own = getHRP(Player)
        local away = own and (pos - own.Position) or Vector3.new(0, 0, -1)
        flat = Vector3.new(away.X, 0, away.Z)
    end
    if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end
    return pos, flat.Unit, ragdolled
end

function Positioner.getBehindCFrame(targetHRP, distance)
    local pos, flatLook, ragdolled = reliableTargetPose(targetHRP)
    if not pos then return nil end
    local studs = math.clamp(distance or CONFIG.BEHIND_STUDS, 2.1, 8)
    -- Short, bounded prediction: optional and disabled for unstable ragdoll physics.
    if CONFIG.PING_COMPENSATE and not ragdolled then
        local velocity = targetHRP.AssemblyLinearVelocity
        local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
        local ping = math.clamp(getPing(), 0, 300)
        local leadTime = math.clamp(ping / 1000 * 0.65 + 0.018, 0, CONFIG.MAX_LEAD_TIME)
        local lead = flatVel * leadTime
        if lead.Magnitude > 3 then lead = lead.Unit * 3 end
        pos = pos + lead
    end
    local destination = pos - flatLook * studs
    local y = pos.Y + CONFIG.HEIGHT_OFFSET
    if ragdolled then
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = {targetHRP.Parent, Player.Character}
        local hit = workspace:Raycast(destination + Vector3.new(0, 7, 0),
            Vector3.new(0, -24, 0), params)
        if hit then
            -- Keep feet near the floor when the target is knocked down.
            local root = getHRP(Player)
            local hum = speedHumanoid()
            local standingHeight = (hum and hum.HipHeight or 2) + (root and root.Size.Y * 0.5 or 1) + 0.1
            y = hit.Position.Y + standingHeight
        end
    end
    destination = Vector3.new(destination.X, y, destination.Z)
    if not validPoint(destination) then return nil end
    local face = Vector3.new(pos.X, y, pos.Z)
    if (face - destination).Magnitude < 0.15 then return nil end
    return CFrame.lookAt(destination, face)
end

-- Turn only the avatar. Never control camera CFrame (SHIFT or normal camera).
function Positioner.faceTarget(targetRoot)
    local root, hum = getHRP(Player), speedHumanoid()
    if not root or not targetRoot or moveBlocked(hum) or root.Anchored then return end
    local aimPos = reliableTargetPose(targetRoot)
    if not aimPos then return end
    local at = Vector3.new(aimPos.X, root.Position.Y, aimPos.Z)
    local delta = at - root.Position
    if delta.Magnitude < 0.35 then return end
    local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
    if facing.Magnitude > 0.01 and facing.Unit:Dot(delta.Unit) > 0.995 then return end
    pcall(function() root.CFrame = CFrame.lookAt(root.Position, at) end)
end

function Positioner.teleport(force)
    if not Active then return false, "скрипт остановлен" end
    if not SelectedTarget or SelectedTarget.Parent ~= Players then
        return false, "цель не выбрана или вышла"
    end
    if SafeTriggered or ResetInProgress then
        return false, "активен сброс / безопасная зона"
    end
    if TrashBusy then return false, "операция с мусоркой" end
    local char = Player.Character
    local root = getHRP(Player)
    local targetRoot = getHRP(SelectedTarget)
    local hum = speedHumanoid()
    if not char or not root or not hum or hum.Health <= 0 then
        return false, "ожидание персонажа"
    end
    if not targetRoot or not isAlive(SelectedTarget) then
        return false, "ожидание появления цели"
    end
    if root.Anchored then return false, "персонаж закреплён игрой" end
    -- Do not block on Physics/FallingDown: these states are common in TSB.
    -- Server authority still controls whether CFrame movement is accepted.
    local targetCF = Positioner.getBehindCFrame(targetRoot)
    if not targetCF then return false, "позиция цели недоступна" end
    local gap = (root.Position - targetCF.Position).Magnitude
    if not force and gap <= CONFIG.POSITION_TOLERANCE then
        return true, "рядом с целью"
    end
    local ok, err = pcall(function()
        -- PivotTo moves the whole character, instead of leaving body parts behind.
        char:PivotTo(targetCF)
        if force then
            root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end)
    if not ok then
        -- Fallback for experiences that temporarily reject model pivots.
        local fallbackOK = pcall(function() root.CFrame = targetCF end)
        if not fallbackOK then
            return false, "ошибка перемещения: " .. tostring(err):sub(1, 70)
        end
    end
    return true, "попытка TP выполнена"
end

local function teleportToOpponent(opponent, distance, force)
    if not Active or TrashBusy or Evading or SafeTriggered or ResetInProgress then return false end
    local char, root, targetRoot = Player.Character, getHRP(Player), getHRP(opponent)
    local hum = speedHumanoid()
    if not char or not root or not targetRoot or not isAlive(opponent)
        or moveBlocked(hum) then return false end
    local dst = Positioner.getBehindCFrame(targetRoot, distance)
    if not dst then return false end
    if not force and (root.Position - dst.Position).Magnitude <= CONFIG.POSITION_TOLERANCE then
        if not (CONFIG.AIM_ENABLED and AimTarget) then Positioner.faceTarget(targetRoot) end
        return true
    end
    return pcall(function()
        char:PivotTo(dst)
        -- Only initial TP resets momentum. Repeated follow must not fight
        -- jumps, the movement controller, or trash carrying.
        if force then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
    end)
end

local function chooseRandomOpponent()
    local choices = {}
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= Player and isAlive(other) and getHRP(other) then
            table.insert(choices, other)
        end
    end
    if #choices == 0 then return nil end
    return choices[math.random(1, #choices)]
end

-- ============================================================
-- STATUS
-- ============================================================
function UpdateStatus()
    if BackstabActive then
        if SelectedTarget then
            StatusLabel.Text = "ПРЕСЛЕДОВАНИЕ: активно"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        else
            StatusLabel.Text = "No target selected"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    else
        if SelectedTarget then
            StatusLabel.Text = "Цель выбрана • нажми START"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            StatusLabel.Text = "Выбери игрока → START"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end
end

-- ============================================================
-- PLAYER LIST: selection is independent from START.
-- Avatar thumbnails are cached; refreshing the list does not issue repeated downloads.
-- ============================================================
local AvatarCache = {}
local function RefreshPlayerList()
    for _, child in ipairs(PlayerScrollFrame:GetChildren()) do
        if child:IsA("GuiObject") then child:Destroy() end
    end
    PlayerButtons = {}
    local all = Players:GetPlayers()
    table.sort(all, function(a, b)
        return a.DisplayName:lower() < b.DisplayName:lower()
    end)
    local y = 4
    for _, opponent in ipairs(all) do
        if opponent ~= Player then
            local entry = Instance.new("TextButton")
            entry.Name = "User_" .. tostring(opponent.UserId)
            entry.Text = ""
            entry.Size = UDim2.new(1, -9, 0, 49)
            entry.Position = UDim2.fromOffset(3, y)
            entry.BorderSizePixel = 0
            entry.AutoButtonColor = true
            entry.BackgroundColor3 = SelectedTarget == opponent
                and Color3.fromRGB(20, 86, 82) or Color3.fromRGB(37, 44, 60)
            entry.Parent = PlayerScrollFrame
            Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 7)

            local mark = Instance.new("TextLabel")
            mark.Name = "SelectedMark"
            mark.Size = UDim2.fromOffset(23, 23)
            mark.Position = UDim2.new(0, 6, 0.5, -11)
            mark.BackgroundColor3 = Color3.fromRGB(21, 29, 43)
            mark.Text = SelectedTarget == opponent and "✓" or ""
            mark.TextColor3 = Color3.fromRGB(71, 246, 170)
            mark.TextSize = 18
            mark.Font = Enum.Font.SourceSansBold
            mark.ZIndex = 2
            mark.Parent = entry
            Instance.new("UICorner", mark).CornerRadius = UDim.new(0, 5)

            -- Display name on the left; unique username on the right.
            -- Do not embed, cache or show any personal/account identifiers elsewhere.
            local display = Instance.new("TextLabel")
            display.Name = "DisplayName"
            display.Size = UDim2.new(0.42, -25, 0, 37)
            display.Position = UDim2.new(0, 34, 0.5, -19)
            display.BackgroundTransparency = 1
            display.Text = opponent.DisplayName
            display.Font = Enum.Font.SourceSansBold
            display.TextSize = 12
            display.TextXAlignment = Enum.TextXAlignment.Left
            display.TextColor3 = Color3.fromRGB(236, 245, 252)
            display.TextTruncate = Enum.TextTruncate.AtEnd
            display.ZIndex = 2
            display.Parent = entry

            local username = Instance.new("TextLabel")
            username.Name = "Username"
            username.Size = UDim2.new(0.58, -48, 0, 37)
            username.Position = UDim2.new(0.42, 9, 0.5, -19)
            username.BackgroundTransparency = 1
            username.Text = "@" .. opponent.Name
            username.Font = Enum.Font.SourceSans
            username.TextSize = 11
            username.TextXAlignment = Enum.TextXAlignment.Right
            username.TextColor3 = Color3.fromRGB(145, 191, 218)
            username.TextTruncate = Enum.TextTruncate.AtEnd
            username.ZIndex = 2
            username.Parent = entry

            local avatar = Instance.new("ImageLabel")
            avatar.Name = "Avatar"
            avatar.Size = UDim2.fromOffset(37, 37)
            avatar.Position = UDim2.new(1, -41, 0.5, -18)
            avatar.BackgroundColor3 = Color3.fromRGB(27, 63, 83)
            avatar.BorderSizePixel = 0
            avatar.ScaleType = Enum.ScaleType.Crop
            avatar.ZIndex = 2
            avatar.Parent = entry
            avatar.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(opponent.UserId)
                .. "&w=48&h=48"
            Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)
            local cached = AvatarCache[opponent.UserId]
            if cached then
                avatar.Image = cached
            else
                task.spawn(function()
                    local ok, imageUrl = pcall(function()
                        return Players:GetUserThumbnailAsync(
                            opponent.UserId, Enum.ThumbnailType.HeadShot,
                            Enum.ThumbnailSize.Size48x48)
                    end)
                    if ok and imageUrl then
                        AvatarCache[opponent.UserId] = imageUrl
                        if avatar.Parent then avatar.Image = imageUrl end
                    end
                end)
            end

            entry.Activated:Connect(function()
                if not Active then return end
                if BackstabActive and StopBackstab then StopBackstab() end
                if StopRandomCycle then StopRandomCycle(false) end
                SelectedTarget = opponent
                for _, data in pairs(PlayerButtons) do
                    data.entry.BackgroundColor3 = Color3.fromRGB(37, 44, 60)
                    data.mark.Text = ""
                end
                entry.BackgroundColor3 = Color3.fromRGB(20, 86, 82)
                mark.Text = "✓"
                StatusLabel.Text = "Цель выбрана. Нажми START для постоянного TP"
                StatusLabel.TextColor3 = Color3.fromRGB(142, 242, 191)
            end)
            PlayerButtons[opponent.UserId] = {entry = entry, mark = mark}
            y = y + 54
        end
    end
    PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, y + 4)
end

-- ============================================================
-- NOTIFICATION
-- ============================================================
local function Message(Title, Text, Time)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = Title,
            Text = Text,
            Duration = Time or 5
        })
    end)
end

-- ============================================================
-- TRASH v14: indexed candidates, verify pickup, cancelable continuous mode
-- ============================================================
local function trashStatus(s)
    if not Active or not TrashInfo.Parent then return end
    TrashInfo.Text = "TRASH: " .. tostring(s)
end

local function isTrashName(s)
    local low = string.lower(tostring(s or ""))
    return low:find("trash", 1, true) ~= nil
        or low:find("garbage", 1, true) ~= nil
        or low:find("dustbin", 1, true) ~= nil
end

local function trashRoot(item)
    if not item or not item.Parent then return nil end
    if item:IsA("BasePart") then return item end
    if item:IsA("Model") then
        return item.PrimaryPart or item:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

local function hasForeignHumanoid(inst)
    local cursor = inst
    while cursor and cursor ~= workspace do
        if cursor:IsA("Model") and cursor:FindFirstChildOfClass("Humanoid") then
            return true
        end
        cursor = cursor.Parent
    end
    return false
end

local function indexTrash(item)
    if (item:IsA("Model") or item:IsA("BasePart"))
       and isTrashName(item.Name) and not hasForeignHumanoid(item) then
        local root = trashRoot(item)
        if root then TrashIndex[item] = true end
    end
end

task.spawn(function()
    local all = workspace:GetDescendants()
    for i, item in ipairs(all) do
        if not Active then return end
        indexTrash(item)
        if i % 220 == 0 then task.wait() end
    end
    TrashIndexReady = true
end)
TrashIndexConnection = workspace.DescendantAdded:Connect(function(item)
    if not Active then return end
    if isTrashName(item.Name) then task.defer(indexTrash, item) end
end)

local function findTrash()
    local me = getHRP(Player)
    if not me then return nil end
    local now = os.clock()
    local best, bestDistance = nil, math.huge
    for item in pairs(TrashIndex) do
        local root = trashRoot(item)
        if not root or not root:IsDescendantOf(workspace) or hasForeignHumanoid(item) then
            TrashIndex[item] = nil
        elseif (TrashBlacklist[item] or 0) <= now then
            -- Anchored map props may become pickup props; do not exclude solely by anchored state.
            local distance = (root.Position - me.Position).Magnitude
            if distance < bestDistance and distance < 1600 then
                best, bestDistance = item, distance
            end
        end
    end
    -- The map can swap a can's Instance after pickup; rescan at most once
    -- every configured interval, and in small batches to avoid FPS spikes.
    if not best and now - LastTrashScanAt > CONFIG.TRASH_SCAN_INTERVAL then
        LastTrashScanAt = now
        task.spawn(function()
            for i, descendant in ipairs(workspace:GetDescendants()) do
                if not Active then return end
                if i % 260 == 0 then task.wait() end
                indexTrash(descendant)
            end
        end)
    end
    return best
end

local function sendM1()
    local character = Player.Character
    if character then
        local tool = character:FindFirstChildOfClass("Tool")
        if tool and pcall(function() tool:Activate() end) then return true end
    end
    local camera = workspace.CurrentCamera
    local view = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local x, y = math.floor(view.X * 0.90), math.floor(view.Y * 0.43)
    local pg = Player:FindFirstChildOfClass("PlayerGui")
    if pg then
        local nearest, score = nil, math.huge
        for _, gui in ipairs(pg:GetDescendants()) do
            if gui:IsA("GuiButton") and gui.Visible and gui.AbsoluteSize.X > 24 then
                local center = gui.AbsolutePosition + gui.AbsoluteSize / 2
                if center.X > view.X * 0.71 and center.Y > view.Y * 0.27
                    and center.Y < view.Y * 0.62 then
                    local distance = (center - Vector2.new(x, y)).Magnitude
                    if distance < score then nearest, score = center, distance end
                end
            end
        end
        if nearest and score < view.Y * 0.17 then
            x, y = math.floor(nearest.X), math.floor(nearest.Y)
        end
    end
    local ok = pcall(function()
        VirtualInputManager:SendTouchEvent(7, 0, x, y)
        task.wait(0.07)
        VirtualInputManager:SendTouchEvent(7, 2, x, y)
    end)
    if ok then return true end
    ok = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
        task.wait(0.07)
        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
    end)
    if ok then return true end
    local fn = rawget(_G, "mouse1click")
    if type(fn) == "function" then return pcall(fn) end
    return false
end

local function trashCarried(item)
    local char = Player.Character
    if not char then return false end
    -- Some games replace the map prop with another equipped instance.
    for _, obj in ipairs(char:GetDescendants()) do
        if (obj:IsA("Tool") or obj:IsA("Model")) and isTrashName(obj.Name) then
            return true
        end
    end
    if not item then return false end
    if item.Parent and item:IsDescendantOf(char) then return true end
    local part = trashRoot(item)
    if not part then return false end
    for _, joint in ipairs(item:GetDescendants()) do
        if joint:IsA("WeldConstraint") or joint:IsA("Weld") or joint:IsA("Motor6D") then
            local attached, value = pcall(function()
                return (joint.Part0 and joint.Part0:IsDescendantOf(char))
                    or (joint.Part1 and joint.Part1:IsDescendantOf(char))
            end)
            if attached and value then return true end
        end
    end
    return false
end

local function moveNearTrash(item)
    local part = trashRoot(item)
    local char = Player.Character
    local root = getHRP(Player)
    if not part or not char or not root then return false end
    local diff = root.Position - part.Position
    local flat = Vector3.new(diff.X, 0, diff.Z)
    if flat.Magnitude < 0.2 then flat = Vector3.new(0, 0, 1) end
    local target = part.Position + flat.Unit * 3.1
    target = Vector3.new(target.X, root.Position.Y, target.Z)
    return pcall(function()
        char:PivotTo(CFrame.lookAt(target, Vector3.new(part.Position.X, target.Y, part.Position.Z)))
    end)
end

local function readyTrash(token)
    return Active and token == TrashToken and isAlive(Player)
       and not Evading and not SafeTriggered and not ResetInProgress
end

local function collectTrashOnce(token, returnOrigin, withThrow)
    local originChar = Player.Character
    local origin = originChar and originChar:GetPivot()
    local function restore()
        if returnOrigin and origin and readyTrash(token) then
            local char = Player.Character
            if char then pcall(function() char:PivotTo(origin) end) end
        end
    end
    local attempts = 0
    while readyTrash(token) and attempts < 6 do
        local item = findTrash()
        if not item then
            trashStatus(TrashIndexReady and "no available can; rescan/wait" or "indexing the map")
            restore()
            return false, "not found"
        end
        attempts = attempts + 1
        TrashPhase = "approach"
        trashStatus("going to can " .. attempts)
        if moveNearTrash(item) then
            -- Orient towards the available can without changing the camera.
            local canPart = trashRoot(item)
            local myRoot = getHRP(Player)
            if canPart and myRoot then
                local look = Vector3.new(canPart.Position.X, myRoot.Position.Y, canPart.Position.Z)
                if (look - myRoot.Position).Magnitude > 0.1 then
                    pcall(function() myRoot.CFrame = CFrame.lookAt(myRoot.Position, look) end)
                end
            end
            task.wait(0.23)
            if not readyTrash(token) then return false, "cancelled" end
            TrashPhase = "pickup"
            if trashRoot(item) and trashRoot(item):IsDescendantOf(workspace)
                and sendM1() then
                local deadline = os.clock() + CONFIG.TRASH_PICKUP_WAIT
                while os.clock() < deadline and readyTrash(token) do
                    if trashCarried(item) then break end
                    task.wait(0.1)
                end
                if trashCarried(item) then
                    TrashBlacklist[item] = os.clock() + 24
                    if returnOrigin then
                        TrashPhase = "teleport"
                        restore()
                        task.wait(CONFIG.TRASH_RETURN_PAUSE)
                        return true, "picked + returned"
                    end
                    local enemy = chooseRandomOpponent()
                    if not enemy then restore(); return false, "no target" end
                    local part = getHRP(enemy)
                    local char = Player.Character
                    local myRoot = getHRP(Player)
                    if part and char and myRoot and readyTrash(token) then
                        local pos = part.Position - part.CFrame.LookVector * CONFIG.TRASH_TARGET_DISTANCE
                        pos = Vector3.new(pos.X, myRoot.Position.Y, pos.Z)
                        TrashPhase = "teleport"
                        trashStatus("can confirmed; moving to " .. enemy.Name)
                        pcall(function()
                            char:PivotTo(CFrame.lookAt(pos,
                                Vector3.new(part.Position.X, pos.Y, part.Position.Z)))
                        end)
                        task.wait(0.18)
                        if readyTrash(token) and trashCarried(item) then
                            TrashPhase = "throw"
                            trashStatus("throw input sent")
                            if sendM1() then
                                -- Wait for the held prop to detach before considering
                                -- the cycle successful. A successful Lua call != throw.
                                local deadline = os.clock() + math.max(0.7, CONFIG.TRASH_THROW_WAIT)
                                local released = false
                                while readyTrash(token) and os.clock() < deadline do
                                    if not trashCarried(item) then
                                        released = true
                                        break
                                    end
                                    task.wait(0.08)
                                end
                                if released then
                                    TrashBlacklist[item] = os.clock() + 22
                                    return true, "released: " .. enemy.Name .. " (hit unverified)"
                                end
                                TrashBlacklist[item] = os.clock() + 15
                                return false, "throw not confirmed; retrying with next can"
                            end
                        end
                    end
                    restore()
                    return false, "throw not verified"
                end
            end
        end
        TrashBlacklist[item] = os.clock() + 16
        task.wait(0.15)
    end
    restore()
    return false, "pickup not confirmed; skipped target"
end

local function stopTrash()
    TrashAutoEnabled = false
    TrashToken = TrashToken + 1
    TrashBusy = false
    TrashPhase = "idle"
    TrashAutoButton.Text = "TRASH AUTO: OFF"
    TrashAutoButton.BackgroundColor3 = Color3.fromRGB(95, 66, 140)
end

local function trashCycle()
    if TrashAutoEnabled then
        stopTrash()
        trashStatus("AUTO stopped")
        return
    end
    if not Active or TrashBusy then return end
    TrashAutoEnabled = true
    TrashToken = TrashToken + 1
    local token = TrashToken
    TrashAutoButton.Text = "TRASH AUTO: ON (TAP TO STOP)"
    TrashAutoButton.BackgroundColor3 = Color3.fromRGB(30, 112, 74)
    task.spawn(function()
        while TrashAutoEnabled and Active and token == TrashToken do
            if not isAlive(Player) then
                trashStatus("waiting for respawn")
                task.wait(1)
            else
            TrashBusy = true
            local ok, worked, msg = pcall(collectTrashOnce, token, false, true)
            if not ok then
                trashStatus("error; resuming scan")
            else
                trashStatus(msg)
            end
            TrashBusy = false
            TrashPhase = "idle"
            local limit = os.clock() + (worked and 2.5 or CONFIG.TRASH_RETRY_WAIT)
            while TrashAutoEnabled and Active and token == TrashToken and os.clock() < limit do
                task.wait(0.2)
            end
            end
        end
        if token == TrashToken then stopTrash() end
    end)
end

local function trashReturnOnce()
    if not Active or TrashAutoEnabled or TrashBusy then
        trashStatus("stop TRASH AUTO first")
        return
    end
    TrashToken = TrashToken + 1
    local token = TrashToken
    TrashBusy = true
    TrashReturnButton.Text = "PICKING..."
    task.spawn(function()
        local ok, worked, msg = pcall(collectTrashOnce, token, true, false)
        if token == TrashToken then
            TrashBusy = false
            TrashPhase = "idle"
            TrashReturnButton.Text = "ВЗЯТЬ МУСОР И ВЕРНУТЬСЯ"
            trashStatus(ok and msg or "pickup error")
        end
    end)
end

-- ============================================================
-- AIM: manual screen-center acquisition; camera + avatar track only that player.
-- The circle can be dragged without changing the target or toggling AIM.
-- ============================================================
local function clearAimTarget()
    AimTarget = nil
    AimHud.BackgroundColor3 = Color3.fromRGB(91, 96, 107)
    AimHudStroke.Color = Color3.fromRGB(176, 183, 197)
    AimHud.Text = "◎"
end

local function acquireAimTarget()
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local center = camera.ViewportSize * 0.5
    local radius = math.min(center.X, center.Y) * 0.48
    local nearest, nearestDist = nil, radius
    for _, enemy in ipairs(Players:GetPlayers()) do
        if enemy ~= Player and isAlive(enemy) then
            local root = getHRP(enemy)
            if root then
                local point, visible = camera:WorldToViewportPoint(root.Position)
                if visible and point.Z > 0 then
                    local dist = (Vector2.new(point.X, point.Y) - center).Magnitude
                    if dist < nearestDist then
                        nearest, nearestDist = enemy, dist
                    end
                end
            end
        end
    end
    if not nearest then return false end
    -- One-time acquisition. Never change until AIM OFF or manual unlock.
    AimTarget = nearest
    AimHud.BackgroundColor3 = Color3.fromRGB(20, 127, 110)
    AimHudStroke.Color = Color3.fromRGB(118, 244, 195)
    AimHud.Text = "●"
    return true
end

local LockedHumanoid = nil
local function refreshRotationLock()
    local hum = speedHumanoid()
    if LockedHumanoid and LockedHumanoid ~= hum then
        if PreviousAutoRotate ~= nil and LockedHumanoid.Parent then
            pcall(function() LockedHumanoid.AutoRotate = PreviousAutoRotate end)
        end
        LockedHumanoid, PreviousAutoRotate = nil, nil
    end
    if not hum then return end
    local shouldLock = BackstabActive or
        (RandomCycle.enabled and RandomCycle.phase == "chase") or
        (CONFIG.AIM_ENABLED and AimTarget ~= nil)
    if shouldLock then
        if LockedHumanoid ~= hum then
            LockedHumanoid, PreviousAutoRotate = hum, hum.AutoRotate
        end
        if hum.AutoRotate then hum.AutoRotate = false end
    elseif LockedHumanoid == hum then
        if PreviousAutoRotate ~= nil then
            pcall(function() hum.AutoRotate = PreviousAutoRotate end)
        end
        LockedHumanoid, PreviousAutoRotate = nil, nil
    end
end

local function updateAim()
    if not Active then return end
    refreshRotationLock()
    -- A fixed manual lock always takes priority; follow cannot steal it.
    if CONFIG.AIM_ENABLED and AimTarget then
        local root = getHRP(AimTarget)
        if root and isAlive(AimTarget) then
            -- The camera is aligned after Roblox' camera controller, so Shift
            -- Lock cannot silently steal the lock. Position stays unchanged.
            local camera = workspace.CurrentCamera
            if camera and camera.CameraType ~= Enum.CameraType.Scriptable then
                local point = reliableTargetPose(root)
                if point then
                    local origin = camera.CFrame.Position
                    local delta = point - origin
                    if delta.Magnitude > 0.05 then
                        pcall(function()
                            camera.CFrame = CFrame.lookAt(origin, point)
                        end)
                    end
                end
            end
            Positioner.faceTarget(root)
            return
        end
        -- Preserve same player through temporary ragdoll / respawn.
        -- We never silently select another opponent.
        return
    end
    -- Without a manual lock, TP modes can orient the avatar as before.
    local target = nil
    if BackstabActive and SelectedTarget and isAlive(SelectedTarget) then
        target = SelectedTarget
    elseif RandomCycle.enabled and RandomCycle.phase == "chase" and
        RandomCycle.target and isAlive(RandomCycle.target) then
        target = RandomCycle.target
    end
    if target then
        local root = getHRP(target)
        if root then Positioner.faceTarget(root) end
    end
end

local function setAimEnabled(enabled)
    CONFIG.AIM_ENABLED = enabled
    AimHud.Visible = enabled
    paintToggle(AimToggle, "AIM LOCK", enabled)
    clearAimTarget()
    if enabled then
        StatusLabel.Text = "AIM включён: целься по игроку и нажми кружок"
    else
        StatusLabel.Text = "AIM выключен"
    end
end
AimToggle.Activated:Connect(function()
    setAimEnabled(not CONFIG.AIM_ENABLED)
end)
AimHud.Activated:Connect(function()
    if not CONFIG.AIM_ENABLED or os.clock() < aimSuppressClickUntil then return end
    if AimTarget then
        clearAimTarget()
        StatusLabel.Text = "AIM сброшен: нацелься и нажми кружок"
    elseif acquireAimTarget() then
        StatusLabel.Text = "AIM: цель зафиксирована до выключения"
    else
        StatusLabel.Text = "AIM: наведи центр экрана на игрока"
    end
end)
RunService:BindToRenderStep(AimRenderName, Enum.RenderPriority.Camera.Value + 10, updateAim)

-- ============================================================
-- START / STOP
-- ============================================================
StartBackstab = function()
    if not Active then return end
    if not SelectedTarget or SelectedTarget.Parent ~= Players then
        StatusLabel.Text = "Сначала выбери игрока в списке"
        return
    end
    -- Stop conflicting movement controllers first, not AFTER a failed TP.
    if StopRandomCycle then StopRandomCycle(false) end
    if TrashBusy or TrashAutoEnabled then stopTrash() end
    if CONFIG.SAFE_ZONE and SafeTriggered then
        removeSafeZone(false)
        CONFIG.SAFE_ZONE = false
        paintToggle(SafeToggle, "SAVE ZONA", false)
    end
    if PositionConnection then
        PositionConnection:Disconnect()
        PositionConnection = nil
    end
    BackstabActive = true
    FollowWanted = true
    local lastFeedback = -math.huge
    local lastReason = nil
    local function tick()
        if not Active or not BackstabActive then return end
        if not SelectedTarget or SelectedTarget.Parent ~= Players then
            StopBackstab()
            StatusLabel.Text = "Игрок вышел • выбери новую цель"
            return
        end
        local ok, reason = Positioner.teleport(false)
        if ok then
            if lastReason ~= "tracking" then
                StatusLabel.Text = "ПРЕСЛЕДОВАНИЕ: активно"
                StatusLabel.TextColor3 = Color3.fromRGB(109, 244, 169)
                lastReason = "tracking"
            end
        elseif reason ~= lastReason or os.clock() - lastFeedback > 1.5 then
            StatusLabel.Text = "TP: " .. tostring(reason)
            StatusLabel.TextColor3 = Color3.fromRGB(255, 182, 105)
            lastReason = reason
            lastFeedback = os.clock()
        end
    end
    -- START always activates a Heartbeat retry loop, even when first TP fails.
    PositionConnection = RunService.Heartbeat:Connect(tick)
    local ok, reason = Positioner.teleport(true)
    if not ok then
        StatusLabel.Text = "TP ожидает: " .. tostring(reason)
        StatusLabel.TextColor3 = Color3.fromRGB(255, 182, 105)
    else
        StatusLabel.Text = "ПРЕСЛЕДОВАНИЕ: активно"
        StatusLabel.TextColor3 = Color3.fromRGB(109, 244, 169)
    end
    if CONFIG.INVISIBLE then Invisibility.apply() end
end

StopBackstab = function(preserveFollow)
    if not preserveFollow then FollowWanted = false end
    BackstabActive = false
    if PositionConnection then
        PositionConnection:Disconnect()
        PositionConnection = nil
    end
    if not CONFIG.INVISIBLE then Invisibility.remove() end
    UpdateStatus()
end

-- ============================================================
-- MANUAL-SKILL RANDOM MODE
-- The script NEVER sends skill inputs. Button marks and local user inputs
-- estimate cooldown; the actual cooldown/damage is server authoritative.
-- ============================================================
local CenterPoint = Vector3.new(0, 5, 0)
local CenterIsSaved = false
local CenterScanned = false
local CenterDummy = nil
local function centerCFrame()
    if not CenterIsSaved and not CenterScanned then
        CenterScanned = true
        local dummy = workspace:FindFirstChild("Weakest Dummy", true)
        if dummy then
            local p = dummy:IsA("BasePart") and dummy or
                (dummy:IsA("Model") and (dummy.PrimaryPart or
                    dummy:FindFirstChild("HumanoidRootPart") or dummy:FindFirstChildWhichIsA("BasePart", true)))
            if p and validPoint(p.Position) then
                CenterDummy = dummy
                CenterPoint = p.Position + Vector3.new(7, 0, 0)
            end
        end
    end
    local own = getHRP(Player)
    local hum = speedHumanoid()
    if not own or not hum then return nil end
    local point = CenterPoint
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignores = {Player.Character}
    if CenterDummy then table.insert(ignores, CenterDummy) end
    for _, user in ipairs(Players:GetPlayers()) do
        if user ~= Player and user.Character then table.insert(ignores, user.Character) end
    end
    params.FilterDescendantsInstances = ignores
    local ground = workspace:Raycast(Vector3.new(point.X, point.Y + 30, point.Z),
        Vector3.new(0, -130, 0), params)
    local y = ground and (ground.Position.Y + hum.HipHeight + own.Size.Y * 0.5 + 0.3) or point.Y
    local position = Vector3.new(point.X, y, point.Z)
    return validPoint(position) and CFrame.new(position) or nil
end
local function goToCenter()
    local cf = centerCFrame()
    local char = Player.Character
    if not cf or not char or moveBlocked(speedHumanoid()) then return false end
    return pcall(function()
        char:PivotTo(cf)
        local root = getHRP(Player)
        if root then root.AssemblyLinearVelocity = Vector3.zero end
    end)
end
local function setRandomStatus(message)
    local status = Refs.AutoStatus
    if status and status.Parent and status.Text ~= message then status.Text = message end
end
local function cycleValid(token)
    return Active and RandomCycle.enabled and token == RandomCycle.token
end
local function usedSkill(slot)
    if not RandomCycle.enabled or (slot ~= 1 and slot ~= 2) then return end
    local now = os.clock()
    -- Avoid repeated UI / keyboard activations resetting a running cooldown.
    if now + 0.2 < RandomCycle.readyAt[slot] then return end
    RandomCycle.readyAt[slot] = now + (slot == 1 and CONFIG.RANDOM_CD1 or CONFIG.RANDOM_CD2)
    setRandomStatus("Навык " .. slot .. " отмечен • перезарядка")
end
local function abilitySlotFromText(s)
    if type(s) ~= "string" then return nil end
    local str = string.lower(s)
    if str:find("flowing water", 1, true) or str:find("water stream", 1, true) then return 1 end
    if str:find("lethal whirlwind", 1, true) or str:find("whirlwind stream", 1, true) then return 2 end
    return nil
end
local WatchedSkillButtons = setmetatable({}, {__mode="k"})
local WatchedSkillTools = setmetatable({}, {__mode="k"})
local function autoObserveManualInputs()
    -- Detect only explicit user activations, never simulate an attack or skill.
    local gui = Player:FindFirstChildOfClass("PlayerGui")
    if gui then
        for _, item in ipairs(gui:GetDescendants()) do
            if item:IsA("GuiButton") and not WatchedSkillButtons[item] then
                local slot = abilitySlotFromText(item.Name)
                    or (item:IsA("TextButton") and abilitySlotFromText(item.Text))
                if not slot then
                    local parent = item.Parent
                    if parent then
                        slot = abilitySlotFromText(parent.Name)
                        if not slot then
                            for _, label in ipairs(parent:GetChildren()) do
                                if label:IsA("TextLabel") then
                                    slot = abilitySlotFromText(label.Text)
                                    if slot then break end
                                end
                            end
                        end
                    end
                end
                if slot then
                    WatchedSkillButtons[item] = true
                    table.insert(CleanupConnections, item.Activated:Connect(function()
                        if RandomCycle.enabled then usedSkill(slot) end
                    end))
                end
            end
        end
    end
    local bag = Player:FindFirstChildOfClass("Backpack")
    for _, parent in ipairs({Player.Character, bag}) do
        if parent then
            for _, tool in ipairs(parent:GetChildren()) do
                if tool:IsA("Tool") and not WatchedSkillTools[tool] then
                    local slot = abilitySlotFromText(tool.Name)
                    if slot then
                        WatchedSkillTools[tool] = true
                        table.insert(CleanupConnections, tool.Activated:Connect(function()
                            if RandomCycle.enabled then usedSkill(slot) end
                        end))
                    end
                end
            end
        end
    end
end
-- Desktop keys work without needing a mark click. Mobile GUI observation is
-- best-effort because game layouts change; manual mark buttons always work.
table.insert(CleanupConnections, UserInputService.InputBegan:Connect(function(input)
    if not Active or not RandomCycle.enabled or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.One then usedSkill(1) end
    if input.KeyCode == Enum.KeyCode.Two then usedSkill(2) end
end))
Refs.SkillOneButton.Activated:Connect(function() usedSkill(1) end)
Refs.SkillTwoButton.Activated:Connect(function() usedSkill(2) end)
Refs.SaveCenterButton.Activated:Connect(function()
    local root = getHRP(Player)
    if not root then setRandomStatus("Центр: персонаж недоступен"); return end
    CenterPoint = root.Position
    CenterIsSaved = true
    setRandomStatus("Центр сохранён (текущая позиция)")
end)
Refs.GoCenterButton.Activated:Connect(function()
    if RandomCycle.enabled then StopRandomCycle(true) end
    setRandomStatus(goToCenter() and "TP в центр выполнен" or "Центр недоступен")
end)
local LastCycleOpponentId = nil
local function chooseCycleTarget()
    local matches, fresh = {}, {}
    for _, opponent in ipairs(Players:GetPlayers()) do
        if opponent ~= Player and isAlive(opponent) and getHRP(opponent) then
            table.insert(matches, opponent)
            if opponent.UserId ~= LastCycleOpponentId then table.insert(fresh, opponent) end
        end
    end
    local pool = #fresh > 0 and fresh or matches
    if #pool == 0 then return nil end
    local p = pool[math.random(1, #pool)]
    LastCycleOpponentId = p.UserId
    return p
end
StopRandomCycle = function(updateStatus)
    if RandomCycle.followConnection then
        RandomCycle.followConnection:Disconnect()
        RandomCycle.followConnection = nil
    end
    if RandomCycle.enabled then
        RandomCycle.enabled = false
        RandomCycle.token = RandomCycle.token + 1
    end
    RandomCycle.phase = "off"
    RandomCycle.target = nil
    RandomCycle.centered = false
    Refs.AutoStartButton.BackgroundColor3 = Color3.fromRGB(17, 143, 89)
    if updateStatus ~= false then setRandomStatus("Рандомный режим выключен") end
end
StartRandomCycle = function()
    if not Active or RandomCycle.enabled then return end
    if not isAlive(Player) or not getHRP(Player) then
        setRandomStatus("Сначала дождись появления персонажа")
        return
    end
    if TrashAutoEnabled or TrashBusy then
        setRandomStatus("Сначала выключи работу с мусором")
        return
    end
    if BackstabActive and StopBackstab then StopBackstab() end
    if CONFIG.SAFE_ZONE and SafeTriggered then
        setRandomStatus("Отключи активную безопасную зону")
        return
    end
    RandomCycle.enabled = true
    RandomCycle.token = RandomCycle.token + 1
    RandomCycle.centered = false
    RandomCycle.phase = "choose"
    RandomCycle.target = nil
    local token = RandomCycle.token
    Refs.AutoStartButton.BackgroundColor3 = Color3.fromRGB(12, 96, 73)
    -- First TP is synchronous on START when a slot is available.
    local startClock = os.clock()
    if startClock >= RandomCycle.readyAt[1] or startClock >= RandomCycle.readyAt[2] then
        RandomCycle.target = chooseCycleTarget()
        if RandomCycle.target then
            RandomCycle.phase = "chase"
            teleportToOpponent(RandomCycle.target, CONFIG.RANDOM_TARGET_RANGE, true)
        end
    end
    setRandomStatus("Рандомный режим активен • навыки нажимай сам")
    -- Regular Heartbeat follows the player without an artificial polling delay.
    RandomCycle.followConnection = RunService.Heartbeat:Connect(function()
        if cycleValid(token) and RandomCycle.phase == "chase" and
            RandomCycle.target and isAlive(RandomCycle.target) then
            pcall(teleportToOpponent, RandomCycle.target, CONFIG.RANDOM_TARGET_RANGE, false)
        end
    end)
    task.spawn(function()
        local lastStatusAt = -1e9
        local lastWatchAt = -1e9
        while cycleValid(token) do
            if not isAlive(Player) or not getHRP(Player) then
                setRandomStatus("Персонаж недоступен; цикл остановлен")
                StopRandomCycle(false)
                break
            end
            local now = os.clock()
            if now - lastWatchAt > 1.25 then
                lastWatchAt = now
                pcall(autoObserveManualInputs)
            end
            local ready1 = now >= RandomCycle.readyAt[1]
            local ready2 = now >= RandomCycle.readyAt[2]
            if not ready1 and not ready2 then
                RandomCycle.phase = "center"
                RandomCycle.target = nil
                if not RandomCycle.centered then
                    RandomCycle.centered = goToCenter()
                    if not RandomCycle.centered then
                        setRandomStatus("TP в центр недоступен • повтор")
                    end
                end
            elseif RandomCycle.centered and (not ready1 or not ready2) then
                RandomCycle.phase = "center"
                RandomCycle.target = nil
            else
                if RandomCycle.centered and ready1 and ready2 then
                    RandomCycle.centered = false
                    RandomCycle.target = nil
                    RandomCycle.phase = "choose"
                end
                if not RandomCycle.target or not isAlive(RandomCycle.target) or
                    not getHRP(RandomCycle.target) then
                    RandomCycle.target = chooseCycleTarget()
                    RandomCycle.phase = RandomCycle.target and "chase" or "idle"
                    if RandomCycle.target then
                        teleportToOpponent(RandomCycle.target, CONFIG.RANDOM_TARGET_RANGE, true)
                    end
                end
            end
            if now - lastStatusAt > 0.45 then
                lastStatusAt = now
                if RandomCycle.phase == "center" then
                    local remaining = math.max(0, math.max(RandomCycle.readyAt[1], RandomCycle.readyAt[2]) - now)
                    setRandomStatus("Оба навыка на CD → центр • до восстановления ~" .. math.ceil(remaining) .. " с")
                elseif RandomCycle.phase == "chase" then
                    setRandomStatus("Цель найдена • используй навыки 1 и 2 вручную")
                else
                    setRandomStatus("Нет доступных целей • поиск продолжается")
                end
            end
            task.wait(0.035)
        end
    end)
end
Refs.AutoStartButton.Activated:Connect(StartRandomCycle)
Refs.AutoStopButton.Activated:Connect(function() StopRandomCycle(true) end)
for slot, input in ipairs({Refs.SkillCD1Input, Refs.SkillCD2Input}) do
    input.FocusLost:Connect(function()
        local value = tonumber(input.Text)
        if value and value == value and value > 0 and value ~= math.huge and value ~= -math.huge then
            value = math.clamp(math.floor(value + 0.5), 5, 90)
            if slot == 1 then CONFIG.RANDOM_CD1 = value else CONFIG.RANDOM_CD2 = value end
        end
        input.Text = tostring(slot == 1 and CONFIG.RANDOM_CD1 or CONFIG.RANDOM_CD2)
    end)
end

-- ------------------------------------------------------------
-- One-click extras (remote loader is explicitly user-requested).
-- ------------------------------------------------------------
local function paintOptimizeButton()
    Refs.OptimizationToggle.Text = Visual.state.wanted and "⚡ FPS OPTIMIZE: ON" or "⚡ FPS OPTIMIZE: OFF"
    Refs.OptimizationToggle.BackgroundColor3 = Visual.state.wanted
        and Color3.fromRGB(18, 125, 90) or Color3.fromRGB(125, 48, 58)
end
Refs.OptimizationToggle.Activated:Connect(function()
    if Visual.state.wanted then
        Visual.stop()
    else
        Visual.start()
    end
    paintOptimizeButton()
end)
local function paintDistanceButton()
    Refs.DistanceToggle.Text = Visual.state.distanceEnabled
        and "◎ DISTANCE ECO: ON" or "◎ DISTANCE ECO: OFF"
    Refs.DistanceToggle.BackgroundColor3 = Visual.state.distanceEnabled
        and Color3.fromRGB(18, 125, 90) or Color3.fromRGB(125, 48, 58)
end
Refs.DistanceToggle.Activated:Connect(function()
    Visual.setDistanceEnabled(not Visual.state.distanceEnabled)
    CONFIG.VISUAL_DISTANCE_ENABLED = Visual.state.distanceEnabled
    paintDistanceButton()
end)
Refs.RadiusInput.FocusLost:Connect(function()
    local n = tonumber(Refs.RadiusInput.Text)
    if n and n == n and n ~= math.huge and n ~= -math.huge then
        Visual.setRadius(n)
        CONFIG.VISUAL_RADIUS = Visual.state.radius
    end
    Refs.RadiusInput.Text = tostring(CONFIG.VISUAL_RADIUS)
end)


local HKG_URL = "https://raw.githubusercontent.com/pusahursahur-gif/HKG-hub./refs/heads/Lua/HKG-void"
local hkgStarted = false
local hkgLoading = false
Refs.HKGButton.Activated:Connect(function()
    if hkgLoading or hkgStarted then return end
    if type(loadstring) ~= "function" then
        Refs.HKGStatus.Text = "No loadstring support in this executor"
        return
    end
    hkgLoading = true
    Refs.HKGButton.Text = "ЗАГРУЗКА HKG VOID..."
    Refs.HKGStatus.Text = "Loading external code; this code is not audited."
    task.spawn(function()
        local okSource, source = pcall(function()
            return game:HttpGet(HKG_URL)
        end)
        if not Active then return end
        if not okSource or type(source) ~= "string" or #source == 0 then
            Refs.HKGStatus.Text = "Load failed: source is unavailable"
            Refs.HKGButton.Text = "▶ ПОВТОРИТЬ HKG VOID"
            hkgLoading = false
            return
        end
        local okRun, err = pcall(function()
            local compiled, why = loadstring(source)
            if not compiled then error(why or "Lua compilation failed") end
            compiled()
        end)
        if not Active then return end
        if okRun then
            hkgStarted = true
            Refs.HKGButton.Text = "✓ HKG VOID: ЗАПУЩЕН"
            Refs.HKGStatus.Text = "External script executed; its internal result is not verified."
        else
            Refs.HKGStatus.Text = "Error: " .. tostring(err):sub(1, 120)
            Refs.HKGButton.Text = "▶ ПОВТОРИТЬ HKG VOID"
        end
        hkgLoading = false
    end)
end)

-- BUTTON CONNECTIONS
-- ============================================================
-- Speed input applies only on focus loss; avoids per-keystroke writes.
SpeedInput.FocusLost:Connect(function()
    local value = tonumber(SpeedInput.Text)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        SpeedInput.Text = tostring(CONFIG.SPEED_VALUE)
        return
    end
    CONFIG.SPEED_VALUE = math.clamp(math.floor(value + 0.5), 8, 120)
    SpeedInput.Text = tostring(CONFIG.SPEED_VALUE)
    refreshSpeed()
end)

SpeedToggle.Activated:Connect(function()
    CONFIG.SPEED_ENABLED = not CONFIG.SPEED_ENABLED
    paintToggle(SpeedToggle, "SPEED", CONFIG.SPEED_ENABLED)
    if CONFIG.SPEED_ENABLED then
        refreshSpeed()
    else
        releaseSpeed()
    end
end)

local function paintLead()
    Refs.LeadToggle.Text = CONFIG.PING_COMPENSATE and "ОПЕРЕЖЕНИЕ ЦЕЛИ: ВКЛ" or "ОПЕРЕЖЕНИЕ ЦЕЛИ: ВЫКЛ"
    Refs.LeadToggle.BackgroundColor3 = CONFIG.PING_COMPENSATE
        and Color3.fromRGB(24, 125, 65) or Color3.fromRGB(150, 38, 48)
end
Refs.LeadToggle.Activated:Connect(function()
    CONFIG.PING_COMPENSATE = not CONFIG.PING_COMPENSATE
    paintLead()
end)
paintLead()
DistanceInput.FocusLost:Connect(function()
    local value = tonumber(DistanceInput.Text)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        DistanceInput.Text = tostring(CONFIG.BEHIND_STUDS)
        return
    end
    CONFIG.BEHIND_STUDS = math.clamp(math.floor(value * 10 + 0.5) / 10, 2.1, 8)
    DistanceInput.Text = tostring(CONFIG.BEHIND_STUDS)
end)

TpOnceButton.Activated:Connect(function()
    if StopRandomCycle then StopRandomCycle(false) end
    if not SelectedTarget then
        StatusLabel.Text = "Select a player first"
        return
    end
    local ok = Positioner.teleport(true)
    StatusLabel.Text = ok and ("TP attempted: " .. SelectedTarget.Name) or "TP failed: unavailable"
end)

RandomTPButton.Activated:Connect(function()
    if StopRandomCycle then StopRandomCycle(false) end
    local other = chooseRandomOpponent()
    if not other then
        StatusLabel.Text = "No alive players for random TP"
        return
    end
    if BackstabActive and StopBackstab then StopBackstab() end
    SelectedTarget = other
    RefreshPlayerList()
    if StartBackstab then StartBackstab() end
end)

TrashAutoButton.Activated:Connect(function()
    if StopRandomCycle then StopRandomCycle(true) end
    if BackstabActive and StopBackstab then StopBackstab() end
    trashCycle()
end)
TrashReturnButton.Activated:Connect(function()
    if StopRandomCycle then StopRandomCycle(true) end
    if BackstabActive and StopBackstab then StopBackstab() end
    trashReturnOnce()
end)

-- 20 Hz local speed assistance; writes may be rejected / corrected by game.

local lastSpeedTick = 0
SpeedLoopConnection = RunService.Heartbeat:Connect(function(dt)
    if not CONFIG.SPEED_ENABLED then return end
    local now = os.clock()
    if now - lastSpeedTick >= CONFIG.SPEED_UPDATE_INTERVAL then
        local elapsed = lastSpeedTick > 0 and now - lastSpeedTick or dt
        lastSpeedTick = now
        refreshSpeed()
        speedMovementAssist(elapsed)
    end
end)


StartButton.Activated:Connect(StartBackstab)
StopButton.Activated:Connect(StopBackstab)

SafeToggle.Activated:Connect(function()
    CONFIG.SAFE_ZONE = not CONFIG.SAFE_ZONE
    if not CONFIG.SAFE_ZONE then
        removeSafeZone(true)
        StatusLabel.Text = "SAVE ZONA disabled"
        StatusLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
    else
        SafeTriggered = false
        StatusLabel.Text = "SAVE ZONA armed • trigger at ≤" .. CONFIG.RESET_THRESHOLD .. " HP"
        StatusLabel.TextColor3 = Color3.fromRGB(80, 220, 255)
    end
    paintToggle(SafeToggle, "SAVE ZONA", CONFIG.SAFE_ZONE)
end)

InvisToggle.Activated:Connect(function()
    CONFIG.INVISIBLE = not CONFIG.INVISIBLE
    if CONFIG.INVISIBLE then
        Invisibility.apply()
        StatusLabel.Text = "INVIS ON • LOCAL ONLY"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 195, 95)
    else
        Invisibility.remove()
        StatusLabel.Text = "INVIS disabled"
        StatusLabel.TextColor3 = Color3.fromRGB(220, 225, 240)
    end
    paintToggle(InvisToggle, "INVIS", CONFIG.INVISIBLE)
end)

ResetToggle.Activated:Connect(function()
    CONFIG.AUTO_RESET = not CONFIG.AUTO_RESET
    paintToggle(ResetToggle, "AUTO RESET", CONFIG.AUTO_RESET)
    StatusLabel.Text = CONFIG.AUTO_RESET
        and "AUTO RESET armed • corpse vanishes on death"
        or "AUTO RESET disabled"
    StatusLabel.TextColor3 = CONFIG.AUTO_RESET
        and Color3.fromRGB(120, 245, 195)
        or Color3.fromRGB(220, 225, 240)
end)

-- One shutdown path for title-bar X and re-execution.
Shutdown = function()
    if closing then return end
    closing = true
    local function safe(callback) pcall(callback) end
    safe(function() if StopRandomCycle then StopRandomCycle(false) end end)
    Active = false
    safe(Visual.stop)
    safe(stopTrash)
    safe(function() setAimEnabled(false) end)
    safe(function() RunService:UnbindFromRenderStep(AimRenderName) end)
    safe(function() RunService:UnbindFromRenderStep(MoveRenderName) end)
    safe(function() if TrashIndexConnection then TrashIndexConnection:Disconnect() end end)
    safe(function() CONFIG.SPEED_ENABLED = false; releaseSpeed() end)
    safe(function() if SpeedLoopConnection then SpeedLoopConnection:Disconnect() end end)
    safe(function() if PositionConnection then PositionConnection:Disconnect() end end)
    safe(function() if Refs.moveConnection then Refs.moveConnection:Disconnect() end end)
    safe(function() StopBackstab() end)
    safe(function() refreshRotationLock() end)
    safe(function() removeSafeZone(false) end) -- no unwanted exit teleport
    safe(Invisibility.remove)
    CONFIG.INVISIBLE = false
    for _, conn in pairs({HealthConnection, DeathConnection, CharacterConnection,
        DescendantConnection, InvisHardConnection}) do
        if conn then safe(function() conn:Disconnect() end) end
    end
    for _, conn in ipairs(CleanupConnections) do
        if conn then safe(function() conn:Disconnect() end) end
    end
    safe(function() if HiddenFolder then HiddenFolder:Destroy() end end)
    if sharedEnvironment and sharedEnvironment.__TSB_DELTA_V21_SHUTDOWN == Shutdown then
        sharedEnvironment.__TSB_DELTA_V21_SHUTDOWN = nil
    end
    safe(function() ScreenGui:Destroy() end)
end
if sharedEnvironment then sharedEnvironment.__TSB_DELTA_V21_SHUTDOWN = Shutdown end

-- ============================================================
-- PLAYER JOIN / LEAVE
-- ============================================================
table.insert(CleanupConnections, Players.PlayerAdded:Connect(function(newPlayer)
    RefreshPlayerList()
end))

table.insert(CleanupConnections, Players.PlayerRemoving:Connect(function(player)
    if RandomCycle.target == player then RandomCycle.target = nil end
    if AimTarget == player then
        clearAimTarget()
        StatusLabel.Text = "AIM: выбранный игрок вышел"
    end
    if SelectedTarget == player then
        if BackstabActive and StopBackstab then StopBackstab() end
        SelectedTarget = nil
    end
    RefreshPlayerList()
    UpdateStatus()
end))

-- ============================================================
-- RESPAWN
-- ============================================================
CharacterConnection = Player.CharacterAdded:Connect(function(character)
    if StopRandomCycle then StopRandomCycle(false) end
    local resumeFollow = FollowWanted and SelectedTarget ~= nil
    if BackstabActive and StopBackstab then StopBackstab(true) end
    -- Keep the long-running AUTO toggle armed across respawns.
    if not TrashAutoEnabled then
        TrashToken = TrashToken + 1
        TrashBusy = false
        TrashPhase = "idle"
    end
    -- Keep AIM lock on the same player after our own respawn.
    OriginalWalkSpeed = nil
    SpeedHumanoid = nil
    CurrentSpeedWritten = nil
    if CONFIG.SPEED_ENABLED then task.defer(refreshSpeed) end
    Invisibility.remove()
    PreviousAutoRotate = nil
    SafeTriggered = false
    if SafePlatform then removeSafeZone(false) end

    monitorHealth(character)

    if resumeFollow and SelectedTarget then
        task.defer(function()
            if not Active or Player.Character ~= character then return end
            local hum = character:WaitForChild("Humanoid", 10)
            local root = character:WaitForChild("HumanoidRootPart", 10)
            if hum and root and FollowWanted and SelectedTarget and StartBackstab then
                StartBackstab() -- target may be respawning too; Heartbeat will retry
            end
        end)
    end

    if CONFIG.INVISIBLE then
        task.defer(function()
            if Player.Character == character then
                Invisibility.apply()
            end
        end)
    end
end)

if Player.Character then
    task.defer(monitorHealth, Player.Character)
end

-- ============================================================
-- INIT
-- ============================================================
RefreshPlayerList()
UpdateStatus()
Visual.start()  -- default performance mode ON; reversible in Extras.
paintOptimizeButton()
paintDistanceButton()
-- No popup during startup; all controls are visible in the panel.
