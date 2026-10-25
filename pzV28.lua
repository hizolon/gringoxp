-- TSB_DELTA_v28 | streamlined mobile controls and standalone Invis
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
    AIM_ENABLED = false,
    -- Approximations for Garou's normal (non-awakened) abilities.
    -- Client-side timers cannot observe authoritative server cooldowns.
    RANDOM_CD1 = 18,
    RANDOM_CD2 = 21,
    RANDOM_TARGET_RANGE = 2.9,
    WALL_PASS = false,
    SS_POSITIONING = false,
}

-- ============================================================
-- FPS ULTRA: local, bounded graphics suppression and particle cleanup.
-- Remote network packets / server scripts cannot be cleaned by a client.
-- Never remove collision/physics/characters or call server remotes.
-- Toggle ON/OFF restores reversible properties; particles already
-- cleared from rendering cannot be recreated by the toggle.
-- ============================================================
local Visual = {}
do
    local Lighting = game:GetService("Lighting")
    local state = {
        active=false, wanted=false, generation=0, addedConn=nil, lightConn=nil,
        originals=setmetatable({}, {__mode="k"}),
        effects=setmetatable({}, {__mode="k"}),
        seen=setmetatable({}, {__mode="k"}),
        candidates={}, hidden=setmetatable({}, {__mode="k"}),
        radius=CONFIG.VISUAL_RADIUS,
        distanceEnabled=CONFIG.VISUAL_DISTANCE_ENABLED,
        inspected=0, cleared=0, liveFX=0, sweeps=0,
    }
    local fxTypes = {
        ParticleEmitter=true, Trail=true, Beam=true, Smoke=true,
        Fire=true, Sparkles=true,
    }
    local function alive(obj)
        return obj and obj.Parent ~= nil
    end
    local function remember(obj, prop, value)
        local ok, prev = pcall(function() return obj[prop] end)
        if not ok or prev == value then return end
        local saved = state.originals[obj]
        if not saved then saved={}; state.originals[obj]=saved end
        if saved[prop] == nil then saved[prop]=prev end
        pcall(function() obj[prop]=value end)
    end
    local function playerAncestor(obj)
        local p=obj
        while p and p ~= workspace do
            if p:IsA("Model") and p:FindFirstChildOfClass("Humanoid") then
                return true
            end
            p=p.Parent
        end
        return false
    end
    local function cosmeticPart(obj)
        if not obj:IsA("BasePart") or not obj.Anchored or obj.CanCollide
            or obj.CanTouch or obj.Transparency >= 0.98 then return false end
        if playerAncestor(obj) then return false end
        local p=obj
        while p and p ~= workspace do
            local name=string.lower(p.Name)
            if name:find("hitbox",1,true) or name:find("combat",1,true)
                or name:find("projectile",1,true) or name:find("attack",1,true)
                or name:find("weapon",1,true) or name:find("dummy",1,true) then
                return false
            end
            p=p.Parent
        end
        return true
    end
    local function addCandidate(obj)
        if state.seen[obj] or #state.candidates >= 950 then return end
        if not cosmeticPart(obj) then return end
        state.seen[obj]=true
        state.candidates[#state.candidates+1]=obj
    end
    local function optimize(obj)
        if not state.active or not alive(obj) then return end
        local kind=obj.ClassName
        if fxTypes[kind] then
            if not state.effects[obj] then
                state.effects[obj]=true
                state.liveFX=state.liveFX+1
            end
            remember(obj,"Enabled",false)
            if kind=="ParticleEmitter" or kind=="Trail" then
                -- Flush visible particle/trail history instead of retaining it.
                pcall(function() obj:Clear() end)
                state.cleared=state.cleared+1
            end
        elseif obj:IsA("PostEffect") then
            remember(obj,"Enabled",false)
        elseif kind=="PointLight" or kind=="SpotLight" or kind=="SurfaceLight" then
            if not playerAncestor(obj) then remember(obj,"Enabled",false) end
        elseif obj:IsA("BasePart") then
            if cosmeticPart(obj) then
                remember(obj,"CastShadow",false)
                if state.distanceEnabled then addCandidate(obj) end
            end
        elseif (kind=="Decal" or kind=="Texture") then
            local parent=obj.Parent
            if parent and cosmeticPart(parent) then
                remember(obj,"Transparency",1)
            end
        end
        state.inspected=state.inspected+1
    end
    local function restoreDistance()
        for obj, old in pairs(state.hidden) do
            pcall(function()
                if alive(obj) and obj.LocalTransparencyModifier==1 then
                    obj.LocalTransparencyModifier=old
                end
            end)
        end
        state.hidden=setmetatable({}, {__mode="k"})
    end
    local function distancePass()
        if not state.distanceEnabled then return end
        local character=Player.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local p=root.Position
        local far=(state.radius+15)^2
        local near=(state.radius-10)^2
        local out={}
        for _,obj in ipairs(state.candidates) do
            if alive(obj) and cosmeticPart(obj) then
                out[#out+1]=obj
                local q=obj.Position
                local d=(p.X-q.X)^2+(p.Y-q.Y)^2+(p.Z-q.Z)^2
                if d>far and state.hidden[obj]==nil then
                    local ok,old=pcall(function() return obj.LocalTransparencyModifier end)
                    if ok and old<1 then
                        state.hidden[obj]=old
                        pcall(function() obj.LocalTransparencyModifier=1 end)
                    end
                elseif d<near and state.hidden[obj]~=nil then
                    local old=state.hidden[obj]
                    pcall(function()
                        if obj.LocalTransparencyModifier==1 then
                            obj.LocalTransparencyModifier=old
                        end
                    end)
                    state.hidden[obj]=nil
                end
            else
                state.seen[obj]=nil
                state.hidden[obj]=nil
            end
        end
        state.candidates=out -- prune destroyed references, avoid growing forever
    end
    local function auditFX()
        local total=0
        for obj in pairs(state.effects) do
            if alive(obj) then
                total=total+1
                if total<=2600 then
                    -- Game code may re-enable the same emitter between attacks.
                    local ok,enabled=pcall(function() return obj.Enabled end)
                    if ok and enabled then
                        pcall(function() obj.Enabled=false end)
                    end
                    -- :Emit() can create particles even when Enabled is false.
                    -- Periodic capped clearing prevents lingering emitted particles.
                    if total<=650 and (obj:IsA("ParticleEmitter") or obj:IsA("Trail")) then
                        pcall(function() obj:Clear() end)
                        state.cleared=state.cleared+1
                    end
                end
            else
                state.effects[obj]=nil
            end
        end
        state.liveFX=total
        state.sweeps=state.sweeps+1
    end
    local function scanGradually(token)
        local queue=workspace:GetChildren()
        for _,obj in ipairs(Lighting:GetChildren()) do queue[#queue+1]=obj end
        local n=1
        local tail=#queue
        local inspected=0
        while state.active and state.generation==token and n<=tail and inspected<30000 do
            local obj=queue[n]
            queue[n]=nil -- keep the breadth-first queue memory-bounded
            n=n+1
            if alive(obj) then
                pcall(optimize,obj)
                if obj~=workspace.CurrentCamera then
                    for _,child in ipairs(obj:GetChildren()) do
                        tail=tail+1
                        queue[tail]=child
                    end
                end
            end
            inspected=inspected+1
            if inspected%90==0 then task.wait() end
        end
    end
    Visual.start=function()
        state.wanted=true
        if state.active then return end
        state.active=true
        state.generation=state.generation+1
        local token=state.generation
        remember(Lighting,"GlobalShadows",false)
        state.addedConn=workspace.DescendantAdded:Connect(function(obj)
            pcall(optimize,obj)
        end)
        state.lightConn=Lighting.DescendantAdded:Connect(function(obj)
            pcall(optimize,obj)
        end)
        task.spawn(scanGradually,token)
        task.spawn(function()
            local loops=0
            while state.active and state.generation==token do
                loops=loops+1
                pcall(auditFX)
                if loops%3==0 then pcall(distancePass) end
                task.wait(2.5) -- never walk the whole map each frame
            end
        end)
    end
    Visual.stop=function()
        state.wanted=false
        state.active=false
        state.generation=state.generation+1
        if state.addedConn then state.addedConn:Disconnect();state.addedConn=nil end
        if state.lightConn then state.lightConn:Disconnect();state.lightConn=nil end
        restoreDistance()
        for obj,properties in pairs(state.originals) do
            if alive(obj) then
                for property,original in pairs(properties) do
                    pcall(function() obj[property]=original end)
                end
            end
        end
        state.originals=setmetatable({}, {__mode="k"})
        state.effects=setmetatable({}, {__mode="k"})
        state.candidates={}
        state.seen=setmetatable({}, {__mode="k"})
        state.liveFX=0
    end
    Visual.setRadius=function(v)
        state.radius=math.clamp(math.floor(v+0.5),80,300)
    end
    Visual.setDistanceEnabled=function(enabled)
        state.distanceEnabled=enabled==true
        if not state.distanceEnabled then restoreDistance() end
    end
    Visual.state=state
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
    for _, key in ipairs({"__TSB_DELTA_V28_SHUTDOWN", "__TSB_DELTA_V27_SHUTDOWN", "__TSB_DELTA_V26_SHUTDOWN", "__TSB_DELTA_V25_SHUTDOWN", "__TSB_DELTA_V24_SHUTDOWN", "__TSB_DELTA_V23_SHUTDOWN", "__TSB_DELTA_V22_SHUTDOWN", "__TSB_DELTA_V21_SHUTDOWN", "__TSB_DELTA_V20_SHUTDOWN", "__TSB_DELTA_V19_SHUTDOWN"}) do
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
            if gui:IsA("ScreenGui") and (gui.Name:match("^%a+TSBv%d+$") or gui.Name == "TSB_Delta_Clean" or gui.Name == "TSB_Delta_V20" or gui.Name == "TSB_Delta_V21" or gui.Name == "TSB_Delta_V22" or gui.Name == "TSB_Delta_V23" or gui.Name == "TSB_Delta_V24" or gui.Name == "TSB_Delta_V25" or gui.Name == "TSB_Delta_V26" or gui.Name == "TSB_Delta_V27" or gui.Name == "TSB_DELTA_v28") then
                gui:Destroy()
            end
        end
    end)
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "TSB_DELTA_v28"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 150
local guiOK = pcall(function() ScreenGui.Parent = CoreGui end)
if not guiOK then
    local alternate = Player:FindFirstChildOfClass("PlayerGui") or Player:WaitForChild("PlayerGui", 7)
    if not alternate then error("TSB: no UI parent") end
    ScreenGui.Parent = alternate
end
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local MainFrame = Instance.new("Frame")
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(480, 680)
local PANEL_W = math.max(238, math.min(348, math.floor(viewport.X - 24)))
local PANEL_H = math.max(278, math.min(455, math.floor(viewport.Y - 26)))
MainFrame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
MainFrame.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
MainFrame.BackgroundColor3 = Color3.fromRGB(14, 20, 31)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = false
MainFrame.Parent = ScreenGui

local MainFrameCorner = Instance.new("UICorner")
MainFrameCorner.CornerRadius = UDim.new(0, 12)
MainFrameCorner.Parent = MainFrame

local MainFrameStroke = Instance.new("UIStroke")
MainFrameStroke.Color = Color3.fromRGB(59, 180, 207)
MainFrameStroke.Thickness = 1.2
MainFrameStroke.Parent = MainFrame
local panelGradient=Instance.new("UIGradient")
panelGradient.Rotation=90
panelGradient.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(23,33,48)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(12,17,27)),
})
panelGradient.Parent=MainFrame

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 32)
TitleBar.BackgroundColor3 = Color3.fromRGB(19, 48, 66)
TitleBar.BorderSizePixel = 0
TitleBar.Active = true
TitleBar.Parent = MainFrame
local barGradient=Instance.new("UIGradient")
barGradient.Color=ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(18,58,79)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(15,33,51)),
})
barGradient.Parent=TitleBar

local TitleBarCorner = Instance.new("UICorner")
TitleBarCorner.CornerRadius = UDim.new(0, 4)
TitleBarCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -77, 1, 0)
Title.BackgroundTransparency = 1
Title.Text = "TSB_DELTA_v28"
Title.TextColor3 = Color3.fromRGB(134, 246, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 13
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Position = UDim2.new(0, 9, 0, 0)
Title.Parent = TitleBar
Title.Active = true

local CloseButton = Instance.new("TextButton")
CloseButton.Position = UDim2.new(1, -32, 0, 1)
CloseButton.Size = UDim2.fromOffset(30, 30)
CloseButton.BackgroundColor3 = Color3.fromRGB(153, 49, 65)
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
MinimizeButton.BackgroundColor3 = Color3.fromRGB(39, 58, 74)
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
SelectionCorner.CornerRadius = UDim.new(0, 9)
SelectionCorner.Parent = SelectionFrame
local rosterStroke=Instance.new("UIStroke")
rosterStroke.Color=Color3.fromRGB(42,65,85)
rosterStroke.Thickness=1
rosterStroke.Parent=SelectionFrame

local PlayerScrollFrame = Instance.new("ScrollingFrame")
PlayerScrollFrame.Position = UDim2.new(0, 4, 0, 4)
PlayerScrollFrame.Size = UDim2.new(1, -8, 1, -8)
PlayerScrollFrame.BackgroundTransparency = 1
PlayerScrollFrame.BorderSizePixel = 0
PlayerScrollFrame.ScrollBarThickness = 4
PlayerScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(67, 191, 212)
PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
PlayerScrollFrame.Parent = SelectionFrame

local StartButton = Instance.new("TextButton")
StartButton.Position = UDim2.new(0, 7, 0, 196)
StartButton.Size = UDim2.new(0.5, -10, 0, 28)
StartButton.BackgroundColor3 = Color3.fromRGB(12, 159, 103)
StartButton.BorderSizePixel = 0
StartButton.Text = "START"
StartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StartButton.Font = Enum.Font.SourceSansBold
StartButton.TextSize = 12
StartButton.Parent = MainFrame

local StartCorner = Instance.new("UICorner")
StartCorner.CornerRadius = UDim.new(0, 8)
StartCorner.Parent = StartButton

local StopButton = Instance.new("TextButton")
StopButton.Position = UDim2.new(0.5, 3, 0, 196)
StopButton.Size = UDim2.new(0.5, -10, 0, 28)
StopButton.BackgroundColor3 = Color3.fromRGB(168, 57, 71)
StopButton.BorderSizePixel = 0
StopButton.Text = "STOP"
StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
StopButton.Font = Enum.Font.SourceSansBold
StopButton.TextSize = 12
StopButton.Parent = MainFrame

local StopCorner = Instance.new("UICorner")
StopCorner.CornerRadius = UDim.new(0, 8)
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
    corner.CornerRadius = UDim.new(0, 8)
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
    button.BackgroundColor3 = enabled and Color3.fromRGB(19, 128, 104) or Color3.fromRGB(48, 60, 81)
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
local innerW -- shared with the player-list builder after UI creation
do
-- ============================================================
-- Compact mobile panel, four pages and draggable title
-- ============================================================
MainFrame.ClipsDescendants = true
Title.Text = "TSB_DELTA_v28"
StatusLabel.Parent = MainFrame
StatusLabel.Position = UDim2.fromOffset(10, 38)
StatusLabel.Size = UDim2.new(1, -20, 0, 21)
StatusLabel.TextSize = 12
StatusLabel.TextTruncate = Enum.TextTruncate.AtEnd
StatusLabel.TextColor3 = Color3.fromRGB(224, 242, 249)

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
    button.Font = Enum.Font.GothamBold
    button.TextSize = 10
    button.Text = tabName
    button.BorderSizePixel = 0
    button.Parent = TabsBar
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 9)
    tabButtons[index] = button
    local page = Instance.new("Frame")
    page.Name = "Page" .. index
    page.BackgroundColor3 = Color3.fromRGB(21, 29, 43)
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
        tabButtons[i].BackgroundColor3 = i == index and Color3.fromRGB(19, 131, 156) or Color3.fromRGB(32, 43, 62)
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
innerW = PAGE_W - 16
local halfW = math.floor((innerW - 8) / 2)
local rightX = 8 + halfW + 8
local rightW = innerW - halfW - 8
local function infoLabel(parent, message, y, h)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(157, 185, 204)
    label.Font = Enum.Font.Gotham
    label.TextSize = 11
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
local targetListHeight = math.max(100, PAGE_H - 210)
local RosterLabel = infoLabel(TargetScroll, "ИГРОКИ: загрузка…", 12, 25)
RosterLabel.Size = UDim2.fromOffset(halfW - 4, 25)
RosterLabel.Font = Enum.Font.SourceSansBold
RosterLabel.TextColor3 = Color3.fromRGB(166, 237, 255)
local RefreshPlayersButton = Instance.new("TextButton")
RefreshPlayersButton.Name = "RefreshPlayers"
RefreshPlayersButton.Text = "↻ ОБНОВИТЬ"
RefreshPlayersButton.Font = Enum.Font.SourceSansBold
RefreshPlayersButton.TextSize = 12
RefreshPlayersButton.TextColor3 = Color3.fromRGB(234, 255, 255)
RefreshPlayersButton.BackgroundColor3 = Color3.fromRGB(24, 114, 135)
RefreshPlayersButton.BorderSizePixel = 0
relayout(RefreshPlayersButton, TargetScroll, rightX, 5, rightW, 29)
Instance.new("UICorner", RefreshPlayersButton).CornerRadius = UDim.new(0, 7)
relayout(SelectionFrame, TargetScroll, 8, 40, innerW, targetListHeight)
PlayerScrollFrame.Size = UDim2.new(1, -8, 1, -8)
relayout(StartButton, TargetScroll, 8, targetListHeight + 48, halfW, 35)
relayout(StopButton, TargetScroll, rightX, targetListHeight + 48, rightW, 35)
StartButton.Text = "▶ START / TP"
StopButton.Text = "ОСТАНОВИТЬ"
StartButton.TextSize = 11
StopButton.TextSize = 11
relayout(TpOnceButton, TargetScroll, 8, targetListHeight + 90, halfW, 34)
relayout(RandomTPButton, TargetScroll, rightX, targetListHeight + 90, rightW, 34)
TpOnceButton.Text = "TP СЕЙЧАС"
RandomTPButton.Text = "TP РАНДОМ"
relayout(DistanceLabel, TargetScroll, 8, targetListHeight + 132, halfW, 34)
DistanceLabel.Text = "ДИСТАНЦИЯ"
relayout(DistanceInput, TargetScroll, rightX, targetListHeight + 132, rightW, 34)
local LeadToggle = Instance.new("TextButton")
LeadToggle.Name = "LeadToggle"
LeadToggle.BorderSizePixel = 0
LeadToggle.Font = Enum.Font.SourceSansBold
LeadToggle.TextSize = 12
LeadToggle.TextColor3 = Color3.new(1, 1, 1)
relayout(LeadToggle, TargetScroll, 8, targetListHeight + 174, innerW, 35)
Instance.new("UICorner", LeadToggle).CornerRadius = UDim.new(0, 6)
infoLabel(TargetScroll, "Выбери игрока (галочка), затем START. TP повторяется непрерывно; STOP прекращает. Автоатак нет.", targetListHeight + 217, 48)
TargetScroll.CanvasSize = UDim2.fromOffset(0, targetListHeight + 282)

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
ControlsScroll.CanvasSize = UDim2.fromOffset(0, 282)
ControlsScroll.ScrollBarThickness = 3
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
-- Compact layout: core functions only; every control has an independent row.
feature(AimToggle, 8, 134, innerW, 36)
local QuickOptimizeButton = Instance.new("TextButton")
QuickOptimizeButton.Name = "QuickFPSUltra"
QuickOptimizeButton.BackgroundColor3 = Color3.fromRGB(22, 131, 98)
QuickOptimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
QuickOptimizeButton.Font = Enum.Font.GothamBold
QuickOptimizeButton.TextSize = 14
QuickOptimizeButton.BorderSizePixel = 0
QuickOptimizeButton.Text = "⚡ FPS ULTRA: ON"
relayout(QuickOptimizeButton, ControlsScroll, 8, 179, innerW, 43)
Instance.new("UICorner", QuickOptimizeButton).CornerRadius = UDim.new(0, 8)
local FPSStatus = infoLabel(ControlsScroll,
    "Очистка накопленных визуальных частиц, отключение тяжёлых эффектов. Без изменения физики и сетевых пакетов.",
    236, 66)
FPSStatus.Name = "FPSStatus"
infoLabel(ControlsScroll,
    "AIM: наведи центр камеры и нажми кружок для фиксации одной цели. Отключается отдельно.",
    316, 60)
ControlsScroll.CanvasSize = UDim2.fromOffset(0, 400)

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

-- Standalone manual loader: visually distinct, never executed on opening the menu.
local DangerLaunchButton = Instance.new("TextButton")
DangerLaunchButton.Name = "LaunchDangerModule"
DangerLaunchButton.BorderSizePixel = 0
DangerLaunchButton.Text = ""
DangerLaunchButton.AutoButtonColor = false
DangerLaunchButton.BackgroundColor3 = Color3.fromRGB(92, 15, 22)
relayout(DangerLaunchButton, ExtraScroll, 8, 9, innerW, 66)
Instance.new("UICorner", DangerLaunchButton).CornerRadius = UDim.new(0, 9)
local DangerGradient = Instance.new("UIGradient")
DangerGradient.Rotation = 0
DangerGradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(21, 9, 16)),
    ColorSequenceKeypoint.new(0.48, Color3.fromRGB(143, 21, 33)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(47, 8, 22)),
})
DangerGradient.Parent = DangerLaunchButton
local DangerBorder = Instance.new("UIStroke")
DangerBorder.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
DangerBorder.Color = Color3.fromRGB(255, 69, 80)
DangerBorder.Thickness = 1.7
DangerBorder.Parent = DangerLaunchButton
local DangerTitle = Instance.new("TextLabel")
DangerTitle.Name = "DangerTitle"
DangerTitle.BackgroundTransparency = 1
DangerTitle.Font = Enum.Font.GothamBlack
DangerTitle.Text = "☠  DANGER SCRIPT  ☠"
DangerTitle.TextSize = 16
DangerTitle.TextScaled = false
DangerTitle.TextTruncate = Enum.TextTruncate.AtEnd
DangerTitle.TextColor3 = Color3.fromRGB(255, 244, 242)
DangerTitle.Size = UDim2.new(1, -18, 0, 29)
DangerTitle.Position = UDim2.fromOffset(9, 7)
DangerTitle.Parent = DangerLaunchButton
local DangerSubtitle = Instance.new("TextLabel")
DangerSubtitle.BackgroundTransparency = 1
DangerSubtitle.Font = Enum.Font.GothamBold
DangerSubtitle.Text = "МОДУЛЬ  •  НАЖМИ ДЛЯ ЗАПУСКА"
DangerSubtitle.TextSize = 10
DangerSubtitle.TextColor3 = Color3.fromRGB(255, 191, 174)
DangerSubtitle.Size = UDim2.new(1, -18, 0, 18)
DangerSubtitle.Position = UDim2.fromOffset(9, 37)
DangerSubtitle.Parent = DangerLaunchButton
local DangerStatus = infoLabel(ExtraScroll,
    "Внешний модуль: загружается только после нажатия. Содержимое по ссылке не проверено.",
    81, 47)

local OptimizationToggle = Instance.new("TextButton")
OptimizationToggle.Name = "OptimizationToggle"
OptimizationToggle.BorderSizePixel = 0
OptimizationToggle.Font = Enum.Font.SourceSansBold
OptimizationToggle.TextSize = 14
OptimizationToggle.TextColor3 = Color3.new(1, 1, 1)
relayout(OptimizationToggle, ExtraScroll, 8, 139, innerW, 40)
Instance.new("UICorner", OptimizationToggle).CornerRadius = UDim.new(0, 6)
infoLabel(ExtraScroll, "Тени декора, частицы и тяжёлые эффекты: OFF. Игроки, физика, коллизии и интерфейс сохраняются. Можно отключить режим.", 187, 64)

local DistanceToggle = Instance.new("TextButton")
DistanceToggle.Name = "DistanceEcoToggle"
DistanceToggle.BorderSizePixel = 0
DistanceToggle.Font = Enum.Font.SourceSansBold
DistanceToggle.TextSize = 13
DistanceToggle.TextColor3 = Color3.new(1,1,1)
relayout(DistanceToggle, ExtraScroll, 8, 257, innerW, 36)
Instance.new("UICorner", DistanceToggle).CornerRadius = UDim.new(0, 6)

local RadiusLabel = infoLabel(ExtraScroll, "Радиус декора (80–300 studs):", 306, 33)
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
relayout(RadiusInput, ExtraScroll, rightX, 306, rightW, 34)
Instance.new("UICorner", RadiusInput).CornerRadius = UDim.new(0, 6)
infoLabel(ExtraScroll, "Важно: скрипт не может включить серверный StreamingEnabled. Коллизии, физика, NPC и боевые объекты остаются. Изменения графики обратимы.", 351, 68)

local HKGButton = Instance.new("TextButton")
HKGButton.Name = "ExternalHKGVoid"
HKGButton.BorderSizePixel = 0
HKGButton.BackgroundColor3 = Color3.fromRGB(76, 75, 149)
HKGButton.TextColor3 = Color3.new(1, 1, 1)
HKGButton.Font = Enum.Font.SourceSansBold
HKGButton.TextSize = 15
HKGButton.Text = "▶ ЗАПУСТИТЬ HKG VOID"
relayout(HKGButton, ExtraScroll, 8, 425, innerW, 39)
Instance.new("UICorner", HKGButton).CornerRadius = UDim.new(0, 7)
local HKGStatus = infoLabel(ExtraScroll, "Дополнительный код запускается только по нажатию. Источник не проверен.", 470, 76)

-- Imported features from two supplied variants; merged as native controls.
local ImportHeading = infoLabel(ExtraScroll, "ДОПОЛНИТЕЛЬНЫЕ РЕЖИМЫ", 545, 26)
ImportHeading.Font = Enum.Font.SourceSansBold
ImportHeading.TextColor3 = Color3.fromRGB(166, 237, 255)
local function importedButton(id, caption, x, y, width, color)
    local b=Instance.new("TextButton")
    b.Name=id
    b.BorderSizePixel=0
    b.BackgroundColor3=color
    b.TextColor3=Color3.fromRGB(255,255,255)
    b.Font=Enum.Font.GothamBold
    b.TextSize=12
    b.Text=caption
    b.TextTruncate=Enum.TextTruncate.AtEnd
    relayout(b, ExtraScroll, x, y, width, 38)
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,7)
    return b
end
local WallButton=importedButton("WallPass", "WALL PASS: OFF", 8, 579, innerW, Color3.fromRGB(117,43,61))
local PrecisionButton=importedButton("ImportedPrecision", "TP SS+ MODE: OFF", 8, 625, innerW, Color3.fromRGB(33,100,137))
local CoordSafeButton=importedButton("CoordinateSafe", "TP К КООРДИНАТАМ: OFF", 8, 671, innerW, Color3.fromRGB(108,80,32))
local ImportedStatus=infoLabel(ExtraScroll,
    "WALL PASS меняет локальные столкновения со стенами. " ..
    "TP SS+ уточняет позицию. TP к Y=-10000 опасен и может привести к смерти.",
    716, 80)
ImportedStatus.Name="ImportedStatus"
ExtraScroll.CanvasSize = UDim2.fromOffset(0, 805)
Refs.WallButton=WallButton
Refs.PrecisionButton=PrecisionButton
Refs.CoordSafeButton=CoordSafeButton
Refs.ImportedStatus=ImportedStatus
Refs.DangerLaunchButton = DangerLaunchButton
Refs.DangerTitle = DangerTitle
Refs.DangerSubtitle = DangerSubtitle
Refs.DangerStatus = DangerStatus
Refs.DangerBorder = DangerBorder


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
Refs.QuickOptimizeButton = QuickOptimizeButton
Refs.FPSStatus = FPSStatus
Refs.RosterLabel = RosterLabel
Refs.RefreshPlayersButton = RefreshPlayersButton
Refs.DistanceToggle = DistanceToggle
Refs.RadiusInput = RadiusInput
Refs.HKGButton = HKGButton
Refs.HKGStatus = HKGStatus
Refs.moveConnection = moveConnection
end


-- Draggable right-side menu grip and compact INVIS off switch.
-- The buttons can be tapped or moved independently with touch/mouse.
local floatingConnections={}
local function addFloatingConnection(conn)
    table.insert(floatingConnections,conn)
    return conn
end
local function makeDraggableFloating(button, onTap)
    local drag=nil
    local initial=nil
    local origin=nil
    local moved=false
    addFloatingConnection(button.InputBegan:Connect(function(input)
        if input.UserInputType~=Enum.UserInputType.Touch and
           input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        drag=input
        initial=Vector2.new(input.Position.X,input.Position.Y)
        origin=button.AbsolutePosition
        moved=false
        button:SetAttribute("WasDragged",false)
    end))
    addFloatingConnection(UserInputService.InputChanged:Connect(function(input)
        if not drag or not initial or not origin then return end
        if drag.UserInputType==Enum.UserInputType.Touch then
            if input~=drag then return end
        elseif input.UserInputType~=Enum.UserInputType.MouseMovement then
            return
        end
        local delta=Vector2.new(input.Position.X,input.Position.Y)-initial
        if delta.Magnitude>8 then moved=true end
        if not moved then return end
        button:SetAttribute("WasDragged",true)
        local cam=workspace.CurrentCamera
        local vp=cam and cam.ViewportSize or Vector2.new(800,600)
        local size=button.AbsoluteSize
        local x=math.clamp(origin.X+delta.X,4,math.max(4,vp.X-size.X-4))
        local y=math.clamp(origin.Y+delta.Y,4,math.max(4,vp.Y-size.Y-4))
        button.Position=UDim2.fromOffset(math.floor(x),math.floor(y))
    end))
    addFloatingConnection(UserInputService.InputEnded:Connect(function(input)
        if not drag then return end
        if drag.UserInputType==Enum.UserInputType.Touch and input~=drag then return end
        if drag.UserInputType==Enum.UserInputType.MouseButton1 and
           input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
        drag=nil
        initial=nil
        origin=nil
    end))
    if onTap then
        addFloatingConnection(button.Activated:Connect(function()
            if button:GetAttribute("WasDragged") then return end
            onTap()
        end))
    end
end

local DockButton = Instance.new("TextButton")
DockButton.Name="SideMenuToggle"
DockButton.Size=UDim2.fromOffset(38,38)
DockButton.Position=UDim2.fromOffset(math.max(5,viewport.X-52), math.floor(viewport.Y*0.31))
DockButton.BackgroundColor3=Color3.fromRGB(22,98,132)
DockButton.BorderSizePixel=0
DockButton.Text="≡"
DockButton.TextSize=25
DockButton.Font=Enum.Font.GothamBold
DockButton.TextColor3=Color3.new(1,1,1)
DockButton.ZIndex=25
DockButton.Active=true
DockButton.Parent=ScreenGui
Instance.new("UICorner",DockButton).CornerRadius=UDim.new(0,10)
local dockStroke=Instance.new("UIStroke",DockButton)
dockStroke.Color=Color3.fromRGB(67,206,236)
dockStroke.Thickness=1
makeDraggableFloating(DockButton,function()
    if closing then return end
    MainFrame.Visible=not MainFrame.Visible
    DockButton.BackgroundColor3=MainFrame.Visible
        and Color3.fromRGB(22,98,132) or Color3.fromRGB(35,117,102)
    if MainFrame.Visible then task.defer(ensurePanelOnscreen) end
end)

local InvisHud=Instance.new("TextButton")
InvisHud.Name="InvisSwitch"
InvisHud.Size=UDim2.fromOffset(35,35)
InvisHud.Position=UDim2.fromOffset(math.max(5,viewport.X-100),math.floor(viewport.Y*0.46))
InvisHud.BackgroundColor3=Color3.fromRGB(22,125,105)
InvisHud.BorderSizePixel=0
InvisHud.Text="INV"
InvisHud.TextSize=10
InvisHud.Font=Enum.Font.GothamBold
InvisHud.TextColor3=Color3.new(1,1,1)
InvisHud.ZIndex=26
InvisHud.Visible=false
InvisHud.Active=true
InvisHud.Parent=ScreenGui
Instance.new("UICorner",InvisHud).CornerRadius=UDim.new(1,0)
local invisStroke=Instance.new("UIStroke",InvisHud)
invisStroke.Color=Color3.fromRGB(94,236,206)
invisStroke.Thickness=1
makeDraggableFloating(InvisHud)
Refs.floatingConnections=floatingConnections

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
local Evading = false -- compatibility guard only; never set true in v16
local OriginalWalkSpeed = nil
local SpeedHumanoid = nil
local CurrentSpeedWritten = nil
local SpeedLoopConnection = nil
local Active = true
local AimTarget = nil
local AimRenderName = "TSB_DELTA_AIM_V28"
local LastRealSpeed = 0
local MoveRenderName = "TSB_DELTA_MOVE_V28"

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
-- IMPORTED MODES: independent state, no extra ScreenGui and no remotes.
-- ============================================================
local WallMode = {
    original=setmetatable({}, {__mode="k"}),
    tickConnection=nil, accumulator=0,
}
local wallParams=RaycastParams.new()
wallParams.FilterType=Enum.RaycastFilterType.Exclude
wallParams.IgnoreWater=true
local wallHeights={-0.85,0.9}
local wallDirections={
    Vector3.new(1,0,0),Vector3.new(-1,0,0),
    Vector3.new(0,0,1),Vector3.new(0,0,-1),
    Vector3.new(0.7071,0,0.7071),Vector3.new(-0.7071,0,0.7071),
    Vector3.new(0.7071,0,-0.7071),Vector3.new(-0.7071,0,-0.7071),
}
local function wallDistanceToBounds(part, point)
    local p=part.CFrame:PointToObjectSpace(point)
    local r=part.Size*0.5
    local dx=math.max(math.abs(p.X)-r.X,0)
    local dy=math.max(math.abs(p.Y)-r.Y,0)
    local dz=math.max(math.abs(p.Z)-r.Z,0)
    return math.sqrt(dx*dx+dy*dy+dz*dz)
end
local function wallRestore()
    if WallMode.tickConnection then
        WallMode.tickConnection:Disconnect()
        WallMode.tickConnection=nil
    end
    for part, previous in pairs(WallMode.original) do
        if part and part.Parent then
            pcall(function() part.CanCollide=previous end)
        end
        WallMode.original[part]=nil
    end
    WallMode.accumulator=0
end
local function wallScan()
    local char=Player.Character
    local root=getHRP(Player)
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not char or not root or not hum or hum.Health<=0 then return end
    local ignored={char}
    if SafePlatform then ignored[#ignored+1]=SafePlatform end
    wallParams.FilterDescendantsInstances=ignored
    local below=workspace:Raycast(root.Position, Vector3.new(0,-5,0),wallParams)
    local floor=below and below.Normal.Y>0.55 and below.Instance or nil
    for _, dir in ipairs(wallDirections) do
        for _, h in ipairs(wallHeights) do
            local hit=workspace:Raycast(root.Position+Vector3.new(0,h,0),dir*4.5,wallParams)
            local part=hit and hit.Instance
            if part and part:IsA("BasePart") and part~=floor
                and part.Anchored and part.CanCollide and math.abs(hit.Normal.Y)<0.4 then
                local horizontal=math.abs(part.CFrame.UpVector.Y)>0.8
                    and part.Size.Y<3 and (part.Size.X>8 or part.Size.Z>8)
                if not horizontal then
                    if WallMode.original[part]==nil then
                        WallMode.original[part]=part.CanCollide
                    end
                    pcall(function() part.CanCollide=false end)
                end
            end
        end
    end
    for part, old in pairs(WallMode.original) do
        if not part or not part.Parent then
            WallMode.original[part]=nil
        elseif wallDistanceToBounds(part,root.Position)>7 then
            pcall(function() part.CanCollide=old end)
            WallMode.original[part]=nil
        end
    end
end
local function wallStart()
    if WallMode.tickConnection then return end
    WallMode.accumulator=0
    pcall(wallScan)
    WallMode.tickConnection=RunService.Heartbeat:Connect(function(dt)
        if not Active or not CONFIG.WALL_PASS then return end
        WallMode.accumulator=WallMode.accumulator+dt
        if WallMode.accumulator<0.12 then return end
        WallMode.accumulator=0
        pcall(wallScan)
    end)
end

local CoordMode={active=false, previous=nil, platform=nil}
local COORD_CFRAME=CFrame.new(
    -216.581772,-10000.0029,-145.716171,
    0.852498353,-1.00300547e-07,0.522729933,
    6.29894217e-08,1,8.91515128e-08,
    -0.522729933,-4.30750616e-08,0.852498353
)
local function coordReturn(restore)
    if CoordMode.platform then CoordMode.platform:Destroy();CoordMode.platform=nil end
    if restore and CoordMode.previous then
        local char, root=Player.Character,getHRP(Player)
        if char and root then
            pcall(function()
                char:PivotTo(CoordMode.previous)
                root.AssemblyLinearVelocity=Vector3.zero
                root.AssemblyAngularVelocity=Vector3.zero
            end)
        end
    end
    CoordMode.previous=nil
    CoordMode.active=false
end
local function coordGo()
    local char, root=Player.Character,getHRP(Player)
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not char or not root or not hum or hum.Health<=0 then
        return false,"персонаж ещё не готов"
    end
    if root.Anchored then return false,"персонаж закреплён" end
    CoordMode.previous=root.CFrame
    local floor=Instance.new("Part")
    floor.Name="ImportedCoordinateFloor"
    floor.Size=Vector3.new(28,2,28)
    floor.Anchored=true
    floor.CanCollide=true
    floor.CanTouch=false
    floor.CanQuery=false
    floor.CastShadow=false
    floor.Transparency=1
    floor.CFrame=CFrame.new(COORD_CFRAME.Position-Vector3.new(0,3,0))
    floor.Parent=workspace
    CoordMode.platform=floor
    local ok,err=pcall(function()
        char:PivotTo(COORD_CFRAME)
        root.AssemblyLinearVelocity=Vector3.zero
        root.AssemblyAngularVelocity=Vector3.zero
    end)
    if not ok then coordReturn(false); return false,tostring(err):sub(1,90) end
    CoordMode.active=true
    return true,"клиентский TP выполнен; сервер может откатить"
end

-- ============================================================
-- INVIS: isolated clone-based mode adapted from the provided IY code.
-- No command bar, no network loader, no remote scanning or asset removal.
-- TSB/server anti-cheat may reverse this client-side technique.
-- ============================================================
local Invisibility = {}
local InvisMode = {
    active=false, switching=false, original=nil, clone=nil,
    originalArchivable=nil, camera=nil, deathConn=nil,
    ignoredEvents=setmetatable({}, {__mode="k"}),
}
function Invisibility.isManagedCharacter(character)
    if InvisMode.ignoredEvents[character] then
        InvisMode.ignoredEvents[character]=nil
        return true
    end
    return InvisMode.switching or (InvisMode.active and character==InvisMode.clone)
end
function Invisibility.apply()
    if InvisMode.active then return true end
    if InvisMode.switching then return false,"переключение ещё выполняется" end
    local original=Player.Character
    local root=original and original:FindFirstChild("HumanoidRootPart")
    local hum=original and original:FindFirstChildOfClass("Humanoid")
    if not original or not root or not hum or hum.Health<=0 then
        return false,"персонаж не готов"
    end
    local archivable=original.Archivable
    local okClone,clone=pcall(function()
        original.Archivable=true
        return original:Clone()
    end)
    pcall(function() original.Archivable=archivable end)
    if not okClone or not clone then return false,"не удалось создать копию персонажа" end
    local cloneRoot=clone:FindFirstChild("HumanoidRootPart")
    local cloneHum=clone:FindFirstChildOfClass("Humanoid")
    if not cloneRoot or not cloneHum then
        clone:Destroy()
        return false,"копия персонажа неполная"
    end
    clone.Name="InvisAvatar"
    local target=root.CFrame
    local camera=workspace.CurrentCamera
    local originalParent=original.Parent
    InvisMode.switching=true
    InvisMode.ignoredEvents[clone]=true
    local success,why=pcall(function()
        -- The real avatar is parked locally; the controlled clone takes its place.
        original.Parent=game:GetService("Lighting")
        clone.Parent=workspace
        clone:PivotTo(target)
        Player.Character=clone
        if camera then camera.CameraSubject=cloneHum end
        local animate=clone:FindFirstChild("Animate")
        if animate and animate:IsA("LocalScript") then
            animate.Disabled=true
            animate.Disabled=false
        end
    end)
    if not success then
        pcall(function()
            Player.Character=original
            original.Parent=originalParent or workspace
            original:PivotTo(target)
            if camera then camera.CameraSubject=hum end
        end)
        pcall(function() clone:Destroy() end)
        InvisMode.switching=false
        return false,tostring(why):sub(1,80)
    end
    InvisMode.original=original
    InvisMode.originalParent=originalParent
    InvisMode.clone=clone
    InvisMode.camera=camera
    InvisMode.active=true
    InvisMode.switching=false
    -- A dead clone should never leave a disconnected character behind.
    InvisMode.deathConn=cloneHum.Died:Connect(function()
        task.defer(function()
            if InvisMode.active and InvisMode.clone==clone then
                CONFIG.INVISIBLE=false
                Invisibility.remove(true)
                if Invisibility.onChange then Invisibility.onChange(false,"INVIS отключён после смерти") end
            end
        end)
    end)
    return true
end
function Invisibility.remove(recover)
    if InvisMode.switching then return end
    if not InvisMode.active and not InvisMode.clone then return end
    local original,clone=InvisMode.original,InvisMode.clone
    local camera=InvisMode.camera or workspace.CurrentCamera
    local originalParent=InvisMode.originalParent
    InvisMode.switching=true
    if InvisMode.deathConn then InvisMode.deathConn:Disconnect() end
    InvisMode.deathConn=nil
    local returnToAvatar=(recover~=false and original and original.Parent)
    local cf
    if clone and clone.Parent then
        local root=clone:FindFirstChild("HumanoidRootPart")
        if root then cf=root.CFrame end
    end
    if returnToAvatar then
        InvisMode.ignoredEvents[original]=true
        pcall(function()
            original.Parent=originalParent or workspace
            if cf then original:PivotTo(cf) end
            Player.Character=original
            if camera then
                local humanoid=original:FindFirstChildOfClass("Humanoid")
                if humanoid then camera.CameraSubject=humanoid end
            end
        end)
    elseif original and original.Parent==game:GetService("Lighting") then
        -- Character was replaced by a genuine respawn; do not revive an old avatar.
        pcall(function() original:Destroy() end)
    end
    if clone then pcall(function() clone:Destroy() end) end
    InvisMode.active=false
    InvisMode.original=nil
    InvisMode.clone=nil
    InvisMode.camera=nil
    InvisMode.originalParent=nil
    InvisMode.switching=false
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
    platform.Name = "TSBLocalSafeZone"
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
-- TSB server can override character controls and abilities.
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
    if CONFIG.SS_POSITIONING and not ragdolled then
        -- Alternative source formula. Capped extrapolation and predicted facing.
        local dt=math.min(math.clamp(getPing(),0,300)/1000*1.3,0.12)
        local velocity=targetHRP.AssemblyLinearVelocity
        local flatVel=Vector3.new(velocity.X,0,velocity.Z)
        local lead=flatVel*dt
        if lead.Magnitude>3 then lead=lead.Unit*3 end
        pos=pos+lead
        local ang=targetHRP.AssemblyAngularVelocity
        if ang.Magnitude>0.1 then
            local delta=CFrame.fromAxisAngle(ang.Unit,math.min(ang.Magnitude*dt,math.pi/2))
            local rotated=delta:VectorToWorldSpace(flatLook)
            local flat=Vector3.new(rotated.X,0,rotated.Z)
            if flat.Magnitude>0.05 then flatLook=flat.Unit end
        end
        local destination=Vector3.new(pos.X,pos.Y+CONFIG.HEIGHT_OFFSET,pos.Z)-flatLook*studs
        if not validPoint(destination) then return nil end
        return CFrame.lookAt(destination,Vector3.new(pos.X,destination.Y,pos.Z))
    end
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

local TPDiag = {
    attempts=0, applied=0, corrections=0, lastApplied=nil, lastTime=0,
    checkedAt=0, lastMode="none", lastError="", checkBackAt=0,
}

-- Try root CFrame first because some experiences expose the local character's
-- root but temporarily reject a whole-model PivotTo call. Validate the result.
-- This cannot bypass server-authoritative movement or anti-cheat.
function Positioner.teleport(force)
    if not Active then return false, "скрипт остановлен" end
    if not SelectedTarget or SelectedTarget.Parent ~= Players then
        return false, "цель не выбрана или вышла"
    end
    if SafeTriggered or ResetInProgress or CoordMode.active then
        return false, "активна безопасная зона / сброс"
    end
    local char, root = Player.Character, getHRP(Player)
    local targetRoot = getHRP(SelectedTarget)
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not char or not root or not hum or hum.Health <= 0 then
        return false, "ожидание персонажа"
    end
    if not targetRoot or not isAlive(SelectedTarget) then
        return false, "ожидание появления цели"
    end
    if root.Anchored then return false, "персонаж закреплён игрой" end
    local targetCF = Positioner.getBehindCFrame(targetRoot)
    if not targetCF then return false, "координаты цели недоступны" end
    local gap = (root.Position - targetCF.Position).Magnitude
    if not force and gap <= math.max(CONFIG.POSITION_TOLERANCE, 0.7) then
        return true, "рядом с целью"
    end
    TPDiag.attempts = TPDiag.attempts + 1
    local errorText = ""
    local function apply(mode)
        local ok, err = pcall(function()
            if mode == "root" then
                root.CFrame = targetCF
            else
                char:PivotTo(targetCF)
            end
            if force then
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
            end
        end)
        if not ok then errorText = tostring(err) end
        local measured = (root.Position - targetCF.Position).Magnitude
        if ok and measured <= 2.8 then
            TPDiag.applied = TPDiag.applied + 1
            TPDiag.lastApplied = targetCF.Position
            TPDiag.lastTime = os.clock()
            TPDiag.lastMode = mode
            return true
        end
        return false
    end
    -- Alternate the methods when one cannot move the local root.
    local worked = apply("root")
    if not worked then worked = apply("pivot") end
    if not worked then
        TPDiag.lastError = errorText ~= "" and errorText or "позиция не изменилась"
        return false, "TP отклонён локально: " .. TPDiag.lastError:sub(1, 55)
    end
    return true, "TP локально выполнен"
end

local function teleportToOpponent(opponent, distance, force)
    if not Active or Evading or SafeTriggered or ResetInProgress or CoordMode.active then return false end
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
        -- jumps or the normal movement controller.
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
    -- Responsive layout: two stacked name lines, fixed avatar space.
    local rowWidth = math.max(110, PlayerScrollFrame.AbsoluteSize.X - 14)
    local avatarSize = 29
    local avatarX = rowWidth - avatarSize - 7
    local nameX = 33
    local nameW = math.max(65, avatarX - nameX - 8)
    for _, opponent in ipairs(all) do
        if opponent ~= Player then
            local entry = Instance.new("TextButton")
            entry.Name = "User_" .. tostring(opponent.UserId)
            entry.Text = ""
            entry.Size = UDim2.new(1, -9, 0, 44)
            entry.Position = UDim2.fromOffset(3, y)
            entry.BorderSizePixel = 0
            entry.AutoButtonColor = true
            entry.BackgroundColor3 = SelectedTarget == opponent
                and Color3.fromRGB(20, 86, 82) or Color3.fromRGB(37, 44, 60)
            entry.Parent = PlayerScrollFrame
            Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 7)

            local mark = Instance.new("TextLabel")
            mark.Name = "SelectedMark"
            mark.Size = UDim2.fromOffset(19, 19)
            mark.Position = UDim2.new(0, 7, 0.5, -10)
            mark.BackgroundColor3 = Color3.fromRGB(21, 29, 43)
            mark.Text = SelectedTarget == opponent and "✓" or ""
            mark.TextColor3 = Color3.fromRGB(71, 246, 170)
            mark.TextSize = 15
            mark.Font = Enum.Font.SourceSansBold
            mark.ZIndex = 2
            mark.Parent = entry
            Instance.new("UICorner", mark).CornerRadius = UDim.new(0, 5)

            -- Display name on the left; unique username on the right.
            -- Do not embed, cache or show any personal/account identifiers elsewhere.
            local display = Instance.new("TextLabel")
            display.Name = "DisplayName"
            display.Size = UDim2.fromOffset(nameW, 18)
            display.Position = UDim2.fromOffset(nameX, 5)
            display.BackgroundTransparency = 1
            display.Text = opponent.DisplayName
            display.Font = Enum.Font.GothamBold
            display.TextSize = 12
            display.TextXAlignment = Enum.TextXAlignment.Left
            display.TextColor3 = Color3.fromRGB(236, 245, 252)
            display.TextTruncate = Enum.TextTruncate.AtEnd
            display.ZIndex = 2
            display.Parent = entry

            local username = Instance.new("TextLabel")
            username.Name = "Username"
            username.Size = UDim2.fromOffset(nameW, 15)
            username.Position = UDim2.fromOffset(nameX, 23)
            username.BackgroundTransparency = 1
            username.Text = "@" .. opponent.Name
            username.Font = Enum.Font.Gotham
            username.TextSize = 11
            username.TextXAlignment = Enum.TextXAlignment.Left
            username.TextColor3 = Color3.fromRGB(145, 191, 218)
            username.TextTruncate = Enum.TextTruncate.AtEnd
            username.ZIndex = 2
            username.Parent = entry

            local avatar = Instance.new("ImageLabel")
            avatar.Name = "Avatar"
            avatar.Size = UDim2.fromOffset(avatarSize, avatarSize)
            avatar.Position = UDim2.new(0, avatarX, 0.5, -avatarSize / 2)
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
                if not Active or opponent.Parent~=Players then return end
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
            y = y + 49
        end
    end
    PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, y + 4)
    local count=0
    for _,p in ipairs(all) do if p ~= Player then count=count+1 end end
    Refs.RosterLabel.Text="ИГРОКИ: "..count
    if count==0 then
        local empty = Instance.new("TextLabel")
        empty.Name="RosterEmpty"
        empty.BackgroundTransparency=1
        empty.Text="Других игроков пока нет. Нажми ОБНОВИТЬ."
        empty.TextColor3=Color3.fromRGB(179,201,222)
        empty.TextSize=12
        empty.TextWrapped=true
        empty.Size=UDim2.new(1,-10,0,68)
        empty.Position=UDim2.fromOffset(4,12)
        empty.Parent=PlayerScrollFrame
        PlayerScrollFrame.CanvasSize=UDim2.fromOffset(0,78)
    end
end

local function safeRefreshPlayers()
    local ok, err=pcall(RefreshPlayerList)
    if not ok then
        Refs.RosterLabel.Text="СПИСОК: ОШИБКА"
        StatusLabel.Text="Ошибка списка: "..tostring(err):sub(1,68)
        StatusLabel.TextColor3=Color3.fromRGB(255,156,137)
    end
    return ok
end
Refs.RefreshPlayersButton.Activated:Connect(safeRefreshPlayers)
-- Do not wait until the end of the embedded command module to populate UI.
safeRefreshPlayers()
task.defer(function()
    if Active and ScreenGui.Parent then safeRefreshPlayers() end
end)

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
    if CoordMode.active then
        StatusLabel.Text="Сначала вернись из координатной зоны"
        return
    end
    if not SelectedTarget or SelectedTarget == Player or SelectedTarget.Parent ~= Players then
        StatusLabel.Text = "Сначала выбери игрока в списке"
        StatusLabel.TextColor3 = Color3.fromRGB(255, 182, 105)
        return
    end
    if StopRandomCycle then StopRandomCycle(false) end
    if SafeTriggered then removeSafeZone(false) end
    if CONFIG.SAFE_ZONE then
        CONFIG.SAFE_ZONE = false
        paintToggle(SafeToggle, "SAVE ZONA", false)
    end
    if PositionConnection then PositionConnection:Disconnect(); PositionConnection = nil end
    BackstabActive, FollowWanted = true, true
    local previousPosition = nil
    local previousAt = 0
    local retryClock, lastFeedback, lastMessage = 0, -1e9, nil
    local function tick()
        if not Active or not BackstabActive then return end
        if not SelectedTarget or SelectedTarget.Parent ~= Players then
            StopBackstab()
            StatusLabel.Text = "Цель покинула сервер"
            return
        end
        local now = os.clock()
        local root = getHRP(Player)
        -- Detect a correction between consecutive frames; do not call a local
        -- CFrame write 'successful server TP'.
        if previousPosition and root and now - previousAt < 0.45 then
            local dest = Positioner.getBehindCFrame(getHRP(SelectedTarget))
            if dest and (root.Position - previousPosition).Magnitude > 14
                and (root.Position - dest.Position).Magnitude > 14 then
                TPDiag.corrections = TPDiag.corrections + 1
            end
        end
        if now - retryClock < 1 / 45 then return end
        retryClock = now
        local okCall, moved, reason = pcall(Positioner.teleport, false)
        if not okCall then moved, reason = false, "ошибка TP: " .. tostring(moved):sub(1, 55) end
        if moved and root then
            previousPosition, previousAt = root.Position, now
        end
        local msg
        if not moved then
            msg = "TP: " .. tostring(reason or "неизвестная ошибка")
        elseif TPDiag.corrections >= 3 then
            msg = "TP откатывает сервер • клиент не может это отменить"
        else
            msg = "TP: преследование активно • попытки " .. TPDiag.applied
        end
        if msg ~= lastMessage and now - lastFeedback >= 0.22
            or now - lastFeedback >= 1.1 then
            StatusLabel.Text = msg
            StatusLabel.TextColor3 = moved and Color3.fromRGB(109, 244, 169)
                or Color3.fromRGB(255, 182, 105)
            if TPDiag.corrections >= 3 then
                StatusLabel.TextColor3 = Color3.fromRGB(255, 182, 105)
            end
            lastMessage, lastFeedback = msg, now
        end
    end
    TPDiag.corrections, TPDiag.applied, TPDiag.attempts = 0, 0, 0
    -- First attempt happens immediately in the button handler, not in a delayed task.
    local callOK, moved, reason = pcall(Positioner.teleport, true)
    if not callOK then moved, reason = false, "ошибка: " .. tostring(moved) end
    StatusLabel.Text = moved and "TP стартовал • удерживаю выбранную цель"
        or ("TP запущен • " .. tostring(reason))
    StatusLabel.TextColor3 = moved and Color3.fromRGB(109, 244, 169)
        or Color3.fromRGB(255, 182, 105)
    PositionConnection = RunService.Heartbeat:Connect(function()
        local ok, err = pcall(tick)
        if not ok and BackstabActive then
            local now = os.clock()
            if now-lastFeedback > 0.8 then
                StatusLabel.Text = "TP ошибка цикла: " .. tostring(err):sub(1, 60)
                StatusLabel.TextColor3 = Color3.fromRGB(255, 130, 110)
                lastFeedback = now
            end
        end
    end)
end

StopBackstab = function(preserveFollow)
    if not preserveFollow then FollowWanted = false end
    BackstabActive = false
    if PositionConnection then
        PositionConnection:Disconnect()
        PositionConnection = nil
    end
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
    if CoordMode.active then
        setRandomStatus("Сначала выйди из координатной зоны")
        return
    end
    if not isAlive(Player) or not getHRP(Player) then
        setRandomStatus("Сначала дождись появления персонажа")
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
    local enabled = Visual.state.wanted
    local label = enabled and "⚡ FPS ULTRA: ON" or "⚡ FPS ULTRA: OFF"
    local color = enabled and Color3.fromRGB(17, 137, 96)
        or Color3.fromRGB(135, 43, 61)
    for _,button in ipairs({Refs.OptimizationToggle, Refs.QuickOptimizeButton}) do
        button.Text=label
        button.BackgroundColor3=color
    end
    Refs.FPSStatus.Text = enabled
        and ("Оптимизация активна • обработано объектов: " .. Visual.state.inspected
             .. " • эффектов под контролем: " .. Visual.state.liveFX
             .. " • сбросов частиц: " .. Visual.state.cleared)
        or "Оптимизация выключена • визуальные настройки восстановлены"
end
local function switchOptimization()
    if Visual.state.wanted then Visual.stop() else Visual.start() end
    paintOptimizeButton()
end
Refs.OptimizationToggle.Activated:Connect(switchOptimization)
Refs.QuickOptimizeButton.Activated:Connect(switchOptimization)
local performanceStatusRunning = true
-- Status updates are slow and bounded: no per-frame GUI garbage.
task.spawn(function()
    while performanceStatusRunning and Active do
        pcall(paintOptimizeButton)
        task.wait(3.5)
    end
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


-- ------------------------------------------------------------
-- Manually launched external JNKIE module. User-provided URL only.
-- Neither HTTP download nor code execution occurs until the button is tapped.
-- Script content may change on the remote server without notice.
-- ------------------------------------------------------------
local JNKIE_DANGER_URL = "https://api.jnkie.com/api/v1/luascripts/public/e7272cc100526cce2983ec85de722d45e915a26117824385c78e0c30e61585f4/download"
local dangerStarted, dangerLoading = false, false
local function dangerUI(title, subtitle, status, stroke)
    if not Active or not ScreenGui.Parent then return end
    Refs.DangerTitle.Text = title
    Refs.DangerSubtitle.Text = subtitle
    Refs.DangerStatus.Text = status
    Refs.DangerBorder.Color = stroke
end
Refs.DangerLaunchButton.Activated:Connect(function()
    if dangerLoading or dangerStarted or not Active then return end
    if type(loadstring) ~= "function" then
        dangerUI("☠  НЕ ПОДДЕРЖИВАЕТСЯ", "НУЖЕН LOADSTRING",
            "Этот исполнитель не поддерживает loadstring.", Color3.fromRGB(255, 155, 70))
        return
    end
    dangerLoading = true
    dangerUI("⌛  ЗАГРУЖАЮ...", "МОДУЛЬ  •  ПРОВЕРКА ОТВЕТА",
        "Подключаюсь к указанному адресу...", Color3.fromRGB(255, 185, 65))
    task.spawn(function()
        local okFetch, sourceOrErr = pcall(function()
            return game:HttpGet(JNKIE_DANGER_URL)
        end)
        if not Active then return end
        if not okFetch or type(sourceOrErr) ~= "string" or sourceOrErr == "" then
            dangerLoading = false
            dangerUI("☠  ПОВТОРИТЬ ЗАПУСК", "МОДУЛЬ  •  НЕТ ОТВЕТА",
                "Загрузка не удалась: " .. tostring(sourceOrErr):sub(1, 105), Color3.fromRGB(255, 90, 90))
            return
        end
        local source = sourceOrErr
        if source:sub(1, 256):lower():find("<html", 1, true) or source:sub(1, 256):lower():find("<!doctype", 1, true) then
            dangerLoading = false
            dangerUI("☠  ПОВТОРИТЬ ЗАПУСК", "МОДУЛЬ  •  НЕКОРРЕКТНЫЙ ОТВЕТ",
                "Сервер вернул HTML вместо Lua-кода.", Color3.fromRGB(255, 90, 90))
            return
        end
        local okCompile, compiledOrErr = pcall(loadstring, source)
        if not okCompile or type(compiledOrErr) ~= "function" then
            dangerLoading = false
            dangerUI("☠  ПОВТОРИТЬ ЗАПУСК", "МОДУЛЬ  •  ОШИБКА LUA",
                "Код не скомпилирован: " .. tostring(compiledOrErr):sub(1, 105), Color3.fromRGB(255, 90, 90))
            return
        end
        -- Mark as started before entering the external chunk, which might not return.
        dangerStarted = true
        dangerLoading = false
        dangerUI("⌛  КОД ВЫПОЛНЯЕТСЯ", "МОДУЛЬ  •  НЕ ЗАПУСКАТЬ ДВАЖДЫ",
            "Модуль передан на выполнение. Работа его функций не подтверждена.", Color3.fromRGB(255, 105, 115))
        local okRun, runErr = pcall(compiledOrErr)
        if not Active then return end
        if okRun then
            dangerUI("☠  МОДУЛЬ ЗАПУЩЕН", "МОДУЛЬ  •  ПОВТОРНЫЙ ЗАПУСК ЗАБЛОКИРОВАН",
                "Код выполнен без ошибки Lua. Внутренние функции не проверены.", Color3.fromRGB(255, 105, 115))
        else
            dangerStarted = false
            dangerUI("☠  ПОВТОРИТЬ ЗАПУСК", "МОДУЛЬ  •  ОШИБКА ВЫПОЛНЕНИЯ",
                "Ошибка внешнего модуля: " .. tostring(runErr):sub(1, 105), Color3.fromRGB(255, 90, 90))
        end
    end)
end)

-- ------------------------------------------------------------
-- IMPORTED FEATURE BUTTONS: all explicitly manual, no extra GUI.
-- ------------------------------------------------------------
local function paintImported()
    Refs.WallButton.Text=CONFIG.WALL_PASS and "WALL PASS: ON" or "WALL PASS: OFF"
    Refs.WallButton.BackgroundColor3=CONFIG.WALL_PASS
        and Color3.fromRGB(17,128,91) or Color3.fromRGB(117,43,61)
    Refs.PrecisionButton.Text=CONFIG.SS_POSITIONING and "TP SS+ MODE: ON" or "TP SS+ MODE: OFF"
    Refs.PrecisionButton.BackgroundColor3=CONFIG.SS_POSITIONING
        and Color3.fromRGB(16,134,101) or Color3.fromRGB(33,100,137)
    Refs.CoordSafeButton.Text=CoordMode.active and "↩ НАЗАД С КООРДИНАТ" or "TP К КООРДИНАТАМ: OFF"
    Refs.CoordSafeButton.BackgroundColor3=CoordMode.active
        and Color3.fromRGB(27,123,104) or Color3.fromRGB(108,80,32)
end
Refs.WallButton.Activated:Connect(function()
    CONFIG.WALL_PASS=not CONFIG.WALL_PASS
    if CONFIG.WALL_PASS then wallStart() else wallRestore() end
    paintImported()
    Refs.ImportedStatus.Text=CONFIG.WALL_PASS
        and "WALL HACK включён: стены без локальных коллизий, пол сохраняется (если сервер разрешает)."
        or "WALL HACK выключен: коллизии восстановлены."
end)
Refs.PrecisionButton.Activated:Connect(function()
    CONFIG.SS_POSITIONING=not CONFIG.SS_POSITIONING
    paintImported()
    Refs.ImportedStatus.Text=CONFIG.SS_POSITIONING
        and "Альтернативное TP SS+ включено: прогноз движения и направления цели."
        or "TP SS+ выключено: используется штатный позиционер."
end)
Refs.CoordSafeButton.Activated:Connect(function()
    if CoordMode.active then
        coordReturn(true)
        Refs.ImportedStatus.Text="Возврат к сохранённой точке запрошен."
    else
        if BackstabActive and StopBackstab then StopBackstab() end
        if StopRandomCycle then StopRandomCycle(false) end
        if SafeTriggered then removeSafeZone(false) end
        if CONFIG.SAFE_ZONE then
            CONFIG.SAFE_ZONE=false
            paintToggle(SafeToggle,"SAVE ZONA",false)
        end
        local ok,reason=coordGo()
        Refs.ImportedStatus.Text=ok
            and "TP к Y = −10000 выполнен локально. ВНИМАНИЕ: возможны смерть и откат сервером."
            or ("TP не выполнен: "..tostring(reason))
    end
    paintImported()
end)
paintImported()

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
    safeRefreshPlayers()
    if StartBackstab then StartBackstab() end
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


StartButton.Activated:Connect(function()
    if CONFIG.INVISIBLE then
        StatusLabel.Text="Сначала выключи INVIS перед постоянным TP"
        return
    end
    StartBackstab()
end)
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

local function setInvis(enabled)
    if enabled==CONFIG.INVISIBLE then return end
    if enabled then
        -- Clone-based invisible mode conflicts with active follow/teleport loops.
        if BackstabActive and StopBackstab then StopBackstab() end
        if StopRandomCycle then StopRandomCycle(false) end
        local ok,why=Invisibility.apply()
        if not ok then
            CONFIG.INVISIBLE=false
            StatusLabel.Text="INVIS: "..tostring(why)
            StatusLabel.TextColor3=Color3.fromRGB(255,170,142)
        else
            CONFIG.INVISIBLE=true
            StatusLabel.Text="INVIS включён • удерживай кнопку для перемещения"
            StatusLabel.TextColor3=Color3.fromRGB(110,242,195)
        end
    else
        CONFIG.INVISIBLE=false
        Invisibility.remove(true)
        StatusLabel.Text="INVIS выключен"
        StatusLabel.TextColor3=Color3.fromRGB(225,236,246)
    end
    paintToggle(InvisToggle,"INVIS",CONFIG.INVISIBLE)
    InvisHud.Visible=CONFIG.INVISIBLE
end
Invisibility.onChange=function(active,message)
    CONFIG.INVISIBLE=active
    InvisHud.Visible=active
    paintToggle(InvisToggle,"INVIS",active)
    if message then StatusLabel.Text=message end
end
InvisToggle.Activated:Connect(function() setInvis(not CONFIG.INVISIBLE) end)
InvisHud.Activated:Connect(function()
    if InvisHud:GetAttribute("WasDragged") then return end
    setInvis(false)
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
    performanceStatusRunning = false
    safe(Visual.stop)
    safe(function() setAimEnabled(false) end)
    safe(function() RunService:UnbindFromRenderStep(AimRenderName) end)
    safe(function() RunService:UnbindFromRenderStep(MoveRenderName) end)
    safe(function() CONFIG.SPEED_ENABLED = false; releaseSpeed() end)
    safe(function() if SpeedLoopConnection then SpeedLoopConnection:Disconnect() end end)
    safe(function() if PositionConnection then PositionConnection:Disconnect() end end)
    safe(function() if Refs.moveConnection then Refs.moveConnection:Disconnect() end end)
    safe(function() StopBackstab() end)
    safe(function() refreshRotationLock() end)
    safe(function() removeSafeZone(false) end) -- no unwanted exit teleport
    safe(function() coordReturn(false) end)
    safe(wallRestore)
    CONFIG.WALL_PASS=false
    safe(function() Invisibility.remove(true) end)
    CONFIG.INVISIBLE = false
    for _, conn in ipairs(Refs.floatingConnections or {}) do
        safe(function() conn:Disconnect() end)
    end
    for _, conn in pairs({HealthConnection, DeathConnection, CharacterConnection}) do
        if conn then safe(function() conn:Disconnect() end) end
    end
    for _, conn in ipairs(CleanupConnections) do
        if conn then safe(function() conn:Disconnect() end) end
    end
    if sharedEnvironment and sharedEnvironment.__TSB_DELTA_V28_SHUTDOWN == Shutdown then
        sharedEnvironment.__TSB_DELTA_V28_SHUTDOWN = nil
    end
    safe(function() ScreenGui:Destroy() end)
end
if sharedEnvironment then sharedEnvironment.__TSB_DELTA_V28_SHUTDOWN = Shutdown end

-- ============================================================
-- PLAYER JOIN / LEAVE
-- ============================================================
table.insert(CleanupConnections, Players.PlayerAdded:Connect(function()
    task.defer(safeRefreshPlayers)
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
    safeRefreshPlayers()
    UpdateStatus()
end))

-- ============================================================
-- RESPAWN
-- ============================================================
CharacterConnection = Player.CharacterAdded:Connect(function(character)
    if Invisibility.isManagedCharacter(character) then return end
    if CONFIG.INVISIBLE then
        CONFIG.INVISIBLE=false
        Invisibility.remove(false)
        InvisHud.Visible=false
        paintToggle(InvisToggle,"INVIS",false)
    end
    -- Release all local wall collision changes and coordinate platform after death.
    local keepWall=CONFIG.WALL_PASS
    wallRestore()
    coordReturn(false)
    if keepWall then task.defer(function()
        if Active and CONFIG.WALL_PASS and Player.Character==character then wallStart() end
    end) end
    if StopRandomCycle then StopRandomCycle(false) end
    local resumeFollow = FollowWanted and SelectedTarget ~= nil
    if BackstabActive and StopBackstab then StopBackstab(true) end
    -- Keep the long-running AUTO toggle armed across respawns.
    -- Keep AIM lock on the same player after our own respawn.
    OriginalWalkSpeed = nil
    SpeedHumanoid = nil
    CurrentSpeedWritten = nil
    if CONFIG.SPEED_ENABLED then task.defer(refreshSpeed) end
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

    paintImported()
end)

if Player.Character then
    task.defer(monitorHealth, Player.Character)
end

-- ============================================================
-- INIT
-- ============================================================
safeRefreshPlayers()
UpdateStatus()
Visual.start()  -- default performance mode ON; reversible in Extras.
paintOptimizeButton()
paintDistanceButton()
-- No popup during startup; all controls are visible in the panel.
