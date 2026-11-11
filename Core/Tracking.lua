local _, atlas = ...
local recent = {}
local lockoutsReady = false
local suppressedCharacters = {}
local observeStatisticGrowth = false
local statisticSamples = {}
local brokerStatisticSamples = {}
local brokerStatisticCreditUntil
local questRefreshPending = false
local raidRefreshPending = false

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

local function active(expires, now)
    return validNumber(expires) and expires > (now or GetServerTime())
end

local function refresh()
    if atlas.capturePlanSnapshot then atlas.capturePlanSnapshot(lockoutsReady) end
    if atlas.refreshDetails then atlas.refreshDetails() end
end

local function localKills(mount)
    local counts = type(MountAtlasDB) == "table" and MountAtlasDB.kills
    local count = type(counts) == "table" and counts[mount.countKey or tostring(mount.id)]
    return validNumber(count) and math.floor(count) or 0
end

function atlas.usesKillAPI(mount)
    return atlas.killStatistics[mount.id] ~= nil
end

local function readStatistics(ids)
    if not GetStatistic then return nil end
    local total, samples = 0, {}
    for _, id in ipairs(ids) do
        -- A catalog snapshot can contain a statistic unavailable in this client.
        local ok, value = pcall(GetStatistic, id)
        if not ok then return nil end
        if not readable(value) then return nil end
        local pending = false
        if type(value) == "string" then
            if value:match("^%s*%-%-?%s*$") then value, pending = 0, true
            else
                value = value:gsub(" ", ""):gsub(" ", ""):gsub("[%s,%.]", "")
                value = value:match("^%d+$") and tonumber(value) or nil
            end
        end
        if not validNumber(value) then return nil end
        total = total + math.floor(value)
        if not pending then samples[id] = math.floor(value) end
    end
    return total, samples
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
    refresh()
    if atlas.refreshAccountSettings then atlas.refreshAccountSettings() end
    return true
end

local function saveStatistic(record, id, count, samples)
    if count == nil then return end
    local previous = record.statistics[id]
    local observed = statisticSamples[id] or {}
    statisticSamples[id] = observed
    local increase = 0
    for statisticID, value in pairs(samples or {}) do
        local baseline = observed[statisticID]
        -- A saved total identifies the baseline only for a single statistic.
        -- With several difficulties, a newly loaded component may be old kills.
        if baseline == nil and #atlas.killStatistics[id] == 1 and validNumber(previous) and previous > 0 then
            baseline = previous
        end
        if validNumber(baseline) and value > baseline then increase = increase + value - baseline end
        observed[statisticID] = validNumber(baseline) and math.max(baseline, value) or value
    end
    local grew = observeStatisticGrowth and increase > 0
    if grew and atlas.recordImportedStatistic then
        atlas.recordImportedStatistic(id, UnitGUID("player"), increase)
    end
    -- Lifetime kill statistics are cumulative. During login the API can briefly
    -- return "--"/zero before loading its real value; retain the known baseline.
    record.statistics[id] = validNumber(previous) and math.max(math.floor(previous), count) or count
    if grew and atlas.notifyKillStatistic then
        atlas.notifyKillStatistic(id)
    end
    return grew or record.statistics[id] ~= previous
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
        local count, samples = readStatistics(statistics)
        -- An unavailable API must not erase the last valid character snapshot.
        if saveStatistic(record, id, count, samples) then changed = true end
        -- A card can read the same statistic before the delayed gameplay scan.
        -- Keep its display/import baseline separate from Broker credit.
        local observed = brokerStatisticSamples[id] or {}
        brokerStatisticSamples[id] = observed
        for statisticID, value in pairs(samples or {}) do
            local previous = observed[statisticID]
            if gameplay and previous and value > previous then credited[id] = true end
            if gameplay or not pendingGameplay or not previous then
                observed[statisticID] = previous and math.max(previous, value) or value
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

function atlas.accountCharacters()
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local result = {}
    for guid, record in pairs(type(characters) == "table" and characters or {}) do
        if type(record) == "table" then
            result[#result + 1] = { guid = guid, name = record.name or "—", realm = record.realm or "—", level = record.level }
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
local statisticRetryDelays = { 2, 5, 8, 10, 15, 20 }

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
    statisticSamples = {}
    brokerStatisticSamples, brokerStatisticCreditUntil = {}, nil
    local observed = observeStatisticGrowth
    observeStatisticGrowth = false
    if atlas.resetAttemptStageSession then atlas.resetAttemptStageSession() end
    -- Blizzard's lifetime history cannot be erased. Reload the current character
    -- silently; other character snapshots return when those characters log in.
    syncStatistics()
    refresh()
    observeStatisticGrowth = observed
    if atlas.refreshAccountSettings then atlas.refreshAccountSettings() end
    return true
end

function atlas.rawKills(mount)
    local record = characterCounts()
    local api = atlas.usesKillAPI(mount)
    if api and record then
        local count, samples = readStatistics(atlas.killStatistics[mount.id])
        saveStatistic(record, mount.id, count, samples)
    end
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local total, found = 0, false
    if type(characters) == "table" then
        for _, character in pairs(characters) do
            if type(character) == "table" then
                local counts
                if api then counts = character.statistics else counts = character.kills end
                local key = api and mount.id or (mount.countKey or tostring(mount.id))
                local count = type(counts) == "table" and counts[key]
                if validNumber(count) then total, found = total + math.floor(count), true end
            end
        end
    end
    if api then return found and total or nil end
    -- At login the player's GUID can be unavailable until entering the world.
    local guid = UnitGUID and UnitGUID("player")
    local suppressed = readable(guid) and suppressedCharacters[guid]
    return total + (not record and not suppressed and localKills(mount) or 0)
end

function atlas.kills(mount)
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    local reward = definitions and definitions.reward
    if reward and reward.unverifiedEligibility then
        if reward.rarityEncounterEstimate and atlas.withImportedAttempts then return atlas.withImportedAttempts(mount) end
        return
    end
    local count = atlas.rawKills(mount)
    if atlas.withImportedAttempts then return atlas.withImportedAttempts(mount, count) end
    return count
end

-- Independent eligible attempts: the historical probability is not the chance
-- of the next drop. Container/ingredient rates must not use NPC kill counts.
function atlas.dropProbability(mount)
    if atlas.raidLootRewards and atlas.raidLootRewards[mount.id] then return nil end
    if atlas.rewardChanceEligible and not atlas.rewardChanceEligible(mount) then return nil end
    local progress = atlas.rewardAttemptProgress and atlas.rewardAttemptProgress(mount)
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
    local attempts = tracked and atlas.kills(mount)
    if not validNumber(attempts) or (not overall and item and item.basis ~= "drop") then return perAttempt end
    attempts = math.floor(attempts)
    local cumulative = attempts == 0 and 0 or (1 - (1 - perAttempt) ^ attempts)
    return perAttempt, math.max(0, math.min(1, cumulative)), attempts
end

local function incrementLocal(mount, credited)
    local record = characterCounts()
    local key = mount.countKey or tostring(mount.id)
    local count = record and record.kills[key]
    count = validNumber(count) and math.floor(count) or localKills(mount)
    MountAtlasDB.kills[key] = count + 1
    if record then
        record.kills[key] = count + 1
        credited[mount.id] = true
        if atlas.recordImportedAttempt then atlas.recordImportedAttempt(mount, UnitGUID("player")) end
    end
    if record and atlas.notifyMountAttempt then atlas.notifyMountAttempt(mount) end
end

local function resetAt(frequency)
    local seconds
    if frequency == "weekly" then seconds = C_DateAndTime.GetSecondsUntilWeeklyReset()
    elseif frequency == "daily" then seconds = C_DateAndTime.GetSecondsUntilDailyReset() end
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
    local changed, credited = false, {}
    for _, mount in ipairs(atlas.mounts) do
        if mount.encounter and mount.encounter == encounter and mount.difficulties[difficulty] then
            if atlas.usesKillAPI(mount) then
                RequestRaidInfo()
                queueStatisticRetries()
                changed = true
            else
                local key = encounterKey(mount, difficulty)
                local now = GetTime()
                -- BOSS_KILL and ENCOUNTER_END describe the same kill. Persist known
                -- reset limits so a reload or another locked run cannot add an attempt.
                -- Do not consult the post-kill raid API here: it already includes this kill.
                if not active(MountAtlasDB.lastAttempts[key]) and not (recent[key] and now - recent[key] < 30) then
                    recent[key] = now
                    incrementLocal(mount, credited)
                    MountAtlasDB.lastAttempts[key] = resetAt(atlas.lootFrequency(mount))
                    markVisit(mount)
                    changed = true
                end
            end
        end
    end
    if next(credited) and atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(credited) end
    if changed then refresh() end
end

local function recordLoot()
    if atlas.shouldCountCreatureLoot and not atlas.shouldCountCreatureLoot() then return end
    local now = GetServerTime()
    for guid, expires in pairs(MountAtlasDB.lastLoot) do
        if not active(expires, now) then MountAtlasDB.lastLoot[guid] = nil end
    end
    local slots = GetNumLootItems()
    if not validNumber(slots) then return end
    local changed, credited = false, {}
    for slot = 1, slots do
        local sources = { GetLootSourceInfo(slot) }
        for i = 1, #sources, 2 do
            local guid = sources[i]
            if readable(guid) and type(guid) == "string" then
                local unitType, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
                -- Vehicles can award the same creature loot (for example Felsiege).
                -- Keep objects, items and player GUIDs out of creature attempts.
                local targets = (unitType == "Creature" or unitType == "Vehicle") and atlas.lootByNPC[tonumber(npc)]
                npc = tonumber(npc)
                if targets and not MountAtlasDB.lastLoot[guid] then
                    MountAtlasDB.lastLoot[guid] = now + 86400
                    local limits = {}
                    for _, mount in ipairs(targets) do
                        local frequency = atlas.lootFrequencies[mount.id]
                        local expires = resetAt(frequency)
                        local group = atlas.sharedLootLockouts and atlas.sharedLootLockouts[mount.id]
                        local key = atlas.lootOpportunityKey and atlas.lootOpportunityKey(mount, npc, frequency or "unknown")
                            or "npc:" .. (group or npc) .. ":" .. (frequency or "unknown")
                        local previous = atlas.lootOpportunityExpires and atlas.lootOpportunityExpires(mount, npc, frequency or "unknown")
                            or MountAtlasDB.lastAttempts[key]
                        if atlas.usesKillAPI(mount) then
                            queueStatisticRetries()
                        elseif (not atlas.isMountAttemptEligible or atlas.isMountAttemptEligible(mount, npc))
                            and (not expires or not active(previous, now)) then
                            incrementLocal(mount, credited)
                            if expires then limits[key] = expires end
                            changed = true
                        end
                    end
                    -- Commit after all mounts sharing this corpse have been counted.
                    for key, expires in pairs(limits) do MountAtlasDB.lastAttempts[key] = expires end
                end
            end
        end
    end
    if next(credited) and atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(credited) end
    if changed then refresh() end
end

local function onEvent(event, ...)
    if event == "ENCOUNTER_END" then
        local encounter, _, difficulty, _, success = ...
        if readable(success) and success == 1 then
            countEncounter(encounter, difficulty)
            requestLockoutsAfterKill()
        end
    elseif event == "BOSS_KILL" then
        countEncounter((...), select(3, GetInstanceInfo()))
        requestLockoutsAfterKill()
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
        atlas.refreshAccountStatistics()
        -- Reloading during a fight has no PLAYER_REGEN_DISABLED event. The
        -- initial scan above establishes available baselines; unknown samples
        -- still cannot contribute growth until a real value has been observed.
        if inCombat() then observeStatisticGrowth = true end
        local _, _, difficulty, _, _, _, _, map = GetInstanceInfo()
        if validNumber(map) and validNumber(difficulty) then
            for _, mount in ipairs(atlas.mounts) do
                if mount.map and mount.map == map and mount.difficulties[difficulty] then markVisit(mount) end
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
    if atlas.planTargets then atlas.planTargets() end
    for _, name in ipairs({ "ENCOUNTER_END", "BOSS_KILL", "LOOT_READY", "LOOT_OPENED", "PLAYER_ENTERING_WORLD",
        "PLAYER_LOGOUT", "UPDATE_INSTANCE_INFO", "CRITERIA_UPDATE", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
        "QUEST_LOG_UPDATE", "QUEST_TURNED_IN" }) do
        atlas:RegisterEvent(name, onEvent)
    end
end
