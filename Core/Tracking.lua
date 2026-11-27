local _, atlas = ...
local recent = {}
local lockoutsReady = false
local suppressedCharacters = {}
local observeStatisticGrowth = false
local statisticSamples = {}
local statisticVictories = {}
local npcStatistics, encounterStatistics = {}, {}
local brokerStatisticSamples = {}
local brokerStatisticCreditUntil
local questRefreshPending = false
local raidRefreshPending = false
local encounterTargets, visitTargets = {}, {}
local lastLootPrune
local pendingAttemptRefresh
local bonusRollPrompts, activeBonusRoll = {}, nil
local worldCreatureEvidence, nextWorldCreaturePrune = {}, 0
local npcLootQuestIndex = {}
-- BfA expedition Map.db2 IDs tracked by Rarity: Collector's Edition.
local islandMaps = {
    [1813] = true, [1814] = true, [1879] = true, [1882] = true, [1883] = true, [1892] = true,
    [1893] = true, [1897] = true, [1898] = true, [1907] = true, [2124] = true,
}

local function requestLockoutsAfterKill()
    if raidRefreshPending then return end
    raidRefreshPending = true
    C_Timer.After(1, function()
        raidRefreshPending = false
        RequestRaidInfo()
    end)
end

atlas.addTranslations("enUS", {
    ["В коллекции"] = "Collected",
    ["В плане"] = "Planned",
    ["Попыток: %s"] = "Attempts: %s",
    ["Босс убит"] = "Boss defeated",
    ["Вход отмечен"] = "Visit recorded",
    ["Можно идти"] = "Available",
    ["Ждём данные рейда"] = "Waiting for raid data",
})

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function inCombat()
    local combat = InCombatLockdown and InCombatLockdown()
    return readable(combat) and combat == true
end

local function validNumber(value)
    return readable(value) and type(value) == "number" and value >= 0 and value < math.huge
end

local function modeBoolean(getter, ...)
    local value = getter and getter(...)
    if readable(value) and type(value) == "boolean" then return value end
end

local function warModeToggleStatus(api, desired)
    if modeBoolean(IsInInstance) == true then return false, "instance" end
    if inCombat() or modeBoolean(UnitAffectingCombat, "player") == true then return false, "combat" end
    if desired == nil or not api.ToggleWarMode then return false, "unknown" end
    local allowed = modeBoolean(api.CanToggleWarMode, not desired)
    if allowed == true then return true end
    if allowed == nil then return false, "unknown" end
    if modeBoolean(api.CanToggleWarModeInArea) == false then return false, "area" end
    return false, "restricted"
end

function atlas.warModeToggleStatus()
    local api = C_PvP
    return warModeToggleStatus(api, modeBoolean(api and api.IsWarModeDesired))
end

-- Call only from a hardware click. Native permission checks own the location,
-- level and character restrictions; no desired state is predicted or persisted.
function atlas.toggleWarMode()
    local allowed, reason = atlas.warModeToggleStatus()
    if not allowed then return false, reason end
    C_PvP.ToggleWarMode()
    return true
end

function atlas.currentCharacterModes()
    local api = C_PvP
    local result = {
        warModeActive = modeBoolean(api and api.IsWarModeActive),
        warModeDesired = modeBoolean(api and api.IsWarModeDesired),
        chromieTimeActive = modeBoolean(C_PlayerInfo and C_PlayerInfo.IsPlayerInChromieTime),
    }
    result.warModeCanToggle, result.warModeToggleReason = warModeToggleStatus(api, result.warModeDesired)
    if result.chromieTimeActive == true and UnitChromieTimeID then
        local id = UnitChromieTimeID("player")
        if validNumber(id) and id > 0 then
            result.chromieTimeID = id
            local option = C_ChromieTime and C_ChromieTime.GetChromieTimeExpansionOption
                and C_ChromieTime.GetChromieTimeExpansionOption(id)
            if option and option.id == id and readable(option.name) and type(option.name) == "string" and option.name ~= "" then
                result.chromieTimeName = option.name
            end
        end
    end
    return result
end

local previousModes
local modeEvents = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "WAR_MODE_STATUS_UPDATE", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "PLAYER_LEVEL_UP" }) do
    modeEvents:RegisterEvent(event)
end
modeEvents:RegisterUnitEvent("UNIT_PHASE", "player")
modeEvents:RegisterEvent("PLAYER_FLAGS_CHANGED")
modeEvents:SetScript("OnEvent", function(_, event, unit)
    if (event == "UNIT_PHASE" or event == "PLAYER_FLAGS_CHANGED") and unit ~= "player" then return end
    local current = atlas.currentCharacterModes()
    -- Rest-area and level changes can affect the tooltip even when the toggle stays blocked.
    local changed = previousModes == nil or event == "PLAYER_UPDATE_RESTING" or event == "PLAYER_LEVEL_UP"
    for _, key in ipairs({ "warModeActive", "warModeDesired", "warModeCanToggle", "warModeToggleReason",
        "chromieTimeActive", "chromieTimeID", "chromieTimeName" }) do
        if previousModes and current[key] ~= previousModes[key] then changed = true end
    end
    previousModes = current
    if changed and atlas.refreshCharacterModes then atlas.refreshCharacterModes() end
end)

local function active(expires, now)
    return validNumber(expires) and expires > (now or GetServerTime())
end

local function refresh()
    pendingAttemptRefresh = nil
    if atlas.capturePlanSnapshot then atlas.capturePlanSnapshot(lockoutsReady) end
    if atlas.refreshDetails then atlas.refreshDetails() end
end

function atlas.queueAttemptRefresh(planChanged)
    if atlas.invalidateCatalogAttemptOrder then atlas.invalidateCatalogAttemptOrder() end
    local pending = pendingAttemptRefresh
    if pending then
        if planChanged then pending.capture = true end
        return
    end
    pending = { capture = planChanged }
    pendingAttemptRefresh = pending
    C_Timer.After(0, function()
        if pendingAttemptRefresh ~= pending then return end
        pendingAttemptRefresh = nil
        if pending.capture then refresh()
        elseif atlas.refreshDetails then atlas.refreshDetails() end
    end)
end

local function localKills(mount)
    local counts = type(MountAtlasDB) == "table" and MountAtlasDB.kills
    local count = type(counts) == "table" and counts[mount.countKey or tostring(mount.id)]
    return validNumber(count) and math.floor(count) or 0
end

function atlas.usesKillAPI(mount)
    return atlas.killStatistics[mount.id] ~= nil
end

local function readStatistic(id)
    -- Some historical statistic IDs are unavailable in the current client.
    local ok, value = pcall(GetStatistic, id)
    if not ok or not readable(value) then return end
    if type(value) == "string" then
        if value:match("^%s*%-%-?%s*$") then return false end
        value = value:gsub(" ", ""):gsub(" ", ""):gsub("[%s,%.]", "")
        value = value:match("^%d+$") and tonumber(value) or nil
    end
    if validNumber(value) then return math.floor(value) end
end

local function readStatistics(ids, observed)
    if not GetStatistic then return end
    local total, samples = 0, {}
    for _, id in ipairs(ids) do
        local value = readStatistic(id)
        samples[id] = value
        -- One difficulty can still be loading while another records a kill.
        total = total + math.max(value or 0, observed and observed[id] or 0)
    end
    if next(samples) then return total, samples end
end

-- Account totals retain one contribution per character GUID. Local attempts and
-- API snapshots are separate: API history already includes observed encounters.
local function characterCounts()
    local guid = UnitGUID and UnitGUID("player")
    if not readable(guid) or type(guid) ~= "string" or guid == "" then return nil end
    if suppressedCharacters[guid] then return nil end
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    if type(MountAtlasAccountDB.characters) ~= "table" then MountAtlasAccountDB.characters = {} end
    local record = MountAtlasAccountDB.characters[guid]
    if type(record) ~= "table" then
        record = {}
        MountAtlasAccountDB.characters[guid] = record
    end
    if type(record.kills) ~= "table" then record.kills = {} end
    if type(record.statistics) ~= "table" then record.statistics = {} end
    -- Offline alts still have their own saved kill cache. A shared reset must
    -- invalidate that cache before a later login can migrate or increment it.
    if type(MountAtlasDB) == "table" then
        local generation = validNumber(MountAtlasAccountDB.statisticsGeneration)
            and math.floor(MountAtlasAccountDB.statisticsGeneration) or 0
        local localGeneration = validNumber(MountAtlasDB.statisticsGeneration)
            and math.floor(MountAtlasDB.statisticsGeneration) or 0
        if localGeneration ~= generation then MountAtlasDB.kills = {} end
        MountAtlasDB.statisticsGeneration = generation
    end
    local name, realm
    if UnitFullName then name, realm = UnitFullName("player") end
    if readable(name) and type(name) == "string" and name ~= "" then record.name = name end
    if not realm or realm == "" then realm = GetRealmName and GetRealmName() end
    if readable(realm) and type(realm) == "string" and realm ~= "" then record.realm = realm end
    local level = UnitLevel and UnitLevel("player")
    if validNumber(level) and level > 0 then record.level = math.floor(level) end
    local class
    if UnitClass then class = select(2, UnitClass("player")) end
    if readable(class) and type(class) == "string" and class ~= "" then record.class = class end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if readable(faction) and (faction == "Horde" or faction == "Alliance") then record.faction = faction end
    if not record.migrated and type(MountAtlasDB) == "table" and type(MountAtlasDB.kills) == "table" then
        for key, count in pairs(MountAtlasDB.kills) do
            if validNumber(count) then record.kills[key] = math.floor(count) end
        end
        record.migrated = true
    end
    return record
end

function atlas.islandExpeditionCompletions()
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local total = 0
    for guid, character in pairs(type(characters) == "table" and characters or {}) do
        local count = type(character) == "table" and character.islandExpeditionCompletions
        if not suppressedCharacters[guid] and validNumber(count) then total = total + math.floor(count) end
    end
    return total
end

local function onDifferentMap(map, instanceType, island)
    return validNumber(map) and map ~= island and (map > 0 or (readable(instanceType) and instanceType == "none"))
end

function atlas.pendingIslandExpeditionMap()
    local map = select(8, GetInstanceInfo())
    if validNumber(map) and islandMaps[map] and MountAtlasDB.completedIslandMap ~= map then return map end
end

local function recordIslandCompletion(map)
    if not validNumber(map) or not islandMaps[map] or MountAtlasDB.completedIslandMap == map then return end
    -- ISLAND_COMPLETED is synchronous and only identifies the map and winner.
    -- Ignore a replay after zoning out, but trust the event while instance data loads.
    local _, instanceType, _, _, _, _, _, instanceMap = GetInstanceInfo()
    if onDifferentMap(instanceMap, instanceType, map) then return end
    local character = characterCounts()
    if not character then return end
    MountAtlasDB.completedIslandMap = map
    local count = character.islandExpeditionCompletions
    character.islandExpeditionCompletions = (validNumber(count) and math.floor(count) or 0) + 1
    if atlas.invalidateCatalogAttemptOrder then atlas.invalidateCatalogAttemptOrder() end
    if atlas.settleIslandExpeditionAcquisitions then atlas.settleIslandExpeditionAcquisitions(map) end
    local settings = MountAtlasAccountDB.settings
    if (not settings or settings.chatMessages ~= false) and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("PawAtlas: " .. atlas.L("Пройдено экспедиций: %d", atlas.islandExpeditionCompletions()))
    end
    if atlas.refreshIslandExpeditionDetails then atlas.refreshIslandExpeditionDetails() end
end

-- Stage attempts share character identity/removal with boss statistics, but
-- never inherit a kill count as fishing casts or opened containers.
function atlas.currentAttemptCharacter()
    return characterCounts()
end

function atlas.characterFaction(guid)
    local current = UnitGUID and UnitGUID("player")
    if not readable(current) then current = nil end
    local faction
    if not guid or guid == current then
        faction = UnitFactionGroup and UnitFactionGroup("player")
    else
        local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
        local record = type(characters) == "table" and characters[guid]
        faction = type(record) == "table" and record.faction
    end
    if readable(faction) and (faction == "Horde" or faction == "Alliance") then return faction end
end

function atlas.sourceAvailableToCharacter(npc, guid)
    local required = atlas.npcSourceFactions and atlas.npcSourceFactions[npc]
    if not required then return true end
    local faction = atlas.characterFaction(guid)
    if faction then return required == faction end
end

function atlas.isCharacterSuppressed(guid)
    return suppressedCharacters[guid] == true
end

function atlas.removeAccountCharacter(guid)
    if type(guid) ~= "string" or type(MountAtlasAccountDB) ~= "table"
        or type(MountAtlasAccountDB.characters) ~= "table" then return false end
    local character = MountAtlasAccountDB.characters[guid]
    if not character then return false end
    if atlas.preserveStageDailyLocks then atlas.preserveStageDailyLocks(character) end
    MountAtlasAccountDB.characters[guid] = nil
    if atlas.removeImportedCharacterDelta then atlas.removeImportedCharacterDelta(guid) end
    -- Current-character reads happen during UI refresh; wait for a new login
    -- before allowing them to recreate an explicitly removed record.
    suppressedCharacters[guid] = true
    if atlas.invalidateCatalogAttemptOrder then atlas.invalidateCatalogAttemptOrder() end
    refresh()
    if atlas.refreshAccountSettings then atlas.refreshAccountSettings() end
    return true
end

local statisticRetryDelays = { 2, 5, 8, 10, 15, 20 }
-- After() runs on the next available frame, including the last scheduled scan.
local statisticConfirmationWindow = statisticRetryDelays[#statisticRetryDelays] + 0.5

-- A statistic can update before an encounter or loot event confirms its source.
local function confirmStatisticRise(observed, stat, value, candidate, victory, time)
    if candidate then
        observed.pending = observed.pending or {}
        observed.pending[stat] = { value = value, expires = time + statisticConfirmationWindow }
    end
    local pending = observed.pending and observed.pending[stat]
    if not pending then return false end
    if pending.value ~= value or pending.expires < time then
        observed.pending[stat] = nil
    elseif victory then
        observed.pending[stat] = nil
        return true
    end
    return false
end

local function saveStatistic(record, id, count, samples)
    if count == nil then return end
    local previous = record.statistics[id]
    local observed = statisticSamples[id] or {}
    statisticSamples[id] = observed
    local increase, confirmed = 0, false
    local time = GetTime()
    local singleStatistic = #atlas.killStatistics[id] == 1
    local worldBoss = singleStatistic and atlas.worldBossLocks and atlas.worldBossLocks[id]
    for statisticID, value in pairs(samples or {}) do
        local baseline = observed[statisticID]
        if value == false then
            if baseline == nil then observed[statisticID] = false end
        else
            local sampledBaseline = baseline
            -- Only a single-statistic mount has an unambiguous saved baseline.
            if singleStatistic and validNumber(previous) and previous > 0 then
                baseline = math.max(baseline or 0, previous)
            end
            local victory = (statisticVictories[statisticID] or -1) >= time
            -- Outside combat, world bosses can update an already sampled total
            -- while the same kill's encounter or corpse is still being reported.
            local candidate = count > (previous or 0) and (baseline == false and value == 1
                or worldBoss and not observeStatisticGrowth and validNumber(sampledBaseline) and value == baseline + 1)
            if confirmStatisticRise(observed, statisticID, value, candidate, victory, time) then
                increase, confirmed = increase + 1, true
            elseif validNumber(baseline) and value > baseline and (observeStatisticGrowth or victory) then
                increase = increase + value - baseline
                if victory and not observeStatisticGrowth then confirmed = true end
            end
            observed[statisticID] = math.max(baseline or 0, value)
        end
    end
    local grew = increase > 0
    if grew and atlas.recordImportedStatistic then
        atlas.recordImportedStatistic(id, UnitGUID("player"), increase)
    end
    -- Lifetime kill statistics are cumulative. During login the API can briefly
    -- return "--"/zero before loading its real value; retain the known baseline.
    record.statistics[id] = validNumber(previous) and math.max(math.floor(previous), count) or count
    if confirmed and atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(id) end
    if grew and atlas.notifyKillStatistic then
        atlas.notifyKillStatistic(id)
    end
    local changed = grew or record.statistics[id] ~= previous
    if changed and atlas.invalidateCatalogAttemptOrder then atlas.invalidateCatalogAttemptOrder() end
    return changed
end

function atlas.seedImportedStatistics(guid, statistics)
    local current = UnitGUID and UnitGUID("player")
    if not readable(current) or guid ~= current or suppressedCharacters[guid] or type(statistics) ~= "table" then return end
    for id, ids in pairs(atlas.killStatistics) do
        local samples = statisticSamples[id] or {}
        statisticSamples[id] = samples
        for _, statisticID in ipairs(ids) do
            local value = statistics[statisticID]
            if validNumber(value) then samples[statisticID] = math.max(samples[statisticID] or 0, math.floor(value)) end
        end
    end
end

local function syncStatistics(creditAttempts)
    local record = characterCounts()
    if not record then return end
    local changed, credited = false, {}
    local gameplay = creditAttempts and observeStatisticGrowth
    local pendingGameplay = observeStatisticGrowth
        and (inCombat() or (brokerStatisticCreditUntil and GetTime() <= brokerStatisticCreditUntil))
    for id, statistics in pairs(atlas.killStatistics) do
        local count, samples = readStatistics(statistics, statisticSamples[id])
        -- An unavailable API must not erase the last valid character snapshot.
        if saveStatistic(record, id, count, samples) then changed = true end
        -- A card can read the same statistic before the delayed gameplay scan.
        -- Keep its display/import baseline separate from Broker credit.
        local observed = brokerStatisticSamples[id] or {}
        brokerStatisticSamples[id] = observed
        for statisticID, value in pairs(samples or {}) do
            if value ~= false then
                local previous = observed[statisticID]
                if gameplay and previous and value > previous then credited[id] = true end
                if gameplay or not pendingGameplay or not previous then
                    observed[statisticID] = previous and math.max(previous, value) or value
                end
            end
        end
    end
    if next(credited) and atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(credited) end
    return changed
end

function atlas.accountCharacterCount()
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local count = 0
    for _, record in pairs(type(characters) == "table" and characters or {}) do
        if type(record) == "table" then count = count + 1 end
    end
    return count
end

local function warbandCharacter(guid)
    if not readable(guid) or type(guid) ~= "string" then return end
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local record = type(characters) == "table" and characters[guid]
    if type(record) == "table" then return record end
end

function atlas.isWarbandCharacterHidden(guid)
    local record = warbandCharacter(guid)
    return record ~= nil and record.hiddenFromWarband == true
end

function atlas.setWarbandCharacterHidden(guid, hidden)
    local record = warbandCharacter(guid)
    if not record or type(hidden) ~= "boolean" then return false end
    if (record.hiddenFromWarband == true) == hidden then return true end
    record.hiddenFromWarband = hidden and true or nil
    local saved = MountAtlasAccountDB.settings
    if hidden and type(saved) == "table" and saved.plannerCharacterGUID == guid then
        atlas.selectPlanCharacter(nil)
    end
    if atlas.refreshDetails then atlas.refreshDetails() end
    return true
end

function atlas.accountCharacters(includeHidden)
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local result = {}
    for guid, record in pairs(type(characters) == "table" and characters or {}) do
        if type(record) == "table" and (includeHidden or record.hiddenFromWarband ~= true) then
            result[#result + 1] = { guid = guid, name = record.name or "—", realm = record.realm or "—",
                level = record.level, class = record.class }
        end
    end
    table.sort(result, function(a, b)
        if a.realm ~= b.realm then return a.realm < b.realm end
        if a.name ~= b.name then return a.name < b.name end
        return tostring(a.guid) < tostring(b.guid)
    end)
    return result
end

local scanGeneration = 0
local statisticRetryGeneration = 0
local pendingStatisticScans = {}

local function refreshChangedStatistics(creditAttempts)
    if not syncStatistics(creditAttempts) then return end
    refresh()
end

local function queueStatisticScan(delay, creditAttempts)
    local generation = scanGeneration
    local pending = pendingStatisticScans[delay]
    if pending and pending.generation == generation then
        pending.creditAttempts = pending.creditAttempts or creditAttempts
        return
    end
    pending = { generation = generation, creditAttempts = creditAttempts }
    pendingStatisticScans[delay] = pending
    C_Timer.After(delay, function()
        if generation ~= scanGeneration then return end
        pendingStatisticScans[delay] = nil
        refreshChangedStatistics(pending.creditAttempts)
    end)
end

local function queueStatisticRetries()
    -- Journal-only bosses and prerequisite items may have no encounter/NPC
    -- mapping. Keep Rarity's post-combat retries for delayed API statistics.
    if observeStatisticGrowth then brokerStatisticCreditUntil = GetTime() + statisticRetryDelays[#statisticRetryDelays] end
    queueStatisticScan(.25, true)
    statisticRetryGeneration = statisticRetryGeneration + 1
    local generation, retryGeneration = scanGeneration, statisticRetryGeneration
    for _, delay in ipairs(statisticRetryDelays) do
        C_Timer.After(delay, function()
            if generation ~= scanGeneration or retryGeneration ~= statisticRetryGeneration then return end
            refreshChangedStatistics(true)
        end)
    end
end

local function indexStatisticSource(index, key, stat, source)
    if not key then return end
    local entries = index[key] or {}
    index[key] = entries
    entries[#entries + 1] = { stat = stat, source = source }
end

local function markStatisticVictory(entries, difficulty, map)
    if not entries then return false end
    local time, changed, matched = GetTime(), false, false
    for _, entry in ipairs(entries) do
        local source = entry.source
        if (not source.map or (validNumber(map) and map == source.map))
            and (not source.difficulties or (validNumber(difficulty) and source.difficulties[difficulty])) then
            matched = true
            local untilTime = time + statisticConfirmationWindow
            if untilTime > (statisticVictories[entry.stat] or 0) + 1 then changed = true end
            statisticVictories[entry.stat] = untilTime
        end
    end
    return changed, matched
end

local function readableTable(value)
    return readable(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function confirmBossStatistics(encounter, difficulty, units)
    local _, _, instanceDifficulty, _, _, _, _, map = GetInstanceInfo()
    if not validNumber(difficulty) then difficulty = instanceDifficulty end
    local matched = validNumber(encounter) and markStatisticVictory(encounterStatistics[encounter], difficulty, map)
    if readableTable(units) then
        for _, unit in ipairs(units) do
            if readableTable(unit) and validNumber(unit.creatureID) then
                matched = markStatisticVictory(npcStatistics[unit.creatureID], difficulty, map) or matched
            end
        end
    end
    if matched then queueStatisticRetries() end
end

local function creatureID(guid)
    if not readable(guid) or type(guid) ~= "string" then return end
    local kind, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if kind == "Creature" or kind == "Vehicle" then return tonumber(npc) end
end

local function confirmCreatureStatistics(entries)
    if not entries then return end
    local _, _, difficulty, _, _, _, _, map = GetInstanceInfo()
    local changed, matched = markStatisticVictory(entries, difficulty, map)
    if changed then queueStatisticRetries() end
    return matched
end

function atlas.refreshAccountStatistics()
    scanGeneration = scanGeneration + 1
    brokerStatisticSamples, brokerStatisticCreditUntil = {}, nil
    syncStatistics()
    if atlas.refreshAccountSettings then atlas.refreshAccountSettings() end
    -- Like Rarity, re-read while login statistics reach the client.
    -- Only the current character is queryable; other GUIDs retain their snapshot.
    for _, delay in ipairs(statisticRetryDelays) do queueStatisticScan(delay) end
end

function atlas.clearAttemptStatistics()
    if atlas.cancelRarityImport then atlas.cancelRarityImport() end
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    local account = MountAtlasAccountDB
    account.statisticsGeneration = (validNumber(account.statisticsGeneration)
        and math.floor(account.statisticsGeneration) or 0) + 1
    for _, character in pairs(type(account.characters) == "table" and account.characters or {}) do
        if type(character) == "table" then
            character.kills, character.statistics, character.stageAttempts = {}, {}, {}
            character.collectionItems = nil
            character.factionRewardAttempts = nil
            character.islandExpeditionCompletions = nil
            character.bonusRolls = nil
            character.migrated = true
        end
    end
    account.rarityImport = nil
    account.acquisitionAttempts = nil
    if type(MountAtlasDB) == "table" then
        MountAtlasDB.kills = {}
        MountAtlasDB.statisticsGeneration = account.statisticsGeneration
    end
    -- Drop pending imports/messages and delayed statistic refreshes. Eligibility
    -- locks and loot GUIDs remain intact so one loot window cannot count twice.
    scanGeneration = scanGeneration + 1
    statisticSamples, statisticVictories = {}, {}
    brokerStatisticSamples, brokerStatisticCreditUntil = {}, nil
    bonusRollPrompts, activeBonusRoll = {}, nil
    local observed = observeStatisticGrowth
    observeStatisticGrowth = false
    if atlas.resetAttemptStageSession then atlas.resetAttemptStageSession() end
    if atlas.invalidateCatalogAttemptOrder then atlas.invalidateCatalogAttemptOrder() end
    -- Blizzard's lifetime history cannot be erased. Reload the current character
    -- silently; other character snapshots return when those characters log in.
    syncStatistics()
    refresh()
    observeStatisticGrowth = observed
    if atlas.refreshAccountSettings then atlas.refreshAccountSettings() end
    return true
end

local function savedCount(field, key, additionalField)
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local total, found = 0, false
    if type(characters) == "table" then
        for _, character in pairs(characters) do
            if type(character) == "table" then
                local counts = character[field]
                local count = type(counts) == "table" and counts[key]
                if validNumber(count) then total, found = total + math.floor(count), true end
                local additional = additionalField and character[additionalField]
                local extra = type(additional) == "table" and additional[key]
                if validNumber(extra) then total, found = total + math.floor(extra), true end
            end
        end
    end
    return found and total or nil
end

function atlas.savedStatisticAttempts(id)
    return savedCount("statistics", id, "bonusRolls")
end

function atlas.rawKills(mount)
    local record = characterCounts()
    if atlas.usesKillAPI(mount) then
        if record then
            local count, samples = readStatistics(atlas.killStatistics[mount.id], statisticSamples[mount.id])
            saveStatistic(record, mount.id, count, samples)
        end
        return atlas.savedStatisticAttempts(mount.id)
    end
    local total = savedCount("kills", mount.countKey or tostring(mount.id)) or 0
    -- At login the player's GUID can be unavailable until entering the world.
    local guid = UnitGUID and UnitGUID("player")
    local suppressed = readable(guid) and suppressedCharacters[guid]
    return total + (not record and not suppressed and localKills(mount) or 0)
end

function atlas.kills(mount, savedStatisticsOnly)
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    local reward = definitions and definitions.reward
    if reward and reward.unverifiedEligibility then
        if reward.rarityEncounterEstimate and atlas.withImportedAttempts then return atlas.withImportedAttempts(mount) end
        return
    end
    local count
    if savedStatisticsOnly and atlas.usesKillAPI(mount) then
        count = atlas.savedStatisticAttempts(mount.id)
    else
        count = atlas.rawKills(mount)
    end
    if atlas.withImportedAttempts then return atlas.withImportedAttempts(mount, count) end
    return count
end

-- Independent eligible attempts: the historical probability is not the chance
-- of the next drop. Container/ingredient rates must not use NPC kill counts.
function atlas.dropProbability(mount, savedAttempts, forCatalog)
    if atlas.raidLootRewards and atlas.raidLootRewards[mount.id] then return nil end
    if atlas.rewardChanceEligible and not atlas.rewardChanceEligible(mount) then return nil end
    local progress = atlas.rewardAttemptProgress and atlas.rewardAttemptProgress(mount, nil, forCatalog)
    if progress then return progress.perAttempt, progress.cumulative, progress.attempts end
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    local reward = definitions and definitions.reward
    -- An overall reward rate is already expressed per tracked attempt, even
    -- when the reward is delivered through a container.
    local overall = reward and reward.overall
    local item = atlas.lootItems[mount.id]
    local rate = mount.odds or (item and item.rate)
    if overall then rate = reward.rate end
    if not validNumber(rate) or rate < 1 then return nil end
    local perAttempt = 1 / rate
    if reward and reward.unverifiedEligibility then return perAttempt end
    local tracked = not mount.journalOnly or atlas.usesKillAPI(mount)
    local attempts = tracked and (savedAttempts or atlas.kills(mount, forCatalog))
    if not validNumber(attempts) or (not overall and item and item.basis ~= "drop") then return perAttempt end
    attempts = math.floor(attempts)
    local cumulative = attempts == 0 and 0 or (1 - (1 - perAttempt) ^ attempts)
    return perAttempt, math.max(0, math.min(1, cumulative)), attempts
end

local function incrementLocal(mount, credited, lootNPC, fromLoot)
    local record = characterCounts()
    local key = mount.countKey or tostring(mount.id)
    local count = record and record.kills[key]
    count = validNumber(count) and math.floor(count) or localKills(mount)
    MountAtlasDB.kills[key] = count + 1
    if record then
        record.kills[key] = count + 1
        credited[mount.id] = true
        if atlas.recordImportedAttempt then atlas.recordImportedAttempt(mount, UnitGUID("player"), lootNPC) end
    end
    if record and atlas.notifyMountAttempt then atlas.notifyMountAttempt(mount, fromLoot == true) end
end

local function resetAt(frequency)
    local method = frequency == "weekly" and "GetSecondsUntilWeeklyReset"
        or frequency == "daily" and "GetSecondsUntilDailyReset"
    local getter = method and C_DateAndTime and C_DateAndTime[method]
    local seconds = getter and getter()
    if validNumber(seconds) then return GetServerTime() + seconds end
end

local function encounterKey(mount, difficulty)
    return "encounter:" .. mount.countKey .. ":" .. difficulty
end

function atlas.isKilled(mount)
    return atlas.bossLockout(mount) == "boss"
end

function atlas.status(mount)
    if mount.journalOnly then
        local owned = select(11, C_MountJournal.GetMountInfoByID(mount.id))
        return atlas.L(readable(owned) and owned and "В коллекции" or "В плане")
    end
    if mount.npcs then return atlas.L("Попыток: %s", atlas.kills(mount) or "—") end
    if atlas.isKilled(mount) then return atlas.L("Босс убит") end
    local visits = MountAtlasDB.visits[mount.countKey]
    if visits and active(visits.visit) then return atlas.L("Вход отмечен") end
    return atlas.L(lockoutsReady and "Можно идти" or "Ждём данные рейда")
end

local function markVisit(mount)
    local expires = resetAt(atlas.lootFrequency(mount))
    if not expires then return end
    local visit = MountAtlasDB.visits[mount.countKey] or {}
    visit.visit = expires
    MountAtlasDB.visits[mount.countKey] = visit
end

local function countEncounter(encounter, difficulty)
    if not validNumber(encounter) or not validNumber(difficulty) then return end
    local targets = encounterTargets[encounter]
    if not targets then return end
    targets = targets[difficulty]
    if not targets then return end
    local changed, retryStatistics, credited = false, false, {}
    for _, mount in ipairs(targets) do
        if atlas.usesKillAPI(mount) then
            retryStatistics = true
        else
            local key = encounterKey(mount, difficulty)
            local now = GetTime()
            -- BOSS_KILL and ENCOUNTER_END describe the same kill. Persist known
            -- reset limits so a reload or another locked run cannot add an attempt.
            -- The post-kill raid API already includes this kill.
            if not active(MountAtlasDB.lastAttempts[key]) and not (recent[key] and now - recent[key] < 30) then
                recent[key] = now
                incrementLocal(mount, credited)
                MountAtlasDB.lastAttempts[key] = resetAt(atlas.lootFrequency(mount))
                markVisit(mount)
                changed = true
            end
        end
    end
    if retryStatistics then
        RequestRaidInfo()
        queueStatisticRetries()
    end
    if next(credited) and atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(credited) end
    if changed or retryStatistics then atlas.queueAttemptRefresh(true) end
end

local function lootQuestComplete(quest)
    return modeBoolean(C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted, quest)
end

local function creatureOpportunityAvailable(mount, npc, guid, fromKill)
    local quests = atlas.npcLootQuests and atlas.npcLootQuests[mount.id]
    local quest = quests and quests[npc]
    if not quest or not (npcLootQuestIndex[npc] and npcLootQuestIndex[npc][quest]) then return true end
    local evidence = worldCreatureEvidence[guid]
    local before = evidence and evidence.expires > GetTime() and evidence.quests and evidence.quests[quest]
    if before and active(before.reset) then return not before.complete end
    -- At death, a completed flag without a pre-kill sample can belong to this
    -- kill or to an earlier lockout. Let exact personal loot resolve that case.
    return not fromKill or lootQuestComplete(quest) == false
end

local function recordLoot(fallbackGUID, fromKill)
    if not fromKill and atlas.shouldCountCreatureLoot and not atlas.shouldCountCreatureLoot() then return end
    if not readable(fallbackGUID) then return end
    local slots
    if not fallbackGUID then
        slots = GetNumLootItems()
        if not validNumber(slots) or slots == 0 then return end
    end
    local now = GetServerTime()
    if not lastLootPrune or now - lastLootPrune >= 60 then
        for guid, expires in pairs(MountAtlasDB.lastLoot) do
            if not active(expires, now) then MountAtlasDB.lastLoot[guid] = nil end
        end
        lastLootPrune = now
    end
    local changed, retryStatistics, credited = false, false, {}
    local function recordCorpse(guid)
        -- Vehicles can award the same creature loot (for example Felsiege).
        local npc = creatureID(guid)
        if not npc or active(MountAtlasDB.lastLoot[guid], now) then return end
        local statisticKey = "stat:" .. guid
        local alreadyConfirmed = active(MountAtlasDB.lastLoot[statisticKey], now)
        local confirmed = alreadyConfirmed or confirmCreatureStatistics(npcStatistics[npc])
        local targets = atlas.lootByNPC[npc]
        if fromKill then
            if confirmed then MountAtlasDB.lastLoot[statisticKey] = now + 86400 end
        elseif confirmed or targets then
            MountAtlasDB.lastLoot[guid] = now + 86400
        end
        if targets then
            local limits = {}
            for _, mount in ipairs(targets) do
                local killKey = "kill:" .. mount.id .. ":" .. guid
                local frequency = atlas.lootFrequencies[mount.id]
                local expires = resetAt(frequency)
                local group = atlas.sharedLootLockouts and atlas.sharedLootLockouts[mount.id]
                local key = atlas.lootOpportunityKey and atlas.lootOpportunityKey(mount, npc, frequency or "unknown")
                    or "npc:" .. (group or npc) .. ":" .. (frequency or "unknown")
                local previous = atlas.lootOpportunityExpires and atlas.lootOpportunityExpires(mount, npc, frequency or "unknown")
                    or MountAtlasDB.lastAttempts[key]
                if atlas.usesKillAPI(mount) then
                    retryStatistics = retryStatistics or not alreadyConfirmed
                elseif not active(MountAtlasDB.lastLoot[killKey], now)
                    and creatureOpportunityAvailable(mount, npc, guid, fromKill)
                    and (not atlas.isMountAttemptEligible or atlas.isMountAttemptEligible(mount, npc))
                    and (not expires or not active(previous, now)) then
                    incrementLocal(mount, credited, npc, not fromKill)
                    if fromKill then MountAtlasDB.lastLoot[killKey] = now + 86400 end
                    if expires then limits[key] = expires end
                    changed = true
                end
            end
            -- Commit after all mounts sharing this corpse have been counted.
            for key, expires in pairs(limits) do MountAtlasDB.lastAttempts[key] = expires end
        end
    end
    if fallbackGUID then recordCorpse(fallbackGUID)
    elseif GetLootSourceInfo then
        for slot = 1, slots do
            local sources = { GetLootSourceInfo(slot) }
            for i = 1, #sources, 2 do recordCorpse(sources[i]) end
        end
    end
    if retryStatistics then queueStatisticRetries() end
    if next(credited) and atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(credited) end
    if changed then atlas.queueAttemptRefresh(true) end
end

function atlas.recordCreatureLoot(guid)
    recordLoot(guid)
end

local function inOpenWorld()
    if IsInInstance then return modeBoolean(IsInInstance) == false end
    local _, kind = GetInstanceInfo()
    return readable(kind) and kind == "none"
end

local function unitGUID(unit)
    local guid = UnitGUID and UnitGUID(unit)
    if readable(guid) and type(guid) == "string" and guid ~= "" then return guid end
end

local function tracksCreatureKill(npc)
    return npc and (atlas.lootByNPC[npc] or npcStatistics[npc]
        or (atlas.hasCreatureKillStage and atlas.hasCreatureKillStage(npc)))
end

local function creatureEvidence(guid)
    local time = GetTime()
    if time >= nextWorldCreaturePrune then
        for key, evidence in pairs(worldCreatureEvidence) do
            if evidence.expires <= time then worldCreatureEvidence[key] = nil end
        end
        nextWorldCreaturePrune = time + 60
    end
    local evidence = worldCreatureEvidence[guid]
    if not evidence or evidence.expires <= time then
        evidence = {}
        worldCreatureEvidence[guid] = evidence
    end
    evidence.expires = time + 300
    return evidence
end

local function readCreatureEvidence(unit, evidence)
    evidence.tapDenied = modeBoolean(UnitIsTapDenied, unit)
    local classification = UnitClassification and UnitClassification(unit)
    if readable(classification) and type(classification) == "string" then evidence.minor = classification == "minus" end
end

local function observeCreature(unit)
    if not readable(unit) or type(unit) ~= "string" then return end
    local guid = unitGUID(unit)
    local npc = creatureID(guid)
    if not tracksCreatureKill(npc) then return end
    local evidence = creatureEvidence(guid)
    readCreatureEvidence(unit, evidence)
    local quests = npcLootQuestIndex[npc]
    if quests and modeBoolean(UnitIsDead, unit) == false then
        local samples = evidence.quests or {}
        evidence.quests = samples
        for quest, frequency in pairs(quests) do
            if not samples[quest] or not active(samples[quest].reset) then
                local complete, expires = lootQuestComplete(quest), resetAt(frequency)
                if complete ~= nil and expires then samples[quest] = { complete = complete, reset = expires } end
            end
        end
    end
    return guid, evidence
end

local function liveCreatureUnit(guid)
    local unit = UnitTokenFromGUID and UnitTokenFromGUID(guid)
    if readable(unit) and type(unit) == "string" and unitGUID(unit) == guid then return unit end
    if unitGUID("target") == guid then return "target" end
    if unitGUID("pettarget") == guid then return "pettarget" end
    if unitGUID("mouseover") == guid then return "mouseover" end
end

local function isOurKiller(guid)
    if not readable(guid) or type(guid) ~= "string" then return false end
    if guid == unitGUID("player") or guid == unitGUID("pet") then return true end
    local raid = modeBoolean(IsInRaid) == true
    if not raid and modeBoolean(IsInGroup) ~= true then return false end
    local count = GetNumGroupMembers and GetNumGroupMembers()
    if not validNumber(count) then return false end
    local prefix = raid and "raid" or "party"
    for index = 1, math.min(raid and 40 or 4, raid and count or count - 1) do
        if unitGUID(prefix .. index) == guid then return true end
    end
    return false
end

local function recordWorldCreature(guid, npc, evidence)
    if evidence.recorded or evidence.rejected then return end
    evidence.recorded = true
    if atlas.sourceAvailableToCharacter(npc) ~= true then return end
    recordLoot(guid, true)
    if atlas.recordStageCreatureKill then
        atlas.recordStageCreatureKill(guid, npc, function(mount)
            return creatureOpportunityAvailable(mount, npc, guid, true)
        end)
    end
end

local function onPartyKill(attacker, guid)
    local npc = creatureID(guid)
    if not npc then return end
    if not inOpenWorld() then
        confirmCreatureStatistics(npcStatistics[npc])
        return
    end
    if not tracksCreatureKill(npc) then return end
    local evidence = creatureEvidence(guid)
    local unit = liveCreatureUnit(guid)
    if unit then readCreatureEvidence(unit, evidence) end
    if not isOurKiller(attacker) or evidence.tapDenied == true or evidence.minor then
        evidence.rejected = true
        return
    end
    if evidence.tapDenied ~= false then
        -- A native lifetime statistic can still prove a victory while the
        -- corpse is out of view. Local counters need known loot eligibility.
        if not unit and npcStatistics[npc] then
            local time, key = GetServerTime(), "stat:" .. guid
            if not active(MountAtlasDB.lastLoot[guid], time) and not active(MountAtlasDB.lastLoot[key], time)
                and confirmCreatureStatistics(npcStatistics[npc]) then
                MountAtlasDB.lastLoot[key] = time + 86400
            end
        end
        return
    end
    recordWorldCreature(guid, npc, evidence)
end

local function observePetTarget()
    local guid, evidence = observeCreature("pettarget")
    if not guid or evidence.tapDenied ~= false then return end
    local threat = UnitThreatSituation and UnitThreatSituation("pet", "pettarget")
    if validNumber(threat) then evidence.petEngaged = GetTime() end
end

local function onCreatureDeath(guid)
    local npc = creatureID(guid)
    if not tracksCreatureKill(npc) then return end
    local evidence = creatureEvidence(guid)
    if evidence.recorded or evidence.rejected or evidence.petPending then return end
    local petTarget = unitGUID("pettarget") == guid
    if petTarget then observePetTarget() end
    local unit = liveCreatureUnit(guid)
    if unit then readCreatureEvidence(unit, evidence) end
    if evidence.tapDenied ~= false or evidence.minor then return end
    local engaged = evidence.petEngaged and GetTime() - evidence.petEngaged <= 5
    local hasLoot, canLoot
    if petTarget and CanLootUnit then hasLoot, canLoot = CanLootUnit(guid) end
    if not engaged and not (readable(hasLoot) and hasLoot == true and readable(canLoot) and canLoot == true) then return end
    evidence.petPending = true
    -- UNIT_DIED reports nearby deaths. Leave the more specific PARTY_KILL a
    -- chance to identify the attacker before crediting the pet's target.
    C_Timer.After(.5, function()
        if worldCreatureEvidence[guid] == evidence and inOpenWorld() then recordWorldCreature(guid, npc, evidence) end
    end)
end

local function rememberBonusRollPrompt(spell, promptType, _, duration, currency, cost)
    if not atlas.bonusRollSources then return end
    local bonusType = Enum and Enum.ConfirmationPromptUIType and Enum.ConfirmationPromptUIType.BonusRoll or 1
    if not validNumber(spell) or not validNumber(promptType) or promptType ~= bonusType
        or not validNumber(duration) or duration == 0
        or not validNumber(currency) or not validNumber(cost) or cost ~= 1 then return end
    local source = atlas.bonusRollSources[spell]
    if currency == 0 then currency = BONUS_ROLL_REQUIRED_CURRENCY end
    if not source or not validNumber(currency) or source.currency ~= currency or not atlas.killStatistics[source.mount] then return end
    local time = GetTime()
    local previous = bonusRollPrompts[spell]
    if not previous or (previous ~= activeBonusRoll and previous.expires <= time) then
        bonusRollPrompts[spell] = { source = source, expires = time + duration }
    end
end

local function restoreBonusRollPrompts(initialLogin, reloadingUI)
    if initialLogin == true or reloadingUI == true then
        bonusRollPrompts, activeBonusRoll = {}, nil
    else
        local time = GetTime()
        for spell, prompt in pairs(bonusRollPrompts) do
            if prompt ~= activeBonusRoll and (not prompt.started or prompt.expires <= time) then
                bonusRollPrompts[spell] = nil
            end
        end
    end
    -- Blizzard rebuilds the native roll window from this same pending list.
    local prompts = GetSpellConfirmationPromptsInfo and GetSpellConfirmationPromptsInfo()
    if not readableTable(prompts) then return end
    for _, prompt in ipairs(prompts) do
        if readableTable(prompt) then
            rememberBonusRollPrompt(prompt.spellID, prompt.confirmType, nil, prompt.duration, prompt.currencyID, prompt.currencyCost)
        end
    end
end

local function startBonusRoll()
    -- STARTED has no spell payload. Blizzard keeps the selected spell and its
    -- cost currency on the single bonus roll frame throughout the roll.
    local frame = BonusRollFrame
    local spell = frame and frame:IsShown() and frame.spellID
    local currency = frame and frame.CurrentCountFrame and frame.CurrentCountFrame.currencyID
    local prompt = validNumber(spell) and bonusRollPrompts[spell]
    if prompt and activeBonusRoll == prompt then return end
    activeBonusRoll = nil
    if not prompt or prompt.started or prompt.expires <= GetTime()
        or not validNumber(currency) or prompt.source.currency ~= currency then return end
    prompt.started, prompt.spell = true, spell
    activeBonusRoll = prompt
end

local function finishBonusRoll(rewardType, _, _, _, _, _, _, secondary)
    if not activeBonusRoll or not readable(secondary) or secondary ~= false or not readable(rewardType)
        or (rewardType ~= "item" and rewardType ~= "money" and rewardType ~= "currency") then return end
    local id = activeBonusRoll.source.mount
    activeBonusRoll = nil
    local record = characterCounts()
    if not record then return end
    if type(record.bonusRolls) ~= "table" then record.bonusRolls = {} end
    local previous = record.bonusRolls[id]
    record.bonusRolls[id] = (validNumber(previous) and math.floor(previous) or 0) + 1
    if atlas.recordImportedStatistic then atlas.recordImportedStatistic(id, UnitGUID("player"), 1) end
    if atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(id) end
    if atlas.notifyKillStatistic then atlas.notifyKillStatistic(id) end
    atlas.queueAttemptRefresh(true)
end

local function onEvent(event, ...)
    if event == "ENCOUNTER_END" then
        local encounter, _, difficulty, _, success, units = ...
        if readable(success) and success == 1 then
            confirmBossStatistics(encounter, difficulty, units)
            countEncounter(encounter, difficulty)
            requestLockoutsAfterKill()
        end
    elseif event == "BOSS_KILL" then
        confirmBossStatistics((...))
        countEncounter((...), select(3, GetInstanceInfo()))
        requestLockoutsAfterKill()
    elseif event == "PARTY_KILL" then
        onPartyKill(...)
    elseif event == "UNIT_DIED" then
        if inOpenWorld() then onCreatureDeath(...) end
    elseif event == "UNIT_TARGET" or event == "UNIT_THREAT_SITUATION_UPDATE" then
        local unit = ...
        if readable(unit) and unit == "pet" and inOpenWorld() then observePetTarget() end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        if inOpenWorld() then observeCreature(...) end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if inOpenWorld() then observeCreature("target") end
    elseif event == "SPELL_CONFIRMATION_PROMPT" then
        rememberBonusRollPrompt(...)
    elseif event == "SPELL_CONFIRMATION_TIMEOUT" then
        local spell = ...
        local prompt = validNumber(spell) and bonusRollPrompts[spell]
        if prompt and not prompt.started then bonusRollPrompts[spell] = nil end
    elseif event == "BONUS_ROLL_STARTED" then
        startBonusRoll()
    elseif event == "BONUS_ROLL_FAILED" then
        if activeBonusRoll and bonusRollPrompts[activeBonusRoll.spell] == activeBonusRoll then
            bonusRollPrompts[activeBonusRoll.spell] = nil
        end
        activeBonusRoll = nil
    elseif event == "BONUS_ROLL_RESULT" then
        finishBonusRoll(...)
    elseif event == "ISLAND_COMPLETED" then
        recordIslandCompletion(...)
    elseif event == "LOOT_READY" then
        recordLoot()
    elseif event == "LOOT_OPENED" then
        -- Source GUIDs can become available only when the loot window opens.
        -- The saved corpse GUID prevents recounting a successful LOOT_READY.
        local _, fromItem = ...
        if readable(fromItem) and not fromItem then recordLoot() end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Establish the current character's baseline before the first fight.
        -- A first login can reveal old kills already included in an import.
        if not observeStatisticGrowth then
            refreshChangedStatistics()
            observeStatisticGrowth = true
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        queueStatisticRetries()
    elseif event == "PLAYER_ENTERING_WORLD" then
        worldCreatureEvidence, nextWorldCreaturePrune = {}, 0
        if inOpenWorld() then observeCreature("target") end
        if atlas.bonusRollSources then restoreBonusRollPrompts(...) end
        atlas.refreshAccountStatistics()
        -- Reloading during a fight has no PLAYER_REGEN_DISABLED event. The
        -- initial scan above establishes available baselines; unknown samples
        -- still cannot contribute growth until a real value has been observed.
        if inCombat() then observeStatisticGrowth = true end
        local _, instanceType, difficulty, _, _, _, _, map = GetInstanceInfo()
        -- A reload on the completed island preserves its marker. A confirmed
        -- map change lets the character count another run on that same island.
        if MountAtlasDB.completedIslandMap and onDifferentMap(map, instanceType, MountAtlasDB.completedIslandMap) then
            MountAtlasDB.completedIslandMap = nil
        end
        if validNumber(map) and validNumber(difficulty) then
            local targets = visitTargets[map]
            if targets then
                for _, mount in ipairs(targets[difficulty] or {}) do markVisit(mount) end
            end
        end
        RequestRaidInfo()
        refresh()
    elseif event == "UPDATE_INSTANCE_INFO" then
        lockoutsReady = true
        refresh()
    elseif event == "CRITERIA_UPDATE" then
        queueStatisticScan(.25, inCombat())
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_TURNED_IN" then
        if not questRefreshPending then
            questRefreshPending = true
            C_Timer.After(.1, function()
                questRefreshPending = false
                refresh()
            end)
        end
    elseif event == "PLAYER_LOGOUT" then
        syncStatistics()
        if atlas.capturePlanSnapshot then atlas.capturePlanSnapshot(lockoutsReady) end
    end
end

local function indexTarget(index, key, difficulty, mount)
    local byDifficulty = index[key]
    if not byDifficulty then byDifficulty = {}; index[key] = byDifficulty end
    local targets = byDifficulty[difficulty]
    if not targets then targets = {}; byDifficulty[difficulty] = targets end
    targets[#targets + 1] = mount
end

function atlas.initializeTracking()
    if type(MountAtlasDB) ~= "table" then MountAtlasDB = {} end
    for _, key in ipairs({ "kills", "visits", "lastLoot", "lastAttempts", "plan", "minimap" }) do
        if type(MountAtlasDB[key]) ~= "table" then MountAtlasDB[key] = {} end
    end
    for key, value in pairs(MountAtlasDB.kills) do
        MountAtlasDB.kills[key] = validNumber(value) and math.floor(value) or nil
    end
    for _, name in ipairs({ "lastLoot", "lastAttempts" }) do
        for key, expires in pairs(MountAtlasDB[name]) do
            if not active(expires) then MountAtlasDB[name][key] = nil end
        end
    end
    for key, visit in pairs(MountAtlasDB.visits) do
        if type(visit) ~= "table" then MountAtlasDB.visits[key] = nil
        else
            if not validNumber(visit.visit) then visit.visit = nil end
            if not validNumber(visit.kill) then visit.kill = nil end
        end
    end
    -- Preserve existing single-difficulty kill markers without assigning them
    -- to every difficulty of a target that may gain more sources later.
    for _, mount in ipairs(atlas.mounts) do
        if mount.encounter or mount.map then
            for difficulty, enabled in pairs(mount.difficulties or {}) do
                if enabled then
                    if mount.encounter then indexTarget(encounterTargets, mount.encounter, difficulty, mount) end
                    if mount.map then indexTarget(visitTargets, mount.map, difficulty, mount) end
                end
            end
        end
        if mount.encounter then
            local difficulty = next(mount.difficulties)
            local visit = MountAtlasDB.visits[mount.countKey]
            if difficulty and not next(mount.difficulties, difficulty) and visit and active(visit.kill) then
                local key = encounterKey(mount, difficulty)
                MountAtlasDB.lastAttempts[key] = math.max(MountAtlasDB.lastAttempts[key] or 0, visit.kill)
            end
        end
    end
    characterCounts()
    for stat, sources in pairs(atlas.killStatisticSources or {}) do
        for _, source in ipairs(sources) do
            indexStatisticSource(npcStatistics, source.npc, stat, source)
            indexStatisticSource(encounterStatistics, source.encounter, stat, source)
        end
    end
    for id, quests in pairs(atlas.npcLootQuests or {}) do
        local frequency = atlas.lootFrequencies[id]
        if frequency == "daily" or frequency == "weekly" then
            for npc, quest in pairs(quests) do
                if validNumber(npc) and validNumber(quest) and quest > 0 then
                    local index = npcLootQuestIndex[npc] or {}
                    npcLootQuestIndex[npc] = index
                    if not index[quest] or frequency == "daily" then index[quest] = frequency end
                end
            end
        end
    end
    if atlas.planTargets then atlas.planTargets() end
    for _, name in ipairs({ "ENCOUNTER_END", "BOSS_KILL", "LOOT_READY", "LOOT_OPENED", "PLAYER_ENTERING_WORLD",
        "PLAYER_LOGOUT", "UPDATE_INSTANCE_INFO", "CRITERIA_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "ISLAND_COMPLETED" }) do
        atlas:RegisterEvent(name, onEvent)
    end
    for _, name in ipairs({ "PARTY_KILL", "UNIT_DIED", "UNIT_TARGET", "UNIT_THREAT_SITUATION_UPDATE",
        "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_TARGET_CHANGED" }) do
        if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(name) then
            atlas:RegisterEvent(name, onEvent)
        end
    end
    if atlas.bonusRollSources then
        for _, name in ipairs({ "SPELL_CONFIRMATION_PROMPT", "SPELL_CONFIRMATION_TIMEOUT", "BONUS_ROLL_STARTED",
            "BONUS_ROLL_FAILED", "BONUS_ROLL_RESULT" }) do
            if not C_EventUtils or not C_EventUtils.IsEventValid or C_EventUtils.IsEventValid(name) then
                atlas:RegisterEvent(name, onEvent)
            end
        end
    end
end
