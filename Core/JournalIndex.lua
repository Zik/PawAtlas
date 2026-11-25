local _, atlas = ...
-- The journal API uses BATTLE_PET_SOURCE_* indices, one above Mount.db2's
-- SourceTypeEnum. Zero is uncategorized and must remain unknown.
local kinds = {
    [1] = "Добыча", [2] = "Квест", [3] = "Торговец", [4] = "Профессия", [5] = "Битвы питомцев",
    [6] = "Достижение", [7] = "Событие", [8] = "Акция", [9] = "Карточная игра",
    [10] = "Магазин", [11] = "Исследование", [12] = "Торговая лавка",
}
local known, baseKeys = {}, {}
local uniqueMounts = atlas.uniqueMounts or {}
atlas.journalSourceRevision = 0
function atlas.mountByID(id)
    return known[id]
end
-- Acquisition item names differ from journal names. Index static localized
-- aliases once, including prerequisites and opened containers; searching must
-- not depend on visiting an item first or issue item requests per keystroke.
local function itemSearchWords(id)
    local words, seen = {}, {}
    local function add(value)
        if type(value) == "string" and value ~= "" and not seen[value] then
            seen[value] = true; words[#words + 1] = value
        end
    end
    local function entry(value)
        if type(value) ~= "table" then return end
        add(value.name); add(value.englishName)
        for _, name in ipairs(value.searchNames or {}) do add(name) end
        for _, variant in ipairs(value.variants or {}) do entry(variant) end
    end
    entry(atlas.lootItems[id])
    entry((atlas.vendorTokenOffers or {})[id])
    entry((atlas.factionMountGifts or {})[id])
    for _, reward in ipairs((atlas.mountRewardItems or {})[id] or {}) do entry(reward) end
    for _, stage in pairs((atlas.attemptStages or {})[id] or {}) do entry(stage) end
    return table.concat(words, " ")
end
local placeholderMarkers = { "PH", "DND", "NYI" }
local function isPlaceholder(name)
    local upper = name:upper()
    for _, marker in ipairs(placeholderMarkers) do
        if upper:find("[" .. marker .. "]", 1, true) or upper:match("%(" .. marker .. "[%s%)]") then return true end
    end
    return upper:match("^TEST MOUNT")
        or upper:match("^UNUSED[ _%-]") or upper:match("^UNUSED$")
end
local excludedSpells, unreleasedSpells = {}, {}
for _, spell in pairs(atlas.nonCollectibleMounts or {}) do excludedSpells[spell] = true end
for _, spell in pairs(atlas.unreleasedMounts or {}) do unreleasedSpells[spell] = true end
local function excludedByIdentity(id, name, spell, collected)
    -- A changed live spell must not inherit the old MountID's exclusion.
    if excludedSpells[spell] or (not spell and (atlas.nonCollectibleMounts or {})[id]) then return true end
    -- Acquisition confirms a collectible, but cannot turn a known movement
    -- ability into one. Unreleased/placeholder metadata may become obsolete.
    if collected then return false end
    -- Unused vendor records can retain a vendor, zone and price in the journal.
    local vendorSpell = (atlas.unusedVendorMounts or {})[id]
    if vendorSpell and (not spell or spell == vendorSpell) then return true end
    -- Prefer the current localized name over a stale English [PH] entry.
    return isPlaceholder(name and name ~= "" and name or atlas.englishNames[id] or "")
end

local function excludedBySource(id, spell, source)
    if unreleasedSpells[spell] or (not spell and (atlas.unreleasedMounts or {})[id]) then
        local liveSource = (source or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")
            :match("^%s*(.-)%s*$")
        if liveSource == "" or liveSource == "Старинное" or liveSource == "Legacy" then return true end
        -- The old 2186 placeholder has only a Trading Post category heading.
        if id == 2186 and (not spell or spell == 448845)
            and (liveSource == "Торговая лавка" or liveSource == "Trading Post") then return true end
    end
end

function atlas.isExcludedJournalMount(id, name, spell, collected, source)
    if excludedByIdentity(id, name, spell, collected) then return true end
    if collected then return false end
    if source == nil and unreleasedSpells[spell] and C_MountJournal
        and C_MountJournal.GetMountInfoExtraByID then
        source = select(3, C_MountJournal.GetMountInfoExtraByID(id))
        if issecretvalue and issecretvalue(source) then source = nil end
    end
    return excludedBySource(id, spell, source)
end

for index = #atlas.mounts, 1, -1 do
    local m = atlas.mounts[index]
    if atlas.isExcludedJournalMount(m.id, m.name) then table.remove(atlas.mounts, index)
    else known[m.id], baseKeys[m.id] = m, m.key or "" end
end
local raidZones = {}
for _, zone in ipairs(atlas.raidZones) do raidZones[atlas.searchKey(zone)] = true end

local function raidSource(mount, source)
    if mount.kind == "Рейд" or atlas.raidMounts[mount.id] then return true end
    if mount.kind == "Подземелье" or mount.locations then return nil end
    for line in source:gmatch("[^\n]+") do
        local achievement = line:match("^Достижение:%s*(.+)") or line:match("^Achievement:%s*(.+)")
        if achievement then
            achievement = atlas.searchKey(achievement):gsub('^"', ""):gsub("^guild ", "")
            if achievement:match("^слава рейдеру ") or achievement:match("^glory of .-raider") then return true end
        end
        local zone = line:match("^Зона:%s*(.+)") or line:match("^Место:%s*(.+)") or line:match("^Область:%s*(.+)")
            or line:match("^Zone:%s*(.+)") or line:match("^Location:%s*(.+)") or line:match("^Area:%s*(.+)")
        if zone then
            zone = atlas.searchKey(zone)
            -- Remove only recognized difficulty suffixes, never arbitrary qualifiers.
            zone = atlas.sourceDifficultySuffix(zone) or zone
            zone = zone:gsub('^"(.-)"$', "%1")
            if raidZones[zone] then return true end
        end
    end
end

local function display(text)
    return ((text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|n", "\n"):match("^%s*(.-)%s*$"))
end

local function plain(text)
    return (display(text):gsub("|T.-|t", ""):gsub("|A.-|a", "")
        :gsub("|H.-|h(.-)|h", "%1"))
end

local sourceKinds = {
    ["Источник"] = "Добыча", ["Добыча"] = "Добыча", ["Сокровище"] = "Добыча",
    ["Торговец"] = "Торговец", ["Торговцы"] = "Торговец", ["Продавец"] = "Торговец",
    ["Задание"] = "Квест", ["Локальное задание"] = "Квест", ["Задание гарнизона"] = "Квест",
    ["Достижение"] = "Достижение", ["Великий подвиг"] = "Достижение", ["Профессия"] = "Профессия", ["Класс"] = "Класс",
    ["Событие"] = "Событие", ["Особое событие"] = "Событие", ["Праздник"] = "Событие",
    ["Промоакция"] = "Акция", ["Исследование"] = "Исследование", ["PvP"] = "PvP",
    ["Рыбалка"] = "Рыбалка", ["Рыбная ловля"] = "Рыбалка",
    ["Коллекционная карточная игра"] = "Карточная игра", ["Карточная игра"] = "Карточная игра",
    ["Drop"] = "Добыча", ["Source"] = "Добыча", ["Treasure"] = "Добыча", ["Vendor"] = "Торговец", ["Quest"] = "Квест",
    ["Achievement"] = "Достижение", ["Feats of Strength"] = "Достижение", ["Profession"] = "Профессия", ["Class"] = "Класс",
    ["Vendors"] = "Торговец", ["World Quest"] = "Квест", ["Garrison Mission"] = "Квест",
    ["Event"] = "Событие", ["World Event"] = "Событие", ["Special Event"] = "Событие", ["Holiday"] = "Событие",
    ["Promotion"] = "Акция", ["Exploration"] = "Исследование", Fishing = "Рыбалка",
    ["Trading Card Game"] = "Карточная игра",
}

local missingPlaces = { ["—"] = true, ["-"] = true, ["Журнал"] = true, ["Нет данных"] = true,
    ["Рарка"] = true, ["Босс"] = true, ["Рейд"] = true, ["Подземелье"] = true,
    ["Торговая лавка"] = true, ["Старинное"] = true,
    Journal = true, Unknown = true, Rare = true, Boss = true, Raid = true, Dungeon = true,
    ["Trading Post"] = true, Legacy = true }
function atlas.sourcePlaceValue(value, kind)
    if type(value) ~= "string" then return end
    local name = plain(value):match("^%s*(.-)%s*$")
    if name == "" or name == kind or kind and name == atlas.L(kind) or missingPlaces[name] or sourceKinds[name] then return end
    return value:match("^%s*(.-)%s*$")
end

local function sourceKind(source, category)
    if source == "Старинное" or source == "Legacy" then return "Журнал", true end
    local covenantOnly = false
    for line in source:gmatch("[^\n]+") do
        local bare = line:match("^%s*(.-)%s*$"):gsub("%.$", "")
        if bare == "Задание" or bare == "Квест" or bare == "Quest" then return "Квест", true end
        local label = line:match("^%s*([^:]+):")
        label = label and label:match("^%s*(.-)%s*$")
        local kind = sourceKinds[label or bare]
        if not label and (bare == "Источник" or bare == "Source") then kind = nil end
        if kind then return kind, true end
        if label == "Ковенант" or label == "Covenant" then covenantOnly = true end
        if line:match("^Паладин%s*$") or line:match("^Paladin%s*$") then return "Класс", true end
        -- Explicit journal text outranks numeric categories, which can still
        -- describe an older acquisition route in either client locale.
        if bare == "Внутриигровой магазин" or bare == "In-Game Shop" then return "Магазин", true end
        if bare == "Торговая лавка" or bare == "Trading Post" then return "Торговая лавка", true end
    end
    return kinds[category] or "Журнал", false, covenantOnly
end

function atlas.isAchievementSourceLabel(label)
    return sourceKinds[label] == "Достижение"
end

local function routeVersionCurrent(route)
    if route.sinceInterface or route.untilInterface then
        if not GetBuildInfo then return false end
        local ok, _, _, _, interface = pcall(GetBuildInfo)
        if not ok or (issecretvalue and issecretvalue(interface)) or type(interface) ~= "number"
            or (route.sinceInterface and interface < route.sinceInterface)
            or (route.untilInterface and interface >= route.untilInterface) then return false end
    end
    return true
end

function atlas.verifiedRewardDropRoute(mount)
    local route = atlas.rewardDropRoutes and atlas.rewardDropRoutes[mount.id]
    local stages = atlas.attemptStages and atlas.attemptStages[mount.id]
    local reward = stages and stages.reward
    if not route or not reward or route.method ~= reward.method or route.item ~= reward.item
        or not routeVersionCurrent(route) then return end
    return route
end

function atlas.raidLootReward(mount)
    local reward = atlas.raidLootRewards and atlas.raidLootRewards[mount.id]
    if not reward or reward.scope ~= "raid" or not routeVersionCurrent(reward) then return end
    if reward.spell and mount.spell and mount.spell ~= reward.spell then return end
    local stages = atlas.attemptStages and atlas.attemptStages[mount.id]
    local definition = stages and stages.reward
    if definition then
        if reward.item == definition.item and definition.difficulties and definition.difficulties[reward.difficultyID] then return reward end
        return
    end
    local source = atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id]
    if not reward.spell or not source or source.map ~= reward.map
        or not (source.difficulties and source.difficulties[reward.difficultyID]) then return end
    for _, item in ipairs((atlas.mountRewardItems or {})[mount.id] or {}) do
        if item.item == reward.item then return reward end
    end
end

local dropLabels = { ["Источник"] = true, ["Добыча"] = true, ["Сокровище"] = true, Drop = true, Source = true, Treasure = true }
local placeLabels = { ["Зона"] = true, ["Место"] = true, ["Область"] = true, ["Zone"] = true, ["Location"] = true, ["Area"] = true }
local containerWords = { "сундук", "тайник", "сумк", "мешок", "контейнер", "сокровищ", "ларь", "ларец",
    "дар алекстраз", "элементиевый фрагмент", "chest", "cache", "bag", "box", "spoils", "alexstrasza's gift", "elementium fragment" }
local difficultyNames = {
    ["обычный"] = "normal", ["обычный режим"] = "normal", ["normal"] = "normal",
    ["героический"] = "heroic", ["героический режим"] = "heroic", ["heroic"] = "heroic",
    ["эпохальный"] = "mythic", ["эпохальный режим"] = "mythic", ["mythic"] = "mythic",
    ["поиск рейда"] = "normal", ["raid finder"] = "normal",
    ["путешествие во времени"] = "heroic", ["timewalking"] = "heroic",
}
local difficultyLabels = { ["Режим"] = true, ["Сложность"] = true, Difficulty = true, Mode = true }
local dropConditionLabels = { ["Праздник"] = true, ["Событие"] = true, ["Особое событие"] = true,
    ["Ковенант"] = true, Holiday = true, Event = true, Covenant = true }

-- Shared source metadata: both the card layout and its difficulty badge use
-- the same strict grammar. Unknown conditions remain in the full source card.
function atlas.isDifficultySourceLabel(label)
    return difficultyLabels[label] == true
end

function atlas.isDropSourceLabel(label)
    return dropLabels[label] == true
end

function atlas.parseSourceDifficulty(value)
    local text = display(value)
    local result = {}
    for part in text:gmatch("[^,;/]+") do
        part = part:match("^%s*(.-)%s*$")
        local kind = difficultyNames[atlas.searchKey(part)]
        if not kind then return end
        result[#result + 1] = { name = part, kind = kind }
    end
    return #result > 0 and result or nil
end

function atlas.sourceDifficultySuffix(value)
    local place, mode = value:match("^(.-)%s*%(([^()]*)%)%s*$")
    if not place then place, mode = value:match("^(.-)%s+·%s+(.+)$") end
    if mode and atlas.parseSourceDifficulty(mode) then return place:match("^%s*(.-)%s*$"), mode end
end

local function sourceLine(line)
    local heading, value = line:match("^([^:{]*):%s*(.-)%s*$")
    if not heading then return end
    local label = heading:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    if label == "" or label:find("|", 1, true) then return end
    -- These misspellings occur in native ruRU journal headings.
    if label == "Торгоец" then label = "Торговец" end
    if label == "IПредмет" then label = "Предмет" end
    if label == "в" and line:match("^%s*|c[fF][fF][fF][fF][dD]200в:|r%s*%S") then
        label = "Зона" -- A short location header in the native ruRU journal.
    end
    -- A heading's closing color escape can follow its colon. Remove only that
    -- closing escape; links, textures and colors belonging to values stay intact.
    if heading:match("|c%x%x%x%x%x%x%x%x[^|]*$") then value = value:gsub("^|r%s*", "", 1) end
    return label, value
end

local inlineReference = "{%a+:%d+:"
local function journalSourceFields(source, kind)
    local target, place
    for line in source:gmatch("[^\n]+") do
        local label, value = sourceLine(line)
        if value and value ~= "" and not value:find(inlineReference) then
            if not place and placeLabels[label] then place = atlas.sourcePlaceValue(value, kind) end
            if not target and (sourceKinds[label] == kind
                or (kind == "Добыча" or kind == "Рейд") and (dropLabels[label] or label == "NPC")) then
                target = value
            end
        end
    end
    return target or kind, place
end

local function achievementAlternatives(source)
    local alternatives, newRoute, faction = {}, true, nil
    local factionHeaders = { ["Альянс"] = "Alliance", ["Орда"] = "Horde", Alliance = "Alliance", Horde = "Horde" }
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local text = plain(line)
        if factionHeaders[text] then
            faction, newRoute = factionHeaders[text], true
        elseif text == "" then newRoute = true
        elseif newRoute then
            local label, value = sourceLine(line)
            if atlas.isAchievementSourceLabel(label) and value ~= "" then
                alternatives[#alternatives + 1] = { text = label .. ": " .. value, faction = faction }
            end
            newRoute = false
        end
    end
    return alternatives
end

-- Card helpers repeatedly parse the same journal text. Keep a small bounded
-- cache of this pure conversion; changed native text is a different key.
local normalizedSources, normalizedOrder, normalizedCursor = {}, {}, 0
function atlas.normalizeSource(source)
    source = source or ""
    if normalizedSources[source] then return normalizedSources[source] end
    local original = source
    local lines, places, seenPlaces = {}, {}, {}
    local previousDrop
    local function flushPlaces()
        if #places > 0 then
            lines[#lines + 1] = "Место: " .. table.concat(places, " · ")
            places, seenPlaces = {}, {}
        end
    end
    source = (source or ""):gsub("|n", "\n"):gsub("\r\n", "\n"):gsub("\r", "\n")
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local label, value = sourceLine(line)
        if placeLabels[label] and value ~= "" then
            if not seenPlaces[value] then places[#places + 1], seenPlaces[value] = value, true end
            previousDrop = nil
        else
            flushPlaces()
            local normalized = label and (label .. ": " .. value) or line
            if not (dropLabels[label] and previousDrop == normalized) then lines[#lines + 1] = normalized end
            previousDrop = dropLabels[label] and normalized or nil
        end
    end
    flushPlaces()
    local result = table.concat(lines, "\n")
    normalizedCursor = normalizedCursor % 32 + 1
    local expired = normalizedOrder[normalizedCursor]
    if expired then normalizedSources[expired] = nil end
    normalizedOrder[normalizedCursor], normalizedSources[original] = original, result
    return result
end

local function journalSourceDetail(id, spell, kind, source)
    local reward = atlas.questMountRewards and atlas.questMountRewards[id]
    local detail = atlas.journalSourceDetails and atlas.journalSourceDetails[id] or reward and reward.journalDetail
    if not detail or detail.spell ~= spell or (detail.replacesKind ~= kind and detail.alternateKind ~= kind) then return end
    if not detail.replacesSource then return detail end
    if source == nil then return end
    local normalized = atlas.normalizeSource(source)
    for _, expected in ipairs(detail.replacesSource) do
        if normalized == atlas.normalizeSource(expected) then return detail end
    end
end

local function directMountGrant(id, spell, kind, source, covenantOnly)
    local grant = atlas.directMountGrants and atlas.directMountGrants[id]
    if not grant or grant.spell ~= spell or grant.kind ~= kind or not source then return end
    if grant.covenant then return (covenantOnly or grant.alternate) and grant or nil end
    local normalized = atlas.normalizeSource(display(source))
    for _, expected in ipairs(grant.source or {}) do
        if normalized == atlas.normalizeSource(expected) then return grant end
    end
end

local function sourcePanels(mount, source, kind)
    if not mount.journalOnly or (kind ~= "Добыча" and kind ~= "Рейд") then return end
    -- Source buttons cannot render/click rich inline payloads. Keep those in the
    -- hyperlink-enabled journal surface instead of flattening them into labels.
    local raw = mount.journalSourceOverride or mount.journalSourceRaw or ""
    if raw:find("|[HTA]") or raw:find(inlineReference) then return end
    local groups, current = {}, { lines = {}, modes = {}, seenModes = {}, conditions = {} }
    local prefixMode, hasConditions
    local function addModes(group, entries)
        for _, entry in ipairs(entries) do
            local key = atlas.searchKey(entry.name)
            if not group.seenModes[key] then
                group.modes[#group.modes + 1], group.seenModes[key] = entry.name, true
            end
        end
    end
    local function flush()
        if #current.lines > 0 then groups[#groups + 1] = current end
        current = { lines = {}, modes = {}, seenModes = {}, conditions = {} }
    end
    for line in (atlas.normalizeSource(source) .. "\n"):gmatch("(.-)\n") do
        if line:match("%S") then
            local label, value = sourceLine(line)
            if not value or value == "" then return end
            if dropLabels[label] then
                if current.boss then flush() end
                current.boss = value
                current.treasure = label == "Сокровище" or label == "Treasure"
            elseif placeLabels[label] and not current.place then current.place = value
            elseif atlas.isDifficultySourceLabel(label) then
                local entries = atlas.parseSourceDifficulty(value)
                if not entries then return end
                if not current.boss then prefixMode = true end
                addModes(current, entries)
            elseif dropConditionLabels[label] then
                current.conditions[#current.conditions + 1] = line
                hasConditions = true
            else return end -- Unrecognized requirements stay in the full, hyperlink-enabled source.
            current.lines[#current.lines + 1] = line
        end
    end
    flush()
    if #groups == 0 then return end
    -- A shared prefix/trailing condition has no reliable scope across alternatives.
    if #groups > 1 and (prefixMode or hasConditions) then return end
    local info = mount.sourceOverride or (atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id])
    local bossRoutes = info and info.bosses
    local primaryBoss = bossRoutes and bossRoutes[1]
    local separateDifficulties = primaryBoss and primaryBoss.difficulties ~= nil
    if primaryBoss and #groups == 1 then
        local shared = groups[1]
        local name = atlas.searchKey(shared.boss or "")
        local generic = name == "boss drop" or name == "добыча с босса"
        local knownPrimary = separateDifficulties and #shared.modes == 0 and not shared.treasure
            and (name == atlas.searchKey(primaryBoss.boss) or name == atlas.searchKey(primaryBoss.englishBoss))
        -- Only expand a verified shared instance; don't reinterpret a new live
        -- journal location or a condition whose scope is unknown.
        local samePlace = not shared.place or atlas.searchKey(shared.place) == atlas.searchKey(info.place or "")
            or atlas.searchKey(shared.place) == atlas.searchKey(info.englishPlace or "")
        if (generic or knownPrimary) and samePlace and not hasConditions and not prefixMode then
            groups = {}
            local english = GetLocale and GetLocale() ~= "ruRU"
            local place = shared.place or (english and info.englishPlace or info.place)
            for _, entry in ipairs(bossRoutes) do
                local boss = english and entry.englishBoss or entry.boss
                groups[#groups + 1] = { boss = boss, englishBoss = entry.englishBoss,
                    place = place, npc = entry.npc, difficulties = entry.difficulties,
                    modes = shared.modes, seenModes = shared.seenModes, conditions = {},
                    lines = { "Источник: " .. boss, "Место: " .. place } }
            end
        end
    end
    for _, group in ipairs(groups) do
        local boss, place = group.boss, group.place
        if info and #groups == 1 then
            local en = GetLocale and GetLocale() ~= "ruRU"
            local map = info.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(info.map)
            place = place or (map and map.name) or (en and info.englishPlace or info.place)
            local genericBoss = atlas.searchKey(boss or "")
            if not boss or genericBoss == "boss drop" or genericBoss == "добыча с босса" then
                boss = (en and info.englishBoss or info.boss) or boss
            end
        end
        if not boss or not place then return end
        local baseBoss, bossMode = atlas.sourceDifficultySuffix(boss)
        if bossMode then boss = baseBoss; addModes(group, atlas.parseSourceDifficulty(bossMode)) end
        local basePlace, placeMode = atlas.sourceDifficultySuffix(place)
        if placeMode then place = basePlace; addModes(group, atlas.parseSourceDifficulty(placeMode)) end
        -- A shared mount's metadata must not turn an alternative cache into its boss.
        local matchingInfo = info and (not separateDifficulties or group.difficulties) and
            (#groups == 1 or atlas.searchKey(place) == atlas.searchKey(info.place or "")
            or atlas.searchKey(place) == atlas.searchKey(info.englishPlace or "")) and info
        local sourceKind = group.treasure and "Добыча" or (matchingInfo and matchingInfo.sourceKind)
            or (atlas.bossSources and atlas.bossSources[mount.id] and "Босс") or "Добыча"
        local normalized = atlas.searchKey(boss)
        for _, word in ipairs(containerWords) do
            if normalized:find(atlas.searchKey(word), 1, true) then sourceKind = "Добыча"; break end
        end
        local placeKind = matchingInfo and matchingInfo.placeKind
            or (raidZones[atlas.searchKey(place)] and "Рейд")
            or (matchingInfo and matchingInfo.mapType == 3 and "Открытый мир")
        -- UiMap type4 denotes an instance; it does not distinguish raids from dungeons.
        group.id, group.boss, group.sourceKind = mount.id, boss, sourceKind
        group.sourcePlaceKind, group.isRaid = placeKind, placeKind == "Рейд"
        group.sourceMap = matchingInfo and matchingInfo.map
        group.sourceMaps = matchingInfo and matchingInfo.maps
        group.hasSourcePanels, group.difficultyLocalOnly = true, #groups > 1 or separateDifficulties
        group.trackingCompatible = (not separateDifficulties or group.difficulties ~= nil)
            and (#groups == 1 or sourceKind == "Босс")
        group.difficulties = group.difficulties or (matchingInfo and group.trackingCompatible and (matchingInfo.difficulties
            or (matchingInfo.difficultyID and { [matchingInfo.difficultyID] = true })))
        group.journalSourceRaw = table.concat(group.lines, "\n")
        group.conditions = table.concat(group.conditions, "\n")
        group.place = place .. (#group.modes > 0 and (" · " .. table.concat(group.modes, ", ")) or "")
        group.lines, group.modes, group.seenModes, group.treasure = nil, nil, nil, nil
    end
    for _, group in ipairs(groups) do if group.isRaid then mount.isRaid = true end end
    mount.sourcePlaceKind = groups[1].sourcePlaceKind
    return groups[1].boss, groups[1].place, groups[1].sourceKind, groups
end

local function indexJournalMount(mount, id, name, spell, category, rawSource)
    local source = plain(rawSource)
    local kind, explicitKind, covenantOnly = sourceKind(source, category)
    local vendorSource, vendorOffer
    if atlas.vendorTokenSource then
        vendorSource, vendorOffer = atlas.vendorTokenSource({ id = id, spell = spell, journalSourceRaw = rawSource })
    end
    if vendorSource then source, kind, explicitKind = vendorSource, "Торговец", true end
    local reviewedSource, reviewedOffer
    if atlas.reviewedVendorSource then
        reviewedSource, reviewedOffer = atlas.reviewedVendorSource({ id = id, spell = spell, journalSourceRaw = rawSource })
    end
    if reviewedSource and not vendorSource then source, kind, explicitKind = reviewedSource, "Торговец", true end
    local saddlePurchase = atlas.reviewSaddlePurchase and atlas.reviewSaddlePurchase(id, spell, kind, source)
    if saddlePurchase and saddlePurchase.season then
        source, kind, explicitKind = atlas.saddlePurchaseSource(saddlePurchase), "Торговец", true
    end
    local detail = journalSourceDetail(id, spell, kind, rawSource ~= nil and source or nil)
    if detail then
        kind, explicitKind = detail.kind, true
        if detail.source then
            source = GetLocale and GetLocale() ~= "ruRU" and detail.englishSource or atlas.L(detail.source)
        end
    end
    local route = atlas.verifiedRewardDropRoute({ id = id })
    local raidReward = atlas.raidLootReward({ id = id, spell = spell })
    local raidMode
    if raidReward and kind == "Добыча" and raidReward.boss and raidReward.place and raidReward.npc then
        local bosses, places = {}, {}
        for _, name in ipairs({ raidReward.boss, raidReward.englishBoss }) do bosses[atlas.searchKey(name)] = true end
        for _, name in ipairs({ raidReward.place, raidReward.englishPlace }) do places[atlas.searchKey(name)] = true end
        local bossSeen, placeSeen
        for line in source:gmatch("[^\n]+") do
            local label, value = sourceLine(line)
            if value and (dropLabels[label] or placeLabels[label]) then
                local base, mode = atlas.sourceDifficultySuffix(value)
                local name = atlas.searchKey(base or value)
                bossSeen, placeSeen = bossSeen or bosses[name], placeSeen or places[name]
                raidMode = raidMode or mode
            end
        end
        -- A reviewed boss/place pair may be reversed in the journal.
        -- A new, unrelated live source never inherits that correction.
        if bossSeen and placeSeen then route = raidReward end
    end
    local sourceOverride
    if route and (route == raidReward or route.replacesJournalKind == kind)
        and route.boss and route.place and route.sourceKind then
        sourceOverride = route
        local english = GetLocale and GetLocale() ~= "ruRU"
        local boss, place = english and route.englishBoss or route.boss, english and route.englishPlace or route.place
        source = (english and "Drop: " or "Источник: ") .. boss .. "\n" .. (english and "Zone: " or "Место: ") .. place
        if route == raidReward and raidMode then source = source .. "\n" .. (english and "Difficulty: " or "Режим: ") .. raidMode end
        kind, explicitKind = "Добыча", true
    end
    local legacy = source == "Старинное" or source == "Legacy"
    local reviewedAvailability = atlas.legacySourceDetails
        and atlas.legacySourceDetails({ id = id, spell = spell, journalSourceRaw = rawSource })
    -- A review without a confirmed replacement must not overwrite
    -- the current journal or disable its source interactions.
    local availability = reviewedAvailability and type(reviewedAvailability.source) == "string"
        and reviewedAvailability.source ~= "" and reviewedAvailability or nil
    local unavailable = availability and availability.state == "unavailable" or false
    if availability then
        source = atlas.L(availability.source)
        local routeKind = availability.routes and availability.routes[1] and availability.routes[1].kind
        kind = availability.state == "available" and availability.kind or nil
        kind = kind or ((routeKind == "vendor" or availability.state == "blackmarket") and "Торговец")
            or (routeKind == "tradingpost" and "Торговая лавка")
            or (routeKind == "quest" and "Квест") or (routeKind == "class" and "Класс") or "Журнал"
        explicitKind, sourceOverride, detail = true, nil, nil
    end
    local grant = (not availability or availability.state == "available")
        and directMountGrant(id, spell, kind, rawSource, covenantOnly) or nil
    local grantSource
    if grant and not grant.alternate and grant.text then
        grantSource = GetLocale and GetLocale() ~= "ruRU" and grant.englishText or grant.text
        source = grantSource
    elseif grant and grant.renown and not grant.alternate
        and not source:match("\nИзвестность:") and not source:match("\nRenown:") then
        local requirement = atlas.L("Известность") .. ": " .. grant.renown
        grantSource = atlas.normalizeSource(rawSource):gsub("%s+$", "") .. "\n" .. requirement
        source = plain(grantSource)
    end
    if mount.journalOnly then
        mount.name, mount.kind = name, kind
        mount.boss, mount.place = journalSourceFields(source, kind)
    end
    mount.spell = spell
    mount.availability = availability
    mount.sourceReview = reviewedAvailability
    mount.saddlePurchase = not availability and saddlePurchase or nil
    mount.directSourceGrant = grant
    if availability then mount.kind = kind end
    mount.expansion = mount.expansion or atlas.mountExpansions[id]
    mount.covenantSourceOnly = covenantOnly and not explicitKind or nil
    mount.journalSourceRaw = rawSource or ""
    mount.vendorTokenOffer = vendorOffer
    mount.reviewedVendorOffer = not availability and not vendorOffer and reviewedOffer or nil
    mount.sourceOverride = sourceOverride
    mount.journalSourceOverride = (sourceOverride or (detail and detail.source) or availability or vendorOffer or reviewedOffer
        or (saddlePurchase and saddlePurchase.season) or grantSource) and source or nil
    mount.unavailable = unavailable
    mount.journalUnknownSourceNote = detail and detail.unknownSourceNote or nil
    mount.sourceRequirements = detail and detail.kind == kind and detail.requirements or nil
    mount.weeklyRewardQuests = detail and detail.kind == kind and detail.weeklyRewardQuests or nil
    mount.journalSource = unavailable and "Недоступно для получения" or display(mount.journalSourceOverride or rawSource)
    mount.isRaid = raidSource(mount, source)
    mount.sourcePlaceKind = nil
    local sourceBoss, sourcePlace, panelKind, groups = sourcePanels(mount, source, kind)
    mount.hasSourcePanels = sourceBoss ~= nil
    mount.sourceKind = panelKind
    mount.sourceGroups = groups
    if sourceBoss then mount.boss, mount.place = sourceBoss, sourcePlace end
    local forgeMap
    if kind == "Профессия" and not availability and not mount.place then
        local item = atlas.craftedMountItem(mount)
        if item and atlas.protoformMountRecipes[item] then
            forgeMap = atlas.sourceUiMaps[atlas.protoformForgeMapID]
            mount.place = forgeMap[atlas.getLocale() == "enUS" and 2 or 1]
        end
    end
    mount.questFrequency = not legacy and atlas.questFrequencies[id] or nil
    local reward = atlas.attemptStages[id] and atlas.attemptStages[id].reward
    local trackedLoot = reward and reward.method ~= "SPECIAL"
    -- Hidden loot-lockout quests and world quests around a rare are
    -- not quest rewards. Actual quest starters keep their own flag.
    mount.hasQuest = not legacy and (mount.quest ~= nil or (not trackedLoot and
        ((explicitKind and kind == "Квест") or source:find("Задание:", 1, true) ~= nil
            or source:find("Quest:", 1, true) ~= nil)))
    mount.achievementSteps = nil
    mount.hasAchievement = not legacy and kind == "Достижение"
    for _, route in ipairs(availability and availability.routes or {}) do
        if route.kind == "achievement" then mount.hasAchievement = true; break end
    end
    local hasAchievementField = source:find("Достижение:", 1, true) or source:find("Achievement:", 1, true)
        or source:find("Великий подвиг:", 1, true) or source:find("Feats of Strength:", 1, true)
    if not legacy and not availability and (vendorOffer or hasAchievementField) then
        local hasVendorField = vendorOffer or kind == "Торговец" or source:find("Торговец:", 1, true)
            or source:find("Торговцы:", 1, true) or source:find("Продавец:", 1, true)
            or source:find("Vendor:", 1, true) or source:find("Vendors:", 1, true)
        local steps = hasVendorField and atlas.vendorAchievementRequirements and atlas.vendorAchievementRequirements(mount)
        if (not steps or #steps == 0) and not mount.hasAchievement then
            steps = achievementAlternatives(atlas.normalizeSource(mount.journalSourceOverride or rawSource or ""))
        end
        if steps and #steps > 0 then mount.achievementSteps, mount.hasAchievement = steps, true end
    end
    local alternatives = {}
    for _, group in ipairs(groups or {}) do
        alternatives[#alternatives + 1] = group.boss
        alternatives[#alternatives + 1] = group.englishBoss or ""
    end
    local uniqueName = availability and availability.unique and availability.name or ""
    mount.key = atlas.searchKey(table.concat({ baseKeys[id] or "", name, mount.english, uniqueName, kind, source, table.concat(alternatives, " "),
        itemSearchWords(id), forgeMap and forgeMap[1] or "", forgeMap and forgeMap[2] or "" }, " "))

    -- An empty source is valid. Nil means the extra info needs to be retried.
    mount.indexed = rawSource ~= nil
end

local pending, pendingIdentity, membershipReady = {}, {}, false

local function journalValue(value)
    if not (issecretvalue and issecretvalue(value)) then return value end
end

local function validMountID(id)
    return type(id) == "number" and id > 0 and id % 1 == 0
end

local function changeCounts(collection, expansion, total, collected)
    local counts = collection.expansions[expansion]
    if not counts then
        counts = { total = 0, collected = 0 }
        collection.expansions[expansion] = counts
    end
    counts.total, counts.collected = counts.total + total, counts.collected + collected
    if counts.total == 0 then collection.expansions[expansion] = nil end
    collection.total, collection.collected = collection.total + total, collection.collected + collected
end

local function journalBatch(collection)
    return { collection = collection or { byID = {}, expansions = {}, collected = 0, total = 0 },
        added = {}, removed = {}, changed = collection == nil }
end

local function publishJournal(batch)
    if not batch.changed then return false end
    if next(batch.removed) then
        for i = #atlas.mounts, 1, -1 do
            if batch.removed[atlas.mounts[i]] then table.remove(atlas.mounts, i) end
        end
    end
    local added = {}
    for _, mount in pairs(batch.added) do added[#added + 1] = mount end
    table.sort(added, function(a, b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    for _, mount in ipairs(added) do atlas.mounts[#atlas.mounts + 1] = mount end
    if batch.sourcesChanged then atlas.journalSourceRevision = atlas.journalSourceRevision + 1 end
    -- Publish a new identity for the UI. The underlying index is updated by ID.
    local collection = batch.collection
    atlas.collection = { byID = collection.byID, expansions = collection.expansions,
        collected = collection.collected, total = collection.total }
    if atlas.queuePlanBrokerRefresh then atlas.queuePlanBrokerRefresh() end
    if atlas.queueExpeditionTrackerRefresh then atlas.queueExpeditionTrackerRefresh() end
    return true
end

local function sampleMount(batch, id, retryable, requestedOnly)
    local collection = batch.collection
    local mount = known[id]
    local name, spell, icon, _, _, category, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(id)
    name, spell, icon = journalValue(name), journalValue(spell), journalValue(icon)
    category, collected = journalValue(category), journalValue(collected)
    local candidate = uniqueMounts[id]
    local uniqueNative = candidate and spell == candidate.spell
    local unique = candidate and (uniqueNative
        or spell == nil and (not mount or not mount.spell or mount.spell == candidate.spell)) and candidate
    -- Historical metadata can fill in a name and icon. Ownership requires a
    -- native response for the same spell.
    if candidate and spell == nil then collected, icon = nil, nil end
    if unique then
        name = atlas.getLocale() == "enUS" and unique.englishName or unique.name
        spell, icon, retryable = unique.spell, icon or unique.icon, true
    end
    -- An arbitrary requested ID without a native record must not subscribe
    -- that ID to future journal events. A later explicit request can try again.
    if requestedOnly and not mount and name == nil and spell == nil then return false end
    local previousOwned = collection.byID[id]
    local acquiring = pending[id] == true
    local identityReady = type(name) == "string" and name ~= "" and type(spell) == "number"
    local replaced = candidate and mount and spell ~= nil and mount.spell ~= spell
    if replaced and not identityReady then collected, icon = nil, nil end
    if retryable and not identityReady and not (mount and mount.journalName) then
        pendingIdentity[id] = true
    else
        pendingIdentity[id] = nil
    end
    local ownershipReady = type(collected) == "boolean" and (not acquiring or collected == true)
    local owned = previousOwned
    if replaced and identityReady then owned = nil end
    if ownershipReady then owned = collected end
    if owned == nil then owned = "unknown" end

    local sameIdentity = mount and mount.journalName == name and mount.spell == spell
    local indexed = sameIdentity and mount.indexed
    local rawSource
    if unique then
        rawSource = ""
    elseif identityReady and (retryable or indexed or excludedSpells[spell]) then
        local excludedEarly = excludedByIdentity(id, name, spell, owned == true)
        if not excludedEarly then
            if indexed then rawSource = mount.journalSourceRaw
            else rawSource = journalValue(select(3, C_MountJournal.GetMountInfoExtraByID(id))) end
        end
        if excludedEarly or (owned ~= true and excludedBySource(id, spell, rawSource)) then
            -- An unreleased entry can appear once its source arrives. Genuine
            -- non-collectible abilities and resolved placeholder IDs can stop.
            pending[id] = nil
            if not excludedSpells[spell] then
                if acquiring and not ownershipReady then pending[id] = true
                elseif not ownershipReady or not excludedEarly and rawSource == nil then pending[id] = false end
            end
            if not mount then return end
            known[id], collection.byID[id] = nil, nil
            batch.changed, batch.sourcesChanged = true, true
            if previousOwned ~= nil then
                changeCounts(collection, atlas.collectionCategory(mount), -1, previousOwned == true and -1 or 0)
            end
            if batch.added[id] == mount then batch.added[id] = nil
            else batch.removed[mount] = true end
            return
        end
    end

    if acquiring and owned ~= true then pending[id] = true
    elseif uniqueNative and not ownershipReady then pending[id] = false
    elseif retryable and not unique and (not identityReady or not ownershipReady or rawSource == nil) then pending[id] = false
    else pending[id] = nil end

    local previousExpansion = previousOwned ~= nil and mount and atlas.collectionCategory(mount)
    local changed = false
    if retryable and identityReady and not indexed and (rawSource ~= nil or not sameIdentity) then
        if not mount then
            mount = { id = id, journalOnly = true }
            known[id] = mount
            batch.added[id] = mount
        end
        if unique then
            mount.english = unique.englishName
            mount.expansion = unique.expansion
        elseif candidate then
            mount.english = name
            if replaced then mount.expansion, mount.icon = nil, nil end
        else
            mount.english = mount.english or atlas.englishNames[id] or name
        end
        indexJournalMount(mount, id, name, spell, category, rawSource)
        mount.journalName = name
        batch.sourcesChanged = true
        changed = true
    end
    if not mount then return end

    if icon ~= nil and mount.icon ~= icon then
        mount.icon, changed = icon, true
    end
    mount.unknownSourceNote = owned == false and mount.journalUnknownSourceNote or nil
    local expansion = atlas.collectionCategory(mount)
    if previousExpansion ~= expansion then
        if previousExpansion then
            changeCounts(collection, previousExpansion, -1, previousOwned == true and -1 or 0)
        end
        changeCounts(collection, expansion, 1, owned == true and 1 or 0)
        changed = true
    elseif previousOwned ~= owned then
        local collectedDelta = (owned == true and 1 or 0) - (previousOwned == true and 1 or 0)
        changeCounts(collection, expansion, 0, collectedDelta)
        changed = true
    end
    collection.byID[id] = owned
    if changed then batch.changed = true end
end

local function samplePending(ids)
    local batch = journalBatch(atlas.collection)
    for id in pairs(ids) do sampleMount(batch, id, true) end
    return publishJournal(batch)
end

local function notifyJournalChanged(changed)
    if changed and atlas.onJournalChanged then atlas.onJournalChanged() end
end

local function retryAcquisitions(acquisitions)
    if not next(acquisitions) then return end
    -- NEW_MOUNT_ADDED can arrive before ownership is readable. Allow one
    -- delayed read even when Blizzard's journal has no follow-up search event.
    C_Timer.After(.25, function()
        for id in pairs(acquisitions) do
            if pending[id] ~= true then acquisitions[id] = nil end
        end
        if next(acquisitions) then notifyJournalChanged(samplePending(acquisitions)) end
    end)
end

local draft, scan, scanTimer
local prepareRequested, retryBeforePublish = false, false
local initialRetryDelays, initialRetry = { .25, .75, 1.5, 3, 6 }, 0
local earlyAcquisitions = {}

local function scanCheckpoint(job)
    if not job.rows then return end
    job.rows = job.rows + 1
    if job.rows >= 32 or (job.deadline and debugprofilestop() >= job.deadline) then coroutine.yield() end
end

local function scanJournal(job)
    local ids = journalValue(C_MountJournal.GetMountIDs())
    if type(ids) ~= "table" or (canaccesstable and not canaccesstable(ids)) or not next(ids) then return false end

    local batch, sampled, complete = job.batch, {}, true
    for _, id in ipairs(ids) do
        id = journalValue(id)
        if not validMountID(id) then
            complete = false
        elseif not sampled[id] then
            sampled[id] = true
            sampleMount(batch, id, true)
        end
        scanCheckpoint(job)
    end
    -- Curated entries can exist outside the client's current membership.
    for id in pairs(uniqueMounts) do
        if not sampled[id] then
            sampled[id] = true
            sampleMount(batch, id, true)
        end
        scanCheckpoint(job)
    end
    for _, mount in ipairs(atlas.mounts) do
        local id = mount.id
        if not sampled[id] and known[id] == mount then
            sampled[id] = true
            sampleMount(batch, id, pending[id] == true)
        end
        scanCheckpoint(job)
    end
    local staged = {}
    for id in pairs(batch.added) do
        if not sampled[id] then staged[#staged + 1] = id end
    end
    for _, id in ipairs(staged) do
        sampled[id] = true
        sampleMount(batch, id, true)
        scanCheckpoint(job)
    end
    local retry, retryLoaded = {}, job.initial and retryBeforePublish
    retryBeforePublish = false
    for id, acquiring in pairs(pending) do
        if not sampled[id] then
            if acquiring or batch.added[id] then retry[#retry + 1] = id
            elseif complete then pending[id], pendingIdentity[id] = nil, nil end
        elseif retryLoaded and not acquiring then
            retry[#retry + 1] = id
        end
    end
    for _, id in ipairs(retry) do
        if pending[id] ~= nil then sampleMount(batch, id, true) end
        scanCheckpoint(job)
    end
    -- A mount acquired after its first sample must still be reflected in the
    -- initial snapshot. Swap each set before yielding so new events stay queued.
    while next(earlyAcquisitions) do
        local acquisitions = earlyAcquisitions
        earlyAcquisitions = {}
        for id in pairs(acquisitions) do
            if pending[id] == true then sampleMount(batch, id, true) end
            scanCheckpoint(job)
        end
    end
    return complete
end

local function advanceJournalScan(sliced)
    if not scan or scan.invalidated then
        local initial = atlas.collection == nil
        if initial and not draft then draft = journalBatch() end
        local job = { batch = initial and draft or journalBatch(atlas.collection), initial = initial }
        job.thread = coroutine.create(function() return scanJournal(job) end)
        scan = job
    end
    local job = scan
    job.rows = sliced and 0 or nil
    job.deadline = sliced and debugprofilestop and (debugprofilestop() + 4) or nil
    local ok, complete = coroutine.resume(job.thread)
    if not ok then
        scan = nil
        error(complete, 0)
    end
    if coroutine.status(job.thread) ~= "dead" then return false end
    scan = nil
    membershipReady = complete
    if job.initial and not complete then return false end
    local awaiting = job.initial and prepareRequested
    if job.initial then
        draft, prepareRequested, retryBeforePublish, initialRetry = nil, false, false, 0
    end
    local changed = publishJournal(job.batch)
    if job.initial then
        local acquisitions = {}
        for id, acquiring in pairs(pending) do
            if acquiring then acquisitions[id] = true end
        end
        retryAcquisitions(acquisitions)
    end
    if awaiting then notifyJournalChanged(changed) end
    return changed
end

local function scheduleInitialScan(delay)
    if scanTimer then return end
    local ticket = {}
    scanTimer = ticket
    C_Timer.After(delay, function()
        if scanTimer ~= ticket then return end
        scanTimer = nil
        advanceJournalScan(true)
        if scan then
            scheduleInitialScan(0)
        elseif not atlas.collection and initialRetryDelays[initialRetry + 1] then
            initialRetry = initialRetry + 1
            scheduleInitialScan(initialRetryDelays[initialRetry])
        end
    end)
end

function atlas.syncJournal()
    -- Consume the same scan if a synchronous caller needs the full catalog now.
    local changed = advanceJournalScan(false)
    if atlas.collection then scanTimer = nil end
    return changed
end

function atlas.ensureJournal()
    local changed = false
    if not membershipReady then
        changed = atlas.syncJournal()
    elseif next(pending) then
        changed = samplePending(pending)
    end
    return changed, membershipReady and not next(pendingIdentity)
end

function atlas.resolveJournalMount(id)
    id = journalValue(id)
    if not validMountID(id) then return end
    local mount = known[id]
    if mount and pending[id] == nil and (atlas.collection or mount.journalName) then return mount end
    local batch
    if atlas.collection then
        batch = journalBatch(atlas.collection)
    else
        if not draft then draft = journalBatch() end
        batch = draft
    end
    sampleMount(batch, id, true, pending[id] == nil)
    if atlas.collection then publishJournal(batch) end
    return known[id]
end

local acquired, retryPending, rescan, queued = {}, false, false, false
local function flushJournalEvents()
    local acquisitions, shouldRetry, shouldRescan = acquired, retryPending, rescan
    acquired, retryPending, rescan, queued = {}, false, false, false
    for id in pairs(acquisitions) do pending[id] = true end

    local changed
    if shouldRescan then changed = atlas.syncJournal()
    elseif shouldRetry then changed = atlas.ensureJournal()
    else changed = samplePending(acquisitions) end
    notifyJournalChanged(changed)

    for id in pairs(acquisitions) do
        if pending[id] ~= true then acquisitions[id] = nil end
    end
    retryAcquisitions(acquisitions)
end

local function queueJournalEvents()
    if queued then return end
    queued = true
    C_Timer.After(0, flushJournalEvents)
end

function atlas.prepareJournal()
    if atlas.collection then
        if not membershipReady or next(pending) then
            retryPending = true
            queueJournalEvents()
        end
        return true
    end
    if not draft then draft = journalBatch() end
    if not scan and not scanTimer then initialRetry = 0 end
    prepareRequested = true
    scheduleInitialScan(0)
    return false
end

local journalEvents = CreateFrame("Frame")
journalEvents:RegisterEvent("NEW_MOUNT_ADDED")
journalEvents:RegisterEvent("COMPANION_UNLEARNED")
journalEvents:RegisterEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
journalEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
journalEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
journalEvents:SetScript("OnEvent", function(_, event, value, reloadingUI)
    -- Keep the journal dormant until a consumer requests data.
    if not atlas.collection and not draft then return end
    value = journalValue(value)
    local reset = event == "PLAYER_ENTERING_WORLD" and (value == true or journalValue(reloadingUI) == true)
    if event == "COMPANION_UNLEARNED" then
        if value and value ~= "MOUNT" then return end
        reset = true
    end
    if not atlas.collection then
        if event == "NEW_MOUNT_ADDED" then
            if not validMountID(value) or pending[value] == true then return end
            pending[value], earlyAcquisitions[value] = true, true
        elseif reset and scan then
            -- A login or mount removal can change earlier samples in the draft.
            scan.invalidated = true
        else
            retryBeforePublish = true
        end
        if prepareRequested then scheduleInitialScan(0) end
        return
    end
    if event == "NEW_MOUNT_ADDED" then
        if not validMountID(value) or pending[value] == true or atlas.collection.byID[value] == true then return end
        acquired[value] = true
    elseif reset then
        rescan = true
    else
        -- The native search and filter controls also fire the search event.
        if membershipReady and not next(pending) then return end
        retryPending = true
    end
    queueJournalEvents()
end)
