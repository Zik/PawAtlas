local _, atlas = ...
local events = CreateFrame("Frame")
local stages, bags, pendingUses, itemSpells = {}, {}, {}, {}
local stagesByMethod, npcStages, specialSpells = {}, {}, {}
local encounterStages, useStages, mapVisits, gossipStages, archaeologyRaces = {}, {}, {}, {}, {}
local objectNodes = {}
local lootQuests = {}
local timeRifts = { container = 207583, byInstance = {}, byItem = {}, receiptWindow = 3 }
local unresolvedItemSpells = {}
local acquisitionItems, collectionReceipts, prerequisiteOwners = {}, {}, {}
local mountsByID = {}
local interactions, archaeology, visits, gossipOpen = {}, {}, {}, {}
local ready, lootCounted, itemLootUntil, enteredWorld = false, false, 0, false
local itemLootOpen, itemLootSettled = false, false
local cast, lastNode, openingHover, notificationGuard
local creatureLoot
local npcItemLoot = { items = {} }
local npcLootReceiptWindow = 3
local recentEvents = {}
local pendingStageMessages = {}
local lootChat, lootChatOpen = {}, false
local queueLootChat
local pendingAcquisitions = {}
local lastLootPrune, lastCollectionPrune = 0, 0
local sessionGeneration = 0

-- Prerequisite boss drops can have their own lifetime statistic. Reuse the
-- account statistic merger, under the item's key rather than a mount counter.
for _, definitions in pairs(atlas.attemptStages or {}) do
    local definition = definitions.item
    if definition and definition.key and definition.statisticId and #definition.statisticId > 0 then
        atlas.killStatistics[definition.key] = definition.statisticId
    end
end

atlas.addTranslations("enUS", {
    ["PawAtlas: {название} — попытка {попытки} · вероятность за попытки: {вероятность}"] =
        "PawAtlas: {mount} — attempt {attempts} · probability across attempts: {probability}",
    ["PawAtlas: {название} — попытка {попытки}"] = "PawAtlas: {mount} — attempt {attempts}",
    ["<0,01%"] = "<0.01%",
})

local function readable(v)
    return not (issecretvalue and issecretvalue(v))
end

local function number(v)
    return readable(v) and type(v) == "number" and v >= 0 and v < math.huge
end

local function safe(fn, ...)
    if type(fn) ~= "function" then return end
    local ok, a, b, c, d = pcall(fn, ...)
    if ok and readable(a) then return a, b, c, d end
end

local function now()
    return safe(GetTime) or 0
end

local function serverTime()
    return safe(GetServerTime) or 0
end

local function contains(values, value)
    if value == nil or type(values) ~= "table" then return false end
    if values[value] == true or values[tostring(value)] == true then return true end
    for _, candidate in ipairs(values) do
        if candidate == value or tostring(candidate) == tostring(value) then return true end
    end
    return false
end

local function mapID()
    return C_Map and safe(C_Map.GetBestMapForUnit, "player")
end

local function inZone(definition)
    local hasZones = definition.zones and next(definition.zones)
    if not definition.excludedMaps and not hasZones then return true end
    local map = mapID()
    if definition.excludedMaps and contains(definition.excludedMaps, map) then return false end
    if not hasZones then return true end
    if definition.includeChildMaps and C_Map and C_Map.GetMapInfo then
        local parent = map
        for _ = 1, 8 do
            if contains(definition.zones, parent) then return true end
            local info = safe(C_Map.GetMapInfo, parent)
            if type(info) ~= "table" or not number(info.parentMapID) or info.parentMapID == parent or info.parentMapID == 0 then break end
            parent = info.parentMapID
        end
    end
    return contains(definition.zones, map) or contains(definition.zones, safe(GetRealZoneText))
        or contains(definition.zones, safe(GetSubZoneText))
end

local function eligible(definition, heldBeforeLoot)
    if not inZone(definition) then return false end
    if definition.requiresHorde or definition.requiresAlliance then
        local faction = safe(UnitFactionGroup, "player")
        if definition.requiresHorde and faction ~= "Horde" then return false end
        if definition.requiresAlliance and faction ~= "Alliance" then return false end
    end
    if definition.disableForClass then
        local _, class = safe(UnitClass, "player")
        if readable(class) and contains(definition.disableForClass, class) then return false end
    end
    if definition.requiredCovenantID then
        local covenant = C_Covenants and safe(C_Covenants.GetActiveCovenantID)
        if covenant ~= definition.requiredCovenantID then return false end
    end
    if definition.requiredRenown then
        local requirement = definition.requiredRenown
        local info = C_MajorFactions and safe(C_MajorFactions.GetMajorFactionData, requirement.factionID)
        if type(info) ~= "table" or not number(info.renownLevel) or info.renownLevel < requirement.level then return false end
    end
    for _, quest in ipairs(definition.requiresCompletedQuestId or {}) do
        if not (C_QuestLog and safe(C_QuestLog.IsQuestFlaggedCompleted, quest)) then return false end
    end
    if definition.requiresAccountQuest then
        local quest = definition.requiresAccountQuest
        local unlocked = C_QuestLog and (safe(C_QuestLog.IsQuestFlaggedCompletedOnAccount, quest)
            or safe(C_QuestLog.IsQuestFlaggedCompleted, quest))
        if unlocked ~= true then return false end
    end
    if definition.requiredAreaPOIs then
        local active = C_AreaPoiInfo and safe(C_AreaPoiInfo.GetAreaPOIForMap, mapID())
        local found = false
        for _, id in ipairs(type(active) == "table" and active or {}) do
            if contains(definition.requiredAreaPOIs, id) then found = true end
        end
        if not found then return false end
    end
    if definition.difficulties or definition.requiredDungeons or definition.instanceID then
        local values = GetInstanceInfo and { GetInstanceInfo() } or {}
        if definition.difficulties and next(definition.difficulties)
            and (not readable(values[3]) or not contains(definition.difficulties, values[3])) then return false end
        if definition.requiredDungeons and next(definition.requiredDungeons)
            and (not readable(values[10]) or not contains(definition.requiredDungeons, values[10])) then return false end
        if definition.instanceID and (not readable(values[8]) or values[8] ~= definition.instanceID) then return false end
    end
    if definition.unique then
        if heldBeforeLoot == false then return false end
        local count = heldBeforeLoot or (C_Item and safe(C_Item.GetItemCount, definition.item, false, false, false, false))
        if number(count) and count > 0 then return false end
    end
    return true
end

local function record()
    local character = atlas.currentAttemptCharacter and atlas.currentAttemptCharacter()
    if character then
        if type(character.stageAttempts) ~= "table" then character.stageAttempts = {} end
        if type(character.stageLootGUIDs) ~= "table" then character.stageLootGUIDs = {} end
    end
    return character
end

local function refreshAttempts(planChanged)
    if atlas.queueAttemptRefresh then atlas.queueAttemptRefresh(planChanged); return end
    if planChanged and atlas.refreshPlanSnapshot then atlas.refreshPlanSnapshot() end
    if atlas.refreshDetails then atlas.refreshDetails() end
end

function atlas.rawStageAttempts(key)
    if atlas.killStatistics[key] then return atlas.rawKills({ id = key }) end
    local value = 0
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    for guid, character in pairs(type(characters) == "table" and characters or {}) do
        if not (atlas.isCharacterSuppressed and atlas.isCharacterSuppressed(guid)) then
            local count = type(character) == "table" and type(character.stageAttempts) == "table"
                and character.stageAttempts[key]
            if number(count) then value = value + math.floor(count) end
        end
    end
    return value
end

local function total(key, savedStatistics)
    local raw
    if savedStatistics and atlas.killStatistics[key] then
        raw = atlas.savedStatisticAttempts and atlas.savedStatisticAttempts(key)
    else
        raw = atlas.rawStageAttempts(key)
    end
    return atlas.withImportedAttempts and atlas.withImportedAttempts({ id = key }, raw) or raw
end

local function collectionItems(definition)
    if definition and number(definition.required) and definition.required > 0 and number(definition.item) then
        return definition.collectedItems or { definition.item }
    end
end

function atlas.rawItemCollection(mount, baseline, snapshot)
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    local items = definitions and collectionItems(definitions.item)
    local counts = snapshot and {} or nil
    if not items then return nil, 0, counts end
    local raw, delta = nil, 0
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    for guid, character in pairs(type(characters) == "table" and characters or {}) do
        local acquired = type(character) == "table" and character.collectionItems
        if type(acquired) == "table" and not atlas.isCharacterSuppressed(guid) then
            local quantity = 0
            for _, item in ipairs(items) do
                local value = acquired[item]
                if number(value) then quantity = quantity + math.floor(value) end
            end
            if quantity > 0 then
                raw = (raw or 0) + quantity
                local previous = type(baseline) == "table" and baseline[guid]
                delta = delta + math.max(0, quantity - (number(previous) and previous or 0))
                if counts then counts[guid] = quantity end
            end
        end
    end
    return raw, delta, counts
end

function atlas.itemCollectionCount(mount)
    local imported, baseline
    if atlas.rarityImportedCollection then imported, baseline = atlas.rarityImportedCollection(mount) end
    local raw, delta = atlas.rawItemCollection(mount, baseline)
    if imported then return math.max(raw or 0, imported + delta) end
    return raw
end

local function acquisitionReward(key)
    if type(key) ~= "string" then return end
    local id = tonumber(key:match("^mount:(%d+)$") or key:match("^mount:(%d+):"))
    local definitions = id and atlas.attemptStages and atlas.attemptStages[id]
    if id and key == "mount:" .. id then return definitions and definitions.reward, id end
    local reward = definitions and definitions.alternateReward
    if reward and reward.key == key then return reward, id end
end

local function timeRiftSource(id)
    return id and atlas.timeRiftSources and atlas.timeRiftSources[id]
end

local function factionImportAcquisition(id, saved)
    return type(saved) == "table" and saved.source == "rarity" and id
        and atlas.rarityFactionRewardVariants and atlas.rarityFactionRewardVariants(id)
end

local function islandMount(id)
    return id and atlas.islandSalvageMounts and atlas.islandSalvageMounts[id]
end

-- Freeze success counts; later farming and imports must not rewrite an award.
function atlas.rememberAcquisition(key, attempts, item, acquiredAt, confirmedLoot, islandProgress, riftSource, riftTotal, routeKey)
    if not number(attempts) or attempts < 1 then return end
    local reward, id = acquisitionReward(key)
    if reward and reward.unverifiedEligibility then return end
    local source, totalAttempts
    if timeRiftSource(id) then
        source = riftSource
        if not confirmedLoot or (source ~= "riftFinal" and source ~= "riftBox") then return end
        -- Keep the successful route count and the overall count as two snapshots.
        key = "rift:" .. key
        if number(riftTotal) and riftTotal >= attempts then totalAttempts = math.floor(riftTotal) end
    end
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    local records = MountAtlasAccountDB.acquisitionAttempts
    if type(records) ~= "table" then records = {}; MountAtlasAccountDB.acquisitionAttempts = records end
    local previous = records[key]
    if not previous or (confirmedLoot and factionImportAcquisition(id, previous))
        or (routeKey and (type(previous) ~= "table" or not previous.routeKey or confirmedLoot and previous.source == "rarity")) then
        records[key] = { attempts = math.floor(attempts), item = item,
        time = number(acquiredAt) and acquiredAt or serverTime(),
        confirmedLoot = confirmedLoot == true or nil,
        islandProgress = islandProgress,
        totalAttempts = totalAttempts,
        routeKey = routeKey,
        source = source or (reward and reward.rarityIncompatible and "local" or nil) }
    end
    return records[key]
end

function atlas.acquisitionAttempts(key)
    local records = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.acquisitionAttempts
    local reward, id = acquisitionReward(key)
    local rift = timeRiftSource(id)
    if rift then key = "rift:" .. key end
    local record = type(records) == "table" and records[key]
    if type(record) ~= "table" or not number(record.attempts) or record.attempts <= 0 then return end
    if rift and (record.confirmedLoot ~= true or (record.source ~= "riftFinal" and record.source ~= "riftBox")) then return end
    if reward and reward.unverifiedEligibility then return end
    if reward and reward.requiresLootSource then
        local route, routeID = acquisitionReward(record.routeKey)
        if not (route and routeID == id and route.item == record.item and record.confirmedLoot == true)
            and record.source ~= "rarity" then return end
    end
    if factionImportAcquisition(id, record) then return end
    -- Older island receipts contain only the container count.
    if islandMount(id) and type(record.islandProgress) ~= "table" then return end
    if not rift and reward and reward.rarityIncompatible and record.source ~= "local" then
        local imported = MountAtlasAccountDB.rarityImport
        local entries = type(imported) == "table" and imported.entries
        -- Older local awards could freeze the imported floor as well.
        if record.source == "rarity" or record.source == "unverified"
            or (type(entries) == "table" and (entries[id] or entries[key])) then return end
    end
    return record
end

local function probability(rate, attempts)
    if not number(rate) or rate < 1 then return nil end
    local perAttempt = 1 / rate
    return perAttempt, attempts == 0 and 0 or math.min(1, 1 - (1 - perAttempt) ^ attempts)
end

function atlas.timeRiftAttemptProgress(mount)
    if not timeRiftSource(mount.id) then return end
    return { finals = atlas.rawStageAttempts("rift:" .. mount.id), boxes = atlas.rawStageAttempts("mount:" .. mount.id) }
end

function atlas.localIslandAttempts(mount, baseline, snapshot)
    if not (atlas.islandSalvageMounts and atlas.islandSalvageMounts[mount.id]) then return end
    local key = atlas.attemptStages[mount.id].reward.key
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    local raw, delta, counts = 0, 0, snapshot and {} or nil
    for guid, character in pairs(type(characters) == "table" and characters or {}) do
        if type(character) == "table" and not atlas.isCharacterSuppressed(guid) then
            local runs = character.islandExpeditionCompletions
            local bags = type(character.stageAttempts) == "table" and character.stageAttempts[key]
            local count = (number(runs) and math.floor(runs) or 0) + (number(bags) and math.floor(bags) or 0)
            raw = raw + count
            if baseline then
                local previous = baseline[guid]
                delta = delta + math.max(0, count - (number(previous) and previous or 0))
            end
            if counts and count > 0 then counts[guid] = count end
        end
    end
    return raw, delta, counts
end

function atlas.islandExpeditionProgress(mount)
    if not (atlas.islandSalvageMounts and atlas.islandSalvageMounts[mount.id]) then return end
    local attempts = atlas.withImportedIslandAttempts and atlas.withImportedIslandAttempts(mount) or atlas.localIslandAttempts(mount)
    local stage = atlas.attemptStages[mount.id]
    local perAttempt, cumulative = probability(stage.reward.expeditionRate, attempts)
    return attempts, cumulative, perAttempt
end

local function stageName(definition, fallback)
    local name = C_Item and safe(C_Item.GetItemInfo, definition.item)
    if definition.item and atlas.itemDisplayName then
        return atlas.itemDisplayName(definition, name) or atlas.itemReferenceName(definition.item)
    end
    if type(name) == "string" and name ~= "" then return name end
    return (atlas.dataName and atlas.dataName(definition) or definition.name) or fallback
end

local function supported(definition)
    if definition.unverifiedEligibility then return false end
    local method = definition.method
    if definition.statisticId and #definition.statisticId > 0 then return true end
    if method == "LOOT_TOAST" then return definition.toastItems and next(definition.toastItems) end
    if method == "SPECIAL" then
        return definition.spells or definition.nodes or definition.quests
            or definition.event == "MAP_VISIT" or definition.event == "GOSSIP" or definition.event == "MOUSEOVER"
    end
    if method == "USE" then return definition.items and next(definition.items) end
    if method == "ARCH" then return definition.raceId end
    if method == "ENCOUNTER" then return definition.encounters and next(definition.encounters) end
    return method == "FISHING" or method == "ZONE" or (method == "NPC" and definition.npcs and next(definition.npcs))
end

function atlas.stageAttemptDefinition(key)
    local entry = stages[key]
    if entry and supported(entry.definition) then return entry.definition end
end

local function progress(definition, fallback, savedStatistics)
    if type(definition) ~= "table" or type(definition.key) ~= "string" then return end
    local collection = definition.method == "COLLECTION"
    local count = supported(definition) and total(definition.key, savedStatistics) or nil
    local perAttempt, cumulative = probability(not collection and definition.rate or nil, count or 0)
    if count == nil then cumulative = nil end
    local collected = (definition.inventoryGoal or (number(definition.required) and definition.required > 1)) and C_Item
        and safe(C_Item.GetItemCount, definition.item, true, false, true, true) or nil
    return { item = definition.item, name = stageName(definition, fallback), englishName = definition.englishName, required = definition.required,
        collected = number(collected) and collected or nil, collection = collection,
        attempts = count, perAttempt = perAttempt, cumulative = cumulative, method = definition.method, event = definition.event,
        rateEstimated = definition.rateEstimated == true,
        contentsPerOpening = probability(definition.contentsRate, 0) }
end

local function usesExistingCounter(mount, definition)
    if atlas.usesKillAPI(mount) then return true end
    return (definition.method == "NPC" or definition.method == "BOSS" or definition.method == "ENCOUNTER")
        and not mount.journalOnly and (mount.npcs ~= nil or mount.encounter ~= nil)
end

local function prerequisiteProgress(mount, definition, reward, fallback, savedAttempts)
    local result = progress(definition, fallback, savedAttempts ~= nil)
    if not result then return end
    local count
    if usesExistingCounter(mount, reward) then count = savedAttempts or atlas.kills(mount)
    elseif supported(reward) then count = total(reward.key, savedAttempts ~= nil) end
    result.attempts = number(count) and math.floor(count) or nil
    result.perAttempt, result.cumulative = probability(definition.rate, result.attempts or 0)
    if result.attempts == nil then result.cumulative = nil end
    local reagent = atlas.guaranteedRewards and atlas.guaranteedRewards[mount.id]
    reagent = reagent and reagent.reagent
    if reagent and reagent.item == result.item and reagent.completionQuest then
        -- Some starters are consumed on pickup. The persistent character quest
        -- flag confirms receipt; neither bags nor the daily kill flag do.
        result.acquired = C_QuestLog and safe(C_QuestLog.IsQuestFlaggedCompleted, reagent.completionQuest) == true or false
    end
    return result
end

function atlas.itemAttemptProgress(mount, savedAttempts)
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    if not definitions then return end
    if definitions.item then
        if definitions.item.attemptsFromReward and definitions.reward then
            return prerequisiteProgress(mount, definitions.item, definitions.reward, nil, savedAttempts)
        end
        return progress(definitions.item, nil, savedAttempts ~= nil)
    end

    -- Some upstream mount entries track a quest starter rather than the final
    -- mount item. Reuse that exact item's counter; a second stage would lose its
    -- existing history and count the same eligible loot twice.
    local guaranteed = atlas.guaranteedRewards and atlas.guaranteedRewards[mount.id]
    local reagent = guaranteed and guaranteed.reagent
    local definition = definitions.reward
    if not reagent or not definition or definition.item ~= reagent.item then return end
    local loot = atlas.lootItems and atlas.lootItems[mount.id]
    local result = prerequisiteProgress(mount, definition, definition,
        loot and loot.item == definition.item and loot.name or nil, savedAttempts)
    if not result then return end
    result.required = reagent.required
    return result
end

function atlas.isMountAttemptEligible(mount, npc)
    local definition = atlas.attemptStages and atlas.attemptStages[mount.id]
    definition = definition and definition.reward
    if not definition then return true end
    if definition.historical or definition.unverifiedEligibility then return false end
    if definition.method ~= "NPC" and definition.method ~= "BOSS" and definition.method ~= "ENCOUNTER" then return false end
    for _, variant in ipairs(definition.variants or { definition }) do
        if (not npc or not variant.npcs or contains(variant.npcs, npc)) and eligible(variant) then return true end
    end
    return false
end

function atlas.shouldCountCreatureLoot()
    if itemLootOpen or next(interactions) or safe(IsFishingLoot) == true then return false end
    return not (cast and cast.expires > now() and cast.kind ~= "Fishing")
end

local directRewardLabels = {
    ["Достижение"] = true, ["Achievement"] = true, ["Торговец"] = true, ["Vendor"] = true,
    ["Задание"] = true, ["Квест"] = true, ["Quest"] = true, ["Локальное задание"] = true,
    ["World Quest"] = true, ["Задание гарнизона"] = true, ["Класс"] = true, ["Class"] = true,
    ["Профессия"] = true, ["Profession"] = true, ["PvP"] = true, ["Торговая лавка"] = true,
    ["Trading Post"] = true, ["Внутриигровой магазин"] = true, ["In-Game Shop"] = true,
}

function atlas.rewardChanceEligible(mount, vendorRoute)
    if vendorRoute or mount.unavailable or mount.availability then return false end
    if timeRiftSource(mount.id) then return true end
    local definition = atlas.attemptStages and atlas.attemptStages[mount.id]
    definition = definition and definition.reward
    if definition and definition.historical then return false end
    -- A current, reviewed alternative can outlive an old journal achievement.
    -- Match the actual reward/method so later database changes cannot inherit it.
    local route = atlas.verifiedRewardDropRoute and atlas.verifiedRewardDropRoute(mount)
    if route then return true end
    local randomProfession = definition and (definition.method == "FISHING" or definition.method == "ARCH")
    local source = mount.journalSourceRaw or mount.journalSource
    if not readable(source) or type(source) ~= "string" then return true end
    source = source:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", "\n")
    local direct = false
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local label = line:match("^%s*([^:]+):")
        label = label and label:match("^%s*(.-)%s*$")
        if label == "Источник" or label == "Добыча" or label == "Drop" or label == "Source"
            or label == "Сокровище" or label == "Treasure" then return true end
        local bare = line:match("^%s*(.-)%s*$")
        local profession = label == "Профессия" or label == "Profession" or bare == "Профессия" or bare == "Profession"
        if (directRewardLabels[label] or directRewardLabels[bare] or bare == "Паладин" or bare == "Paladin")
            and not (profession and randomProfession) then direct = true end
    end
    return not direct
end

function atlas.rewardAttemptProgress(mount, stageKey)
    local stagesForMount = atlas.attemptStages and atlas.attemptStages[mount.id]
    if stageKey then
        local alternate = stagesForMount and stagesForMount.alternateReward
        if alternate and alternate.key == stageKey and supported(alternate) then
            return progress(alternate, mount.name)
        end
        return
    end
    local definition = stagesForMount and stagesForMount.reward
    if not definition or not atlas.rewardChanceEligible(mount) then return end
    local rift = atlas.timeRiftAttemptProgress(mount)
    if rift then
        local attempts = rift.finals + rift.boxes
        local referencePerAttempt, referenceCumulative = probability(definition.riftProgressRate, attempts)
        return { item = definition.item, method = definition.method, attempts = attempts,
            finals = rift.finals, boxes = rift.boxes, referencePerAttempt = referencePerAttempt,
            referenceCumulative = referenceCumulative }
    end
    local container = atlas.mountRewardContainerRewards and atlas.mountRewardContainerRewards[mount.id]
    if container then
        local item = stagesForMount.item
        if not item or not item.rate or not supported(item) then return end
        local attempts = total(item.key)
        local perAttempt, cumulative = probability(item.rate * container.contentsRate, attempts or 0)
        return { item = definition.item, method = item.method, attempts = attempts, perAttempt = perAttempt,
            cumulative = attempts and cumulative or nil, rateEstimated = true }
    end
    if usesExistingCounter(mount, definition) or not supported(definition) then return end
    if definition.method == "COLLECTION" then return end
    return progress(definition, mount.name)
end

function atlas.captureMountAcquisition(mount)
    local key = "mount:" .. mount.id
    local saved = atlas.acquisitionAttempts(key)
    if saved or islandMount(mount.id) or timeRiftSource(mount.id) then return saved end
    local definitions = atlas.attemptStages[mount.id]
    local reward = definitions and definitions.reward
    if reward and (reward.unverifiedEligibility or reward.requiresLootSource) then return end
    local guaranteed = atlas.guaranteedRewards and atlas.guaranteedRewards[mount.id]
    local reagent = guaranteed and guaranteed.reagent
    -- A quest starter or egg has a different roll from learning the mount.
    -- Use its frozen success, never the current number of farmed creatures.
    local itemOnly = reward and reward.method == "SPECIAL" and definitions.item
    local questStarter = reagent and reward and reagent.item == reward.item
    if itemOnly or questStarter then
        local itemStage = itemOnly and definitions.item or reward
        local found = atlas.acquisitionAttempts(itemStage.key)
        if found then
            local saved = atlas.rememberAcquisition(key, found.attempts, itemStage.item)
            if saved then saved.source = found.source end
            return saved
        end
        return
    end
    local rewardProgress = atlas.rewardAttemptProgress(mount)
    local attempts = rewardProgress and rewardProgress.attempts
    if attempts == nil and atlas.rewardChanceEligible(mount)
        and (atlas.usesKillAPI(mount) or (not mount.journalOnly and mount.npcs)) then
        attempts = atlas.kills(mount)
    end
    atlas.rememberAcquisition(key, attempts)
    return atlas.acquisitionAttempts(key)
end

local function rememberReceivedAcquisition(key, attempts, pending)
    local _, id = acquisitionReward(key)
    local islandProgress
    if islandMount(id) then
        if not pending.confirmedLoot then return end
        local cumulative, perAttempt
        attempts, cumulative, perAttempt = atlas.islandExpeditionProgress({ id = id })
        islandProgress = { cumulative = cumulative, perAttempt = perAttempt }
    end
    atlas.rememberAcquisition(key, attempts, pending.item, pending.time, pending.confirmedLoot, islandProgress)
end

local function settleNPCItemReceipt(key, loot)
    if loot.confirmedSource then
        for otherKey, other in pairs(npcItemLoot.items) do
            if otherKey ~= key and other.confirmedSource == loot.confirmedSource then return end
        end
        local receipts = npcItemLoot.routeReceipts
        loot.receipt = receipts and receipts[loot.confirmedSource]
    end
    if loot.receipt and loot.attempts and not loot.ambiguous then
        local reward, id = acquisitionReward(key)
        if reward and reward.requiresLootSource then
            local receipt = loot.receipt
            atlas.rememberAcquisition("mount:" .. id, loot.attempts, receipt.item, receipt.time, true, nil, nil, nil, key)
            return
        end
        rememberReceivedAcquisition(key, loot.attempts, loot.receipt)
    end
end

function atlas.settleIslandExpeditionAcquisitions(map)
    for key, pending in pairs(pendingAcquisitions) do
        if pending.islandMap == map then
            if pending.expires > now() then rememberReceivedAcquisition(key, nil, pending) end
            pendingAcquisitions[key] = nil
        end
    end
end

local function finalizePendingAcquisitions(inventoryUpdated)
    for key, pending in pairs(pendingAcquisitions) do
        if pending.expires <= now() then
            pendingAcquisitions[key] = nil
        elseif not pending.waitForLootCount then
            local count = pending.minimumAttempts and total(key)
            local counted = not pending.minimumAttempts or (number(count) and count >= pending.minimumAttempts)
            if counted then
                local held = pending.required and C_Item and safe(C_Item.GetItemCount, pending.item, true, false, true, true)
                if not pending.required or (number(held) and held >= pending.required) then
                    rememberReceivedAcquisition(key, pending.minimumAttempts and count or pending.attempts, pending)
                    pendingAcquisitions[key] = nil
                elseif inventoryUpdated and number(held) then
                    -- A later unrelated bag change cannot turn this shard into success.
                    pendingAcquisitions[key] = nil
                end
            end
        end
    end
end

local function itemCount(id)
    local count = C_Item and safe(C_Item.GetItemCount, id, false, false, false, false)
    return number(count) and math.floor(count) or nil
end

local function pendingUseReady(use, time)
    return use.expires > time and not use.consumed and not use.failed and (use.slot or use.named or use.succeeded)
end

local function hasPendingUse(item, time)
    local uses = pendingUses[item]
    if not uses then return false end
    for _, use in ipairs(uses) do
        if pendingUseReady(use, time) then return true end
    end
    return false
end

local function waitingForContainer(key, awaitBagUpdate)
    -- Loot chat may precede the bag update that counts the opened container.
    -- Freeze the successful total only after that pending use is recorded.
    local entry = stages[key]
    if not entry then return false end
    local time = now()
    local checkInventory = not itemLootSettled and itemLootUntil > time
    for _, variant in ipairs(entry.variants) do
        if (variant.method or entry.definition.method) == "USE" then
            for _, item in ipairs(variant.items or {}) do
                if hasPendingUse(item, time) then return true end
                if checkInventory and number(bags[item]) and bags[item] > 0 then
                    if awaitBagUpdate then return true end
                    local held = itemCount(item)
                    if held and held < bags[item] then return true end
                end
            end
        end
    end
    return false
end

function atlas.mountLootAttemptsPending(id)
    if timeRiftSource(id) and timeRifts.receiptPending(id) then return true end
    local reward = atlas.attemptStages[id] and atlas.attemptStages[id].reward
    local receipts = npcItemLoot.routeReceipts
    local receipt = reward and reward.requiresLootSource and receipts and receipts[reward.item]
    if lootChatOpen and receipt and receipt.expires > now() then return true end
    local pending = pendingAcquisitions["mount:" .. id]
    return pending ~= nil and pending.expires > now()
end

local function ownLootPattern(template)
    if type(template) ~= "string" then return end
    local parts, position = { "^" }, 1
    for first, kind, following in template:gmatch("()%%[%d$]*([sd])()") do
        parts[#parts + 1] = (template:sub(position, first - 1):gsub("(%p)", "%%%1"))
        parts[#parts + 1] = kind == "s" and "\001" or "(%d+)"
        position = following
    end
    parts[#parts + 1] = (template:sub(position):gsub("(%p)", "%%%1")) .. "$"
    return table.concat(parts)
end

local personalReceipts, lootPrefixes = {}, {}
local matchWithoutPrefix = false
for _, key in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE",
    "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF",
    "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
    local template = _G[key]
    if type(template) == "string" then
        local prefix = template:match("^(.-)%%")
        if not prefix or prefix == "" then matchWithoutPrefix = true
        else lootPrefixes[prefix] = #prefix end
        local pushed = key:find("PUSHED", 1, true) ~= nil
        personalReceipts[#personalReceipts + 1] = { pattern = ownLootPattern(template), pushed = pushed,
            drop = not pushed and not key:find("CREATED", 1, true), multiple = key:find("MULTIPLE", 1, true) ~= nil }
    end
end

local function ownLootReceipt(message)
    -- Regular self-loot confirms receipt. Crafted and pushed item messages
    -- also cover other inventory changes and do not seed collection history.
    local normalized, links = message:gsub("|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r", "\001", 1)
    if links == 0 then normalized, links = message:gsub("|cn[%w_]+:|Hitem:.-|h.-|h|r", "\001", 1) end
    if links == 0 then normalized = message:gsub("|Hitem:.-|h.-|h", "\001", 1) end
    for _, receipt in ipairs(personalReceipts) do
        local match = normalized:match(receipt.pattern)
        if match then
            if not receipt.drop then return nil, true, receipt.pushed end
            if not receipt.multiple then return 1, true end
            local quantity = tonumber(match)
            if quantity and quantity >= 1 then return quantity, true end
        end
    end
end

local function firstLootReceipt(lineID)
    if not number(lineID) or lineID <= 0 then return false end
    local time, key = now(), "collection:" .. lineID
    if (recentEvents[key] or 0) > time then return end
    if time - lastCollectionPrune >= 60 then
        for id, expires in pairs(recentEvents) do if expires <= time then recentEvents[id] = nil end end
        lastCollectionPrune = time
    end
    recentEvents[key] = time + 60
    return true
end

local function recordCollectionReceipt(item, quantity)
    local character = record()
    if not character then return end
    if type(character.collectionItems) ~= "table" then character.collectionItems = {} end
    local previous = character.collectionItems[item]
    character.collectionItems[item] = (number(previous) and math.floor(previous) or 0) + quantity
    refreshAttempts(false)
end

local function uncollected(id)
    if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return true end
    local owned = safe(function() return select(11, C_MountJournal.GetMountInfoByID(id)) end)
    if type(owned) == "boolean" then return not owned end
end

local function onItemReceived(message, lineID)
    if not readable(message) or type(message) ~= "string" then return end
    local selfPrefix = false
    for prefix, length in pairs(lootPrefixes) do
        if message:sub(1, length) == prefix then selfPrefix = true; break end
    end
    if not selfPrefix and not matchWithoutPrefix then return end
    local item = tonumber(message:match("|Hitem:(%d+)"))
    if not item then return end
    local owners = acquisitionItems[item]
    local prerequisites = prerequisiteOwners[item]
    local collection = collectionReceipts[item]
    -- Only a complete personal receipt can award an item. Links in group-roll
    -- messages or the loot window do not identify the eventual recipient.
    local quantity, selfLoot, pushed = ownLootReceipt(message)
    if not selfLoot then return end
    local recipients
    local firstReceipt = (collection or prerequisites or owners) and firstLootReceipt(lineID)
    if firstReceipt then
        if quantity and collection then recordCollectionReceipt(item, quantity) end
        for id, announceLoot in pairs(prerequisites or {}) do
            if announceLoot and uncollected(id) then
                recipients = recipients or {}
                recipients[#recipients + 1] = id
            end
        end
    end
    local generation = sessionGeneration
    if not owners then
        if atlas.notifyMountItemLoot then atlas.notifyMountItemLoot(item) end
        if not recipients then return end
    end
    local npcReceipts
    for key, owner in pairs(owners or {}) do
        local _, id = acquisitionReward(key)
        local island = islandMount(id)
        local waiting = waitingForContainer(key, island)
        if timeRiftSource(id) then
            if quantity or pushed then timeRifts.receive(item, quantity ~= nil) end
        elseif owner.requiresLootSource then
            if firstReceipt and quantity and not itemLootOpen and (lootChatOpen or npcItemLoot.expires and npcItemLoot.expires > now()) then
                local receipts = npcItemLoot.routeReceipts or {}
                npcItemLoot.routeReceipts = receipts
                receipts[item] = { item = item, time = serverTime(), expires = now() + npcLootReceiptWindow }
                local loot = npcItemLoot.items[key]
                if loot and not lootChatOpen then settleNPCItemReceipt(key, loot) end
            end
        elseif owner.npcUnique then
            npcReceipts = npcReceipts or {}
            local loot = npcItemLoot.items[key]
            if firstReceipt and quantity and loot and not loot.receipt and not loot.ambiguous
                and (lootChatOpen or npcItemLoot.expires > now()) then
                loot.receipt = { item = item, time = serverTime(), confirmedLoot = true }
                npcReceipts[key] = loot
                if not lootChatOpen then settleNPCItemReceipt(key, loot) end
            end
        elseif not owner.required and not waiting and not pendingAcquisitions[key] then
            -- Inventory and collection events can run before the delayed count.
            pendingAcquisitions[key] = { item = item, waitForLootCount = true,
                islandMap = quantity ~= nil and island and itemLootUntil <= now()
                    and atlas.pendingIslandExpeditionMap and atlas.pendingIslandExpeditionMap() or nil,
                confirmedLoot = quantity ~= nil, expires = now() + 20 }
        elseif (owner.required or waiting) and not atlas.acquisitionAttempts(key) then
            local count = owner.mount and atlas.kills(owner.mount) or total(key)
            if number(count) and (count > 0 or waiting) then
                pendingAcquisitions[key] = { item = item, required = owner.required, attempts = count,
                    minimumAttempts = waiting and count + 1 or nil,
                    confirmedLoot = quantity ~= nil, time = serverTime(), expires = now() + 20 }
            end
        end
    end
    -- Let loot/statistic events for the successful attempt finish first.
    C_Timer.After(.1, function()
        if generation ~= sessionGeneration then return end
        for key, owner in pairs(acquisitionItems[item] or {}) do
            local pending = pendingAcquisitions[key]
            if pending and pending.waitForLootCount and pending.item == item then
                local count = owner.mount and atlas.kills(owner.mount) or total(key)
                local _, id = acquisitionReward(key)
                if islandMount(id) and waitingForContainer(key, true) then
                    pending.waitForLootCount, pending.islandMap = nil, nil
                    pending.minimumAttempts = count + 1
                elseif not pending.islandMap or itemLootUntil > now() then
                    rememberReceivedAcquisition(key, count, pending)
                    pendingAcquisitions[key] = nil
                end
            end
        end
        finalizePendingAcquisitions(false)
        if recipients then
            local function announce()
                if generation == sessionGeneration then atlas.notifyPrerequisiteLoot(item, message, quantity ~= nil, recipients, npcReceipts) end
            end
            if npcReceipts and lootChatOpen then queueLootChat(announce) else announce() end
        end
    end)
    if owners and atlas.notifyMountItemLoot then atlas.notifyMountItemLoot(item, true) end
end

function atlas.defaultChatMessageFormat()
    return atlas.L("PawAtlas: {название} — попытка {попытки} · вероятность за попытки: {вероятность}")
end

function atlas.defaultMountCollectionMessageFormat()
    return atlas.L("PawAtlas: {название} получен! Попытка №{попытки}.")
end

local function attemptItemIcon(item)
    if not number(item) or item < 1 or item ~= math.floor(item) or not C_Item then return "" end
    local icon = safe(C_Item.GetItemIconByID, item)
    if not icon and type(C_Item.GetItemInfoInstant) == "function" then
        icon = safe(function() return select(5, C_Item.GetItemInfoInstant(item)) end)
    end
    if (number(icon) and icon > 0 and icon == math.floor(icon))
        or (readable(icon) and type(icon) == "string" and icon ~= "" and not icon:find("[|:\r\n]")) then
        return "|T" .. tostring(icon) .. ":16:16:0:0|t "
    end
    return ""
end

local function chatProbability(cumulative, perAttempt)
    local probabilityText = "—"
    if number(cumulative) then
        if cumulative > 0 and cumulative < .00005 then probabilityText = atlas.L("<0,01%")
        elseif cumulative >= .99995 and (cumulative < 1 or (number(perAttempt) and perAttempt < 1)) then probabilityText = "<100%"
        else
            probabilityText = string.format("%.2f", cumulative * 100)
            if atlas.getLocale() == "ruRU" then probabilityText = probabilityText:gsub("%.", ",") end
            probabilityText = probabilityText .. "%"
        end
    end
    return probabilityText
end

local function fillChatTokens(template, itemName, count, probabilityText)
    local values = { ["название"] = itemName, ["попытки"] = count, ["вероятность"] = probabilityText,
        mount = itemName, attempts = count, probability = probabilityText }
    return (template:gsub("{([^{}]+)}", function(token) return values[token] or "{" .. token .. "}" end):gsub("[\r\n]", " "))
end

function atlas.formatAttemptMessage(name, attempts, cumulative, perAttempt, item, templateOverride)
    local settings = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    local template = templateOverride ~= nil and templateOverride or (settings and settings.chatMessageFormat)
    local default = atlas.defaultChatMessageFormat()
    if type(template) ~= "string" or template == "" then template = default end
    if not number(cumulative) and template == default then template = atlas.L("PawAtlas: {название} — попытка {попытки}") end
    local itemName, count = attemptItemIcon(item) .. tostring(name or "—"), tostring(attempts or 0)
    return fillChatTokens(template, itemName, count, chatProbability(cumulative, perAttempt))
end

function atlas.formatMountCollectionMessage(name, attempts, cumulative, perAttempt, templateOverride)
    local settings = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    local template = templateOverride ~= nil and templateOverride or (settings and settings.mountCollectionMessageFormat)
    local default = atlas.defaultMountCollectionMessageFormat()
    if type(template) ~= "string" or not template:find("%S") then template = default end
    local known = number(attempts) and attempts >= 1 and attempts == math.floor(attempts)
    if not known and template == default then template = atlas.L("PawAtlas: {название} получен!") end
    return fillChatTokens(template, tostring(name or "—"), known and tostring(attempts) or "—",
        chatProbability(cumulative, perAttempt))
end

local function collectionChatEnabled()
    local settings = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    return not settings or settings.mountCollectionChat ~= false
end

function atlas.notifyMountCollected(id, name)
    if not collectionChatEnabled() then return end
    if not name or not DEFAULT_CHAT_FRAME or not DEFAULT_CHAT_FRAME.AddMessage then return end
    local key = "mount:" .. id
    local recorded = atlas.acquisitionAttempts(key)
    if not recorded or recorded.confirmedLoot ~= true then return end
    -- Only use a frozen receipt of the actual teaching item. A toast can also
    -- freeze an egg or a lifetime counter, which cannot identify this award.
    local item = recorded.item
    if prerequisiteOwners[item] and prerequisiteOwners[item][id] ~= nil then return end
    local native = number(item) and C_MountJournal and safe(C_MountJournal.GetMountFromItem, item)
    local confirmed = native == id
    if not confirmed and (not number(native) or native == 0) and number(item) then
        for _, reward in ipairs((atlas.mountRewardItems or {})[id] or {}) do
            if reward.item == item then confirmed = true; break end
        end
    end
    if not confirmed then return end
    local definition = acquisitionReward(recorded.routeKey or key)
    local attempts, perAttempt, cumulative = recorded.attempts
    if type(recorded.islandProgress) == "table" then
        perAttempt, cumulative = recorded.islandProgress.perAttempt, recorded.islandProgress.cumulative
    elseif timeRiftSource(id) then
        if number(recorded.totalAttempts) then attempts = recorded.totalAttempts end
    elseif definition and definition.item == recorded.item and definition.method ~= "COLLECTION" then
        perAttempt, cumulative = probability(definition.rate, recorded.attempts)
    end
    DEFAULT_CHAT_FRAME:AddMessage(atlas.formatMountCollectionMessage(name, attempts, cumulative, perAttempt))
end

local function attemptChatEnabled()
    local settings = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    return not settings or settings.chatMessages ~= false
end

local function output(name, attempts, cumulative, perAttempt, item)
    if not attemptChatEnabled() then return end
    if not name or not DEFAULT_CHAT_FRAME or not DEFAULT_CHAT_FRAME.AddMessage then return end
    DEFAULT_CHAT_FRAME:AddMessage(atlas.formatAttemptMessage(name, attempts, cumulative, perAttempt, item))
end

function atlas.notifyPrerequisiteLoot(item, message, fromDrop, recipients, npcReceipts)
    if not collectionChatEnabled() or not DEFAULT_CHAT_FRAME or not DEFAULT_CHAT_FRAME.AddMessage then return end
    local teachingMount = C_MountJournal and safe(C_MountJournal.GetMountFromItem, item)
    if number(teachingMount) and teachingMount > 0 then return end
    local count, rate, cumulative, found
    for _, id in ipairs(recipients) do
        local mount = mountsByID[id] or { id = id, journalOnly = true }
        local progress = fromDrop and atlas.itemAttemptProgress(mount)
        local attempts, perAttempt, cumulativeChance
        if progress and progress.item == item and not progress.collection and (progress.attempts or 0) > 0 then
            attempts, perAttempt, cumulativeChance = progress.attempts, progress.perAttempt, progress.cumulative
            local definition = atlas.attemptStages[id] and atlas.attemptStages[id].item
            local owner = definition and acquisitionItems[item] and acquisitionItems[item][definition.key]
            if owner and owner.npcUnique then
                local loot = npcReceipts and npcReceipts[definition.key]
                attempts = loot and not loot.ambiguous and loot.attempts or nil
                perAttempt, cumulativeChance = probability(attempts and definition.rate, attempts or 0)
            end
        end
        -- A shared item can serve several mounts with different farm histories.
        if found and (count ~= attempts or rate ~= perAttempt) then
            count, rate, cumulative = nil, nil, nil
            break
        end
        found, count, rate, cumulative = true, attempts, perAttempt, cumulativeChance
    end
    if not found then return end
    local link = message:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h.-|h|r)")
        or message:match("(|cn[%w_]+:|Hitem:[^|]+|h.-|h|r)") or message:match("(|Hitem:[^|]+|h.-|h)")
    if link then
        DEFAULT_CHAT_FRAME:AddMessage(atlas.formatMountCollectionMessage(attemptItemIcon(item) .. link, count, cumulative, rate))
    end
end

local attemptMessageDelays = { 1, 2, 5, 12 }
local function deliverLootChat(callbacks)
    for _, callback in ipairs(callbacks) do callback() end
end

local function settleLootChat()
    lootChatOpen = false
    if #lootChat == 0 then return end
    local callbacks = lootChat
    lootChat = {}
    C_Timer.After(.2, function()
        deliverLootChat(callbacks)
    end)
end

queueLootChat = function(callback)
    local batch = lootChat
    batch[#batch + 1] = callback
    if #batch == 1 and not lootChatOpen then
        -- Autoloot can provide only LOOT_READY, or a bag change without a window.
        C_Timer.After(.2, function()
            if lootChat ~= batch or lootChatOpen then return end
            lootChat = {}
            deliverLootChat(batch)
        end)
    end
end

local function retryAttemptMessage(deliver, finish, afterLoot)
    local generation = sessionGeneration
    local function retry(attempt)
        if generation ~= sessionGeneration then return end
        local delay = attemptMessageDelays[attempt]
        if not attemptChatEnabled() or deliver() or not delay then
            if finish then finish() end
            return
        end
        C_Timer.After(delay, function() retry(attempt + 1) end)
    end
    if afterLoot then
        queueLootChat(function() retry(1) end)
    else
        retry(1)
    end
end

local function notifyStage(entry, count, cumulative, perAttempt)
    local unknownOwnership
    for id in pairs(entry.mountIDs) do
        local needed = uncollected(id)
        if needed then
            local name = stageName(entry.definition, entry.name)
            if not name then return false end
            if count then output(name, count, cumulative, perAttempt, entry.definition.item) end
            return true
        elseif needed == nil then
            unknownOwnership = true
        end
    end
    return not unknownOwnership
end

local function queueStageAttemptMessage(entry, count, rate, fromContainer, fromLoot, riftContext, riftAttempt)
    if not attemptChatEnabled() then return end
    local definition = entry.definition
    local perAttempt, cumulative = probability(rate, count)
    -- Some reagents have several sources, so a zone corpse alone does not
    -- establish a drop chance for the collection goal.
    if number(definition.required) and definition.required > 1 and not perAttempt then return end
    local reward, id = acquisitionReward(definition.key)
    local containerReward = fromContainer and reward and reward.item
    if islandMount(id) then
        count, cumulative, perAttempt = atlas.islandExpeditionProgress({ id = id })
    end
    -- Preserve the total and order of this stage's messages while data loads.
    local key = definition.key
    local previous, message = pendingStageMessages[key], {}
    pendingStageMessages[key] = message
    retryAttemptMessage(function()
        if previous and not previous.finished then return false end
        if riftAttempt and collectionChatEnabled() then
            if riftAttempt.awarded then return true end
            if riftContext.expires >= now() or (riftContext == timeRifts.box and itemLootOpen) then return false end
        elseif containerReward and collectionChatEnabled() then
            local award = atlas.acquisitionAttempts(key)
            if award and award.confirmedLoot and award.item == containerReward and award.attempts == count then return true end
        end
        return notifyStage(entry, count, cumulative, perAttempt)
    end, function()
        message.finished = true
        if pendingStageMessages[key] == message then pendingStageMessages[key] = nil end
    end, containerReward or fromLoot)
end

local function mountAttemptMessage(mount, savedAttempts)
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    if definitions and definitions.reward and not usesExistingCounter(mount, definitions.reward) then return end
    notificationGuard = true
    local itemProgress = atlas.itemAttemptProgress(mount, savedAttempts)
    local deliver
    if itemProgress and definitions and definitions.reward and definitions.reward.item == itemProgress.item then
        local entry = { definition = definitions.reward, name = itemProgress.name, mountIDs = { [mount.id] = true } }
        deliver = function()
            return notifyStage(entry, itemProgress.attempts or 0, itemProgress.cumulative, itemProgress.perAttempt)
        end
    else
        local perAttempt, cumulative, attempts = atlas.dropProbability(mount, savedAttempts)
        local item = definitions and definitions.reward and definitions.reward.item
        if not item and atlas.rewardItem then
            local reward = atlas.rewardItem(mount)
            item = reward and reward.item
        end
        local count = attempts or savedAttempts or atlas.kills(mount) or 0
        deliver = function()
            output(mount.name, count, cumulative, perAttempt, item)
            return true
        end
    end
    notificationGuard = false
    return deliver
end

function atlas.notifyMountAttempt(mount, fromCreatureLoot)
    if notificationGuard or not attemptChatEnabled() or uncollected(mount.id) == false then return end
    -- The attempt is already saved. Keep its total while journal data loads.
    local deliver = mountAttemptMessage(mount)
    if not deliver then return end
    retryAttemptMessage(function()
        local needed = uncollected(mount.id)
        return needed == false or (needed and deliver())
    end, nil, fromCreatureLoot)
end

function atlas.notifyKillStatistic(id)
    if notificationGuard or not attemptChatEnabled() then return end
    -- Tracking calls once per confirmed increase after saving the statistic and
    -- the imported delta. Keep that total without sampling the API again.
    local count = total(id, true)
    if not number(count) then return end
    local stage = stages[id]
    if stage then
        queueStageAttemptMessage(stage, count, stage.definition.rate)
        return
    end
    local message
    retryAttemptMessage(function()
        local needed = uncollected(id)
        if needed == false then return true end
        if not needed then return false end
        if not message then
            local mount = atlas.mountByID and atlas.mountByID(id) or mountsByID[id]
            if not mount and atlas.resolveJournalMount then mount = atlas.resolveJournalMount(id) end
            if not mount then return false end
            message = mountAttemptMessage(mount, count)
        end
        return not message or message()
    end)
end

function atlas.preserveStageDailyLocks(character)
    local legacy = type(character) == "table" and character.stageDaily
    if type(legacy) ~= "table" then return end
    local locks = MountAtlasAccountDB.stageDaily
    local time = serverTime()
    for key, expires in pairs(legacy) do
        if number(expires) and expires > time then
            if type(locks) ~= "table" then locks = {}; MountAtlasAccountDB.stageDaily = locks end
            local previous = locks[key]
            if not number(previous) or previous < expires then locks[key] = expires end
        end
    end
end

local function claimFirstDaily(key)
    local time = serverTime()
    if time <= 0 then return false end
    local locks = MountAtlasAccountDB.stageDaily
    local expires = type(locks) == "table" and locks[key]
    if number(expires) and expires > time then return false end
    local seconds = C_DateAndTime and safe(C_DateAndTime.GetSecondsUntilDailyReset)
    if not number(seconds) or seconds <= 0 then return false end
    if type(locks) ~= "table" then locks = {}; MountAtlasAccountDB.stageDaily = locks end
    locks[key] = time + seconds
    return true
end

local function cooldownAvailable(character, definition)
    if not definition.cooldownSeconds then return true end
    if type(character.stageCooldowns) ~= "table" then character.stageCooldowns = {} end
    local expires = character.stageCooldowns[definition.key]
    if not number(expires) or expires <= serverTime() then return true end
    -- Keep the last event protected while its buff arrives. Unreadable combat
    -- auras cannot be used to infer that a new offering became available.
    if definition.cooldownAura and expires - serverTime() < definition.cooldownSeconds - 15
        and safe(InCombatLockdown) == false and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, definition.cooldownAura)
        if ok and readable(aura) and aura == nil then return true end
    end
    return false
end

local function increment(entry, variant, amount, credited, character, fromLoot, loot)
    character = character or record()
    if not character or not eligible(variant, loot and loot.heldBeforeLoot)
        or not cooldownAvailable(character, entry.definition) then return false end
    local definition = entry.definition
    if variant.firstDaily or definition.firstDaily then
        if not claimFirstDaily(definition.key) then return false end
        amount = 1
    end
    amount = amount or 1
    local _, id = acquisitionReward(definition.key)
    local rift = timeRiftSource(id)
    local method = variant.method or definition.method
    local split = method == "USE" and not rift and amount > 1 and attemptChatEnabled()
    local step = split and 1 or amount
    local guid = atlas.recordImportedStatistic and not rift and safe(UnitGUID, "player")
    local previous = character.stageAttempts[definition.key]
    previous = number(previous) and math.floor(previous) or 0
    for offset = step, amount, step do
        character.stageAttempts[definition.key] = previous + offset
        if atlas.recordImportedStatistic and not rift then atlas.recordImportedStatistic(definition.key, guid, step) end
        -- Freeze each total before the next opening changes account or import progress.
        if split then
            queueStageAttemptMessage(entry, total(definition.key), variant.rate or definition.rate, true, fromLoot)
        end
    end
    if definition.cooldownSeconds then character.stageCooldowns[definition.key] = serverTime() + definition.cooldownSeconds end
    if credited then
        for id in pairs(entry.mountIDs) do credited[id] = true end
    elseif atlas.recordBrokerAttempt then
        atlas.recordBrokerAttempt(entry.mountIDs)
    end
    local count = rift and atlas.rawStageAttempts(definition.key) or total(definition.key)
    if loot then
        loot.attempts = count
        if not lootChatOpen then settleNPCItemReceipt(definition.key, loot) end
    end
    if rift and method == "USE" then
        timeRifts.countBox(id, count, amount)
    elseif not split then
        queueStageAttemptMessage(entry, count, variant.rate or definition.rate, method == "USE", fromLoot)
    end
    return true
end

local function opportunityLocks(entry, npc)
    local locks, open = {}, false
    if not atlas.planStageOpportunityKey then return locks, true end
    local attempts = type(MountAtlasDB) == "table" and MountAtlasDB.lastAttempts
    local time = serverTime()
    for _, mount in pairs(entry.mountIDs) do
        local key, frequency = atlas.planStageOpportunityKey(mount, entry.definition, npc)
        if key then
            local getter = C_DateAndTime and C_DateAndTime[frequency == "daily"
                and "GetSecondsUntilDailyReset" or "GetSecondsUntilWeeklyReset"]
            local seconds = safe(getter)
            if number(seconds) and seconds > 0 then
                locks[key] = time + seconds
                local previous = type(attempts) == "table" and attempts[key]
                if npc and atlas.lootOpportunityExpires then previous = atlas.lootOpportunityExpires(mount, npc, frequency) end
                if not number(previous) or previous <= time then open = true end
            end
        end
    end
    return locks, not next(locks) or open
end

local function saveOpportunityLocks(locks)
    if not next(locks) then return end
    if type(MountAtlasDB) ~= "table" then MountAtlasDB = {} end
    if type(MountAtlasDB.lastAttempts) ~= "table" then MountAtlasDB.lastAttempts = {} end
    for key, expires in pairs(locks) do MountAtlasDB.lastAttempts[key] = expires end
end

local function apply(method, match, amount, id, character, fromLoot, lootGUID, applied)
    local candidates = stagesByMethod[method]
    if method == "NPC" then candidates = npcStages[id]
    elseif method == "ENCOUNTER" then candidates = encounterStages[id]
    elseif method == "USE" then candidates = useStages[id] end
    if not candidates then return false end
    local npc = method == "NPC" and id or nil
    local changed, pendingLocks, credited = false, {}, {}
    for _, entry in pairs(candidates) do
        local loot = lootGUID and npcItemLoot.items[entry.definition.key]
        if loot and (loot.guid ~= lootGUID or loot.ambiguous) then loot = nil end
        for _, variant in ipairs(entry.variants) do
            if (variant.method or entry.definition.method) == method and match(variant, entry.definition) then
                local locks, available = opportunityLocks(entry, npc)
                local watch = lootQuests[variant.lootQuestID]
                if available and watch and watch.pendingLock then
                    if next(locks) then
                        saveOpportunityLocks(locks)
                        watch.pendingLock = nil
                    end
                    break
                end
                if available and increment(entry, variant, amount, credited, character, fromLoot, loot) then
                    changed = true
                    if applied then applied[entry.definition.key] = true end
                    if watch and atlas.planStageOpportunityKey and not next(locks) then watch.pendingLock = true end
                    for key, expires in pairs(locks) do pendingLocks[key] = expires end
                    break
                end
            end
        end
    end
    -- Commit after every reward/prerequisite sharing this loot event was tested.
    -- This records reset progress without creating a second boss/rare counter.
    saveOpportunityLocks(pendingLocks)
    if changed then
        if atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(credited) end
        refreshAttempts(true)
    end
    return changed
end

local function observeLootQuests(baseline)
    for quest, watch in pairs(lootQuests) do
        if baseline then watch.complete, watch.pendingLock = nil, nil end
        local previous = watch.complete
        local complete = C_QuestLog and safe(C_QuestLog.IsQuestFlaggedCompleted, quest)
        if complete == false then
            if previous == true then watch.pendingLock = nil end
            watch.complete = false
        elseif complete == true and (previous ~= true or watch.pendingLock) then
            watch.complete = true
            -- Use the same character/reset lock as an opening identified by its
            -- object or casting target. A login snapshot only establishes the lock.
            if previous == false and not watch.pendingLock and atlas.planStageOpportunityKey then
                apply("SPECIAL", function(v) return v.lootQuestID == quest end, nil, nil, nil, true)
            else
                local locks, available = opportunityLocks(watch.entry)
                if available then saveOpportunityLocks(locks) end
                -- Retain the observed opening until the daily reset API is ready.
                watch.pendingLock = atlas.planStageOpportunityKey and not next(locks) or nil
            end
        end
    end
end

local function resolveItemSpell(item)
    if not unresolvedItemSpells[item] or not C_Item then return end
    local _, spell = safe(C_Item.GetItemSpell, item)
    if number(spell) then
        itemSpells[spell] = item
        unresolvedItemSpells[item] = nil
    end
end

local function registerPrerequisite(id, item, container)
    if not number(item) or item <= 0 then return end
    local grant = atlas.guaranteedRewards and atlas.guaranteedRewards[id]
    local reagent = grant and grant.reagent
    prerequisiteOwners[item] = prerequisiteOwners[item] or {}
    -- Keep container ownership for reward identification, even on overlapping routes.
    local owners = prerequisiteOwners[item]
    owners[id] = owners[id] ~= false and not container and not (reagent and reagent.item == item and reagent.hideLootMessage)
end

local function indexEntries(index, ids, key, entry)
    for position, value in pairs(ids or {}) do
        local id = tonumber(value == true and position or value)
        if id then
            local candidates = index[id]
            if not candidates then candidates = {}; index[id] = candidates end
            candidates[key] = entry
        end
    end
end

local function buildStages()
    local loadItems = {}
    for id, source in pairs(atlas.timeRiftSources or {}) do
        local reward = atlas.attemptStages[id] and atlas.attemptStages[id].reward
        if number(source.instance) and number(source.criterion) and reward and number(reward.item) then
            local routes = timeRifts.byInstance[source.instance]
            if not routes then routes = {}; timeRifts.byInstance[source.instance] = routes end
            routes[id] = source
            timeRifts.byItem[reward.item] = id
        end
    end
    for _, mount in ipairs(atlas.mounts or {}) do mountsByID[mount.id] = mount end
    for id, grant in pairs(atlas.guaranteedRewards or {}) do
        if grant.reagent then registerPrerequisite(id, grant.reagent.item) end
    end
    for id, container in pairs(atlas.mountRewardContainerRewards or {}) do
        registerPrerequisite(id, container.item, true)
    end
    for id, loot in pairs(atlas.lootItems or {}) do
        if loot.basis == "open" or loot.basis == "cage" or loot.basis == "egg" or loot.basis == "ingredient" then
            registerPrerequisite(id, loot.item, loot.basis == "open" or loot.basis == "cage")
        end
    end
    for id, definitions in pairs(atlas.attemptStages or {}) do
        local mount = mountsByID[id]
        local prerequisite = definitions.item
        if prerequisite and prerequisite.item and not prerequisite.historical then
            for _, item in ipairs(prerequisite.collectedItems or { prerequisite.item }) do
                registerPrerequisite(id, item)
            end
        end
        for _, item in ipairs(collectionItems(definitions.item) or {}) do collectionReceipts[item] = true end
        for _, role in ipairs({ "item", "reward", "alternateReward" }) do
            local definition = definitions[role]
            if definition and definition.unverifiedEligibility then definition = nil end
            if definition and not definition.historical then
                for _, variant in ipairs(definition.variants or { definition }) do
                    if not variant.historical and (variant.method or definition.method) == "USE" then
                        for _, item in ipairs(variant.items or {}) do registerPrerequisite(id, item, true) end
                    end
                end
            end
            local existing = (role == "item" and definition and definition.attemptsFromReward)
                or (role == "reward" and ((definition and definition.historical) or (atlas.killStatistics and atlas.killStatistics[id])
                    or (mount and usesExistingCounter(mount, definition or {}))))
            if definition and definition.item and not definition.historical then
                local counterMount = role == "reward" and mount and usesExistingCounter(mount, definition) and mount or nil
                if counterMount or (not existing and supported(definition)) then
                    local owners = acquisitionItems[definition.item] or {}
                    acquisitionItems[definition.item] = owners
                    owners[definition.key] = { mount = counterMount,
                        npcUnique = role == "item" and definition.method == "NPC" and definition.unique,
                        requiresLootSource = definition.requiresLootSource,
                        required = role == "item" and definition.required and definition.required > 1 and definition.required or nil }
                end
            end
            if definition and definition.key and not existing then
                local entry = stages[definition.key] or { definition = definition,
                    variants = definition.variants or { definition },
                    name = role ~= "item" and mount and mount.name or nil, mountIDs = {} }
                -- Stage-only mounts can already be tracked before the catalog is opened.
                entry.mountIDs[id] = mount or { id = id, journalOnly = true }
                stages[definition.key] = entry
                if definition.item then loadItems[definition.item] = true end
            end
        end
    end
    for key, entry in pairs(stages) do
        local definition = entry.definition
        if definition.lootQuestID then lootQuests[definition.lootQuestID] = { entry = entry } end
        if definition.event == "MAP_VISIT" then mapVisits[key] = entry end
        if definition.event == "GOSSIP" then gossipStages[key] = entry end
        if definition.method == "ARCH" then archaeologyRaces[definition.raceId] = true end
        for _, variant in ipairs(entry.variants) do
            local method = variant.method or entry.definition.method
            if method == "NPC" then
                indexEntries(npcStages, variant.npcs, key, entry)
            elseif method == "ENCOUNTER" then
                indexEntries(encounterStages, variant.encounters, key, entry)
            elseif method == "USE" then
                indexEntries(useStages, variant.items, key, entry)
            elseif method then
                local candidates = stagesByMethod[method] or {}
                stagesByMethod[method] = candidates
                candidates[key] = entry
                if method == "SPECIAL" then
                    for index, value in pairs(variant.spells or {}) do
                        local spell = tonumber(value == true and index or value)
                        if spell then specialSpells[spell] = true end
                    end
                    for _, id in ipairs(variant.objects or {}) do objectNodes[id] = true end
                end
            end
        end
    end
    for item in pairs(useStages) do
        loadItems[item], unresolvedItemSpells[item] = true, true
        resolveItemSpell(item)
    end
    if C_Item and C_Item.RequestLoadItemDataByID then
        for item in pairs(loadItems) do pcall(C_Item.RequestLoadItemDataByID, item) end
    end
    ready = true
end

local function blocked()
    return next(interactions) ~= nil
end

local function currentRiftInstance()
    if not next(timeRifts.byInstance) or not GetInstanceInfo then return end
    local instance = select(8, GetInstanceInfo())
    if number(instance) and timeRifts.byInstance[instance] then return instance end
end

local function riftEligible(source)
    return not source.faction or safe(UnitFactionGroup, "player") == source.faction
end

local function scenarioCompletion()
    local info = C_ScenarioInfo and safe(C_ScenarioInfo.GetScenarioInfo)
    if type(info) == "table" and readable(info.isComplete) then return info.isComplete end
end

function timeRifts.observeScenario()
    local instance = currentRiftInstance()
    if not instance then timeRifts.visit = nil; return end
    local visit = timeRifts.visit
    if not visit or visit.instance ~= instance then
        visit = { instance = instance, receipts = {}, counts = {} }
        timeRifts.visit, timeRifts.worldLoot = visit, nil
    end
    if visit.armed or visit.completed then return end
    -- An already finished visit at login, reload or portal entry has no new attempt.
    if scenarioCompletion() == false then visit.armed = true end
end

local function settleRiftReceipt(context, id)
    local receipt, attempt = context.receipts[id], context.counts[id]
    if not receipt or not attempt then return end
    context.receipts[id] = nil
    local key = "mount:" .. id
    if not atlas.acquisitionAttempts(key) and (receipt.expires >= now() or (attempt.source == "riftBox" and itemLootOpen)) then
        attempt.awarded = atlas.rememberAcquisition(key, attempt.count, receipt.item, receipt.time, true, nil,
            attempt.source, attempt.total) ~= nil
    end
end

local function countRiftAttempt(context, id, source, count, earlier)
    local key = "mount:" .. id
    local otherKey = source == "riftFinal" and key or "rift:" .. id
    local total = count + atlas.rawStageAttempts(otherKey)
    local attempt = { source = source, count = count, total = total }
    if not earlier then
        context.counts[id] = attempt
        settleRiftReceipt(context, id)
    end
    local stage = stages[key]
    if stage then queueStageAttemptMessage(stage, total, nil, false, true, context, attempt) end
end

function timeRifts.complete(criterion, scenarioEvent)
    local visit = timeRifts.visit
    if not enteredWorld or not visit or not visit.armed or visit.completed
        or visit.instance ~= currentRiftInstance() then return end
    -- Use the native scenario completion as well as the timeline-specific criterion.
    -- Both signals describe the same visit, even if the achievement no longer updates.
    if scenarioEvent then
        if scenarioCompletion() ~= true then return end
    elseif not number(criterion) then return end
    local routes = timeRifts.byInstance[visit.instance]
    local eligibleMounts = {}
    local matched
    for id, source in pairs(routes) do
        if scenarioEvent or source.criterion == criterion then
            matched = true
            if riftEligible(source) then eligibleMounts[id] = true end
        end
    end
    if not matched then return end
    local character = record()
    if not character then return end
    visit.completed, visit.expires = true, now() + timeRifts.receiptWindow
    for id in pairs(eligibleMounts) do
        local key = "rift:" .. id
        local previous = character.stageAttempts[key]
        character.stageAttempts[key] = (number(previous) and math.floor(previous) or 0) + 1
        countRiftAttempt(visit, id, "riftFinal", atlas.rawStageAttempts(key))
    end
    if next(eligibleMounts) then
        if atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(eligibleMounts) end
        refreshAttempts(true)
    end
end

local function currentRiftBox()
    local box = timeRifts.box
    if box and (itemLootOpen or box.expires >= now()) then return box end
end

local function startRiftBox()
    local box = { receipts = {}, counts = {}, items = {}, expires = now() + timeRifts.receiptWindow }
    timeRifts.box = box
    return box
end

function timeRifts.countBox(id, count, amount)
    local box = currentRiftBox() or startRiftBox()
    if attemptChatEnabled() then
        -- Only the current window owns receipts. Earlier openings retain their own chat totals.
        for earlier = math.max(1, count - amount + 1), count - 1 do
            countRiftAttempt(box, id, "riftBox", earlier, true)
        end
    end
    countRiftAttempt(box, id, "riftBox", count)
end

function timeRifts.receiptPending(id)
    local box, visit = currentRiftBox(), timeRifts.visit
    local receipt = (box and box.receipts[id]) or (visit and visit.receipts[id])
    return receipt ~= nil and receipt.expires >= now()
end

local function riftFinalReceipt(source, item)
    local visit = timeRifts.visit
    if not enteredWorld or not visit or not visit.armed or (visit.completed and visit.expires < now())
        or visit.instance ~= source.instance or currentRiftInstance() ~= source.instance then return end
    local worldLoot = timeRifts.worldLoot
    if worldLoot and worldLoot.expires >= now() then
        if worldLoot.items[item] then return visit, true end
        return
    end
    return visit, false
end

function timeRifts.receive(item, confirmed)
    local id = timeRifts.byItem[item]
    if not id or blocked() or atlas.acquisitionAttempts("mount:" .. id) then return end
    local source = timeRiftSource(id)
    if not riftEligible(source) then return end
    local box = currentRiftBox()
    -- A receipt inside an item window can only settle against a counted box use.
    if hasPendingUse(timeRifts.container, now()) then
        box = box or startRiftBox()
    elseif itemLootOpen then
        if not box and not (number(bags[timeRifts.container]) and bags[timeRifts.container] > 0) then return end
        box = box or startRiftBox()
    elseif box and not box.counts[id] then
        box = nil
    end
    local visit, bossLoot = riftFinalReceipt(source, item)
    local boxLoot = box and box.items[item] == true
    -- Coincidentally opening a box during a finale does not identify the award.
    if box and visit and boxLoot == bossLoot then return end
    local context = not bossLoot and box or visit
    if not context or not (confirmed or boxLoot or bossLoot) then return end
    context.receipts[id] = { item = item, time = serverTime(), expires = now() + timeRifts.receiptWindow }
    settleRiftReceipt(context, id)
end

local function beginBlockedInteraction(kind)
    settleLootChat()
    interactions[kind] = true
    openingHover = nil
    if creatureLoot then creatureLoot = false end
    npcItemLoot = { items = {} }
    pendingUses, itemLootUntil, itemLootOpen, itemLootSettled = {}, 0, false, false
    timeRifts.box = nil
    if timeRifts.visit then timeRifts.visit.receipts = {} end
end

local function refreshBagBaseline()
    for item in pairs(useStages) do
        bags[item] = itemCount(item) or false
    end
end

local function scanBags(items, onlyDecreases)
    local time, allowed = now(), not blocked()
    for item in pairs(items) do
        local previous, uses = bags[item], pendingUses[item]
        local explicit = hasPendingUse(item, time)
        local itemLoot = itemLootUntil > time and not itemLootSettled
        local current
        if not onlyDecreases or ((explicit or itemLoot) and number(previous) and previous > 0) then current = itemCount(item) end
        if current ~= nil then
            bags[item] = current
            if allowed and number(previous) and current < previous and (explicit or itemLoot) then
                local cursor, heldItem = safe(GetCursorInfo)
                if cursor == "item" and number(heldItem) and heldItem == item then
                    pendingUses[item] = nil
                    if itemLoot then itemLootSettled = true end
                else
                    local decrease = previous - current
                    local count = 0
                    if explicit then
                        for _, use in ipairs(uses) do
                            if pendingUseReady(use, time) then
                                use.consumed = true
                                count = count + 1
                                if count == decrease then break end
                            end
                        end
                    else
                        count = 1
                    end
                    if itemLoot then itemLootSettled = true end
                    apply("USE", function(v) return contains(v.items, item) end, count, item)
                end
            end
            if current > 0 and (not number(previous) or previous == 0) then resolveItemSpell(item) end
        end
        if uses and uses[#uses].expires <= time then pendingUses[item] = nil end
    end
end

local function markUse(item, source, guid, phase)
    if not ready or blocked() or not number(item) or not useStages[item] then return end
    local time, uses = now(), pendingUses[item]
    local matched, available, retained = nil, 0, 0
    if uses then
        for _, use in ipairs(uses) do
            if use.expires > time then
                retained = retained + 1
                uses[retained] = use
                if not use.consumed and not use.failed then available = available + 1 end
                if guid and use.guid == guid then
                    matched = use
                -- A click and its spell can describe the same opening. Keep spent
                -- observations briefly so the confirming cast does not reopen them.
                elseif not matched and not use[source] and not use.failed
                    and (use.time == time or (source == "cast" and not use.consumed)) then
                    matched = use
                end
            end
        end
        for index = retained + 1, #uses do uses[index] = nil end
        if retained == 0 then uses, pendingUses[item] = nil, nil end
    end
    if not matched then
        if phase == "failed" or not number(bags[item]) or available >= bags[item] then return end
        uses = uses or {}
        matched = { time = time, expires = time + 8 }
        uses[#uses + 1], pendingUses[item] = matched, uses
    end
    if source == "cast" then
        matched.cast, matched.guid = true, guid
        if phase == "finished" then matched.succeeded = true
        elseif phase == "failed" and not matched.succeeded then matched.failed = true end
    else
        matched[source] = true
    end
    if item == timeRifts.container and pendingUseReady(matched, time) then
        local box = currentRiftBox()
        if not box or box.closed then startRiftBox() end
    end
end

local function isPool(name)
    return name and ((atlas.fishingPoolNames and atlas.fishingPoolNames[name] == true)
        or (type(Rarity) == "table" and type(Rarity.fishnodes) == "table" and Rarity.fishnodes[name] == true))
end

local function nodeMatches(names, node)
    if contains(names, node) then return true end
    if not node then return false end
    for _, name in ipairs(names or {}) do
        if atlas.attemptNodeNames and atlas.attemptNodeNames[name] == node then return true end
    end
    if not LibStub then return false end
    local ok, locale = pcall(function()
        local library = LibStub("AceLocale-3.0", true)
        return library and library:GetLocale("Rarity", true)
    end)
    if ok and type(locale) == "table" then
        for _, name in ipairs(names or {}) do if locale[name] == node then return true end end
    end
    return false
end

local function lootMatches(definition)
    local currency = definition.lootCurrency
    if not currency then return true end
    local slots = safe(GetNumLootItems)
    for slot = 1, number(slots) and slots or 0 do
        local link = safe(GetLootSlotLink, slot)
        local id = type(link) == "string" and tonumber(link:match("currency:(%d+)"))
        local _, _, quantity = safe(GetLootSlotInfo, slot)
        if id == currency.id and number(quantity) and quantity == currency.quantity then return true end
    end
    return false
end

local function isOpening(kind)
    return kind == "Opening" or kind == "Opening - No Text"
end

local function cleanNodeName(name)
    if readable(name) and type(name) == "string" and name ~= "" then
        return name:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
end

local function readableTable(value)
    return readable(value) and type(value) == "table" and (not canaccesstable or canaccesstable(value))
end

local function worldCursorObjectName()
    local objectType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
    if objectType and C_TooltipInfo and C_TooltipInfo.GetWorldCursor then
        local ok, data = pcall(C_TooltipInfo.GetWorldCursor)
        if ok and readable(data) and data == nil then return end
        if ok and readableTable(data) and readable(data.type) and data.type == objectType then
            local title = readableTable(data.lines) and data.lines[1]
            return readableTable(title) and cleanNodeName(title.leftText) or nil, true, true
        end
        return nil, true
    end
end

local function nodeName()
    local node = GameTooltipTextLeft1 and cleanNodeName(safe(GameTooltipTextLeft1.GetText, GameTooltipTextLeft1))
    if node then
        lastNode = { name = node, time = now() }
        if cast and cast.kind == "Fishing" and isPool(node) then cast.pool = true end
        return node
    end
end

local function openingStartName(requireWorldObject)
    local node, hasCursorData = worldCursorObjectName()
    if hasCursorData then return node end
    if openingHover and openingHover.expires >= now() then return openingHover.name, true end
    if requireWorldObject then return end
    if GameTooltip and GameTooltip.IsShown and not safe(GameTooltip.IsShown, GameTooltip) then return end
    return nodeName()
end

local function lootSources(slots)
    local creatures, objects, knownObject, hasSource = {}, {}, false, false
    local routedItems
    local riftLoot = timeRifts.visit and slots > 0 and { items = {}, expires = now() + timeRifts.receiptWindow }
    for slot = 1, slots do
        local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
        local link = riftLoot and safe(GetLootSlotLink, slot)
        local item = readable(link) and type(link) == "string" and tonumber(link:match("item:(%d+)"))
        local route = item and timeRiftSource(timeRifts.byItem[item])
        for i = 1, #sources, 2 do
            local guid = sources[i]
            if not readable(guid) then
                hasSource = true
            elseif type(guid) == "string" and guid ~= "" then
                hasSource = true
                local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
                id = tonumber(id)
                if kind == "Creature" or kind == "Vehicle" then
                    creatures[guid] = id
                    if route and id and route.npc == id then riftLoot.items[item] = true end
                    for _, entry in pairs(#sources == 2 and npcStages[id] or {}) do
                        if entry.definition.requiresLootSource then
                            if not link then link = safe(GetLootSlotLink, slot) end
                            item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
                            if item == entry.definition.item then
                                routedItems = routedItems or {}
                                routedItems[guid] = routedItems[guid] or {}
                                routedItems[guid][item] = true
                            end
                        end
                    end
                elseif kind == "GameObject" then
                    objects["node:" .. guid] = id
                    if objectNodes[id] then knownObject = true end
                end
            end
        end
    end
    if riftLoot then timeRifts.worldLoot = riftLoot end
    return creatures, objects, knownObject, hasSource, routedItems
end

local function trackNPCItemLoot(guid, npc, snapshot, confirmedItems)
    local entries = npcStages[npc]
    if not entries then return end
    for key, entry in pairs(entries) do
        local item = entry.definition.item
        local owner = acquisitionItems[item] and acquisitionItems[item][key]
        if owner and (owner.npcUnique or owner.requiresLootSource) then
            local previous = npcItemLoot.items[key]
            if not previous then
                npcItemLoot.items[key] = { guid = guid, heldBeforeLoot = snapshot and (itemCount(item) or false) }
                -- Autoloot can report LOOT_READY without a subsequent window.
                npcItemLoot.expires = now() + npcLootReceiptWindow
            elseif previous.guid ~= guid then
                previous.ambiguous = true
            end
            if owner.requiresLootSource and confirmedItems and confirmedItems[item] then
                npcItemLoot.items[key].confirmedSource = item
                if not lootChatOpen then settleNPCItemReceipt(key, npcItemLoot.items[key]) end
            end
        end
    end
end

local function prepareNPCItemLoot()
    if npcItemLoot.closed or (not lootChatOpen and npcItemLoot.expires and npcItemLoot.expires <= now()) then
        creatureLoot, npcItemLoot = nil, { items = {} }
    end
end

local function observeCreatureLoot(slots, hasSource, worldLootOpened, nativeFishing, autoloot)
    -- A late source can identify the loot even if the first event could not.
    if creatureLoot == false then return end
    local time = now()
    if creatureLoot and not creatureLoot.worldLootOpened and creatureLoot.expires <= time then creatureLoot = nil end
    if not creatureLoot then creatureLoot = { expires = time + npcLootReceiptWindow } end
    creatureLoot.worldLootOpened = creatureLoot.worldLootOpened or worldLootOpened
    if creatureLoot.rejected then return end
    if hasSource or nativeFishing ~= false or (cast and cast.expires > now()) then
        creatureLoot.rejected = true
        return
    end
    creatureLoot.autoloot = creatureLoot.autoloot or autoloot
    local _, _, cursorObject = worldCursorObjectName()
    if cursorObject then
        creatureLoot.rejected = true
        return
    end
    if creatureLoot.guid or slots == 0 then return end
    local target, mouseover = safe(UnitGUID, "target"), safe(UnitGUID, "mouseover")
    local unit = mouseover and mouseover ~= target and "mouseover" or "target"
    local guid = unit == "mouseover" and mouseover or target
    local npc = type(guid) == "string" and (guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    local classification = npc and safe(UnitClassification, unit)
    if not npc or type(classification) ~= "string" or classification == "minus"
        or safe(UnitIsDead, unit) ~= true or safe(UnitCanAttack, "player", unit) ~= true
        or safe(UnitIsPlayer, unit) ~= false then
        creatureLoot.rejected = true
        return
    end
    local hasLoot, canLoot = safe(CanLootUnit, guid)
    if hasLoot ~= true or not readable(canLoot) or canLoot ~= true then
        creatureLoot.rejected = true
        return
    end
    creatureLoot.guid, creatureLoot.npc, creatureLoot.unit = guid, tonumber(npc), unit
    creatureLoot.expires = time + npcLootReceiptWindow
    -- Autoloot can give a unique quest starter before the corpse is confirmed.
    trackNPCItemLoot(guid, creatureLoot.npc, true)
end

function atlas.hasCreatureKillStage(npc)
    return npcStages[npc] ~= nil
end

local function pruneStageLoot(character, time)
    if time - lastLootPrune < 60 then return end
    lastLootPrune = time
    for guid, expires in pairs(character.stageLootGUIDs) do
        if not number(expires) or expires <= time then character.stageLootGUIDs[guid] = nil end
    end
    local kills = character.stageCreatureKills
    if type(kills) ~= "table" then return end
    for guid, kill in pairs(kills) do
        if type(kill) ~= "table" or not number(kill.expires) or kill.expires <= time then kills[guid] = nil end
    end
end

function atlas.recordStageCreatureKill(guid, npc, allowMount)
    if not npcStages[npc] then return end
    local character = record()
    if not character then return end
    local time, expires = serverTime(), character.stageLootGUIDs[guid]
    if number(expires) and expires > time then return end
    pruneStageLoot(character, time)
    local kills = character.stageCreatureKills
    local kill = type(kills) == "table" and kills[guid]
    if type(kill) == "table" and number(kill.expires) and kill.expires > time then return end
    local applied = {}
    local changed = apply("NPC", function(variant, definition)
        if variant.requiresCreatureLoot or definition.requiresCreatureLoot or not contains(variant.npcs, npc) then return false end
        if not allowMount then return true end
        for _, mount in pairs(npcStages[npc][definition.key].mountIDs) do
            if allowMount(mount) then return true end
        end
        return false
    end, nil, npc, character, false, nil, applied)
    if not changed then return end
    if type(kills) ~= "table" then kills = {}; character.stageCreatureKills = kills end
    for key in pairs(applied) do
        local item = npcStages[npc][key].definition.item
        if acquisitionItems[item] and acquisitionItems[item][key] then applied[key] = total(key) end
    end
    kills[guid] = { expires = time + 86400, entries = applied, generation = MountAtlasAccountDB.statisticsGeneration }
end

local function recordStageCreatureLoot(creatures, character, time)
    local target = next(creatures) and safe(UnitGUID, "target")
    local mouseover = next(creatures) and safe(UnitGUID, "mouseover")
    for guid, npc in pairs(creatures) do trackNPCItemLoot(guid, npc) end
    for guid, npc in pairs(creatures) do
        local expires = character.stageLootGUIDs[guid]
        if not number(expires) or expires <= time then
            local unit = target == guid and "target" or mouseover == guid and "mouseover"
            if not unit or (safe(UnitClassification, unit) ~= "minus" and safe(UnitIsDead, unit) ~= false) then
                local kills = character.stageCreatureKills
                local kill = type(kills) == "table" and kills[guid]
                local entries = type(kill) == "table" and number(kill.expires) and kill.expires > time
                    and type(kill.entries) == "table" and kill.entries
                if entries and kill.generation == MountAtlasAccountDB.statisticsGeneration then
                    for key, attempts in pairs(entries) do
                        local loot = npcItemLoot.items[key]
                        if number(attempts) and loot and loot.guid == guid and not loot.ambiguous then
                            loot.attempts = attempts
                            if not lootChatOpen then settleNPCItemReceipt(key, loot) end
                        end
                    end
                end
                local changed = apply("NPC", function(v, definition)
                    return (not entries or not entries[definition.key]) and contains(v.npcs, npc)
                end, nil, npc, character, true, guid)
                local zoneChanged = apply("ZONE", function() return true end, nil, nil, character, true)
                if changed or zoneChanged then character.stageLootGUIDs[guid] = time + 86400 end
            end
        end
    end
end

local function finishCreatureLoot()
    local loot = creatureLoot
    creatureLoot = nil
    if not loot or loot.rejected or not loot.guid or not atlas.shouldCountCreatureLoot() then return end
    -- A hovered corpse can differ from the selected unit. Without a confirmed
    -- world window, or a stable selected corpse, only its exact depletion event
    -- ties the interaction to this GUID.
    if not loot.worldLootOpened and (not loot.autoloot or loot.expires <= now()) then return end
    local target, mouseover = safe(UnitGUID, "target"), safe(UnitGUID, "mouseover")
    if (not loot.worldLootOpened or loot.unit == "mouseover" or target ~= loot.guid or (mouseover and mouseover ~= loot.guid))
        and not loot.depleted then return end
    local hasLoot = safe(CanLootUnit, loot.guid)
    if hasLoot ~= false and not (hasLoot == nil and loot.depleted) then return end
    if atlas.recordCreatureLoot then atlas.recordCreatureLoot(loot.guid) end
    local character = record()
    if character then recordStageCreatureLoot({ [loot.guid] = loot.npc }, character, serverTime()) end
end

local function onNodeLoot(character, objects, knownObject, fromCreature, time, worldLootOpened, hasSlots)
    local gathering = cast and cast.expires > now() and cast.kind ~= "Fishing"
    if not gathering and not knownObject then return false end

    local opening = gathering and isOpening(cast.kind)
    local hasObject, seen = next(objects) ~= nil, character.stageLootGUIDs
    if opening then
        cast.lootCreature = cast.lootCreature or fromCreature
        cast.lootObject = cast.lootObject or hasObject
        cast.lootOpened = cast.lootOpened or worldLootOpened
        cast.lootHasSlots = cast.lootHasSlots or hasSlots
    end
    -- A name confirmed at START also works with autoloot at LOOT_READY.
    -- A dispatch or earlier hover name needs explicit world loot.
    local namedOpening = opening and cast.finished and cast.lootHasSlots and (cast.namedAtStart or cast.lootOpened)
        and not cast.lootCreature and cast.node
    if not lootCounted and (knownObject or namedOpening) then
        lootCounted = apply("SPECIAL", function(v)
            if not v.nodes then return false end
            if knownObject then
                -- A loot source ID identifies the chest even when its tooltip
                -- or opening-cast event is missing.
                for key, id in pairs(objects) do
                    if contains(v.objects, id) and (not number(seen[key]) or seen[key] <= time) then
                        return lootMatches(v)
                    end
                end
                return false
            end
            if cast.lootObject and v.objects then return false end
            for key in pairs(objects) do
                if number(seen[key]) and seen[key] > time then return false end
            end
            return nodeMatches(v.nodes, cast.node) and lootMatches(v)
        end, nil, nil, character, true)
    end
    -- A node already counted by name can gain its GUID in LOOT_OPENED.
    if lootCounted then
        for key in pairs(objects) do
            if not number(seen[key]) or seen[key] <= time then seen[key] = time + 86400 end
        end
    end
    return gathering -- Skinning/mining/opening is not another NPC or zone kill.
end

local function onLoot(worldLootOpened, autoloot)
    if not ready or blocked() or itemLootOpen then return end
    local slots = safe(GetNumLootItems)
    if not number(slots) then
        creatureLoot = false
        return
    end
    local creatures, objects, knownObject, hasSource, routedItems = lootSources(slots)
    local nativeFishing = safe(IsFishingLoot)
    observeCreatureLoot(slots, hasSource, worldLootOpened, nativeFishing, autoloot)
    -- Never use a stale fishing cast to reinterpret a known loot source.
    local fallbackFishing = nativeFishing == nil and cast and cast.kind == "Fishing" and cast.expires > now()
        and not next(creatures) and not knownObject
    if nativeFishing or fallbackFishing then
        if not next(creatures) then
            for key, entry in pairs(stagesByMethod.FISHING or {}) do
                local definition = entry.definition
                if definition.requiresLootSource then
                    local loot = npcItemLoot.items[key]
                    if not loot and not lootCounted then
                        loot = { guid = true }
                        npcItemLoot.items[key] = loot
                        npcItemLoot.expires = now() + npcLootReceiptWindow
                    end
                    for slot = 1, loot and slots or 0 do
                        local link = safe(GetLootSlotLink, slot)
                        local item = readable(link) and type(link) == "string" and tonumber(link:match("item:(%d+)"))
                        if item == definition.item then
                            loot.confirmedSource = item
                            if not lootChatOpen then settleNPCItemReceipt(key, loot) end
                            break
                        end
                    end
                end
            end
        end
        if not lootCounted then
            lootCounted = true
            local pool = cast and cast.pool
            apply("FISHING", function(v) return not v.requiresPool or pool == true end, nil, nil, nil, true, true)
            cast = nil
        end
        return
    end

    if routedItems then
        for guid, items in pairs(routedItems) do trackNPCItemLoot(guid, creatures[guid], nil, items) end
    end
    local character = record()
    if not character then return end
    local time = serverTime()
    pruneStageLoot(character, time)
    if onNodeLoot(character, objects, knownObject, next(creatures) ~= nil, time, worldLootOpened, slots > 0) then return end
    recordStageCreatureLoot(creatures, character, time)
end

local function onEncounter(encounter, difficulty)
    if not number(encounter) or not number(difficulty) or not encounterStages[encounter] then return end
    local key = "encounter:" .. encounter .. ":" .. difficulty
    if (recentEvents[key] or 0) > now() then return end
    recentEvents[key] = now() + 30
    apply("ENCOUNTER", function(v)
        return contains(v.encounters, encounter) and (not v.difficulties or contains(v.difficulties, difficulty))
    end, nil, encounter)
end

local function scanArchaeology(countAttempts)
    for race in pairs(archaeologyRaces) do
        local _, _, _, fragments
        if GetArchaeologyRaceInfoByID then _, _, _, fragments = safe(GetArchaeologyRaceInfoByID, race)
        else _, _, _, fragments = safe(GetArchaeologyRaceInfo, race, true) end
        if number(fragments) then
            if countAttempts and archaeology[race] and fragments < archaeology[race] then
                apply("ARCH", function(v) return v.raceId == race end)
            end
            archaeology[race] = fragments
        end
    end
end

local function onZone(initial)
    local map = mapID()
    if not number(map) then return end
    for key, entry in pairs(mapVisits) do
        local definition = entry.definition
        if contains(definition.zones, map) then
            if not visits[key] then visits[key] = now() end
        elseif visits[key] then
            local started = visits[key]
            visits[key] = nil
            if not initial and now() - started >= (definition.minimumSeconds or 60) then
                -- Eligibility was established inside the map. The exit event
                -- necessarily arrives after the current map changed.
                local exitDefinition = {}
                for field, value in pairs(definition) do exitDefinition[field] = value end
                exitDefinition.zones = nil
                if increment(entry, exitDefinition) then refreshAttempts(false) end
            end
        end
    end
end

local function onGossip()
    local text = C_GossipInfo and safe(C_GossipInfo.GetText)
    local guid = safe(UnitGUID, "npc")
    local npc = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    for key, entry in pairs(gossipStages) do
        local definition = entry.definition
        local phrase = definition.gossipText
        local translated = atlas.attemptNodeNames and atlas.attemptNodeNames[phrase]
        local matched = contains(definition.gossipNPCs, npc) or (type(text) == "string" and type(phrase) == "string"
            and (text:find(phrase, 1, true) or (translated and text:find(translated, 1, true))))
        if matched and gossipOpen[key] and increment(entry, definition) then refreshAttempts(false) end
        gossipOpen[key] = matched and true or nil
    end
end

local function onMouseover()
    local guid = safe(UnitGUID, "mouseover")
    if type(guid) ~= "string" then return end
    local npc = tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npc then return end
    local character = record()
    if not character then return end
    local key = "mouseover:" .. guid
    local expires = character.stageLootGUIDs[key]
    if number(expires) and expires > serverTime() then return end
    local changed = apply("SPECIAL", function(v) return v.event == "MOUSEOVER" and contains(v.npcs, npc) end)
    if changed then character.stageLootGUIDs[key] = serverTime() + 86400 end
end

local function readableCastGUID(guid)
    return readable(guid) and type(guid) == "string" and guid ~= ""
end

local function sameCast(guid, castBarID)
    if not cast then return false end
    if cast.guid and readableCastGUID(guid) then return cast.guid == guid end
    return cast.barID ~= nil and readable(castBarID) and cast.barID == castBarID
end

local function onCast(unit, guid, spell, phase, target, castBarID)
    if not readable(unit) or unit ~= "player" or not number(spell) then return end
    local finished, sent = phase == "finished", phase == "sent"
    if (finished or sent) and itemSpells[spell] then
        markUse(itemSpells[spell], "cast", readableCastGUID(guid) and guid or nil, phase)
    end
    local kind = atlas.attemptSpells and atlas.attemptSpells[spell]
    if not kind and (spell == 131474 or spell == 7620 or spell == 158743) then kind = "Fishing" end
    local opening = isOpening(kind)
    if sent and not opening then return end
    if kind then
        local barID = opening and readable(castBarID) and castBarID or nil
        local restrictedTarget = sent and not readable(target)
        local emptyTarget = sent and not restrictedTarget and target == ""
        -- Keep the identity sampled for this cast even after its tooltip disappears.
        if sameCast(guid, barID) and cast.spell == spell and cast.expires > now() then
            if barID ~= nil then cast.barID = barID end
            cast.expires = now() + (kind == "Fishing" and 35 or 8)
            if opening and finished then
                cast.finished = true
                if cast.lootOpened or (cast.namedAtStart and cast.lootHasSlots) then onLoot(cast.lootOpened) end
            elseif opening and sent and not cast.sent then
                local node, hasCursorData = cleanNodeName(target), false
                if emptyTarget then
                    node, hasCursorData = worldCursorObjectName()
                end
                if not emptyTarget or hasCursorData then
                    cast.namedAtStart = cast.namedAtStart and node == cast.node
                    cast.node = node
                end
                cast.sent = true
            elseif opening and not sent and not cast.started then
                local node, fromHover
                if cast.node or cast.canReadStart then node, fromHover = openingStartName(cast.restrictedTarget) end
                if cast.canReadStart then cast.node = node end
                cast.namedAtStart = not cast.restrictedTarget and not fromHover and node ~= nil and node == cast.node
                cast.started = true
            end
        else
            local node, hasCursorData, fromHover
            if sent then
                node = cleanNodeName(target)
                if emptyTarget then node, hasCursorData = worldCursorObjectName() end
            elseif opening then
                if not finished then node, fromHover = openingStartName() end
            else
                node = nodeName()
                if not node and lastNode and now() - lastNode.time <= 5 then node = lastNode.name end
            end
            cast = { kind = kind, spell = spell, guid = readableCastGUID(guid) and guid or nil, barID = barID,
                expires = now() + (kind == "Fishing" and 35 or 8), node = node, pool = isPool(node),
                sent = sent, started = not sent and not finished,
                namedAtStart = opening and not sent and not finished and not fromHover and node ~= nil,
                canReadStart = restrictedTarget or (emptyTarget and not hasCursorData), restrictedTarget = restrictedTarget }
        end
    elseif not finished then
        cast = nil
    end
    if finished and specialSpells[spell] then
        local key = readable(guid) and type(guid) == "string" and guid or ("spell:" .. spell)
        local time = now()
        for id, expires in pairs(recentEvents) do if expires <= time then recentEvents[id] = nil end end
        if not recentEvents[key] then
            recentEvents[key] = time + 2
            apply("SPECIAL", function(v) return contains(v.spells, spell) end)
        end
    end
end

function atlas.resetAttemptStageSession()
    sessionGeneration = sessionGeneration + 1
    lootChat, lootChatOpen = {}, false
    pendingUses, visits, gossipOpen = {}, {}, {}
    pendingStageMessages, pendingAcquisitions = {}, {}
    cast, lastNode, openingHover, lootCounted = nil, nil, nil, false
    creatureLoot, npcItemLoot = nil, { items = {} }
    itemLootUntil, itemLootOpen, itemLootSettled = 0, false, false
    timeRifts.visit, timeRifts.box, timeRifts.worldLoot = nil, nil, nil
    timeRifts.observeScenario()
    observeLootQuests(true)
    refreshBagBaseline()
    scanArchaeology(false)
end

function atlas.initializeAttemptStages()
    if ready then return end
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    for _, character in pairs(type(characters) == "table" and characters or {}) do
        atlas.preserveStageDailyLocks(character)
    end
    buildStages()
    refreshBagBaseline()
    scanArchaeology(false)
    if hooksecurefunc then
        if C_Container and C_Container.UseContainerItem then
            hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
                markUse(safe(C_Container.GetContainerItemID, bag, slot), "slot")
            end)
        end
        if UseItemByName then
            hooksecurefunc("UseItemByName", function(item)
                local id = tonumber(item) or (C_Item and safe(C_Item.GetItemInfoInstant, item))
                markUse(id, "named")
            end)
        end
    end
    for _, name in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED",
        "CURSOR_CHANGED",
        "PLAYER_ENTERING_WORLD", "RESEARCH_ARTIFACT_COMPLETE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE",
        "ENCOUNTER_END", "BOSS_KILL", "GOSSIP_SHOW", "GOSSIP_CLOSED", "ZONE_CHANGED_NEW_AREA", "UPDATE_MOUSEOVER_UNIT",
        "ITEM_DATA_LOAD_RESULT", "SHOW_LOOT_TOAST", "CHAT_MSG_LOOT", "PLAYER_TARGET_CHANGED", "UNIT_LOOT" }) do
        events:RegisterEvent(name)
    end
    if next(timeRifts.byInstance) then
        events:RegisterEvent("SCENARIO_UPDATE")
        events:RegisterEvent("SCENARIO_COMPLETED")
        events:RegisterEvent("CRITERIA_COMPLETE")
    end
    for _, name in ipairs({ "UNIT_SPELLCAST_SENT", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET", "UNIT_SPELLCAST_INTERRUPTED" }) do
        events:RegisterUnitEvent(name, "player")
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        observeLootQuests(true)
        settleLootChat()
        refreshBagBaseline()
        scanArchaeology(false)
        cast, lastNode, openingHover, pendingUses, interactions, lootCounted = nil, nil, nil, {}, {}, false
        creatureLoot, npcItemLoot = nil, { items = {} }
        itemLootUntil, itemLootOpen, itemLootSettled = 0, false, false
        timeRifts.box, timeRifts.worldLoot = nil, nil
        timeRifts.observeScenario()
        onZone(not enteredWorld)
        enteredWorld = true
    elseif event == "LOOT_READY" then
        prepareNPCItemLoot()
        local autoloot = ...
        onLoot(nil, readable(autoloot) and autoloot == true)
        observeLootQuests(not enteredWorld)
    elseif event == "LOOT_OPENED" then
        local _, fromItem = ...
        prepareNPCItemLoot()
        lootChatOpen = true
        local wasItemLootOpen = itemLootOpen
        local box = currentRiftBox()
        itemLootOpen = readable(fromItem) and fromItem == true and not blocked()
        if not readable(fromItem) or fromItem ~= false then creatureLoot, npcItemLoot = false, { items = {} } end
        if itemLootOpen then
            if not wasItemLootOpen and not hasPendingUse(timeRifts.container, now())
                and (not box or box.closed or not next(box.counts)) then
                box, timeRifts.box = nil, nil
            end
            if number(bags[timeRifts.container]) and bags[timeRifts.container] > 0 then
                box = box or startRiftBox()
            end
            if box then
                local slots = safe(GetNumLootItems)
                for slot = 1, number(slots) and slots or 0 do
                    local link = safe(GetLootSlotLink, slot)
                    local item = type(link) == "string" and tonumber(link:match("item:(%d+)"))
                    if item and timeRifts.byItem[item] then box.items[item] = true end
                end
            end
            timeRifts.worldLoot = nil
            openingHover = nil
            itemLootUntil = now() + 3
            if not wasItemLootOpen then itemLootSettled = false end
            if cast and isOpening(cast.kind) then cast = nil end
        else
            timeRifts.box = nil
            onLoot(readable(fromItem) and fromItem == false)
            observeLootQuests(not enteredWorld)
        end
    elseif event == "LOOT_CLOSED" then
        -- A bag update may have already confirmed the open. Only an unresolved
        -- item window or an explicit tracked use needs a follow-up read here.
        if itemLootOpen and not itemLootSettled then scanBags(useStages, true)
        elseif next(pendingUses) then scanBags(pendingUses, true) end
        finishCreatureLoot()
        observeLootQuests(not enteredWorld)
        if not npcItemLoot.closed then
            for key, loot in pairs(npcItemLoot.items) do settleNPCItemReceipt(key, loot) end
            npcItemLoot.closed, npcItemLoot.expires = true, now() + npcLootReceiptWindow
        end
        local box = currentRiftBox()
        if box and not box.closed and (itemLootOpen or next(box.counts)) then
            box.closed, box.expires = true, now() + timeRifts.receiptWindow
        end
        itemLootOpen = false
        finalizePendingAcquisitions(false)
        settleLootChat()
        lootCounted, cast, lastNode, openingHover = false, nil, nil, nil
    elseif event == "PLAYER_TARGET_CHANGED" then
        local target = safe(UnitGUID, "target")
        if creatureLoot and creatureLoot.unit == "target" and target and target ~= creatureLoot.guid then creatureLoot.rejected = true end
    elseif event == "UNIT_LOOT" then
        local guid, hasLoot = ...
        local loot = creatureLoot
        if loot and not loot.rejected and loot.guid and readable(guid) and guid == loot.guid
            and readable(hasLoot) and type(hasLoot) == "boolean" then
            loot.depleted = not hasLoot
            if loot.autoloot and loot.depleted and not loot.worldLootOpened and not loot.settling then
                loot.settling = true
                C_Timer.After(0, function()
                    if creatureLoot ~= loot then return end
                    loot.settling = nil
                    if loot.depleted and not loot.worldLootOpened then finishCreatureLoot() end
                end)
            end
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        scanBags(useStages)
        finalizePendingAcquisitions(true)
    elseif event == "CHAT_MSG_LOOT" then onItemReceived((...), select(11, ...))
    elseif event == "SHOW_LOOT_TOAST" then
        local kind, link, quantity, _, _, personal = ...
        if readable(kind) and kind == "item" and readable(link) and type(link) == "string" then
            local item = tonumber(link:match("item:(%d+)"))
            if item then
                if timeRifts.byItem[item] and number(quantity) and quantity > 0 and readable(personal) and personal == true then
                    timeRifts.receive(item, true)
                    if atlas.notifyMountItemLoot then atlas.notifyMountItemLoot(item, true) end
                end
                apply("LOOT_TOAST", function(v) return contains(v.toastItems, item) end)
            end
        end
    elseif event == "SCENARIO_UPDATE" then timeRifts.observeScenario()
    elseif event == "SCENARIO_COMPLETED" then timeRifts.complete(nil, true)
    elseif event == "CRITERIA_COMPLETE" then timeRifts.complete((...))
    elseif event == "CURSOR_CHANGED" then
        local name = worldCursorObjectName()
        openingHover = name and { name = name, expires = now() + 2 } or nil
        nodeName()
    elseif event == "UNIT_SPELLCAST_SENT" then
        local unit, target, guid, spell = ...
        onCast(unit, guid, spell, "sent", target)
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then
        local unit, guid, spell, castBarID = ...
        onCast(unit, guid, spell, nil, nil, castBarID)
        if readable(unit) and unit == "player" then openingHover = nil end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, guid, spell, castBarID = ...
        onCast(unit, guid, spell, "finished", nil, castBarID)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_FAILED_QUIET" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        local unit, guid, spell = ...
        local castBarID = select(event == "UNIT_SPELLCAST_INTERRUPTED" and 5 or 4, ...)
        if readable(unit) and unit == "player" then
            if number(spell) and itemSpells[spell] then
                markUse(itemSpells[spell], "cast", readableCastGUID(guid) and guid or nil, "failed")
            end
            if sameCast(guid, castBarID) then cast, lastNode, openingHover = nil, nil, nil end
        end
    elseif event == "TRADE_SKILL_SHOW" then
        beginBlockedInteraction("tradeSkill")
        scanArchaeology(false)
    elseif event == "TRADE_SKILL_CLOSE" then
        refreshBagBaseline()
        interactions.tradeSkill = nil
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local kind = ...
        if readable(kind) and kind ~= nil then beginBlockedInteraction(kind) end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        refreshBagBaseline()
        local kind = ...
        if readable(kind) and kind ~= nil then interactions[kind] = nil end
    elseif event == "RESEARCH_ARTIFACT_COMPLETE" then
        local generation = sessionGeneration
        if C_Timer then
            for _, delay in ipairs({ .2, 1 }) do
                C_Timer.After(delay, function()
                    if generation == sessionGeneration then scanArchaeology(true) end
                end)
            end
        end
    elseif event == "QUEST_LOG_UPDATE" then
        observeLootQuests(not enteredWorld)
    elseif event == "QUEST_TURNED_IN" then
        observeLootQuests(not enteredWorld)
        local quest = ...
        if number(quest) then
            local key = "quest:" .. quest
            if (recentEvents[key] or 0) <= now() then
                recentEvents[key] = now() + 5
                apply("SPECIAL", function(v) return contains(v.quests, quest) end)
            end
        end
    elseif event == "ENCOUNTER_END" then
        local encounter, _, difficulty, _, success = ...
        if readable(success) and success == 1 then onEncounter(encounter, difficulty) end
    elseif event == "BOSS_KILL" then
        onEncounter((...), select(3, GetInstanceInfo()))
    elseif event == "ZONE_CHANGED_NEW_AREA" then onZone(false)
    elseif event == "GOSSIP_SHOW" then onGossip()
    elseif event == "GOSSIP_CLOSED" then gossipOpen = {}
    elseif event == "UPDATE_MOUSEOVER_UNIT" then onMouseover()
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        local item, success = ...
        if number(item) and readable(success) and success then resolveItemSpell(item) end
    end
end)
