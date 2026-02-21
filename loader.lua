local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:match("^%s*(.-)%s*$")
end

local function safe_call(fn, ...)
    local ok, a, b, c = pcall(fn, ...)
    if not ok then
        return false, a
    end
    return true, a, b, c
end

local function make_result(ok, code, message, data)
    return {
        ok = ok == true,
        code = code or "UNKNOWN",
        message = message or "Unknown result",
        data = data,
    }
end

-- Layer 1: Config and bootstrap
local Config = {
    WindUIVersion = "1.6.53",
    WindUIReleaseBaseUrl = "https://github.com/Footagesus/WindUI/releases/download/",
    KeyStorageFile = "GalaxyHubKey.txt",
    KeyUrl = "https://ads.luarmor.net/get_key?for=Galaxy_Hub-XPfsiYNlVWIO",
    LuarmorLibraryUrl = "https://sdkapi-public.luarmor.net/library.lua",
    GameByPlaceId = {
        [6137321701] = {
            name = "Blair",
            scriptId = "01709abfe8c48853d9e91bc4fe1c5e8a",
        },
        [6348640020] = {
            name = "Blair",
            scriptId = "01709abfe8c48853d9e91bc4fe1c5e8a",
        },
        [129315204746120] = {
            name = "Escape Quicksand for Brainrots",
            scriptId = "6ef57bb8be96a0ebda87df91de041b28",
        },
    },
}

local placeConfig = Config.GameByPlaceId[game.PlaceId]
local GameName = (placeConfig and placeConfig.name) or "Universal"
local ScriptId = placeConfig and placeConfig.scriptId or nil

local WindUI
do
    local uiUrl = Config.WindUIReleaseBaseUrl .. Config.WindUIVersion .. "/main.lua"
    local ok, loaded = safe_call(function()
        return loadstring(game:HttpGet(uiUrl))()
    end)
    if not ok or not loaded then
        warn("[GalaxyHub] Failed to load WindUI v" .. Config.WindUIVersion .. ": " .. tostring(loaded))
        return
    end
    WindUI = loaded
end

local function notify(payload)
    WindUI:Notify({
        Title = payload.Title or "",
        Content = payload.Content or "",
        Duration = payload.Duration or 4,
        Icon = payload.Icon,
    })
end

-- Layer 2: Key service
local KeyModule = {
    ScriptID = ScriptId,
    MainWindow = nil,
    Notify = nil,
    _api = nil,
    keyData = nil,
    lastResult = nil,
}

local function collect_key_data(raw)
    if type(raw) ~= "table" then
        return nil
    end

    return {
        auth_expire = raw.auth_expire,
        total_executions = raw.total_executions,
        note = raw.note,
    }
end

local function ensure_api()
    if not KeyModule.ScriptID then
        return make_result(false, "UNSUPPORTED_GAME", "This game is not supported yet.")
    end

    if KeyModule._api then
        return make_result(true, "OK", "API ready")
    end

    local okFetch, libSourceOrError = safe_call(function()
        return game:HttpGet(Config.LuarmorLibraryUrl)
    end)
    if not okFetch or type(libSourceOrError) ~= "string" or libSourceOrError == "" then
        return make_result(false, "API_FETCH_FAILED", "Failed to fetch key API.")
    end

    local okInit, apiOrError = safe_call(function()
        return loadstring(libSourceOrError)()
    end)
    if not okInit or type(apiOrError) ~= "table" then
        return make_result(false, "API_INIT_FAILED", "Failed to initialize key API.")
    end

    apiOrError.script_id = KeyModule.ScriptID
    KeyModule._api = apiOrError

    return make_result(true, "OK", "API ready")
end

function KeyModule.SaveKey(key)
    local value = trim(key)
    if value == "" then
        return
    end

    safe_call(function()
        if type(writefile) == "function" then
            writefile(Config.KeyStorageFile, value)
        end
    end)
end

function KeyModule.LoadSavedKey()
    local ok, data = safe_call(function()
        if type(isfile) == "function" and type(readfile) == "function" and isfile(Config.KeyStorageFile) then
            return readfile(Config.KeyStorageFile)
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
        if type(isfile) == "function" and type(delfile) == "function" and isfile(Config.KeyStorageFile) then
            delfile(Config.KeyStorageFile)
        end
    end)
end

function KeyModule.FormatTime(timestamp)
    if type(timestamp) ~= "number" or timestamp <= 0 then
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

local function validate_key_internal(key)
    local value = trim(key)
    if value == "" then
        return make_result(false, "EMPTY_KEY", "Please enter a key.")
    end

    if type(getgenv) == "function" then
        getgenv().script_key = value
    end

    local apiResult = ensure_api()
    if not apiResult.ok then
        return apiResult
    end

    local okCheck, statusOrError = safe_call(function()
        return KeyModule._api.check_key(value)
    end)
    if not okCheck then
        return make_result(false, "CHECK_FAILED", "Failed to validate key. Try again.")
    end
    if type(statusOrError) ~= "table" then
        return make_result(false, "INVALID_RESPONSE", "Key API returned an invalid response.")
    end

    if statusOrError.code == "KEY_VALID" then
        KeyModule.SaveKey(value)
        KeyModule.keyData = collect_key_data(statusOrError.data)
        return make_result(true, "KEY_VALID", statusOrError.message or "Key is valid.", KeyModule.keyData)
    end

    KeyModule.DeleteSavedKey()
    KeyModule.keyData = nil
    return make_result(false, statusOrError.code or "KEY_INVALID", statusOrError.message or "Key validation failed.")
end

local function load_script_internal()
    local apiResult = ensure_api()
    if not apiResult.ok then
        return apiResult
    end

    local okLoad = safe_call(function()
        KeyModule._api.load_script()
    end)
    if not okLoad then
        return make_result(false, "LOAD_FAILED", "Failed to load script.")
    end

    return make_result(true, "LOADED", "Script loaded successfully.")
end

function KeyModule.Validate(key)
    local result = validate_key_internal(key)
    KeyModule.lastResult = result
    return result.ok, result
end

function KeyModule.Load()
    local result = load_script_internal()
    KeyModule.lastResult = result
    return result.ok, result
end

function KeyModule.GetKeyLink()
    return Config.KeyUrl
end

-- Layer 3: UI controller
local Phase = {
    IDLE = "IDLE",
    VALIDATING = "VALIDATING",
    VALID = "VALID",
    INVALID = "INVALID",
    LOADING = "LOADING",
    ERROR = "ERROR",
}

local State = {
    phase = Phase.IDLE,
    keyInput = "",
    validating = false,
    validated = false,
    keyData = nil,
    lastError = nil,
    isSupportedGame = KeyModule.ScriptID ~= nil,
    savedKeyFound = false,
}

local function get_executor_name()
    if type(identifyexecutor) ~= "function" then
        return "Unknown Executor"
    end

    local ok, executorName = safe_call(identifyexecutor)
    if ok and type(executorName) == "string" and executorName ~= "" then
        return executorName
    end

    return "Unknown Executor"
end

local function get_unsupported_executor_name(executorName)
    local value = string.lower(tostring(executorName or ""))
    if string.find(value, "xeno", 1, true) then
        return "Xeno"
    end
    if string.find(value, "solara", 1, true) then
        return "Solara"
    end
    return nil
end

local Window = WindUI:CreateWindow({
    Title = "Galaxy Hub Key System",
    Author = "Galaxy Hub",
    Folder = "GalaxyHub",
    Theme = "Dark",
})

KeyModule.MainWindow = Window
KeyModule.Notify = notify

local function show_executor_warning_if_needed()
    local executorName = get_executor_name()
    local unsupported = get_unsupported_executor_name(executorName)
    if not unsupported then
        return
    end

    local warningText = "You may experience severe stability issues while using " .. unsupported .. ". Some UI and script features may fail or behave unexpectedly."

    local okDialog, dialog = safe_call(function()
        return Window:Dialog({
            Icon = "alert-triangle",
            Title = "Executor Compatibility Warning",
            Content = warningText,
            Buttons = {
                {
                    Title = "Continue",
                    Variant = "Primary",
                    Callback = function()
                    end,
                },
            },
        })
    end)

    if okDialog and dialog and dialog.Show then
        safe_call(function()
            dialog:Show()
        end)
        return
    end

    notify({
        Title = "Executor Compatibility Warning",
        Content = warningText,
        Duration = 8,
        Icon = "alert-triangle",
    })
end

show_executor_warning_if_needed()

local Tab = Window:Tab({
    Title = "Key System",
})

Tab:Section({
    Title = "Access",
    TextSize = 18,
})

local AccessSection = Tab:Section({
    Title = "Key Validation",
    Box = true,
    BoxBorder = true,
    Opened = true,
})

AccessSection:Paragraph({
    Title = "Instructions",
    Desc = "Paste your key and click Validate Key.",
    Image = "key-round",
})

local KeyInput = AccessSection:Input({
    Title = "Enter Key",
    Value = "",
    Placeholder = "Enter your key...",
    Callback = function(text)
        State.keyInput = text or ""
    end,
})

local ValidateButton
local LoadButton
local StatusParagraph
local InfoParagraph
local GameParagraph

local function lock_element(element)
    safe_call(function()
        element:Lock()
    end)
end

local function unlock_element(element)
    safe_call(function()
        element:Unlock()
    end)
end

local function get_status_text()
    if not State.isSupportedGame then
        return "Unsupported game. This key system is not available for this place."
    end

    if State.phase == Phase.IDLE then
        if State.savedKeyFound then
            return "Saved key found. Click Validate Key."
        end
        return "Ready"
    end
    if State.phase == Phase.VALIDATING then
        return "Validating key..."
    end
    if State.phase == Phase.VALID then
        return "Key validated. Ready to load."
    end
    if State.phase == Phase.INVALID then
        return "Validation failed: " .. (State.lastError or "Invalid key.")
    end
    if State.phase == Phase.LOADING then
        return "Loading script..."
    end
    if State.phase == Phase.ERROR then
        return "Error: " .. (State.lastError or "Unknown error.")
    end
    return "Ready"
end

local function get_key_info_text()
    local kd = State.keyData
    if not kd or kd.auth_expire == nil then
        return "Not available"
    end

    local expiry = KeyModule.FormatTime(kd.auth_expire)
    local executions = tostring(kd.total_executions or 0)
    local note = tostring(kd.note or "None")
    return "Expires: " .. expiry .. " | Executions: " .. executions .. " | Note: " .. note
end

local function render()
    if StatusParagraph then
        StatusParagraph:SetDesc(get_status_text())
    end
    if InfoParagraph then
        InfoParagraph:SetDesc(get_key_info_text())
    end
    if GameParagraph then
        local supportText = State.isSupportedGame and "Supported" or "Unsupported"
        local scriptIdText = KeyModule.ScriptID or "N/A"
        GameParagraph:SetDesc("Detected Game: " .. GameName .. " | " .. supportText .. " | Script ID: " .. scriptIdText)
    end

    local busy = State.phase == Phase.VALIDATING or State.phase == Phase.LOADING
    if ValidateButton then
        if (not State.isSupportedGame) or busy then
            lock_element(ValidateButton)
        else
            unlock_element(ValidateButton)
        end
    end

    if LoadButton then
        if (not State.isSupportedGame) or busy or (not State.validated) then
            lock_element(LoadButton)
        else
            unlock_element(LoadButton)
        end
    end
end

local function notify_validation_success(result)
    local message = (result and result.message) or "Key is valid."
    if State.keyData and State.keyData.auth_expire ~= nil then
        if State.keyData.auth_expire <= 0 then
            message = message .. " (Lifetime access)"
        else
            message = message .. " (Expires in: " .. KeyModule.FormatTime(State.keyData.auth_expire) .. ")"
        end
    end

    notify({
        Title = "Success",
        Content = message,
        Duration = 5,
        Icon = "check",
    })
end

local function handle_validate_click()
    if State.phase == Phase.VALIDATING or State.phase == Phase.LOADING then
        return
    end

    local keyValue = trim(State.keyInput)
    if keyValue == "" then
        State.phase = Phase.INVALID
        State.validated = false
        State.keyData = nil
        State.lastError = "Please enter a key."
        notify({
            Title = "Error",
            Content = State.lastError,
            Duration = 4,
            Icon = "x-circle",
        })
        render()
        return
    end

    if not State.isSupportedGame then
        State.phase = Phase.ERROR
        State.validated = false
        State.keyData = nil
        State.lastError = "This game is not supported yet."
        notify({
            Title = "Error",
            Content = State.lastError,
            Duration = 5,
            Icon = "x-circle",
        })
        render()
        return
    end

    State.phase = Phase.VALIDATING
    State.validating = true
    State.validated = false
    State.lastError = nil
    render()

    local ok, result = KeyModule.Validate(keyValue)
    State.validating = false
    if ok then
        State.phase = Phase.VALID
        State.validated = true
        State.keyData = (result and result.data) or KeyModule.keyData
        State.lastError = nil
        notify_validation_success(result)
    else
        State.validated = false
        State.keyData = nil
        State.lastError = (result and result.message) or "Key validation failed."
        if result and (result.code == "API_FETCH_FAILED" or result.code == "API_INIT_FAILED" or result.code == "UNSUPPORTED_GAME") then
            State.phase = Phase.ERROR
        else
            State.phase = Phase.INVALID
        end
        notify({
            Title = "Error",
            Content = State.lastError,
            Duration = 5,
            Icon = "x-circle",
        })
    end

    render()
end

ValidateButton = AccessSection:Button({
    Title = "Validate Key",
    Desc = "Verify your key before loading the script.",
    Icon = "shield-check",
    Callback = handle_validate_click,
})

Tab:Space({
    Columns = 2,
})

Tab:Section({
    Title = "Actions",
    TextSize = 18,
})

local ActionsSection = Tab:Section({
    Title = "Script Actions",
    Box = true,
    BoxBorder = true,
    Opened = true,
})

ActionsSection:Button({
    Title = "Get Key Link",
    Desc = "Copy key link if clipboard is available.",
    Icon = "link",
    Callback = function()
        local link = KeyModule.GetKeyLink()
        local copied = false
        if type(setclipboard) == "function" then
            copied = safe_call(function()
                setclipboard(link)
            end)
        end

        if copied then
            notify({
                Title = "Copied",
                Content = "Key link copied to clipboard.",
                Duration = 4,
                Icon = "copy",
            })
        else
            notify({
                Title = "Key Link",
                Content = link,
                Duration = 8,
                Icon = "link",
            })
        end
    end,
})

local function create_load_dialog(onConfirm)
    local okDialog, dialog = safe_call(function()
        return Window:Dialog({
            Icon = "shield-check",
            Title = "Load Script?",
            Content = "Your key is valid. Do you want to load the script now?",
            Buttons = {
                {
                    Title = "Confirm",
                    Variant = "Primary",
                    Callback = onConfirm,
                },
                {
                    Title = "Cancel",
                    Variant = "Secondary",
                    Callback = function()
                        render()
                    end,
                },
            },
        })
    end)

    if not okDialog or not dialog then
        notify({
            Title = "Error",
            Content = "Unable to open confirmation dialog.",
            Duration = 4,
            Icon = "x-circle",
        })
        return
    end

    if dialog and dialog.Show then
        local okShow = safe_call(function()
            dialog:Show()
        end)
        if not okShow then
            notify({
                Title = "Error",
                Content = "Unable to display confirmation dialog.",
                Duration = 4,
                Icon = "x-circle",
            })
        end
    end
end

LoadButton = ActionsSection:Button({
    Title = "Load Script",
    Desc = "Requires valid key confirmation.",
    Icon = "play",
    Callback = function()
        if State.phase == Phase.VALIDATING or State.phase == Phase.LOADING then
            return
        end

        if not State.validated then
            notify({
                Title = "Action Required",
                Content = "Validate your key first.",
                Duration = 4,
                Icon = "alert-circle",
            })
            return
        end

        create_load_dialog(function()
            if State.phase == Phase.LOADING then
                return
            end

            State.phase = Phase.LOADING
            State.lastError = nil
            render()

            local ok, result = KeyModule.Load()
            if ok then
                State.phase = Phase.VALID
                State.lastError = nil
                notify({
                    Title = "Success",
                    Content = "Script loaded successfully.",
                    Duration = 4,
                    Icon = "check",
                })

                task.delay(1, function()
                    safe_call(function()
                        if KeyModule.MainWindow then
                            KeyModule.MainWindow:Destroy()
                        end
                    end)
                end)
            else
                State.phase = Phase.ERROR
                State.lastError = (result and result.message) or "Unable to load script."
                notify({
                    Title = "Load Failed",
                    Content = State.lastError,
                    Duration = 5,
                    Icon = "x-circle",
                })
            end

            render()
        end)
    end,
})

Tab:Space({
    Columns = 2,
})

Tab:Section({
    Title = "Status",
    TextSize = 18,
})

local StatusSection = Tab:Section({
    Title = "Runtime Status",
    Box = true,
    BoxBorder = true,
    Opened = true,
})

StatusParagraph = StatusSection:Paragraph({
    Title = "Status",
    Desc = "Ready",
    Image = "info",
})

InfoParagraph = StatusSection:Paragraph({
    Title = "Key Info",
    Desc = "Not available",
    Image = "badge-info",
})

GameParagraph = StatusSection:Paragraph({
    Title = "Game",
    Desc = "Detected Game: " .. GameName,
    Image = "gamepad-2",
})

do
    local savedKey = KeyModule.LoadSavedKey()
    if savedKey and savedKey ~= "" then
        State.savedKeyFound = true
        State.keyInput = savedKey
        safe_call(function()
            KeyInput:Set(savedKey)
        end)
    end

    if not State.isSupportedGame then
        State.phase = Phase.ERROR
        State.lastError = "This game is not supported yet."
    else
        State.phase = Phase.IDLE
    end

    render()
end
