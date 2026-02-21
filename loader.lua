local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local GameIds = {
    [6348640020] = "Blair",
    [6137321701] = "Blair",
}

local GameName = GameIds[game.PlaceId] or "Universal"

local KeyModule = {}
local ModuleSource = "Embedded"
do
    local GAME_TO_SCRIPT = {
        [6137321701] = "01709abfe8c48853d9e91bc4fe1c5e8a",
        [6348640020] = "01709abfe8c48853d9e91bc4fe1c5e8a",
    }
    local STORAGE_FILE = "GalaxyHubKey.txt"
    local KEY_URL = "https://ads.luarmor.net/get_key?for=Galaxy_Hub-XPfsiYNlVWIO"
    local LIB_URL = "https://sdkapi-public.luarmor.net/library.lua"

    KeyModule.ScriptID = GAME_TO_SCRIPT[game.PlaceId] or print("Universal Script is not avaible yet.")
    KeyModule.MainWindow = nil
    KeyModule.Notify = nil
    KeyModule._api = nil
    KeyModule.keyData = nil

    local function trim(value)
        if type(value) ~= "string" then
            return ""
        end
        return value:match("^%s*(.-)%s*$")
    end

    local function safe_call(fn, ...)
        local ok, a, b, c = pcall(fn, ...)
        if not ok then
            return false
        end
        return true, a, b, c
    end

    local function ensure_api()
        if KeyModule._api then
            return true
        end
        local ok, api = safe_call(function()
            return loadstring(game:HttpGet(LIB_URL))()
        end)
        if not ok or not api then
            return false
        end
        api.script_id = KeyModule.ScriptID
        KeyModule._api = api
        return true
    end

    function KeyModule.SaveKey(key)
        local value = trim(key)
        if value == "" then
            return
        end
        safe_call(function()
            if writefile then
                writefile(STORAGE_FILE, value)
            end
        end)
    end

    function KeyModule.LoadSavedKey()
        local ok, data = safe_call(function()
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

    function KeyModule.DeleteSavedKey()
        safe_call(function()
            if isfile and isfile(STORAGE_FILE) then
                delfile(STORAGE_FILE)
            end
        end)
    end

    function KeyModule.FormatTime(timestamp)
        if not timestamp or timestamp <= 0 then
            return "Lifetime"
        end
        local remaining = timestamp - os.time()
        if remaining <= 0 then
            return "Expired"
        end
        local days = math.floor(remaining / 86400)
        local hours = math.floor((remaining % 86400) / 3600)
        local minutes = math.floor((remaining % 3600) / 60)
        if days > 0 then
            return days .. " days, " .. hours .. " hours"
        end
        if hours > 0 then
            return hours .. " hours, " .. minutes .. " minutes"
        end
        return minutes .. " minutes"
    end

    function KeyModule.Validate(key)
        local value = trim(key)
        if value == "" then
            if KeyModule.Notify then
                KeyModule.Notify({ Title = "Error", Content = "Please enter a key", Duration = 5 })
            end
            return false
        end
        getgenv().script_key = value
        if not ensure_api() then
            if KeyModule.Notify then
                KeyModule.Notify({ Title = "Error", Content = "API unavailable", Duration = 5 })
            end
            return false
        end
        local ok, status = safe_call(function()
            return KeyModule._api.check_key(getgenv().script_key)
        end)
        if not ok or not status then
            if KeyModule.Notify then
                KeyModule.Notify({ Title = "Error", Content = "Failed to validate key. Try again.", Duration = 5 })
            end
            return false
        end
        if status.code == "KEY_VALID" then
            KeyModule.SaveKey(value)
            if status.data then
                KeyModule.keyData = {
                    auth_expire = status.data.auth_expire,
                    total_executions = status.data.total_executions,
                    note = status.data.note,
                }
            end
            if KeyModule.Notify then
                local suffix = ""
                if status.data and status.data.auth_expire then
                    if status.data.auth_expire <= 0 then
                        suffix = " (Lifetime access)"
                    else
                        suffix = " (Expires in: " .. KeyModule.FormatTime(status.data.auth_expire) .. ")"
                    end
                end
                KeyModule.Notify({ Title = "Success", Content = (status.message or "Key is valid") .. suffix, Duration = 5 })
            end
            return true
        else
            KeyModule.DeleteSavedKey()
            if KeyModule.Notify then
                KeyModule.Notify({ Title = "Error", Content = status.message or "Key validation failed", Duration = 5 })
            end
            return false
        end
    end

    function KeyModule.Load()
        if not ensure_api() then
            return false
        end
        safe_call(function()
            KeyModule._api.load_script()
        end)
        if KeyModule.MainWindow then
            task.delay(1, function()
                KeyModule.MainWindow:Destroy()
            end)
        end
        return true
    end

    function KeyModule.GetKeyLink()
        return KEY_URL
    end
end

local Window = WindUI:CreateWindow({
    Title = "Validate Key",
    Author = "Galaxy Hub",
    Folder = "GalaxyHub",
    Theme = "Dark",
})

local Tab = Window:Tab({
    Title = "Key System",
})

local StatusParagraph = Tab:Paragraph({
    Title = "Status",
    Desc = "Ready",
})

local keyInputValue = ""
local validating = false
local validated = false

local KeyInput = Tab:Input({
    Title = "Enter Key",
    Value = "",
    Placeholder = "Enter your key...",
    Callback = function(text)
        keyInputValue = text or ""
    end,
})

local InfoParagraph = Tab:Paragraph({
    Title = "Key Info",
    Desc = "Not available",
})

local SourceParagraph = Tab:Paragraph({
    Title = "Module Source",
    Desc = ModuleSource,
})

local function notify(data)
    WindUI:Notify({
        Title = data.Title or "",
        Content = data.Content or "",
        Duration = data.Duration or 4,
        Icon = data.Image,
    })
end

local function setStatus(text)
    StatusParagraph:SetTitle("Status")
    StatusParagraph:SetDesc(text)
end

local function updateInfo()
    local kd = KeyModule.keyData
    if kd and kd.auth_expire ~= nil then
        local expiry = KeyModule.FormatTime(kd.auth_expire)
        local executions = tostring(kd.total_executions or 0)
        local note = kd.note or "None"
        InfoParagraph:SetTitle("Key Info")
        InfoParagraph:SetDesc("Expires: " .. expiry .. " | Executions: " .. executions .. " | Note: " .. note)
    else
        InfoParagraph:SetTitle("Key Info")
        InfoParagraph:SetDesc("Not available")
    end
end

local ValidateButton = Tab:Button({
    Title = "Validate Key",
    Callback = function()
        if validating then
            return
        end
        if not keyInputValue or keyInputValue == "" then
            notify({ Title = "Error", Content = "Please enter a key", Duration = 4 })
            return
        end
        validating = true
        validated = false
        setStatus("Validating key...")
        KeyModule.MainWindow = Window
        KeyModule.Notify = function(notifyData)
            notify(notifyData)
            if notifyData.Title == "Success" then
                validated = true
                setStatus("Key validated successfully")
                updateInfo()
            elseif notifyData.Title == "Error" then
                setStatus("Validation failed")
            end
            validating = false
        end
        local handled = false
        if KeyModule.Validate then
            handled = KeyModule.Validate(keyInputValue)
        end
        if not handled and validating then
            validating = false
        end
    end,
})

Tab:Button({
    Title = "Get Key Link",
    Callback = function()
        local link = KeyModule.GetKeyLink and KeyModule.GetKeyLink() or "https://ads.luarmor.net/get_key?for=Galaxy_Hub-jXWGLsIDEaFX"
        if setclipboard then
            setclipboard(link)
        end
        notify({ Title = "Copied", Content = "Key link copied to clipboard", Duration = 4 })
    end,
})

Tab:Button({
    Title = "Load Script",
    Callback = function()
        if not validated then
            notify({ Title = "Action Required", Content = "Validate your key first", Duration = 4 })
            return
        end
        local ok = false
        if KeyModule.Load then
            ok = KeyModule.Load()
        end
        if not ok then
            notify({ Title = "Load Failed", Content = "Unable to load script", Duration = 4 })
        end
    end,
})

Window:Section({
    Title = "Detected Game: " .. GameName,
    Icon = "gamepad-2",
    Opened = true,
})

do
    local saved = KeyModule.LoadSavedKey and KeyModule.LoadSavedKey() or nil
    if saved and saved ~= "" then
        KeyInput:Set(saved)
        keyInputValue = saved
    end
end

