--[[
    tsb_remote_inspector.lua
    Target: Roblox / Luau executor (Delta, Xeno, Arceus X, Codex...)
    Назначение: перехват и логирование всех исходящих RemoteEvent/RemoteFunction
    вызовов клиента. Помогает искать уязвимости через анализ трафика.
    
    ВАЖНО: это исследовательский инструмент. Он НЕ находит уязвимости
    автоматически — он показывает, что игра отправляет на сервер, чтобы ты
    сам мог искать места без серверной валидации.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CONFIG = {
    LOG_TO_CONSOLE = true,      -- печатать в консоль
    LOG_TO_FILE    = false,     -- писать в tsb_remotes.log
    FILE_PATH      = "tsb_remotes.log",
    IGNORE_HIGH_FREQ = true,    -- не спамить частыми вызовами (например, каждые 0.1с)
    MIN_INTERVAL   = 0.05,      -- минимальный интервал между логами одного remote
}

local log_buffer = {}
local last_seen = {}

local function log(msg)
    if CONFIG.LOG_TO_CONSOLE then
        print("[REMOTE] " .. msg)
    end
    if CONFIG.LOG_TO_FILE then
        table.insert(log_buffer, msg)
        if #log_buffer >= 20 then
            pcall(function()
                local f = io.open(CONFIG.FILE_PATH, "a")
                if f then
                    f:write(table.concat(log_buffer, "\n") .. "\n")
                    f:close()
                end
            end)
            log_buffer = {}
        end
    end
end

local function should_log(remote)
    if not CONFIG.IGNORE_HIGH_FREQ then return true end
    local now = tick()
    local key = tostring(remote)
    if last_seen[key] and (now - last_seen[key]) < CONFIG.MIN_INTERVAL then
        return false
    end
    last_seen[key] = now
    return true
end

-- ─── Перехват исходящих вызовов ──────────────────────────────────
-- В Luau нет прямого хука на :FireServer(), но можно перехватить
-- через Namecall hook (Namecall — это то, как Luau вызывает методы).

local old_namecall
old_namecall = hookmetamethod(game, "__namecall", function(self, ...)
    local method = getnamecallmethod()
    
    if method == "FireServer" or method == "InvokeServer" then
        if self:IsA("RemoteEvent") or self:IsA("RemoteFunction") then
            if should_log(self) then
                local args = {...}
                local arg_str = {}
                for i, v in ipairs(args) do
                    arg_str[i] = tostring(v)
                end
                log(("%s | %s | args: [%s]"):format(
                    method,
                    self:GetFullName(),
                    table.concat(arg_str, ", ")
                ))
            end
        end
    end
    
    return old_namecall(self, ...)
end)

-- ─── Список всех Remote в игре (для ручного анализа) ─────────────
local function dump_all_remotes()
    print("\n=== ALL REMOTES IN GAME ===")
    local remotes = {}
    
    local function scan(parent)
        for _, obj in ipairs(parent:GetDescendants()) do
            if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
                table.insert(remotes, obj)
            end
        end
    end
    
    scan(game:GetService("ReplicatedStorage"))
    scan(game:GetService("ReplicatedFirst"))
    
    table.sort(remotes, function(a, b)
        return a:GetFullName() < b:GetFullName()
    end)
    
    for i, r in ipairs(remotes) do
        print(("%3d. [%s] %s"):format(i, r.ClassName, r:GetFullName()))
    end
    
    print(("=== TOTAL: %d remotes ===\n"):format(#remotes))
    return remotes
end

-- ─── Проверка, какие Remote вообще есть ─────────────────────────
local remotes = dump_all_remotes()

-- ─── API ─────────────────────────────────────────────────────────
_G.TSBInspector = {
    dump = dump_all_remotes,
    remotes = remotes,
    
    -- Начать логирование только для конкретного remote
    filter = nil,
    set_filter = function(name)
        _G.TSBInspector.filter = name
        print("[REMOTE] filter set: " .. tostring(name))
    end,
    
    -- Остановить перехват (вернуть оригинальный namecall)
    stop = function()
        if old_namecall then
            hookmetamethod(game, "__namecall", old_namecall)
            old_namecall = nil
            print("[REMOTE] inspector stopped")
        end
    end,
}

print("[TSBInspector] loaded. Используй _G.TSBInspector.dump() для списка remotes")
print("[TSBInspector] или _G.TSBInspector.stop() чтобы остановить перехват")
