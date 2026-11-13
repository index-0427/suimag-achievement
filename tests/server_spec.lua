-- Run all local definitions: node tests/run.js (or lua tests/server_spec.lua for the standard definitions).
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local definitionFiles = {}
local paths = #arg > 0 and arg or { 'achievements/00_default.lua' }
for _, path in ipairs(paths) do
    local filename = assert(path:match('^achievements/([^/]+%.lua)$'), 'Unexpected definition path: ' .. path)
    local file = assert(io.open(path, 'r'))
    definitionFiles[filename] = file:read('*a')
    file:close()
end

local function entry(id, extra)
    return ('{ id = %q, name = "配達", description = "配達を3回完了する。", title = "配達人", target = 3, %s }')
        :format(id, extra or '')
end

local function boot(storage, configure)
    local world = { now = 0, storage = storage or {}, players = {}, callbacks = {}, events = {}, api = {}, pushes = {}, threads = {}, characters = {}, queries = 0, logs = {}, files = copy(definitionFiles) }
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
    world.files['__test_delivery.lua'] = 'return {' .. entry('__test_delivery') .. '}'
    env.io = { readdir = function(path)
        assert(path == '@suimag-achievement/achievements')
        local names = {}
        for name in pairs(world.files) do names[#names + 1] = name end
        table.sort(names, function(a, b) return a > b end) -- Deliberately different from display order.
        local index = 0
        return {
            lines = function() return function() index = index + 1; return names[index] end end,
            close = function() world.directoryClosed = true end,
        }
    end }
    env.LoadResourceFile = function(resource, path)
        assert(resource == 'suimag-achievement')
        return world.files[path:match('^achievements/(.+)$')]
    end
    assert(loadfile('config.lua', 't', env))()
    world.env = env
    if configure then configure(world) end
    assert(loadfile('server/main.lua', 't', env))()
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

test('definition errors identify the file, row, achievement and invalid field', function()
    local invalid = {
        { extra = 'id = "delivery 10"', message = 'id must contain' },
        { extra = 'id = "welcome"', message = '(welcome): duplicate id; first defined at achievements/00_default.lua #1' },
        { extra = 'target = 0', message = '(__test_delivery): target' },
        { extra = 'target = 1.5', message = '(__test_delivery): target' },
        { extra = 'name = ""', message = '(__test_delivery): name' },
        { extra = 'description = false', message = '(__test_delivery): description' },
        { extra = 'title = "~r~配達人"', message = '(__test_delivery): title' },
        { extra = 'unit = 1', message = '(__test_delivery): unit' },
        { extra = 'auto = "play_time"', message = '(__test_delivery): auto' },
    }
    for _, case in ipairs(invalid) do
        local ok, err = pcall(boot, nil, function(w)
            w.files['__test_delivery.lua'] = 'return {' .. entry('__test_delivery', case.extra) .. '}'
        end)
        assert(not ok and tostring(err):find('achievements/__test_delivery.lua #1', 1, true), tostring(err))
        assert(tostring(err):find(case.message, 1, true), tostring(err))
    end
end)

test('malformed lists, syntax errors and runtime errors stop before storage or callbacks', function()
    local invalid = {
        { content = 'return false', message = 'return an array' },
        { content = 'return { delivery = ' .. entry('x') .. '}', message = 'not named keys' },
        { content = 'return { [2] = ' .. entry('x') .. '}', message = '#1: expected an achievement table' },
        { content = 'return { "not a table" }', message = '#1: expected an achievement table' },
        { content = 'return {', message = 'achievements/__test_delivery.lua:' },
        { content = 'Config.Achievements = {}', message = 'achievements/__test_delivery.lua:' },
    }
    for _, case in ipairs(invalid) do
        local world
        local ok, err = pcall(boot, nil, function(w)
            world = w
            w.files['__test_delivery.lua'] = case.content
        end)
        assert(not ok and tostring(err):find(case.message, 1, true), tostring(err))
        assert(next(world.storage) == nil and next(world.callbacks) == nil and #world.threads == 0)
    end
end)

test('directory and file read failures are reported before initialization', function()
    local ok, err = pcall(boot, nil, function(w)
        w.env.io.readdir = function() return nil, 'permission denied' end
    end)
    assert(not ok and tostring(err):find('achievements/: permission denied', 1, true), tostring(err))
    ok, err = pcall(boot, nil, function(w) w.env.LoadResourceFile = function() return nil end end)
    assert(not ok and tostring(err):find(': could not read file', 1, true), tostring(err))
end)

test('files merge in filename order and preserve each author list order', function()
    local w = boot(nil, function(world)
        world.files = {
            ['20_bob.lua'] = 'return {' .. entry('bob_first') .. ',' .. entry('bob_second') .. '}',
            ['10_alice.lua'] = 'return {' .. entry('alice') .. '}',
            ['30_empty.lua'] = 'return {}',
            ['README.md'] = 'This is not a Lua file.',
        }
    end)
    assert(w.directoryClosed)
    w:login(1, 'A')
    local entries = w:get(1).achievements
    assert(#entries == 3 and entries[1].id == 'alice' and entries[2].id == 'bob_first' and entries[3].id == 'bob_second')
    assert(w.api.AddProgress(1, 'alice', 1) and w.api.Unlock(1, 'bob_second'))
end)

test('duplicate IDs within one file report both positions', function()
    local ok, err = pcall(boot, nil, function(w)
        w.files['__test_delivery.lua'] = 'return {' .. entry('same') .. ',' .. entry('same') .. '}'
    end)
    assert(not ok and tostring(err):find('achievements/__test_delivery.lua #2 (same): duplicate id', 1, true), tostring(err))
    assert(tostring(err):find('first defined at achievements/__test_delivery.lua #1', 1, true), tostring(err))
end)

test('an empty folder produces an empty achievement list', function()
    local w = boot(nil, function(world) world.files = {} end)
    w:login(1, 'A')
    assert(#w:get(1).achievements == 0)
end)

test('an added author file reaches progress, titles and statistics', function()
    local w = boot(nil, function(world)
        world.files['__test_time.lua'] = 'return {' .. entry('__test_thirty_minutes',
            'name = "街を散策", description = "合計30分滞在する。", title = "散策中", target = 30, auto = "playtime", unit = "分"') .. '}'
    end)
    w.characters = { 'A' }
    w:login(1, 'A')
    assert(not w:select(1, '__test_thirty_minutes').ok)
    w:tick(1800000)
    local added = record(w:get(1), '__test_thirty_minutes')
    assert(added.unlocked and added.progress == 30 and added.target == 30)
    assert(added.name == '街を散策' and added.description == '合計30分滞在する。' and added.unit == '分')
    assert(w:select(1, '__test_thirty_minutes').ok)
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == '散策中')
    w:startStatistics()
    assert(record(w:get(1), '__test_thirty_minutes').unlockedCount == 1)
end)

test('renaming an author file preserves earned progress, dates and selected titles', function()
    local w = boot()
    w:login(1, 'A')
    w.api.Unlock(1, '__test_delivery')
    w:select(1, '__test_delivery')
    local unlockedAt = record(w:get(1), '__test_delivery').unlockedAt
    w.events.onResourceStop('suimag-achievement')
    local restarted = boot(w.storage, function(world)
        world.files['40_author_renamed.lua'] = world.files['__test_delivery.lua']
        world.files['__test_delivery.lua'] = nil
    end)
    restarted:login(1, 'A')
    local saved = record(restarted:get(1), '__test_delivery')
    assert(saved.unlocked and saved.progress == 3 and saved.unlockedAt == unlockedAt)
    assert(restarted:get(1).selected == '__test_delivery')
    assert(restarted.env.GlobalState.suimagAchievementTitles['1'] == '配達人')
end)

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
        assert(not w.api.AddProgress(1, '__test_delivery', amount))
    end
    assert(not w.api.AddProgress(99, '__test_delivery', 1))
    assert(not w.api.AddProgress(1, {}, 1))
    assert(not w.api.Unlock(1, 'unknown'))
    assert(w.api.AddProgress(1, '__test_delivery'))
    assert(record(w:get(1), '__test_delivery').progress == 1)
    assert(not w:select(1, '__test_delivery').ok)
    assert(w.api.AddProgress(1, '__test_delivery', 10))
    local achieved = record(w:get(1), '__test_delivery')
    assert(achieved.progress == 3 and achieved.unlocked)
    assert(w.api.Unlock(1, '__test_delivery'))
    assert(record(w:get(1), '__test_delivery').unlockedAt == achieved.unlockedAt)
    assert(w:select(1, '__test_delivery').ok)
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
    w.api.Unlock(1, '__test_delivery')
    w:select(1, '__test_delivery')
    w.events['QBCore:Server:OnPlayerUnload'](1)
    -- Qbox may still hold the old player while this event is running.
    assert(not w:get(1).ok)
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == nil)
    w:login(1, 'B')
    assert(not record(w:get(1), '__test_delivery').unlocked)
    assert(w:get(1).selected == false)
    w:unload(1)
    w:login(1, 'A')
    assert(w:get(1).selected == '__test_delivery')
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == '配達人')
    w:login(2, 'C')
    assert(not record(w:get(2), '__test_delivery').unlocked)
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
    w.api.Unlock(1, '__test_delivery')
    w:select(1, '__test_delivery')
    w.env.source = 1
    w.events.playerDropped()
    assert(w.env.GlobalState.suimagAchievementTitles['1'] == nil)
    w:login(1, 'B')
    assert(not record(w:get(1), '__test_delivery').unlocked)
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
        ['character:DELETED'] = { progress = { welcome = { value = 1 }, __test_delivery = { value = 3 } }, playSeconds = 0 },
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
    assert(record(result, '__test_delivery').unlockedCount == 0)
    assert(result.statistics.updatedAt == 1700000000)
    assert(result.statistics.counts == nil) -- Only aggregate data leaves the server.
    assert(w.queries == 1)
end)

test('statistics are cached across reads and awards and refreshed every two hours', function()
    local w = boot()
    w.characters = { 'A', 'B' }
    w:login(1, 'A')
    w:startStatistics()
    assert(record(w:get(1), '__test_delivery').unlockedCount == 0)
    w.api.Unlock(1, '__test_delivery')
    for _ = 1, 10 do w:get(1) end
    w:login(1, 'A')
    assert(w.queries == 1 and record(w:get(1), '__test_delivery').unlockedCount == 0)
    w:tick(7200000 - 1)
    assert(w.queries == 1)
    w:tick(1)
    assert(w.queries == 2)
    assert(record(w:get(1), '__test_delivery').unlockedCount == 1)
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
    w.api.Unlock(1, '__test_delivery')
    w.databaseError = true
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == original)
    assert(record(w:get(1), '__test_delivery').unlockedCount == 0)
    w.databaseError = false
    w.storage['character:B'] = 'corrupt'
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == original)
    assert(record(w:get(1), '__test_delivery').unlockedCount == 0)
    w.storage['character:B'] = { progress = { welcome = { value = 'invalid' } }, playSeconds = 0 }
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == original)
    w.storage['character:B'] = nil
    w:tick(7200000)
    assert(record(w:get(1), '__test_delivery').unlockedCount == 1)
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
    w.api.Unlock(1, '__test_delivery')
    w:tick(7200000)
    assert(w:get(1).statistics.updatedAt == updatedAt)
    assert(record(w:get(1), '__test_delivery').unlockedCount == 0)
    w:tick(0)
    assert(record(w:get(1), '__test_delivery').unlockedCount == 1)
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
