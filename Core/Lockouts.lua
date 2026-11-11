local _, atlas = ...

-- Current loot eligibility only. Never manufacture lifetime attempts from a save.
local ready, worlds, worldsValid, instances = false, {}, false, {}
local function readable(value) return not (issecretvalue and issecretvalue(value)) end
local function number(value)
    return readable(value) and type(value) == "number" and value >= 0 and value < math.huge
end
local function lockDifficulty(map, difficulty, isRaid)
    if not number(difficulty) then return end
    if not isRaid then return difficulty end
    if difficulty <= 0 then return end
    if C_RaidLocks and C_RaidLocks.GetRedirectedDifficultyID then
        local ok, redirected = pcall(C_RaidLocks.GetRedirectedDifficultyID, map, difficulty)
        if not ok or not number(redirected) or redirected <= 0 then return end
        return redirected
    end
    return difficulty
end
local function resetAt(frequency)
    local getter = C_DateAndTime and (frequency == "weekly" and C_DateAndTime.GetSecondsUntilWeeklyReset
        or frequency == "daily" and C_DateAndTime.GetSecondsUntilDailyReset)
    if not getter then return end
    local ok, seconds = pcall(getter)
    if ok and number(seconds) and seconds > 0 then return GetServerTime() + seconds end
end

local accountLootSources = atlas.accountLootSources or {}
local accountLootByItem = {}
for _, rule in pairs(accountLootSources) do accountLootByItem[rule.item] = rule end

local function accountLootRecord(itemID)
    local records = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.accountLootLocks
    local record = type(records) == "table" and records[itemID]
    return type(record) == "table" and record or nil
end

function atlas.accountLootLockout(mount)
    local rule = accountLootSources[mount.id]
    if not rule then return end
    local record = accountLootRecord(rule.item)
    if record and number(record.expires) and record.expires > GetServerTime() then
        return "attempt", record.updated, record.expires
    end
    -- No current receipt can also mean the item dropped while the addon was disabled.
    return "unknown"
end

if next(accountLootByItem) then
    local loot = CreateFrame("Frame")
    loot:RegisterEvent("ENCOUNTER_LOOT_RECEIVED")
    -- Blizzard_FrameXML/BossBannerToast.lua consumes argument 5 as playerName;
    -- LootDocumentation's itemName/fileName labels do not describe that usage.
    loot:SetScript("OnEvent", function(_, _, _, itemID, _, quantity, recipient)
        local rule = number(itemID) and accountLootByItem[itemID]
        if not rule or not number(quantity) or quantity <= 0 or not readable(recipient)
            or type(recipient) ~= "string" or recipient == "" then return end
        local player = GetUnitName and GetUnitName("player", true)
        if not readable(player) or recipient ~= player then return end
        local now, previous = GetServerTime(), accountLootRecord(itemID)
        if previous and number(previous.expires) and previous.expires > now then return end
        local expires = resetAt(rule.frequency)
        if not expires then return end
        if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
        if type(MountAtlasAccountDB.accountLootLocks) ~= "table" then MountAtlasAccountDB.accountLootLocks = {} end
        MountAtlasAccountDB.accountLootLocks[itemID] = { expires = expires, updated = now }
        if atlas.refreshPlanSnapshot then atlas.refreshPlanSnapshot() end
        if atlas.refreshDetails then atlas.refreshDetails() end
    end)
end

function atlas.refreshBossLockouts(isReady)
    ready, worlds, worldsValid, instances = isReady == true, {}, false, {}
    if not ready then return end
    if GetNumSavedWorldBosses and GetSavedWorldBossInfo then
        local ok, count = pcall(GetNumSavedWorldBosses)
        if ok and number(count) then
            worldsValid = true
            for index = 1, count do
                local valid, _, id, reset = pcall(GetSavedWorldBossInfo, index)
                if valid and number(id) and number(reset) then
                    if reset > 0 then worlds[id] = GetServerTime() + reset end
                else worldsValid = false end
            end
        end
    end
    if not GetNumSavedInstances or not GetSavedInstanceInfo then return end
    local ok, count = pcall(GetNumSavedInstances)
    if not ok or not number(count) then return end
    for index = 1, count do
        local valid, _, _, reset, difficulty, locked, extended, _, isRaid, _, _, bosses, _, _, map = pcall(GetSavedInstanceInfo, index)
        if valid and number(map) and map > 0 and number(difficulty) and number(reset) and reset > 0
            and readable(locked) and readable(extended) and (locked == true or extended == true) then
            instances[#instances + 1] = { index = index, map = map,
                difficulty = lockDifficulty(map, difficulty, readable(isRaid) and isRaid == true),
                expires = GetServerTime() + reset, bosses = number(bosses) and bosses or 0 }
        end
    end
end

local function worldState(rule)
    if not ready then return "unknown" end
    local expires = rule.id and worlds[rule.id]
    if number(expires) and expires > GetServerTime() then return "boss", expires end
    local ok, complete
    if rule.quest and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        ok, complete = pcall(C_QuestLog.IsQuestFlaggedCompleted, rule.quest)
    end
    expires = resetAt(rule.frequency)
    if expires and ok and readable(complete) and complete == true then return "boss", expires end
    if expires and ((rule.id and worldsValid) or (ok and readable(complete) and complete == false)) then
        return "available", expires
    end
    return "unknown"
end

local function eligibleDifficulties(mount, view)
    local info = mount.sourceOverride or (atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id])
    local shared = atlas.raidLootReward and atlas.raidLootReward(mount)
    if shared and shared.difficultyID then return { [shared.difficultyID] = true } end
    if info and info.difficultyID then return { [info.difficultyID] = true } end
    local reward = atlas.attemptStages and atlas.attemptStages[mount.id]
    reward = reward and reward.reward
    for _, ids in ipairs({ view.difficulties or false, mount.difficulties or false, (info and info.difficulties) or false,
        (reward and not reward.historical and reward.difficulties) or false }) do
        if type(ids) == "table" and next(ids) then return ids end
    end
    -- A precise Mythic raid label has one numeric mode. Other display kinds
    -- merge different IDs (Heroic/Timewalking, Normal/LFR), so don't guess them.
    if atlas.sourceDifficulty and (view.isRaid or view.sourcePlaceKind == "Рейд" or mount.isRaid) then
        local modes = atlas.sourceDifficulty(view)
        if #modes == 1 and modes[1].kind == "mythic" then return { [16] = true } end
    end
end

local function raidRoute(mount, view)
    if not view.journalEncounter and atlas.resolveSourceEncounter then atlas.resolveSourceEncounter(view) end
    local name, encounter, map
    if view.journalEncounter and EJ_GetEncounterInfo then
        local ok, n, _, _, _, _, _, e, m = pcall(EJ_GetEncounterInfo, view.journalEncounter)
        if ok then name, encounter, map = n, e, m end
    end
    if view == mount and mount.encounter and mount.map then encounter, map = mount.encounter, mount.map end
    if not number(encounter) or encounter <= 0 or not number(map) or map <= 0 then return end
    return { encounter = encounter, map = map, name = readable(name) and name or nil,
        isRaid = view.isRaid or view.sourcePlaceKind == "Рейд" or (view == mount and mount.kind == "Рейд"),
        difficulties = eligibleDifficulties(mount, view) }
end

local function encounterState(route, difficulty, fallbackExpiry)
    local complete, expires
    if C_RaidLocks and C_RaidLocks.IsEncounterComplete then
        local ok, value = pcall(C_RaidLocks.IsEncounterComplete, route.map, route.encounter, difficulty)
        if ok and readable(value) and type(value) == "boolean" then complete = value end
    end
    -- Same saved-instance list as Blizzard's Raid Info. Match the game map,
    -- difficulty and the localized name resolved from this exact journal ID.
    for _, saved in ipairs(instances) do
        if saved.map == route.map and saved.difficulty == difficulty and saved.expires > GetServerTime() then
            expires = saved.expires
            if route.name and GetSavedInstanceEncounterInfo then
                for index = 1, saved.bosses do
                    local ok, name, _, killed = pcall(GetSavedInstanceEncounterInfo, saved.index, index)
                    if ok and readable(name) and name == route.name and readable(killed) and type(killed) == "boolean" then
                        complete = complete == true or killed
                    end
                end
            end
        end
    end
    return complete, expires or fallbackExpiry
end

function atlas.isBossLockoutSource(mount)
    if accountLootSources[mount.id] then return false end
    if atlas.worldBossLocks[mount.id] or mount.encounter then return true end
    for _, view in ipairs(mount.sourceGroups or {}) do
        if view.sourceKind == "Босс" and (view.isRaid or view.sourcePlaceKind == "Подземелье") then return true end
    end
    return false
end

function atlas.bossLockout(mount, selectedView)
    if accountLootSources[mount.id] then return end
    local world = atlas.worldBossLocks[mount.id]
    if world then return worldState(world) end
    if not atlas.isBossLockoutSource(mount) then return end
    if not ready then return "unknown" end
    local fallbackExpiry = resetAt(atlas.lootFrequency(mount))
    local expires
    local views = selectedView and { selectedView } or mount.encounter and { mount } or mount.sourceGroups or {}
    local unknown, available, checked = false, false, false
    for _, view in ipairs(views) do
        local route = raidRoute(mount, view)
        if view.trackingCompatible == false or not route or not route.difficulties then unknown = true
        else
            local seen = {}
            for difficulty, enabled in pairs(route.difficulties) do
                if enabled then
                    difficulty = lockDifficulty(route.map, difficulty, route.isRaid)
                    if not difficulty then unknown = true
                    elseif not seen[difficulty] then
                        seen[difficulty] = true
                        local complete, untilTime = encounterState(route, difficulty, fallbackExpiry)
                        checked = true
                        if complete == false and untilTime then available = true
                        elseif complete ~= true then unknown = true end
                        if untilTime then expires = expires and math.min(expires, untilTime) or untilTime
                        else unknown = true end
                    end
                end
            end
        end
    end
    if available and expires then return "available", expires end
    if checked and not unknown and expires then return "boss", expires end
    return "unknown"
end
