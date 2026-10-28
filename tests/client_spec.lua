-- Run from the resource directory: lua tests/client_spec.lua
local events, nui, calls, stateChanged, app = {}, {}, {}, nil, nil
local phoneState = 'started'
local titleKey = 'suimagAchievementTitles'
GetCurrentResourceName = function() return 'suimag-achievement' end
GlobalState = { [titleKey] = { ['10'] = '新しい住民' } }
GetResourceState = function() return phoneState end
GetPlayerServerId = function(index) return index + 10 end
GetActivePlayers = function() return { 0, 1 } end
TriggerEvent = function(...) calls[#calls + 1] = { ... } end
AddEventHandler = function(name, fn) events[name] = fn end
RegisterNetEvent = AddEventHandler
RegisterNUICallback = function(name, fn) nui[name] = fn end
AddStateBagChangeHandler = function(key, filter, fn)
    assert(key == titleKey and filter == 'global')
    stateChanged = fn
end
CreateThread = function(fn) fn() end
Wait = function(milliseconds) assert(milliseconds == 500) end
exports = { ['lb-phone'] = {
    AddCustomApp = function(_, definition) app = definition; return true end,
    RemoveCustomApp = function(_, id) assert(id == 'suimag-achievement'); app = nil end,
    SendCustomAppMessage = function(_, id, data) assert(id == 'suimag-achievement'); assert(data.type == 'achievementsChanged') end,
} }
lib = { callback = { await = function(name, _, id)
    return { ok = true, callback = name, id = id }
end } }
dofile('client/main.lua')
assert(app.identifier == 'suimag-achievement' and app.defaultApp)
app.onOpen()
local function prefix(index)
    local value
    events['playernames:extendContext'](index, function(key, text)
        assert(key == 'achievementPrefix')
        value = text
    end)
    return value
end
assert(prefix(0) == '[新しい住民] ' and prefix(1) == '')
stateChanged('global', titleKey, { ['11'] = '街の住民' })
assert(prefix(0) == '' and prefix(1) == '[街の住民] ')
assert(calls[#calls][1] == 'playernames:configure' and calls[#calls][3] == 'rnme')
nui.selectTitle({ id = 'welcome' }, function(data) assert(data.ok and data.id == 'welcome') end)
lib.callback.await = function() error('timeout') end
nui.getAchievements({}, function(data) assert(data.ok == false and data.error) end)
events.onClientResourceStop('lb-phone')
phoneState = 'stopped'
events.onClientResourceStart('lb-phone')
phoneState = 'started'
events.onClientResourceStart('lb-phone')
assert(app)
events.onClientResourceStop('suimag-achievement')
assert(app == nil and prefix(1) == '')
print('Passed client bridge, title updates, callback errors and restart checks.')
