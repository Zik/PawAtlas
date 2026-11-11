local addonName, atlas = ...
local L = atlas.L

function atlas.gameTooltipsEnabled()
    local db = MountAtlasAccountDB
    local settings = type(db) == "table" and db.settings
    return type(settings) == "table" and settings.gameTooltips == true
end

local processor = TooltipDataProcessor
local types = Enum and Enum.TooltipDataType
if not processor or not processor.AddTooltipPostCall or not types then return end

local maxMounts = 3
local appended = {}

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function buildIndexes()
    local itemLinks, npcLinks = {}, {}
    local function link(index, sourceID, mountID)
        if type(sourceID) ~= "number" or sourceID <= 0 then return end
        local ids = index[sourceID] or {}
        ids[mountID] = true
        index[sourceID] = ids
    end
    local function addEntry(mountID, entry)
        link(itemLinks, entry.item, mountID)
        for _, itemID in ipairs(entry.items or {}) do link(itemLinks, itemID, mountID) end
        for _, npcID in ipairs(entry.npcs or {}) do link(npcLinks, npcID, mountID) end
        for _, variant in ipairs(entry.variants or {}) do addEntry(mountID, variant) end
    end
    for npcID, mounts in pairs(atlas.lootByNPC or {}) do
        for _, mount in ipairs(mounts) do link(npcLinks, npcID, mount.id) end
    end
    for mountID, item in pairs(atlas.lootItems or {}) do addEntry(mountID, item) end
    for mountID, rewards in pairs(atlas.mountRewardItems or {}) do
        for _, reward in ipairs(rewards) do addEntry(mountID, reward) end
    end
    for mountID, stages in pairs(atlas.attemptStages or {}) do
        for _, stage in pairs(stages) do addEntry(mountID, stage) end
    end
    -- Some legacy loot entries retain past sources for the catalog history.
    for mountID, route in pairs(atlas.historicalRewardRoutes or {}) do
        for _, npcID in ipairs(route.npcs or {}) do
            local mounts = npcLinks[npcID]
            if mounts then mounts[mountID] = nil end
        end
    end
    for mountID in pairs(atlas.rewardDropRoutes or {}) do
        local route = atlas.verifiedRewardDropRoute({ id = mountID })
        if route then link(npcLinks, route.npc, mountID) end
    end
    for mountID in pairs(atlas.raidLootRewards or {}) do
        local reward = atlas.raidLootReward({ id = mountID })
        if reward then link(npcLinks, reward.npc, mountID) end
    end
    local function sortedIndex(links)
        local index = {}
        for sourceID, mounts in pairs(links) do
            local ids = {}
            for mountID in pairs(mounts) do ids[#ids + 1] = mountID end
            table.sort(ids)
            index[sourceID] = ids
        end
        return index
    end
    return sortedIndex(itemLinks), sortedIndex(npcLinks)
end

-- Source links are static. The live journal supplies names and collection state.
local byItem, byNPC = buildIndexes()

local function canAppend(tooltip, data)
    if not atlas.gameTooltipsEnabled() or appended[tooltip] then return false end
    if not readable(data) or type(data) ~= "table" or (canaccesstable and not canaccesstable(data)) then
        return false
    end
    if not tooltip.AddLine or not tooltip.GetPrimaryTooltipData or (tooltip.IsForbidden and tooltip:IsForbidden()) then
        return false
    end
    -- Appended tooltip data can describe a different item from the main tooltip.
    local primary = tooltip:GetPrimaryTooltipData()
    if not readable(primary) or primary ~= data then return false end
    local window = _G.MountAtlasWindow
    local owner = tooltip.GetOwner and tooltip:GetOwner()
    while readable(owner) and owner do
        if owner == window then return false end
        owner = owner.GetParent and owner:GetParent()
    end
    return readable(owner)
end

local function appendMounts(tooltip, ids, directID)
    local getMount = C_MountJournal and C_MountJournal.GetMountInfoByID
    if not (ids or directID) or not getMount then return end
    local count = 0
    local function appendMount(id)
        local name, spell, _, _, _, _, _, _, _, _, collected = getMount(id)
        if not readable(name) or type(name) ~= "string" or name == "" or not readable(spell) then return end
        if not readable(collected) then collected = nil end
        if atlas.isExcludedJournalMount(id, name, spell, collected) then return end
        count = count + 1
        if count > maxMounts then return end
        if count == 1 then
            appended[tooltip] = true
            tooltip:AddLine(addonName, 0.88, 0.72, 0.42)
        end
        local status
        if collected == true then status = L("В коллекции")
        elseif atlas.isPlanned({ id = id }, atlas.activePlanID()) then status = L("В плане") end
        local label = atlas.displayName(name)
        if status then label = label .. " · " .. status end
        tooltip:AddLine(label, 1, 1, 1, true)
    end
    if directID then appendMount(directID) end
    if ids then
        for _, id in ipairs(ids) do if id ~= directID then appendMount(id) end end
    end
    if count > maxMounts then tooltip:AddLine(("+%d"):format(count - maxMounts), 0.75, 0.75, 0.75) end
end

local function onItem(tooltip, data)
    if not readable(tooltip) or not tooltip or (tooltip ~= _G.GameTooltip and tooltip ~= _G.ItemRefTooltip) then return end
    if not canAppend(tooltip, data) then return end
    local id = data.id
    if not readable(id) or type(id) ~= "number" or not (id > 0) then return end
    local getDirectMount = C_MountJournal and C_MountJournal.GetMountFromItem
    local directID = getDirectMount and getDirectMount(id)
    if not readable(directID) or type(directID) ~= "number" or not (directID > 0) then directID = nil end
    appendMounts(tooltip, byItem[id], directID)
end

local function onUnit(tooltip, data)
    if not readable(tooltip) or not tooltip or tooltip ~= _G.GameTooltip or not canAppend(tooltip, data) then return end
    local guid = data.guid
    if not readable(guid) or type(guid) ~= "string" then return end
    local unitType, npc = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return end
    appendMounts(tooltip, byNPC[tonumber(npc)])
end

local function reset(tooltip)
    appended[tooltip] = nil
end

local function watchClears(tooltip)
    if not tooltip or not tooltip.HookScript then return end
    tooltip:HookScript("OnTooltipCleared", reset)
    tooltip:HookScript("OnHide", reset)
end

watchClears(_G.GameTooltip)
watchClears(_G.ItemRefTooltip)
if types.Item then processor.AddTooltipPostCall(types.Item, onItem) end
if types.Unit then processor.AddTooltipPostCall(types.Unit, onUnit) end
