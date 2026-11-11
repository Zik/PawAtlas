local _, atlas = ...
local achievementNames, achievementScan, achievementReady = {}, false, false
local achievementRewards, achievementIcons = {}, {}
local achievementAttempts, achievementRescan = 0, false
local achievementAliases, achievementRetryPending = {}, false
local factionNames, factionScan, factionIndexed = {}, false, false
local quietFactionUntil = 0
local refreshQueued = false

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
    end)
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
local function indexAchievements(retryUnresolved)
    if achievementScan or achievementRetryPending or not GetCategoryList
        or not GetCategoryNumAchievements or not GetAchievementInfo then return end
    if achievementReady then
        if not retryUnresolved or achievementAttempts >= 3 then return end
        achievementRetryPending = true
        C_Timer.After(2, function()
            achievementRetryPending, achievementReady = false, false
            indexAchievements()
        end)
        return
    end
    achievementAttempts = achievementAttempts + 1
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
    addCategories(GetCategoryList())
    if GetGuildCategoryList then addCategories(GetGuildCategoryList()) end
    if #categories == 0 then
        achievementReady = true
        notify()
        indexAchievements(true)
        return
    end
    achievementScan = true
    achievementNames, achievementAliases, achievementRewards, achievementIcons = {}, {}, {}, {}
    local categoryIndex, index = 1, 1
    local related, seen, incomplete, recorded = {}, {}, false, 0
    local function record(id, name, icon)
        if not number(id) or type(name) ~= "string" or name == "" then incomplete = true; return end
        if seen[id] then return end
        seen[id] = true
        recorded = recorded + 1
        if id > 0 then
            local normalized = key(name)
            rememberKey(achievementNames, normalized, id)
            rememberKey(achievementAliases, achievementAlias(normalized), id)
        end
        achievementIcons[id] = icon
        if C_AchievementInfo and C_AchievementInfo.GetRewardItemID and C_MountJournal and C_MountJournal.GetMountFromItem then
            local itemID = C_AchievementInfo.GetRewardItemID(id)
            local mountID = number(itemID) and itemID > 0 and C_MountJournal.GetMountFromItem(itemID)
            if number(mountID) and mountID > 0 then
                if achievementRewards[mountID] == nil then achievementRewards[mountID] = id
                elseif achievementRewards[mountID] ~= id then achievementRewards[mountID] = false end
            end
        end
        local prior = GetPreviousAchievement and GetPreviousAchievement(id)
        local nextID = GetNextAchievement and GetNextAchievement(id)
        if number(prior) and prior > 0 and not seen[prior] then related[#related + 1] = prior end
        if number(nextID) and nextID > 0 and not seen[nextID] then related[#related + 1] = nextID end
        if C_AchievementInfo and C_AchievementInfo.GetSupercedingAchievements then
            for _, replacement in ipairs(C_AchievementInfo.GetSupercedingAchievements(id) or {}) do
                if number(replacement) and replacement > 0 and not seen[replacement] then related[#related + 1] = replacement end
            end
        end
    end
    local function step()
        local remaining = 100
        -- Refresh the count on each tick while category data is still arriving.
        local count
        while (categoryIndex <= #categories or #related > 0) and remaining > 0 do
            if #related > 0 then
                local id = table.remove(related)
                local actualID, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(id)
                if actualID == id then record(id, name, icon) else incomplete = true end
                remaining = remaining - 1
            else
                local category = categories[categoryIndex]
                if count == nil then count = GetCategoryNumAchievements(category) end
                if not number(count) then incomplete = true end
                if not number(count) or index > count then
                    categoryIndex, index = categoryIndex + 1, 1
                    count = nil
                else
                    local id, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(category, index)
                    record(id, name, icon)
                    index, remaining = index + 1, remaining - 1
                end
            end
        end
        if categoryIndex <= #categories or #related > 0 then C_Timer.After(0, step)
        else
            achievementScan, achievementReady = false, true
            notify()
            if achievementRescan or incomplete or recorded == 0 then
                achievementRescan = false
                indexAchievements(true)
            end
        end
    end
    C_Timer.After(0, step)
end

local function indexFactions()
    local api = C_Reputation
    if factionScan or not api or not api.GetNumFactions or not api.GetFactionDataByIndex then return end
    factionScan = true
    local expanded = {}
    local oldLegacy = api.AreLegacyReputationsShown and api.AreLegacyReputationsShown()
    local changedLegacy = oldLegacy == false and api.SetLegacyReputationsShown ~= nil
    -- Expand only while taking the snapshot, then restore the previous UI state,
    -- including after an API failure. No reputation window is opened.
    local ok = pcall(function()
        if changedLegacy then api.SetLegacyReputationsShown(true) end
        local i = 1
        while i <= api.GetNumFactions() do
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
        if C_MajorFactions and C_MajorFactions.GetMajorFactionIDs and C_MajorFactions.GetMajorFactionData then
            for _, id in ipairs(C_MajorFactions.GetMajorFactionIDs() or {}) do
                local info = C_MajorFactions.GetMajorFactionData(id)
                if info then remember(factionNames, info.name, id) end
            end
        end
    end)
    for i = #expanded, 1, -1 do pcall(api.CollapseFactionHeader, expanded[i]) end
    if changedLegacy then pcall(api.SetLegacyReputationsShown, oldLegacy) end
    factionScan = false
    factionIndexed = ok
    quietFactionUntil = GetTime() + .5
end

local function reputation(id)
    if not C_Reputation or not C_Reputation.GetFactionDataByID then return end
    local info = C_Reputation.GetFactionDataByID(id)
    local major = C_MajorFactions and C_MajorFactions.GetMajorFactionData and C_MajorFactions.GetMajorFactionData(id)
    if major and readable(major.isUnlocked) and major.isUnlocked and number(major.renownLevel) then
        local label = atlas.L("Известность %d", major.renownLevel)
        return { label = label, renown = major.renownLevel }
    end
    if not info then return end
    if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
        local friendship = C_GossipInfo.GetFriendshipReputation(id)
        if friendship and number(friendship.friendshipFactionID) and friendship.friendshipFactionID > 0
            and readable(friendship.reaction) and type(friendship.reaction) == "string"
            and friendship.reaction ~= "" then
            local ranks = C_GossipInfo.GetFriendshipReputationRanks and C_GossipInfo.GetFriendshipReputationRanks(friendship.friendshipFactionID)
            return { label = friendship.reaction, rank = ranks and number(ranks.currentLevel) and ranks.currentLevel }
        end
    end
    if number(info.reaction) then
        local labels = { "Ненависть", "Враждебность", "Неприязнь", "Равнодушие", "Дружелюбие", "Уважение", "Почтение", "Превознесение" }
        return { label = labels[info.reaction] and atlas.L(labels[info.reaction]), standing = info.reaction }
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
local function reputationStatus(current, required, renown)
    if not current or not current.label then return atlas.L("  (Текущая репутация: —)"), nil end
    local met
    if required then
        required = key(required)
        if renown then
            if number(current.renown) and tonumber(required) then met = current.renown >= tonumber(required) end
        elseif current.standing then
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

local function factionRequirement(value)
    local text = plain(value):gsub("–", "-"):gsub("—", "-")
    -- Some faction names contain parentheses; prefer a full-name match first.
    local id = factionNames[key(text)]
    if id then return id end
    local name, required = text:match("^(.-)%s*%(([^()]*)%)%s*$")
    if not name then name, required = text:match("^(.-)%s+%-%s+(.+)$") end
    return name and factionNames[key(name)], required
end

local function decoratePrice(value)
    local money = GetMoney and GetMoney()
    if not number(money) then return value end
    local total, last, seen = 0, nil, {}
    -- Read only money textures, never item/currency amounts or hyperlink IDs.
    local clean = value:gsub("|H.-|h.-|h", function(link) return string.rep("#", #link) end)
    clean = clean:gsub("|c%x%x%x%x%x%x%x%x", function(color) return string.rep(" ", #color) end):gsub("|r", "  ")
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
    if not last then return value end
    local remainder = clean:gsub("([%d%s,%.  ]+)(|T.-|t)", function(amount, texture)
        if texture:lower():match("ui%-goldicon") or texture:lower():match("ui%-silvericon")
            or texture:lower():match("ui%-coppericon") then return "" end
        return amount .. texture
    end):gsub("[%s+,]", "")
    local met = money >= total
    local formatMoney = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString or GetMoneyString
    local status = not met and formatMoney and atlas.L("  (Не хватает: %s)", formatMoney(math.ceil(total - money))) or ""
    -- Mixed gold+currency/item prices cannot be completed from wallet gold alone.
    -- Keep the other components neutral; only the known shortage is annotated.
    if remainder ~= "" then
        local text = value:sub(1, last) .. status .. value:sub(last + 1)
        if met then return text, nil end
        return text, false
    end
    return value:sub(1, last) .. status .. value:sub(last + 1), met
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
    local source = mount.journalSourceRaw or mount.journalSource
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
local englishSourceNames
function atlas.dataName(record)
    if type(record) ~= "table" then return nil end
    return atlas.getLocale() == "enUS" and record.englishName or record.name
end

function atlas.sourceName(value, locale)
    if type(value) ~= "string" then return value or "" end
    if (locale or atlas.getLocale()) ~= "enUS" then return value end
    if not englishSourceNames then
        englishSourceNames = {}
        for _, mount in ipairs(atlas.mounts or {}) do
            local english = (atlas.englishNames or {})[mount.id] or mount.english
            if mount.name and english then englishSourceNames[key(mount.name)] = english end
        end
        for name, english in pairs(atlas.sourceEnglishNames or {}) do
            local normalized = key(name)
            if englishSourceNames[normalized] == nil then englishSourceNames[normalized] = english
            elseif englishSourceNames[normalized] ~= english then englishSourceNames[normalized] = false end
        end
    end
    -- Do not substitute a name through a hyperlink or texture; its payload and
    -- native label must stay intact for linking and tooltip handling.
    if value:find("|", 1, true) then return atlas.L(value) end
    return englishSourceNames[key(value)] or atlas.L(value)
end

function atlas.displayName(value)
    local text, i = atlas.sourceName(value), 1
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

function atlas.displaySourceText(source)
    local lines = {}
    for line in ((source or "") .. "\n"):gmatch("(.-)\n") do
        line = atlas.L(line)
        local label, value = line:match("^%s*([^:|]+):%s*(.+)$")
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
    local detail = atlas.legacySources and atlas.legacySources[mount.id]
    if type(detail) ~= "table" or not number(detail.spell) then return end
    local spell = mount.spell
    if not number(spell) and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local _, journalSpell = C_MountJournal.GetMountInfoByID(mount.id)
        spell = journalSpell
    end
    -- A reused MountID must never inherit another spell's retired source.
    if number(spell) and spell == detail.spell then return detail end
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

local function sourceAchievement(mount, title, singleSource)
    local source = atlas.achievementSources and atlas.achievementSources[mount.id]
    local api, journal = C_AchievementInfo, C_MountJournal
    if type(source) ~= "table" or type(source.candidates) ~= "table" or not GetAchievementInfo
        or not api or not api.GetRewardItemID or not journal or not journal.GetMountFromItem then return end
    local spell = mount.spell
    if not number(spell) and journal.GetMountInfoByID then
        local _, nativeSpell = journal.GetMountInfoByID(mount.id)
        spell = nativeSpell
    end
    if not number(spell) or spell ~= source.spell then return end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local selected
    for _, candidate in ipairs(source.candidates) do
        local id = candidate.id
        if number(id) and id > 0 and (not candidate.faction or candidate.faction == faction)
            and (not api.IsValidAchievement or api.IsValidAchievement(id)) then
            local actualID, name = GetAchievementInfo(id)
            local reward = api.GetRewardItemID(id)
            -- Supplemental names only discover candidates. The live reward
            -- must identify this mount, including for hidden chain tiers.
            if actualID == id and type(name) == "string" and name ~= "" and number(reward) and reward > 0
                and journal.GetMountFromItem(reward) == mount.id
                and (singleSource or achievementKey(name) == achievementKey(title)) then
                if selected and selected ~= id then return end
                selected = id
            end
        end
    end
    return selected
end

function atlas.decorateSource(mount)
    local source = (atlas.vendorTokenSource and atlas.vendorTokenSource(mount))
        or mount.journalSourceOverride or (mount.unavailable and mount.journalSource)
        or mount.journalSourceRaw or mount.journalSource or ""
    local legacy = atlas.legacySourceDetails(mount)
    if legacy and type(legacy.source) == "string" and legacy.source ~= "" then source = atlas.L(legacy.source) end
    source = atlas.normalizeSource(source)
    local lines, sourceLines = {}, {}
    local achievementLines = 0
    for line in (source .. "\n"):gmatch("(.-)\n") do
        sourceLines[#sourceLines + 1] = line
        if line:match("^%s*Достижение:%s*.+") or line:match("^%s*Achievement:%s*.+") then
            achievementLines = achievementLines + 1
        end
    end
    local currentFaction
    for index, line in ipairs(sourceLines) do
        local label, value = line:match("^(%s*[^:]+:%s*)(.+)$")
        local kind = label and label:match("^%s*([^:]+)")
        if label then label = displaySourceLabel(kind) .. ": "; line = label .. value end
        if kind == "Достижение" or kind == "Achievement" then
            local id = tonumber(value:match("|Hachievement:(%d+)"))
                or sourceAchievement(mount, value, achievementLines == 1)
                or (achievementReady and ((achievementLines == 1 and achievementRewards[mount.id])
                    or achievementNames[key(value)] or achievementAliases[achievementKey(value)]))
            value = plain(value)
            local icon = id and achievementIcons[id]
            if id and GetAchievementInfo then
                local actualID, name, _, _, _, _, _, _, _, nativeIcon = GetAchievementInfo(id)
                if actualID == id and type(name) == "string" and name ~= "" then value, icon = name, nativeIcon or icon
                else id = nil end
            end
            -- Source text can arrive before the category/reward cache. Retry a
            -- bounded number of times outside rendering; never scan IDs or alter
            -- the achievement window's global search to guess a matching title.
            if not id then indexAchievements(true) end
            if id and atlas.achievementIsFeat(id) then label = atlas.L("Великий подвиг") .. ": " end
            value = achievementTitle(value)
            local shield = "|TInterface\\AchievementFrame\\UI-Achievement-Shields-NoPoints:18:18:0:0:128:128:0:64:0:64|t"
            local badge = icon and ("|T" .. icon .. ":16:16:0:0|t") or shield
            line = label .. badge .. " |cffffd200" .. (id and ("|Hachievement:" .. id .. "|h" .. value .. "|h") or value) .. "|r"
        elseif kind == "Квест" or kind == "Задание" or kind == "Локальное задание"
            or kind == "Задание гарнизона" or kind == "Quest" or kind == "World Quest" or kind == "Garrison Mission" then
            line = label .. "|TInterface\\AddOns\\PawAtlas\\Media\\Controls\\Quest.tga:16:16:0:0|t " .. value
        elseif kind == "Ковенант" or kind == "Covenant" then
            line = label .. decorateCovenant(value)
        elseif kind == "Фракция" or kind == "Репутация" or kind == "Faction" or kind == "Reputation" then
            if not factionIndexed then indexFactions() end
            local id, required = factionRequirement(value)
            currentFaction = id
            local current = id and reputation(id)
            local nextLine = sourceLines[index + 1] or ""
            if not nextLine:match("^Известность:") and not nextLine:match("^Renown:") then
                local status, met = reputationStatus(current, required)
                line = objectiveLine(line .. status, met)
            end
        elseif kind == "Известность" or kind == "Renown" then
            if currentFaction and tonumber(plain(value)) then
                local status, met = reputationStatus(reputation(currentFaction), plain(value), true)
                line = objectiveLine(line .. status, met)
            end
        elseif kind == "Цена" or kind == "Стоимость" or kind == "Cost" or kind == "Price" then
            local price, met = decoratePrice(value)
            line = objectiveLine(label .. price, met)
        end
        if line:match("^%s*$") then currentFaction = nil end
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
for _, event in ipairs({ "UPDATE_FACTION", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "MAJOR_FACTION_UNLOCKED", "PLAYER_ENTERING_WORLD", "ACHIEVEMENT_EARNED", "PLAYER_MONEY", "BAG_UPDATE_DELAYED", "RECEIVED_ACHIEVEMENT_LIST" }) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
    if factionScan or (event == "UPDATE_FACTION" and GetTime() < quietFactionUntil) then return end
    if event == "PLAYER_ENTERING_WORLD" or event == "MAJOR_FACTION_UNLOCKED" or event == "UPDATE_FACTION" then
        factionIndexed = false
        factionNames = {}
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "ACHIEVEMENT_EARNED" or event == "RECEIVED_ACHIEVEMENT_LIST" then
        achievementAttempts = 0
        if achievementScan then achievementRescan = true else achievementReady = false end
    end
    notify()
end)
