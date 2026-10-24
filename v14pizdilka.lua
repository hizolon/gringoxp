-- GRINGO XP // SHADOW TSB v15 | LocalScript / client-side behavior only
--[[
██████╗ ██████╗ ██╗███╗   ██╗ ██████╗  ██████╗ 
██╔══██╗██╔══██╗██║████╗  ██║██╔════╝ ██╔═══██╗
██████╔╝██████╔╝██║██╔██╗ ██║██║  ███╗██║   ██║
██╔══██╗██╔══██╗██║██║╚██╗██║██║   ██║██║   ██║
██║  ██║██║  ██║██║██║ ╚████║╚██████╔╝╚██████╔╝
╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝  ╚═════╝
SCRIPT HIZOLON PRIVAT SS+
─────────────────────────
• INVIS: client-side appearance only; no unverified remote calls
• SAFE ZONA: армит → TP под карту только при ≤30 HP (жив)
• AUTO RESET: труп исчезает мгновенно при смерти
• Позиционирование позади цели на регулируемом расстоянии + пинг-компенсация
• Компактное широкое меню с прокруткой и выбором цели
• SPEED: ON/OFF + число + управляемое ускорение при движении
• AUTO EVADE удалён целиком: чужие атаки не запускают автоматические телепорты
• RANDOM CYCLE: Garou 1 → 2 → ожидание около центрального Dummy → повтор
• INSTANT SELECT: касание игрока выполняет немедленную попытку TP
• TRASH AUTO: непрерывный поиск с подтверждением подбора и повторными попытками
• THROW SPEED: целочисленная локальная скорость мусорки (бросок контролируется сервером)
• PICKUP + RETURN: один подбор с попыткой вернуться на прежнее место
• AIM LOCK: одна выбранная по прицелу цель, светящийся контур без заливки
Стиль: HIZOLON Fling TSB
Версия: SS+ (v15 instant select + random Garou skill cycle; no reactive evade)
]]

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
    BEHIND_STUDS = 5,
    POSITION_UPDATE_INTERVAL = 0.045, -- 22 Hz follow; selection teleport is immediate
    FOLLOW_CORRECTION_COOLDOWN = 0.22, -- reduce camera jitter from repeat pivots
    FOLLOW_HARD_SNAP_DISTANCE = 12, -- large errors corrected without easing
    FOLLOW_MANUAL_LEASH = 16, -- preserve WASD until target has moved far away
    POSITION_TOLERANCE = 3.0, -- ignore small movements instead of jittering

    HEIGHT_OFFSET = 0,

    INVISIBLE = false,
    SAFE_ZONE = false,
    AUTO_RESET = false,
    RESET_THRESHOLD = 30,
    SAFE_DEPTH = 80,
    SAFE_HEIGHT = 130,

    PING_COMPENSATE = true,
    PREDICTION_MULT = 1.0,
    PING_SAFETY = 1.3,
    MAX_LEAD_TIME = 0.07,
    SMOOTH_FACTOR = 1.0, -- instant target updates (no lerp)

    SPEED_ENABLED = false,
    SPEED_VALUE = 28,
    -- These are attempts at local movement; game/server restrictions still apply.
    SPEED_ACCELERATION = 0.82,
    SPEED_UPDATE_INTERVAL = 0.03,
    SPEED_STEP_MAX = 0.0, -- no CFrame stepping when moving; avoid camera jitter
    SPEED_STEP_MIN = 0.0,
    SPEED_WALL_PADDING = 1.8,
    TRASH_THROW_SPEED = 140,   -- local projectile velocity; server may override
    TRASH_PICKUP_WAIT = 1.1,
    TRASH_THROW_WAIT = 0.5,
    TRASH_TARGET_DISTANCE = 8,
    TRASH_SCAN_INTERVAL = 12.0,
    TRASH_RETRY_WAIT = 1.4,
    TRASH_RETURN_PAUSE = 0.2,
    AIM_ENABLED = false,
    AIM_CAMERA_RISE = 1.35,
    AIM_TARGET_RISE = 2.6,
    -- Approximations for Garou's normal (non-awakened) abilities.
    -- Client-side timers cannot observe authoritative server cooldowns.
    RANDOM_CD1 = 18,
    RANDOM_CD2 = 21,
    RANDOM_GAP_1_TO_2 = 3.0,
    RANDOM_POST_2 = 1.4,
    RANDOM_TARGET_RANGE = 5,
    RANDOM_SAFE_MIN_ENEMY_DISTANCE = 25,
    RANDOM_AUTOUSE = true,
}

-- ============================================================
-- GUI SETUP
-- ============================================================
local oldGui = CoreGui:FindFirstChild("GringoXPShadowTSBv15")
if oldGui then
    warn("GRINGO XP SHADOW v15 is already open. Close it before re-running.")
    return
end

local oldV14 = CoreGui:FindFirstChild("GringoXPShadowTSBv14")
local oldV13 = CoreGui:FindFirstChild("GringoXPShadowTSBv13")
local oldV12 = CoreGui:FindFirstChild("GringoXPShadowTSBv12")
local oldV11 = CoreGui:FindFirstChild("GringoXPShadowTSBv11")
local oldV10 = CoreGui:FindFirstChild("GringoXPShadowTSBv10")
local oldV9 = CoreGui:FindFirstChild("GringoXPShadowTSBv9")
local oldV8 = CoreGui:FindFirstChild("GringoXPShadowTSBv8")
if oldV14 or oldV13 or oldV12 or oldV11 or oldV10 or oldV9 or oldV8 then
    warn("Older SHADOW version is still running. Restart Roblox before running v15 to avoid conflicting teleport loops.")
    return
end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GringoXPShadowTSBv15"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 150
ScreenGui.Parent = CoreGui

local MainFrame = Instance.new("Frame")
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(480, 680)
local PANEL_W = math.max(300, math.min(474, math.floor(viewport.X - 24)))
local PANEL_H = math.max(295, math.min(520, math.floor(viewport.Y - 38)))
MainFrame.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
MainFrame.Position = UDim2.new(0.5, -PANEL_W / 2, 0.5, -PANEL_H / 2)
MainFrame.BackgroundColor3 = Color3.fromRGB(19, 22, 30)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local MainFrameCorner = Instance.new("UICorner")
MainFrameCorner.CornerRadius = UDim.new(0, 9)
MainFrameCorner.Parent = MainFrame

local MainFrameStroke = Instance.new("UIStroke")
MainFrameStroke.Color = Color3.fromRGB(24, 211, 240)
MainFrameStroke.Thickness = 1.2
MainFrameStroke.Parent = MainFrame

local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 21)
TitleBar.BackgroundColor3 = Color3.fromRGB(17, 44, 58)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleBarCorner = Instance.new("UICorner")
TitleBarCorner.CornerRadius = UDim.new(0, 4)
TitleBarCorner.Parent = TitleBar

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -48, 1, 0)
Title.BackgroundTransparency = 1
Title.Text = "◆ GRINGO XP  •  SHADOW v15"
Title.TextColor3 = Color3.fromRGB(134, 246, 255)
Title.Font = Enum.Font.SourceSansBold
Title.TextSize = 11
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Position = UDim2.new(0, 7, 0, 0)
Title.Parent = TitleBar

local CloseButton = Instance.new("TextButton")
CloseButton.Position = UDim2.new(1, -21, 0, 0)
CloseButton.Size = UDim2.new(0, 21, 0, 21)
CloseButton.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
CloseButton.BorderSizePixel = 0
CloseButton.Text = "X"
CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseButton.Font = Enum.Font.SourceSansBold
CloseButton.TextSize = 11
CloseButton.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 4)
CloseCorner.Parent = CloseButton

local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Name = "Minimize"
MinimizeButton.Position = UDim2.new(1, -42, 0, 0)
MinimizeButton.Size = UDim2.fromOffset(21, 21)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
MinimizeButton.BorderSizePixel = 0
MinimizeButton.Text = "-"
MinimizeButton.TextColor3 = Color3.new(1, 1, 1)
MinimizeButton.Font = Enum.Font.SourceSansBold
MinimizeButton.TextSize = 15
MinimizeButton.Parent = TitleBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 4)
MinCorner.Parent = MinimizeButton

local minimized = false
MinimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    MainFrame.Size = UDim2.fromOffset(PANEL_W, minimized and 21 or PANEL_H)
    MinimizeButton.Text = minimized and "+" or "-"
    for _, child in ipairs(MainFrame:GetChildren()) do
        if child:IsA("GuiObject") and child ~= TitleBar then
            child.Visible = not minimized
        end
    end
end)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Position = UDim2.new(0, 7, 0, 28)
StatusLabel.Size = UDim2.new(1, -14, 0, 18)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "TSB • choose a player"
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
SpeedInput.PlaceholderText = "8-100"
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
DistanceInput.PlaceholderText = "4-8"
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

local ThrowLabel = Instance.new("TextLabel")
ThrowLabel.Position = UDim2.fromOffset(108, 373)
ThrowLabel.Size = UDim2.fromOffset(42, 21)
ThrowLabel.Text = "THROW"
ThrowLabel.TextColor3 = Color3.new(1,1,1)
ThrowLabel.TextSize = 9
ThrowLabel.Font = Enum.Font.SourceSansBold
ThrowLabel.BackgroundTransparency = 1
ThrowLabel.Parent = MainFrame

local ThrowInput = Instance.new("TextBox")
ThrowInput.Name = "TrashThrowPower"
ThrowInput.Position = UDim2.fromOffset(151, 373)
ThrowInput.Size = UDim2.fromOffset(52, 21)
ThrowInput.Text = tostring(CONFIG.TRASH_THROW_SPEED)
ThrowInput.PlaceholderText = "30-400"
ThrowInput.ClearTextOnFocus = false
ThrowInput.TextColor3 = Color3.new(1,1,1)
ThrowInput.BackgroundColor3 = Color3.fromRGB(40,46,62)
ThrowInput.TextSize = 12
ThrowInput.Font = Enum.Font.SourceSansBold
ThrowInput.Parent = MainFrame
Instance.new("UICorner", ThrowInput).CornerRadius = UDim.new(0,4)

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
TrashInfo.Text = "TRASH: OFF • manual pickup/throw M1\nServer controls item physics and damage."
TrashInfo.Parent = MainFrame

-- Compact wide, vertically scrollable controls. Player list scrolls separately.
MainFrame.ClipsDescendants = true
Title.Text = "◆ GRINGO XP SHADOW • v15"
SelectionFrame.Position = UDim2.fromOffset(7, 49)
SelectionFrame.Size = UDim2.new(1, -14, 0, 112)
StartButton.Position = UDim2.fromOffset(7, 167)
StartButton.Size = UDim2.new(0.5, -11, 0, 27)
StopButton.Position = UDim2.new(0.5, 3, 0, 167)
StopButton.Size = UDim2.new(0.5, -10, 0, 27)

local ControlsScroll = Instance.new("ScrollingFrame")
ControlsScroll.Name = "ControlsScroll"
ControlsScroll.Position = UDim2.fromOffset(7, 274)
ControlsScroll.Size = UDim2.new(1, -14, 1, -282)
ControlsScroll.CanvasSize = UDim2.fromOffset(0, 483)
ControlsScroll.ScrollBarThickness = 5
ControlsScroll.ScrollingDirection = Enum.ScrollingDirection.Y
ControlsScroll.BackgroundColor3 = Color3.fromRGB(25, 29, 40)
ControlsScroll.BorderSizePixel = 0
ControlsScroll.Active = true
ControlsScroll.Parent = MainFrame
Instance.new("UICorner", ControlsScroll).CornerRadius = UDim.new(0, 5)

local function placeControl(obj, x, y, width, height)
    obj.Parent = ControlsScroll
    obj.Position = UDim2.fromOffset(x, y)
    obj.Size = UDim2.fromOffset(width, height or 26)
end
local FULL_W = PANEL_W - 41
local HALF_W = math.floor((FULL_W - 8) / 2)
local RIGHT_X = 7 + HALF_W + 8
local RIGHT_W = FULL_W - HALF_W - 8
placeControl(SafeToggle, 7, 8, HALF_W)
placeControl(ResetToggle, RIGHT_X, 8, RIGHT_W)
placeControl(InvisToggle, 7, 41, FULL_W)
placeControl(SpeedToggle, 7, 74, HALF_W)
placeControl(SpeedInput, RIGHT_X, 74, RIGHT_W)
placeControl(DistanceLabel, 7, 107, HALF_W)
placeControl(DistanceInput, RIGHT_X, 107, RIGHT_W)
placeControl(TpOnceButton, 7, 140, HALF_W)
placeControl(RandomTPButton, RIGHT_X, 140, RIGHT_W)
placeControl(TrashAutoButton, 7, 173, FULL_W)
placeControl(ThrowLabel, 7, 206, HALF_W)
placeControl(ThrowInput, RIGHT_X, 206, RIGHT_W)
placeControl(TrashInfo, 7, 306, FULL_W, 52)
TrashInfo.TextSize = 11

local TrashReturnButton = makeToggle("TRASH RETURN", 7, 263)
placeControl(TrashReturnButton, 7, 239, FULL_W)
TrashReturnButton.Text = "PICKUP CAN + RETURN (ONCE)"
TrashReturnButton.BackgroundColor3 = Color3.fromRGB(68, 70, 135)
TrashReturnButton.TextColor3 = Color3.new(1, 1, 1)

local AimToggle = makeToggle("AIM", 7, 263)
placeControl(AimToggle, 7, 272, FULL_W)
paintToggle(AimToggle, "AIM LOCK", false)

-- RANDOM CYCLE controls are outside the scroll for instantaneous STOP.
local AutoStartButton = makeToggle("RANDOM START", 7, 150)
AutoStartButton.Position = UDim2.fromOffset(7, 203)
AutoStartButton.Size = UDim2.fromOffset(math.floor((PANEL_W - 22) / 2), 29)
AutoStartButton.Text = "▶ RANDOM: START"
AutoStartButton.TextColor3 = Color3.new(1, 1, 1)
AutoStartButton.TextSize = 13
AutoStartButton.BackgroundColor3 = Color3.fromRGB(17, 143, 89)

local AutoStopButton = makeToggle("RANDOM STOP", 7, 150)
AutoStopButton.Position = UDim2.fromOffset(14 + math.floor((PANEL_W - 22) / 2), 203)
AutoStopButton.Size = UDim2.fromOffset(PANEL_W - 22 - math.floor((PANEL_W - 22) / 2), 29)
AutoStopButton.Text = "■ RANDOM: STOP"
AutoStopButton.TextColor3 = Color3.new(1, 1, 1)
AutoStopButton.TextSize = 13
AutoStopButton.BackgroundColor3 = Color3.fromRGB(151, 42, 54)

local AutoStatus = Instance.new("TextLabel")
AutoStatus.Name = "RandomCycleStatus"
AutoStatus.Position = UDim2.fromOffset(8, 236)
AutoStatus.Size = UDim2.new(1, -16, 0, 31)
AutoStatus.BackgroundColor3 = Color3.fromRGB(26, 49, 56)
AutoStatus.TextColor3 = Color3.fromRGB(191, 247, 246)
AutoStatus.Font = Enum.Font.SourceSansBold
AutoStatus.TextSize = 12
AutoStatus.TextWrapped = true
AutoStatus.Text = "RANDOM CYCLE: OFF | Hero Hunter 1 → 2 → Dummy"
AutoStatus.Parent = MainFrame
Instance.new("UICorner", AutoStatus).CornerRadius = UDim.new(0, 5)

local function newCycleInput(name, x, y, value, placeholder, width)
    local t = Instance.new("TextBox")
    t.Name = name
    t.Text = tostring(value)
    t.PlaceholderText = placeholder
    t.Position = UDim2.fromOffset(x, y)
    t.Size = UDim2.fromOffset(width, 30)
    t.BackgroundColor3 = Color3.fromRGB(40, 46, 62)
    t.TextColor3 = Color3.new(1, 1, 1)
    t.TextSize = 12
    t.Font = Enum.Font.SourceSansBold
    t.ClearTextOnFocus = false
    t.Parent = ControlsScroll
    Instance.new("UICorner", t).CornerRadius = UDim.new(0, 4)
    return t
end

local AutoCastToggle = makeToggle("AUTO CAST", 7, FULL_W)
placeControl(AutoCastToggle, 7, 366, FULL_W, 30)
paintToggle(AutoCastToggle, "AUTO CAST 1+2", CONFIG.RANDOM_AUTOUSE)

local SkillCD1Input = newCycleInput("Cooldown1", 7, 405, CONFIG.RANDOM_CD1, "CD 1 sec", HALF_W)
local SkillCD2Input = newCycleInput("Cooldown2", RIGHT_X, 405, CONFIG.RANDOM_CD2, "CD 2 sec", RIGHT_W)
local CDsLabel = Instance.new("TextLabel")
CDsLabel.Position = UDim2.fromOffset(7, 439)
CDsLabel.Size = UDim2.fromOffset(FULL_W, 33)
CDsLabel.BackgroundTransparency = 1
CDsLabel.TextColor3 = Color3.fromRGB(163, 192, 213)
CDsLabel.TextWrapped = true
CDsLabel.Font = Enum.Font.SourceSans
CDsLabel.TextSize = 12
CDsLabel.Text = "CD (seconds): left = skill 1, right = skill 2. Garou base moves."
CDsLabel.Parent = ControlsScroll


-- Touch-friendly circular target lock beneath the standard Roblox top-left UI.
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
local RandomCycle = {
    enabled = false, token = 0, phase = "off", target = nil,
    previousId = nil, readyAt = {[1] = 0, [2] = 0},
    firstCastAttemptAt = nil, secondCastAttemptAt = nil,
    savedOrigin = nil, cooldownNotice = ""
}
local SelectedTarget = nil
local PlayerButtons = {}
local BackstabActive = false
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
local Evading = false -- compatibility guard only; never set true in v15
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
local AimHighlight = nil
local AimRenderName = "GringoXP_AimV15"
local TrashIndex = {}
local TrashBlacklist = {}
local TrashIndexReady = false
local TrashIndexConnection = nil
local LastTrashScanAt = 0
local CachedTrash = nil
local ManualTeleportAt = -1e9
local LastPositionTick = 0
local LastRealSpeed = 0
local FollowLastCorrection = -1e9
local MoveRenderName = "GringoXP_MoveV15"

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
-- No speculative FireServer / InvokeServer calls. Server abilities are authoritative.
local function probeAndFireHideRemotes(_) end

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
        HiddenFolder.Name = "HizolonHiddenVisuals"
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
    platform.Name = "HizolonLocalSafeZone"
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
    if not Active or not CONFIG.SPEED_ENABLED or Evading or TrashBusy
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
    local blend = math.clamp(dt * 25, 0.15, CONFIG.SPEED_ACCELERATION)
    local nextVel = planar:Lerp(dir * targetSpeed, blend)
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.new(nextVel.X, vel.Y, nextVel.Z)
    end)
end

-- Client movement override after the default input pass. Never forces an
-- ability to execute; merely requests movement when keyboard input exists.
RunService:BindToRenderStep(MoveRenderName, Enum.RenderPriority.Input.Value + 2, function()
    if not Active or not CONFIG.SPEED_ENABLED or TrashBusy or Evading
       or SafeTriggered or ResetInProgress then return end
    local hum = speedHumanoid()
    if moveBlocked(hum) then return end
    local raw = intendedMove(hum)
    if raw.Magnitude > 0.06 then
        pcall(function() hum:Move(raw, false) end)
    end
end)

-- ============================================================
-- AUTO EVADE removed in v15. No animation, effect, or damage listeners trigger TP.
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
        if BackstabActive and StopBackstab then StopBackstab() end
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

function Positioner.getBehindCFrame(targetHRP)
    if not targetHRP then return nil end

    local targetCF = targetHRP.CFrame
    local targetPos = targetHRP.Position
    local targetLook = targetCF.LookVector

    local pingRaw = getPing() / 1000
    local leadTime = math.min(pingRaw * CONFIG.PING_SAFETY, CONFIG.MAX_LEAD_TIME)
    local predictedPos = targetPos
    local predictedLook = targetLook

    if CONFIG.PING_COMPENSATE then
        local vel = targetHRP.AssemblyLinearVelocity
        local predMult = math.clamp(CONFIG.PREDICTION_MULT, 0.5, 1.5)
        local flatVel = Vector3.new(vel.X, 0, vel.Z)
        if flatVel.Magnitude > 55 then flatVel = flatVel.Unit * 55 end
        predictedPos = targetPos + flatVel * leadTime * predMult

        local angVel = targetHRP.AssemblyAngularVelocity
        if angVel.Magnitude > 0.1 then
            local angle = angVel.Magnitude * leadTime * predMult
            angle = math.clamp(angle, -math.pi / 2, math.pi / 2)
            local axis = angVel.Unit
            local rotDelta = CFrame.fromAxisAngle(axis, angle)
            predictedLook = (rotDelta * targetLook).Unit
        end
        -- Keep vertical placement stable on ragdolls; no double Y prediction.
    end

    local flatLook = Vector3.new(predictedLook.X, 0, predictedLook.Z)
    if flatLook.Magnitude < 0.05 then flatLook = Vector3.new(0, 0, -1) end
    local behindPos = predictedPos - flatLook.Unit * CONFIG.BEHIND_STUDS
    behindPos = behindPos + Vector3.new(0, CONFIG.HEIGHT_OFFSET, 0)

    local facePos = Vector3.new(predictedPos.X, behindPos.Y, predictedPos.Z)
    if (facePos - behindPos).Magnitude < 0.01 then
        return CFrame.new(behindPos)
    end
    return CFrame.lookAt(behindPos, facePos)
end

-- Only rotate the avatar, not CurrentCamera: abilities and mouse-look stay free.
function Positioner.faceTarget(targetRoot)
    local root, hum = getHRP(Player), speedHumanoid()
    if not root or not targetRoot or moveBlocked(hum) or root.Anchored then return end
    local pos = root.Position
    local at = Vector3.new(targetRoot.Position.X, pos.Y, targetRoot.Position.Z)
    local delta = at - pos
    if delta.Magnitude < 0.4 then return end
    local facing = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
    local dot = facing.Magnitude > 0.01 and facing.Unit:Dot(delta.Unit) or 0
    if dot > 0.987 then return end  -- avoid tiny frame-to-frame rotation changes
    pcall(function() root.CFrame = CFrame.lookAt(pos, at) end)
end

function Positioner.teleport(force)
    if not Active or Evading or TrashBusy or ResetInProgress or SafeTriggered
        or not SelectedTarget or not isAlive(SelectedTarget) then return false end
    local targetRoot = getHRP(SelectedTarget)
    local root = getHRP(Player)
    local char = Player.Character
    local hum = speedHumanoid()
    if not targetRoot or not root or not char or moveBlocked(hum) then return false end
    local targetCFrame = Positioner.getBehindCFrame(targetRoot)
    if not targetCFrame then return false end
    local gap = (root.Position - targetCFrame.Position).Magnitude

    if not force then
        -- Manual WASD/mobile movement gets priority over follow teleports.
        -- This keeps attacking, movement and camera control usable together.
        local input = intendedMove(hum)
        if input.Magnitude > 0.09 and gap <= CONFIG.FOLLOW_MANUAL_LEASH then
            Positioner.faceTarget(targetRoot)
            return true
        end
        if gap <= CONFIG.POSITION_TOLERANCE then
            Positioner.faceTarget(targetRoot)
            return true
        end
        if gap < CONFIG.FOLLOW_HARD_SNAP_DISTANCE and
           os.clock() - FollowLastCorrection < CONFIG.FOLLOW_CORRECTION_COOLDOWN then
            Positioner.faceTarget(targetRoot)
            return true
        end
    end

    local ok = pcall(function()
        char:PivotTo(targetCFrame)
        -- Never reset velocity every follow step: this causes shaky camera and
        -- prevents ability movement / dashes. Only hard start may stop drift.
        if force then
            local vel = root.AssemblyLinearVelocity
            root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
        end
    end)
    if ok then FollowLastCorrection = os.clock() end
    return ok
end

local function teleportToOpponent(opponent, distance)
    if not Active or TrashBusy or Evading or SafeTriggered or ResetInProgress then return false end
    local char = Player.Character
    local root = getHRP(Player)
    local targetRoot = getHRP(opponent)
    if not char or not root or not targetRoot or not isAlive(opponent) then return false end
    local old = CONFIG.BEHIND_STUDS
    CONFIG.BEHIND_STUDS = distance or old
    local dst = Positioner.getBehindCFrame(targetRoot)
    CONFIG.BEHIND_STUDS = old
    if not dst then return false end
    return pcall(function()
        char:PivotTo(dst)
        root.AssemblyLinearVelocity = Vector3.zero
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
            StatusLabel.Text = "Backstabbing: " .. SelectedTarget.Name
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        else
            StatusLabel.Text = "No target selected"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    else
        if SelectedTarget then
            StatusLabel.Text = "Target: " .. SelectedTarget.Name
            StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            StatusLabel.Text = "TSB • choose a player"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end
end

-- ============================================================
-- PLAYER LIST
-- ============================================================
local function RefreshPlayerList()
    for _, child in pairs(PlayerScrollFrame:GetChildren()) do
        child:Destroy()
    end
    PlayerButtons = {}
    local PlayerList = Players:GetPlayers()
    table.sort(PlayerList, function(a, b) return a.Name:lower() < b.Name:lower() end)
    local yPosition = 4
    for _, player in ipairs(PlayerList) do
        if player ~= Player then
            local PlayerEntry = Instance.new("Frame")
            PlayerEntry.Size = UDim2.new(1, -7, 0, 21)
            PlayerEntry.Position = UDim2.new(0, 4, 0, yPosition)
            PlayerEntry.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
            PlayerEntry.BorderSizePixel = 0
            PlayerEntry.Parent = PlayerScrollFrame

            local EntryCorner = Instance.new("UICorner")
            EntryCorner.CornerRadius = UDim.new(0, 4)
            EntryCorner.Parent = PlayerEntry

            local Checkbox = Instance.new("TextButton")
            Checkbox.Size = UDim2.new(0, 17, 0, 17)
            Checkbox.Position = UDim2.new(0, 2, 0.5, -8)
            Checkbox.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
            Checkbox.BorderSizePixel = 0
            Checkbox.Text = ""
            Checkbox.Parent = PlayerEntry

            local CheckCorner = Instance.new("UICorner")
            CheckCorner.CornerRadius = UDim.new(0, 3)
            CheckCorner.Parent = Checkbox

            local Checkmark = Instance.new("TextLabel")
            Checkmark.Size = UDim2.new(1, 0, 1, 0)
            Checkmark.BackgroundTransparency = 1
            Checkmark.Text = "✓"
            Checkmark.TextColor3 = Color3.fromRGB(0, 255, 0)
            Checkmark.TextSize = 12
            Checkmark.Font = Enum.Font.SourceSansBold
            Checkmark.Visible = (SelectedTarget == player)
            Checkmark.Parent = Checkbox

            -- DisplayName (nickname) first, then immutable @username.
            -- Both labels truncate instead of overflowing on small screens.
            local NameLabel = Instance.new("TextLabel")
            NameLabel.Size = UDim2.new(0.48, -11, 1, 0)
            NameLabel.Position = UDim2.new(0, 24, 0, 0)
            NameLabel.BackgroundTransparency = 1
            NameLabel.Text = tostring(player.DisplayName)
            NameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
            NameLabel.TextSize = 11
            NameLabel.Font = Enum.Font.SourceSansBold
            NameLabel.TextXAlignment = Enum.TextXAlignment.Left
            NameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            NameLabel.Parent = PlayerEntry

            local UsernameLabel = Instance.new("TextLabel")
            UsernameLabel.Name = "Username"
            UsernameLabel.Size = UDim2.new(0.52, -29, 1, 0)
            UsernameLabel.Position = UDim2.new(0.48, 12, 0, 0)
            UsernameLabel.BackgroundTransparency = 1
            UsernameLabel.Text = "@" .. tostring(player.Name)
            UsernameLabel.TextColor3 = Color3.fromRGB(160, 204, 222)
            UsernameLabel.TextSize = 10
            UsernameLabel.Font = Enum.Font.SourceSans
            UsernameLabel.TextXAlignment = Enum.TextXAlignment.Left
            UsernameLabel.TextTruncate = Enum.TextTruncate.AtEnd
            UsernameLabel.Parent = PlayerEntry

            local Avatar = Instance.new("ImageLabel")
            Avatar.Name = "PlayerAvatar"
            Avatar.Size = UDim2.fromOffset(18, 18)
            Avatar.Position = UDim2.new(1, -21, 0.5, -9)
            Avatar.BackgroundColor3 = Color3.fromRGB(28, 44, 60)
            Avatar.BorderSizePixel = 0
            Avatar.ScaleType = Enum.ScaleType.Crop
            Avatar.Parent = PlayerEntry

            local AvatarCorner = Instance.new("UICorner")
            AvatarCorner.CornerRadius = UDim.new(1, 0)
            AvatarCorner.Parent = Avatar

            task.spawn(function()
                local ok, url = pcall(function()
                    return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
                end)
                if ok and Avatar.Parent then Avatar.Image = url end
            end)

            local ClickArea = Instance.new("TextButton")
            ClickArea.Size = UDim2.new(1, 0, 1, 0)
            ClickArea.BackgroundTransparency = 1
            ClickArea.Text = ""
            ClickArea.ZIndex = 2
            ClickArea.Parent = PlayerEntry

            ClickArea.MouseButton1Click:Connect(function()
                -- Selection must never wait for a follower tick or a UI refresh.
                if StopRandomCycle then StopRandomCycle(true) end
                if BackstabActive and StopBackstab then StopBackstab() end
                if SelectedTarget == player then
                    SelectedTarget = nil
                    Checkmark.Visible = false
                    UpdateStatus()
                    return
                end
                SelectedTarget = player
                for _, data in pairs(PlayerButtons) do
                    data.Checkmark.Visible = false
                end
                Checkmark.Visible = true
                -- The TP attempt happens synchronously on click, no task.wait.
                local success = teleportToOpponent(player, CONFIG.BEHIND_STUDS)
                UpdateStatus()
                StatusLabel.Text = success
                    and ("INSTANT TP attempted: " .. player.Name)
                    or ("TARGET SELECTED; TP unavailable: " .. player.Name)
            end)

            PlayerButtons[player.Name] = {
                Entry = PlayerEntry,
                Checkmark = Checkmark
            }
            yPosition = yPosition + 25
        end
    end
    PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, yPosition + 4)
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

local function tryTrashImpulse(item, enemy)
    local part = trashRoot(item)
    local target = getHRP(enemy)
    if not part or not target or part.Anchored then return false end
    if trashCarried(item) then return false end -- don't fling the held object
    local offset = target.Position - part.Position
    if offset.Magnitude < 0.1 then return false end
    local requested = CONFIG.TRASH_THROW_SPEED
    return pcall(function()
        -- A client-owned loose projectile may accept this velocity; server-owned
        -- trash often overrides it. No fabricated server remotes are invoked.
        part.AssemblyLinearVelocity = offset.Unit * requested
            + Vector3.new(0, math.clamp(requested * 0.10, 9, 35), 0)
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
                                    tryTrashImpulse(item, enemy)  -- server may reject impulse
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
            TrashReturnButton.Text = "PICKUP CAN + RETURN (ONCE)"
            trashStatus(ok and msg or "pickup error")
        end
    end)
end

-- ============================================================
-- AIM v14: lock ONE manually acquired player, no automatic retargeting.
-- Local camera control + outline-only highlight.
-- ============================================================
local function clearAimTarget()
    AimTarget = nil
    if AimHighlight then
        pcall(function() AimHighlight:Destroy() end)
        AimHighlight = nil
    end
    AimHud.BackgroundColor3 = Color3.fromRGB(91, 96, 107)
    AimHudStroke.Color = Color3.fromRGB(176, 183, 197)
    AimHud.Text = "◎"
end

local function acquireAimTarget()
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local size = camera.ViewportSize
    local mid = size * 0.5
    local best, bestPixels = nil, math.min(size.X, size.Y) * 0.22
    for _, enemy in ipairs(Players:GetPlayers()) do
        if enemy ~= Player and isAlive(enemy) then
            local root = getHRP(enemy)
            if root then
                local screenPoint, onscreen = camera:WorldToViewportPoint(root.Position)
                if onscreen and screenPoint.Z > 0 then
                    local pixels = (Vector2.new(screenPoint.X, screenPoint.Y) - mid).Magnitude
                    if pixels < bestPixels then best, bestPixels = enemy, pixels end
                end
            end
        end
    end
    if not best then return false end
    clearAimTarget()
    AimTarget = best
    local char = best.Character
    if char then
        local outline = Instance.new("Highlight")
        outline.Name = "ShadowV15AimOutline"
        outline.Adornee = char
        outline.FillTransparency = 1
        outline.OutlineTransparency = 0.06
        outline.OutlineColor = Color3.fromRGB(108, 236, 255)
        outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        outline.Parent = workspace.CurrentCamera
        AimHighlight = outline
    end
    AimHud.BackgroundColor3 = Color3.fromRGB(21, 130, 112)
    AimHudStroke.Color = Color3.fromRGB(108, 236, 255)
    AimHud.Text = "●"
    return true
end

local function updateAim()
    if not Active or not CONFIG.AIM_ENABLED then return end
    if not AimTarget then return end
    if not isAlive(AimTarget) then
        clearAimTarget()
        return
    end
    local cam = workspace.CurrentCamera
    local targetRoot = getHRP(AimTarget)
    if not cam or not targetRoot then return end
    if not AimHighlight or AimHighlight.Adornee ~= AimTarget.Character then
        local saved = AimTarget
        clearAimTarget()
        AimTarget = saved
        local outline = Instance.new("Highlight")
        outline.Name = "ShadowV15AimOutline"
        outline.Adornee = saved.Character
        outline.FillTransparency = 1
        outline.OutlineTransparency = 0.06
        outline.OutlineColor = Color3.fromRGB(108, 236, 255)
        outline.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        outline.Parent = cam
        AimHighlight = outline
    end
    local char = AimTarget.Character
    local head = char and char:FindFirstChild("Head")
    local focus = (head and head:IsA("BasePart") and head.Position or targetRoot.Position)
        + Vector3.new(0, head and 0.65 or CONFIG.AIM_TARGET_RISE, 0)
    local origin = cam.CFrame.Position
    -- Default Roblox camera writes at priority 200. We execute at 201,
    -- so our optional vertical offset does not accumulate frame-to-frame.
    if cam.CameraType ~= Enum.CameraType.Scriptable then
        origin = origin + Vector3.new(0, CONFIG.AIM_CAMERA_RISE, 0)
    end
    if (focus - origin).Magnitude > 0.1 then
        cam.CFrame = CFrame.lookAt(origin, focus) -- zero interpolation/lag
    end
end

local function setAimEnabled(enabled)
    CONFIG.AIM_ENABLED = enabled
    AimHud.Visible = enabled
    paintToggle(AimToggle, "AIM LOCK", enabled)
    clearAimTarget()
    if enabled then
        if not acquireAimTarget() then
            StatusLabel.Text = "AIM: aim at a player, tap circle under Roblox"
        end
    else
        StatusLabel.Text = "AIM OFF"
    end
end

AimToggle.MouseButton1Click:Connect(function()
    setAimEnabled(not CONFIG.AIM_ENABLED)
end)
AimHud.MouseButton1Click:Connect(function()
    if not CONFIG.AIM_ENABLED or os.clock() < aimSuppressClickUntil then return end
    -- Keep current lock until the player explicitly taps the circle.
    if AimTarget then
        clearAimTarget()
        StatusLabel.Text = "AIM: unlocked; look at target and tap again"
    elseif acquireAimTarget() then
        StatusLabel.Text = "AIM locked: " .. AimTarget.Name
    else
        StatusLabel.Text = "AIM: no player in center of screen"
    end
end)
RunService:BindToRenderStep(AimRenderName, Enum.RenderPriority.Camera.Value + 1, updateAim)

-- ============================================================
-- START / STOP
-- ============================================================
local function StartBackstab()
    if BackstabActive then
        Positioner.teleport(true)
        return
    end
    if not SelectedTarget then
        StatusLabel.Text = "No target selected!"
        return
    end
    if not isAlive(SelectedTarget) or not getHRP(SelectedTarget) then
        StatusLabel.Text = "Target is not ready"
        return
    end

    -- Execute the first teleport immediately on START, before notifications
    -- or other potentially expensive appearance work.
    if StopRandomCycle then StopRandomCycle(false) end
    local firstTeleportOk = Positioner.teleport(true)
    if not firstTeleportOk then
        StatusLabel.Text = "TP not available: check character/target"
        return
    end
    BackstabActive = true
    local myHum = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
    if myHum then
        PreviousAutoRotate = myHum.AutoRotate
        myHum.AutoRotate = false
    end

    UpdateStatus()
    Message("GRINGO XP SHADOW TSB", "Backstabbing " .. SelectedTarget.Name, 2)

    if CONFIG.SAFE_ZONE and SafeTriggered then
        removeSafeZone(false)
        CONFIG.SAFE_ZONE = false
        paintToggle(SafeToggle, "SAVE ZONA", false)
    end

    if CONFIG.INVISIBLE then
        Invisibility.apply()
    end

    LastPositionTick = os.clock()
    PositionConnection = RunService.Heartbeat:Connect(function()
        if not Active or not BackstabActive then return end
        -- The target must stay alive. Never silently attach to respawn.
        if not SelectedTarget or not isAlive(SelectedTarget) or not getHRP(SelectedTarget) then
            StopBackstab()
            StatusLabel.Text = "TARGET DEAD / LEFT — press START for a new target"
            return
        end
        local now = os.clock()
        if now - LastPositionTick < CONFIG.POSITION_UPDATE_INTERVAL then return end
        LastPositionTick = now
        pcall(Positioner.teleport, false)
    end)
end

StopBackstab = function()
    if not BackstabActive then return end
    BackstabActive = false
    if PositionConnection then
        PositionConnection:Disconnect()
        PositionConnection = nil
    end
    if not CONFIG.INVISIBLE then
        Invisibility.remove()
    end
    local myHum = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
    if myHum and PreviousAutoRotate ~= nil then
        myHum.AutoRotate = PreviousAutoRotate
    end
    PreviousAutoRotate = nil
    UpdateStatus()
    Message("GRINGO XP SHADOW TSB", "Backstab stopped", 2)
end

-- ============================================================
-- ============================================================
-- RANDOM GAROU CYCLE v15: targeting -> skill 1 -> skill 2 ->
-- safe waiting point near map center Dummy -> cooldown -> repeat.
-- Only ordinary local skill input is attempted (no invented server remotes).
-- Server may reject teleports and skill activation; cooldowns are estimates.
-- ============================================================
local function setRandomStatus(message)
    if not Active or not AutoStatus.Parent then return end
    AutoStatus.Text = "RANDOM CYCLE: " .. tostring(message)
end

local function cycleValid(token)
    return Active and RandomCycle.enabled and RandomCycle.token == token
end

local function cycleWait(token, duration)
    local untilTime = os.clock() + math.max(0, duration)
    while cycleValid(token) and os.clock() < untilTime do
        task.wait(math.min(0.12, untilTime - os.clock()))
    end
    return cycleValid(token)
end

local function chooseCycleTarget()
    local all, fresh = {}, {}
    for _, candidate in ipairs(Players:GetPlayers()) do
        if candidate ~= Player and isAlive(candidate) and getHRP(candidate) then
            table.insert(all, candidate)
            if candidate.UserId ~= RandomCycle.previousId then
                table.insert(fresh, candidate)
            end
        end
    end
    local pool = (#fresh > 0) and fresh or all
    if #pool == 0 then return nil end
    return pool[math.random(1, #pool)]
end

local function flatDistance(a, b)
    return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- Find the central Dummy dynamically. No hardcoded coordinates, since the
-- arena can change. The center is a *waiting point*, not invulnerability.
local cachedDummy, cachedDummyAt = nil, -math.huge
local function centralDummyPosition()
    if os.clock() - cachedDummyAt < 12 then return cachedDummy end
    local bestPosition, bestXZ = nil, math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") and string.find(string.lower(obj.Name), "dummy", 1, true)
            and not Players:GetPlayerFromCharacter(obj) then
            local part = obj:FindFirstChild("HumanoidRootPart") or obj.PrimaryPart
            if not part then part = obj:FindFirstChildWhichIsA("BasePart") end
            if part then
                local p = part.Position
                local d = math.sqrt(p.X * p.X + p.Z * p.Z)
                if d < bestXZ then bestXZ, bestPosition = d, p end
            end
        end
    end
    cachedDummy, cachedDummyAt = bestPosition, os.clock()
    return bestPosition
end

local function findGroundedRestPoint()
    local char = Player.Character
    local charRoot = getHRP(Player)
    if not char or not charRoot then return nil end
    local center = centralDummyPosition()
    if not center then
        -- Fallback is user's origin; never blindly teleport to 0,0,0.
        local old = RandomCycle.savedOrigin
        center = old and old.Position or charRoot.Position
    end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char}
    params.IgnoreWater = true

    local best, bestScore = nil, -math.huge
    -- Test several rings around dummy to avoid collision with it and enemies.
    for _, radius in ipairs({25, 36, 48, 62}) do
        for j = 0, 7 do
            local angle = j * math.pi / 4
            local x, z = center.X + radius * math.cos(angle), center.Z + radius * math.sin(angle)
            local hit = workspace:Raycast(Vector3.new(x, center.Y + 85, z), Vector3.new(0, -190, 0), params)
            if hit and hit.Normal.Y > 0.67 and hit.Instance.CanCollide then
                local pos = Vector3.new(x, hit.Position.Y + 3.8, z)
                local nearest = math.huge
                for _, enemy in ipairs(Players:GetPlayers()) do
                    if enemy ~= Player and isAlive(enemy) then
                        local eRoot = getHRP(enemy)
                        if eRoot then nearest = math.min(nearest, flatDistance(pos, eRoot.Position)) end
                    end
                end
                local score = math.min(nearest, 100) - radius * 0.15
                if nearest >= CONFIG.RANDOM_SAFE_MIN_ENEMY_DISTANCE and score > bestScore then
                    best, bestScore = pos, score
                end
            end
        end
    end
    return best
end

local function retreatToCenter()
    local char = Player.Character
    local root = getHRP(Player)
    if not char or not root or not isAlive(Player) or root.Anchored then return false, "no character" end
    local pos = findGroundedRestPoint()
    if not pos then return false, "no safe ground found" end
    local look = root.CFrame.LookVector
    local forward = Vector3.new(look.X, 0, look.Z)
    if forward.Magnitude < 0.1 then forward = Vector3.new(0, 0, -1) end
    local ok = pcall(function()
        char:PivotTo(CFrame.lookAt(pos, pos + forward.Unit))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    return ok, ok and "attempted" or "local TP failed"
end

-- Skill buttons in live TSB are controlled by the game; simulated key events
-- and Tool activation are best-effort on Android / Delta. Never fire guessed
-- RemoteEvents, claim server acceptance, or bypass actual cooldowns.
local function tapMobileSkill(slot)
    local ui = Player:FindFirstChildOfClass("PlayerGui")
    if not ui then return false end
    local expected = (slot == 1) and "flowing water" or "lethal whirlwind stream"
    for _, item in ipairs(ui:GetDescendants()) do
        if item:IsA("TextLabel") or item:IsA("TextButton") then
            local name = string.lower(tostring(item.Text or ""))
            if string.find(name, expected, 1, true) then
                local node, visible = item, true
                while node and node ~= ui do
                    if node:IsA("GuiObject") and not node.Visible then
                        visible = false
                        break
                    end
                    if node:IsA("ScreenGui") and not node.Enabled then
                        visible = false
                        break
                    end
                    node = node.Parent
                end
                if visible and item.AbsoluteSize.X > 5 and item.AbsoluteSize.Y > 5 then
                    local center = item.AbsolutePosition + item.AbsoluteSize * 0.5
                    local x, y = math.floor(center.X), math.floor(center.Y)
                    local ok = pcall(function()
                        VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
                        task.wait(0.065)
                        VirtualInputManager:SendMouseButtonEvent(x, y, 0, false, game, 0)
                    end)
                    if ok then return true end
                end
            end
        end
    end
    return false
end

local function attemptSkill(slot)
    if not isAlive(Player) then return false end
    if UserInputService.TouchEnabled and tapMobileSkill(slot) then return true end
    local key = (slot == 1) and Enum.KeyCode.One or Enum.KeyCode.Two
    local keySucceeded = false
    local downOk = pcall(function()
        VirtualInputManager:SendKeyEvent(true, key, false, game)
    end)
    if downOk then
        task.wait(0.07)
        keySucceeded = pcall(function()
            VirtualInputManager:SendKeyEvent(false, key, false, game)
        end)
    end
    if keySucceeded then return true end

    -- Some games represent moves as Tools instead of keyboard bindings.
    local char = Player.Character
    local bag = Player:FindFirstChildOfClass("Backpack")
    local expected = (slot == 1) and "flowing water" or "lethal whirlwind stream"
    local tool = nil
    for _, parent in ipairs({char, bag}) do
        if parent then
            for _, child in ipairs(parent:GetChildren()) do
                if child:IsA("Tool") and
                    (string.lower(child.Name) == expected or child.Name == tostring(slot)) then
                    tool = child
                    break
                end
            end
        end
        if tool then break end
    end
    if tool then
        return pcall(function()
            if tool.Parent ~= char then
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if hum then hum:EquipTool(tool) end
            end
            tool:Activate()
        end)
    end
    return false
end

StopRandomCycle = function(updateStatus)
    if RandomCycle.enabled then
        RandomCycle.enabled = false
        RandomCycle.token = RandomCycle.token + 1
    end
    RandomCycle.phase = "off"
    RandomCycle.target = nil
    AutoStartButton.BackgroundColor3 = Color3.fromRGB(17, 143, 89)
    AutoStopButton.BackgroundColor3 = Color3.fromRGB(151, 42, 54)
    if updateStatus ~= false then setRandomStatus("STOPPED") end
end

StartRandomCycle = function()
    if RandomCycle.enabled or not Active then return end
    if not isAlive(Player) or not getHRP(Player) then
        setRandomStatus("character unavailable")
        return
    end
    -- No two separate features may fight over character CFrame.
    if BackstabActive and StopBackstab then StopBackstab() end
    if TrashAutoEnabled or TrashBusy then
        setRandomStatus("stop TRASH AUTO and wait for pickup first")
        return
    end
    if SafeTriggered then
        setRandomStatus("disable active SAFE ZONA first")
        return
    end
    if CONFIG.SAFE_ZONE then
        CONFIG.SAFE_ZONE = false
        paintToggle(SafeToggle, "SAVE ZONA", false)
    end

    RandomCycle.savedOrigin = getHRP(Player).CFrame
    RandomCycle.enabled = true
    RandomCycle.token = RandomCycle.token + 1
    local token = RandomCycle.token
    RandomCycle.previousId = nil
    RandomCycle.readyAt = {[1] = 0, [2] = 0}
    RandomCycle.phase = "starting"
    AutoStartButton.BackgroundColor3 = Color3.fromRGB(12, 96, 73)
    AutoStopButton.BackgroundColor3 = Color3.fromRGB(190, 39, 48)
    setRandomStatus("STARTING | 1 → 2 → central Dummy")

    task.spawn(function()
        while cycleValid(token) do
            if not isAlive(Player) or not getHRP(Player) then
                setRandomStatus("respawn needed; stopped")
                StopRandomCycle(false)
                break
            end
            local nextReady = math.max(RandomCycle.readyAt[1], RandomCycle.readyAt[2])
            local seconds = math.max(0, nextReady - os.clock())
            if seconds > 0 then
                RandomCycle.phase = "cooldown"
                setRandomStatus("CD 1+2: " .. math.ceil(seconds) .. "s | waiting by Dummy")
                if not cycleWait(token, math.min(seconds, 0.75)) then break end
            else
                local opponent = chooseCycleTarget()
                if not opponent then
                    RandomCycle.phase = "no target"
                    setRandomStatus("No live players; waiting")
                    if not cycleWait(token, 1.0) then break end
                else
                    RandomCycle.phase = "target"
                    RandomCycle.target = opponent
                    RandomCycle.previousId = opponent.UserId
                    setRandomStatus("TP → @" .. opponent.Name)
                    local moved = teleportToOpponent(opponent, CONFIG.RANDOM_TARGET_RANGE)
                    if not moved then
                        setRandomStatus("TP attempt unavailable; next target")
                        if not cycleWait(token, 0.55) then break end
                    else
                        if not cycleWait(token, 0.18) then break end
                        if not isAlive(opponent) then
                            setRandomStatus("Target unavailable; next")
                        else
                            RandomCycle.phase = "skill 1"
                            local a = CONFIG.RANDOM_AUTOUSE and attemptSkill(1)
                            if not cycleValid(token) then break end
                            if CONFIG.RANDOM_AUTOUSE and not a then
                                setRandomStatus("Skill 1 input unavailable on Delta; STOP")
                                StopRandomCycle(false)
                                break
                            end
                            RandomCycle.readyAt[1] = os.clock() + CONFIG.RANDOM_CD1
                            setRandomStatus(CONFIG.RANDOM_AUTOUSE and "Skill 1 sent; waiting for 2" or "Use skill 1 manually")
                            if not cycleWait(token, CONFIG.RANDOM_GAP_1_TO_2) then break end
                            RandomCycle.phase = "skill 2"
                            -- Skill 1 may have moved both fighters; re-aim before skill 2.
                            if not isAlive(Player) then break end
                            if isAlive(opponent) then
                                teleportToOpponent(opponent, CONFIG.RANDOM_TARGET_RANGE)
                            end
                            local b = CONFIG.RANDOM_AUTOUSE and attemptSkill(2)
                            if not cycleValid(token) then break end
                            if CONFIG.RANDOM_AUTOUSE and not b then
                                setRandomStatus("Skill 2 input unavailable on Delta; STOP")
                                StopRandomCycle(false)
                                break
                            end
                            RandomCycle.readyAt[2] = os.clock() + CONFIG.RANDOM_CD2
                            setRandomStatus(CONFIG.RANDOM_AUTOUSE and "Skill 2 sent → retreat" or "Use skill 2 manually")
                            if not cycleWait(token, CONFIG.RANDOM_POST_2) then break end
                            RandomCycle.phase = "retreat"
                            local safeOK, reason = retreatToCenter()
                            setRandomStatus(safeOK and "TP to Dummy area attempted; cooldown" or
                                ("Retreat unavailable: " .. reason))
                            if not cycleWait(token, 0.3) then break end
                        end
                    end
                end
            end
        end
        if Active and not RandomCycle.enabled then
            AutoStartButton.BackgroundColor3 = Color3.fromRGB(17, 143, 89)
        end
    end)
end

AutoStartButton.MouseButton1Click:Connect(StartRandomCycle)
AutoStopButton.MouseButton1Click:Connect(function() StopRandomCycle(true) end)
AutoCastToggle.MouseButton1Click:Connect(function()
    CONFIG.RANDOM_AUTOUSE = not CONFIG.RANDOM_AUTOUSE
    paintToggle(AutoCastToggle, "AUTO CAST 1+2", CONFIG.RANDOM_AUTOUSE)
    if not RandomCycle.enabled then
        setRandomStatus(CONFIG.RANDOM_AUTOUSE and "automatic skill input ON" or
            "manual skills mode (uses approximate timers)")
    end
end)
for slot, input in ipairs({SkillCD1Input, SkillCD2Input}) do
    input.FocusLost:Connect(function()
        local value = tonumber(input.Text)
        if value and value == value and value > 0 and value < 300 then
            value = math.clamp(math.floor(value + 0.5), 5, 90)
            if slot == 1 then CONFIG.RANDOM_CD1 = value else CONFIG.RANDOM_CD2 = value end
        end
        input.Text = tostring(slot == 1 and CONFIG.RANDOM_CD1 or CONFIG.RANDOM_CD2)
    end)
end

-- BUTTON CONNECTIONS
-- ============================================================
-- Speed input applies only on focus loss; avoids per-keystroke writes.
SpeedInput.FocusLost:Connect(function()
    local value = tonumber(SpeedInput.Text)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        SpeedInput.Text = tostring(CONFIG.SPEED_VALUE)
        return
    end
    CONFIG.SPEED_VALUE = math.clamp(math.floor(value + 0.5), 8, 100)
    SpeedInput.Text = tostring(CONFIG.SPEED_VALUE)
    refreshSpeed()
end)

SpeedToggle.MouseButton1Click:Connect(function()
    CONFIG.SPEED_ENABLED = not CONFIG.SPEED_ENABLED
    paintToggle(SpeedToggle, "SPEED", CONFIG.SPEED_ENABLED)
    if CONFIG.SPEED_ENABLED then
        refreshSpeed()
    else
        releaseSpeed()
    end
end)

DistanceInput.FocusLost:Connect(function()
    local value = tonumber(DistanceInput.Text)
    if not value or value ~= value or value == math.huge or value == -math.huge then
        DistanceInput.Text = tostring(CONFIG.BEHIND_STUDS)
        return
    end
    CONFIG.BEHIND_STUDS = math.clamp(math.floor(value + 0.5), 4, 8)
    DistanceInput.Text = tostring(CONFIG.BEHIND_STUDS)
end)

TpOnceButton.MouseButton1Click:Connect(function()
    if StopRandomCycle then StopRandomCycle(false) end
    if not SelectedTarget then
        StatusLabel.Text = "Select a player first"
        return
    end
    local ok = Positioner.teleport(true)
    StatusLabel.Text = ok and ("TP attempted: " .. SelectedTarget.Name) or "TP failed: unavailable"
end)

RandomTPButton.MouseButton1Click:Connect(function()
    if StopRandomCycle then StopRandomCycle(false) end
    local other = chooseRandomOpponent()
    if not other then
        StatusLabel.Text = "No alive players for random TP"
        return
    end
    SelectedTarget = other
    RefreshPlayerList()
    local ok = teleportToOpponent(other, CONFIG.BEHIND_STUDS)
    StatusLabel.Text = ok and ("Random TP attempted: " .. other.Name) or "Random TP failed"
end)

ThrowInput.FocusLost:Connect(function()
    local x = tonumber(ThrowInput.Text)
    if x and x == x and x ~= math.huge and x ~= -math.huge then
        CONFIG.TRASH_THROW_SPEED = math.clamp(math.floor(x + 0.5), 30, 400)
    end
    ThrowInput.Text = tostring(CONFIG.TRASH_THROW_SPEED)
end)

TrashAutoButton.MouseButton1Click:Connect(function()
    if StopRandomCycle then StopRandomCycle(true) end
    trashCycle()
end)
TrashReturnButton.MouseButton1Click:Connect(function()
    if StopRandomCycle then StopRandomCycle(true) end
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


StartButton.MouseButton1Click:Connect(StartBackstab)
StopButton.MouseButton1Click:Connect(StopBackstab)

SafeToggle.MouseButton1Click:Connect(function()
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

InvisToggle.MouseButton1Click:Connect(function()
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

ResetToggle.MouseButton1Click:Connect(function()
    CONFIG.AUTO_RESET = not CONFIG.AUTO_RESET
    paintToggle(ResetToggle, "AUTO RESET", CONFIG.AUTO_RESET)
    StatusLabel.Text = CONFIG.AUTO_RESET
        and "AUTO RESET armed • corpse vanishes on death"
        or "AUTO RESET disabled"
    StatusLabel.TextColor3 = CONFIG.AUTO_RESET
        and Color3.fromRGB(120, 245, 195)
        or Color3.fromRGB(220, 225, 240)
end)

CloseButton.MouseButton1Click:Connect(function()
    if StopRandomCycle then StopRandomCycle(false) end
    Active = false
    stopTrash()
    setAimEnabled(false)
    pcall(function() RunService:UnbindFromRenderStep(AimRenderName) end)
    pcall(function() RunService:UnbindFromRenderStep(MoveRenderName) end)
    if TrashIndexConnection then TrashIndexConnection:Disconnect() end
    CONFIG.SPEED_ENABLED = false
    releaseSpeed()
    if SpeedLoopConnection then SpeedLoopConnection:Disconnect(); SpeedLoopConnection = nil end
    StopBackstab()
    removeSafeZone(true)
    Invisibility.remove()
    CONFIG.INVISIBLE = false
    if HealthConnection then HealthConnection:Disconnect() end
    if DeathConnection then DeathConnection:Disconnect() end
    if CharacterConnection then CharacterConnection:Disconnect() end
    if DescendantConnection then DescendantConnection:Disconnect() end
    if InvisHardConnection then InvisHardConnection:Disconnect() end
    for _, conn in ipairs(CleanupConnections) do
        conn:Disconnect()
    end
    if HiddenFolder then pcall(function() HiddenFolder:Destroy() end) end
    ScreenGui:Destroy()
end)

-- ============================================================
-- PLAYER JOIN / LEAVE
-- ============================================================
table.insert(CleanupConnections, Players.PlayerAdded:Connect(function(newPlayer)
    RefreshPlayerList()
end))

table.insert(CleanupConnections, Players.PlayerRemoving:Connect(function(player)
    if RandomCycle.target == player then RandomCycle.target = nil end
    if AimTarget == player then clearAimTarget() end
    if SelectedTarget == player then
        if BackstabActive and StopBackstab then StopBackstab() end
        SelectedTarget = nil
    end
    task.wait(0.1)
    RefreshPlayerList()
    UpdateStatus()
end))

-- ============================================================
-- RESPAWN
-- ============================================================
CharacterConnection = Player.CharacterAdded:Connect(function(character)
    if StopRandomCycle then StopRandomCycle(false) end
    if BackstabActive and StopBackstab then StopBackstab() end
    -- Keep the long-running AUTO toggle armed across respawns.
    if not TrashAutoEnabled then
        TrashToken = TrashToken + 1
        TrashBusy = false
        TrashPhase = "idle"
    end
    clearAimTarget()
    OriginalWalkSpeed = nil
    SpeedHumanoid = nil
    CurrentSpeedWritten = nil
    if CONFIG.SPEED_ENABLED then task.defer(refreshSpeed) end
    Invisibility.remove()
    PreviousAutoRotate = nil
    SafeTriggered = false
    if SafePlatform then removeSafeZone(false) end

    monitorHealth(character)

    if BackstabActive then
        local hum = character:WaitForChild("Humanoid", 10)
        if hum then
            PreviousAutoRotate = hum.AutoRotate
            hum.AutoRotate = false
        end
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
Message("GRINGO XP SHADOW TSB", "v15: instant TP + Garou 1/2 random cycle (no auto evade)", 4)
