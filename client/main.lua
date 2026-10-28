local resourceName = GetCurrentResourceName()
local appId = 'suimag-achievement'
local titleKey = 'suimagAchievementTitles'
local titles = GlobalState[titleKey] or {}
local registered = false

local function addApp()
    if registered or GetResourceState('lb-phone') ~= 'started' then return end
    Wait(500) -- LB Phone registers its exports shortly after startup.
    if registered or GetResourceState('lb-phone') ~= 'started' then return end
    local ok, reason = exports['lb-phone']:AddCustomApp({
        identifier = appId,
        name = '実績',
        description = '街での歩みを記録して、称号を身につけよう。',
        developer = 'SuiMag',
        defaultApp = true,
        size = 32,
        ui = resourceName .. '/ui/index.html',
        icon = 'https://cfx-nui-' .. resourceName .. '/ui/icon.svg',
        fixBlur = true,
        onOpen = function()
            exports['lb-phone']:SendCustomAppMessage(appId, { type = 'achievementsChanged' })
        end,
    })
    registered = ok
    if not ok then print(('[%s] App registration failed: %s'):format(resourceName, tostring(reason))) end
end

local function callback(name, serverCallback)
    RegisterNUICallback(name, function(data, cb)
        local ok, response = pcall(lib.callback.await, serverCallback, false, type(data) == 'table' and data.id or nil)
        cb(ok and response or { ok = false, error = '通信に失敗しました。もう一度お試しください。' })
    end)
end

callback('getAchievements', 'suimag-achievement:get')
callback('selectTitle', 'suimag-achievement:select')

RegisterNetEvent('suimag-achievement:refresh', function()
    if registered then
        exports['lb-phone']:SendCustomAppMessage(appId, { type = 'achievementsChanged' })
    end
end)

-- Use the existing playernames context extension; never replace player settings.
AddEventHandler('playernames:extendContext', function(playerIndex, cb)
    local title = titles[tostring(GetPlayerServerId(playerIndex))]
    cb('achievementPrefix', title and ('[' .. title .. '] ') or '')
end)

local function rename(serverId)
    TriggerEvent('playernames:configure', tonumber(serverId), 'rnme')
end

AddStateBagChangeHandler(titleKey, 'global', function(_, _, value)
    local previous = titles
    titles = value or {}
    for id in pairs(previous) do if previous[id] ~= titles[id] then rename(id) end end
    for id in pairs(titles) do if not previous[id] then rename(id) end end
end)

CreateThread(function()
    addApp()
    for _, playerIndex in ipairs(GetActivePlayers()) do rename(GetPlayerServerId(playerIndex)) end
end)

AddEventHandler('onClientResourceStart', function(name)
    if name == 'lb-phone' then addApp() end
end)

AddEventHandler('onClientResourceStop', function(name)
    if name == 'lb-phone' then registered = false end
    if name ~= resourceName then return end
    local previous = titles
    titles = {}
    for id in pairs(previous) do rename(id) end
    if registered and GetResourceState('lb-phone') == 'started' then
        exports['lb-phone']:RemoveCustomApp(appId)
    end
end)
