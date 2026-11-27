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

local loggedIn, lootGUID, statistic, raidRequests = false, nil, 11, 0
local massLoot
local now, player = 1000, "Player-test"
local playerClass
SlashCmdList = {}
function GetLocale() return "enUS" end
function IsLoggedIn() return loggedIn end
function UnitGUID(unit) if unit == "player" then return player end end
function UnitClass(unit) if unit == "player" then return "Localized class", playerClass end end
function GetTime() return now end
function GetServerTime() return now end
function GetInstanceInfo() return "Raid", "raid", 16, nil, nil, nil, nil, 101 end
function GetStatistic(id)
    equal(id, 12763, "King Dazar kill statistic ID")
    return tostring(statistic)
end
function GetNumLootItems() return massLoot and #massLoot or 1 end
function GetLootSourceInfo(slot)
    if massLoot then return unpack(massLoot[slot]) end
    if lootGUID then return lootGUID, 1 end
end
function RequestRaidInfo() raidRequests = raidRequests + 1 end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 3600 end }
local refreshTimers = {}
C_Timer = { After = function(delay, callback)
    if delay == 0 then refreshTimers[#refreshTimers + 1] = callback end
end }

local boss = { id = 1, countKey = "boss", encounter = 401, map = 101, difficulties = { [16] = true } }
local oldBoss = { id = 2, countKey = "legacy", encounter = 402, difficulties = { [16] = true } }
local rare = { id = 3, countKey = "rare", npcs = { 601 } }
local stage = { key = "mount:4", method = "ENCOUNTER", encounters = { 401 } }
local stageRare = { key = "mount:6", method = "NPC", npcs = { 601 } }
local stageZone = { key = "mount:7", method = "ZONE", zones = { 1536 } }
local statisticCatalog = {}
assert(loadfile("Data/Rares.lua"))("PawAtlas", statisticCatalog)
assert(loadfile("Data/JournalData.lua"))("PawAtlas", statisticCatalog)
assert(loadfile("Data/LootSources.lua"))("PawAtlas", statisticCatalog)
assert(loadfile("Data/Mounts.lua"))("PawAtlas", statisticCatalog)
local gorespineStage = statisticCatalog.attemptStages[1373].reward
local gorespine = { id = 1373, countKey = "1373", name = gorespineStage.name, npcs = gorespineStage.npcs }
local bloodtusk = statisticCatalog.lootByNPC[162819][1]
local atlas = {
    mounts = { boss, oldBoss, rare, { id = 4, journalOnly = true }, gorespine, bloodtusk },
    attemptStages = { [4] = { reward = stage }, [6] = { reward = stageRare }, [7] = { reward = stageZone },
        [1372] = statisticCatalog.attemptStages[1372], [1373] = { reward = gorespineStage } },
    killStatistics = { [1040] = { 12763 } },
    killStatisticSources = statisticCatalog.killStatisticSources,
    lootByNPC = { [601] = { rare }, [162690] = { gorespine }, [162819] = statisticCatalog.lootByNPC[162819] },
    lootFrequencies = { [1373] = "daily", [1372] = statisticCatalog.lootFrequencies[1372] },
    npcLootQuests = { [1372] = statisticCatalog.npcLootQuests[1372] },
    lootItems = {},
    lootFrequency = function() return "weekly" end,
}
local planMigrations, detailRefreshes, snapshots = 0, 0, {}
function atlas.planTargets()
    planMigrations = planMigrations + 1
    equal(atlas.getLocale(), "enUS", "client locale before plan initialization")
    assert(MountAtlasDB.plan[1], "legacy planner data missing")
end
function atlas.capturePlanSnapshot(ready) snapshots[#snapshots + 1] = ready end
function atlas.refreshDetails() detailRefreshes = detailRefreshes + 1 end

-- Follow the production TOC order without loading the catalog or creating UI.
local coreFiles = {
    ["Core/Addon.lua"] = true, ["Core/Locale.lua"] = true,
    ["Core/Tracking.lua"] = true, ["Core/AttemptStages.lua"] = true,
    ["Locales/enUS_Sources.lua"] = true,
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
equal(character.class, nil, "unavailable current class stays unknown")
equal(MountAtlasAccountDB.characters.offline.class, nil, "offline character class is not inferred")
equal(planMigrations, 1, "planner initialized once")
equal(MountAtlasAccountDB.settings.language, "ruRU", "legacy language setting left intact")
equal(character.kills.legacy, 4, "legacy attempts migrated")
equal(MountAtlasDB.kills.broken, nil, "invalid legacy attempt removed")
equal(MountAtlasDB.lastLoot.expired, nil, "expired corpse GUID removed")
equal(MountAtlasDB.lastAttempts["encounter:legacy:16"], 1900, "saved single-difficulty lock migrated")
equal(MountAtlasAccountDB.stageDaily.legacy, 1800, "legacy account stage lock migrated")
equal(atlas.stageAttemptDefinition(stage.key), stage, "native stages initialized")
for _, event in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
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
playerClass = "MAGE"
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
equal(character.class, "MAGE", "login enriches the current character class")
for _, entry in ipairs(atlas.accountCharacters()) do
    equal(entry.class, entry.guid == player and "MAGE" or nil, "account roster exposes only known class tokens")
end
playerClass = nil
atlas.currentAttemptCharacter()
equal(character.class, "MAGE", "unavailable API preserves the last known class")
equal(raidRequests, 1, "first world entry requests lockouts")
equal(MountAtlasDB.visits.boss.visit, 4600, "first world entry records visit")
equal(character.statistics[1040], 11, "first world entry reads character statistic")
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
equal(atlas.rawStageAttempts(stageRare.key), 1, "late corpse GUID reaches the stage without a journal entry")
fire("LOOT_READY")
fire("LOOT_OPENED", false, false)
equal(character.kills.rare, 1, "late corpse GUID counts once across loot events")
lootGUID = "Creature-0-1-2-3-601-000000002"
fire("LOOT_OPENED", false, true)
equal(character.kills.rare, 1, "item-origin loot does not count as creature loot")
equal(atlas.rawStageAttempts(stageRare.key), 1, "item-origin loot does not count as a creature stage")

fire("LOOT_CLOSED")
massLoot = {}
for slot = 1, 8 do
    massLoot[slot] = { lootGUID, 1, "Creature-0-1-2-3-601-000000003", 1 }
end
fire("LOOT_READY")
fire("LOOT_OPENED", false, false)
fire("LOOT_CLOSED")
massLoot = nil
equal(character.kills.rare, 3, "mass loot immediately tracks each distinct corpse once")
equal(atlas.rawStageAttempts(stageRare.key), 3, "mass loot immediately saves the matching stages")
equal(#refreshTimers, 1, "native and stage updates share one pending refresh")
equal(detailRefreshes, 1, "loot events do not redraw synchronously")
table.remove(refreshTimers, 1)()
equal(detailRefreshes, 2, "mass loot redraws once")
equal(#snapshots, 2, "mass loot captures one planner snapshot")

fire("UPDATE_INSTANCE_INFO")
equal(snapshots[#snapshots], true, "raid data marks snapshots ready")

do
    local chat, timers = {}, {}
    local previousTime = now
    local oldGUID, oldDead, oldAttack, oldIsPlayer = UnitGUID, UnitIsDead, UnitCanAttack, UnitIsPlayer
    local oldClassification, oldCanLoot, oldFishing = UnitClassification, CanLootUnit, IsFishingLoot
    local oldSecret = issecretvalue
    local oldJournal, oldFrame, oldAfter, oldDailyReset = C_MountJournal, DEFAULT_CHAT_FRAME, C_Timer.After, C_DateAndTime.GetSecondsUntilDailyReset
    local settings = MountAtlasAccountDB.settings
    local oldChat, oldFormat = settings.chatMessages, settings.chatMessageFormat
    local ownershipMount = gorespine.id
    local target, mouseover, dead, hostile, playerTarget, hasLoot, canLoot, ownership
    UnitGUID = function(unit)
        if unit == "target" then return target end
        if unit == "mouseover" then return mouseover end
        return oldGUID(unit)
    end
    UnitIsDead = function(unit) return (unit == "target" or unit == "mouseover") and dead end
    UnitCanAttack = function(unit, other) return unit == "player" and (other == "target" or other == "mouseover") and hostile end
    UnitIsPlayer = function(unit) return (unit == "target" or unit == "mouseover") and playerTarget end
    UnitClassification = function() return "rare" end
    IsFishingLoot = function() return false end
    local restrictedLoot = {}
    issecretvalue = function(value) return value == restrictedLoot or (oldSecret and oldSecret(value)) end
    CanLootUnit = function(guid)
        if guid == target or guid == mouseover then return hasLoot, canLoot end
    end
    C_MountJournal = { GetMountInfoByID = function(id)
        equal(id, ownershipMount, "only the attempted mount needs an ownership lookup")
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ownership
    end }
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) chat[#chat + 1] = line end }
    C_Timer.After = function(delay, callback)
        if delay > 0 then timers[#timers + 1] = callback else oldAfter(delay, callback) end
    end
    C_DateAndTime.GetSecondsUntilDailyReset = function() return 3600 end
    settings.chatMessages, settings.chatMessageFormat = true, "{mount} #{attempts}"

    local first = "Creature-0-1-2-3-162690-000000001"
    local second = "Creature-0-1-2-3-162690-000000002"
    local other = "Creature-0-1-2-3-601-000000004"
    local function selectCorpse(guid)
        target, mouseover, dead, hostile, playerTarget = guid, guid, true, true, false
        hasLoot, canLoot = true, true
    end
    local function finishAutoloot(fromItem, slots)
        massLoot = slots or {}
        fire("LOOT_OPENED", true, fromItem)
        fire("LOOT_CLOSED")
    end
    local function autoloot(slots, fromItem, drained)
        massLoot = slots
        fire("LOOT_READY", true)
        if drained then hasLoot, canLoot = false, false end
        finishAutoloot(fromItem == true)
    end

    selectCorpse(first)
    autoloot({ {} })
    equal(atlas.rawKills(gorespine), 0, "matching target and cursor cannot credit another world loot window")

    massLoot = { {} }
    fire("LOOT_READY", true)
    hasLoot, canLoot = nil, nil
    finishAutoloot(false)
    equal(atlas.rawKills(gorespine), 0, "unavailable loot state cannot prove the selected corpse was looted")

    selectCorpse(first)
    massLoot = { {} }
    fire("LOOT_READY", true)
    hasLoot, canLoot = restrictedLoot, restrictedLoot
    fire("UNIT_LOOT", first, restrictedLoot)
    finishAutoloot(false)
    equal(atlas.rawKills(gorespine), 0, "restricted loot state cannot prove an attempt")

    selectCorpse(first)
    canLoot = restrictedLoot
    autoloot({ {} }, false, true)
    equal(atlas.rawKills(gorespine), 0, "depletion requires known personal loot access before it")

    selectCorpse(first)
    massLoot = { {} }
    fire("LOOT_READY", false)
    hasLoot, canLoot = false, false
    fire("UNIT_LOOT", first, false)
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 0, "manual loot still needs a confirmed world loot window")

    selectCorpse(first)
    massLoot = { {}, {} }
    fire("LOOT_READY", true)
    fire("LOOT_READY", true)
    equal(atlas.rawKills(gorespine), 0, "fallback waits for confirmed world loot")
    hasLoot, canLoot = false, false
    finishAutoloot(false)
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 1, "autoloot credits the target corpse when source GUIDs are missing and slots are already clear")
    equal(atlas.rawStageAttempts(gorespineStage.key), 0, "Gorespine keeps a single counter in Tracking")
    equal(#chat, 0, "cold ownership defers the attempt message")
    equal(#timers, 1, "the saved attempt schedules one chat retry")
    ownership = false
    timers[1]()
    equal(chat[1], "Кровоспин #1", "the saved attempt announces without opening the catalog")

    selectCorpse("Creature-0-1-2-3-162690-000000009")
    autoloot({ {} }, false, true)
    equal(atlas.rawKills(gorespine), 1, "a second corpse cannot bypass the daily limit")
    equal(#chat, 1, "repeat delivery and a locked opening produce no additional message")
    settings.chatMessages = false
    now = now + 3601
    selectCorpse(first)
    autoloot({ { first, 1 } })
    equal(atlas.rawKills(gorespine), 1, "the precise GUID cannot recredit the same corpse after the daily reset")

    selectCorpse(second)
    autoloot({ {} }, true, true)
    equal(atlas.rawKills(gorespine), 1, "a container from the bag cannot use the corpse fallback")
    selectCorpse(second)
    autoloot({}, false, true)
    equal(atlas.rawKills(gorespine), 1, "a loot window with no slots does not prove a corpse was looted")
    selectCorpse(second)
    massLoot = { {} }
    fire("LOOT_READY", true)
    hasLoot, canLoot = false, false
    finishAutoloot(false, { { "GameObject-0-1-2-3-354175-000000021", 1 } })
    equal(atlas.rawKills(gorespine), 1, "a different exact world source overrides a pending corpse fallback")

    selectCorpse(second)
    dead = false
    autoloot({ {} }, false, true)
    equal(atlas.rawKills(gorespine), 1, "pickpocketing a live target cannot count a corpse attempt")
    selectCorpse(second)
    dead, hostile = true, false
    autoloot({ {} }, false, true)
    equal(atlas.rawKills(gorespine), 1, "a non-attackable unit cannot stand in for a loot source")
    selectCorpse(second)
    canLoot = false
    autoloot({ {} }, false, true)
    equal(atlas.rawKills(gorespine), 1, "a corpse the player cannot loot is not evidence for the fallback")
    selectCorpse(second)
    mouseover = other
    autoloot({ {} }, false, true)
    equal(atlas.rawKills(gorespine), 1, "different target and mouseover GUIDs cannot identify one corpse")

    selectCorpse(second)
    massLoot = { {} }
    fire("LOOT_READY", true)
    selectCorpse(first)
    fire("PLAYER_TARGET_CHANGED")
    selectCorpse(second)
    fire("PLAYER_TARGET_CHANGED")
    hasLoot, canLoot = false, false
    finishAutoloot(false)
    equal(atlas.rawKills(gorespine), 1, "returning to a previous target cannot reuse stale loot evidence")

    target, mouseover = nil, nil
    autoloot({ {} })
    equal(atlas.rawKills(gorespine), 1, "an empty source list without a corpse cannot add an attempt")
    autoloot({ { second, 1, other, 1 }, { second, 1, other, 1 } })
    equal(atlas.rawKills(gorespine), 2, "precise area loot counts a new corpse once without a target")
    equal(atlas.rawStageAttempts(stageRare.key), 4, "the same area loot reaches stage-only mounts")

    selectCorpse("Creature-0-1-2-3-601-000000005")
    massLoot = {}
    fire("LOOT_OPENED", true, false)
    massLoot = { {} }
    fire("LOOT_READY", true)
    hasLoot, canLoot = false, false
    fire("LOOT_CLOSED")
    equal(atlas.rawStageAttempts(stageRare.key), 5, "stage-only mounts count when world confirmation arrives before the slots")

    now = now + 3601
    local third = "Creature-0-1-2-3-162690-000000003"
    selectCorpse(third)
    mouseover = nil
    autoloot({ {} })
    equal(atlas.rawKills(gorespine), 2, "a selected corpse alone does not identify the source of world loot")
    massLoot = { {} }
    fire("LOOT_READY", true)
    massLoot = {}
    fire("LOOT_OPENED", true, false)
    equal(atlas.rawKills(gorespine), 2, "keyboard interaction waits for the selected corpse to lose loot")
    hasLoot, canLoot = nil, nil
    fire("UNIT_LOOT", other, false)
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 2, "another corpse losing loot cannot confirm the selected target")

    selectCorpse(third)
    mouseover = nil
    massLoot = { {} }
    fire("LOOT_READY", true)
    massLoot = {}
    fire("LOOT_OPENED", true, false)
    fire("UNIT_LOOT", third, false)
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 2, "the selected corpse remaining lootable invalidates a depletion event")

    massLoot = { {} }
    fire("LOOT_READY", true)
    massLoot = {}
    fire("LOOT_OPENED", true, false)
    hasLoot, canLoot = nil, nil
    fire("UNIT_LOOT", third, false)
    fire("UNIT_LOOT", third, true)
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 2, "a later native lootable update cancels an earlier depletion event")

    selectCorpse(third)
    mouseover = nil
    massLoot = { {} }
    fire("LOOT_READY", true)
    massLoot = {}
    fire("LOOT_OPENED", true, false)
    hasLoot, canLoot = nil, nil
    fire("UNIT_LOOT", third, false)
    fire("LOOT_CLOSED")
    fire("UNIT_LOOT", third, false)
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 3, "keyboard interaction can confirm the same selected corpse")

    now = now + 3601
    local fourth = "Creature-0-1-2-3-162690-000000004"
    target, mouseover, dead, hostile, playerTarget = nil, fourth, true, true, false
    hasLoot, canLoot, massLoot = true, true, { {} }
    fire("LOOT_READY", true)
    massLoot = {}
    fire("LOOT_OPENED", true, false)
    mouseover, hasLoot, canLoot = nil, false, false
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 3, "moving away without a GUID-specific depletion event cannot count a mouseover corpse")

    local fifth = "Creature-0-1-2-3-162690-000000005"
    target, mouseover, dead, hostile, playerTarget = nil, fifth, true, true, false
    hasLoot, canLoot, massLoot = true, true, { {} }
    settings.chatMessages = true
    local beforeMouseoverMessage = #chat
    local beforeMouseoverRetry = #timers
    fire("LOOT_READY", true)
    equal(atlas.rawKills(gorespine), 3, "mouse-over identity alone does not count before loot depletion")
    massLoot = {}
    fire("LOOT_OPENED", true, false)
    fire("UNIT_LOOT", fifth, false)
    hasLoot, canLoot = false, false
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 4, "an empty-target mouseover corpse counts after its exact depletion event")
    equal(#timers, beforeMouseoverRetry + 1, "the confirmed mouseover kill schedules one ownership-aware notification")
    timers[#timers]()
    equal(#chat, beforeMouseoverMessage + 1, "a confirmed mouseover corpse announces exactly one attempt")
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 4, "duplicate close cannot recount a confirmed mouseover corpse")

    now = now + 3601
    local sixth = "Creature-0-1-2-3-162690-000000006"
    target, mouseover, hasLoot, canLoot = "Player-bystander", sixth, true, true
    massLoot = { {} }
    fire("LOOT_READY", true)
    hasLoot, canLoot = false, false
    fire("UNIT_LOOT", sixth, false)
    table.remove(refreshTimers)()
    equal(atlas.rawKills(gorespine), 5, "ready-only autoloot accepts a different selected target with the exact mouseover GUID")
    timers[#timers]()
    equal(#chat, beforeMouseoverMessage + 2, "ready-only autoloot announces one attempt")
    massLoot = { { sixth, 1 } }
    fire("LOOT_READY", true)
    finishAutoloot(false)
    equal(atlas.rawKills(gorespine), 5, "late loot source and close cannot recount the ready-only attempt")

    now = now + 3601
    local seventh = "Creature-0-1-2-3-162690-000000007"
    mouseover, hasLoot, canLoot, massLoot = seventh, true, true, { {} }
    fire("LOOT_READY", true)
    hasLoot, canLoot = false, false
    fire("UNIT_LOOT", seventh, false)
    fire("LOOT_OPENED", true, true)
    table.remove(refreshTimers)()
    fire("LOOT_CLOSED")
    equal(atlas.rawKills(gorespine), 5, "a later bag window vetoes a pending ready-only corpse")

    local oldInstance, oldTap, oldThreat = IsInInstance, UnitIsTapDenied, UnitThreatSituation
    local oldInGroup, oldGroupCount = IsInGroup, GetNumGroupMembers
    local oldMap = C_Map
    local corpseGUID = UnitGUID
    local member, pet, petTarget = "Player-group-member", "Pet-test"
    local inInstance, denied, petThreat = false, false, nil
    IsInInstance = function() return inInstance end
    UnitIsTapDenied = function() return denied end
    UnitThreatSituation = function(unit, other)
        if unit == "pet" and other == "pettarget" then return petThreat end
    end
    IsInGroup = function() return true end
    GetNumGroupMembers = function() return 2 end
    C_Map = { GetBestMapForUnit = function() return 1536 end }
    UnitGUID = function(unit)
        if unit == "party1" then return member end
        if unit == "pet" then return pet end
        if unit == "pettarget" then return petTarget end
        return corpseGUID(unit)
    end
    settings.chatMessages = false
    local beforeRare, beforeStage = atlas.rawKills(rare), atlas.rawStageAttempts(stageRare.key)
    selectCorpse("Creature-0-1-2-3-601-000000011")
    fire("PARTY_KILL", member, target)
    equal(atlas.rawKills(rare), beforeRare + 1, "a known group kill counts before looting")
    equal(atlas.rawStageAttempts(stageRare.key), beforeStage + 1, "a known group kill reaches compatible NPC stages")
    equal(atlas.rawStageAttempts(stageZone.key), 0, "a group kill alone does not advance a loot-only zone stage")
    fire("PARTY_KILL", member, target)
    autoloot({ { target, 1 } })
    equal(atlas.rawKills(rare), beforeRare + 1, "duplicate group kill and exact loot use the same kill count")
    equal(atlas.rawStageAttempts(stageRare.key), beforeStage + 1, "duplicate group kill and exact loot use one NPC stage count")
    equal(atlas.rawStageAttempts(stageZone.key), 1, "the same corpse can still provide an independent zone loot attempt")

    selectCorpse("Creature-0-1-2-3-601-000000012")
    autoloot({ { target, 1 } })
    fire("PARTY_KILL", player, target)
    equal(atlas.rawKills(rare), beforeRare + 2, "exact loot arriving first prevents duplicate player kill credit")
    equal(atlas.rawStageAttempts(stageRare.key), beforeStage + 2, "exact loot arriving first prevents duplicate NPC stage credit")

    selectCorpse("Creature-0-1-2-3-601-000000013")
    denied = true
    fire("PARTY_KILL", player, target)
    selectCorpse("Creature-0-1-2-3-601-000000014")
    denied = restrictedLoot
    fire("PARTY_KILL", member, target)
    selectCorpse("Creature-0-1-2-3-601-000000015")
    denied, inInstance = false, true
    fire("PARTY_KILL", member, target)
    inInstance = false
    fire("PARTY_KILL", restrictedLoot, target)
    fire("PARTY_KILL", player, restrictedLoot)
    fire("UNIT_DIED", target)
    equal(atlas.rawKills(rare), beforeRare + 2, "foreign taps, secret events, instance kills and unrelated deaths cannot award an outdoor attempt")

    selectCorpse("Creature-0-1-2-3-601-000000016")
    petTarget, petThreat, hasLoot, canLoot = target, 0, false, false
    fire("UNIT_TARGET", "pet")
    petTarget = nil
    fire("UNIT_DIED", target)
    fire("UNIT_DIED", target)
    timers[#timers]()
    equal(atlas.rawKills(rare), beforeRare + 3, "death of the pet's confirmed recent combat target counts once")
    equal(atlas.rawStageAttempts(stageRare.key), beforeStage + 3, "the same pet kill reaches the NPC stage once")

    selectCorpse("Creature-0-1-2-3-601-000000017")
    petTarget, petThreat = target, 0
    fire("UNIT_DIED", target)
    fire("PARTY_KILL", "Player-stranger", target)
    timers[#timers]()
    equal(atlas.rawKills(rare), beforeRare + 3, "the exact attacker event can rule out an apparent pet kill")

    local oldQuestLog = C_QuestLog
    local completed = true
    C_QuestLog = { IsQuestFlaggedCompleted = function(id)
        equal(id, 58889, "Mal'Korak uses the real personal loot quest")
        return completed
    end }
    ownershipMount, settings.chatMessages = bloodtusk.id, true
    local beforeBloodtusk = #chat
    selectCorpse("Creature-0-1-2-3-162819-000000020")
    dead = false
    fire("PLAYER_TARGET_CHANGED")
    dead = true
    fire("PARTY_KILL", player, target)
    autoloot({ { target, 1 } })
    equal(atlas.rawKills(bloodtusk), 0, "Mal'Korak already locked before death earns no attempt, even with generic loot")

    now, completed = now + 3601, false
    local eligibleBloodtusk = "Creature-0-1-2-3-162819-000000021"
    selectCorpse(eligibleBloodtusk)
    dead = false
    fire("PLAYER_TARGET_CHANGED")
    dead, completed = true, true
    fire("PARTY_KILL", player, target)
    equal(atlas.rawKills(bloodtusk), 1, "Mal'Korak earns an attempt if the loot quest flips before the kill event")
    autoloot({ { target, 1 } })
    equal(atlas.rawKills(bloodtusk), 1, "the same Mal'Korak GUID is counted once across kill and loot")
    equal(chat[beforeBloodtusk + 1], "Обугленный кровобивень #1", "Mal'Korak announces with the catalog closed")
    equal(#chat, beforeBloodtusk + 1, "kill and loot send just one attempt message")

    selectCorpse("Creature-0-1-2-3-162819-000000022")
    completed = nil
    autoloot({ { target, 1 } })
    equal(atlas.rawKills(bloodtusk), 1, "Mal'Korak's local daily lock works with the quest flag unavailable")

    now, completed = now + 3601, false
    selectCorpse(eligibleBloodtusk)
    fire("PARTY_KILL", player, target)
    equal(atlas.rawKills(bloodtusk), 1, "daily reset does not make the former Mal'Korak GUID new")
    selectCorpse("Creature-0-1-2-3-162819-000000023")
    completed = true
    fire("PARTY_KILL", player, target)
    equal(atlas.rawKills(bloodtusk), 1, "Mal'Korak's completed flag without a live sample is ambiguous")
    autoloot({ { target, 1 } })
    timers[#timers]()
    equal(atlas.rawKills(bloodtusk), 2, "personal loot can confirm the next day's Mal'Korak attempt")
    equal(#chat, beforeBloodtusk + 2, "the next day's personal loot sends one attempt message")

    C_QuestLog, C_Map = oldQuestLog, oldMap
    IsInInstance, UnitIsTapDenied, UnitThreatSituation = oldInstance, oldTap, oldThreat
    IsInGroup, GetNumGroupMembers = oldInGroup, oldGroupCount
    now, massLoot = previousTime, nil
    UnitGUID, UnitIsDead, UnitCanAttack, UnitIsPlayer = oldGUID, oldDead, oldAttack, oldIsPlayer
    UnitClassification, CanLootUnit, IsFishingLoot = oldClassification, oldCanLoot, oldFishing
    issecretvalue = oldSecret
    C_MountJournal, DEFAULT_CHAT_FRAME, C_Timer.After, C_DateAndTime.GetSecondsUntilDailyReset = oldJournal, oldFrame, oldAfter, oldDailyReset
    settings.chatMessages, settings.chatMessageFormat = oldChat, oldFormat
    print("PawAtlas creature loot passed: area loot, corpse fallback, deduplication, daily lock and chat")
end

do
    local chat, lookups, known = {}, 0, {}
    local settings = MountAtlasAccountDB.settings
    local oldChat, oldFormat = settings.chatMessages, settings.chatMessageFormat
    local oldFrame, oldAfter = DEFAULT_CHAT_FRAME, C_Timer.After
    settings.chatMessages, settings.chatMessageFormat = true, "{mount} #{attempts}"
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
    atlas.mountByID = function(id) return known[id] end
    atlas.resolveJournalMount = function(id)
        equal(id, 1040, "only the mount for the changed statistic is requested")
        lookups = lookups + 1
        known[id] = { id = id, name = "Tomb Stalker", journalOnly = true }
        return known[id]
    end
    C_Timer.After = function(delay, callback)
        if delay >= 2 then callback() end
    end
    fire("PLAYER_REGEN_DISABLED")
    fire("PLAYER_REGEN_ENABLED")
    equal(lookups, 0, "unchanged statistics leave the journal cold")
    statistic = 12
    fire("PLAYER_REGEN_ENABLED")
    fire("PLAYER_REGEN_ENABLED")
    equal(character.statistics[1040], 12, "post-combat scan saves the new Dazar total")
    equal(chat[1], "Tomb Stalker #12", "a journal-only boss announces without opening the catalog")
    equal(#chat, 1, "post-combat retries announce the same increase once")
    equal(lookups, 1, "one exact journal lookup for the new attempt")
    atlas.mountByID, atlas.resolveJournalMount = nil, nil
    DEFAULT_CHAT_FRAME, C_Timer.After = oldFrame, oldAfter
    settings.chatMessages, settings.chatMessageFormat = oldChat, oldFormat
end
do
    local catalog = {}
    assert(loadfile("Data/JournalData.lua"))("PawAtlas", catalog)
    local totals = { [8146] = 20, [8147] = 17 }
    local namesReady, ownership = {}, { [542] = false }
    local messages, timers = {}, {}
    local oldStatistic, oldJournal, oldFrame, oldAfter = GetStatistic, C_MountJournal, DEFAULT_CHAT_FRAME, C_Timer.After
    local settings = MountAtlasAccountDB.settings
    local oldChat, oldFormat = settings.chatMessages, settings.chatMessageFormat
    settings.chatMessages, settings.chatMessageFormat = true, "{mount} #{attempts}"
    GetStatistic = function(id) return totals[id] and tostring(totals[id]) or oldStatistic(id) end
    C_MountJournal = { GetMountInfoByID = function(id)
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ownership[id]
    end }
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[message] = (messages[message] or 0) + 1 end }
    atlas.resolveJournalMount = function(id)
        if namesReady[id] then return { id = id, journalOnly = true, name = catalog.englishNames[id] } end
    end
    C_Timer.After = function(delay, callback)
        if delay == 2 then callback()
        elseif delay == 1 then timers[#timers + 1] = callback end
    end
    for _, id in ipairs({ 542, 533 }) do
        atlas.killStatistics[id] = catalog.killStatistics[id]
        atlas.attemptStages[id] = catalog.attemptStages[id]
        atlas.lootItems[id] = catalog.lootItems[id]
    end
    fire("PLAYER_REGEN_ENABLED")
    totals[8146], totals[8147] = 21, 18
    fire("PLAYER_REGEN_ENABLED")
    fire("PLAYER_REGEN_ENABLED")
    equal(character.statistics[542], 21, "Nalak's kill is saved before his mount name loads")
    equal(character.statistics[533], 18, "Oondasta's kill is saved before ownership loads")
    assert(not next(messages), "pending journal data must not print a guessed notification")
    equal(#timers, 2, "only the two missing journal responses need retries")
    namesReady[542], namesReady[533], ownership[533] = true, true, false
    for _, callback in ipairs(timers) do callback() end
    fire("PLAYER_REGEN_ENABLED")
    for id, count in pairs({ [542] = 21, [533] = 18 }) do
        equal(messages[catalog.englishNames[id] .. " #" .. count], 1, "one delayed world boss notification")
        equal(character.statistics[id], count, "chat retries do not increment the kill statistic")
    end
    timers, ownership[533] = {}, nil
    totals[8147] = 19
    fire("PLAYER_REGEN_ENABLED")
    ownership[533] = true
    equal(#timers, 1, "only Oondasta's ownership is pending")
    timers[1]()
    equal(character.statistics[533], 19, "the owned mount retains its kill statistic")
    equal(messages[catalog.englishNames[533] .. " #19"], nil, "acquisition suppresses the pending attempt line")
    for _, id in ipairs({ 542, 533 }) do
        atlas.killStatistics[id], atlas.attemptStages[id], atlas.lootItems[id] = nil, nil, nil
    end
    atlas.resolveJournalMount = nil
    GetStatistic, C_MountJournal, DEFAULT_CHAT_FRAME, C_Timer.After = oldStatistic, oldJournal, oldFrame, oldAfter
    settings.chatMessages, settings.chatMessageFormat = oldChat, oldFormat
end
do
    local id = 478 -- Astral Cloud Serpent
    local totals, chat, brokerCredits, importDelta = {}, {}, 0, 0
    local oldInfo, oldStatistic, oldAfter, oldFrame = GetInstanceInfo, GetStatistic, C_Timer.After, DEFAULT_CHAT_FRAME
    local oldChat, oldFormat = MountAtlasAccountDB.settings.chatMessages, MountAtlasAccountDB.settings.chatMessageFormat
    local oldCredit, oldImport = atlas.recordBrokerAttempt, atlas.recordImportedStatistic
    local mode, started = 3, now
    local scans = {}
    GetInstanceInfo = function() return "Vaults", "raid", mode, nil, nil, nil, nil, 1008 end
    for _, stat in ipairs(statisticCatalog.killStatistics[id]) do totals[stat] = "--" end
    GetStatistic = function(stat) return totals[stat] or oldStatistic(stat) end
    C_Timer.After = function(delay, callback) if delay == 2 then scans[#scans + 1] = callback end end
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) chat[#chat + 1] = line end }
    MountAtlasAccountDB.settings.chatMessages, MountAtlasAccountDB.settings.chatMessageFormat = true, "{mount} #{attempts}"
    atlas.killStatistics[id] = statisticCatalog.killStatistics[id]
    atlas.lootItems[id] = statisticCatalog.lootItems[id]
    atlas.attemptStages[id] = statisticCatalog.attemptStages[id]
    local mount = { id = id, name = statisticCatalog.englishNames[id], journalOnly = true }
    atlas.resolveJournalMount = function(mid) equal(mid, id, "only Elegon needs a journal lookup"); return mount end
    atlas.recordBrokerAttempt = function(ids)
        if ids == id or type(ids) == "table" and ids[id] then brokerCredits = brokerCredits + 1 end
    end
    atlas.recordImportedStatistic = function(mid, _, delta) if mid == id then importDelta = importDelta + delta end end
    local units = { { creatureID = 60410 } }
    local function checkScans()
        now = now + 2
        for _, callback in ipairs(scans) do callback() end
        scans = {}
    end
    equal(atlas.rawKills(mount), 0, "a fresh character has no recorded Elegon kills")
    fire("ENCOUNTER_END", 1500, "Elegon", 3, 10, 0, units)
    fire("ENCOUNTER_END", 1499, "Another encounter", 3, 10, 1, { { creatureID = 1 } })
    fire("ENCOUNTER_END", 1500, "Elegon", 7, 25, 1, units)
    totals[6797] = "1"
    equal(atlas.rawKills(mount), 1, "the native total may arrive before the victory event")
    equal(#chat, 0, "neither a wipe, an unrelated boss nor an ineligible difficulty credits Elegon")
    now = now + 7
    fire("ENCOUNTER_END", 1500, "Elegon", 3, 10, 1, units)
    fire("BOSS_KILL", 1500, "Elegon")
    fire("PARTY_KILL", player, "Creature-0-1-2-3-60410-00001")
    checkScans()
    equal(chat[1], "Astral Cloud Serpent #1", "first Elegon kill before opening the journal")
    equal(brokerCredits, 1, "duplicate victory signals select one Broker target")
    equal(importDelta, 1, "duplicate victory signals add one to imported history")
    -- The 25-player kill has the opposite event order and a new per-mode statistic.
    now, mode = now + 25, 4
    fire("ENCOUNTER_END", 1500, "Elegon", 4, 25, 1, units)
    checkScans()
    equal(#chat, 1, "a victory alone does not add a mount attempt")
    totals[6797], totals[7923], totals[7924] = "--", "1", "unavailable"
    fire("PLAYER_REGEN_ENABLED")
    checkScans()
    equal(chat[2], "Astral Cloud Serpent #2", "the first kill on a second difficulty is credited")
    equal(brokerCredits, 2, "one Broker credit per confirmed roll")
    equal(importDelta, 2, "each native first kill contributes once after import")
    totals[6798] = "9"
    equal(atlas.rawKills(mount), 11, "late historical data repairs the raw total")
    equal(#chat, 2, "loading an old statistic does not print new attempts")
    now = started
    atlas.resolveJournalMount = nil
    atlas.killStatistics[id], atlas.lootItems[id], atlas.attemptStages[id] = nil, nil, nil
    atlas.recordBrokerAttempt, atlas.recordImportedStatistic = oldCredit, oldImport
    GetInstanceInfo, GetStatistic, C_Timer.After, DEFAULT_CHAT_FRAME = oldInfo, oldStatistic, oldAfter, oldFrame
    MountAtlasAccountDB.settings.chatMessages, MountAtlasAccountDB.settings.chatMessageFormat = oldChat, oldFormat
end
local snapshotCount = #snapshots
statistic = 13
fire("PLAYER_LOGOUT")
equal(character.statistics[1040], 13, "logout saves the latest character statistic")
equal(#snapshots, snapshotCount + 1, "logout saves a planner snapshot")
equal(snapshots[#snapshots], true, "logout preserves raid-data readiness")
print("PawAtlas lifecycle passed: saved data, first world entry, encounter and loot deduplication, logout")

do
    local getInstanceInfo, characterDB = GetInstanceInfo, MountAtlasDB
    local previousChatFrame, chat = DEFAULT_CHAT_FRAME, {}
    local settings = MountAtlasAccountDB.settings
    local previousChatSetting = settings.chatMessages
    local map, instanceType, cardRefreshes = 1813, "scenario", 0
    function GetInstanceInfo() return "Instance", instanceType, 38, nil, nil, nil, nil, map end
    function atlas.refreshIslandExpeditionDetails() cardRefreshes = cardRefreshes + 1 end
    local previousStageAttempts = atlas.rawStageAttempts(stage.key)
    DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
    settings.chatMessages = true

    equal(atlas.islandExpeditionCompletions(), 0, "old saves do not imply island history")
    fire("PLAYER_ENTERING_WORLD")
    fire("LFG_COMPLETION_REWARD")
    fire("ISLAND_COMPLETED", 100, 1)
    fire("ISLAND_COMPLETED", 1897, 1)
    equal(atlas.islandExpeditionCompletions(), 0, "entry, rewards and nonmatching maps do not count")
    map = nil
    fire("ISLAND_COMPLETED", 1813, 0)
    equal(atlas.islandExpeditionCompletions(), 1, "the completion event identifies the island while instance data loads")
    map = 1813
    fire("ISLAND_COMPLETED", 1813, 0)
    equal(atlas.islandExpeditionCompletions(), 1, "completion counts once regardless of winner")
    equal(cardRefreshes, 1, "completion refreshes the island card immediately")
    equal(atlas.rawStageAttempts(stage.key), previousStageAttempts, "completion leaves mount attempts intact")
    equal(#chat, 1, "duplicate completion prints once")
    equal(chat[1], "PawAtlas: Expeditions completed: 1", "expedition message uses the shared localized label")

    fire("PLAYER_LOGOUT")
    MountAtlasDB = { completedIslandMap = characterDB.completedIslandMap }
    map = 0
    fire("PLAYER_ENTERING_WORLD", true, true)
    map = 1813
    fire("ISLAND_COMPLETED", 1813, 0)
    equal(atlas.islandExpeditionCompletions(), 1, "saved character marker survives a reload on the island")

    map, instanceType = 0, "none"
    fire("PLAYER_ENTERING_WORLD")
    fire("ISLAND_COMPLETED", 1813, 0)
    equal(atlas.islandExpeditionCompletions(), 1, "exit and off-map completion do not count")
    map, instanceType = 1813, "scenario"
    fire("PLAYER_ENTERING_WORLD")
    fire("ISLAND_COMPLETED", 1813, 1)
    equal(atlas.islandExpeditionCompletions(), 2, "another run of the same island counts")
    map = 2124
    fire("PLAYER_ENTERING_WORLD")
    fire("ISLAND_COMPLETED", 2124, 1)
    equal(atlas.islandExpeditionCompletions(), 3, "a different island adds to the same total")

    local mainIslandDB = MountAtlasDB
    MountAtlasDB = {}
    player = "Player-islands"
    settings.chatMessages = false
    fire("PLAYER_ENTERING_WORLD", true, false)
    fire("ISLAND_COMPLETED", 2124, 1)
    equal(atlas.islandExpeditionCompletions(), 4, "another character adds to the same account total")
    equal(cardRefreshes, 4, "only credited completions refresh the island card")
    equal(#chat, 3, "muting attempt chat still tracks completions")
    equal(chat[3], "PawAtlas: Expeditions completed: 3", "chat shows the running account total")

    assert(atlas.removeAccountCharacter(player), "remove current expedition character")
    equal(atlas.islandExpeditionCompletions(), 3, "removing one character subtracts their contribution")
    settings.chatMessages = true
    map = 1813
    fire("PLAYER_ENTERING_WORLD")
    fire("ISLAND_COMPLETED", 1813, 1)
    equal(MountAtlasAccountDB.characters[player], nil, "completion does not recreate a removed character")
    equal(atlas.islandExpeditionCompletions(), 3, "suppressed completion does not change the total")
    equal(#chat, 3, "suppressed completion does not announce")
    equal(cardRefreshes, 4, "suppressed completion does not redraw the card")

    player, MountAtlasDB, map = "Player-test", mainIslandDB, 2124
    MountAtlasAccountDB.characters.offline.islandExpeditionCompletions = 7
    assert(atlas.clearAttemptStatistics(), "clear account-wide attempt statistics")
    equal(atlas.islandExpeditionCompletions(), 0, "reset clears current and offline character histories")
    fire("ISLAND_COMPLETED", 2124, 1)
    equal(atlas.islandExpeditionCompletions(), 0, "reset does not allow recounting the completed island")
    map = 1813
    fire("PLAYER_ENTERING_WORLD")
    fire("ISLAND_COMPLETED", 1813, 1)
    equal(atlas.islandExpeditionCompletions(), 1, "a new run starts the account total after reset")
    equal(chat[4], "PawAtlas: Expeditions completed: 1", "new completions announce the post-reset total")

    player, GetInstanceInfo, MountAtlasDB = "Player-test", getInstanceInfo, characterDB
    DEFAULT_CHAT_FRAME, settings.chatMessages = previousChatFrame, previousChatSetting
    atlas.refreshIslandExpeditionDetails = nil
    print("PawAtlas island expeditions passed: completion, saved deduplication, account total, chat, deletion and reset")
end

do
    local callback, modeFrame, combat, instance, active, desired, chromie, canToggle, inArea, toggles, redraws
    combat, instance, active, desired, chromie, canToggle, inArea, toggles, redraws = false, false, false, false, false, true, true, 0, 0
    local env = setmetatable({ C_PvP = {}, C_PlayerInfo = {} }, { __index = _G })
    env.CreateFrame = function()
        modeFrame = { events={}, units={}, RegisterEvent=function(self,event) self.events[event]=true end,
            RegisterUnitEvent=function(self,event,unit) self.events[event]=true; self.units[event]=unit end,
            SetScript=function(_,_,fn) callback=fn end }
        return modeFrame
    end
    env.InCombatLockdown = function() return combat end
    env.UnitAffectingCombat = function() return combat end
    env.IsInInstance = function() return instance end
    env.C_PvP = { IsWarModeActive=function() return active end, IsWarModeDesired=function() return desired end,
        CanToggleWarMode=function(target) equal(target,not desired,"toggle follows native desired state"); return canToggle end,
        CanToggleWarModeInArea=function() return inArea end,
        ToggleWarMode=function() toggles=toggles+1 end }
    env.C_PlayerInfo = { IsPlayerInChromieTime=function() return chromie end }
    env.UnitChromieTimeID = function(unit) equal(unit,"player","timeline uses current player"); return 6 end
    env.C_ChromieTime = { GetChromieTimeExpansionOption=function(id) return {id=id,name="Timeline"} end }
    local modes = { addTranslations=function() end, refreshCharacterModes=function() redraws=redraws+1 end }
    setfenv(assert(loadfile("Core/Tracking.lua")), env)("PawAtlas", modes)
    equal(modeFrame.units.UNIT_PHASE,"player","phase events only observe current player")
    assert(modeFrame.events.PLAYER_FLAGS_CHANGED,"native player flag event is registered")
    local state=modes.currentCharacterModes()
    equal(state.warModeActive,false,"confirmed disabled war mode")
    equal(state.warModeDesired,false,"confirmed opt-out stays distinct from unknown")
    equal(state.chromieTimeActive,false,"confirmed inactive Chromie time")
    equal(state.chromieTimeID,nil,"inactive Chromie time has no stale timeline")
    callback(nil,"PLAYER_ENTERING_WORLD")
    local before=redraws
    callback(nil,"WAR_MODE_STATUS_UPDATE")
    equal(redraws,before,"duplicate mode event avoids redraw")
    active,desired,chromie=true,false,true
    callback(nil,"PLAYER_FLAGS_CHANGED","target")
    equal(redraws,before,"another unit's flag event cannot refresh current modes")
    callback(nil,"UNIT_PHASE","player")
    state=modes.currentCharacterModes()
    equal(state.warModeActive,true,"active and desired states are distinct")
    equal(state.warModeDesired,false,"pending desired state remains distinct")
    equal(state.chromieTimeName,"Timeline","exact native timeline name")
    assert(modes.toggleWarMode() and toggles==1,"permitted hardware handler invokes native toggle once")
    combat=true
    equal(select(2,modes.toggleWarMode()),"combat","combat blocks toggle")
    combat,active,desired=false,true,true
    callback(nil,"PLAYER_REGEN_ENABLED")
    before=redraws
    instance,active=true,false
    callback(nil,"PLAYER_ENTERING_WORLD")
    equal(redraws,before+1,"entering the instance refreshes the current modes")
    state=modes.currentCharacterModes()
    equal(state.warModeDesired,true,"instance entrance preserves the character's War Mode opt-in")
    equal(state.warModeActive,false,"War Mode is inactive in the instance")
    equal(state.warModeCanToggle,false,"toggle is blocked in the instance")
    equal(state.warModeToggleReason,"instance","instance explains why the toggle is blocked")
    equal(select(2,modes.toggleWarMode()),"instance","instance blocks toggle")

    desired=nil
    state=modes.currentCharacterModes()
    equal(state.warModeDesired,nil,"unavailable preference does not reuse the previous opt-in")
    equal(state.warModeToggleReason,"instance","instance remains a known restriction with unavailable preference")
    equal(select(2,modes.toggleWarMode()),"instance","unavailable preference does not mask the instance")

    before=redraws
    instance,active,desired=false,true,true
    callback(nil,"PLAYER_ENTERING_WORLD")
    equal(redraws,before+1,"leaving the instance refreshes the current modes")
    state=modes.currentCharacterModes()
    equal(state.warModeDesired,true,"selected War Mode persists outside the instance")
    equal(state.warModeActive,true,"active War Mode returns outside the instance")
    equal(state.warModeCanToggle,true,"toggle permission is checked again outside the instance")

    active,desired=false,true
    env.issecretvalue=function(value) return value==true end
    state=modes.currentCharacterModes()
    equal(state.warModeDesired,nil,"unreadable native preference stays unknown")
    equal(state.warModeToggleReason,"unknown","unreadable preference cannot grant toggle permission")
    env.issecretvalue=nil
    instance,canToggle,inArea=false,false,false
    equal(select(2,modes.toggleWarMode()),"area","native location restriction blocks toggle")
    for _, event in ipairs({ "PLAYER_UPDATE_RESTING", "PLAYER_LEVEL_UP" }) do
        assert(modeFrame.events[event],"native permission event is registered")
        canToggle=false
        callback(nil,"ZONE_CHANGED")
        before=redraws
        callback(nil,event)
        equal(redraws,before+1,"tooltip refreshes without a permission change on "..event)
        canToggle=true
        callback(nil,event)
        equal(redraws,before+2,"native permission change refreshes on "..event)
    end
    canToggle,inArea=nil,true
    equal(select(2,modes.toggleWarMode()),"unknown","unavailable native permission stays unknown")
    equal(toggles,1,"rejected toggles never call native action")
    env.C_PvP,env.C_PlayerInfo={},{}
    state=modes.currentCharacterModes()
    equal(state.warModeActive,nil,"missing war mode API stays unknown")
    equal(state.chromieTimeActive,nil,"missing Chromie API stays unknown")
    equal(select(2,modes.toggleWarMode()),"unknown","unknown native permission blocks action")
    print("PawAtlas current modes passed: current player, unknown data, desired state, event deduplication and native toggle restrictions")
end

do
    local catalog = {}
    for _, path in ipairs({ "Data/Rares.lua", "Data/JournalData.lua", "Data/LootSources.lua" }) do
        assert(loadfile(path))("PawAtlas", catalog)
    end
    local handlers, messages, source, mouseover, tooltip = {}, {}, nil, nil, nil
    local lootSlotsWithoutSource = 0
    local sceneTime, covenant = now, 0
    local bagCount, bagReads, requests, boxSpell = 3, 0, 0, nil
    local starterCount
    local character = {}
    local account = { settings = {}, characters = { player = character } }
    local env = setmetatable({ MountAtlasAccountDB = account, MountAtlasDB = { lastAttempts = {} } }, { __index = _G })
    env._G, env.LOOT_ITEM_SELF = env, "You receive loot: %s."
    env.CreateFrame = function()
        return { RegisterEvent = function() end, RegisterUnitEvent = function() end,
            SetScript = function(_, _, callback) handlers[#handlers + 1] = callback end }
    end
    env.UnitGUID = function(unit) if unit == "mouseover" then return mouseover else return "player" end end
    env.C_MountJournal = { GetMountInfoByID = function() return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false end }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
    env.GameTooltipTextLeft1 = { GetText = function() return tooltip end }
    env.GetTime = function() return sceneTime end
    env.GetServerTime = env.GetTime
    env.C_Map = { GetBestMapForUnit = function() return 2413 end }
    local chatTimers = {}
    env.C_Timer = { After = function(delay, callback)
        if delay == .2 then chatTimers[#chatTimers + 1] = callback else C_Timer.After(delay, callback) end
    end }
    local function flushLootChat()
        while #chatTimers > 0 do table.remove(chatTimers, 1)() end
    end
    env.C_QuestLog = { IsQuestFlaggedCompletedOnAccount = function(id) return id == 90474 end }
    env.C_Covenants = { GetActiveCovenantID = function() return covenant end }
    env.C_Item = {
        GetItemCount = function(id, bank)
            if id == 900001 and not bank then bagReads = bagReads + 1; return bagCount end
            if id == 187282 and not bank then return starterCount end
        end,
        GetItemSpell = function(id) if id == 900001 then return "Container spell", boxSpell end end,
        RequestLoadItemDataByID = function() requests = requests + 1 end,
    }
    env.GetNumLootItems = function() return source and 1 or lootSlotsWithoutSource end
    env.GetLootSourceInfo = function()
        if type(source) == "table" then return unpack(source) end
        return source, 1
    end
    env.IsFishingLoot = function() return false end
    env.C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
    local testAtlas = { mounts = {}, attemptStages = {}, killStatistics = {}, attemptSpells = catalog.attemptSpells,
        attemptNodeNames = catalog.attemptNodeNames, currentAttemptCharacter = function() return character end,
        addTranslations = function() end, usesKillAPI = function() return false end,
        L = function(value) return value end, getLocale = function() return "ruRU" end }
    for _, id in ipairs({ 400, 1395, 1426, 1493, 2159, 2749 }) do
        if id ~= 1426 then testAtlas.mounts[#testAtlas.mounts + 1] = { id = id } end
        testAtlas.attemptStages[id] = catalog.attemptStages[id]
    end
    testAtlas.attemptStages[900] = { reward = { key = "mount:900", method = "USE", items = { 900001 } } }
    testAtlas.planStageOpportunityKey = function(mount, definition)
        if mount.id == 1426 then return "stage:" .. definition.key .. ":daily", "daily" end
    end
    setfenv(assert(loadfile("Core/AttemptStages.lua")), env)("PawAtlas", testAtlas)
    testAtlas.initializeAttemptStages()
    local function event(name, ...) handlers[1](nil, name, ...) end

    local initialRequests = requests
    assert(initialRequests > 0, "initialization requests tracked item data")
    event("PLAYER_ENTERING_WORLD")
    equal(requests, initialRequests, "world entry reuses the static item index")
    equal(bagReads, 2, "initialization and world entry sample current inventory")
    event("LOOT_OPENED", false, false)
    event("LOOT_CLOSED")
    equal(bagReads, 2, "ordinary loot close does not rescan tracked boxes")
    event("LOOT_OPENED", false, true)
    bagCount = 2
    event("BAG_UPDATE_DELAYED")
    local readsAfterFirst = bagReads
    event("LOOT_CLOSED")
    equal(bagReads, readsAfterFirst, "loot close reuses confirmed bag-update result")
    equal(testAtlas.rawStageAttempts("mount:900"), 1, "first box counts once")
    event("LOOT_OPENED", false, true)
    bagCount = 1
    event("LOOT_CLOSED")
    equal(testAtlas.rawStageAttempts("mount:900"), 2, "second box counts immediately when close precedes the delayed event")
    event("BAG_UPDATE_DELAYED")
    equal(testAtlas.rawStageAttempts("mount:900"), 2, "late bag update cannot duplicate a box")
    event("LOOT_OPENED", false, true)
    event("LOOT_CLOSED")
    event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 123)
    bagCount = 0
    event("LOOT_OPENED", false, true)
    event("BAG_UPDATE_DELAYED")
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 123)
    event("BAG_UPDATE_DELAYED")
    equal(testAtlas.rawStageAttempts("mount:900"), 2, "bank transfers cannot use an old item-loot window")
    bagCount = 2
    event("BAG_UPDATE_DELAYED")
    event("LOOT_OPENED", false, true)
    event("LOOT_CLOSED")
    bagCount = 1
    event("BAG_UPDATE_DELAYED")
    equal(testAtlas.rawStageAttempts("mount:900"), 3, "unresolved close leaves the later bag decrease eligible")
    boxSpell = 900002
    event("ITEM_DATA_LOAD_RESULT", 900001, true)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-container", boxSpell)
    bagCount = 0
    event("BAG_UPDATE_DELAYED")
    equal(testAtlas.rawStageAttempts("mount:900"), 4, "late item metadata supports a container cast without a loot window")

    -- A zone corpse maintains the existing statistic but is not proof of a
    -- skyshard receipt, and must not emit an incomplete collection message.
    source = "Creature-0-1-2-3-12345-000000001"
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("item:255826"), 1, "skyshard zone statistic retained")
    equal(#messages, 0, "unknown collection rate stays silent")
    testAtlas.attemptStages[2749].item.rate = 100
    source = "Creature-0-1-2-3-12345-000000002"
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("item:255826"), 2, "known collection rate still counts")
    flushLootChat()
    equal(#messages, 1, "known collection rate still announces")
    testAtlas.attemptStages[2749].item.rate = nil
    testAtlas.attemptStages[2749].item.required = 1
    source = "Creature-0-1-2-3-12345-000000003"
    event("LOOT_READY")
    flushLootChat()
    equal(#messages, 2, "ordinary unknown-rate drop still announces")
    testAtlas.attemptStages[2749].item.required = 500

    -- Both figurines are encounters with a figurine, not Dormus kills.
    for i, npc in ipairs({ 50410, 50409 }) do
        mouseover = "Creature-0-1-2-3-" .. npc .. "-000000001"
        event("UPDATE_MOUSEOVER_UNIT")
        event("UPDATE_MOUSEOVER_UNIT")
        equal(testAtlas.rewardAttemptProgress({ id = 400 }).attempts, i, "one attempt per figurine GUID")
    end
    equal(testAtlas.rewardAttemptProgress({ id = 400 }).event, "MOUSEOVER", "figurine progress identifies its event")
    event("PLAYER_ENTERING_WORLD")
    event("UPDATE_MOUSEOVER_UNIT")
    equal(testAtlas.rawStageAttempts("mount:400"), 2, "figurine GUID survives world entry")

    local before = #messages
    tooltip = "Unrelated tooltip"
    event("CURSOR_CHANGED")
    source = "GameObject-0-1-2-3-354175-000000001"
    event("LOOT_READY")
    event("LOOT_READY")
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 1, "loot source identifies a cache without opening cast or tooltip")
    flushLootChat()
    equal(#messages, before, "cache chat waits while the loot window is open")
    event("LOOT_CLOSED")
    flushLootChat()
    equal(#messages, before + 1, "cache attempt announces once after collection")
    source = "GameObject-0-1-2-3-354175-000000002"
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 1, "the cache respects its daily limit before the catalog opens")
    event("LOOT_CLOSED")

    sceneTime = sceneTime + 3601
    source = nil -- This event sequence exposes only the localized tooltip and cast.
    lootSlotsWithoutSource = 1
    tooltip = catalog.attemptNodeNames["Cache of the Ascended"]
    event("CURSOR_CHANGED")
    event("UNIT_SPELLCAST_START", "player", "Cast-cache", 3365)
    tooltip = "Unrelated tooltip"
    event("CURSOR_CHANGED")
    tooltip = nil
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-cache", 3365)
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("mount:1426"), 2, "localized opening with no visible loot GUID records on LOOT_READY")
    source = "GameObject-0-1-2-3-354175-000000002"
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 2, "opening retains localized chest name across unrelated tooltips")
    event("LOOT_CLOSED")
    flushLootChat()
    equal(#messages, before + 2, "late exact GUID does not duplicate a tooltip-based notification")
    event("PLAYER_ENTERING_WORLD")
    env.MountAtlasDB.lastAttempts = {}
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 2, "late GUID prevents reopening after world entry")
    event("LOOT_CLOSED")

    source = nil
    tooltip = catalog.attemptNodeNames["Cache of the Ascended"]
    event("CURSOR_CHANGED")
    tooltip = "Other named chest"
    event("CURSOR_CHANGED")
    event("UNIT_SPELLCAST_START", "player", "Cast-untracked-chest", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-untracked-chest", 3365)
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("mount:1426"), 2, "a new cast over a different chest cannot reuse an earlier hover")
    event("LOOT_CLOSED")

    -- Neither an interrupted opening nor a later unrelated spell completion
    -- can retain an old cache identity.
    tooltip = catalog.attemptNodeNames["Cache of the Ascended"]
    event("UNIT_SPELLCAST_START", "player", "Cast-interrupted", 3365)
    event("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-interrupted", 3365)
    source = nil
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("mount:1426"), 2, "interrupted opening cannot count without loot identity")
    tooltip = nil
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-other", 3365)
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("mount:1426"), 2, "different cast cannot reuse old node")
    event("LOOT_CLOSED")

    tooltip = catalog.attemptNodeNames["Cache of the Ascended"]
    event("UNIT_SPELLCAST_START", "player", "Cast-other-object", 3365)
    source = "GameObject-0-1-2-3-465242-000000001"
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 2, "exact GUID overrides a misleading tooltip")
    equal(testAtlas.rawStageAttempts("mount:2159"), 1, "alternate Awakened Cache object shares the same attempt counter")
    event("LOOT_CLOSED")
    flushLootChat()

    account.settings.chatMessages = false
    source = "GameObject-0-1-2-3-354175-000000003"
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "turning chat off keeps recording attempts")
    equal(#messages, before + 3, "attempt chat opt-out applies to native chest loot")
    event("LOOT_CLOSED")

    source = "GameObject-0-1-2-3-356818-000000001"
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("mount:1395"), 0, "native chest identity does not bypass covenant eligibility")
    event("LOOT_CLOSED")
    covenant = 1
    local zoneKey = catalog.attemptStages[2749].item.key
    local previousZoneAttempts = testAtlas.rawStageAttempts(zoneKey)
    source = { source, 1, "Creature-0-1-2-3-12345-000000004", 1 }
    event("LOOT_READY")
    equal(testAtlas.rawStageAttempts("mount:1395"), 1, "eligible covenant can count the chest by GUID")
    equal(testAtlas.rawStageAttempts(zoneKey), previousZoneAttempts + 1, "separate corpse retains its zone attempt")

    local nearChest = catalog.attemptNodeNames["Cache of the Ascended"]
    local cursorType, cursorName = 4, nearChest
    local restrictedTitle = setmetatable({}, { __index = function() error("restricted tooltip title read") end })
    env.canaccesstable = function(value) return value ~= restrictedTitle end
    local hideCursorTitle
    env.Enum = { TooltipDataType = { Object = 4 } }
    env.C_TooltipInfo = { GetWorldCursor = function()
        return cursorName and { type = cursorType, lines = { hideCursorTitle and restrictedTitle or { leftText = cursorName } } }
    end }
    event("LOOT_CLOSED")
    source, tooltip = nil, nil
    env.MountAtlasDB.lastAttempts = {}

    event("UNIT_SPELLCAST_SENT", "player", "Other chest", "Cast-different-target", 3365)
    event("UNIT_SPELLCAST_START", "player", "Cast-different-target", 3365, 1)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-different-target", 3365)
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "a named cast target overrides the chest under the cursor")
    event("LOOT_CLOSED")

    event("UNIT_SPELLCAST_SENT", "player", nearChest, "Cast-item", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-item", 3365)
    event("LOOT_READY")
    event("LOOT_OPENED", true, true)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "bag loot cannot complete a cache attempt")
    event("LOOT_CLOSED")

    event("UNIT_SPELLCAST_SENT", "player", nearChest, "Cast-failed", 3365)
    event("LOOT_OPENED", false, false)
    event("UNIT_SPELLCAST_FAILED_QUIET", "player", "Cast-failed", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-other", 3365)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "another cast cannot complete a failed cache opening")
    event("LOOT_CLOSED")

    event("UNIT_SPELLCAST_SENT", "party1", nearChest, "Cast-party", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-party", 3365)
    tooltip = nearChest
    event("CURSOR_CHANGED")
    cursorType = 2
    event("UNIT_SPELLCAST_SENT", "player", "", "Cast-cursor-unit", 3365)
    cursorType = 4
    event("UNIT_SPELLCAST_START", "player", "Cast-cursor-unit", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-cursor-unit", 3365)
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "party casts, cached titles and current unit tooltips cannot identify a cache")
    event("LOOT_CLOSED")

    hideCursorTitle = true
    event("UNIT_SPELLCAST_SENT", "player", "", "Cast-restricted-title", 3365)
    event("UNIT_SPELLCAST_START", "player", "Cast-restricted-title", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-restricted-title", 3365)
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "a restricted object title cannot identify a cache")
    hideCursorTitle = false
    event("LOOT_CLOSED")

    event("UNIT_SPELLCAST_SENT", "player", nearChest, "Cast-corpse", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-corpse", 3365)
    source = "Creature-0-1-2-3-12345-000000006"
    event("LOOT_READY")
    source = nil
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "a corpse source observed before the window opens blocks the name fallback")
    event("LOOT_CLOSED")

    lootSlotsWithoutSource = 0
    event("UNIT_SPELLCAST_SENT", "player", nearChest, "Cast-empty", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-empty", 3365)
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "an empty window without an object identifier does not confirm personal loot")
    event("LOOT_CLOSED")

    lootSlotsWithoutSource = 1
    cursorName, tooltip = nil, nil
    event("UNIT_SPELLCAST_SENT", "player", nearChest, "Cast-exact-name", 3365)
    event("LOOT_READY")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-exact-name", 3365)
    equal(testAtlas.rawStageAttempts("mount:1426"), 3, "a successful cast after loot readiness still needs the world loot window")
    lootSlotsWithoutSource = 0
    event("LOOT_OPENED", false, false)
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 4, "the exact localized cast target records one attempt without a tooltip or GUID")
    event("LOOT_CLOSED")

    env.MountAtlasDB.lastAttempts = {}
    lootSlotsWithoutSource = 1
    cursorType, cursorName = 4, nearChest
    event("UNIT_SPELLCAST_SENT", "player", "", "Cast-cursor-object", 3365)
    cursorName = nil
    event("UNIT_SPELLCAST_START", "player", "Cast-cursor-object", 3365, 2)
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 4, "world loot waits for success of the same pending cast")
    lootSlotsWithoutSource = 0
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-cursor-object", 3365)
    equal(testAtlas.rawStageAttempts("mount:1426"), 5, "a fresh world-object title is retained from spell dispatch to subsequent success")
    event("LOOT_CLOSED")

    env.MountAtlasDB.lastAttempts = {}
    event("UNIT_SPELLCAST_SENT", "player", nearChest, "Cast-late-object", 3365)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-late-object", 3365)
    event("LOOT_READY")
    source = "GameObject-0-1-2-3-465242-000000007"
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 5, "a different object revealed on loot open overrides the cast target")
    event("LOOT_CLOSED")

    source, cursorName, tooltip = nil, nil, nil
    lootSlotsWithoutSource = 1
    event("UNIT_SPELLCAST_SENT", "player", "", "Cast-name-on-start", 3365)
    tooltip = nearChest
    event("UNIT_SPELLCAST_START", "player", "Cast-name-on-start", 3365)
    tooltip = nil
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-name-on-start", 3365)
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 6, "an empty dispatch can still capture the current tooltip on cast start")
    event("LOOT_CLOSED")

    for index, readyBeforeSuccess in ipairs({ false, true }) do
        env.MountAtlasDB.lastAttempts = {}
        local guid = "Cast-start-autoloot-" .. index
        lootSlotsWithoutSource = 1
        cursorName = nearChest
        event("UNIT_SPELLCAST_SENT", "player", nearChest, guid, 3365)
        event("UNIT_SPELLCAST_START", "player", guid, 3365)
        cursorName = nil
        if readyBeforeSuccess then
            event("LOOT_READY")
            equal(testAtlas.rawStageAttempts("mount:1426"), 5 + index, "early autoloot still waits for the successful cast")
            lootSlotsWithoutSource = 0
        end
        event("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 3365)
        if not readyBeforeSuccess then event("LOOT_READY") end
        equal(testAtlas.rawStageAttempts("mount:1426"), 6 + index, "live START confirmation counts autoloot before LOOT_OPENED")
        event("LOOT_OPENED", true, false)
        equal(testAtlas.rawStageAttempts("mount:1426"), 6 + index, "a later LOOT_OPENED cannot recount confirmed autoloot")
        event("LOOT_CLOSED")
    end

    -- The world-cursor title can disappear as soon as the player clicks the chest.
    -- Start and loot events still arrive while the catalog is closed.
    account.settings.chatMessages = true
    env.GameTooltip = { IsShown = function() return tooltip ~= nil end }
    sceneTime = sceneTime + 3601
    local cacheKey = "mount:1426"
    local previousAttempts, previousMessages = testAtlas.rawStageAttempts(cacheKey), #messages
    local function hoverCache()
        cursorType, cursorName = env.Enum.TooltipDataType.Object, nearChest
        event("CURSOR_CHANGED")
    end
    local function startWithHiddenCursor(guid, castBarID)
        cursorName = nil
        event("UNIT_SPELLCAST_START", "player", guid, 3365, castBarID)
    end

    hoverCache()
    startWithHiddenCursor("Cast-cache-autoloot")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-cache-autoloot", 3365)
    lootSlotsWithoutSource = 2
    event("LOOT_READY", true)
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts, "cursor fallback needs world-loot confirmation")
    lootSlotsWithoutSource = 0
    event("LOOT_OPENED", true, false)
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "cached object title identifies the chest when autoloot clears the slots")
    event("LOOT_READY", true)
    event("LOOT_OPENED", true, false)
    event("LOOT_CLOSED")
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "repeated events count the chest only once")
    flushLootChat()
    equal(#messages, previousMessages + 1, "the cached title path announces the attempt once")

    hoverCache()
    startWithHiddenCursor("Cast-cache-daily-lock")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-cache-daily-lock", 3365)
    lootSlotsWithoutSource = 2
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "the cached title path respects the daily lock")
    event("LOOT_CLOSED")

    sceneTime = sceneTime + 3601
    hoverCache()
    startWithHiddenCursor("Cast-item-after-cache-hover")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-item-after-cache-hover", 3365)
    event("LOOT_READY", true)
    event("LOOT_OPENED", true, true)
    event("LOOT_CLOSED")
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "item-container loot cannot use a recent chest title")

    for _, cursor in ipairs({ { 2, nearChest }, { env.Enum.TooltipDataType.Object, "Other chest" } }) do
        hoverCache()
        cursorType, cursorName = unpack(cursor)
        event("CURSOR_CHANGED")
        startWithHiddenCursor("Cast-after-cursor-change")
        event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-after-cursor-change", 3365)
        event("LOOT_OPENED", false, false)
        event("LOOT_CLOSED")
        equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "a newer cursor target replaces the cached chest title")
    end

    hoverCache()
    sceneTime = sceneTime + 30
    startWithHiddenCursor("Cast-after-old-cache-hover")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-after-old-cache-hover", 3365)
    event("LOOT_OPENED", false, false)
    event("LOOT_CLOSED")
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "an old cursor title cannot identify the chest")

    hoverCache()
    startWithHiddenCursor("Cast-cache-with-other-source")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-cache-with-other-source", 3365)
    event("LOOT_READY")
    source = "GameObject-0-1-2-3-465242-000000009"
    event("LOOT_OPENED", false, false)
    event("LOOT_CLOSED")
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "a different object GUID overrides the cached chest title")

    local restrictedGUID = {}
    env.issecretvalue = function(value) return value == restrictedGUID end
    source = nil
    hoverCache()
    startWithHiddenCursor(restrictedGUID, 7)
    event("LOOT_OPENED", false, false)
    event("UNIT_SPELLCAST_INTERRUPTED", "player", restrictedGUID, 3365, "Creature-0-1-2-3-12345-000000007", 8)
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 1, "world loot waits for a successful opening")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", restrictedGUID, 3365, 7)
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 2, "cast bar ID confirms the same opening when the GUID is restricted")
    event("LOOT_CLOSED")

    sceneTime = sceneTime + 3601
    hoverCache()
    startWithHiddenCursor(restrictedGUID, 9)
    event("UNIT_SPELLCAST_INTERRUPTED", "player", restrictedGUID, 3365, "Creature-0-1-2-3-12345-000000007", 9)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", restrictedGUID, 3365, 9)
    event("LOOT_OPENED", false, false)
    event("LOOT_CLOSED")
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 2, "interruption clears an opening identified by cast bar ID")

    local restrictedTarget = {}
    env.issecretvalue = function(value) return value == restrictedTarget end
    local function openWithRestrictedTarget(guid)
        event("UNIT_SPELLCAST_SENT", "player", restrictedTarget, guid, 3365)
        startWithHiddenCursor(guid)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", guid, 3365)
        event("LOOT_READY", true)
        equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 2, "a restricted cast target still needs world loot")
        event("LOOT_OPENED", true, false)
        event("LOOT_CLOSED")
    end
    tooltip = nearChest
    openWithRestrictedTarget("Cast-cache-untyped-cursor")
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 2, "an untyped tooltip cannot replace a restricted cast target")
    tooltip = nil
    hoverCache()
    openWithRestrictedTarget("Cast-cache-restricted-target")
    equal(testAtlas.rawStageAttempts(cacheKey), previousAttempts + 3, "a typed cursor sample identifies a chest when the cast target is restricted")

    local key = "item:187282"
    local target, lootable, sequence = nil, false, 0
    env.UnitGUID = function(unit)
        if unit == "target" then return target end
        if unit == "player" then return "player" end
    end
    env.UnitIsDead, env.UnitCanAttack = function() return true end, function() return true end
    env.UnitIsPlayer, env.UnitClassification = function() return false end, function() return "rare" end
    env.CanLootUnit = function(guid) return guid == target and lootable, guid == target and lootable end
    local receiptTimers = {}
    env.C_Timer.After = function(delay, callback)
        if delay == .1 then receiptTimers[#receiptTimers + 1] = callback
        elseif delay == .2 then chatTimers[#chatTimers + 1] = callback end
    end
    account.settings.chatMessages = false
    account.settings.mountCollectionMessageFormat = "{название} #{попытки}"
    local function openCorpse(held, knownSource, readyOnly)
        sequence = sequence + 1
        account.acquisitionAttempts = nil
        character.stageAttempts[key] = 5
        covenant, starterCount, lootable = 1, held, true
        cursorName, tooltip, lootSlotsWithoutSource = nil, nil, 1
        target = ("Creature-0-1-2-3-180032-%09d"):format(sequence)
        source = knownSource and target or nil
        event("LOOT_READY", true)
        if not readyOnly then event("LOOT_OPENED", true, false) end
    end
    local function receiveStarter()
        event("CHAT_MSG_LOOT", "You receive loot: |Hitem:187282|h[Intact Aquilon Core]|h.",
            nil, nil, nil, nil, nil, nil, nil, nil, nil, sequence)
        table.remove(receiptTimers, 1)()
    end
    local function closeCorpse(depleted)
        lootable = not depleted
        event("LOOT_CLOSED")
        flushLootChat()
    end
    openCorpse(0)
    starterCount = 1
    receiveStarter()
    equal(testAtlas.acquisitionAttempts(key), nil, "an early receipt waits for confirmation of the fallback corpse")
    closeCorpse(true)
    equal(testAtlas.rawStageAttempts(key), 6, "a unique starter received before close still credits the eligible attempt")
    equal(testAtlas.acquisitionAttempts(key).attempts, 6, "a successful receipt freezes the confirmed attempt")
    assert(messages[#messages]:find("#6", 1, true), "early receipt announces its confirmed count")
    event("LOOT_CLOSED")
    equal(testAtlas.rawStageAttempts(key), 6, "duplicate close cannot credit the same corpse twice")

    openCorpse(0)
    closeCorpse(true)
    starterCount = 1
    receiveStarter()
    equal(testAtlas.acquisitionAttempts(key).attempts, 6, "a receipt after close uses this corpse's recorded attempt")

    openCorpse(0, true)
    equal(testAtlas.rawStageAttempts(key), 6, "the exact GUID path still records before the loot window closes")
    starterCount = 1
    receiveStarter()
    closeCorpse(true)
    equal(testAtlas.acquisitionAttempts(key).attempts, 6, "the exact GUID and the receipt still settle once")

    openCorpse(1)
    starterCount = 0
    receiveStarter()
    closeCorpse(true)
    equal(testAtlas.rawStageAttempts(key), 5, "already holding a unique starter prevents the attempt even if bags change")
    equal(testAtlas.acquisitionAttempts(key), nil, "an ineligible attempt cannot freeze an old count")

    openCorpse(0)
    receiveStarter()
    closeCorpse(false)
    equal(testAtlas.rawStageAttempts(key), 5, "receipt cannot substitute for confirmed loot depletion")
    equal(testAtlas.acquisitionAttempts(key), nil, "a cancelled loot window cannot freeze an old count")
    assert(not messages[#messages]:find("#5", 1, true), "an unresolved receipt omits the old count")

    openCorpse(0)
    covenant = 2
    closeCorpse(true)
    receiveStarter()
    equal(testAtlas.rawStageAttempts(key), 5, "a stock snapshot cannot bypass the starter's covenant")
    equal(testAtlas.acquisitionAttempts(key), nil, "wrong-covenant loot cannot claim a count")

    openCorpse(0, true, true)
    sceneTime = sceneTime + 4
    receiveStarter()
    equal(testAtlas.acquisitionAttempts(key), nil, "a receipt beyond the source window cannot borrow an earlier count")
    openCorpse(0, true, true)
    starterCount = 1
    receiveStarter()
    equal(testAtlas.acquisitionAttempts(key).attempts, 6, "the next LOOT_READY-only attempt has its own receipt context")
    closeCorpse(true)

    openCorpse(0)
    receiveStarter()
    testAtlas.resetAttemptStageSession()
    closeCorpse(true)
    equal(testAtlas.rawStageAttempts(key), 5, "session reset clears a pending fallback corpse")
    equal(testAtlas.acquisitionAttempts(key), nil, "a receipt from a reset session cannot freeze history")

    sequence = sequence + 1
    target = ("Creature-0-1-2-3-180032-%09d"):format(sequence)
    testAtlas.recordStageCreatureKill(target, 180032)
    equal(testAtlas.rawStageAttempts(key), 6, "eligible starter NPC death counts before the item is looted")
    testAtlas.recordStageCreatureKill("Creature-0-1-2-3-180032-000001000", 180032)
    equal(testAtlas.rawStageAttempts(key), 7, "another eligible death has its own attempt number")
    equal(testAtlas.acquisitionAttempts(key), nil, "death alone cannot register a personal item receipt")
    testAtlas.resetAttemptStageSession()
    source = target
    event("LOOT_READY", true)
    event("LOOT_OPENED", true, false)
    starterCount = 1
    receiveStarter()
    closeCorpse(true)
    equal(testAtlas.rawStageAttempts(key), 7, "looting the starter does not credit the same NPC death again")
    equal(testAtlas.acquisitionAttempts(key).attempts, 6, "personal loot freezes the number of the exact corpse's attempt")
    print("PawAtlas attempt events passed: collection messages, figurines, cache identity, and unique NPC loot")
end

do
    local mount = { id = 1426, npcs = { 170832, 170833, 170834, 170835, 170836 } }
    local key, councilQuest, cacheQuest = "mount:1426", 60933, 60977
    local current, other = "Player-cache-1", "Player-cache-2"
    local character, now, source, unnamedLootSlots = current, 1000, nil, 0
    local restricted = {}
    local flags = { [current] = { [cacheQuest] = true }, [other] = { [cacheQuest] = false } }
    local account = { characters = { [current] = {}, [other] = {} }, plan = { ["1426"] = true },
        settings = { chatMessages = false } }
    local stageFrames = {}
    local env = setmetatable({
        MountAtlasAccountDB = account,
        MountAtlasDB = { lastAttempts = {}, planMigrated = true },
        IsLoggedIn = function() return true end,
        GetTime = function() return now end,
        GetServerTime = function() return now end,
        UnitGUID = function(unit) if unit == "player" then return character end end,
        IsFishingLoot = function() return false end,
        GetNumLootItems = function() return source and 1 or unnamedLootSlots end,
        GetLootSourceInfo = function() return source, 1 end,
        C_Map = { GetBestMapForUnit = function() return 1533 end },
        C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end },
        C_QuestLog = { IsQuestFlaggedCompleted = function(id) return flags[character][id] end },
        C_Timer = { After = function(_, callback) callback() end },
        issecretvalue = function(value) return value == restricted end,
    }, { __index = _G })
    env._G = env
    env.CreateFrame = function()
        local instance = setmetatable({ events = {} }, { __index = frame })
        stageFrames[#stageFrames + 1] = instance
        return instance
    end
    local probe = { mounts = {}, killStatistics = {},
        addTranslations = function() end, getLocale = function() return "enUS" end,
        L = function(value) return value end, usesKillAPI = function() return false end,
        currentAttemptCharacter = function() return account.characters[character] end,
        mountByID = function(id) if id == mount.id then return mount end end,
        refreshBossLockouts = function() end, isWarbandCharacterHidden = function() return false end }
    for _, path in ipairs({ "Data/JournalData.lua", "Data/LootSources.lua", "Core/WarbandPlan.lua", "Core/AttemptStages.lua" }) do
        setfenv(assert(loadfile(path)), env)("PawAtlas", probe)
    end
    equal(probe.attemptStages[mount.id].reward.lootQuestID, cacheQuest, "the stage uses the cache's own loot quest")
    probe.initializeAttemptStages()
    local function event(name, ...)
        for _, instance in ipairs(stageFrames) do
            if instance.events[name] then instance.onEvent(instance, name, ...) end
        end
    end
    local function login(guid)
        character = guid
        env.MountAtlasDB = { lastAttempts = {}, planMigrated = true }
        event("PLAYER_ENTERING_WORLD", true, false)
    end
    local function nextDay()
        now = now + 3601
        flags[character][cacheQuest] = false
        event("QUEST_LOG_UPDATE")
    end
    local function count(expected, scenario)
        equal(probe.rawStageAttempts(key), expected, scenario)
    end

    local opportunity = probe.planOpportunityProgress(mount, current)
    equal(opportunity.totalAttempts, 1, "the five Council members share one cache opportunity")
    equal(opportunity.completedAttempts, 1, "the planner reads a completed cache without an opening event")
    login(current)
    count(0, "a cache looted before login is not a new attempt")
    equal(probe.planCharacterStatus(mount, current), "attempt", "an already-complete cache closes today's planner opportunity")
    probe.capturePlanSnapshot(true)
    login(other)
    flags[other][councilQuest] = true
    event("QUEST_TURNED_IN", councilQuest)
    event("QUEST_LOG_UPDATE")
    count(0, "completing the Council does not count opening the cache")
    equal(probe.planCharacterStatus(mount, other), "available", "the Council quest does not close the cache opportunity")
    equal(probe.planCharacterStatus(mount, current), "attempt", "the offline character retains its own cache lock")

    event("LOOT_OPENED", false, false)
    flags[other][cacheQuest] = true
    event("LOOT_CLOSED")
    event("QUEST_LOG_UPDATE")
    event("LOOT_CLOSED")
    count(1, "manual loot with unreadable source counts once from the cache quest")
    equal(probe.planCharacterStatus(mount, other), "attempt", "the cache quest closes this character's opportunity")
    equal((account.characters[current].stageAttempts or {})[key], nil, "the new attempt belongs only to the character who looted")

    nextDay()
    equal(probe.planCharacterStatus(mount, other), "available", "the reset opens today's cache opportunity")
    source = "GameObject-0-1-2-3-354175-000000001"
    event("LOOT_READY", true)
    count(2, "the exact GUID still records the opening before the cache quest arrives")
    flags[other][cacheQuest] = true
    event("QUEST_LOG_UPDATE")
    event("LOOT_OPENED", true, false)
    event("LOOT_CLOSED")
    count(2, "a quest update following a known GUID does not double-count the cache")

    nextDay()
    source = nil
    flags[other][cacheQuest] = true
    event("LOOT_READY", true)
    count(3, "early autoloot can confirm a cache with no visible GUID")
    source = "GameObject-0-1-2-3-354175-000000002"
    event("LOOT_OPENED", true, false)
    event("LOOT_CLOSED")
    event("QUEST_LOG_UPDATE")
    count(3, "a GUID revealed after quest confirmation does not duplicate autoloot")

    nextDay()
    source, flags[other][cacheQuest] = nil, true
    event("LOOT_OPENED", true, false)
    count(4, "a cache with no preceding loot-ready event is detected at loot opening")
    event("LOOT_CLOSED")

    nextDay()
    source, unnamedLootSlots = nil, 1
    local target = probe.attemptStages[mount.id].reward.nodes[1]
    event("UNIT_SPELLCAST_SENT", "player", target, "Cast-ascended-title", 3365)
    event("LOOT_READY", false)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-ascended-title", 3365)
    event("LOOT_OPENED", false, false)
    count(5, "the exact opening name still records a cache with no GUID")
    unnamedLootSlots, flags[other][cacheQuest] = 0, true
    event("LOOT_CLOSED")
    event("QUEST_LOG_UPDATE")
    count(5, "a flag following an opening identified by name does not duplicate it")

    nextDay()
    flags[other][cacheQuest] = true
    event("QUEST_LOG_UPDATE")
    event("QUEST_LOG_UPDATE")
    count(6, "a quest log transition alone counts once")

    nextDay()
    source, flags[other][cacheQuest] = nil, restricted
    event("PLAYER_ENTERING_WORLD", false, false)
    event("QUEST_LOG_UPDATE")
    equal(probe.planCharacterStatus(mount, other), "unknown", "restricted data do not promise an available cache")
    flags[other][cacheQuest] = true
    event("QUEST_LOG_UPDATE")
    count(6, "a restricted world-entry baseline cannot establish a new opening")
    equal(probe.planCharacterStatus(mount, other), "attempt", "a readable completed flag closes the opportunity without crediting an attempt")

    nextDay()
    flags[other][cacheQuest] = nil
    event("PLAYER_ENTERING_WORLD", false, false)
    flags[other][cacheQuest] = true
    event("LOOT_OPENED", true, false)
    event("LOOT_CLOSED")
    count(6, "unavailable quest data cannot stand in for an observed incomplete flag")

    nextDay()
    flags[other][cacheQuest] = true
    event("PLAYER_ENTERING_WORLD", false, false)
    event("QUEST_LOG_UPDATE")
    count(6, "re-entering the world with an already completed quest does not backfill an attempt")
    nextDay()
    flags[other][cacheQuest] = restricted
    event("QUEST_LOG_UPDATE")
    flags[other][cacheQuest] = true
    event("QUEST_LOG_UPDATE")
    count(7, "a brief unreadable result during play preserves the last known incomplete flag")

    nextDay()
    local daily = env.C_DateAndTime.GetSecondsUntilDailyReset
    local lockKey = "stage:" .. key .. ":daily"
    local oldExpiry = env.MountAtlasDB.lastAttempts[lockKey]
    env.C_DateAndTime.GetSecondsUntilDailyReset = nil
    env.C_DateAndTime.GetSecondsUntilWeeklyReset = function() return 604800 end
    source = "GameObject-0-1-2-3-354175-000000003"
    event("LOOT_READY", true)
    flags[other][cacheQuest] = true
    event("LOOT_CLOSED")
    count(8, "the exact opening and the flag share credit even with no daily reset time")
    equal(env.MountAtlasDB.lastAttempts[lockKey], oldExpiry, "a missing daily reset cannot install a weekly lock")
    env.C_DateAndTime.GetSecondsUntilDailyReset = daily
    event("QUEST_LOG_UPDATE")
    count(8, "delayed daily reset data cannot replay the opening")
    equal(env.MountAtlasDB.lastAttempts[lockKey], now + 3600, "late reset data completes the original daily lock")

    nextDay()
    local messages = {}
    account.characters[other].stageAttempts[key] = 10
    account.settings.chatMessages, account.settings.chatMessageFormat = true, "#{attempts} {probability}"
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, line) messages[#messages + 1] = line end }
    env.C_MountJournal = { GetMountInfoByID = function()
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, false
    end }
    source = nil
    event("LOOT_OPENED", true, false)
    flags[other][cacheQuest] = true
    event("QUEST_LOG_UPDATE")
    count(11, "the eleventh opening is already saved before loot chat")
    equal(#messages, 0, "the quest confirmation does not interrupt autoloot messages")
    event("LOOT_CLOSED")
    event("QUEST_LOG_UPDATE")
    equal(#messages, 1, "the flag-only opening announces once with a closed catalog")
    assert(messages[1]:find("#11", 1, true) and messages[1]:find("43.12%", 1, true))
    print("PawAtlas Ascended cache passed: personal quest, planner, both loot orders, reset and unavailable data")
end

do
    local loader, timers, active, opened, inserted, itemReady
    timers, opened, inserted = {}, {}, {}
    local function editor()
        return { text = "", focused = true, visible = true,
            HasFocus = function(self) return self.focused end,
            IsVisible = function(self) return self.visible end,
            GetText = function(self) return self.text end,
            Insert = function(self, text) self.text = self.text .. text end }
    end
    local whisper, other = editor(), editor()
    local env = setmetatable({ WIM = { EditBoxInFocus = whisper } }, { __index = _G })
    env.CreateFrame = function()
        return { RegisterEvent = function(self) loader = self end, UnregisterEvent = function() end,
            SetScript = function(self, name, callback) self[name] = callback end }
    end
    env.ChatFrameUtil = {
        GetActiveWindow = function() return active end,
        InsertLink = function(link) inserted[#inserted + 1] = link; return true end,
        OpenChat = function(link) opened[#opened + 1] = link end,
    }
    env.C_MountJournal = { GetMountInfoByID = function() return "Mount", 88750 end }
    env.C_Spell = { GetSpellLink = function(id) return "|Hspell:" .. id .. "|h[Mount]|h" end }
    env.GetQuestLink = function(id)
        if id ~= 12687 then return "|Hquest:" .. id .. ":1|h[Quest]|h" end
    end
    env.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
    env.C_Item = { GetItemInfo = function() if itemReady then return "Item", "|Hitem:123|h[Item]|h" end end,
        RequestLoadItemDataByID = function() end }
    local links = {}
    setfenv(assert(loadfile("Core/SourceDetails.lua")), env)("PawAtlas", links)
    setfenv(assert(loadfile("Core/Links.lua")), env)("PawAtlas", links)
    assert(links.linkMount(400), "mount link inserted in WIM")
    assert(whisper.text:find("|Hspell:88750", 1, true), "focused WIM receives mount link")
    equal(#opened, 0, "WIM does not open general chat")
    equal(#inserted, 0, "WIM bypasses unrelated Blizzard editor")
    assert(links.linkSource("quest:90474"), "quest source link supported")
    assert(whisper.text:find("|Hquest:90474:1", 1, true), "WIM receives native quest link")
    assert(links.linkSource("quest:12687:0", nil, "[Путь в Долину Теней]"), "cold inline quest can be inserted immediately")
    assert(whisper.text:find("|Hquest:12687:0|h[Путь в Долину Теней]|h", 1, true), "WIM receives the exact cold quest link")
    local openedInstance
    links.openPlace = function(view) openedInstance = view.journalInstance end
    local raidMarkup = "{journal:1302:Манагорн Омега}"
    local fallbackRaid = "|cff66bbff|Hpawatlasjournal:1302|hМанагорн Омега|h|r"
    equal(links.sourceInlineLinks(raidMarkup), fallbackRaid, "an unavailable native link still permits opening the raid")
    assert(links.openSourceReference("pawatlasjournal:1302", whisper), "cold raid opens through the instance handler")
    equal(openedInstance, 1302, "the click opens exactly the raid's journal instance")
    assert(not links.openSourceReference("journal:1:1302:0", whisper), "an encounter link is not treated as an instance")
    local draft = whisper.text
    assert(not links.linkSource(fallbackRaid, whisper), "the internal raid link is never sent to chat")
    equal(whisper.text, draft, "missing native APIs leave the draft intact")

    local nativeRaid = "|cff66bbff|Hjournal:0:1302:0|h[Манагорн Омега]|h|r"
    env.Enum = { JournalLinkTypes = { Instance = 0 } }
    env.C_EncounterJournal = { GetEncounterJournalLink = function(kind, instance, label, difficulty)
        assert(kind == 0 and instance == 1302 and label == "Манагорн Омега" and difficulty == 0)
        return nativeRaid
    end }
    equal(links.sourceInlineLinks(raidMarkup), "|cff66bbff|Hjournal:0:1302:0|hМанагорн Омега|h|r",
        "the cold native API provides clickable localized text inside the sentence")
    assert(links.linkSource(fallbackRaid, whisper), "an existing inline fallback can still share the native raid link")
    equal(whisper.text, draft .. nativeRaid, "chat preserves the native hyperlink exactly")
    env.EJ_GetInstanceInfo = function(instance)
        assert(instance == 1302)
        return "Манагорн Омега", nil, nil, nil, nil, nil, nil, nativeRaid
    end
    local englishRaid = links.sourceInlineLinks("{journal:1302:Manaforge Omega}")
    equal(englishRaid, "|cff66bbff|Hjournal:0:1302:0|hManaforge Omega|h|r",
        "the alternate addon locale keeps its own inline caption")
    assert(links.openSourceReference("journal:0:1302:0", whisper), "the native link opens the same raid")
    assert(links.linkSource(englishRaid, whisper), "the warm client link can be shared")
    equal(whisper.text, draft .. nativeRaid .. nativeRaid, "chat keeps the client locale for a native link")
    local clicked, openedMission
    env.SetItemRef = function(payload, link, button, owner) clicked = { payload, link, button, owner } end
    local questRows = { [45020] = "Воссоединение кровоглядов", [44988] = "Воссоединение злобоклювов",
        [44969] = "Воссоединение снегоспинов", [45019] = "Воссоединение острокогтей", [85811] = "Трайир Очи Сирены" }
    local questReady, questCallbacks, activeQuest, popupQuest = {}, {}, nil, nil
    local itemRef = { lines = {} }
    function itemRef:IsShown() return self.shown == true end
    function itemRef:Show() self.shown = true end
    function itemRef:Hide() self.shown, self.primary, self.owner = false, nil, nil end
    function itemRef:SetOwner(owner) self.owner = owner end
    function itemRef:ClearLines() self.lines = {} end
    function itemRef:NumLines() return #self.lines end
    function itemRef:AddLine(text) self.lines[#self.lines + 1] = text end
    function itemRef:GetPrimaryTooltipInfo() return self.primary end
    function itemRef:GetLeftLine()
        return { GetText = function() return self.lines[1] end }
    end
    function itemRef:SetHyperlink(payload)
        local id = tonumber(payload:match("^quest:(%d+)"))
        if not questReady[id] or id == 44969 then self:Hide(); return false end
        self.payload = payload
        self.primary = { getterName = "GetHyperlink", getterArgs = { payload } }
        self:AddLine(questRows[id])
        self:Show()
        return true
    end
    env.ItemRefTooltip, env.UIParent = itemRef, {}
    env.C_QuestLog = {
        IsOnQuest = function(id) return id == activeQuest end,
        GetTitleForQuestID = function(id) if questReady[id] then return questRows[id] end end,
        GetQuestObjectives = function(id)
            if questReady[id] then return { { text = "Objective " .. id } } end
        end,
        RequestLoadQuestByID = function() end,
    }
    env.GetQuestLink = function(id)
        if questReady[id] then return ("|Hquest:%d:45|h[%s]|h"):format(id, questRows[id]) end
    end
    env.QuestUtil = {
        OpenQuestDetails = function(id) popupQuest = id ~= popupQuest and id or nil end,
        IsShowingQuestDetails = function(id) return popupQuest == id end,
    }
    env.QuestEventListener = { AddCallback = function(_, id, callback) questCallbacks[id] = callback end }
    for _, id in ipairs({ 45020, 44988, 44969, 45019, 85811 }) do
        local payload, label = "quest:" .. id .. ":0", "[" .. questRows[id] .. "]"
        assert(links.openSourceReference(payload, whisper, label), "cold quest pins its tooltip")
        equal(itemRef.lines[1], questRows[id], "cold tooltip retains the quest title")
        equal(itemRef.owner, env.UIParent, "tooltip reacquires its owner after a missing hyperlink")
        questReady[id] = true
        questCallbacks[id]()
        if id == 44969 then
            equal(itemRef.lines[2], "Objective 44969", "inactive quest with no native tooltip shows known objectives")
        else
            equal(itemRef.payload, "quest:" .. id .. ":45", "quest load replaces the synthetic link with a native payload")
        end
        equal(itemRef.lines[1], questRows[id], "loaded tooltip matches the selected quest")
    end
    questReady[85811] = nil
    assert(links.openSourceReference("quest:85811", whisper, questRows[85811]), "a bare quest ID uses the supplied title")
    itemRef.primary = { getterName = "GetHyperlink", getterArgs = { "item:232639" } }
    questReady[85811] = true
    questCallbacks[85811]() -- The quest and its item have the same title.
    equal(itemRef.primary.getterArgs[1], "item:232639", "late quest data cannot replace another pinned reference")
    activeQuest = 45019
    assert(links.openSourceReference("quest:45019:0", whisper), "an active quest opens the Blizzard log popup")
    equal(popupQuest, 45019, "quest popup selects the exact quest")
    assert(links.openSourceReference("quest:45019:0", whisper), "the native quest popup can be toggled")
    equal(popupQuest, nil, "second click closes the quest popup")
    assert(not clicked, "quest handling requires a visible panel or tooltip")

    local thrayir = "|Hitem:232639|h[Трайир Очи Сирены]|h"
    assert(links.openSourceReference("item:232639", whisper, thrayir), "source item opens its native reference")
    equal(clicked[1], "item:232639", "item click passes the exact item payload")
    equal(clicked[2], thrayir, "item click keeps the full display link")
    equal(clicked[4], whisper, "item click passes the source frame")
    env.C_Garrison = {
        GetMissionLink = function(id) if id == 679 then return "|Hgarrmission:679:0123456789ABCDEF|h[Breaker Two]|h" end end,
        GetMissionName = function(id) if id == 615 then return "Riverbeast" end end,
    }
    env.FloatingGarrisonMission_Toggle = function(id) openedMission = id end
    assert(links.openSourceReference("pawatlasmission:679", whisper), "a native mission link opens normally")
    equal(clicked[1], "garrmission:679:0123456789ABCDEF", "native mission link keeps its instance ID")
    assert(links.linkSource("pawatlasmission:679", whisper, "[Breaker Two]"), "native mission link can be shared")
    assert(whisper.text:find("|Hgarrmission:679:0123456789ABCDEF", 1, true), "WIM receives the real native mission link")
    assert(links.openSourceReference("pawatlasmission:615", whisper, "[Riverbeast]"), "mission details can open without an offered instance")
    equal(openedMission, 615, "mission details open by Garrison mission ID")
    assert(links.linkSource("pawatlasmission:615", whisper, "[Riverbeast]"), "unoffered mission can be shared by title")
    assert(whisper.text:match("Riverbeast$"), "sharing uses the title when there is no native mission link")
    local previous = whisper.text
    local nativeAchievementLink = env.GetAchievementLink
    env.GetAchievementLink = function() return nil end
    assert(links.linkSource("achievement:15035", whisper), "a cold achievement can wait for the native link")
    env.GetAchievementLink = function() return "|Hachievement:15064:player|h[Other achievement]|h" end
    loader.OnEvent(loader, "RECEIVED_ACHIEVEMENT_LIST")
    equal(whisper.text, previous, "a native counterpart link does not replace the requested achievement")
    env.GetAchievementLink = function() return "|Hachievement:15035:player|h[On the Offensive]|h" end
    loader.OnEvent(loader, "RECEIVED_ACHIEVEMENT_LIST")
    equal(whisper.text, previous .. env.GetAchievementLink(), "a loaded achievement is inserted into the original draft")
    previous = whisper.text
    loader.OnEvent(loader, "RECEIVED_ACHIEVEMENT_LIST")
    equal(whisper.text, previous, "duplicate achievement data notifications do not repeat the link")
    env.GetAchievementLink = nativeAchievementLink
    assert(links.linkItem(123), "uncached item request accepted")
    env.WIM.EditBoxInFocus = other
    itemReady = true
    loader.OnEvent(loader, "ITEM_DATA_LOAD_RESULT", 123, true)
    equal(whisper.text, previous, "delayed link cannot target old WIM conversation")
    equal(other.text, "", "delayed link cannot target new WIM conversation")
    itemReady = false
    assert(links.linkItem(123), "second uncached item request accepted")
    other.text = "edited draft"
    itemReady = true
    loader.OnEvent(loader, "ITEM_DATA_LOAD_RESULT", 123, true)
    equal(other.text, "edited draft", "editing WIM cancels delayed insertion")
    env.WIM.EditBoxInFocus.focused = false
    active = editor()
    assert(links.linkMount(400), "Blizzard active draft remains supported")
    equal(active.text, env.C_Spell.GetSpellLink(88750), "the focused Blizzard editor receives the mount link")
    active.focused = false
    assert(not links.linkMount(400), "an unfocused native editor cannot accept a link")
    active.focused, active.visible = true, false
    assert(not links.linkMount(400), "a hidden native editor cannot accept a link")
    active = nil
    assert(not links.linkMount(400), "a closed chat stays closed")
    itemReady = false
    local queued = #timers
    assert(not links.linkItem(123) and #timers == queued, "a closed chat does not queue a future insertion")
    links.L = string.format
    active = editor()
    local message = "|Hspell:88750|h[Mount]|h · Попыток: 42"
    assert(links.shareMountAttempts({ id = 400 }, 42))
    equal(active.text, message, "the active channel receives the displayed attempt count")
    env.WIM.EditBoxInFocus = whisper
    local draft = whisper.text
    assert(links.shareMountAttempts({ id = 400 }, 42))
    equal(whisper.text, draft .. message, "attempt sharing preserves the current whisper and existing draft")
    assert(not links.shareMountAttempts({ id = 400 }, nil), "unknown attempts cannot be shared as zero")
    env.WIM.EditBoxInFocus, active, env.C_Spell.GetSpellLink = nil, nil, function() end
    assert(not links.shareMountAttempts({ id = 400, journalName = "Mount" }, 0))
    local core = { item = 187282, name = "Невредимый сердечник аквилона", attempts = 8, perAttempt = .01 }
    links.getLocale = function() return "ruRU" end
    env.C_Item.GetItemInfo = function() end
    assert(not links.shareItemAttempts(core), "sharing item attempts also leaves closed chat alone")
    active = editor()
    assert(links.shareMountAttempts({ id = 400, journalName = "Mount" }, 0))
    equal(active.text, "[Mount] · Попыток: 0", "a known zero is inserted into the open draft")
    active.text = "Look: "
    assert(links.shareItemAttempts(core))
    equal(active.text, "Look: |Hitem:187282|h[Невредимый сердечник аквилона]|h · Попыток: 8",
        "a cold starter shares its own item and attempts instead of the guaranteed mount")
    assert(not links.shareItemAttempts({ item = 187282, attempts = nil }))
    assert(not links.shareItemAttempts({ item = 94288, required = 9999, attempts = 0 }),
        "collection progress is not a shareable drop attempt")
    equal(#opened, 0, "link sharing never opens chat")
    equal(#inserted, 0, "link sharing never redirects to a non-chat edit box")
    print("PawAtlas chat links passed: focused chat drafts, WIM, native links and async context")
end

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
    equal(L("(%d/%s попыток)", 24, "100"), russian and "(24/100 попыток)" or "(24/100 attempts)", clientLocale .. " tooltip attempts")

    local dynamic = "|Hitem:999999|h[Already localized]|h"
    equal(L(dynamic), dynamic, clientLocale .. " dynamic text remains unchanged")
    local library = environment.LibStub("AceLocale-3.0")
    equal(rawget(library:GetLocale("PawAtlas"), dynamic), nil, clientLocale .. " dynamic text is not cached")
    equal(library:GetLocale("OtherAddon")["Попыток: %s"], "Other: %s", clientLocale .. " other addon dictionary")
end

for _, locale in ipairs({ "ruRU", "enUS", "deDE" }) do checkLocale(locale) end
print("PawAtlas locales passed: ruRU, enUS and English fallback")

-- Exercise the real tooltip callbacks across native clear/reuse cycles.
do
    local callbacks, lines, hooks = {}, {}, {}
    local tooltip = {}
    local data, owner, collected, link = nil, nil, false, "|cffa335ee|Hitem:184062|h[Warhound reins]|h|r"
    local chance, attempts = .01, 24
    function tooltip:AddLine(text, r, g, b) lines[#lines + 1] = { text, r, g, b } end
    function tooltip:GetPrimaryTooltipData() return data end
    function tooltip:GetOwner() return owner end
    function tooltip:HookScript(event, callback) hooks[event] = callback end
    local mount = { id = 1437 }
    local tooltipAtlas = {
        L = function(text, ...) return text:format(...) end,
        mounts = { mount }, lootByNPC = { [162875] = { mount } },
        mountByID = function(id) return id == mount.id and mount end,
        lootItems = { [1437] = { item = 184062 } },
        displayName = function(name) return name end,
        isExcludedJournalMount = function() return false end,
        activePlanID = function() return 1 end,
        isPlanned = function() return true end,
        dropProbability = function(value)
            equal(value, mount, "tooltip uses catalog entry for statistics")
            return chance, nil, attempts
        end,
    }
    local environment = setmetatable({
        GameTooltip = tooltip, MountAtlasWindow = {},
        MountAtlasAccountDB = { settings = { gameTooltips = false } },
        Enum = { TooltipDataType = { Item = 0, Unit = 1 } },
        TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) callbacks[kind] = callback end },
        C_Item = { GetItemInfo = function() return nil, link end },
        C_MountJournal = { GetMountInfoByID = function()
            return "Mount · name", 344228, nil, nil, nil, nil, nil, nil, nil, nil, collected
        end },
    }, { __index = _G })
    environment._G = environment
    for _, path in ipairs({ "UI/Theme.lua", "UI/GameTooltips.lua" }) do
        setfenv(assert(loadfile(path)), environment)("PawAtlas", tooltipAtlas)
    end
    tooltipAtlas.initializeGameTooltips()
    assert(next(hooks) == nil and next(callbacks) == nil, "disabled tooltips leave native callbacks unregistered")
    environment.MountAtlasAccountDB.settings.gameTooltips = true
    tooltipAtlas.initializeGameTooltips()
    local itemCallback, unitCallback, clearedHook = callbacks[0], callbacks[1], hooks.OnTooltipCleared
    assert(itemCallback and unitCallback and clearedHook, "enabling tooltips registers the native callbacks")
    tooltipAtlas.initializeGameTooltips()
    assert(callbacks[0] == itemCallback and callbacks[1] == unitCallback and hooks.OnTooltipCleared == clearedHook,
        "reinitializing tooltips preserves the native callbacks")
    local function hover(kind)
        hooks.OnTooltipCleared(tooltip)
        lines = {}
        data = kind == 1 and { guid = "Creature-0-1-2-3-162875-000000001" } or { id = 184062 }
        callbacks[kind](tooltip, data)
    end
    hover(1)
    equal(lines[1][1], " ", "creature tooltip separates the addon section from native lines")
    assert(lines[2][1]:find(link, 1, true), "native item hyperlink must remain intact")
    assert(lines[2][1]:find("(24/100 попыток)", 1, true), "tooltip shows attempt count and inverse chance")
    equal(lines[3][1], "В плане", "plan status is a separate line")
    callbacks[1](tooltip, data)
    equal(#lines, 3, "repeated callback does not duplicate lines or spacing")
    collected = true
    hover(0)
    equal(lines[2][1], "В коллекции", "collection status wins over plan")
    equal(lines[2][2], 1, "collected status red component")
    equal(lines[2][3], .2, "collected status green component")
    assert(not lines[1][1]:find("попыток", 1, true), "collected mount hides attempts")
    collected, link, attempts = false, nil, nil
    hover(1)
    assert(lines[2][1]:find("Mount / name", 1, true), "uncached item falls back to font-safe mount name")
    assert(not lines[2][1]:find("попыток", 1, true), "unknown count is not presented as zero")
    link, chance, attempts = "|Hitem:184062|h[Loaded]|h", 1 / 33, 0
    hover(1)
    assert(lines[2][1]:find("[Loaded]", 1, true), "next hover picks up loaded item data")
    assert(lines[2][1]:find("(0/33 попыток)", 1, true), "known zero attempts remains visible")
    hooks.OnTooltipCleared(tooltip)
    lines = {}
    data = { guid = "Creature-0-1-2-3-42-000000001" }
    local getOwner = tooltip.GetOwner
    tooltip.GetOwner = function() error("untracked creatures should not read the tooltip owner") end
    callbacks[1](tooltip, data)
    tooltip.GetOwner = getOwner
    equal(#lines, 0, "creatures without addon information add no spacing")
    owner = environment.MountAtlasWindow
    hover(0)
    equal(#lines, 0, "addon's own tooltips are not extended")
    owner = nil
    environment.MountAtlasAccountDB.settings.gameTooltips = false
    hover(1)
    equal(#lines, 0, "disabled tooltip integration adds nothing")
    print("PawAtlas game tooltips passed: links, counts, statuses, fallback and reuse")
end

do
    local environment = setmetatable({ StaticPopupDialogs = {}, CLOSE = "Close" }, { __index = _G })
    local settingsAtlas = { ui = {}, L = function(text) return text end }
    setfenv(assert(loadfile("UI/Settings.lua")), environment)("PawAtlas", settingsAtlas)
    local spec = assert(environment.StaticPopupDialogs.PAWATLAS_PROJECT_URL)
    local popup = { which = "PAWATLAS_PROJECT_URL", shown = true }
    local edit = { text = "" }
    function popup:IsShown() return self.shown end
    function popup:GetEditBox() return edit end
    function popup:Hide() self.shown = false; spec.OnHide(self) end
    function edit:GetParent() return popup end
    function edit:GetText() return self.text end
    function edit:SetText(value)
        self.text = value
        self.writes = (self.writes or 0) + 1
        assert(self.writes < 20, "copy-only field must not recurse indefinitely")
        spec.EditBoxOnTextChanged(self)
    end
    function edit:SetFocus() self.focused = true end
    function edit:ClearFocus() self.focused = false end
    function edit:HighlightText() self.highlighted = self.text end
    local url = "https://github.com/Zik/PawAtlas"
    spec.OnShow(popup)
    equal(edit.text, url, "project URL on open")
    equal(edit.highlighted, url, "project URL selected for native copy")
    assert(edit.focused, "copy field keeps keyboard focus")
    for _, value in ipairs({ "x", "", "https://example.invalid/pasted", url .. "x" }) do
        edit.writes = 0
        edit:SetText(value)
        equal(edit.text, url, "input cannot change project URL")
        equal(edit.highlighted, url, "restored URL stays selected")
        assert(edit.focused, "editing guard must not disable keyboard focus")
    end
    spec.EditBoxOnEscapePressed(edit)
    assert(not popup.shown and not edit.focused and edit.text == "", "Escape closes and clears copy field")
    popup.shown = true
    spec.OnShow(popup)
    equal(edit.text, url, "reopening restores project URL")
    popup.which = "OTHER_DIALOG"
    edit:SetText("other dialog value")
    equal(edit.text, "other dialog value", "reused native editbox is not forced to project URL")
    print("PawAtlas project popup passed: selection, copy-only editing, Escape and reuse")
end

do
    local mounted, loaded, chat, timers, handlers = {}, {}, {}, {}, {}
    local islandItems = { [166467] = 1212, [163583] = 1176, [163584] = 1175 }
    local pendingIslandMap, salvageCount = nil, 2
    local giftCount = 0
    local corpse, npcItemReady
    local time = 0
    local settings = { rewardToast = false, chatMessages = false }
    local character = { stageAttempts = { ["mount:2"] = 5, ["mount:3"] = 8, ["mount:7"] = 60 } }
    local account = { settings = settings, characters = { player = character } }
    local env = setmetatable({ MountAtlasAccountDB = account }, { __index = _G })
    env._G, env.LOOT_ITEM_SELF = env, "You receive loot: %s."
    env.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    env.LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE = "You receive bonus loot: %sx%d."
    env.LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
    env.GetTime = function() return time end
    env.LibStub = function(name)
        equal(name, "LibSharedMedia-3.0", "notification media library")
        return {}
    end
    env.CreateFrame = function()
        local instance = setmetatable({ events = {} }, { __index = frame })
        handlers[#handlers + 1] = instance
        return instance
    end
    env.C_Timer = { After = function(delay, callback)
        timers[#timers + 1] = { time = time + delay, callback = callback }
    end }
    env.C_MountJournal = {
        GetMountFromItem = function(item)
            if item > 1000 and item < 1008 then return item - 1000 end
            if item == 186657 then return 1501 end
            return islandItems[item]
        end,
        GetMountInfoByID = function(id)
            if loaded[id] then return "Маунт " .. id, 99, 123, nil, nil, nil, nil, nil, nil, nil, mounted[id] end
        end,
    }
    env.C_Item = {
        GetItemCount = function(item)
            if item == 173989 then return salvageCount end
            if item == 187029 then return giftCount end
        end,
        GetItemInfo = function(item) if item == 8202 and npcItemReady then return "Rare reins" end end,
    }
    env.GetNumLootItems = function() return corpse and 1 or 0 end
    env.GetLootSourceInfo = function() return corpse, 1 end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
    local notifications = {
        ui = {}, mounts = {}, addTranslations = function() end, getLocale = function() return "ruRU" end,
        L = function(message) return message end,
        currentAttemptCharacter = function() return character end,
        isCharacterSuppressed = function() return false end,
        pendingIslandExpeditionMap = function() return pendingIslandMap end,
        killStatistics = {},
        attemptStages = {
            [2] = { reward = { key = "mount:2", item = 1002, method = "ENCOUNTER", encounters = { 100 } } },
            [3] = { reward = { key = "mount:3", item = 1003, method = "ENCOUNTER", encounters = { 101 } } },
            [7] = { reward = { key = "mount:7", item = 1007, method = "ENCOUNTER", encounters = { 102 } } },
            [8201] = { reward = { key = "mount:8201", name = "Dungeon reins", method = "ENCOUNTER", encounters = { 8201 } } },
            [8202] = { reward = { key = "mount:8202", item = 8202, method = "NPC", npcs = { 8202 } } },
        },
    }
    local catalog = {}
    for _, path in ipairs({ "Data/JournalData.lua", "Data/LootSources.lua" }) do
        assert(loadfile(path))("PawAtlas", catalog)
    end
    for _, id in ipairs({ 1313, 537, 538, 539, 540, 1501 }) do notifications.attemptStages[id] = catalog.attemptStages[id] end
    notifications.islandSalvageMounts = {}
    for _, id in pairs(islandItems) do
        notifications.attemptStages[id] = catalog.attemptStages[id]
        notifications.islandSalvageMounts[id] = catalog.islandSalvageMounts[id]
        loaded[id], mounted[id] = true, false
    end
    notifications.guaranteedRewards, notifications.lootItems = catalog.guaranteedRewards, catalog.lootItems
    notifications.mountRewardContainerRewards = catalog.mountRewardContainerRewards
    for _, path in ipairs({ "Core/AttemptStages.lua", "UI/Notifications.lua" }) do
        setfenv(assert(loadfile(path)), env)("PawAtlas", notifications)
    end
    notifications.initializeAttemptStages()
    local function event(name, ...)
        for _, handler in ipairs(handlers) do
            if handler.events[name] then handler.onEvent(handler, name, ...) end
        end
    end
    local function advance(interval)
        local limit = time + interval
        while #timers > 0 do
            table.sort(timers, function(a, b) return a.time < b.time end)
            if timers[1].time > limit then break end
            local timer = table.remove(timers, 1)
            time = timer.time
            timer.callback()
        end
        time = limit
    end

    loaded[1], mounted[1] = true, true
    event("NEW_MOUNT_ADDED", 1)
    event("PLAYER_LOGIN")
    event("NEW_MOUNT_ADDED", 1)
    event("PLAYER_ENTERING_WORLD")
    event("NEW_MOUNT_ADDED", 1)
    advance(1)
    equal(#chat, 0, "login and an already-collected mount do not announce")

    loaded[2], mounted[2] = true, false
    do
        local link = "|Hitem:1002|h[Mount item]|h"
        local slots, plansCompleted = env.GetNumLootItems, 0
        env.GetNumLootItems = function() return 1 end
        env.GetLootSlotLink = function() return link end
        notifications.completePlanTarget = function() plansCompleted = plansCompleted + 1 end
        event("LOOT_READY", true)
        event("LOOT_OPENED", true, false)
        event("CHAT_MSG_LOOT", "You have selected Need for: " .. link)
        event("LOOT_CLOSED")
        event("CHAT_MSG_LOOT", "Another player receives loot: " .. link .. ".")
        event("CHAT_MSG_LOOT", "You receive loot: pending roll for " .. link .. ".")
        advance(.4)
        equal(plansCompleted, 0, "a group loot preview or another winner cannot complete the player's plan")
        equal(notifications.acquisitionAttempts("mount:2"), nil, "an unawarded roll cannot freeze a successful attempt")
        equal((account.mountLootNotifications or {})[2], nil, "losing a roll does not reserve the personal loot toast")
        equal(#chat, 0, "the player gets no collection message before a personal award")
        env.GetNumLootItems, env.GetLootSlotLink = slots, nil
        notifications.completePlanTarget = nil
    end
    event("CHAT_MSG_LOOT", "You receive loot: |Hitem:1002|h[Mount item]|h.")
    event("ENCOUNTER_END", 100, "First encounter", 16, 20, 1)
    advance(.22)
    equal(#chat, 0, "looted but unlearned mount stays out of chat")
    mounted[2] = true
    event("NEW_MOUNT_ADDED", 2)
    event("NEW_MOUNT_ADDED", 2)
    advance(.3)
    equal(chat[1], "PawAtlas: Маунт 2 получен! Попытка №6.", "collection after item loot uses final attempt")
    equal(#chat, 1, "same mount and spell only announce once")

    loaded[3], mounted[3] = true, true
    event("NEW_MOUNT_ADDED", 3)
    env.C_Timer.After(.2, function()
        event("CHAT_MSG_LOOT", "You receive loot: |Hitem:1003|h[Mount item]|h.")
        event("ENCOUNTER_END", 101, "Second encounter", 16, 20, 1)
    end)
    advance(.26)
    equal(#chat, 1, "ordinary loot already in flight blocks the collection message")
    advance(.3)
    equal(chat[2], "PawAtlas: Маунт 3 получен! Попытка №9.", "collection before loot gets the final attempt for its mount ID")

    event("NEW_MOUNT_ADDED", 4)
    notifications.rememberAcquisition("mount:4", 20, 94295, nil, true)
    advance(.4)
    equal(#chat, 2, "wait for the collection journal to resolve")
    loaded[4], mounted[4] = true, true
    event("NEW_MOUNT_ADDED", 4)
    advance(.6)
    equal(#chat, 2, "a historical egg count does not duplicate the native mount announcement after a retry")

    settings.mountCollectionMessageFormat = "{mount} #{попытки} ({probability})"
    loaded[5], mounted[5] = true, true
    notifications.rememberAcquisition("mount:5", 14, 268730, nil, true)
    event("NEW_MOUNT_ADDED", 5)
    advance(.3)
    equal(#chat, 2, "a custom template cannot turn an unrelated receipt into a mount award")
    settings.mountCollectionChat, settings.chatMessages = false, true
    loaded[6], mounted[6] = true, true
    event("NEW_MOUNT_ADDED", 6)
    advance(.3)
    equal(#chat, 2, "acquisition opt-out works independently of attempt chat")
    equal(settings.mountCollectionChat, false, "explicit opt-out is preserved")
    settings.mountCollectionChat, settings.mountCollectionMessageFormat = nil, nil
    loaded[7], mounted[7] = true, true
    event("CHAT_MSG_LOOT", "You receive item: |Hitem:1007|h[Purchased mount item]|h.")
    event("NEW_MOUNT_ADDED", 7)
    advance(.3)
    equal(notifications.acquisitionAttempts("mount:7").attempts, 60, "ordinary toast history remains compatible")
    equal(#chat, 2, "purchased teaching item leaves the collection announcement to Blizzard")
    for _, id in ipairs({ 1313, 538, 539, 540 }) do
        loaded[id], mounted[id] = true, false
    end
    local scale = "|cnIQ2:|Hitem:174230|h[Scale]|h|r"
    local function receipt(text, line)
        event("CHAT_MSG_LOOT", text, nil, nil, nil, nil, nil, nil, nil, nil, nil, line)
    end
    loaded[537], mounted[537] = true, false
    local bones = "You receive loot: |Hitem:94288|h[Giant Dinosaur Bone]|h"
    receipt(bones .. "x12.", 1301)
    receipt(bones .. "x12.", 1301)
    receipt(bones .. ".", 1302)
    advance(.2)
    equal(#chat, 2, "single and stacked dinosaur bones leave only the native loot message")
    equal(notifications.itemCollectionCount({ id = 537 }), 13, "distinct bone receipts still advance collection by their quantity")
    local bonus = "You receive bonus loot: |Hitem:94288|h[Giant Dinosaur Bone]|hx2."
    receipt(bonus, 1303)
    receipt(bonus, 1303)
    equal(notifications.itemCollectionCount({ id = 537 }), 15, "a personal bonus award is counted once")
    settings.chatMessages = false
    settings.mountCollectionMessageFormat = "{название} #{попытки} ({вероятность})"
    character.stageAttempts["item:174230"] = 1
    corpse = "Creature-0-1-2-3-157162-000000001"
    event("LOOT_READY", true)
    receipt("You receive loot: " .. scale .. ".", 501)
    receipt("You receive loot: " .. scale .. ".", 501)
    event("LOOT_CLOSED")
    corpse = nil
    advance(.2)
    equal(chat[3], scale .. " #2 (3,96%)", "actual scale drop includes final attempt and shared custom format")
    equal(#chat, 3, "duplicate loot line announces only once")
    local egg = "|Hitem:94295|h[Primal Egg]|h"
    character.stageAttempts["item:94295"] = 7
    corpse = "Creature-0-1-2-3-69983-000000001"
    event("LOOT_READY", true)
    receipt("Another player receives loot: " .. egg .. ".", 502)
    receipt("You receive loot: " .. egg .. ".", 503)
    event("LOOT_CLOSED")
    corpse = nil
    advance(.2)
    equal(#chat, 4, "one egg for three mounts announces once and only for self loot")
    assert(chat[4]:find(egg .. " #8", 1, true))
    receipt("You receive item: " .. scale .. ".", 504)
    advance(.2)
    equal(chat[5], scale .. " #— (—)", "a pushed item has no proven drop attempt")
    settings.mountCollectionChat = false
    receipt("You receive loot: " .. scale .. ".", 505)
    advance(.2)
    equal(#chat, 5, "shared collection opt-out applies to item receipts")
    -- Zenet's egg has a catalogued reward but no independent attempt stage.
    loaded[1672], mounted[1672] = true, false
    settings.mountCollectionChat = true
    local zenet = "|Hitem:200879|h[Zenet Egg]|h"
    receipt("You receive loot: " .. zenet .. ".", 506)
    mounted[1672] = true
    event("NEW_MOUNT_ADDED", 1672)
    receipt("You receive loot: " .. zenet .. ".", 506)
    advance(.5)
    equal(#chat, 6, "rapid learning keeps the single item receipt without duplicating Blizzard")
    equal(chat[6], zenet .. " #— (—)", "an uncounted egg never borrows mount attempts")
    print("PawAtlas collection chat passed: login, both loot orders, delayed data, deduplication, template and opt-out")

    settings.chatMessageFormat = "{mount} #{attempts}"
    pendingIslandMap = 1879
    receipt("You receive loot: |Hitem:166467|h[Island Thunderscale]|h.", 507)
    mounted[1212] = true
    event("NEW_MOUNT_ADDED", 1212)
    advance(.4)
    equal(notifications.acquisitionAttempts("mount:1212"), nil, "island receipt waits for the completion event")
    equal(#chat, 6, "early island receipt does not announce an incomplete total")
    notifications.settleIslandExpeditionAcquisitions(1813)
    equal(notifications.acquisitionAttempts("mount:1212"), nil, "a different map cannot settle the pending receipt")
    character.islandExpeditionCompletions, pendingIslandMap = 1, nil
    notifications.settleIslandExpeditionAcquisitions(1879)
    advance(.3)
    equal(notifications.acquisitionAttempts("mount:1212").attempts, 1, "loot-before-completion freezes the successful expedition")
    assert(chat[7]:find("Маунт 1212 #1", 1, true))

    character.islandExpeditionCompletions = 2
    notifications.settleIslandExpeditionAcquisitions(1813)
    receipt("You receive loot: |Hitem:163583|h[Craghorn Chasm-Leaper]|h.", 508)
    mounted[1176] = true
    event("NEW_MOUNT_ADDED", 1176)
    advance(.3)
    equal(notifications.acquisitionAttempts("mount:1176").attempts, 2, "completion-before-loot freezes the same combined counter")
    assert(chat[8]:find("Маунт 1176 #2", 1, true))

    settings.chatMessages = true
    loaded[1501], mounted[1501] = true, false
    local giftLink = "|Hitem:187029|h[Mysterious Gift from Ve'nari]|h"
    giftCount = 2
    receipt("You receive item: " .. giftLink .. ".", 15011)
    receipt("You receive loot: " .. giftLink .. ".", 15012)
    receipt("You receive loot: |Hitem:94296|h[Cracked Primal Egg]|h.", 15013)
    receipt("You receive loot: |Hitem:173950|h[Rotting Mire Salvage]|h.", 15014)
    event("BAG_UPDATE_DELAYED")
    advance(.3)
    equal(#chat, 8, "receiving a gift, a mature egg or shared island salvage stays silent")
    equal(notifications.rawStageAttempts("mount:1501"), 0, "receiving the gift is not an opening")
    settings.chatMessageFormat = "{mount} #{attempts} ({probability})"
    event("LOOT_OPENED", true, true)
    giftCount = 1
    event("BAG_UPDATE_DELAYED")
    event("LOOT_CLOSED")
    event("BAG_UPDATE_DELAYED")
    advance(.3)
    equal(notifications.rawStageAttempts("mount:1501"), 1, "the gift was opened exactly once")
    assert(chat[9]:find("#1 (12,50%)", 1, true), "an unsuccessful gift reports its count and cumulative chance")
    equal(#chat, 9, "one gift opening produces one attempt message")
    settings.chatMessageFormat = "{mount} #{attempts}"
    receipt("You receive loot: |Hitem:163584|h[Twilight Avenger]|h.", 509)
    event("LOOT_OPENED", false, true)
    advance(.15)
    equal(notifications.acquisitionAttempts("mount:1175"), nil, "salvage receipt waits for verified consumption")
    salvageCount = 1
    event("BAG_UPDATE_DELAYED")
    event("LOOT_CLOSED")
    event("BAG_UPDATE_DELAYED")
    equal(notifications.rawStageAttempts("mount:1175"), 1, "the bag update and loot close count the same opening once")
    equal(notifications.acquisitionAttempts("mount:1175").attempts, 3, "salvage receipt freezes expeditions and the successful open")
    advance(.3)
    equal(#chat, 9, "successful salvage leaves the winning mount's line to collection chat")
    mounted[1175] = true
    event("NEW_MOUNT_ADDED", 1175)
    advance(.3)
    assert(chat[10]:find("Маунт 1175 #3", 1, true), "reward chat reports the frozen combined total")

    event("LOOT_OPENED", false, true)
    salvageCount = 0
    event("LOOT_CLOSED")
    event("BAG_UPDATE_DELAYED")
    equal(notifications.islandExpeditionProgress({ id = 1175 }), 4, "salvage keeps counting after the mount is learned")
    equal(notifications.acquisitionAttempts("mount:1175").attempts, 3, "later farming does not change a frozen acquisition")
    equal(#chat, 10, "collected mounts stay out of routine attempt chat")
    print("PawAtlas island acquisition chat passed: both expedition orders, salvage deduplication and frozen totals")

    local function bossLoot(serial)
        corpse = "Creature-0-1-2-3-8202-00000000" .. serial
        event("LOOT_READY")
        event("LOOT_OPENED", false, false)
        event("LOOT_CLOSED")
    end
    event("ENCOUNTER_END", 8201, "Dungeon boss", 16, 20, 0)
    equal(notifications.rawStageAttempts("mount:8201"), 0, "failed encounters do not queue chat")
    event("ENCOUNTER_END", 8201, "Dungeon boss", 16, 20, 1)
    event("BOSS_KILL", 8201, "Dungeon boss")
    bossLoot(1)
    advance(.1)
    bossLoot(2)
    equal(notifications.rawStageAttempts("mount:8201"), 1, "staged encounter is saved once before ownership arrives")
    equal(notifications.rawStageAttempts("mount:8202"), 2, "different corpses save two staged attempts before ownership arrives")
    equal(#chat, 10, "unknown boss mount ownership defers chat")
    loaded[8201], loaded[8202], mounted[8201], mounted[8202] = true, true, false, false
    advance(1)
    equal(chat[11], "Dungeon reins #1", "a staged encounter announces without opening the catalog")
    equal(#chat, 11, "a cold staged item name still defers chat")
    npcItemReady = true
    event("ITEM_DATA_LOAD_RESULT", 8202, true)
    advance(2.3)
    equal(chat[12], "Rare reins #1", "first pending corpse keeps its own count")
    equal(chat[13], "Rare reins #2", "second pending corpse keeps its own count")
    equal(#chat, 13, "duplicate encounter and corpse events do not repeat chat")

    loaded[8202] = false
    bossLoot(3)
    loaded[8202], mounted[8202] = true, true
    advance(1)
    equal(notifications.rawStageAttempts("mount:8202"), 3, "a pending staged boss attempt remains saved after acquisition")
    equal(#chat, 13, "acquiring a staged mount suppresses its pending line")
    loaded[8202] = false
    bossLoot(4)
    settings.chatMessages = false
    advance(1)
    settings.chatMessages = true
    loaded[8202], mounted[8202] = true, false
    advance(20)
    equal(notifications.rawStageAttempts("mount:8202"), 4, "muting pending staged boss chat preserves the attempt")
    equal(#chat, 13, "reenabling attempt chat does not replay the canceled line")
    event("LOOT_OPENED", false, true)
    giftCount = 0
    event("BAG_UPDATE_DELAYED")
    advance(.4)
    receipt("You receive loot: |Hitem:186657|h[Soulbound Gloomcharger's Reins]|h.", 15015)
    event("LOOT_CLOSED")
    advance(.4)
    mounted[1501] = true
    event("NEW_MOUNT_ADDED", 1501)
    advance(.5)
    equal(notifications.acquisitionAttempts("mount:1501").attempts, 2, "the successful opening is included")
    equal(#chat, 14, "manual looting produces only the mount announcement for the successful gift")
    assert(chat[14]:find("Маунт 1501 #2", 1, true))
    print("PawAtlas staged boss chat passed: ownership and item retry, independent totals, event deduplication and opt-out")
end

do
    local id = 533
    local mount = { id = id, journalOnly = true, name = statisticCatalog.englishNames[id] }
    local statisticID = statisticCatalog.killStatistics[id][1]
    local sample, ownership, resolved = 18, nil, nil
    local reads, lookups, chat, timers, handlers = 0, 0, {}, {}, {}
    local account = {
        settings = { chatMessageFormat = "{mount} #{attempts} ({probability})" },
        characters = { alt = { statistics = { [id] = 5 } } },
        rarityImport = { entries = { [id] = { total = 40 } } },
    }
    local env = setmetatable({ MountAtlasAccountDB = account, MountAtlasDB = {} }, { __index = _G })
    env.GetStatistic = function(key)
        equal(key, statisticID, "only the selected boss's statistic is read")
        reads = reads + 1
        return tostring(sample)
    end
    env.C_MountJournal = { GetMountInfoByID = function(key)
        equal(key, id, "only the selected boss mount's ownership is read")
        return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ownership
    end }
    env.C_Timer = { After = function(delay, callback)
        equal(delay, 1, "a cold statistic notification only schedules its first retry")
        timers[#timers + 1] = callback
    end }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
    local probe = {
        mounts = {}, attemptStages = { [id] = statisticCatalog.attemptStages[id] },
        lootItems = { [id] = statisticCatalog.lootItems[id] }, killStatistics = { [id] = { statisticID } },
        addTranslations = function() end, getLocale = function() return "enUS" end,
        L = function(message) return message end,
        RegisterEvent = function(_, event, handler) handlers[event] = handler end,
        mountByID = function() return resolved end,
        resolveJournalMount = function(key)
            equal(key, id, "the retry only resolves the selected journal entry")
            lookups, resolved = lookups + 1, mount
            return resolved
        end,
    }
    for _, path in ipairs({ "Core/Tracking.lua", "Core/AttemptStages.lua", "Core/RarityImport.lua" }) do
        setfenv(assert(loadfile(path)), env)("PawAtlas", probe)
    end
    probe.initializeTracking()
    probe.initializeAttemptStages()
    handlers.PLAYER_REGEN_DISABLED("PLAYER_REGEN_DISABLED")
    sample = 19
    equal(probe.rawKills(mount), 24, "first rise includes the other character's saved total")
    equal(probe.rawKills(mount), 24, "an unchanged rescan retains the saved total")
    sample = 20
    equal(probe.rawKills(mount), 25, "second rise is also saved before loading the journal")
    equal(lookups, 0, "updating a statistic does not load the mount journal")
    equal(#chat, 0, "unknown ownership suppresses premature chat")
    equal(#timers, 2, "two rises queue separate messages while their duplicate scans queue none")
    equal(reads, 4, "saving and scheduling do not recursively sample the statistic")
    local readsBeforeRetry = reads
    ownership = false
    for _, retry in ipairs(timers) do retry() end
    equal(chat[1], "Cobalt Primordial Direhorn #41 (33.77%)", "first line retains the imported count and its probability")
    equal(chat[2], "Cobalt Primordial Direhorn #42 (34.43%)", "second line retains its own count and probability")
    equal(reads, readsBeforeRetry, "delivery does not resample the statistic")
    equal(#chat, 2, "each rise announces once")
    equal(lookups, 1, "both lines reuse the selected journal mount")
    equal(account.rarityImport.entries[id].deltaByGUID[player], 2, "each confirmed rise credits the import once")

    ownership, sample = nil, 21
    equal(probe.rawKills(mount), 26, "a later statistic rise is still saved")
    probe.resetAttemptStageSession()
    ownership = false
    timers[3]()
    equal(#chat, 2, "reset invalidates pending statistic chat")
    print("PawAtlas statistic chat passed: independent delayed totals, imported history, deduplication and reset")
end

do
    local worldBosses = { [473] = 870, [515] = 870, [533] = 870, [542] = 1064, [634] = 1116 }
    local rollSpells = { [473] = 132205, [515] = 132206, [533] = 137554, [542] = 136381 }
    for id, map in pairs(worldBosses) do
        local currentMap = map
        local stat = statisticCatalog.killStatistics[id][1]
        local source = statisticCatalog.killStatisticSources[stat][1]
        local mount = { id = id, name = statisticCatalog.englishNames[id], journalOnly = true }
        local time, sample, credits, imported, loot = 1000, "--", 0, 0, false
        local chat, timers, handlers = {}, {}, {}
        local account = { settings = { chatMessageFormat = "{mount} #{attempts}" } }
        local env = setmetatable({ MountAtlasAccountDB = account, MountAtlasDB = {} }, { __index = _G })
        env.GetTime = function() return time end
        env.GetInstanceInfo = function() return "World", "none", 0, nil, nil, nil, nil, currentMap end
        env.GetStatistic = function(key)
            equal(key, stat, "read targeted world boss statistic")
            return sample
        end
        local promptSpell, coin = rollSpells[id], id <= 515 and 697 or 752
        local pendingPrompts
        env.GetSpellConfirmationPromptsInfo = function() return pendingPrompts end
        env.BONUS_ROLL_REQUIRED_CURRENCY = 697
        env.BonusRollFrame = { CurrentCountFrame = {}, shown = true, IsShown = function(self) return self.shown end }
        env.C_MountJournal = { GetMountInfoByID = function(key)
            equal(key, id, "read targeted world boss mount ownership")
            return mount.name, nil, nil, nil, nil, nil, nil, nil, nil, nil, false
        end }
        local guid = "Creature-0-1-2-3-" .. source.npc .. "-00001"
        env.GetNumLootItems = function() return loot and 1 or 0 end
        env.GetLootSourceInfo = function() return guid, 1 end
        env.C_Timer = { After = function(delay, callback)
            timers[#timers + 1] = { time + delay, callback }
        end }
        local function advance(seconds)
            local untilTime = time + seconds
            while #timers > 0 do
                table.sort(timers, function(a, b) return a[1] < b[1] end)
                if timers[1][1] > untilTime then break end
                local timer = table.remove(timers, 1)
                time = timer[1]
                timer[2]()
            end
            time = untilTime
        end
        env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
        local probe = {
            mounts = {}, lootByNPC = {}, killStatistics = { [id] = { stat } },
            killStatisticSources = { [stat] = { source } },
            bonusRollSources = statisticCatalog.bonusRollSources,
            worldBossLocks = { [id] = { frequency = "weekly" } },
            attemptStages = { [id] = statisticCatalog.attemptStages[id] },
            lootItems = { [id] = statisticCatalog.lootItems[id] },
            addTranslations = function() end, getLocale = function() return "enUS" end,
            L = function(message) return message end,
            RegisterEvent = function(_, event, handler) handlers[event] = handler end,
            resolveJournalMount = function(key)
                equal(key, id, "resolve a world boss mount without the catalog")
                return mount
            end,
            recordBrokerAttempt = function(key)
                if key == id or type(key) == "table" and key[id] then credits = credits + 1 end
            end,
            recordImportedStatistic = function(key, _, delta)
                equal(key, id, "world boss import target")
                imported = imported + delta
            end,
        }
        for _, path in ipairs({ "Core/Tracking.lua", "Core/AttemptStages.lua" }) do
            setfenv(assert(loadfile(path)), env)("PawAtlas", probe)
        end
        probe.initializeTracking()
        probe.initializeAttemptStages()
        local function signal(event, ...)
            assert(handlers[event], "missing tracking event " .. event)(event, ...)
        end
        signal("PLAYER_ENTERING_WORLD")
        sample = "7"
        advance(2)
        equal(#chat, 0, "late login history remains silent " .. id)
        sample = "8"
        signal("CRITERIA_UPDATE")
        advance(.5)
        equal(probe.savedStatisticAttempts(id), 8, "a cold statistic rise is saved " .. id)
        equal(#chat, 0, "a cold rise alone cannot announce a kill " .. id)
        signal("BOSS_KILL", source.encounter)
        signal("ENCOUNTER_END", source.encounter, nil, 0, 1, 1, { { creatureID = source.npc } })
        loot = true
        signal("LOOT_READY")
        signal("LOOT_OPENED", true, false)
        advance(2)
        equal(chat[1], mount.name .. " #8", "victory confirms the recent numeric rise " .. id)
        equal(credits, 1, "duplicates give one Broker credit " .. id)
        equal(imported, 1, "duplicates give one imported delta " .. id)
        advance(25)

        loot = false
        signal("LOOT_READY")
        loot = true
        guid = "Creature-0-1-2-3-" .. source.npc .. "-00002"
        currentMap = nil
        signal("LOOT_READY")
        currentMap = map
        signal("LOOT_OPENED", true, false)
        advance(6)
        equal(#chat, 1, "the loot event alone cannot confirm a second attempt " .. id)
        sample = "9"
        advance(16)
        equal(probe.savedStatisticAttempts(id), 9, "late statistic reaches the same character snapshot " .. id)
        equal(chat[2], mount.name .. " #9", "late statistic is announced without a catalog " .. id)
        equal(#chat, 2, "duplicate rescans do not replay old attempts " .. id)
        equal(credits, 2, "both attempts reach the Broker " .. id)
        equal(imported, 2, "both attempts contribute once to imported history " .. id)

        signal("LOOT_OPENED", true, false)
        sample = "10"
        signal("CRITERIA_UPDATE")
        advance(2)
        equal(probe.savedStatisticAttempts(id), 10, "a later statistic remains visible " .. id)
        equal(#chat, 2, "a previously counted corpse cannot confirm another rise " .. id)

        sample = "--"
        probe.clearAttemptStatistics()
        signal("PARTY_KILL", player, "Creature-0-1-2-3-" .. source.npc .. "-00003")
        advance(6)
        equal(#chat, 2, "the first victory waits for a readable count " .. id)
        sample = "1"
        advance(16)
        equal(chat[3], mount.name .. " #1", "a first kill announces after a delayed first statistic " .. id)
        equal(credits, 3, "the first kill credits Broker once " .. id)
        equal(imported, 3, "the first kill adds one imported delta " .. id)
        if promptSpell then
            local function prompt(spell, currency)
                env.BonusRollFrame.spellID = spell
                env.BonusRollFrame.CurrentCountFrame.currencyID = currency == 0 and env.BONUS_ROLL_REQUIRED_CURRENCY or currency
                signal("SPELL_CONFIRMATION_PROMPT", spell, 1, nil, 180, currency, 1)
            end
            local function result(kind, secondary)
                signal("BONUS_ROLL_RESULT", kind or "money", "", 1, 0, 0, true, nil, secondary == true)
            end

            -- The boss prompt can arrive before the statistic updates.
            signal("BOSS_KILL", source.encounter)
            prompt(promptSpell, id == 515 and 0 or coin)
            signal("BONUS_ROLL_STARTED")
            signal("BONUS_ROLL_STARTED")
            signal("SPELL_CONFIRMATION_TIMEOUT", promptSpell, 1)
            result("item", true)
            equal(#chat, 3, "secondary result does not complete the roll " .. id)
            result()
            result()
            signal("BONUS_ROLL_STARTED")
            result()
            equal(chat[4], mount.name .. " #2", "gold counts as one bonus attempt " .. id)
            equal(#chat, 4, "repeated bonus events do not add attempts " .. id)
            equal(account.characters[player].statistics[id], 1, "bonus does not change the base statistic " .. id)
            sample = "2"
            advance(3)
            equal(chat[5], mount.name .. " #3", "late base attempt follows the bonus attempt " .. id)
            equal(probe.kills(mount), 3, "base and bonus attempts share the account total " .. id)
            local rate, cumulative, attempts = probe.dropProbability(mount)
            equal(attempts, 3, "the probability uses the combined total " .. id)
            assert(math.abs(cumulative - (1 - (1 - rate) ^ 3)) < 1e-12)
            equal(imported, 5, "base and bonus add one imported delta each " .. id)
            equal(credits, 5, "base and bonus both credit Broker " .. id)

            advance(180)
            sample = "3"
            signal("BOSS_KILL", source.encounter)
            advance(3)
            equal(chat[6], mount.name .. " #4", "base attempt can arrive first " .. id)
            prompt(promptSpell, coin)
            env.BonusRollFrame.spellID = promptSpell + 1
            signal("BONUS_ROLL_STARTED")
            result()
            env.BonusRollFrame.spellID = promptSpell
            result()
            equal(#chat, 6, "another boss and unstarted prompts cannot count " .. id)
            env.BonusRollFrame.shown = false
            signal("BONUS_ROLL_STARTED")
            result()
            equal(#chat, 6, "an unrelated start cannot use a hidden stale frame " .. id)
            env.BonusRollFrame.shown = true
            signal("BONUS_ROLL_STARTED")
            signal("BONUS_ROLL_FAILED")
            result()
            equal(#chat, 6, "a failed roll cannot count " .. id)
            prompt(promptSpell, coin)
            signal("SPELL_CONFIRMATION_TIMEOUT", promptSpell, 1)
            signal("BONUS_ROLL_STARTED")
            result()
            prompt(promptSpell, coin + 1)
            signal("BONUS_ROLL_STARTED")
            result()
            equal(#chat, 6, "expired and wrong-currency prompts cannot count " .. id)
            prompt(promptSpell, coin)
            signal("BONUS_ROLL_STARTED")
            result("item")
            equal(chat[7], mount.name .. " #5", "a completed roll counts after the base attempt " .. id)

            advance(180)
            prompt(promptSpell, coin)
            signal("BONUS_ROLL_STARTED")
            result()
            equal(chat[8], mount.name .. " #6", "a confirmed roll can be used without a new base attempt " .. id)
            equal(account.characters[player].bonusRolls[id], 3, "only confirmed bonus history is stored " .. id)

            setfenv(assert(loadfile("Core/RarityImport.lua")), env)("PawAtlas", probe)
            account.rarityImport = { entries = { [id] = { total = 100 } } }
            advance(180)
            prompt(promptSpell, coin)
            signal("BONUS_ROLL_STARTED")
            result()
            equal(chat[9], mount.name .. " #101", "a new roll adds once above the Rarity import floor " .. id)
            equal(probe.rawKills(mount), 7, "Rarity history stays separate from local and Blizzard counts " .. id)
            equal(probe.kills(mount), 101, "Rarity history and the new roll reach the displayed total " .. id)

            advance(180)
            prompt(promptSpell, coin)
            signal("BONUS_ROLL_STARTED")
            probe.clearAttemptStatistics()
            result()
            equal(probe.kills(mount), 3, "reset preserves the Blizzard history and clears local bonus history " .. id)
            equal(#chat, 9, "result arriving after reset cannot count " .. id)

            pendingPrompts = { { spellID = promptSpell, confirmType = 1, duration = 1,
                currencyID = coin, currencyCost = 1 } }
            signal("PLAYER_ENTERING_WORLD", false, true)
            signal("BONUS_ROLL_STARTED")
            advance(2)
            pendingPrompts = nil
            signal("PLAYER_ENTERING_WORLD", false, false)
            result()
            result()
            equal(chat[10], mount.name .. " #4", "a restored offer can finish after an in-session zone transition " .. id)
            equal(#chat, 10, "zone changes do not allow a duplicate result " .. id)
        end
    end
    print("PawAtlas world boss attempts passed: five bosses, cold journal, both bonus orders and duplicate events")
end

do
    local catalog = {}
    for _, path in ipairs({ "Data/Rares.lua", "Data/JournalData.lua", "Data/LootSources.lua" }) do
        assert(loadfile(path))("PawAtlas", catalog)
    end
    local character = { islandExpeditionCompletions = 2 }
    local settings = { chatMessageFormat = "{mount} #{attempts}" }
    local map, fishing, bagCount, clock, bagReads = 1970, true, 2, 100, 0
    local ownership, messages, timers = {}, {}, {}
    local callback, containerHook, nameHook, cursorItem
    local env = setmetatable({ MountAtlasAccountDB = { characters = { player = character }, settings = settings } },
        { __index = _G })
    env.CreateFrame = function()
        return { RegisterEvent = function() end, RegisterUnitEvent = function() end,
            SetScript = function(_, _, handler) callback = handler end }
    end
    env.GetTime = function() return clock end
    env.GetServerTime = env.GetTime
    env.GetNumLootItems = function() return 1 end
    env.GetLootSourceInfo = function() end
    env.IsFishingLoot = function() return fishing end
    env.C_Map = { GetBestMapForUnit = function() return map end }
    env.C_MountJournal = {
        GetMountInfoByID = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ownership[id] end,
    }
    local salvageItem, salvageSpell = 173989, 900003
    env.C_Item = {
        GetItemCount = function(item)
            if item == salvageItem then
                bagReads = bagReads + 1
                return bagCount
            end
        end,
        GetItemSpell = function(item) if item == salvageItem then return "Open Salvage", salvageSpell end end,
    }
    env.GetCursorInfo = function() if cursorItem then return "item", cursorItem end end
    env.C_Container = {
        UseContainerItem = function() end,
        GetContainerItemID = function() return salvageItem end,
    }
    env.UseItemByName = function() end
    env.hooksecurefunc = function(owner, name, hook)
        if owner == env.C_Container and name == "UseContainerItem" then containerHook = hook
        elseif owner == "UseItemByName" then nameHook = name end
    end
    local settleTimers = {}
    env.C_Timer = { After = function(delay, fn)
        local queue = delay == .2 and settleTimers or timers
        queue[#queue + 1] = fn
    end }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) messages[#messages + 1] = message end }
    local probe = { mounts = {}, killStatistics = {},
        attemptStages = { [982] = catalog.attemptStages[982], [1434] = catalog.attemptStages[1434],
            [1212] = catalog.attemptStages[1212] },
        islandSalvageMounts = { [1212] = catalog.islandSalvageMounts[1212] },
        dataName = function(data) return data.englishName end,
        currentAttemptCharacter = function() return character end,
        isCharacterSuppressed = function() return false end,
        getLocale = function() return "enUS" end,
        addTranslations = function() end, L = function(value) return value end }
    setfenv(assert(loadfile("Core/AttemptStages.lua")), env)("PawAtlas", probe)
    probe.initializeAttemptStages()
    local function event(name, ...) callback(nil, name, ...) end
    local function settle()
        while #settleTimers > 0 do table.remove(settleTimers, 1)() end
    end
    local function catch()
        event("LOOT_READY", true)
        event("LOOT_OPENED", true, false)
        event("LOOT_CLOSED")
        settle()
    end
    local function drainTimers()
        settle()
        local calls = 0
        while #timers > 0 and calls < 20 do
            calls = calls + 1
            table.remove(timers, 1)()
        end
        equal(#timers, 0, "attempt retries drain in finite time")
        return calls
    end

    event("PLAYER_ENTERING_WORLD")
    map = 100
    catch()
    equal(probe.rawStageAttempts("item:187662"), 0, "Strange Goop requires Zereth Mortis")
    map = 1970
    catch()
    equal(#messages, 0, "unknown ownership defers fishing chat")
    ownership[1434] = false
    catch()
    equal(probe.rawStageAttempts("item:187662"), 2, "two catches save before ownership without double-counting both loot events")
    equal(#messages, 0, "a newly resolved stage cannot overtake its pending first message")
    map, ownership[982] = 885, false
    catch()
    equal(messages[1], "Pond Nettle #1", "another stage does not wait for the pending fishing message")
    map = 1970
    drainTimers()
    equal(messages[2], "Strange Goop #1", "the first delayed fishing line keeps its own attempt")
    equal(messages[3], "Strange Goop #2", "the second delayed fishing line keeps its own attempt")

    ownership[1434] = nil
    catch()
    equal(drainTimers(), 4, "unavailable ownership exhausts the retry window")
    catch()
    ownership[1434] = true
    drainTimers()
    ownership[1434] = nil
    catch()
    settings.chatMessages = false
    drainTimers()
    settings.chatMessages = true
    catch()
    probe.resetAttemptStageSession()
    ownership[1434] = false
    drainTimers()
    equal(#messages, 3, "acquisition, muting and session reset cancel pending fishing lines")
    equal(probe.rawStageAttempts("item:187662"), 6, "canceled fishing lines leave every catch in saved history")

    fishing = false
    for remaining = 1, 0, -1 do
        event("LOOT_OPENED", false, true)
        bagCount = remaining
        event("BAG_UPDATE_DELAYED")
        event("LOOT_CLOSED")
    end
    equal(probe.rawStageAttempts("mount:1212"), 2, "verified Jorundall Salvage consumes two bags")
    equal(probe.islandExpeditionProgress({ id = 1212 }), 4, "expedition completions and bags share a displayed total")
    local _, islandBar, islandRate = probe.islandExpeditionProgress({ id = 1212 })
    local sortRate, sortBar = probe.catalogDropChances({ id = 1212 })
    equal(sortRate, islandRate, "catalog uses the island's common per-attempt rate")
    equal(sortBar, islandBar, "catalog uses the same expedition and salvage bar")
    equal(#messages, 3, "unknown ownership defers salvage chat")
    ownership[1212] = false
    drainTimers()
    equal(messages[4], "Island Thunderscale #3", "first delayed bag line freezes its own expedition total")
    equal(messages[5], "Island Thunderscale #4", "second delayed bag line freezes its own expedition total")
    equal(#messages, 5, "late ownership does not duplicate any attempt line")

    local function resetSalvage()
        bagCount, messages = 2, {}
        character.stageAttempts["mount:1212"], character.islandExpeditionCompletions = nil, 0
        probe.resetAttemptStageSession()
    end
    local function castSalvage(guid)
        event("UNIT_SPELLCAST_SUCCEEDED", "player", guid, salvageSpell)
    end
    local function confirmSalvage(remaining)
        bagCount = remaining
        event("BAG_UPDATE_DELAYED")
        event("BAG_UPDATE_DELAYED")
        event("LOOT_CLOSED")
        event("LOOT_CLOSED")
        drainTimers()
    end
    local function checkSalvage(count, scenario)
        equal(probe.rawStageAttempts("mount:1212"), count, scenario)
        equal(#messages, count, scenario .. " chat lines")
        for attempt = 1, count do
            equal(messages[attempt], "Island Thunderscale #" .. attempt, scenario .. " attempt order")
        end
    end

    settings.chatMessages = true
    resetSalvage()
    containerHook(0, 1)
    containerHook(0, 1)
    bagCount = 0
    event("BAG_UPDATE_DELAYED")
    drainTimers()
    checkSalvage(2, "two opens can share one bag update without a loot window")
    local readsAfterConfirm = bagReads
    event("LOOT_CLOSED")
    event("LOOT_CLOSED")
    equal(bagReads, readsAfterConfirm, "confirmed uses do not force another bag read on duplicate close")
    drainTimers()
    checkSalvage(2, "late close cannot add a line after auto-loot already announced both opens")

    resetSalvage()
    containerHook(0, 1)
    nameHook(salvageItem)
    castSalvage("Cast-salvage-one")
    containerHook(0, 1)
    nameHook(salvageItem)
    castSalvage("Cast-salvage-two")
    confirmSalvage(1)
    checkSalvage(1, "the first bag update spends only one of two observed uses")
    castSalvage("Cast-salvage-one")
    castSalvage("Cast-salvage-two")
    confirmSalvage(0)
    checkSalvage(2, "the second bag update spends the other use once despite duplicate signals")

    resetSalvage()
    containerHook(0, 1)
    nameHook(salvageItem)
    castSalvage("Cast-single-salvage")
    castSalvage("Cast-single-salvage")
    confirmSalvage(0)
    checkSalvage(1, "one use reported by multiple hooks and a repeated cast cannot prove two openings")

    resetSalvage()
    bagCount = 1
    event("BAG_UPDATE_DELAYED")
    containerHook(0, 1)
    containerHook(0, 1)
    confirmSalvage(0)
    checkSalvage(1, "a repeated hook with one available box cannot prove two uses")

    resetSalvage()
    event("LOOT_OPENED", false, true)
    bagCount = 1
    event("BAG_UPDATE_DELAYED")
    event("LOOT_OPENED", false, true)
    confirmSalvage(0)
    checkSalvage(1, "repeating the same item window cannot spend another passive opening")

    resetSalvage()
    containerHook(0, 1)
    event("UNIT_SPELLCAST_SENT", "player", "", "Cast-cancelled-salvage", salvageSpell)
    event("UNIT_SPELLCAST_INTERRUPTED", "player", "Cast-cancelled-salvage", salvageSpell)
    confirmSalvage(1)
    checkSalvage(0, "cancelled use cannot count a subsequent inventory decrease")

    resetSalvage()
    containerHook(0, 1)
    cursorItem = salvageItem
    confirmSalvage(1)
    cursorItem = nil
    confirmSalvage(2)
    checkSalvage(0, "moving a box with the cursor cannot confirm a use")

    resetSalvage()
    containerHook(0, 1)
    event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 123)
    containerHook(0, 1)
    confirmSalvage(1)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 123)
    confirmSalvage(0)
    checkSalvage(0, "selling or moving a box during an interaction cannot confirm a use")

    resetSalvage()
    containerHook(0, 1)
    clock = clock + 9
    confirmSalvage(1)
    checkSalvage(0, "an expired use cannot count an unrelated inventory decrease")

    resetSalvage()
    setfenv(assert(loadfile("Core/RarityImport.lua")), env)("PawAtlas", probe)
    env.MountAtlasAccountDB.rarityImport = { entries = { ["mount:1212"] = { total = 25, source = 25 } } }
    probe.initializeIslandImports()
    nameHook(salvageItem)
    nameHook(salvageItem)
    confirmSalvage(0)
    equal(probe.rawStageAttempts("mount:1212"), 2, "imported expedition history leaves local openings separate")
    equal(probe.islandExpeditionProgress({ id = 1212 }), 27, "both openings advance the imported expedition total")
    equal(#messages, 2, "two box lines keep the imported attempt history")
    equal(messages[1], "Island Thunderscale #26", "first box line starts at the imported count")
    equal(messages[2], "Island Thunderscale #27", "second box line advances the imported count")
    print("PawAtlas fishing and salvage chat passed: cold ownership, rapid openings, exact totals, deduplication and cancellation")
end

do
    local catalog = { addTranslations = function() end }
    assert(loadfile("Data/JournalData.lua"))("PawAtlas", catalog)
    local character = { stageAttempts = { ["mount:1776"] = 2, ["mount:1781"] = 4 } }
    local previousAward = { attempts = 4, item = 206678, confirmedLoot = true }
    local account = {
        characters = { player = character }, settings = { chatMessages = false },
        acquisitionAttempts = { ["mount:1781"] = previousAward },
        rarityImport = { entries = { [1781] = { attempts = 99 } } },
    }
    local clock, faction, instance, completed, bags = 100, "Alliance", 0, false, 0
    local source, slotLink, stageCallback, registered, useItem
    local roster = { [1776] = 206673, [1777] = 206674, [1778] = 206675, [1779] = 206676,
        [1781] = 206678, [1782] = 206679, [1783] = 206680 }
    local env = setmetatable({ MountAtlasAccountDB = account }, { __index = _G })
    env._G = env
    env.LOOT_ITEM_SELF, env.LOOT_ITEM_PUSHED_SELF = "You receive loot: %s.", "You receive item: %s."
    env.CreateFrame = function()
        registered = {}
        return { RegisterEvent = function(_, event) registered[event] = true end, RegisterUnitEvent = function() end,
            SetScript = function(_, _, handler) stageCallback = handler end }
    end
    env.GetTime = function() return clock end
    env.GetServerTime = env.GetTime
    env.GetInstanceInfo = function() return nil, "scenario", nil, nil, nil, nil, nil, instance end
    env.UnitFactionGroup = function() return faction end
    env.C_ScenarioInfo = { GetScenarioInfo = function() return { isComplete = completed } end }
    env.C_Item = { GetItemCount = function(item) if item == 207583 then return bags end end }
    env.C_Timer = { After = function(_, run) run() end }
    env.GetNumLootItems = function() return slotLink and 1 or 0 end
    env.GetLootSlotLink = function() return slotLink end
    env.GetLootSourceInfo = function() return source, 1 end
    env.UseItemByName = function() end
    env.hooksecurefunc = function(name, callback)
        equal(name, "UseItemByName", "box use hook")
        useItem = callback
    end
    local function restart()
        local probe = { mounts = {}, killStatistics = {}, attemptStages = {},
            timeRiftSources = catalog.timeRiftSources, addTranslations = function() end,
            currentAttemptCharacter = function() return character end,
            L = function(value) return value end, getLocale = function() return "enUS" end,
            withImportedAttempts = function(_, raw) return raw + 99 end }
        for id in pairs(roster) do probe.attemptStages[id] = catalog.attemptStages[id] end
        setfenv(assert(loadfile("Core/AttemptStages.lua")), env)("PawAtlas", probe)
        probe.initializeAttemptStages()
        assert(registered.CRITERIA_COMPLETE and registered.SCENARIO_UPDATE and registered.SCENARIO_COMPLETED)
        return probe
    end
    local function event(name, ...) stageCallback(nil, name, ...) end
    local function enter(map, isComplete)
        instance, completed = map, isComplete
        event("PLAYER_ENTERING_WORLD", false, false)
    end
    local function finish(criterion)
        completed = true
        event("SCENARIO_UPDATE")
        event("CRITERIA_COMPLETE", criterion)
        event("CRITERIA_COMPLETE", criterion)
    end
    local function link(id) return "|Hitem:" .. roster[id] .. "|h[mount]|h" end
    local function receipt(id, pushed)
        event("CHAT_MSG_LOOT", (pushed and env.LOOT_ITEM_PUSHED_SELF or env.LOOT_ITEM_SELF):format(link(id)))
    end
    local function toast(id) event("SHOW_LOOT_TOAST", "item", link(id), 1, 0, 0, true) end
    local probe = restart()
    local function progress(id) return probe.timeRiftAttemptProgress({ id = id }) end
    local function award(id) return probe.acquisitionAttempts("mount:" .. id) end

    enter(2634, true)
    finish(60692)
    event("SCENARIO_COMPLETED")
    equal(progress(1777).finals, 0, "joining a completed scenario does not backfill a finale")
    enter(0, false)
    event("CRITERIA_COMPLETE", 60692)
    equal(progress(1777).finals, 0, "the same criterion outside its instance is ignored")
    enter(2634, nil)
    completed = false
    event("SCENARIO_UPDATE")
    event("CRITERIA_COMPLETE", 60690)
    event("SCENARIO_CRITERIA_UPDATE", 60692)
    equal(progress(1777).finals, 0, "unrelated criteria and increment updates are ignored")
    finish(60692)
    equal(progress(1777).finals, 1, "only the eligible Alliance reward gets a Warlands finale")
    equal(progress(1776).finals, 0, "the opposing faction does not get a Warlands attempt")
    equal(progress(1779).finals, 0, "other timelines get no attempt")
    equal(progress(1776).boxes, 2, "existing box openings are preserved without the import floor")
    probe = restart()
    enter(2634, true)
    finish(60692)
    equal(progress(1777).finals, 1, "reload does not replay an already recorded finale")
    enter(2586, false)
    finish(60685)
    equal(progress(1777).finals, 1, "Azmerloth has no mount attempt")

    faction = "Horde"
    enter(2634, false)
    finish(60692)
    equal(progress(1776).finals, 1, "the next Warlands run credits the Horde reward")
    equal(progress(1777).finals, 1, "the Alliance counter is isolated")
    enter(2595, false)
    receipt(1779, true)
    equal(probe.mountLootAttemptsPending(1779), false, "a bare pushed item is no proof of a drop")
    toast(1779)
    equal(probe.mountLootAttemptsPending(1779), true, "personal toast can wait for the associated finale")
    finish(60690)
    equal(award(1779).source, "riftFinal", "a confirmed receipt may precede the finale")
    equal(award(1779).attempts, 1, "the successful event is included in its own route count")

    enter(2635, false)
    finish(60688)
    source, slotLink = "Creature-0-1-2-3-111111-000000001", link(1778)
    event("LOOT_READY")
    event("LOOT_OPENED", false, false)
    receipt(1778)
    event("LOOT_CLOSED")
    equal(award(1778), nil, "an unrelated corpse cannot be mistaken for a finale drop")
    source = "Creature-0-1-2-3-205304-000000002"
    event("LOOT_READY")
    event("LOOT_OPENED", false, false)
    receipt(1778, true)
    event("LOOT_CLOSED")
    equal(award(1778).source, "riftFinal", "a pushed receipt from the correct boss loot slot can follow the finale")

    enter(2593, false)
    finish(60691)
    equal(award(1781), nil, "an older receipt with no source cannot freeze legitimate Rift history")
    event("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", 5)
    receipt(1781, true)
    toast(1781)
    event("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5)
    equal(probe.captureMountAcquisition({ id = 1781 }), nil, "buying or learning the reward cannot freeze attempts")
    enter(0, false)
    receipt(1781)
    equal(award(1781), nil, "an unrelated self-receipt does not use old box history")
    equal(account.acquisitionAttempts["mount:1781"], previousAward, "the ambiguous historical record is preserved")

    source, slotLink, bags = nil, nil, 2
    event("BAG_UPDATE_DELAYED")
    equal(progress(1781).boxes, 4, "receiving a box does not record an opening")
    slotLink = link(1781)
    event("LOOT_OPENED", false, true)
    receipt(1781, true)
    equal(probe.mountLootAttemptsPending(1781), true, "a verified slot receipt may precede consuming the box")
    bags = 1
    event("BAG_UPDATE_DELAYED")
    event("LOOT_CLOSED")
    event("BAG_UPDATE_DELAYED")
    equal(progress(1781).boxes, 5, "the bag change and loot close count one opening")
    equal(progress(1781).finals, 1, "opening the box records no extra finale")
    equal(award(1781).source, "riftBox", "a genuine box receipt works despite the historical import")
    equal(award(1781).attempts, 5, "the frozen award shows only openings")
    equal(award(1781).totalAttempts, 6, "the same award stores the overall attempt number separately")
    equal(progress(1776).boxes, 3, "the box increments eligible Horde rewards")
    equal(progress(1777).boxes, 0, "the box does not increment conflicting faction rewards")
    local aggregate = probe.rewardAttemptProgress({ id = 1781, journalSource = "Vendor: example" })
    equal(aggregate.attempts, 6, "shared progress sums the two local counters")
    equal(aggregate.finals, 1, "shared progress retains the finale count")
    equal(aggregate.boxes, 5, "shared progress retains the box count")
    equal(aggregate.perAttempt, nil, "unverified drop rates stay unknown")
    equal(aggregate.cumulative, nil, "shared progress never mixes probability across sources")
    equal(aggregate.referencePerAttempt, 1 / 500, "the Rift bar uses the Rarity reference rate")
    equal(aggregate.referenceCumulative, 1 - (1 - 1 / 500) ^ 6, "the Rift bar uses the total across both routes")

    slotLink = link(1783)
    event("LOOT_OPENED", true, true)
    bags = 0
    event("BAG_UPDATE_DELAYED")
    event("LOOT_OPENED", true, true)
    event("LOOT_CLOSED")
    clock = clock + 1
    receipt(1783)
    equal(award(1783).source, "riftBox", "a receipt can follow counting and closing the same box")
    equal(award(1783).attempts, 2, "duplicate loot open events do not inflate the box count")

    bags = 1
    event("BAG_UPDATE_DELAYED")
    useItem(207583)
    bags = 0
    event("BAG_UPDATE_DELAYED")
    slotLink = link(1782)
    event("LOOT_OPENED", false, true)
    receipt(1782, true)
    event("LOOT_CLOSED")
    equal(award(1782).attempts, 3, "the bag decrease may precede the item window after an explicit opening")
    equal(award(1782).source, "riftBox", "the same opening supplies the source of the reward")

    slotLink = nil
    enter(2587, false)
    event("SCENARIO_COMPLETED")
    equal(progress(1782).finals, 0, "scenario complete notifications require confirmed current completion")
    completed = true
    event("SCENARIO_COMPLETED")
    equal(progress(1782).finals, 1, "the native scenario completion is repeatable without an achievement update")
    event("CRITERIA_COMPLETE", 60693)
    enter(2639, false)
    finish(60689)
    equal(progress(1782).finals, 1, "Mechagon credits only the corresponding finale")
    equal(progress(1783).finals, 1, "the Lich King credits only the corresponding finale")

    enter(2634, false)
    bags = 1
    event("BAG_UPDATE_DELAYED")
    event("LOOT_OPENED", true, true)
    bags = 0
    event("BAG_UPDATE_DELAYED")
    finish(60692)
    toast(1776)
    equal(award(1776), nil, "overlapping openings and finales cannot prove the source of a personal toast")
    equal(progress(1776).finals, 2, "an ambiguous award preserves the confirmed finale")
    equal(progress(1776).boxes, 6, "an ambiguous award preserves the confirmed opening")
    event("LOOT_CLOSED")

    local chat, timers = {}, {}
    local ownership = { [1776] = false }
    for id in pairs(roster) do if id ~= 1776 and id ~= 1777 then ownership[id] = true end end
    env.C_MountJournal = {
        GetMountInfoByID = function(id) return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, ownership[id] end,
        GetMountFromItem = function(item) for id, reward in pairs(roster) do if reward == item then return id end end end,
    }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
    env.C_Timer = { After = function(delay, callback)
        timers[#timers + 1] = { time = clock + delay, callback = callback }
    end }
    local function advance(seconds)
        local target = clock + seconds
        while true do
            local nextTimer
            for i, timer in ipairs(timers) do
                if timer.time <= target and (not nextTimer or timer.time < timers[nextTimer].time) then nextTimer = i end
            end
            if not nextTimer then break end
            local timer = table.remove(timers, nextTimer)
            clock = timer.time
            timer.callback()
        end
        clock = target
    end
    local function openBox()
        bags = 1
        event("BAG_UPDATE_DELAYED")
        event("LOOT_OPENED", true, true)
        bags = 0
        event("BAG_UPDATE_DELAYED")
    end
    local function chatCount(index, attempts)
        assert(chat[index] and chat[index]:find("#" .. attempts .. " [—]", 1, true), chat[index] or "missing Rift chat line")
    end

    local settings = account.settings
    settings.chatMessages, settings.chatMessageFormat = true, "{mount} #{attempts} [{probability}]"
    settings.mountCollectionMessageFormat = "{mount} #{attempts} [{probability}]"
    faction = "Alliance"
    enter(0, false)
    enter(2634, false)
    finish(60692)
    advance(3.3)
    equal(#chat, 0, "temporarily unreadable ownership defers chat from a cold catalog")
    ownership[1777] = false
    enter(0, false)
    openBox()
    event("BAG_UPDATE_DELAYED")
    event("LOOT_CLOSED")
    event("LOOT_CLOSED")
    advance(9)
    equal(#chat, 2, "one eligible message per ordinary finale and box, even after duplicate events")
    chatCount(1, 2)
    chatCount(2, 3)
    equal(progress(1776).boxes, 6, "opening a box on Alliance still does not change the Horde count")

    enter(2634, false)
    event("LOOT_OPENED", false, false)
    finish(60692)
    advance(2)
    equal(#chat, 2, "the finale does not interrupt the loot window")
    event("LOOT_CLOSED")
    advance(.5)
    equal(#chat, 2, "the finale still waits for late personal loot after the window closes")
    toast(1777)
    receipt(1777)
    probe.notifyMountCollected(1777, "Black Gryphon")
    advance(4)
    equal(#chat, 3, "the successful finale leaves exactly one collection line")
    chatCount(3, 4)
    equal(award(1777).attempts, 3, "the successful finale stores the route count")
    equal(award(1777).totalAttempts, 4, "the successful finale stores the overall count for chat and toast")

    faction = "Horde"
    enter(0, false)
    openBox()
    event("LOOT_CLOSED")
    advance(1.5)
    equal(#chat, 3, "the box waits for delayed personal loot")
    receipt(1776)
    probe.notifyMountCollected(1776, "White War Wolf")
    advance(4)
    equal(#chat, 4, "the successful box leaves exactly one collection line")
    chatCount(4, 9)
    equal(award(1776).attempts, 7, "the successful box stores the route count")
    equal(award(1776).totalAttempts, 9, "the successful box stores an independent overall count")

    enter(2634, false)
    finish(60692)
    settings.chatMessages = false
    advance(4)
    settings.chatMessages, settings.mountCollectionChat = true, false
    enter(0, false)
    openBox()
    event("LOOT_CLOSED")
    advance(.3)
    equal(#chat, 5, "a muted pending finale is not replayed and collection chat can be disabled separately")
    chatCount(5, 11)
    equal(award(1776).totalAttempts, 9, "later attempts cannot alter the frozen success snapshot")

    enter(2634, false)
    openBox()
    finish(60692)
    advance(.3)
    equal(#chat, 5, "an overlapping finale and opening both wait for the loot window")
    event("LOOT_CLOSED")
    advance(.3)
    equal(#chat, 7, "each confirmed route contributes one new total when its events overlap")
    chatCount(6, 12)
    chatCount(7, 13)

    enter(0, false)
    local previousBoxes = progress(1776).boxes
    bags = 2
    event("BAG_UPDATE_DELAYED")
    useItem(207583)
    useItem(207583)
    bags = 0
    event("BAG_UPDATE_DELAYED")
    event("BAG_UPDATE_DELAYED")
    event("LOOT_CLOSED")
    advance(.3)
    equal(progress(1776).boxes, previousBoxes + 2, "two Rift boxes can share one bag update")
    equal(#chat, 9, "each Rift box reports its own attempt")
    local sortRate, sortBar = probe.catalogDropChances({ id = 1776 })
    equal(sortRate, nil, "a reference rate is not a known drop chance")
    equal(sortBar, probe.rewardAttemptProgress({ id = 1776 }).referenceCumulative, "catalog sorts by the displayed rift bar")
    chatCount(8, 14)
    chatCount(9, 15)
    print("PawAtlas Time Rifts passed: timeline, faction, reload, proven acquisitions and ordered chat without duplicates")
end

do
    local turtle = { id = 312, spell = 64731, journalOnly = true }
    local fishingKey, garrisonKey, ridingKey = "mount:312", "mount:312:garrison", "mount:125"
    local character = { stageAttempts = { [fishingKey] = 7 } }
    local previousAward = { item = 46109, attempts = 7 }
    local account = { characters = { player = character }, settings = { chatMessages = false },
        acquisitionAttempts = { [fishingKey] = previousAward } }
    local env = setmetatable({ MountAtlasAccountDB = account, MountAtlasDB = {} }, { __index = _G })
    local callback, lootSource, itemLink, pool, nativeFishing
    local lineID = 40
    local function link(item) return "|Hitem:" .. item .. ":0|h[Item]|h" end
    env._G = env
    env.LOOT_ITEM_SELF = "You receive loot: %s."
    env.CreateFrame = function()
        return { RegisterEvent = function() end, RegisterUnitEvent = function() end,
            SetScript = function(_, _, handler) callback = handler end }
    end
    env.UnitGUID = function(unit) if unit == "player" then return "player" end end
    env.GetLootSourceInfo = function() if lootSource then return lootSource, 1 end end
    env.GetNumLootItems = function() return 1 end
    env.GetLootSlotLink = function() return itemLink end
    env.IsFishingLoot = function() return nativeFishing == true end
    env.C_Map = { GetBestMapForUnit = function() return 116 end }
    env.C_Timer = { After = function(_, run) run() end }
    env.GameTooltipTextLeft1 = { GetText = function() return pool and "Floating Debris Pool" or "Water" end }
    local probe = { mounts = { turtle }, killStatistics = {},
        attemptStages = { [125] = statisticCatalog.attemptStages[125], [312] = statisticCatalog.attemptStages[312] },
        fishingPoolNames = statisticCatalog.fishingPoolNames, addTranslations = function() end,
        currentAttemptCharacter = function() return character end,
        usesKillAPI = function() return false end }
    setfenv(assert(loadfile("Core/AttemptStages.lua")), env)("PawAtlas", probe)
    probe.initializeAttemptStages()
    local function event(name, ...) callback(nil, name, ...) end
    local function receipt(template)
        lineID = lineID + 1
        event("CHAT_MSG_LOOT", template:format(link(46109)), nil, nil, nil, nil, nil, nil, nil, nil, nil, lineID)
    end
    local function count(key) return probe.rawStageAttempts(key) end
    equal(probe.captureMountAcquisition(turtle), nil, "legacy acquisition without source is not evidence of fishing")
    equal(account.acquisitionAttempts[fishingKey], previousAward, "preserve the legacy acquisition record")

    for index, npc in ipairs({ 81171, 85715 }) do
        lootSource = "Creature-0-1-2-3-" .. npc .. "-00000000" .. index
        itemLink = link(123)
        probe.recordStageCreatureKill(lootSource, npc)
        equal(count(garrisonKey), index - 1, "a cavedweller kill alone gives Sea Turtle no attempt")
        equal(count(ridingKey), index - 1, "a cavedweller kill alone gives Riding Turtle no attempt")
        event("LOOT_READY")
        event("LOOT_OPENED", true, false)
        event("LOOT_CLOSED")
        event("LOOT_OPENED", false, false)
        event("LOOT_CLOSED")
        equal(count(garrisonKey), index, "each faction's cavedweller adds one garrison attempt")
        equal(count(ridingKey), index, "Riding Turtle gets its independent attempt on the same corpse")
        equal(count(fishingKey), 7, "looting cavedwellers never adds casts or alters fishing history")
    end
    local route = probe.rewardAttemptProgress(turtle, garrisonKey)
    equal(route.attempts, 2, "the garrison route exposes its own counter")
    equal(route.perAttempt, nil, "the garrison route does not inherit the fishing chance")
    equal(route.cumulative, nil, "unknown garrison drop rate has no cumulative chance")
    equal(probe.rewardAttemptProgress(turtle).perAttempt, 0.0001, "the fishing rate is preserved")

    -- The personal receipt arrives after the first read, with the matching
    -- item slot and corpse unchanged when the game publishes the source.
    lootSource = "Creature-0-1-2-3-81171-000000003"
    itemLink = nil
    event("LOOT_OPENED", true, false)
    receipt(env.LOOT_ITEM_SELF)
    itemLink = link(46109)
    event("LOOT_READY")
    event("LOOT_CLOSED")
    local award = assert(probe.acquisitionAttempts(fishingKey))
    equal(award.attempts, 3, "the confirmed garrison drop freezes the garrison count")
    equal(award.routeKey, garrisonKey, "the award retains the garrison source")

    lootSource, nativeFishing, pool = nil, true, false
    account.acquisitionAttempts[fishingKey] = nil
    event("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-open-water", 131474)
    event("LOOT_OPENED", true, false)
    receipt(env.LOOT_ITEM_SELF)
    event("LOOT_CLOSED")
    equal(count(fishingKey), 7, "open water adds no pool attempt")
    equal(probe.captureMountAcquisition(turtle), nil, "an unmatched receipt cannot be assigned to either route")
    pool = true
    event("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-northrend-pool", 131474)
    event("LOOT_READY")
    event("LOOT_OPENED", true, false)
    event("LOOT_CLOSED")
    receipt(env.LOOT_ITEM_SELF)
    equal(count(fishingKey), 8, "one pool catch counts despite two loot events")
    equal(count(garrisonKey), 3, "fishing does not increment garrison attempts")
    award = assert(probe.acquisitionAttempts(fishingKey))
    equal(award.attempts, 8, "a late fishing receipt uses only the fishing counter")
    equal(award.routeKey, fishingKey, "the fishing success retains the pool source")
    print("PawAtlas Sea Turtle passed: distinct sources, both cavedwellers, corpse deduplication and confirmed route receipts")
end
