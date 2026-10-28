-- Run from the resource directory: lua tests/server_spec.lua
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function boot(storage)
    local world = { now = 0, storage = storage or {}, players = {}, callbacks = {}, events = {}, api = {}, pushes = {}, threads = {}, characters = {}, queries = 0, logs = {} }
    local env = setmetatable({}, { __index = _G })
    env.GetCurrentResourceName = function() return 'suimag-achievement' end
    env.GetGameTimer = function() return world.now end
    env.os = setmetatable({ time = function() return 1700000000 + math.floor(world.now / 1000) end }, { __index = os })
    env.GetPlayers = function()
        local ids = {}
        for id in pairs(world.players) do ids[#ids + 1] = tostring(id) end
        return ids
    end
    env.GetResourceKvpString = function(key) return copy(world.storage[key]) end
    env.SetResourceKvp = function(key, value) world.storage[key] = copy(value) end
    -- JSON is supplied by FiveM. Copies model the persistence boundary in this harness.
    env.json = {
        encode = copy,
        decode = function(value)
            if value == 'corrupt' then error('invalid JSON') end
            return copy(value)
        end,
    }
    env.GlobalState = {}
    env.lib = { callback = { register = function(name, fn) world.callbacks[name] = fn end } }
    env.exports = setmetatable({
        qbx_core = { GetPlayer = function(_, id) return world.players[id] end },
    }, { __call = function(_, name, fn) world.api[name] = fn end })
    env.TriggerClientEvent = function(...) world.pushes[#world.pushes + 1] = { ... } end
    env.AddEventHandler = function(name, fn) world.events[name] = fn end
    env.RegisterNetEvent = env.AddEventHandler
    local function resume(task)
        local ok, delay = coroutine.resume(task.thread)
        assert(ok, delay)
        task.wakeAt = world.now + (delay or 0)
    end
    env.CreateThread = function(fn)
        local task = { thread = coroutine.create(fn) }
        world.threads[#world.threads + 1] = task
        resume(task)
    end
    env.Wait = function(milliseconds) coroutine.yield(milliseconds) end
    env.print = function(message) world.logs[#world.logs + 1] = message end
    env.MySQL = {
        ready = function(fn) world.databaseReady = fn end,
        query = { await = function(sql)
            assert(sql == 'SELECT citizenid FROM players')
            world.queries = world.queries + 1
            if world.databaseError then error('database unavailable') end
            local rows = {}
            for _, citizenid in ipairs(world.characters) do rows[#rows + 1] = { citizenid = citizenid } end
            return rows
        end },
    }
    assert(loadfile('config.lua', 't', env))()
    env.Config.Achievements[#env.Config.Achievements + 1] = {
        id = 'delivery', name = '配達', description = '配達を3回完了する。',
        title = '配達人', target = 3,
    }
    assert(loadfile('server/main.lua', 't', env))()
    world.env = env
    function world:login(id, citizenid)
        self.players[id] = { PlayerData = { citizenid = citizenid } }
        self.env.source = id
        self.events['QBCore:Server:OnPlayerLoaded']()
    end
    function world:get(id) return self.callbacks['suimag-achievement:get'](id) end
    function world:select(id, title)
        self.now = self.now + 500
        return self.callbacks['suimag-achievement:select'](id, title)
    end
    function world:tick(milliseconds)
        self.now = self.now + milliseconds
        for _, task in ipairs(self.threads) do
            if coroutine.status(task.thread) ~= 'dead' and task.wakeAt <= self.now then resume(task) end
        end
    end
    function world:startStatistics()
        self.env.CreateThread(self.databaseReady)
    end
    function world:unload(id)
        self.events['QBCore:Server:OnPlayerUnload'](id)
        self.players[id] = nil
    end
    return world
end

local function record(snapshot, id)
    for _, entry in ipairs(snapshot.achievements) do if entry.id == id then return entry end end
    error('Missing achievement: ' .. id)
end
local count = 0
local function test(name, fn)
    fn()
    count = count + 1
    print('ok ' .. count .. ' - ' .. name)
end

test('login unlocks once; unknown and locked titles are rejected', function()
    local w = boot()
    assert(not w:get(1).ok)
    w:login(1, 'A')
    local first = record(w:get(1), 'welcome')
    assert(first.unlocked and first.progress == 1 and first.unlockedAt)
    assert(not w:select(1, 'one_hour').ok)
    assert(not w:select(1, 'missing').ok)
    assert(not w:select(1, {}).ok)
    w:login(1, 'A')
    assert(record(w:get(1), 'welcome').unlockedAt == first.unlockedAt)
    assert(w:select(1, 'welcome').ok)
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == '新しい住民')
    assert(not w.callbacks['suimag-achievement:select'](1, '').ok)
    assert(w:select(1, '').ok)
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == nil)
end)

test('server awards validate inputs, cap progress and preserve unlock date', function()
    local w = boot()
    w:login(1, 'A')
    for _, amount in ipairs({ -1, 0, .5, math.huge, 0/0, '3', 2147483648 }) do
        assert(not w.api.AddProgress(1, 'delivery', amount))
    end
    assert(not w.api.AddProgress(99, 'delivery', 1))
    assert(not w.api.AddProgress(1, {}, 1))
    assert(not w.api.Unlock(1, 'unknown'))
    assert(w.api.AddProgress(1, 'delivery'))
    assert(record(w:get(1), 'delivery').progress == 1)
    assert(not w:select(1, 'delivery').ok)
    assert(w.api.AddProgress(1, 'delivery', 10))
    local achieved = record(w:get(1), 'delivery')
    assert(achieved.progress == 3 and achieved.unlocked)
    assert(w.api.Unlock(1, 'delivery'))
    assert(record(w:get(1), 'delivery').unlockedAt == achieved.unlockedAt)
    assert(w:select(1, 'delivery').ok)
    -- No network award events are registered by this resource.
    assert(w.events['suimag-achievement:AddProgress'] == nil)
end)

test('server time counts elapsed login time, not callback or login requests', function()
    local w = boot()
    w:login(1, 'A')
    for _ = 1, 20 do w:get(1); w:login(1, 'A') end
    assert(record(w:get(1), 'one_hour').progress == 0)
    w:tick(59000)
    assert(record(w:get(1), 'one_hour').progress == 0)
    w:tick(1000)
    assert(record(w:get(1), 'one_hour').progress == 1)
    w:tick(3540000)
    assert(record(w:get(1), 'one_hour').unlocked)
    assert(not record(w:get(1), 'ten_hours').unlocked)
end)

test('characters are isolated and unloading clears titles and stale reads', function()
    local w = boot()
    w:login(1, 'A')
    w.api.Unlock(1, 'delivery')
    w:select(1, 'delivery')
    w.events['QBCore:Server:OnPlayerUnload'](1)
    -- Qbox may still hold the old player while this event is running.
    assert(not w:get(1).ok)
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == nil)
    w:login(1, 'B')
    assert(not record(w:get(1), 'delivery').unlocked)
    assert(w:get(1).selected == false)
    w:unload(1)
    w:login(1, 'A')
    assert(w:get(1).selected == 'delivery')
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == '配達人')
    w:login(2, 'C')
    assert(not record(w:get(2), 'delivery').unlocked)
end)

test('resource restart restores title and partial time; offline time is excluded', function()
    local w = boot()
    w:login(1, 'A')
    w:select(1, 'welcome')
    w.now = 59000
    w.events.onResourceStop('suimag-achievement')
    assert(next(w.env.GlobalState.suimagAchievementTitles) == nil)
    local nextWorld = boot(w.storage)
    nextWorld.now = 9000000
    nextWorld:login(1, 'A')
    assert(nextWorld:get(1).selected == 'welcome')
    assert(record(nextWorld:get(1), 'one_hour').progress == 0)
    nextWorld:tick(1000)
    assert(record(nextWorld:get(1), 'one_hour').progress == 1)
end)

test('disconnect and reused server ID do not inherit progress or title', function()
    local w = boot()
    w:login(1, 'A')
    w.api.Unlock(1, 'delivery')
    w:select(1, 'delivery')
    w.env.source = 1
    w.events.playerDropped()
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == nil)
    w:login(1, 'B')
    assert(not record(w:get(1), 'delivery').unlocked)
    assert(w:get(1).selected == false)
end)

test('corrupt persistence is not replaced with empty data', function()
    local w = boot({ ['character:A'] = 'corrupt' })
    w:login(1, 'A')
    assert(not w:get(1).ok)
    assert(w.storage['character:A'] == 'corrupt')
end)

test('statistics include offline and untracked characters but exclude deleted ones', function()
    local w = boot({
        ['character:B'] = { progress = { welcome = { value = 1 }, one_hour = { value = 60 } }, playSeconds = 3600 },
        ['character:DELETED'] = { progress = { welcome = { value = 1 }, delivery = { value = 3 } }, playSeconds = 0 },
    })
    w.characters = { 'A', 'B', 'C' }
    w:login(1, 'A')
    assert(w:get(1).statistics == nil)
    assert(record(w:get(1), 'welcome').unlockedCount == nil)
    w:startStatistics()
    local result = w:get(1)
    assert(result.statistics.totalPlayers == 3 and result.statistics.refreshMinutes == 120)
    assert(record(result, 'welcome').unlockedCount == 2)
    assert(record(result, 'one_hour').unlockedCount == 1)
    assert(record(result, 'delivery').unlockedCount == 0)
    assert(result.statistics.updatedAt == 1700000000)
    assert(result.statistics.counts == nil) -- Only aggregate data leaves the server.
    assert(w.queries == 1)
end)

test('statistics are cached across reads and awards and refreshed every two hours', function()
    local w = boot()
    w.characters = { 'A', 'B' }
    w:login(1, 'A')
    w:startStatistics()
    assert(record(w:get(1), 'delivery').unlockedCount == 0)
    w.api.Unlock(1, 'delivery')
    for _ = 1, 10 do w:get(1) end
    w:login(1, 'A')
    assert(w.queries == 1 and record(w:get(1), 'delivery').unlockedCount == 0)
    w:tick(7200000 - 1)
    assert(w.queries == 1)
    w:tick(1)
    assert(w.queries == 2)
    assert(record(w:get(1), 'delivery').unlockedCount == 1)
    assert(w:get(1).statistics.updatedAt == 1700007200)
    local broadcasts = 0
    for _, push in ipairs(w.pushes) do if push[2] == -1 then broadcasts = broadcasts + 1 end end
    assert(broadcasts == 2)
end)

test('zero players produces a valid zero-count snapshot', function()
    local w = boot()
    w:login(1, 'A')
    w:startStatistics()
    assert(w:get(1).statistics.totalPlayers == 0)
    assert(record(w:get(1), 'welcome').unlockedCount == 0)
end)

test('failed collection keeps the entire previous snapshot and retries next interval', function()
    local w = boot()
    w.characters = { 'A', 'B' }
    w:login(1, 'A')
    w:startStatistics()
    local original = w:get(1).statistics.updatedAt
    w.api.Unlock(1, 'delivery')
    w.databaseError = true
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == original)
    assert(record(w:get(1), 'delivery').unlockedCount == 0)
    w.databaseError = false
    w.storage['character:B'] = 'corrupt'
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == original)
    assert(record(w:get(1), 'delivery').unlockedCount == 0)
    w.storage['character:B'] = { progress = { welcome = { value = 'invalid' } }, playSeconds = 0 }
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == original)
    w.storage['character:B'] = nil
    w:tick(7200000)
    assert(record(w:get(1), 'delivery').unlockedCount == 1)
    assert(w:get(1).statistics.updatedAt > original and #w.logs == 3)
end)

test('first collection failure stays pending until a successful retry', function()
    local w = boot()
    w.characters = { 'A' }
    w:login(1, 'A')
    w.databaseError = true
    w:startStatistics()
    assert(w:get(1).statistics == nil)
    w.databaseError = false
    w:tick(7200000)
    assert(w:get(1).statistics.totalPlayers == 1)
end)

test('large collections yield without exposing partial counts', function()
    local w = boot()
    w:login(1, 'A')
    for index = 1, 200 do w.characters[index] = 'offline_' .. index end
    w.characters[201] = 'A'
    w:startStatistics()
    assert(w:get(1).statistics == nil)
    w:tick(0)
    assert(w:get(1).statistics.totalPlayers == 201)
    assert(record(w:get(1), 'welcome').unlockedCount == 1)
    local updatedAt = w:get(1).statistics.updatedAt
    w.api.Unlock(1, 'delivery')
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == updatedAt)
    assert(record(w:get(1), 'delivery').unlockedCount == 0)
    w:tick(0)
    assert(record(w:get(1), 'delivery').unlockedCount == 1)
end)

test('configured collection interval is respected', function()
    local w = boot()
    w.env.Config.StatisticsRefreshMinutes = 5
    w:startStatistics()
    w:tick(300000 - 1)
    assert(w.queries == 1)
    w:tick(1)
    assert(w.queries == 2)
end)

print(('Passed %d server scenarios.'):format(count))
