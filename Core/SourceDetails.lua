local _, atlas = ...
local achievementNames, achievementScan, achievementReady = {}, false, false
local achievementRewards, achievementIcons = {}, {}
local achievementAttempts, achievementRescan = 0, false
local achievementAliases, achievementRetryPending = {}, false
local achievementSourcesByRoute = {}
local factionNames, factionScan, factionIndexed = {}, false, false
local majorFactionNames = {}
local quietFactionUntil = 0
local refreshQueued, mountQualitiesQueued = false, false
local questLoads, sourceItemLoads = {}, {}
local mountQualityItems = {}

local function respawnText(window)
    if not window then return end
    local low, high = window.min or window.max, window.max or window.min
    local unit = "%s мин"
    if low % 60 == 0 and high % 60 == 0 then
        low, high, unit = low / 60, high / 60, "%s ч"
    elseif low % 1 ~= 0 or high % 1 ~= 0 then
        low, high, unit = low * 60, high * 60, "%s с"
    end
    local duration = low == high and tostring(low) or string.format("%d–%d", low, high)
    local text = atlas.L(unit, duration)
    if not window.min then text = atlas.L("до %s", text)
    elseif not window.max then text = atlas.L("от %s", text) end
    return text, window.condition and atlas.L(window.condition)
end

function atlas.npcRespawnText(npcID)
    return respawnText(atlas.npcRespawns and atlas.npcRespawns[npcID])
end

function atlas.sourceRespawnText(mount, view, point)
    if not view then return end
    local npc = atlas.sourceCreatureID(mount, view, point)
    if npc then return atlas.npcRespawnText(npc) end
    local requirement = view.sourceRequirements
    if requirement and (not point or requirement.name and requirement.name ~= "" and point.boss == requirement.name
        or requirement.englishName and requirement.englishName ~= "" and point.englishBoss == requirement.englishName) then
        return respawnText(requirement.respawn)
    end
    local journal = atlas.journalRespawnSource(mount, view, point)
    if journal then
        if journal.npc then return atlas.npcRespawnText(journal.npc) end
        return respawnText(journal.respawn)
    end
end

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end
local function number(value)
    return readable(value) and type(value) == "number" and value >= 0 and value < math.huge
end
local function plain(text)
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", ""))
end
local function key(text)
    text = plain(text):gsub("\194\160", " "):gsub("\226\128\175", " "):match("^%s*(.-)%s*$")
    while true do
        local unquoted = text:match('^"(.-)"$') or text:match("^«(.-)»$")
            or text:match("^“(.-)”$") or text:match("^„(.-)”$") or text:match("^'(.-)'$") or text:match("^‘(.-)’$")
        if not unquoted then break end
        text = unquoted:match("^%s*(.-)%s*$")
    end
    text = text:gsub("%s+", " ")
    return atlas.searchKey(text)
end
local achievementPunctuation = { "«", "»", "“", "”", "„", "—", "–", "‑", "…" }
local function achievementAlias(text)
    for _, mark in ipairs(achievementPunctuation) do text = text:gsub(mark, " ") end
    return text:gsub("%p", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
end
local function achievementKey(text)
    return achievementAlias(key(text))
end
local function notify()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0, function()
        refreshQueued = false
        if atlas.refreshSourceDetails then atlas.refreshSourceDetails() end
        if mountQualitiesQueued then
            mountQualitiesQueued = false
            if atlas.refreshMountQualities then atlas.refreshMountQualities() end
        end
    end)
end

function atlas.sourceQuestLink(id)
    if not number(id) or id <= 0 then return end
    local link = GetQuestLink and GetQuestLink(id)
    if type(link) == "string" and link:find("|Hquest:" .. id .. ":", 1, true) then
        questLoads[id] = nil
        return link
    end
    if not questLoads[id] and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
        questLoads[id] = "pending"
        C_QuestLog.RequestLoadQuestByID(id)
    end
end

function atlas.sourceQuestReference(id, fallback)
    if not number(id) or id <= 0 or id % 1 ~= 0 then return end
    local link = atlas.sourceQuestLink(id)
    if link then return link end
    local journal = C_QuestLog
    local title = journal and journal.GetTitleForQuestID and journal.GetTitleForQuestID(id)
    if not readable(title) or title == "" then title = nil end
    local label = fallback or title
    if type(label) == "string" and label ~= "" and not label:find("[|\r\n]") then
        local level = title and journal.GetQuestDifficultyLevel and journal.GetQuestDifficultyLevel(id)
        return ("|cffffff00|Hquest:%d:%d|h[%s]|h|r"):format(id, number(level) and level or 0, label)
    end
end

local function itemNameInLocale(name, english, russian)
    if not readable(name) or type(name) ~= "string" or name == "" then return end
    local label = name:match("^%s*%[(.-)%]%s*$") or name
    if atlas.getLocale() == "ruRU" and label:find("%a") and not label:find("[\128-\255]") then
        local englishLabel = english and (english:match("^%s*%[(.-)%]%s*$") or english)
        if label ~= name or label == englishLabel or russian and russian:find("[\208\209]") then return end
    end
    return label
end

function atlas.itemDisplayName(record, nativeName)
    local english = atlas.getLocale() ~= "ruRU"
    local fallback = english and record.englishName or record.name
    local native = itemNameInLocale(nativeName, record.englishName, record.name)
    return native or itemNameInLocale(fallback, record.englishName), native ~= nil
end

function atlas.itemReferenceName(id)
    return (ITEM or (atlas.getLocale() == "ruRU" and "Предмет" or "Item")) .. " #" .. id
end

local function requestSourceItem(id)
    if not sourceItemLoads[id] and C_Item and C_Item.RequestLoadItemDataByID then
        sourceItemLoads[id] = "pending"
        C_Item.RequestLoadItemDataByID(id)
    end
end

local qualityRGB = {
    [0] = { 157, 157, 157 }, { 255, 255, 255 }, { 30, 255, 0 }, { 0, 112, 221 },
    { 163, 53, 238 }, { 255, 128, 0 }, { 230, 204, 128 }, { 0, 204, 255 }, { 0, 204, 255 },
}

function atlas.qualityColor(quality)
    if not number(quality) or not qualityRGB[quality] then return end
    local color = ColorManager and ColorManager.GetColorDataForItemQuality
        and ColorManager.GetColorDataForItemQuality(quality)
    if color and color.color then return color.color:GetRGB() end
    if C_Item and C_Item.GetItemQualityColor then
        local r, g, b = C_Item.GetItemQualityColor(quality)
        if number(r) and number(g) and number(b) then return r, g, b end
    end
    local fallback = qualityRGB[quality]
    return fallback[1] / 255, fallback[2] / 255, fallback[3] / 255
end

local function qualityPrefix(quality)
    local r, g, b = atlas.qualityColor(quality)
    if r then return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + .5), math.floor(g * 255 + .5), math.floor(b * 255 + .5)) end
end

function atlas.qualityText(text, quality)
    local prefix = qualityPrefix(quality)
    return prefix and prefix .. text .. "|r" or text
end

function atlas.sourceItemInfo(id)
    if not number(id) or id <= 0 or id % 1 ~= 0 then return end
    local name, link, quality
    if C_Item and C_Item.GetItemInfo then name, link, quality = C_Item.GetItemInfo(id) end
    if not number(quality) and C_Item and C_Item.GetItemQualityByID then quality = C_Item.GetItemQualityByID(id) end
    if not readable(name) or type(name) ~= "string" or name == "" or not number(quality) then requestSourceItem(id) end
    return name, link, number(quality) and quality or nil
end

function atlas.mountDisplayQuality(id)
    local quality = atlas.mountQuality and atlas.mountQuality[id]
    if quality ~= nil then return quality end
    local records = atlas.mountRewardItems and atlas.mountRewardItems[id]
    if not records then return end
    local item
    for _, record in ipairs(records) do
        if item and item ~= record.item then return end
        item = record.item
    end
    if item then
        quality = select(3, atlas.sourceItemInfo(item))
        if not quality and sourceItemLoads[item] == "pending" then mountQualityItems[item] = true end
        return quality
    end
end

function atlas.sourceItemReference(id, fallback)
    if not number(id) or id <= 0 or id % 1 ~= 0 then return fallback end
    local name, link
    if C_Item and C_Item.GetItemInfo then name, link = C_Item.GetItemInfo(id) end
    local native = itemNameInLocale(name, nil, fallback)
    local label = native or itemNameInLocale(fallback) or atlas.itemReferenceName(id)
    if readable(link) and type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) == id then
        return native and link or (link:gsub("|h.-|h", function() return "|h[" .. label .. "]|h" end, 1))
    end
    -- Keep the exact link usable while the client loads its name/quality.
    requestSourceItem(id)
    return "|Hitem:" .. id .. "|h[" .. label .. "]|h"
end

function atlas.sourceItemLinks(text)
    return (text:gsub("{[iI][tT][eE][mM]:(%d+):([^{}]+)}", function(id, fallback)
        return atlas.sourceItemReference(tonumber(id), fallback)
    end))
end

-- Decorate only rendered captions; the underlying item links stay suitable for chat.
function atlas.cardItemIcons(text)
    if not text:find("|Hitem:", 1, true) then return text end
    local parts, cursor = {}, 1
    while true do
        local first, last, link, rawID, caption = text:find("(|Hitem:(%d+)[^|]*|h)(.-)|h", cursor)
        if not first then break end
        local before, after = text:sub(cursor, first - 1), "|h"
        local id = tonumber(rawID)
        local label = plain(caption):gsub("|cn[%w_]+:", ""):gsub("^%s*%[%s*%]%s*$", "")
        if number(id) and id > 0 and label:find("%S") then
            local current = before:match("(|c%x%x%x%x%x%x%x%x)$") or before:match("(|cn[%w_]+:)$")
            local prefix = qualityPrefix(select(3, atlas.sourceItemInfo(id)))
            if prefix and (not current or text:sub(last + 1, last + 2) == "|r") then
                if current then
                    before, last = before:sub(1, -#current - 1), last + 2
                end
                link, after = prefix .. link, after .. "|r"
            end
            local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
            if (number(icon) and icon > 0) or (readable(icon) and type(icon) == "string" and icon ~= "") then
                local adjacent = before:gsub("|c%x%x%x%x%x%x%x%x$", ""):gsub("|cn[%w_]+:$", "")
                local texture = adjacent:match("|T([^:|]+)[^|]*|t%s*$")
                if not caption:find("|[TA]") and texture ~= tostring(icon) then
                    caption = "|T" .. icon .. ":16:16|t " .. caption
                end
            else
                requestSourceItem(id)
            end
        end
        parts[#parts + 1] = before .. link .. caption .. after
        cursor = last + 1
    end
    parts[#parts + 1] = text:sub(cursor)
    return table.concat(parts)
end

local function liveCraftSlots(recipeID, itemID)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then return end
    local recipe = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not recipe or recipe.outputItemID ~= itemID then return end
    local slots = {}
    for _, slot in ipairs(recipe.reagentSlotSchematics or {}) do
        if slot.required and not slot.hiddenInCraftingForm then
            if not number(slot.quantityRequired) or slot.quantityRequired <= 0 then return end
            local choices = { slot.quantityRequired }
            for _, reagent in ipairs(slot.reagents or {}) do
                if not number(reagent.itemID) or reagent.itemID <= 0 then return end
                choices[#choices + 1] = reagent.itemID
            end
            if #choices == 1 then return end
            slots[#slots + 1] = choices
        end
    end
    if #slots > 0 then return slots end
end

function atlas.mountCraftReagentText(itemID)
    local recipeID = atlas.mountCraftRecipes[itemID]
    if not recipeID then return end
    local protoform = atlas.protoformMountRecipes[itemID]
    local fallback = protoform and protoform.slots or atlas.mountCraftFallbackSlots and atlas.mountCraftFallbackSlots[itemID]
    local slots = liveCraftSlots(recipeID, itemID)
    if fallback and (not slots or #slots < #fallback) then slots = fallback end
    if not slots then return end

    local lines = {}
    for _, slot in ipairs(slots) do
        local choices = {}
        for i = 2, #slot do
            local id = slot[i]
            local item = atlas.protoformReagentNames[id] or atlas.craftReagentInfo and atlas.craftReagentInfo[id]
            local name = item and atlas.itemDisplayName(item) or atlas.itemReferenceName(id)
            local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
            if not (readable(icon) and (type(icon) == "string" and icon ~= "" or number(icon) and icon > 0)) then
                icon = "Interface\\Icons\\" .. (item and item.icon or "INV_Misc_QuestionMark")
            end
            local link = atlas.sourceItemLinks(("{item:%d:%s}"):format(id, name))
            choices[#choices + 1] = link:gsub("|h.-|h", ("|h|T%s:0:0|t|h"):format(icon), 1)
        end
        lines[#lines + 1] = slot[1] .. " " .. table.concat(choices, "/")
    end
    return atlas.L("Реагенты") .. ": " .. table.concat(lines, " + ")
end

local inlineQuestPattern = "{quest:(%d+):([^{}]+)}"
local inlineMissionPattern = "{mission:(%d+):([^{}]+)}"
local inlineJournalPattern = "{journal:(%d+):([^{}]+)}"
function atlas.sourceInlineLinks(text)
    text = atlas.sourceItemLinks(text)
    text = text:gsub(inlineQuestPattern, function(rawID, fallback)
        return atlas.sourceQuestReference(tonumber(rawID), fallback) or fallback
    end)
    text = text:gsub(inlineJournalPattern, function(rawID, fallback)
        return atlas.sourceJournalInstanceLink and atlas.sourceJournalInstanceLink(rawID, fallback) or fallback
    end)
    return (text:gsub(inlineMissionPattern, function(rawID, name)
        local id = tonumber(rawID)
        if id <= 0 or id == math.huge or name:find("[|\r\n]") then return name end
        return ("|cffffff00|Hpawatlasmission:%d|h[%s]|h|r"):format(id, name)
    end))
end
local function rememberKey(names, normalized, id)
    if names[normalized] == nil then names[normalized] = id
    elseif names[normalized] ~= id then names[normalized] = false end
end
local function remember(names, name, id)
    if type(name) == "string" and number(id) and id > 0 then rememberKey(names, key(name), id) end
end

-- Names in the mount journal can lag behind achievement renames. A reward item
-- mapped back to this mount is stronger evidence than a localized name match.
-- Ambiguous names/rewards stay unresolved; the scan never guesses an ID.
local function indexAchievements()
    if achievementScan or achievementReady or achievementRetryPending or achievementAttempts >= 3 or not GetCategoryList
        or not GetCategoryNumAchievements or not GetAchievementInfo then return end
    achievementAttempts = achievementAttempts + 1
    achievementScan = true
    achievementNames, achievementAliases, achievementRewards, achievementIcons = {}, {}, {}, {}
    local categories, categorySeen = {}, {}
    local function addCategories(list)
        if type(list) ~= "table" then return end
        for _, category in ipairs(list) do
            if number(category) and not categorySeen[category] then
                categories[#categories + 1] = category
                categorySeen[category] = true
            end
        end
    end
    local initialized = false
    local categoryIndex, index, count = 1, 1
    local related, queued, seen, incomplete, recorded = {}, {}, {}, false, 0
    local function queueRelated(id)
        if not number(id) or id <= 0 or seen[id] or queued[id] then return end
        related[#related + 1] = id
        queued[id] = true
    end
    local function record(id, name, icon, statistic)
        if not number(id) or not readable(name) or type(name) ~= "string" or name == "" then incomplete = true; return end
        if seen[id] then return end
        seen[id] = true
        if id <= 0 or (readable(statistic) and statistic == true) then return end
        recorded = recorded + 1
        local normalized = key(name)
        rememberKey(achievementNames, normalized, id)
        rememberKey(achievementAliases, achievementAlias(normalized), id)
        if readable(icon) then achievementIcons[id] = icon end
        if C_AchievementInfo and C_AchievementInfo.GetRewardItemID and C_MountJournal and C_MountJournal.GetMountFromItem then
            local itemID = C_AchievementInfo.GetRewardItemID(id)
            local mountID = number(itemID) and itemID > 0 and C_MountJournal.GetMountFromItem(itemID)
            if number(mountID) and mountID > 0 then
                if achievementRewards[mountID] == nil then achievementRewards[mountID] = id
                elseif achievementRewards[mountID] ~= id then achievementRewards[mountID] = false end
            end
        end
        if GetPreviousAchievement then queueRelated(GetPreviousAchievement(id)) end
        if GetNextAchievement then queueRelated(GetNextAchievement(id)) end
        if C_AchievementInfo and C_AchievementInfo.GetSupercedingAchievements then
            for _, replacement in ipairs(C_AchievementInfo.GetSupercedingAchievements(id) or {}) do
                queueRelated(replacement)
            end
        end
    end
    local function step()
        local remaining = 20
        local started = debugprofilestop and debugprofilestop()
        if not initialized then
            -- Requesting categories can initialize the native achievement
            -- cache. Begin discovery after the mount card has rendered.
            initialized = true
            addCategories(GetCategoryList())
            if GetGuildCategoryList then addCategories(GetGuildCategoryList()) end
            if started and debugprofilestop() - started >= 2 then C_Timer.After(0, step); return end
        end
        while (categoryIndex <= #categories or #related > 0) and remaining > 0 do
            if #related > 0 then
                local id = table.remove(related)
                if not seen[id] then
                    local actualID, name, _, _, _, _, _, _, _, icon, _, _, _, _, statistic = GetAchievementInfo(id)
                    if readable(actualID) and actualID == id then record(id, name, icon, statistic) else incomplete = true end
                end
            else
                local category = categories[categoryIndex]
                if count == nil then count = GetCategoryNumAchievements(category) end
                if not number(count) then incomplete = true end
                if not number(count) or index > count then
                    categoryIndex, index = categoryIndex + 1, 1
                    count = nil
                else
                    local id, name, _, _, _, _, _, _, _, icon, _, _, _, _, statistic = GetAchievementInfo(category, index)
                    record(id, name, icon, statistic)
                    index = index + 1
                end
            end
            remaining = remaining - 1
            -- Native queries can be expensive on the first visit. Yield by
            -- elapsed time as well as count, keeping input/hover responsive.
            if started and debugprofilestop() - started >= 2 then break end
        end
        if categoryIndex <= #categories or #related > 0 then C_Timer.After(0, step)
        else
            achievementScan, achievementReady = false, not achievementRescan and not incomplete and recorded > 0
            notify()
            if (achievementRescan or incomplete or recorded == 0) and achievementAttempts < 3 then
                achievementRetryPending = true
                C_Timer.After(2, function()
                    achievementRetryPending, achievementReady = false, false
                    indexAchievements()
                end)
            end
            achievementRescan = false
        end
    end
    C_Timer.After(0, step)
end

local function indexFactions()
    local api = C_Reputation
    local canReadReputations = api and api.GetNumFactions and api.GetFactionDataByIndex
    local major = C_MajorFactions
    if factionScan or not (canReadReputations or major and major.GetMajorFactionIDs and major.GetMajorFactionData) then return end
    factionScan = true
    local expanded = {}
    local oldLegacy = canReadReputations and api.AreLegacyReputationsShown and api.AreLegacyReputationsShown()
    local changedLegacy = oldLegacy == false and api.SetLegacyReputationsShown ~= nil
    -- Expand only while taking the snapshot, then restore the previous UI state,
    -- including after an API failure. No reputation window is opened.
    local ok = pcall(function()
        if changedLegacy then api.SetLegacyReputationsShown(true) end
        local i = 1
        while canReadReputations and i <= api.GetNumFactions() do
            local info = api.GetFactionDataByIndex(i)
            if info then
                remember(factionNames, info.name, info.factionID)
                if info.isHeader and info.isCollapsed and api.ExpandFactionHeader and api.CollapseFactionHeader then
                    expanded[#expanded + 1] = i
                    api.ExpandFactionHeader(i)
                end
            end
            i = i + 1
        end
        if major and major.GetMajorFactionIDs and major.GetMajorFactionData then
            for _, id in ipairs(major.GetMajorFactionIDs() or {}) do
                local info = major.GetMajorFactionData(id)
                if info and readable(info.name) then
                    remember(majorFactionNames, info.name, id)
                    remember(factionNames, info.name, id)
                end
            end
        end
    end)
    for i = #expanded, 1, -1 do pcall(api.CollapseFactionHeader, expanded[i]) end
    if changedLegacy then pcall(api.SetLegacyReputationsShown, oldLegacy) end
    factionScan = false
    factionIndexed = ok
    quietFactionUntil = GetTime() + .5
end

local function majorFactionData(id)
    return id and C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
end

local function renownLevel(id)
    local info = majorFactionData(id)
    if info and readable(info.isUnlocked) and info.isUnlocked == true and number(info.renownLevel)
        and info.renownLevel % 1 == 0 then
        return info.renownLevel
    end
end

function atlas.appendMajorRenown(source, requirement)
    for line in source:gmatch("[^\n]+") do
        local label = line:match("^%s*([^:]+):")
        if label == "Известность" or label == "Renown" then return source end
    end
    local faction = requirement.faction
    local info = majorFactionData(faction.id)
    local name = info and readable(info.name) and type(info.name) == "string" and info.name ~= "" and info.name
        or atlas.dataName(faction)
    local fields = ("%s: %s\n%s: %d"):format(atlas.L("Фракция"), name, atlas.L("Известность"), requirement.level)
    return source ~= "" and source .. "\n" .. fields or fields
end

local function reputation(id)
    local level = renownLevel(id)
    if level then return { label = atlas.L("Известность %d", level) } end
    local api, info = C_Reputation
    if api then
        if id == 1168 and api.GetGuildFactionData then info = api.GetGuildFactionData()
        elseif api.GetFactionDataByID then info = api.GetFactionDataByID(id) end
    end
    local name = info and readable(info.name) and type(info.name) == "string" and info.name ~= "" and info.name or nil
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendship = C_GossipInfo.GetFriendshipReputation(id)
        if friendship and number(friendship.friendshipFactionID) and friendship.friendshipFactionID > 0
            and readable(friendship.reaction) and type(friendship.reaction) == "string"
            and friendship.reaction ~= "" then
            local ranks = C_GossipInfo.GetFriendshipReputationRanks and C_GossipInfo.GetFriendshipReputationRanks(friendship.friendshipFactionID)
            name = name or readable(friendship.name) and type(friendship.name) == "string" and friendship.name ~= "" and friendship.name or nil
            return { label = friendship.reaction, rank = ranks and number(ranks.currentLevel) and ranks.currentLevel, name = name }
        end
    end
    if info and number(info.reaction) then
        local labels = { "Ненависть", "Враждебность", "Неприязнь", "Равнодушие", "Дружелюбие", "Уважение", "Почтение", "Превознесение" }
        return { label = labels[info.reaction] and atlas.L(labels[info.reaction]), standing = info.reaction, name = name }
    end
end

-- Match Blizzard's completed objective: native check and muted text, while
-- missing requirements remain readable. Unknown data is never a failed goal.
local complete = " |A:ui-questtracker-tracker-check:14:14:0:2|a"
local function objectiveLine(text, state)
    if state == nil then return text end
    local color = state and "999999" or "efe9da"
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return "|cff" .. color .. text .. "|r" .. (state and complete or "")
end
local standings = { "Ненависть", "Враждебность", "Неприязнь", "Равнодушие", "Дружелюбие", "Уважение", "Почтение", "Превознесение" }
local englishStandings = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }
local function reputationStatus(current, required)
    if not current or not current.label then return atlas.L("  (Текущая репутация: —)"), nil end
    local met
    if required then
        required = key(required)
        if current.standing then
            for i = 1, 8 do
                if required == key(_G["FACTION_STANDING_LABEL" .. i] or standings[i]) or required == key(standings[i])
                    or required == key(englishStandings[i]) then met = current.standing >= i; break end
            end
        else
            local rank = required:match("^ур%.?%s*(%d+)$") or required:match("^(%d+)%-й ранг$")
                or required:match("^rank%s+(%d+)$") or required:match("^tier%s+(%d+)$")
            if rank and number(current.rank) then met = current.rank >= tonumber(rank)
            elseif required == key(current.label) then met = true end
        end
    end
    return met and "" or atlas.L("  (Текущая репутация: %s)", current.label), met
end

local covenantFactionIDs = {}
for _, vendor in pairs(atlas.covenantVariantVendors or {}) do
    local faction = vendor.reputation
    if faction then
        covenantFactionIDs[key(faction.name)] = faction.id
        covenantFactionIDs[key(faction.englishName)] = faction.id
    end
end

local function factionRequirement(value)
    local text = plain(value):gsub("–", "-"):gsub("—", "-")
    -- Some faction names contain parentheses; prefer a full-name match first.
    local id = factionNames[key(text)]
    if id then return id end
    local name, required = text:match("^(.-)%s*%(([^()]*)%)%s*$")
    if not name then name, required = text:match("^(.-)%s+%-%s+(.+)$") end
    if name then
        local normalized = key(name)
        if normalized == "guild" or normalized == key("Гильдия") then return 1168, required end
        local covenantID = covenantFactionIDs[normalized]
        return covenantID or factionNames[normalized], required, covenantID
    end
end

local function renownRequirement(value)
    local text = plain(value):match("^%s*(.-)%s*$")
    if text:match("^%d+$") then return tonumber(text) end
    local name, rank = text:match("^(.+)%s+[Rr]ank%s+(%d+)$")
    if not name then name, rank = text:match("^(.+)%s+(%d+)%-го уровня$") end
    return tonumber(rank), name
end

local function decorateRenown(line, required, level)
    local text = level and atlas.L("  (Текущая известность: %d)", level) or atlas.L("  (Текущая известность: —)")
    return objectiveLine(line .. text, level and level >= required)
end

local function decoratePrice(value)
    value = atlas.sourceItemLinks(value)
    local money = GetMoney and GetMoney()
    local total, last, seen = 0, nil, {}
    local costs = {}
    -- Keep byte offsets for inserting the gold shortage in the original line.
    local function spaces(text) return string.rep(" ", #text) end
    local clean = value:gsub("|c%x%x%x%x%x%x%x%x", spaces):gsub("|cn[%w_]+:", spaces):gsub("|r", "  ")
    clean = clean:gsub("([%d ,%.  ]+)(|H(%a+):(%d+)[^|]*|h.-|h)", function(amount, link, kind, rawID)
        local id = tonumber(rawID)
        local digits = amount:gsub(" ", ""):gsub(" ", ""):gsub("[ ,.]", "")
        local required = tonumber(digits)
        if (kind ~= "item" and kind ~= "currency") or not number(required) or required <= 0 then return end
        local key = kind .. ":" .. rawID
        local cost = costs[key] or { kind = kind, id = id, required = 0 }
        cost.required = cost.required + required
        costs[key] = cost
        return spaces(amount .. link)
    end)
    clean = clean:gsub("|H.-|h.-|h", function(link) return string.rep("#", #link) end)
    for amount, texture, ending in clean:gmatch("([%d%s,%.  ]+)(|T.-|t)()") do
        local coin = texture:lower():match("ui%-(%a+)icon")
        local multiplier = ({ gold = 10000, silver = 100, copper = 1 })[coin]
        if multiplier then
            if seen[coin] then return value end -- Alternative prices are not one purchase.
            local digits = amount:gsub(" ", ""):gsub(" ", ""):gsub("[%s,%.]", "")
            local count = tonumber(digits)
            if not number(count) then return value end
            total, last, seen[coin] = total + count * multiplier, ending - 1, true
        end
    end
    if not last and not next(costs) then return value end
    local remainder = clean:gsub("([%d%s,%.  ]+)(|T.-|t)", function(amount, texture)
        if texture:lower():match("ui%-goldicon") or texture:lower():match("ui%-silvericon")
            or texture:lower():match("ui%-coppericon") then return "" end
        return amount .. texture
    end):gsub("[%s+,]", "")
    local goldKnown = number(money)
    local short = last and goldKnown and money < total
    local formatMoney = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString or GetMoneyString
    if short and formatMoney then
        value = value:sub(1, last) .. atlas.L("  (Не хватает: %s)", formatMoney(math.ceil(total - money))) .. value:sub(last + 1)
    end
    if short then return value, false end
    if remainder ~= "" or (last and not goldKnown) then return value end
    for _, cost in pairs(costs) do
        local held
        if cost.kind == "item" then
            held = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(cost.id)
        elseif C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
            local info = C_CurrencyInfo.GetCurrencyInfo(cost.id)
            held = info and info.quantity
        end
        if not number(held) or held < cost.required then return value end
    end
    return value, true
end

-- Blizzard's covenant sigils live at Interface\Icons\UI_Sigil_<textureKit>.
-- Prefer localized covenant data; the aliases also cover journal snapshots.
local covenantKits = {
    ["кирии"] = "Kyrian", ["kyrian"] = "Kyrian",
    ["вентиры"] = "Venthyr", ["venthyr"] = "Venthyr",
    ["ночной народец"] = "NightFae", ["night fae"] = "NightFae",
    ["некролорды"] = "Necrolord", ["necrolord"] = "Necrolord", ["necrolords"] = "Necrolord",
}
local validCovenantKits = { Kyrian = true, Venthyr = true, NightFae = true, Necrolord = true }
local covenantIDs = { Kyrian = 1, Venthyr = 2, NightFae = 3, Necrolord = 4 }
local covenantDefaults = {
    [1] = { kit = "Kyrian", name = "Кирии", english = "Kyrian" },
    [2] = { kit = "Venthyr", name = "Вентиры", english = "Venthyr" },
    [3] = { kit = "NightFae", name = "Ночной народец", english = "Night Fae" },
    [4] = { kit = "Necrolord", name = "Некролорды", english = "Necrolords" },
}

local function covenantData(id)
    local fallback = covenantDefaults[id]
    if not fallback then return end
    local data
    if C_Covenants and C_Covenants.GetCovenantData then
        local ok, value = pcall(C_Covenants.GetCovenantData, id)
        if ok and readable(value) and type(value) == "table" then data = value end
    end
    local name = atlas.L(fallback.name)
    local kit = data and readable(data.textureKit) and validCovenantKits[data.textureKit] and data.textureKit or fallback.kit
    return { id = id, name = name, texture = "Interface\\Icons\\UI_Sigil_" .. kit }
end

function atlas.covenantSourceID(name)
    return covenantIDs[covenantKits[key(name)]]
end

function atlas.covenantRenownSource(covenant, renown)
    local data = covenantDefaults[covenant]
    local source = ("%s: %s"):format(atlas.L("Ковенант"), atlas.L(data.name))
    if renown then source = source .. ("\n%s: %d"):format(atlas.L("Известность"), renown) end
    return source
end

local function covenantRenownLevel(covenant)
    local active = C_Covenants and C_Covenants.GetActiveCovenantID and C_Covenants.GetActiveCovenantID()
    if not number(active) or active ~= covenant then return end
    local level = C_CovenantSanctumUI and C_CovenantSanctumUI.GetRenownLevel and C_CovenantSanctumUI.GetRenownLevel()
    if number(level) and level > 0 and level % 1 == 0 then return level end
end

-- Only acquisition requirements are eligible: an explicit journal field or
-- a typed prerequisite in the source database. A zone/flavour mention is not
-- proof that the mount requires that covenant. Several entries are alternatives.
function atlas.covenantSourcePages(mount)
    local source = mount.journalSourceOverride or mount.journalSourceRaw or mount.journalSource
    if type(source) ~= "string" then return end
    source = source:gsub("|n", "\n"):gsub("\r\n", "\n")
    local pages, covenants = {}, {}
    for block in (source .. "\n\n"):gmatch("(.-)\n%s*\n") do
        block = block:match("^%s*(.-)%s*$")
        if block ~= "" then
            local covenant, count = nil, 0
            for line in (plain(block) .. "\n"):gmatch("(.-)\n") do
                local label, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
                if label == "Ковенант" or label == "Covenant" then covenant, count = key(value), count + 1 end
            end
            -- Never discard a shared preamble or a condition with unclear scope.
            if count ~= 1 or covenants[covenant] then return end
            covenants[covenant] = true
            pages[#pages + 1] = block
        end
    end
    if #pages > 1 then return pages end
end

function atlas.mountCovenantRequirements(mount)
    if type(mount) ~= "table" then return {} end
    local found, result = {}, {}
    local function add(id, source)
        if not number(id) or found[id] then return end
        local data = covenantData(id)
        if data then data.source = source; found[id] = data end
    end
    local source = mount.journalSourceOverride or mount.journalSourceRaw or mount.journalSource
    if type(source) ~= "string" and number(mount.id) and C_MountJournal and C_MountJournal.GetMountInfoExtraByID then
        local ok, _, _, value = pcall(C_MountJournal.GetMountInfoExtraByID, mount.id)
        if ok and readable(value) and type(value) == "string" then source = value end
    end
    source = readable(source) and type(source) == "string" and plain(source):gsub("|n", "\n"):gsub("\r", "\n") or ""
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
        if label == "Ковенант" or label == "Covenant" then
            local normalized = key(value)
            local id = covenantIDs[covenantKits[normalized]]
            if not id then
                for candidate = 1, 4 do
                    local data = covenantData(candidate)
                    if data and key(data.name) == normalized then id = candidate; break end
                end
            end
            if id then add(id, "journal") end
        end
    end
    if not next(found) then
        add(atlas.mountCovenantSources and atlas.mountCovenantSources[mount.id], "simplearmory")
        local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
        for _, role in ipairs({ "reward", "item" }) do
            local definition = definitions and definitions[role]
            for _, variant in ipairs(definition and (definition.variants or { definition }) or {}) do
                add(variant.requiredCovenantID, "rarity")
            end
        end
    end
    for id = 1, 4 do if found[id] then result[#result + 1] = found[id] end end
    return result
end

local function decorateCovenant(value)
    if value:find("|T", 1, true) or value:find("|A", 1, true) then return value end
    local name = key(value)
    local kit = covenantKits[name]
    if C_Covenants and C_Covenants.GetCovenantIDs and C_Covenants.GetCovenantData then
        for _, id in ipairs(C_Covenants.GetCovenantIDs() or {}) do
            local data = C_Covenants.GetCovenantData(id)
            if data and readable(data.name) and type(data.name) == "string" and key(data.name) == name
                and readable(data.textureKit) and validCovenantKits[data.textureKit] then
                kit = data.textureKit
                break
            end
        end
    end
    local localized = kit and covenantData(covenantIDs[kit])
    return kit and ("|TInterface\\Icons\\UI_Sigil_" .. kit .. ":16:16:0:0|t " .. (localized and localized.name or value)) or value
end

-- Capitalize only the first visible letter. WoW link payloads, textures and
-- color escapes remain byte-for-byte intact; source data keeps its original form.
local titleLetters = {}
do
    local lower = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
    local upper = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
    for i = 1, #lower, 2 do
        titleLetters[lower:sub(i, i + 1)] = upper:sub(i, i + 1)
        titleLetters[upper:sub(i, i + 1)] = upper:sub(i, i + 1)
    end
end
-- Curated names have paired translations from the same source IDs. Never
-- mutate raw source fields: parsers and saved route keys use those originals.
local englishSourceNames, englishTargetNames
function atlas.dataName(record)
    if type(record) ~= "table" then return nil end
    return atlas.getLocale() == "enUS" and record.englishName or record.name
end

function atlas.sourceName(value, locale, role)
    if type(value) ~= "string" then return value or "" end
    if (locale or atlas.getLocale()) ~= "enUS" then return value end
    if not englishSourceNames then
        englishSourceNames, englishTargetNames = {}, {}
        local function add(names, normalized, english)
            if names[normalized] == nil then names[normalized] = english
            elseif names[normalized] ~= english then names[normalized] = false end
        end
        for _, mount in ipairs(atlas.mounts or {}) do
            local english = (atlas.englishNames or {})[mount.id] or mount.english
            if mount.name and english then
                add(englishSourceNames, key(mount.name), english)
            end
        end
        for name, english in pairs(atlas.sourceEnglishNames or {}) do
            local normalized = key(name)
            add(englishTargetNames, normalized, english)
            add(englishSourceNames, normalized, english)
        end
    end
    -- Do not substitute a name through a hyperlink or texture; its payload and
    -- native label must stay intact for linking and tooltip handling.
    if value:find("|", 1, true) then return atlas.L(value) end
    local normalized = key(value)
    return role == "target" and englishTargetNames[normalized] or englishSourceNames[normalized] or atlas.L(value)
end

function atlas.displayName(value, role)
    local text, i = atlas.sourceName(value, nil, role), 1
    while i <= #text do
        local token = text:sub(i, i + 1)
        if token == "|H" or token == "|T" or token == "|A" then
            local close = text:find(token:lower(), i + 2, true)
            if not close then return text end
            i = close + 2
        elseif token == "|c" and text:sub(i + 2, i + 9):match("^%x%x%x%x%x%x%x%x$") then i = i + 10
        elseif token == "|r" or token == "|h" or token == "|t" or token == "|a" or token == "|n" or token == "||" then i = i + 2
        elseif titleLetters[token] then
            return text:sub(1, i - 1) .. titleLetters[token] .. text:sub(i + 2)
        elseif text:sub(i, i):match("%a") then
            return text:sub(1, i - 1) .. text:sub(i, i):upper() .. text:sub(i + 1)
        else i = i + 1 end
    end
    return text
end

function atlas.displayMountName(mount)
    if mount.journalName then return mount.journalName end
    local english = atlas.getLocale() == "enUS" and ((atlas.englishNames or {})[mount.id] or mount.english)
    return english or mount.name or ""
end

local sourceLabels = {
    Drop = "Источник", Source = "Источник", Vendor = "Торговец", Vendors = "Торговцы",
    Zone = "Зона", Zones = "Зоны", Location = "Место", Area = "Область", Cost = "Цена", Price = "Цена",
    Faction = "Фракция", Reputation = "Репутация", Renown = "Известность", Covenant = "Ковенант",
    Achievement = "Достижение", Category = "Категория", Quest = "Задание", ["World Quest"] = "Локальное задание",
    ["Garrison Mission"] = "Задание гарнизона", Profession = "Профессия", Skill = "Навык", Requires = "Требуется",
    Event = "Событие", Holiday = "Праздник", ["World Event"] = "Особое событие", ["Special Event"] = "Особое событие",
    Promotion = "Промоакция", ["In-Game Shop"] = "Магазин", ["Trading Post"] = "Торговая лавка",
    Legacy = "Старинное", ["Trading Card Game"] = "Коллекционная карточная игра", Difficulty = "Режим",
}
local function displaySourceLabel(value)
    return atlas.L(sourceLabels[value] or value)
end

local function priceIcon(link, kind, id, caption)
    -- Zero dimensions follow the font size of the price line.
    local texture, options = caption:match("^|T([^:|]+)([^|]*)|t$")
    if texture then
        local suffix = options:match("^:%d+:%d+(.*)$") or ""
        return link .. "|T" .. texture .. ":0:0" .. suffix .. "|t|h"
    end
    if kind ~= "currency" and kind ~= "item" then return link .. caption .. "|h" end
    if caption:find("|T", 1, true) or caption:find("|A", 1, true) then return link .. caption .. "|h" end
    id = tonumber(id)
    local icon
    if kind == "currency" then
        local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
        icon = info and info.iconFileID
    elseif C_Item and C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(id)
    end
    if (number(icon) and icon > 0) or (readable(icon) and type(icon) == "string" and icon ~= "") then
        caption = "|T" .. icon .. ":0:0|t"
    else
        caption = "|TInterface\\Icons\\INV_Misc_QuestionMark:0:0|t"
        if kind == "item" then requestSourceItem(id) end
    end
    return link .. caption .. "|h"
end

local coinValues = { gold = 10000, silver = 100, copper = 1 }
local function priceComponents(line)
    local parts, pos = {}, 1
    while true do
        local start, _, token = line:find("|([HT])", pos)
        if not start then break end
        parts[#parts + 1] = line:sub(pos, start - 1)
        local close = token == "H" and "|h" or "|t"
        local finish = line:find(close, start + 2, true)
        if finish and token == "H" then finish = line:find(close, finish + 2, true) end
        if not finish then pos = start; break end
        local markup = line:sub(start, finish + 1)
        if token == "H" then
            markup = markup:gsub("^(|H(%a+):(%d+)[^|]*|h)(.-)|h$", priceIcon)
        else
            local path = markup:match("^|T([^:|]+)")
            local coin = path and path:lower():gsub("/", "\\"):match("moneyframe\\ui%-(%a+)icon")
            if coinValues[coin] then
                markup = "|Hpawatlascoin:" .. coinValues[coin] .. "|h|T" .. path .. ":0:0|t|h"
            end
        end
        parts[#parts + 1] = markup
        pos = finish + 2
    end
    parts[#parts + 1] = line:sub(pos)
    return table.concat(parts)
end

local function groupPriceAmount(prefix, amount, token)
    local raw, gap = amount:gsub(" ", " "):gsub(" ", " "):match("^(.-)( *)$")
    local digits = raw:gsub("[ ,.]", "")
    if token == "|H" then gap = " " end
    if #digits < 4 then return prefix .. raw .. gap .. token end
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1 "):reverse():gsub("^ ", "")
    if raw ~= digits and raw:gsub("[,.]", " ") ~= grouped then return prefix .. amount .. token end
    local separator = atlas.getLocale() == "enUS" and "," or " "
    return prefix .. grouped:gsub(" ", separator) .. gap .. token
end

function atlas.displaySourceText(source)
    local lines = {}
    for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
        line = atlas.sourceInlineLinks(atlas.L(line))
        local priceLabel = line:match("^%s*([^:|{]+):") or line:match("^|c%x%x%x%x%x%x%x%x([^:|{]+):")
        if priceLabel == "Цена" or priceLabel == "Стоимость" or priceLabel == "Price" or priceLabel == "Cost" then
            line = priceComponents(line)
                :gsub("(|Hitem:[^|]*|h|T[^|]*|t|h)%s*(%d)", "%1 + %2")
                :gsub("(|Hcurrency:[^|]*|h|T[^|]*|t|h)%s*(%d)", "%1 + %2")
                :gsub("([%s:+%(])(%d[%d ,%.  ]*)(|[HTA])", groupPriceAmount)
        end
        local label, value = line:match("^%s*([^:|{]+):%s*(.+)$")
        lines[#lines + 1] = label and (displaySourceLabel(label) .. ": " .. atlas.displayName(value))
            or atlas.displayName(displaySourceLabel(line))
    end
    return table.concat(lines, "\n")
end

local function achievementTitle(value)
    value = value:match("^%s*(.-)%s*$")
    local unquoted = value:match('^"(.-)"$') or value:match("^«(.-)»$")
    while unquoted do
        value = unquoted:match("^%s*(.-)%s*$")
        unquoted = value:match('^"(.-)"$') or value:match("^«(.-)»$")
    end
    return atlas.getLocale() == "enUS" and ('"' .. value .. '"') or ("«" .. value .. "»")
end

function atlas.legacySourceDetails(mount)
    if type(mount) ~= "table" then return end
    local unique = atlas.uniqueMounts and atlas.uniqueMounts[mount.id]
    local detail = atlas.legacySources and atlas.legacySources[mount.id]
    if not unique and (type(detail) ~= "table" or not number(detail.spell)) then return end
    local spell = mount.spell
    if not number(spell) and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local _, journalSpell = C_MountJournal.GetMountInfoByID(mount.id)
        spell = journalSpell
    end
    -- A reused MountID must never inherit another spell's retired source.
    if not number(spell) then return end
    if unique and spell == unique.spell then return unique end
    if type(detail) == "table" and spell == detail.spell then return detail end
end

function atlas.achievementIsFeat(id)
    if not number(id) or not GetAchievementCategory then return false end
    local ok, category = pcall(GetAchievementCategory, id)
    local seen = {}
    while ok and number(category) and category > 0 and not seen[category] do
        -- Same personal/guild roots used by Blizzard AchievementUI.
        if category == 81 or category == 15093 then return true end
        seen[category] = true
        if not GetCategoryInfo then break end
        local name
        ok, name, category = pcall(GetCategoryInfo, category)
    end
    return false
end

local function achievementInfo(id)
    if not GetAchievementInfo then return end
    local actualID, name, _, completed, _, _, _, _, _, icon, _, _, _, _, statistic = GetAchievementInfo(id)
    if not readable(actualID) or actualID ~= id or (readable(statistic) and statistic == true) then return end
    if not readable(name) or type(name) ~= "string" or name == "" then name = nil end
    if not readable(icon) then icon = nil end
    return name, icon, readable(completed) and completed == true
end

function atlas.achievementProgress(id)
    if not number(id) or id == 0 or not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then return end
    if C_AchievementInfo and C_AchievementInfo.IsValidAchievement and not C_AchievementInfo.IsValidAchievement(id) then return end
    local total = GetAchievementNumCriteria(id)
    if not number(total) or total < 1 then return end
    if total == 1 then
        local _, _, done, quantity, required = GetAchievementCriteriaInfo(id, 1)
        if number(quantity) and number(required) and required > 1 then
            return math.min(quantity, required), required, true
        end
        return nil, nil, number(required) and required == 1 and readable(done) and type(done) == "boolean"
    end
    local completed = 0
    for index = 1, total do
        local _, _, done = GetAchievementCriteriaInfo(id, index)
        if not readable(done) or type(done) ~= "boolean" then return end
        if done then completed = completed + 1 end
    end
    return completed, total, true
end

local function indexedAchievement(title, rewardMount)
    if not achievementReady then return end
    local id = achievementNames[key(title)]
    if id == nil then id = achievementAliases[achievementKey(title)] end
    if id then return id end
    return achievementRewards[rewardMount] or nil
end

local function achievementReward(mountID, spell, id, candidate)
    local api, journal = C_AchievementInfo, C_MountJournal
    if not api or not api.GetRewardItemID or not journal or not journal.GetMountFromItem
        or api.IsValidAchievement and not api.IsValidAchievement(id) then return end
    local reward = api.GetRewardItemID(id)
    if not number(reward) or reward == 0 then return end
    local rewardMount = journal.GetMountFromItem(reward)
    if not number(rewardMount) or rewardMount == 0 then return end
    if rewardMount == mountID then return reward end
    if candidate and candidate.rewardVariants and journal.GetMountInfoByID then
        local target, alternate
        for _, variant in ipairs(candidate.rewardVariants) do
            if variant.mount == mountID and variant.spell == spell then target = true end
            if variant.item == reward and variant.mount == rewardMount then
                local _, rewardSpell = journal.GetMountInfoByID(rewardMount)
                alternate = readable(rewardSpell) and rewardSpell == variant.spell
            end
        end
        if target and alternate then return reward end
    end
end

local achievementFactions = { Alliance = "Alliance", Horde = "Horde", ["Альянс"] = "Alliance", ["Орда"] = "Horde" }
local function achievementLabel(label)
    return label == "Достижение" or label == "Achievement" or label == "Великий подвиг" or label == "Feats of Strength"
end

local function sourceAchievement(mount, title, singleSource, purchase, routeFaction)
    local source = atlas.achievementSources and atlas.achievementSources[mount.id]
    if not source then return end
    local journal = C_MountJournal
    local spell, faction = mount.spell, achievementFactions[routeFaction or mount.faction]
    if journal and journal.GetMountInfoByID and (not number(spell) or (not faction and #source.candidates > 1)) then
        local _, nativeSpell, _, _, _, _, _, restricted, nativeFaction = journal.GetMountInfoByID(mount.id)
        if not number(spell) then spell = nativeSpell end
        if not faction and readable(restricted) and restricted and number(nativeFaction) then
            faction = nativeFaction == 0 and "Horde" or nativeFaction == 1 and "Alliance" or nil
        end
    end
    if not number(spell) or spell ~= source.spell then return end
    local player = not faction and UnitFactionGroup and UnitFactionGroup("player")
    local playerFaction = readable(player) and achievementFactions[player]
    local sourceTitle = key(title)
    local context = table.concat({ atlas.getLocale(), spell, faction or "", playerFaction or "",
        purchase and "purchase" or "reward", sourceTitle }, "\001")
    local cached = achievementSourcesByRoute[mount.id]
    if cached and cached[context] then return cached[context], spell end
    local titleKey = achievementAlias(sourceTitle)
    local selected, candidateCount, bestRank, ambiguous = nil, 0, 0, false
    local combined = source.combined and not purchase and {}
    for _, candidate in ipairs(source.candidates) do
        if (not candidate.faction or not faction or candidate.faction == faction)
            and (candidate.vendorRequirement == true) == (purchase == true) then
            candidateCount = candidateCount + 1
            local matchesTitle = candidate.name and achievementKey(candidate.name) == titleKey
                or candidate.englishName and achievementKey(candidate.englishName) == titleKey
            if not matchesTitle then
                for _, caption in ipairs(candidate.journalTitles or {}) do
                    if achievementKey(caption) == titleKey then matchesTitle = true; break end
                end
            end
            if not matchesTitle then
                local name = achievementInfo(candidate.id)
                matchesTitle = name and achievementKey(name) == titleKey
            end
            if combined and matchesTitle then combined[#combined + 1] = candidate end
            local reward
            if not combined and not purchase and (#source.candidates > 1 or not matchesTitle and singleSource) then
                reward = achievementReward(mount.id, spell, candidate.id, candidate)
            end
            local rank = matchesTitle and (reward and 3 or 2) or reward and singleSource and 1
            if rank then
                local matchesPlayer = candidate.faction and candidate.faction == playerFaction
                rank = rank * 2 + (matchesPlayer and 1 or 0)
                if rank > bestRank then
                    bestRank, ambiguous, selected = rank, false, candidate
                elseif rank == bestRank and selected.id ~= candidate.id then
                    ambiguous = true
                end
            end
        end
    end
    if combined and #combined > 1 then return nil, nil, true, combined end
    if ambiguous then return nil, nil, true end
    -- Only retain an identity that cannot change when a competing reward finishes loading.
    if selected and candidateCount == 1 and bestRank >= 4 then
        cached = cached or {}
        achievementSourcesByRoute[mount.id], cached[context] = cached, selected
    end
    return selected, spell
end

local function achievementForSource(mount, title, singleSource, purchase, faction, catalogOnly)
    local explicitID = tonumber(title:match("|Hachievement:(%d+)"))
    if explicitID and explicitID > 0 then return explicitID end
    local candidate, spell, ambiguous, combined = sourceAchievement(mount, title, singleSource, purchase, faction)
    if candidate then return candidate.id, candidate, spell end
    if combined then return nil, nil, nil, combined end
    if ambiguous or purchase or catalogOnly then return end
    local id = indexedAchievement(title, singleSource and mount.id or nil)
    if not id then indexAchievements() end
    return id
end

local function decorateAchievement(id, title, purchase, label)
    local name, icon, completed
    if id then
        name, icon, completed = achievementInfo(id)
        icon = icon or achievementIcons[id]
        if name and not purchase and atlas.achievementIsFeat(id) then label = atlas.L("Великий подвиг") .. ": " end
    end
    local value = achievementTitle(name or plain(title))
    local shield = "|TInterface\\AchievementFrame\\UI-Achievement-Shields-NoPoints:18:18:0:0:128:128:0:64:0:64|t"
    local badge = icon and ("|T" .. icon .. ":16:16:0:0|t") or shield
    local line = label .. badge .. " |cffffd200" .. (id and ("|Hachievement:" .. id .. "|h" .. value .. "|h") or value) .. "|r"
    return completed and objectiveLine(line, true) or line
end

local function decorateAchievementSource(mount, title, label, singleSource, purchase, faction, catalogOnly)
    local id, _, _, combined = achievementForSource(mount, title, singleSource, purchase, faction, catalogOnly)
    if combined then
        local alternatives = {}
        for _, candidate in ipairs(combined) do
            local caption = atlas.getLocale() == "enUS" and candidate.englishName or candidate.name
            alternatives[#alternatives + 1] = decorateAchievement(candidate.id, caption, false, label)
        end
        return table.concat(alternatives, "\n")
    end
    if id or not catalogOnly then return decorateAchievement(id, title, purchase, label) end
end

function atlas.historicalAchievementSource(mount)
    if not mount.unavailable or not (atlas.achievementSources and atlas.achievementSources[mount.id]) then return end
    local lines = {}
    for line in atlas.normalizeSource(mount.journalSourceRaw):gmatch("[^\n]+") do
        local label, title = line:match("^%s*([^:]+):%s*(.+)$")
        if achievementLabel(label) then
            local text = decorateAchievementSource(mount, title, displaySourceLabel(label) .. ": ", false, false, mount.faction, true)
            if text then lines[#lines + 1] = text end
        end
    end
    if #lines > 0 then return table.concat(lines, "\n") end
end

function atlas.achievementRouteChoices(mount)
    local source = atlas.achievementSources and atlas.achievementSources[mount.id]
    if mount.kind ~= "Достижение" or not source or source.spell ~= mount.spell then return end
    local choices = {}
    for _, candidate in ipairs(source.candidates) do
        if candidate.routeExpansion then
            local id = candidate.id
            local name = atlas.getLocale() == "enUS" and candidate.englishName or candidate.name
            local sourceText = atlas.L("Достижение") .. ": |Hachievement:" .. id .. "|h" .. name .. "|h"
            choices[#choices + 1] = { category = "achievement", compact = true, routeCaption = candidate.routeExpansion,
                view = { id = mount.id, spell = mount.spell, kind = mount.kind, journalSourceRaw = sourceText } }
        end
    end
    if #choices > 0 then return choices end
end

function atlas.sourceAchievementReward(mount, view)
    if view.purchaseRequirement or view.vendorName then return end
    local api, journal = C_AchievementInfo, C_MountJournal
    if not api or not api.GetRewardItemID or not journal or not journal.GetMountFromItem then return end
    local source = atlas.normalizeSource(view.journalSourceOverride or view.journalSourceRaw or view.journalSource)
    local item, faction = nil, view.faction
    for line in source:gmatch("[^\n]+") do
        local label, title = line:match("^%s*([^:]+):%s*(.+)$")
        if not label then faction = achievementFactions[plain(line):match("^%s*(.-)%s*$")] or faction end
        if achievementLabel(label) then
            local id, candidate, spell = achievementForSource(mount, title, false, false, faction)
            if id then item = achievementReward(mount.id, spell or mount.spell, id, candidate) or item end
        end
    end
    return item
end

local function matchesQuestName(quest, name)
    if (quest.name and key(quest.name) == name) or (quest.englishName and key(quest.englishName) == name) then return true end
    for _, alias in ipairs(quest.journalNames or {}) do
        if key(alias) == name then return true end
    end
    return false
end

local function rewardQuest(mount, spell, title)
    local reward = atlas.questMountRewards and atlas.questMountRewards[mount.id]
    if not reward or reward.spell ~= spell then return end
    local name = key(title)
    local match, factionMatch, ambiguous, factionAmbiguous
    for _, quest in ipairs(reward.quests) do
        if matchesQuestName(quest, name) then
            ambiguous = ambiguous or match and match.id ~= quest.id
            match = quest
            if atlas.questMatchesPlayerFaction and atlas.questMatchesPlayerFaction(quest) then
                factionAmbiguous = factionAmbiguous or factionMatch and factionMatch.id ~= quest.id
                factionMatch = quest
            end
        end
    end
    if not ambiguous then return match end
    if not factionAmbiguous then return factionMatch end
end

function atlas.decorateSource(mount)
    local source = (atlas.vendorTokenSource and atlas.vendorTokenSource(mount))
        or mount.journalSourceOverride or (mount.unavailable and mount.journalSource)
        or mount.journalSourceRaw or mount.journalSource or ""
    local legacy = atlas.legacySourceDetails(mount)
    if legacy and type(legacy.source) == "string" and legacy.source ~= ""
        and not (mount.directSourceGrant and mount.journalSourceOverride) then source = atlas.L(legacy.source) end
    source = atlas.normalizeSource(source)
    if atlas.merchantPriceSource and not mount.vendorPriceResolved then
        source = atlas.merchantPriceSource(mount, source, mount.vendorName)
    end
    local questDetail = atlas.journalSourceDetails and atlas.journalSourceDetails[mount.id]
    if questDetail and type(questDetail.quests) == "table" then
        local normalized = atlas.searchKey(source)
        local matching = (questDetail.source and normalized == atlas.searchKey(atlas.normalizeSource(atlas.L(questDetail.source))))
            or (questDetail.englishSource and normalized == atlas.searchKey(atlas.normalizeSource(questDetail.englishSource)))
        for _, expected in ipairs(questDetail.replacesSource or {}) do
            if normalized == atlas.searchKey(atlas.normalizeSource(expected)) then matching = true; break end
        end
        if not matching then questDetail = nil end
    else
        questDetail = nil
    end
    local questRenown = (atlas.questRenownRequirements or {})[mount.id]
    if questRenown and questRenown.spell == mount.spell then
        for line in source:gmatch("[^\n]+") do
            local label, value = line:match("^([^:]+):%s*(.+)$")
            if label == "Задание" or label == "Квест" or label == "Quest" then
                for _, quest in ipairs(questRenown.quest) do
                    if key(value) == key(quest) then
                        source = atlas.appendMajorRenown(source, questRenown)
                        break
                    end
                end
                break
            end
        end
    end
    local lines, sourceLines = {}, {}
    local achievementLines = 0
    local purchaseRequirement = mount.purchaseRequirement == true or mount.vendorName ~= nil
    for line in (source .. "\n"):gmatch("(.-)\n") do
        sourceLines[#sourceLines + 1] = line
        if achievementLabel(line:match("^%s*([^:]+):%s*.+")) then
            achievementLines = achievementLines + 1
        end
    end
    local currentFaction, currentCovenant, questIndex = nil, nil, 0
    local achievementFaction = mount.faction
    for index, line in ipairs(sourceLines) do
        local label, value = line:match("^(%s*[^:{]+:%s*)(.+)$")
        local kind = label and label:match("^%s*([^:]+)")
        if not kind then achievementFaction = achievementFactions[plain(line):match("^%s*(.-)%s*$")] or achievementFaction end
        if label then label = displaySourceLabel(kind) .. ": "; line = label .. value end
        if achievementLabel(kind) then
            line = decorateAchievementSource(mount, value, label, achievementLines == 1, purchaseRequirement, achievementFaction)
        elseif kind == "Квест" or kind == "Задание" or kind == "Локальное задание"
            or kind == "Задание гарнизона" or kind == "Quest" or kind == "World Quest" or kind == "Garrison Mission" then
            local mission = kind == "Задание гарнизона" or kind == "Garrison Mission"
            if not mission then questIndex = questIndex + 1 end
            -- Explicit markup is resolved by displaySourceText. It already
            -- describes the linked fragment and must stay separate from prose.
            if not value:find(inlineQuestPattern) and not value:find(inlineMissionPattern) then
                local id = not mission and tonumber(value:match("|Hquest:(%d+)"))
                local spell = mount.spell
                if not mission then
                    if not number(spell) and C_MountJournal and C_MountJournal.GetMountInfoByID then
                        spell = select(2, C_MountJournal.GetMountInfoByID(mount.id))
                    end
                    if not id and questDetail and questDetail.spell == spell and type(questDetail.quests) == "table" then
                        id = questDetail.quests[questIndex]
                    end
                end
                local title = plain(value)
                local suffix = title:match("(%s+—%s+.+)$") or title:match("(%s+–%s+.+)$") or ""
                if suffix ~= "" then title = title:sub(1, #title - #suffix) end
                title = title:gsub("^%[", ""):gsub("%]$", "")
                title = title:match('^"(.-)"$') or title:match("^«(.-)»$") or title
                if not id and not mission then
                    local reward = rewardQuest(mount, spell, title)
                    if reward then id, title = reward.id, atlas.dataName(reward) or title end
                end
                local link = id and atlas.sourceQuestReference(id, title)
                if not id and (title == "стойла гарнизона" or title == "Стойла гарнизона" or title == "Garrison Stables") then
                    label = atlas.L("Место") .. ": "
                end
                line = label .. (link or title) .. suffix
            end
        elseif kind == "Ковенант" or kind == "Covenant" then
            currentFaction = nil
            currentCovenant = atlas.covenantSourceID(value)
            line = label .. decorateCovenant(value)
        elseif kind == "Фракция" or kind == "Репутация" or kind == "Faction" or kind == "Reputation" then
            currentCovenant = nil
            local id, required, covenantID = factionRequirement(value)
            if not id and not factionIndexed then
                indexFactions()
                id, required = factionRequirement(value)
            end
            local nextLabel = (sourceLines[index + 1] or ""):match("^%s*([^:]+):")
            if nextLabel == "Известность" or nextLabel == "Renown" then
                currentFaction = majorFactionNames[key(value)] or id
            else
                local current = id and reputation(id)
                local status, met = reputationStatus(current, required)
                if covenantID and current and current.name then line = label .. current.name .. " (" .. required .. ")" end
                line = objectiveLine(line .. status, met)
            end
        elseif kind == "Известность" or kind == "Renown" then
            local required, name = renownRequirement(value)
            if required and required > 0 then
                if not factionIndexed then indexFactions() end
                local factionID = currentFaction
                if name then factionID = majorFactionNames[key(name)] end
                local level
                if not name and not factionID and currentCovenant then
                    level = covenantRenownLevel(currentCovenant)
                else
                    level = renownLevel(factionID)
                end
                line = decorateRenown(line, required, level)
            end
            currentFaction, currentCovenant = nil, nil
        elseif kind == "Цена" or kind == "Стоимость" or kind == "Cost" or kind == "Price" then
            local price, met = decoratePrice(value)
            line = objectiveLine(label .. price, met)
        end
        if line:match("^%s*$") then currentFaction, currentCovenant = nil, nil end
        lines[#lines + 1] = line
    end
    return atlas.displaySourceText(table.concat(lines, "\n"))
end

function atlas.openAchievement(id)
    if not number(id) or id <= 0 or (InCombatLockdown and InCombatLockdown()) then return false end
    if C_AchievementInfo and C_AchievementInfo.IsValidAchievement and not C_AchievementInfo.IsValidAchievement(id) then return false end
    if not AchievementFrame_SelectAchievement then C_AddOns.LoadAddOn("Blizzard_AchievementUI") end
    if not AchievementFrame or not AchievementFrame_SelectAchievement then return false end
    if AchievementFrame_ToggleAchievementFrame then
        -- SelectAchievement alone keeps the current statistics/guild/comparison
        -- view. Use Blizzard's normal entry point to establish the right tab.
        local isGuild = select(12, GetAchievementInfo(id))
        if AchievementFrame:IsShown() then HideUIPanel(AchievementFrame) end
        AchievementFrame_ToggleAchievementFrame(false, isGuild == true)
        if not AchievementFrame:IsShown() then return false end
    else
        ShowUIPanel(AchievementFrame)
    end
    AchievementFrame_SelectAchievement(id)
    if MountAtlasWindow then MountAtlasWindow:Hide() end
    return true
end

local events = CreateFrame("Frame")
for _, event in ipairs({ "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED",
    "COVENANT_CHOSEN", "COVENANT_SANCTUM_RENOWN_LEVEL_CHANGED", "PLAYER_ENTERING_WORLD", "ACHIEVEMENT_EARNED",
    "NEUTRAL_FACTION_SELECT_RESULT", "PLAYER_GUILD_UPDATE",
    "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "CURRENCY_DISPLAY_UPDATE", "RECEIVED_ACHIEVEMENT_LIST", "QUEST_DATA_LOAD_RESULT", "ITEM_DATA_LOAD_RESULT" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event, id, success)
    if event == "PLAYER_GUILD_UPDATE" and (not readable(id) or id ~= "player") then return end
    if event == "ITEM_DATA_LOAD_RESULT" then
        if not number(id) or sourceItemLoads[id] ~= "pending" then return end
        sourceItemLoads[id] = success == true and "loaded" or "failed"
        if mountQualityItems[id] then
            mountQualityItems[id] = nil
            if success == true then mountQualitiesQueued = true end
        end
        if success == true then notify() end
        return
    end
    if event == "QUEST_DATA_LOAD_RESULT" then
        if not number(id) or questLoads[id] ~= "pending" then return end
        questLoads[id] = success == true and "loaded" or "failed"
        if success == true then notify() end
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then questLoads, sourceItemLoads, mountQualityItems = {}, {}, {} end
    if event == "RECEIVED_ACHIEVEMENT_LIST" or event == "NEUTRAL_FACTION_SELECT_RESULT" or event == "PLAYER_GUILD_UPDATE" then
        achievementAttempts = 0
        if achievementScan then achievementRescan = true else achievementReady = false end
        notify()
        return
    end
    if event == "ACHIEVEMENT_EARNED" then notify(); return end
    if factionScan or (event == "UPDATE_FACTION" and GetTime() < quietFactionUntil) then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "MAJOR_FACTION_UNLOCKED" or event == "UPDATE_FACTION" then
        factionIndexed = false
        factionNames = {}
        majorFactionNames = {}
    end
    notify()
end)
