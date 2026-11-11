local _, atlas = ...
local events = CreateFrame("Frame")
local stages, bags, pendingUses, itemSpells = {}, {}, {}, {}
local stagesByMethod, npcStages, specialSpells = {}, {}, {}
local resolvedItemSpells = {}
local acquisitionItems, collectionReceipts = {}, {}
local mountsByID = {}
local interactions, archaeology, visits, gossipOpen = {}, {}, {}, {}
local ready, lootCounted, itemLootUntil, enteredWorld = false, false, 0, false
local cast, lastNode, notificationGuard
local recentEvents = {}
local pendingMessages = {}
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
    local map = mapID()
    if definition.excludedMaps and contains(definition.excludedMaps, map) then return false end
    if not definition.zones or not next(definition.zones) then return true end
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

local function eligible(definition)
    if not inZone(definition) then return false end
    local faction = safe(UnitFactionGroup, "player")
    if definition.requiresHorde and faction ~= "Horde" then return false end
    if definition.requiresAlliance and faction ~= "Alliance" then return false end
    local _, class = safe(UnitClass, "player")
    if definition.disableForClass and readable(class) and contains(definition.disableForClass, class) then return false end
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
    if definition.unique and C_Item then
        local count = safe(C_Item.GetItemCount, definition.item, false, false, false, false)
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

local function total(key)
    local raw = atlas.rawStageAttempts(key)
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
    local id = type(key) == "string" and tonumber(key:match("^mount:(%d+)$"))
    local definitions = id and atlas.attemptStages and atlas.attemptStages[id]
    return definitions and definitions.reward, id
end

-- Freeze success counts; later farming and imports must not rewrite an award.
function atlas.rememberAcquisition(key, attempts, item, acquiredAt)
    if not number(attempts) or attempts < 1 then return end
    local reward = acquisitionReward(key)
    if reward and reward.unverifiedEligibility then return end
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    local records = MountAtlasAccountDB.acquisitionAttempts
    if type(records) ~= "table" then records = {}; MountAtlasAccountDB.acquisitionAttempts = records end
    if not records[key] then records[key] = { attempts = math.floor(attempts), item = item,
        time = number(acquiredAt) and acquiredAt or serverTime(),
        source = reward and reward.rarityIncompatible and "local" or nil } end
    return records[key]
end

function atlas.acquisitionAttempts(key)
    local records = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.acquisitionAttempts
    local record = type(records) == "table" and records[key]
    if type(record) ~= "table" or not number(record.attempts) or record.attempts <= 0 then return end
    local reward, id = acquisitionReward(key)
    if reward and reward.unverifiedEligibility then return end
    if reward and reward.rarityIncompatible and record.source ~= "local" then
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

local function stageName(definition, fallback)
    local name = C_Item and safe(C_Item.GetItemInfo, definition.item)
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

local function progress(definition, fallback)
    if type(definition) ~= "table" or type(definition.key) ~= "string" then return end
    local collection = definition.method == "COLLECTION"
    local count = supported(definition) and total(definition.key) or nil
    local perAttempt, cumulative = probability(not collection and definition.rate or nil, count or 0)
    if count == nil then cumulative = nil end
    local collected = (definition.inventoryGoal or (number(definition.required) and definition.required > 1)) and C_Item
        and safe(C_Item.GetItemCount, definition.item, true, false, true, true) or nil
    return { item = definition.item, name = stageName(definition, fallback), englishName = definition.englishName, required = definition.required,
        collected = number(collected) and collected or nil, collection = collection,
        attempts = count, perAttempt = perAttempt, cumulative = cumulative, method = definition.method,
        rateEstimated = definition.rateEstimated == true,
        contentsPerOpening = probability(definition.contentsRate, 0) }
end

local function usesExistingCounter(mount, definition)
    if atlas.usesKillAPI(mount) then return true end
    return (definition.method == "NPC" or definition.method == "BOSS" or definition.method == "ENCOUNTER")
        and not mount.journalOnly and (mount.npcs ~= nil or mount.encounter ~= nil)
end

local function prerequisiteProgress(mount, definition, reward, fallback)
    local result = progress(definition, fallback)
    if not result then return end
    local count
    if usesExistingCounter(mount, reward) then count = atlas.kills(mount)
    elseif supported(reward) then count = total(reward.key) end
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

function atlas.itemAttemptProgress(mount)
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    if not definitions then return end
    if definitions.item then
        if definitions.item.attemptsFromReward and definitions.reward then
            return prerequisiteProgress(mount, definitions.item, definitions.reward)
        end
        return progress(definitions.item)
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
        loot and loot.item == definition.item and loot.name or nil)
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
    if safe(IsFishingLoot) == true then return false end
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

function atlas.rewardAttemptProgress(mount)
    local definition = atlas.attemptStages and atlas.attemptStages[mount.id]
    definition = definition and definition.reward
    if not definition or not atlas.rewardChanceEligible(mount)
        or usesExistingCounter(mount, definition) or not supported(definition) then return end
    if definition.method == "COLLECTION" then return end
    return progress(definition, mount.name)
end

function atlas.captureMountAcquisition(mount)
    local key = "mount:" .. mount.id
    local saved = atlas.acquisitionAttempts(key)
    if saved then return saved end
    local definitions = atlas.attemptStages[mount.id]
    local reward = definitions and definitions.reward
    if reward and reward.unverifiedEligibility then return end
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

local function finalizePendingAcquisitions(inventoryUpdated)
    for key, pending in pairs(pendingAcquisitions) do
        local held = C_Item and safe(C_Item.GetItemCount, pending.item, true, false, true, true)
        local count = pending.minimumAttempts and total(key)
        local counted = not pending.minimumAttempts or (number(count) and count >= pending.minimumAttempts)
        if pending.expires <= now() then pendingAcquisitions[key] = nil
        elseif counted and (not pending.required or (number(held) and held >= pending.required)) then
            if pending.minimumAttempts then pending.attempts = count end
            atlas.rememberAcquisition(key, pending.attempts, pending.item, pending.time)
            pendingAcquisitions[key] = nil
        elseif counted and inventoryUpdated and number(held) then
            -- This loot's inventory update settled below the goal. Do not let
            -- a later unrelated bag change turn its first shard into success.
            pendingAcquisitions[key] = nil
        end
    end
end

local function waitingForContainer(key)
    -- Loot chat may precede the bag update that counts the opened container.
    -- Freeze the successful total only after that pending use is recorded.
    local entry = stages[key]
    if not entry then return false end
    for _, variant in ipairs(entry.definition.variants or { entry.definition }) do
        if (variant.method or entry.definition.method) == "USE" then
            for _, item in ipairs(variant.items or {}) do
                local pending = pendingUses[item]
                local held = C_Item and safe(C_Item.GetItemCount, item, false, false, false, false)
                if (pending and pending > now()) or (itemLootUntil > now()
                    and number(bags[item]) and number(held) and held < bags[item]) then return true end
            end
        end
    end
    return false
end

function atlas.mountLootAttemptsPending(id)
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

local ownLootSingle, ownLootMultiple = ownLootPattern(LOOT_ITEM_SELF), ownLootPattern(LOOT_ITEM_SELF_MULTIPLE)

local function recordCollectionReceipt(item, message, lineID)
    if not collectionReceipts[item] or not number(lineID) or lineID <= 0 then return end
    -- Regular self-loot confirms receipt. Crafted and pushed item messages
    -- also cover other inventory changes and do not seed collection history.
    local normalized, links = message:gsub("|c%x%x%x%x%x%x%x%x|Hitem:.-|h.-|h|r", "\001", 1)
    if links == 0 then normalized, links = message:gsub("|cn[%w_]+:|Hitem:.-|h.-|h|r", "\001", 1) end
    if links == 0 then normalized = message:gsub("|Hitem:.-|h.-|h", "\001", 1) end
    local quantity = ownLootMultiple and tonumber(normalized:match(ownLootMultiple))
    if not quantity and ownLootSingle and normalized:match(ownLootSingle) then quantity = 1 end
    if not number(quantity) or quantity < 1 then return end
    local time, key = now(), "collection:" .. lineID
    if (recentEvents[key] or 0) > time then return end
    local character = record()
    if not character then return end
    if time - lastCollectionPrune >= 60 then
        for id, expires in pairs(recentEvents) do if expires <= time then recentEvents[id] = nil end end
        lastCollectionPrune = time
    end
    recentEvents[key] = time + 60
    if type(character.collectionItems) ~= "table" then character.collectionItems = {} end
    local previous = character.collectionItems[item]
    character.collectionItems[item] = (number(previous) and math.floor(previous) or 0) + quantity
    if atlas.refreshDetails then atlas.refreshDetails() end
end

local function onItemReceived(message, lineID)
    if not readable(message) or type(message) ~= "string" then return end
    local item = tonumber(message:match("|Hitem:(%d+)"))
    if not item then return end
    recordCollectionReceipt(item, message, lineID)
    local selfLoot = false
    for _, name in ipairs({ "LOOT_ITEM_SELF", "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF",
        "LOOT_ITEM_CREATED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_PUSHED_SELF_MULTIPLE" }) do
        local template = _G[name]
        local prefix = type(template) == "string" and template:match("^(.-)%%")
        if prefix and prefix ~= "" and message:sub(1, #prefix) == prefix then selfLoot = true; break end
    end
    if not selfLoot then return end
    local owners = acquisitionItems[item]
    if not owners then
        if atlas.notifyMountItemLoot then atlas.notifyMountItemLoot(item) end
        return
    end
    local generation = sessionGeneration
    for key, owner in pairs(owners) do
        local waiting = waitingForContainer(key)
        if (owner.required or waiting) and not atlas.acquisitionAttempts(key) then
            local count = owner.mount and atlas.kills(owner.mount) or total(key)
            if number(count) and (count > 0 or waiting) then
                pendingAcquisitions[key] = { item = item, required = owner.required, attempts = count,
                    minimumAttempts = waiting and count + 1 or nil,
                    time = serverTime(), expires = now() + 20 }
            end
        end
    end
    -- Let loot/statistic events for the successful attempt finish first.
    C_Timer.After(.1, function()
        if generation ~= sessionGeneration then return end
        for key, owner in pairs(acquisitionItems[item] or {}) do
            if not owner.required and not pendingAcquisitions[key] then
                local count = owner.mount and atlas.kills(owner.mount) or total(key)
                atlas.rememberAcquisition(key, count, item)
            end
        end
        finalizePendingAcquisitions(false)
    end)
    if atlas.notifyMountItemLoot then atlas.notifyMountItemLoot(item, true) end
end

function atlas.defaultChatMessageFormat()
    return atlas.L("PawAtlas: {название} — попытка {попытки} · вероятность за попытки: {вероятность}")
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

function atlas.formatAttemptMessage(name, attempts, cumulative, perAttempt, item, templateOverride)
    local settings = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    local template = templateOverride ~= nil and templateOverride or (settings and settings.chatMessageFormat)
    local default = atlas.defaultChatMessageFormat()
    if type(template) ~= "string" or template == "" then template = default end
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
    if not number(cumulative) and template == default then template = atlas.L("PawAtlas: {название} — попытка {попытки}") end
    local itemName, count = attemptItemIcon(item) .. tostring(name or "—"), tostring(attempts or 0)
    local values = { ["название"] = itemName, ["попытки"] = count, ["вероятность"] = probabilityText,
        mount = itemName, attempts = count, probability = probabilityText }
    return (template:gsub("{([^{}]+)}", function(token) return values[token] or "{" .. token .. "}" end):gsub("[\r\n]", " "))
end

local function output(name, attempts, cumulative, perAttempt, item)
    local settings = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    if settings and settings.chatMessages == false then return end
    if not name or not DEFAULT_CHAT_FRAME or not DEFAULT_CHAT_FRAME.AddMessage then return end
    DEFAULT_CHAT_FRAME:AddMessage(atlas.formatAttemptMessage(name, attempts, cumulative, perAttempt, item))
end

local function uncollected(id)
    if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return true end
    local owned = safe(function() return select(11, C_MountJournal.GetMountInfoByID(id)) end)
    return owned == false
end

local function notifyStage(entry, count, cumulative)
    if MountAtlasAccountDB.settings and MountAtlasAccountDB.settings.chatMessages == false then return end
    for id in pairs(entry.mountIDs) do
        if uncollected(id) then
            local name = stageName(entry.definition, entry.name)
            if name then output(name, count, cumulative, probability(entry.definition.rate, count or 0), entry.definition.item)
            else pendingMessages[entry.definition.key] = { entry = entry, count = count, cumulative = cumulative, expires = now() + 20 } end
            return
        end
    end
end

function atlas.notifyMountAttempt(mount)
    if notificationGuard or not uncollected(mount.id) then return end
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    if definitions and definitions.reward and not usesExistingCounter(mount, definitions.reward) then return end
    notificationGuard = true
    local itemProgress = atlas.itemAttemptProgress(mount)
    if itemProgress and definitions and definitions.reward and definitions.reward.item == itemProgress.item then
        notifyStage({ definition = definitions.reward, name = itemProgress.name, mountIDs = { [mount.id] = true } },
            itemProgress.attempts or 0, itemProgress.cumulative)
    else
        local perAttempt, cumulative, attempts = atlas.dropProbability(mount)
        local item = definitions and definitions.reward and definitions.reward.item
        if not item and atlas.rewardItem then
            local reward = atlas.rewardItem(mount)
            item = reward and reward.item
        end
        output(mount.name, attempts or atlas.kills(mount) or 0, cumulative, perAttempt, item)
    end
    notificationGuard = false
end

function atlas.notifyKillStatistic(id)
    if notificationGuard then return end
    if stages[id] then
        local count = total(id)
        local _, cumulative = probability(stages[id].definition.rate, count or 0)
        notifyStage(stages[id], count or 0, count and cumulative or nil)
        return
    end
    for _, mount in ipairs(atlas.mounts) do
        if mount.id == id then atlas.notifyMountAttempt(mount); return end
    end
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

local function increment(entry, variant, amount, credited)
    local character = record()
    if not character or not eligible(variant) or not cooldownAvailable(character, entry.definition) then return false end
    local definition = entry.definition
    if variant.firstDaily or definition.firstDaily then
        if not claimFirstDaily(definition.key) then return false end
        amount = 1
    end
    local previous = character.stageAttempts[definition.key]
    character.stageAttempts[definition.key] = (number(previous) and math.floor(previous) or 0) + (amount or 1)
    if atlas.recordImportedStatistic then
        atlas.recordImportedStatistic(definition.key, safe(UnitGUID, "player"), amount or 1)
    end
    if definition.cooldownSeconds then character.stageCooldowns[definition.key] = serverTime() + definition.cooldownSeconds end
    local count = total(definition.key)
    local _, cumulative = probability(variant.rate or definition.rate, count)
    if credited then
        for id in pairs(entry.mountIDs) do credited[id] = true end
    elseif atlas.recordBrokerAttempt then
        atlas.recordBrokerAttempt(entry.mountIDs)
    end
    notifyStage(entry, count, cumulative)
    return true
end

local function variants(entry)
    return entry.definition.variants or { entry.definition }
end

local function opportunityLocks(entry, npc)
    local locks, open = {}, false
    if not atlas.planStageOpportunityKey then return locks, true end
    local attempts = type(MountAtlasDB) == "table" and MountAtlasDB.lastAttempts
    local time = serverTime()
    for id in pairs(entry.mountIDs) do
        local mount = mountsByID[id]
        local key, frequency
        if mount then key, frequency = atlas.planStageOpportunityKey(mount, entry.definition, npc) end
        if key then
            local getter = C_DateAndTime and (frequency == "daily" and C_DateAndTime.GetSecondsUntilDailyReset
                or C_DateAndTime.GetSecondsUntilWeeklyReset)
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

local function apply(method, match, amount, npc)
    local candidates = stagesByMethod[method]
    if method == "NPC" then candidates = npcStages[npc] end
    if not candidates then return false end
    local changed, pendingLocks, credited = false, {}, {}
    for _, entry in pairs(candidates) do
        for _, variant in ipairs(variants(entry)) do
            if (variant.method or entry.definition.method) == method and match(variant, entry.definition) then
                local locks, available = opportunityLocks(entry, npc)
                if available and increment(entry, variant, amount, credited) then
                    changed = true
                    for key, expires in pairs(locks) do pendingLocks[key] = expires end
                    break
                end
            end
        end
    end
    -- Commit after every reward/prerequisite sharing this loot event was tested.
    -- This records reset progress without creating a second boss/rare counter.
    if next(pendingLocks) then
        if type(MountAtlasDB) ~= "table" then MountAtlasDB = {} end
        if type(MountAtlasDB.lastAttempts) ~= "table" then MountAtlasDB.lastAttempts = {} end
        for key, expires in pairs(pendingLocks) do MountAtlasDB.lastAttempts[key] = expires end
    end
    if changed then
        if atlas.recordBrokerAttempt then atlas.recordBrokerAttempt(credited) end
        if atlas.refreshPlanSnapshot then atlas.refreshPlanSnapshot() end
        if atlas.refreshDetails then atlas.refreshDetails() end
    end
    return changed
end

local function itemCount(id)
    local count = C_Item and safe(C_Item.GetItemCount, id, false, false, false, false)
    return number(count) and math.floor(count) or nil
end

local function resolveItemSpell(item)
    local spell = resolvedItemSpells[item]
    if not spell and C_Item then
        local _, id = safe(C_Item.GetItemSpell, item)
        if number(id) then
            spell = id
            resolvedItemSpells[item] = spell
        end
    end
    if spell then itemSpells[spell] = item end
end

local function buildStages()
    stages, bags, itemSpells, mountsByID, acquisitionItems = {}, {}, {}, {}, {}
    collectionReceipts = {}
    stagesByMethod, npcStages, specialSpells, resolvedItemSpells = {}, {}, {}, {}
    for _, mount in ipairs(atlas.mounts or {}) do mountsByID[mount.id] = mount end
    for id, definitions in pairs(atlas.attemptStages or {}) do
        local mount = mountsByID[id]
        for _, item in ipairs(collectionItems(definitions.item) or {}) do collectionReceipts[item] = true end
        for _, role in ipairs({ "item", "reward" }) do
            local definition = definitions[role]
            if definition and definition.unverifiedEligibility then definition = nil end
            local existing = (role == "item" and definition and definition.attemptsFromReward)
                or (role == "reward" and ((definition and definition.historical) or (atlas.killStatistics and atlas.killStatistics[id])
                    or (mount and usesExistingCounter(mount, definition or {}))))
            if definition and definition.item and not definition.historical then
                local counterMount = role == "reward" and mount and usesExistingCounter(mount, definition) and mount or nil
                if counterMount or (not existing and supported(definition)) then
                    local owners = acquisitionItems[definition.item] or {}
                    acquisitionItems[definition.item] = owners
                    owners[definition.key] = { mount = counterMount,
                        required = role == "item" and definition.required and definition.required > 1 and definition.required or nil }
                end
            end
            if definition and definition.key and not existing then
                local entry = stages[definition.key] or { definition = definition,
                    name = role == "reward" and mount and mount.name or nil, mountIDs = {} }
                entry.mountIDs[id] = true
                stages[definition.key] = entry
                if C_Item and C_Item.RequestLoadItemDataByID and definition.item then
                    pcall(C_Item.RequestLoadItemDataByID, definition.item)
                end
                for _, variant in ipairs(definition.variants or { definition }) do
                    for _, item in ipairs(variant.items or {}) do
                        bags[item] = itemCount(item) or false
                        resolveItemSpell(item)
                    end
                end
            end
        end
    end
    for key, entry in pairs(stages) do
        for _, variant in ipairs(variants(entry)) do
            local method = variant.method or entry.definition.method
            if method == "NPC" then
                for index, value in pairs(variant.npcs or {}) do
                    local npc = tonumber(value == true and index or value)
                    if npc then
                        local rewards = npcStages[npc] or {}
                        npcStages[npc] = rewards
                        rewards[key] = entry
                    end
                end
            elseif method then
                local candidates = stagesByMethod[method] or {}
                stagesByMethod[method] = candidates
                candidates[key] = entry
                if method == "SPECIAL" then
                    for index, value in pairs(variant.spells or {}) do
                        local spell = tonumber(value == true and index or value)
                        if spell then specialSpells[spell] = true end
                    end
                end
            end
        end
    end
    ready = true
end

local function blocked()
    return next(interactions) ~= nil
end

local function scanBags()
    for item, previous in pairs(bags) do
        local current = itemCount(item)
        if current ~= nil then
            local pending = pendingUses[item]
            if ready and not blocked() and number(previous) and current < previous
                and ((pending and pending > now()) or itemLootUntil > now()) then
                apply("USE", function(v) return contains(v.items, item) end, previous - current)
                pendingUses[item] = nil
            end
            bags[item] = current
            resolveItemSpell(item)
        end
    end
end

local function markUse(item)
    if not ready or blocked() or not number(item) then return end
    if bags[item] ~= nil then pendingUses[item] = now() + 8 end
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

local function nodeName()
    local node = GameTooltipTextLeft1 and safe(GameTooltipTextLeft1.GetText, GameTooltipTextLeft1)
    if type(node) == "string" and node ~= "" then
        lastNode = { name = node:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""), time = now() }
        if cast and cast.kind == "Fishing" and isPool(lastNode.name) then cast.pool = true end
    end
end

local function onLoot()
    if not ready or blocked() then return end
    local slots = safe(GetNumLootItems)
    if not number(slots) then return end
    local nativeFishing = safe(IsFishingLoot)
    local fishing = nativeFishing or (nativeFishing == nil and cast and cast.kind == "Fishing" and cast.expires > now())
    -- A fishing state is only a fallback when the client has no native signal.
    -- Looting a creature after casting a line cannot be counted as a catch.
    if fishing and nativeFishing == nil and GetLootSourceInfo then
        for slot = 1, slots do
            local sources = { GetLootSourceInfo(slot) }
            for i = 1, #sources, 2 do
                if readable(sources[i]) and type(sources[i]) == "string"
                    and (sources[i]:match("^Creature%-") or sources[i]:match("^Vehicle%-")) then fishing = false end
            end
        end
    end
    if fishing and not lootCounted then
        lootCounted = true
        local pool = cast and cast.pool
        apply("FISHING", function(v) return not v.requiresPool or pool == true end)
        cast = nil
        return
    end
    if cast and cast.expires > now() and cast.kind ~= "Fishing" then
        local character, objects = record(), {}
        for slot = 1, slots do
            local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
            for i = 1, #sources, 2 do
                local guid = sources[i]
                if readable(guid) and type(guid) == "string" and guid:match("^GameObject%-") then
                    local key = "node:" .. guid
                    local expires = character and character.stageLootGUIDs[key]
                    if number(expires) and expires > serverTime() then return end
                    objects[key] = true
                end
            end
        end
        if not lootCounted then
            local changed = apply("SPECIAL", function(v)
                return v.nodes and nodeMatches(v.nodes, cast.node) and lootMatches(v)
            end)
            -- Required loot/currency may arrive only with LOOT_OPENED.
            -- Seal this window only after an eligible attempt was recorded.
            if changed then lootCounted = true end
        end
        -- A node already counted by name can gain its GUID in LOOT_OPENED.
        if lootCounted and character then
            for key in pairs(objects) do character.stageLootGUIDs[key] = serverTime() + 86400 end
        end
        return -- Skinning/mining/opening is not another NPC or zone kill.
    end
    local character = record()
    if not character then return end
    local time = serverTime()
    if time - lastLootPrune >= 60 then
        for guid, expires in pairs(character.stageLootGUIDs) do
            if not number(expires) or expires <= time then character.stageLootGUIDs[guid] = nil end
        end
        lastLootPrune = time
    end
    local seenGUIDs = {}
    for slot = 1, slots do
        local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
        for i = 1, #sources, 2 do
            local guid = sources[i]
            if readable(guid) and type(guid) == "string" and not seenGUIDs[guid] and not character.stageLootGUIDs[guid] then
                seenGUIDs[guid] = true
                local unitType, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
                if unitType == "Creature" or unitType == "Vehicle" then
                    local target = safe(UnitGUID, "target")
                    local minor = target == guid and safe(UnitClassification, "target") == "minus"
                    if not minor then
                        npc = tonumber(npc)
                        local changed = apply("NPC", function(v) return contains(v.npcs, npc) end, nil, npc)
                        local zoneChanged = apply("ZONE", function() return true end)
                        if changed or zoneChanged then character.stageLootGUIDs[guid] = time + 86400 end
                    end
                end
            end
        end
    end
end

local function onEncounter(encounter, difficulty)
    if not number(encounter) or not number(difficulty) then return end
    local key = "encounter:" .. encounter .. ":" .. difficulty
    if (recentEvents[key] or 0) > now() then return end
    recentEvents[key] = now() + 30
    apply("ENCOUNTER", function(v)
        return contains(v.encounters, encounter) and (not v.difficulties or contains(v.difficulties, difficulty))
    end)
end

local function scanArchaeology(countAttempts)
    local races = {}
    for _, entry in pairs(stages) do
        if entry.definition.method == "ARCH" then races[entry.definition.raceId] = true end
    end
    for race in pairs(races) do
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
    for key, entry in pairs(stages) do
        local definition = entry.definition
        if definition.event == "MAP_VISIT" then
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
                    if increment(entry, exitDefinition) and atlas.refreshDetails then atlas.refreshDetails() end
                end
            end
        end
    end
end

local function onGossip()
    local text = C_GossipInfo and safe(C_GossipInfo.GetText)
    local guid = safe(UnitGUID, "npc")
    local npc = type(guid) == "string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    for key, entry in pairs(stages) do
        local definition = entry.definition
        if definition.event == "GOSSIP" then
            local phrase = definition.gossipText
            local translated = atlas.attemptNodeNames and atlas.attemptNodeNames[phrase]
            local matched = contains(definition.gossipNPCs, npc) or (type(text) == "string" and type(phrase) == "string"
                and (text:find(phrase, 1, true) or (translated and text:find(translated, 1, true))))
            if matched and gossipOpen[key] then
                if increment(entry, definition) and atlas.refreshDetails then atlas.refreshDetails() end
            end
            gossipOpen[key] = matched and true or nil
        end
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

local function onCast(unit, guid, spell, finished)
    if unit ~= "player" or not readable(spell) or not number(spell) then return end
    if finished and itemSpells[spell] then markUse(itemSpells[spell]) end
    local kind = atlas.attemptSpells and atlas.attemptSpells[spell]
    if not kind and (spell == 131474 or spell == 7620 or spell == 158743) then kind = "Fishing" end
    if kind then
        nodeName()
        local node = lastNode and now() - lastNode.time <= 5 and lastNode.name
        cast = { kind = kind, expires = now() + (kind == "Fishing" and 35 or 8), node = node,
            pool = isPool(node) }
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
    pendingMessages, pendingUses, visits, gossipOpen = {}, {}, {}, {}
    pendingAcquisitions = {}
    cast, lastNode, itemLootUntil = nil, nil, 0
    for item in pairs(bags) do bags[item] = itemCount(item) or false end
    scanArchaeology(false)
end

function atlas.initializeAttemptStages()
    local characters = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.characters
    for _, character in pairs(type(characters) == "table" and characters or {}) do
        atlas.preserveStageDailyLocks(character)
    end
    buildStages()
    scanArchaeology(false)
    if hooksecurefunc then
        if C_Container and C_Container.UseContainerItem then
            hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
                markUse(safe(C_Container.GetContainerItemID, bag, slot))
            end)
        end
        if UseItemByName then
            hooksecurefunc("UseItemByName", function(item)
                local id = tonumber(item) or (C_Item and safe(C_Item.GetItemInfoInstant, item))
                markUse(id)
            end)
        end
    end
    for _, name in ipairs({ "LOOT_READY", "LOOT_OPENED", "LOOT_CLOSED", "BAG_UPDATE_DELAYED",
        "CURSOR_CHANGED",
        "PLAYER_ENTERING_WORLD", "RESEARCH_ARTIFACT_COMPLETE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
        "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "QUEST_TURNED_IN",
        "ENCOUNTER_END", "BOSS_KILL", "GOSSIP_SHOW", "GOSSIP_CLOSED", "ZONE_CHANGED_NEW_AREA", "UPDATE_MOUSEOVER_UNIT",
        "ITEM_DATA_LOAD_RESULT", "SHOW_LOOT_TOAST", "CHAT_MSG_LOOT" }) do
        events:RegisterEvent(name)
    end
    for _, name in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        events:RegisterUnitEvent(name, "player")
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        buildStages()
        scanArchaeology(false)
        cast, pendingUses, interactions, lootCounted = nil, {}, {}, false
        onZone(not enteredWorld)
        enteredWorld = true
    elseif event == "LOOT_READY" then onLoot()
    elseif event == "LOOT_OPENED" then
        local _, fromItem = ...
        if readable(fromItem) and fromItem then itemLootUntil = now() + 3 end
        onLoot()
    elseif event == "LOOT_CLOSED" then
        scanBags()
        finalizePendingAcquisitions(false)
        lootCounted, cast, lastNode = false, nil, nil
    elseif event == "BAG_UPDATE_DELAYED" then
        scanBags()
        finalizePendingAcquisitions(true)
    elseif event == "CHAT_MSG_LOOT" then onItemReceived((...), select(11, ...))
    elseif event == "SHOW_LOOT_TOAST" then
        local kind, link = ...
        if readable(kind) and kind == "item" and readable(link) and type(link) == "string" then
            local item = tonumber(link:match("item:(%d+)"))
            if item then apply("LOOT_TOAST", function(v) return contains(v.toastItems, item) end) end
        end
    elseif event == "CURSOR_CHANGED" then nodeName()
    elseif event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START" then onCast(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, guid, spell = ...; onCast(unit, guid, spell, true)
    elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        if ... == "player" then cast = nil end
    elseif event == "TRADE_SKILL_SHOW" then interactions.tradeSkill = true; scanArchaeology(false)
    elseif event == "TRADE_SKILL_CLOSE" then scanBags(); interactions.tradeSkill = nil
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local kind = ...; if readable(kind) then interactions[kind] = true end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        scanBags(); local kind = ...; if readable(kind) then interactions[kind] = nil end
    elseif event == "RESEARCH_ARTIFACT_COMPLETE" then
        local generation = sessionGeneration
        if C_Timer then
            for _, delay in ipairs({ .2, 1 }) do
                C_Timer.After(delay, function()
                    if generation == sessionGeneration then scanArchaeology(true) end
                end)
            end
        end
    elseif event == "QUEST_TURNED_IN" then
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
        for key, message in pairs(pendingMessages) do
            if message.expires <= now() then pendingMessages[key] = nil
            elseif readable(item) and message.entry.definition.item == item and readable(success) and success then
                pendingMessages[key] = nil
                notifyStage(message.entry, message.count, message.cumulative)
            end
        end
    end
end)
