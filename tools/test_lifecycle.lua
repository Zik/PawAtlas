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
    equal(id, 501, "kill statistic ID")
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
local atlas = {
    mounts = { boss, oldBoss, rare, { id = 4, journalOnly = true } },
    attemptStages = { [4] = { reward = stage }, [6] = { reward = stageRare } },
    killStatistics = { [5] = { 501 } },
    lootByNPC = { [601] = { rare } },
    lootFrequencies = {},
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
local snapshotCount = #snapshots
statistic = 9
fire("PLAYER_LOGOUT")
equal(character.statistics[5], 9, "logout saves the latest character statistic")
equal(#snapshots, snapshotCount + 1, "logout saves a planner snapshot")
equal(snapshots[#snapshots], true, "logout preserves raid-data readiness")
print("PawAtlas lifecycle passed: saved data, first world entry, encounter and loot deduplication, logout")

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
    local sceneTime, covenant = now, 0
    local bagCount, bagReads, requests, boxSpell = 3, 0, 0, nil
    local character = {}
    local account = { settings = {}, characters = { player = character } }
    local env = setmetatable({ MountAtlasAccountDB = account, MountAtlasDB = { lastAttempts = {} } }, { __index = _G })
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
    env.C_QuestLog = { IsQuestFlaggedCompletedOnAccount = function(id) return id == 90474 end }
    env.C_Covenants = { GetActiveCovenantID = function() return covenant end }
    env.C_Item = {
        GetItemCount = function(id, bank)
            if id == 900001 and not bank then bagReads = bagReads + 1; return bagCount end
        end,
        GetItemSpell = function(id) if id == 900001 then return "Container spell", boxSpell end end,
        RequestLoadItemDataByID = function() requests = requests + 1 end,
    }
    env.GetNumLootItems = function() return source and 1 or 0 end
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
    for _, id in ipairs({ 400, 1395, 1426, 2159, 2749 }) do
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
    equal(#messages, 1, "known collection rate still announces")
    testAtlas.attemptStages[2749].item.rate = nil
    testAtlas.attemptStages[2749].item.required = 1
    source = "Creature-0-1-2-3-12345-000000003"
    event("LOOT_READY")
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
    equal(#messages, before + 1, "cache attempt announces once")
    event("LOOT_CLOSED")
    source = "GameObject-0-1-2-3-354175-000000002"
    event("LOOT_OPENED", false, false)
    equal(testAtlas.rawStageAttempts("mount:1426"), 1, "the cache respects its daily limit before the catalog opens")
    event("LOOT_CLOSED")

    sceneTime = sceneTime + 3601
    source = nil -- This event sequence exposes only the localized tooltip and cast.
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
    equal(#messages, before + 2, "late exact GUID does not duplicate a tooltip-based notification")
    event("LOOT_CLOSED")
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
    print("PawAtlas attempt events passed: collection messages, figurines, cache identity and deduplication")
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
    equal(#inserted, 1, "unfocused WIM does not steal active chat link")
    active = nil
    assert(links.linkMount(400), "no active editor opens a draft")
    equal(#opened, 1, "no active editor opens exactly one draft")
    print("PawAtlas chat links passed: WIM priority, native quest links, async context and Blizzard fallback")
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
        MountAtlasAccountDB = { settings = { gameTooltips = true } },
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
    callbacks[1](tooltip, data)
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
    local time = 0
    local settings = { rewardToast = false, chatMessages = false }
    local character = { stageAttempts = { ["mount:2"] = 5, ["mount:3"] = 8, ["mount:7"] = 60 } }
    local account = { settings = settings, characters = { player = character } }
    local env = setmetatable({ MountAtlasAccountDB = account }, { __index = _G })
    env._G, env.LOOT_ITEM_SELF = env, "You receive loot: %s."
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
        GetMountFromItem = function(item) if item > 1000 and item < 1008 then return item - 1000 end end,
        GetMountInfoByID = function(id)
            if loaded[id] then return "Маунт " .. id, 99, 123, nil, nil, nil, nil, nil, nil, nil, mounted[id] end
        end,
    }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
    local notifications = {
        ui = {}, mounts = {}, addTranslations = function() end, getLocale = function() return "ruRU" end,
        L = function(message) return message end,
        currentAttemptCharacter = function() return character end,
        killStatistics = {},
        attemptStages = {
            [2] = { reward = { key = "mount:2", item = 1002, method = "ENCOUNTER", encounters = { 100 } } },
            [3] = { reward = { key = "mount:3", item = 1003, method = "ENCOUNTER", encounters = { 101 } } },
            [7] = { reward = { key = "mount:7", item = 1007, method = "ENCOUNTER", encounters = { 102 } } },
        },
    }
    local catalog = {}
    for _, path in ipairs({ "Data/JournalData.lua", "Data/LootSources.lua" }) do
        assert(loadfile(path))("PawAtlas", catalog)
    end
    for _, id in ipairs({ 1313, 538, 539, 540 }) do notifications.attemptStages[id] = catalog.attemptStages[id] end
    notifications.guaranteedRewards, notifications.lootItems = catalog.guaranteedRewards, catalog.lootItems
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
    settings.chatMessages = false
    settings.mountCollectionMessageFormat = "{название} #{попытки} ({вероятность})"
    receipt("You receive loot: " .. scale .. ".", 501)
    receipt("You receive loot: " .. scale .. ".", 501)
    character.stageAttempts["item:174230"] = 2
    advance(.2)
    equal(chat[3], scale .. " #2 (3,96%)", "actual scale drop includes final attempt and shared custom format")
    equal(#chat, 3, "duplicate loot line announces only once")
    local egg = "|Hitem:94295|h[Primal Egg]|h"
    character.stageAttempts["item:94295"] = 8
    receipt("Another player receives loot: " .. egg .. ".", 502)
    receipt("You receive loot: " .. egg .. ".", 503)
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
end
