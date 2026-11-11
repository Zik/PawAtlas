-- Run from the repository root: lua5.1 tools/test_lifecycle.lua
assert(_VERSION == "Lua 5.1", "This test requires Lua 5.1")

local function equal(actual, expected, scenario)
    assert(actual == expected, ("%s: expected %s, got %s"):format(scenario, tostring(expected), tostring(actual)))
end

local frames, callbackErrors = {}, {}
local frame = {}
function frame:RegisterEvent(event) self.events[event] = true end
function frame:RegisterUnitEvent(event, unit)
    self.events[event] = true
    self.units = self.units or {}
    self.units[event] = unit
end
function frame:UnregisterEvent(event) self.events[event] = nil end
function frame:SetScript(script, handler)
    equal(script, "OnEvent", "frame script")
    self.onEvent = handler
end
function CreateFrame()
    local instance = setmetatable({ events = {} }, { __index = frame })
    frames[#frames + 1] = instance
    return instance
end
function geterrorhandler()
    return function(message) callbackErrors[#callbackErrors + 1] = tostring(message) end
end
function securecallfunction(callback, ...) return callback(...) end
local stockXpcall = xpcall
function xpcall(callback, onError, ...)
    -- Retail's xpcall forwards arguments. Stock Lua 5.1's xpcall only takes two.
    local args, count = { ... }, select("#", ...)
    return stockXpcall(function() return callback(unpack(args, 1, count)) end, onError)
end
local function fire(event, ...)
    for _, instance in ipairs(frames) do
        if instance.events[event] and (not instance.units or not instance.units[event] or instance.units[event] == (...)) then
            instance.onEvent(instance, event, ...)
        end
    end
    assert(#callbackErrors == 0, event .. ": " .. table.concat(callbackErrors, "\n"))
end

local loggedIn, lootGUID, statistic, raidRequests = false, nil, 7, 0
local now, player = 1000, "Player-test"
SlashCmdList = {}
function GetLocale() return "enUS" end
function IsLoggedIn() return loggedIn end
function UnitGUID(unit) if unit == "player" then return player end end
function GetTime() return now end
function GetServerTime() return now end
function GetInstanceInfo() return "Raid", "raid", 16, nil, nil, nil, nil, 101 end
function GetStatistic(id)
    equal(id, 501, "kill statistic ID")
    return tostring(statistic)
end
function GetNumLootItems() return 1 end
function GetLootSourceInfo() if lootGUID then return lootGUID, 1 end end
function RequestRaidInfo() raidRequests = raidRequests + 1 end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 3600 end }
-- This test drives synchronous lifecycle and event dispatch.
C_Timer = { After = function() end }

local boss = { id = 1, countKey = "boss", encounter = 401, map = 101, difficulties = { [16] = true } }
local oldBoss = { id = 2, countKey = "legacy", encounter = 402, difficulties = { [16] = true } }
local rare = { id = 3, countKey = "rare", npcs = { 601 } }
local stage = { key = "mount:4", method = "ENCOUNTER", encounters = { 401 } }
local atlas = {
    mounts = { boss, oldBoss, rare, { id = 4, journalOnly = true } },
    attemptStages = { [4] = { reward = stage } },
    killStatistics = { [5] = { 501 } },
    lootByNPC = { [601] = { rare } },
    lootFrequencies = {},
    lootItems = {},
    lootFrequency = function() return "weekly" end,
}
local planMigrations, snapshots = 0, {}
function atlas.planTargets()
    planMigrations = planMigrations + 1
    equal(atlas.getLocale(), "enUS", "client locale before plan initialization")
    assert(MountAtlasDB.plan[1], "legacy planner data missing")
end
function atlas.capturePlanSnapshot(ready) snapshots[#snapshots + 1] = ready end

-- Follow the production TOC order without loading the catalog or creating UI.
local coreFiles = {
    ["Core/Addon.lua"] = true, ["Core/Locale.lua"] = true,
    ["Core/Tracking.lua"] = true, ["Core/AttemptStages.lua"] = true,
}
local tocPaths, loaded = {}, {}
for path in io.lines("PawAtlas.toc") do
    path = path:match("^%s*(.-)%s*$"):gsub("\\", "/")
    tocPaths[#tocPaths + 1] = path
    if coreFiles[path] or path:match("^Libs/LibStub/.*%.lua$") or path:match("^Libs/CallbackHandler%-1%.0/.*%.lua$")
        or path:match("^Libs/Ace[%a]+%-3%.0/.*%.lua$") then
        assert(loadfile(path))("PawAtlas", atlas)
        loaded[path] = true
    end
end
for path in pairs(coreFiles) do assert(loaded[path], "missing TOC entry: " .. path) end

-- SavedVariables arrive after the Lua files have loaded and before ADDON_LOADED.
MountAtlasDB = {
    kills = { legacy = 4.9, broken = "4" },
    visits = { legacy = { kill = 1900 } },
    lastLoot = { expired = now },
    plan = { [1] = true },
}
MountAtlasAccountDB = {
    settings = { language = "ruRU", chatMessages = false },
    characters = { offline = { stageDaily = { legacy = 1800 } } },
}
fire("ADDON_LOADED", "PawAtlas")
fire("ADDON_LOADED", "OtherAddon")
local character = assert(MountAtlasAccountDB.characters[player], "current character was not initialized")
equal(planMigrations, 1, "planner initialized once")
equal(MountAtlasAccountDB.settings.language, "ruRU", "legacy language setting left intact")
equal(character.kills.legacy, 4, "legacy attempts migrated")
equal(MountAtlasDB.kills.broken, nil, "invalid legacy attempt removed")
equal(MountAtlasDB.lastLoot.expired, nil, "expired corpse GUID removed")
equal(MountAtlasDB.lastAttempts["encounter:legacy:16"], 1900, "saved single-difficulty lock migrated")
equal(MountAtlasAccountDB.stageDaily.legacy, 1800, "legacy account stage lock migrated")
equal(atlas.stageAttemptDefinition(stage.key), stage, "native stages initialized")
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
    local registered = false
    for _, instance in ipairs(frames) do
        if instance.events[event] then
            registered = true
            equal(instance.units and instance.units[event], "player", "spell events only observe player")
        end
    end
    assert(registered, "missing player spell event: " .. event)
end

loggedIn = true
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
equal(raidRequests, 1, "first world entry requests lockouts")
equal(MountAtlasDB.visits.boss.visit, 4600, "first world entry records visit")
equal(character.statistics[5], 7, "first world entry reads character statistic")
equal(snapshots[#snapshots], false, "first world snapshot waits for raid data")

fire("ENCOUNTER_END", 401, "Boss", 16, 20, 0)
equal(character.kills.boss, nil, "failed encounter leaves boss counter unchanged")
equal(atlas.rawStageAttempts(stage.key), 0, "failed encounter leaves stage counter unchanged")
fire("ENCOUNTER_END", 401, "Boss", 16, 20, 1)
equal(character.kills.boss, 1, "successful encounter counts the boss")
equal(atlas.rawStageAttempts(stage.key), 1, "successful encounter reaches native stages")
fire("BOSS_KILL", 401, "Boss")
fire("BOSS_KILL", 402, "Legacy boss")
equal(character.kills.boss, 1, "encounter and boss events count one kill")
equal(atlas.rawStageAttempts(stage.key), 1, "native stage counts the shared events once")
equal(character.kills.legacy, 4, "persisted lock prevents recount after reload")

fire("LOOT_READY")
equal(character.kills.rare, nil, "loot without a source GUID")
lootGUID = "Creature-0-1-2-3-601-000000001"
fire("LOOT_OPENED", false, false)
equal(character.kills.rare, 1, "loot opened resolves the late corpse GUID")
fire("LOOT_READY")
fire("LOOT_OPENED", false, false)
equal(character.kills.rare, 1, "late corpse GUID counts once across loot events")
lootGUID = "Creature-0-1-2-3-601-000000002"
fire("LOOT_OPENED", false, true)
equal(character.kills.rare, 1, "item-origin loot does not count as creature loot")

fire("UPDATE_INSTANCE_INFO")
equal(snapshots[#snapshots], true, "raid data marks snapshots ready")
local snapshotCount = #snapshots
statistic = 9
fire("PLAYER_LOGOUT")
equal(character.statistics[5], 9, "logout saves the latest character statistic")
equal(#snapshots, snapshotCount + 1, "logout saves a planner snapshot")
equal(snapshots[#snapshots], true, "logout preserves raid-data readiness")
print("PawAtlas lifecycle passed: saved data, first world entry, encounter and loot deduplication, logout")

local function checkLocale(clientLocale)
    local environment = setmetatable({
        GetLocale = function() return clientLocale end,
        geterrorhandler = function() return error end,
    }, {
        __index = function(_, key)
            if key ~= "LibStub" then return _G[key] end
        end,
    })
    environment._G = environment
    local localizedAtlas = {}
    for _, path in ipairs(tocPaths) do
        if path == "Core/Tracking.lua" then
            -- Another addon's registration changes AceLocale's shared write target.
            local library = environment.LibStub("AceLocale-3.0")
            library:NewLocale("OtherAddon", "enUS", true)["Попыток: %s"] = "Other: %s"
        end
        if path == "Libs/LibStub/LibStub.lua" or path == "Libs/AceLocale-3.0/AceLocale-3.0.lua"
            or path == "Core/Locale.lua" or path == "Core/Tracking.lua" or path:match("^Locales/enUS_.+%.lua$") then
            setfenv(assert(loadfile(path)), environment)("PawAtlas", localizedAtlas)
        end
    end
    local russian = clientLocale == "ruRU"
    local L = localizedAtlas.L
    equal(localizedAtlas.getLocale(), russian and "ruRU" or "enUS", clientLocale .. " selected locale")
    equal(L("Условие"), russian and "Условие" or "Requirements", clientLocale .. " requirements label")
    equal(L("Попыток: %s", 3), russian and "Попыток: 3" or "Attempts: 3", clientLocale .. " late format string")

    local dynamic = "|Hitem:999999|h[Already localized]|h"
    equal(L(dynamic), dynamic, clientLocale .. " dynamic text remains unchanged")
    local library = environment.LibStub("AceLocale-3.0")
    equal(rawget(library:GetLocale("PawAtlas"), dynamic), nil, clientLocale .. " dynamic text is not cached")
    equal(library:GetLocale("OtherAddon")["Попыток: %s"], "Other: %s", clientLocale .. " other addon dictionary")
end

for _, locale in ipairs({ "ruRU", "enUS", "deDE" }) do checkLocale(locale) end
print("PawAtlas locales passed: ruRU, enUS and English fallback")
