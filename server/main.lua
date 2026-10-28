local resourceName = GetCurrentResourceName()
local titleKey = 'suimagAchievementTitles'
local sessions, titles, definitions, unloaded = {}, {}, {}, {}
local statistics

local function isInteger(value)
    return type(value) == 'number' and value == value and value >= 0
        and value < math.huge and value % 1 == 0
end

assert(isInteger(Config.StatisticsRefreshMinutes) and Config.StatisticsRefreshMinutes > 0,
    'StatisticsRefreshMinutes must be a positive integer')

for _, definition in ipairs(Config.Achievements) do
    assert(type(definition.id) == 'string' and definition.id:match('^[%w_%-]+$'), 'Invalid achievement id')
    assert(not definitions[definition.id], 'Duplicate achievement id: ' .. definition.id)
    assert(isInteger(definition.target) and definition.target > 0, 'Invalid achievement target')
    assert(type(definition.name) == 'string' and type(definition.description) == 'string', 'Invalid achievement text')
    assert(type(definition.title) == 'string' and definition.title ~= ''
        and not definition.title:find('[~\r\n]'), 'Invalid title (no GTA formatting codes or line breaks)')
    assert(definition.auto == nil or definition.auto == 'join' or definition.auto == 'playtime', 'Invalid auto type')
    definitions[definition.id] = definition
end

local function publishTitle(playerId, session)
    local selected = session and definitions[session.data.selected]
    local record = selected and session.data.progress[selected.id]
    local title = record and record.value >= selected.target and selected.title or nil
    local key = tostring(playerId)
    if titles[key] == title then return end
    titles[key] = title
    GlobalState[titleKey] = titles
end

local function save(session)
    SetResourceKvp('character:' .. session.citizenid, json.encode(session.data))
end

local function setProgress(session, definition, value)
    local record = session.data.progress[definition.id] or { value = 0 }
    value = math.min(definition.target, value)
    if value <= record.value then return false end
    record.value = value
    if value >= definition.target and not record.unlockedAt then record.unlockedAt = os.time() end
    session.data.progress[definition.id] = record
    return true
end

local function accountTime(session)
    local now = GetGameTimer()
    local seconds = math.max(0, math.floor((now - session.lastTick) / 1000))
    session.lastTick = now
    session.data.playSeconds = session.data.playSeconds + seconds
    for _, definition in ipairs(Config.Achievements) do
        if definition.auto == 'playtime' then
            setProgress(session, definition, math.floor(session.data.playSeconds / 60))
        end
    end
end

local function release(playerId)
    local session = sessions[playerId]
    if session then
        accountTime(session)
        save(session)
    end
    sessions[playerId] = nil
    publishTitle(playerId)
end

local function getSession(playerId)
    playerId = tonumber(playerId)
    if not isInteger(playerId) or playerId < 1 or unloaded[playerId] then return nil end
    local player = exports.qbx_core:GetPlayer(playerId)
    local citizenid = player and player.PlayerData.citizenid
    local session = sessions[playerId]
    if session and session.citizenid ~= citizenid then
        release(playerId)
        session = nil
    end
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end
    if session then return session end

    local data = { progress = {}, playSeconds = 0 }
    local encoded = GetResourceKvpString('character:' .. citizenid)
    if encoded then
        local ok, decoded = pcall(json.decode, encoded)
        if not ok or type(decoded) ~= 'table' or type(decoded.progress) ~= 'table'
            or not isInteger(decoded.playSeconds) then
            print(('[%s] Invalid saved data for %s; left untouched.'):format(resourceName, citizenid))
            return nil
        end
        data = decoded
        for _, record in pairs(data.progress) do
            if type(record) ~= 'table' or not isInteger(record.value)
                or (record.unlockedAt ~= nil and not isInteger(record.unlockedAt)) then
                print(('[%s] Invalid saved progress for %s; left untouched.'):format(resourceName, citizenid))
                return nil
            end
        end
        if type(data.selected) ~= 'string' then data.selected = nil end
    end

    session = { citizenid = citizenid, data = data, lastTick = GetGameTimer() }
    sessions[playerId] = session
    for _, definition in ipairs(Config.Achievements) do
        if definition.auto == 'join' then setProgress(session, definition, definition.target) end
    end
    local selected = definitions[data.selected]
    local record = selected and data.progress[selected.id]
    if not record or record.value < selected.target then data.selected = nil end
    save(session)
    publishTitle(playerId, session)
    return session
end

-- The denominator is all Qbox characters, including offline characters without KVP data.
-- Deleted characters are excluded from both numerator and denominator.
local function collectStatistics()
    local players = MySQL.query.await('SELECT citizenid FROM players')
    assert(type(players) == 'table', 'Could not read the Qbox player list')
    local counts = {}
    for _, definition in ipairs(Config.Achievements) do counts[definition.id] = 0 end

    for index, player in ipairs(players) do
        local encoded = GetResourceKvpString('character:' .. player.citizenid)
        if encoded then
            local data = json.decode(encoded)
            assert(type(data) == 'table' and type(data.progress) == 'table',
                'Invalid saved progress for ' .. player.citizenid)
            for _, definition in ipairs(Config.Achievements) do
                local record = data.progress[definition.id]
                if record ~= nil then
                    assert(type(record) == 'table' and isInteger(record.value),
                        'Invalid saved progress for ' .. player.citizenid)
                    if record.value >= definition.target then
                        counts[definition.id] = counts[definition.id] + 1
                    end
                end
            end
        end
        -- Avoid blocking the game thread while scanning a large population.
        if index % 200 == 0 then Wait(0) end
    end

    return { counts = counts, totalPlayers = #players, updatedAt = os.time() }
end

local function snapshot(session)
    local achievements = {}
    for _, definition in ipairs(Config.Achievements) do
        local record = session.data.progress[definition.id] or { value = 0 }
        achievements[#achievements + 1] = {
            id = definition.id,
            name = definition.name,
            description = definition.description,
            title = definition.title,
            target = definition.target,
            unit = definition.unit or '回',
            progress = math.min(record.value, definition.target),
            unlocked = record.value >= definition.target,
            unlockedAt = record.unlockedAt,
            unlockedCount = statistics and statistics.counts[definition.id],
        }
    end
    return {
        ok = true,
        achievements = achievements,
        selected = session.data.selected or false,
        statistics = statistics and {
            totalPlayers = statistics.totalPlayers,
            updatedAt = statistics.updatedAt,
            refreshMinutes = Config.StatisticsRefreshMinutes,
        },
    }
end

lib.callback.register('suimag-achievement:get', function(source)
    local session = getSession(source)
    if not session then return { ok = false, error = 'キャラクターの実績を読み込めませんでした。' } end
    return snapshot(session)
end)

lib.callback.register('suimag-achievement:select', function(source, id)
    if type(id) ~= 'string' then return { ok = false, error = '称号の指定が正しくありません。' } end
    local session = getSession(source)
    if not session then return { ok = false, error = 'キャラクターの実績を読み込めませんでした。' } end
    if id ~= '' then
        local definition = definitions[id]
        local record = session.data.progress[id]
        if not definition or not record or record.value < definition.target then
            return { ok = false, error = 'まだ獲得していない称号です。' }
        end
    end
    local selected = id ~= '' and id or nil
    if session.data.selected == selected then return snapshot(session) end
    local now = GetGameTimer()
    if session.lastSelection and now - session.lastSelection < 500 then
        return { ok = false, error = '少し待ってから称号を変更してください。' }
    end
    session.lastSelection = now
    session.data.selected = selected
    save(session)
    publishTitle(source, session)
    return snapshot(session)
end)

-- Server exports only: the client cannot award achievements or submit progress.
local function addProgress(playerId, id, amount)
    playerId = tonumber(playerId)
    local definition = type(id) == 'string' and definitions[id]
    if not definition then return false, 'unknown_achievement' end
    amount = amount == nil and 1 or amount
    if not isInteger(amount) or amount < 1 or amount > 2147483647 then return false, 'invalid_amount' end
    local session = getSession(playerId)
    if not session then return false, 'player_unavailable' end
    local record = session.data.progress[id]
    if setProgress(session, definition, (record and record.value or 0) + amount) then
        save(session)
        TriggerClientEvent('suimag-achievement:refresh', playerId)
    end
    return true
end

exports('AddProgress', addProgress)
exports('Unlock', function(playerId, id)
    local definition = type(id) == 'string' and definitions[id]
    if not definition then return false, 'unknown_achievement' end
    return addProgress(playerId, id, definition.target)
end)

RegisterNetEvent('QBCore:Server:OnPlayerLoaded', function()
    unloaded[source] = nil
    getSession(source)
    TriggerClientEvent('suimag-achievement:refresh', source)
end)

AddEventHandler('QBCore:Server:OnPlayerUnload', function(playerId)
    playerId = tonumber(playerId)
    if not playerId then return end
    unloaded[playerId] = true
    release(playerId)
    TriggerClientEvent('suimag-achievement:refresh', playerId)
end)

AddEventHandler('playerDropped', function()
    release(source)
    unloaded[source] = nil
end)

GlobalState[titleKey] = {}
CreateThread(function()
    for _, playerId in ipairs(GetPlayers()) do getSession(tonumber(playerId)) end
    while true do
        Wait(60000)
        for playerId, session in pairs(sessions) do
            local current = getSession(playerId)
            if current == session then
                accountTime(session)
                save(session)
                TriggerClientEvent('suimag-achievement:refresh', playerId)
            end
        end
    end
end)

MySQL.ready(function()
    while true do
        local ok, result = pcall(collectStatistics)
        if ok then
            -- Publish a complete batch; never expose partially updated counts.
            statistics = result
            TriggerClientEvent('suimag-achievement:refresh', -1)
        else
            print(('[%s] Achievement statistics refresh failed; keeping the previous result: %s')
                :format(resourceName, tostring(result)))
        end
        Wait(Config.StatisticsRefreshMinutes * 60000)
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= resourceName then return end
    for _, session in pairs(sessions) do accountTime(session); save(session) end
    GlobalState[titleKey] = {}
end)
