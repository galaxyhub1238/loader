local M = {}

local GAME_TO_SCRIPT = {
    [6137321701] = "01709abfe8c48853d9e91bc4fe1c5e8a",
    [6348640020] = "01709abfe8c48853d9e91bc4fe1c5e8a",
}

local STORAGE_FILE = "GalaxyHubKey.txt"
local KEY_URL = "https://ads.luarmor.net/get_key?for=Galaxy_Hub-XPfsiYNlVWIO"
local LIB_URL = "https://sdkapi-public.luarmor.net/library.lua"

M.ScriptID = GAME_TO_SCRIPT[game.PlaceId] or "e875a9abc2005dd220616ad2d265e2b9"
M.MainWindow = nil
M.Notify = nil
M._api = nil
M.keyData = nil

local function trim(s)
    if type(s) ~= "string" then return "" end
    return s:match("^%s*(.-)%s*$")
end

local function safe_pcall(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return false, nil
    end
    return true, a, b, c
end

local function ensure_api()
    if M._api then return true end
    local ok, api = safe_pcall(function()
        return loadstring(game:HttpGet(LIB_URL))()
    end)
    if not ok or not api then
        return false
    end
    api.script_id = M.ScriptID
    M._api = api
    return true
end

function M.SaveKey(key)
    local k = trim(key)
    if k == "" then return end
    safe_pcall(function()
        if writefile then writefile(STORAGE_FILE, k) end
    end)
end

function M.LoadSavedKey()
    local ok, data = safe_pcall(function()
        if isfile and isfile(STORAGE_FILE) then
            return readfile(STORAGE_FILE)
        end
        return nil
    end)
    if ok and data then
        return trim(data)
    end
    return nil
end

function M.DeleteSavedKey()
    safe_pcall(function()
        if isfile and isfile(STORAGE_FILE) then
            delfile(STORAGE_FILE)
        end
    end)
end

function M.FormatTime(ts)
    if not ts or ts <= 0 then return "Lifetime" end
    local remain = ts - os.time()
    if remain <= 0 then return "Expired" end
    local d = math.floor(remain / 86400)
    local h = math.floor((remain % 86400) / 3600)
    local m = math.floor((remain % 3600) / 60)
    if d > 0 then return string.format("%d days, %d hours", d, h) end
    if h > 0 then return string.format("%d hours, %d minutes", h, m) end
    return string.format("%d minutes", m)
end

function M.Validate(key)
    local input = trim(key)
    if input == "" then
        if M.Notify then M.Notify({ Title = "Error", Content = "Please enter a key", Duration = 5 }) end
        return false
    end
    getgenv().script_key = input
    if not ensure_api() then
        if M.Notify then M.Notify({ Title = "Error", Content = "API unavailable", Duration = 5 }) end
        return false
    end
    local ok, status = safe_pcall(function()
        return M._api.check_key(getgenv().script_key)
    end)
    if not ok or not status then
        if M.Notify then M.Notify({ Title = "Error", Content = "Failed to validate key. Try again.", Duration = 5 }) end
        return false
    end
    if status.code == "KEY_VALID" then
        M.SaveKey(input)
        if status.data then
            M.keyData = {
                auth_expire = status.data.auth_expire,
                total_executions = status.data.total_executions,
                note = status.data.note,
            }
        end
        if M.Notify then
            local extra = ""
            if status.data and status.data.auth_expire then
                if status.data.auth_expire <= 0 then
                    extra = " (Lifetime access)"
                else
                    extra = " (Expires in: " .. M.FormatTime(status.data.auth_expire) .. ")"
                end
            end
            M.Notify({ Title = "Success", Content = (status.message or "Key is valid") .. extra, Duration = 5 })
        end
        return true
    else
        M.DeleteSavedKey()
        if M.Notify then
            local fallback = "Key validation failed"
            local msg = status.message or fallback
            M.Notify({ Title = "Error", Content = msg, Duration = 5 })
        end
        return false
    end
end

function M.Load()
    if not ensure_api() then return false end
    task.wait(0.1)
    safe_pcall(function()
        M._api.load_script()
    end)
    if M.MainWindow then
        task.delay(1, function()
            M.MainWindow:Destroy()
        end)
    end
    return true
end

function M.GetKeyLink()
    return KEY_URL
end

return M
