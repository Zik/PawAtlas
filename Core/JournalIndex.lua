local _, atlas = ...
local kinds = {
    [0] = "Добыча", [1] = "Квест", [2] = "Торговец", [3] = "Профессия", [4] = "Битвы питомцев",
    [5] = "Достижение", [6] = "Событие", [7] = "Акция", [8] = "Карточная игра",
    [9] = "Магазин", [10] = "Исследование", [11] = "Торговая лавка",
}
local known, baseKeys = {}, {}
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
    for _, reward in ipairs((atlas.mountRewardItems or {})[id] or {}) do entry(reward) end
    for _, stage in pairs((atlas.attemptStages or {})[id] or {}) do entry(stage) end
    return table.concat(words, " ")
end
local function isPlaceholder(name)
    local upper = name:upper()
    for _, marker in ipairs({ "PH", "DND", "NYI" }) do
        if upper:find("[" .. marker .. "]", 1, true) or upper:match("%(" .. marker .. "[%s%)]") then return true end
    end
    return upper:match("^TEST MOUNT")
        or upper:match("^UNUSED[ _%-]") or upper:match("^UNUSED$")
end
local excludedSpells, unreleasedSpells = {}, {}
for _, spell in pairs(atlas.nonCollectibleMounts or {}) do excludedSpells[spell] = true end
for _, spell in pairs(atlas.unreleasedMounts or {}) do unreleasedSpells[spell] = true end
local function excluded(id, name, spell, collected, source)
    -- A changed live spell must not inherit the old MountID's exclusion.
    if excludedSpells[spell] or (not spell and (atlas.nonCollectibleMounts or {})[id]) then return true end
    -- Acquisition confirms a collectible, but cannot turn a known movement
    -- ability into one. Unreleased/placeholder metadata may become obsolete.
    if collected then return false end
    if unreleasedSpells[spell] or (not spell and (atlas.unreleasedMounts or {})[id]) then
        local liveSource = (source or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|n", " ")
            :match("^%s*(.-)%s*$")
        if liveSource == "" or liveSource == "Старинное" or liveSource == "Legacy" then return true end
    end
    -- Prefer the current localized name over a stale English [PH] entry.
    return isPlaceholder(name and name ~= "" and name or atlas.englishNames[id] or "")
end

function atlas.isExcludedJournalMount(id, name, spell, collected, source)
    if source == nil and unreleasedSpells[spell] and not collected and C_MountJournal
        and C_MountJournal.GetMountInfoExtraByID then
        source = select(3, C_MountJournal.GetMountInfoExtraByID(id))
        if issecretvalue and issecretvalue(source) then source = nil end
    end
    return excluded(id, name, spell, collected, source)
end

for index = #atlas.mounts, 1, -1 do
    local m = atlas.mounts[index]
    if excluded(m.id, m.name) then table.remove(atlas.mounts, index)
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
    ["Достижение"] = "Достижение", ["Профессия"] = "Профессия", ["Класс"] = "Класс",
    ["Событие"] = "Событие", ["Особое событие"] = "Событие", ["Праздник"] = "Событие",
    ["Промоакция"] = "Акция", ["PvP"] = "PvP",
    ["Drop"] = "Добыча", ["Source"] = "Добыча", ["Treasure"] = "Добыча", ["Vendor"] = "Торговец", ["Quest"] = "Квест",
    ["Achievement"] = "Достижение", ["Profession"] = "Профессия", ["Class"] = "Класс",
    ["Vendors"] = "Торговец", ["World Quest"] = "Квест", ["Garrison Mission"] = "Квест",
    ["Event"] = "Событие", ["World Event"] = "Событие", ["Special Event"] = "Событие", ["Holiday"] = "Событие",
    ["Promotion"] = "Акция",
}

local function sourceKind(source, category)
    if source == "Старинное" or source == "Legacy" then return "Журнал", true end
    local covenantOnly = false
    for line in source:gmatch("[^\n]+") do
        local bare = line:match("^%s*(.-)%s*$"):gsub("%.$", "")
        if bare == "Задание" or bare == "Квест" or bare == "Quest" then return "Квест", true end
        local label = line:match("^%s*([^:]+):")
        label = label and label:match("^%s*(.-)%s*$")
        local kind = label and sourceKinds[label]
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
    local stages = atlas.attemptStages and atlas.attemptStages[mount.id]
    local definition = stages and stages.reward
    if not reward or not definition or reward.item ~= definition.item or reward.scope ~= "raid"
        or not (definition.difficulties and definition.difficulties[reward.difficultyID])
        or not routeVersionCurrent(reward) then return end
    return reward
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
    local heading, value = line:match("^(.-):%s*(.-)%s*$")
    if not heading then return end
    local label = heading:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    if label == "" or label:find("|", 1, true) then return end
    if label == "Торгоец" then label = "Торговец" end -- Native ruRU vendor heading typo.
    -- A heading's closing color escape can follow its colon. Remove only that
    -- closing escape; links, textures and colors belonging to values stay intact.
    if heading:match("|c%x%x%x%x%x%x%x%x[^|]*$") then value = value:gsub("^|r%s*", "", 1) end
    return label, value
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
    local detail = atlas.journalSourceDetails and atlas.journalSourceDetails[id]
    if not detail or detail.spell ~= spell or detail.replacesKind ~= kind then return end
    if not detail.replacesSource then return detail end
    if source == nil then return end
    local normalized = atlas.normalizeSource(source)
    for _, expected in ipairs(detail.replacesSource) do
        if normalized == atlas.normalizeSource(expected) then return detail end
    end
end

local function sourcePanels(mount, source, kind)
    if not mount.journalOnly or (kind ~= "Добыча" and kind ~= "Рейд") then return end
    -- Source buttons cannot render/click rich inline payloads. Keep those in the
    -- hyperlink-enabled journal surface instead of flattening them into labels.
    if (mount.journalSourceOverride or mount.journalSourceRaw or ""):find("|[HTA]") then return end
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

function atlas.syncJournal()
    local added, rejected, collectedByID = {}, {}, {}
    for _, id in ipairs(C_MountJournal.GetMountIDs() or {}) do
        local mount = known[id]
        local name, spell, icon, _, _, category, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(id)
        if issecretvalue and issecretvalue(collected) then collected = nil end
        if issecretvalue and issecretvalue(icon) then icon = nil end
        local rawSource
        if unreleasedSpells[spell] and not collected then
            local _, _, source = C_MountJournal.GetMountInfoExtraByID(id)
            rawSource = source
        end
        if excluded(id, name, spell, collected, rawSource) then
            rejected[id], known[id] = true, nil
        elseif not mount or not mount.indexed then
            if name and name ~= "" then
                if rawSource == nil then
                    local _, _, source = C_MountJournal.GetMountInfoExtraByID(id)
                    rawSource = source
                end
                local source = plain(rawSource)
                local kind, explicitKind, covenantOnly = sourceKind(source, category)
                local vendorSource, vendorOffer
                if atlas.vendorTokenSource then
                    vendorSource, vendorOffer = atlas.vendorTokenSource({ id = id, spell = spell, journalSourceRaw = rawSource })
                end
                if vendorSource then source, kind, explicitKind = vendorSource, "Торговец", true end
                local detail = journalSourceDetail(id, spell, kind, rawSource ~= nil and source or nil)
                if detail then
                    kind, explicitKind = detail.kind, true
                    if detail.source then source = atlas.L(detail.source) end
                end
                local route = atlas.verifiedRewardDropRoute({ id = id })
                local raidReward = atlas.raidLootReward({ id = id })
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
                if not mount then
                    mount = { id = id, journalOnly = true, english = atlas.englishNames[id] or name }
                    known[id] = mount
                    added[#added + 1] = mount
                end
                if mount.journalOnly then
                    mount.name, mount.kind = name, kind
                    mount.boss = source:match("^[^:\n]+:%s*([^\n]+)") or kind
                    mount.place = source:match("Зона:%s*([^\n]+)") or source:match("Место:%s*([^\n]+)")
                        or source:match("Область:%s*([^\n]+)") or source:match("Zone:%s*([^\n]+)")
                        or source:match("Location:%s*([^\n]+)") or source:match("Area:%s*([^\n]+)") or kind
                end
                mount.spell = spell
                mount.availability = availability
                if availability then mount.kind = kind end
                mount.expansion = mount.expansion or atlas.mountExpansions[id]
                mount.covenantSourceOnly = covenantOnly and not explicitKind or nil
                mount.journalSourceRaw = rawSource or ""
                mount.vendorTokenOffer = vendorOffer
                mount.sourceOverride = sourceOverride
                mount.journalSourceOverride = (sourceOverride or (detail and detail.source) or availability or vendorOffer) and source or nil
                mount.unavailable = unavailable
                mount.journalSource = unavailable and "Недоступно для получения" or display(mount.journalSourceOverride or rawSource)
                mount.isRaid = raidSource(mount, source)
                mount.sourcePlaceKind = nil
                local sourceBoss, sourcePlace, panelKind, groups = sourcePanels(mount, source, kind)
                mount.hasSourcePanels = sourceBoss ~= nil
                mount.sourceKind = panelKind
                mount.sourceGroups = groups
                if sourceBoss then mount.boss, mount.place = sourceBoss, sourcePlace end
                mount.questFrequency = not legacy and atlas.questFrequencies[id] or nil
                local reward = atlas.attemptStages[id] and atlas.attemptStages[id].reward
                local trackedLoot = reward and reward.method ~= "SPECIAL"
                -- Hidden loot-lockout quests and world quests around a rare are
                -- not quest rewards. Actual quest starters keep their own flag.
                mount.hasQuest = not legacy and (mount.quest ~= nil or (not trackedLoot and
                    ((explicitKind and kind == "Квест") or source:find("Задание:", 1, true) ~= nil
                        or source:find("Quest:", 1, true) ~= nil)))
                local alternatives = {}
                for _, group in ipairs(groups or {}) do
                    alternatives[#alternatives + 1] = group.boss
                    alternatives[#alternatives + 1] = group.englishBoss or ""
                end
                mount.key = atlas.searchKey(table.concat({ baseKeys[id] or "", name, mount.english, kind, source, table.concat(alternatives, " "),
                    itemSearchWords(id) }, " "))
                -- The extra-info API may return nothing while data is unavailable.
                -- An empty source is valid, but nil must be retried on the next sync.
                mount.indexed = rawSource ~= nil
            end
        end
        if mount and not rejected[id] then
            mount.icon = icon or mount.icon
            if type(collected) == "boolean" then collectedByID[id] = collected
            else collectedByID[id] = "unknown" end
        end
    end
    -- Apply the same policy to curated and already indexed entries. Keep saved
    -- account data intact; only the visible catalog is being filtered.
    for index = #atlas.mounts, 1, -1 do
        if rejected[atlas.mounts[index].id] then table.remove(atlas.mounts, index) end
    end
    table.sort(added, function(a,b)
        if a.name == b.name then return a.id < b.id end
        return a.name < b.name
    end)
    for _, m in ipairs(added) do atlas.mounts[#atlas.mounts + 1] = m end
    -- Use the same ownership sample for the catalog and planner. A missing
    -- journal value is distinct from an explicitly uncollected mount.
    local collection = { byID = collectedByID, expansions = {}, collected = 0, total = #atlas.mounts }
    for _, mount in ipairs(atlas.mounts) do
        local owned = collectedByID[mount.id]
        if owned == nil then
            -- Curated mounts can be present before the journal list is ready.
            local _, _, icon, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mount.id)
            if not (issecretvalue and issecretvalue(icon)) then mount.icon = icon or mount.icon end
            if not (issecretvalue and issecretvalue(collected)) and type(collected) == "boolean" then
                owned = collected
                collectedByID[mount.id] = collected
            end
        end
        local expansion = atlas.collectionCategory(mount)
        local counts = collection.expansions[expansion]
        if not counts then
            counts = { collected = 0, total = 0 }
            collection.expansions[expansion] = counts
        end
        counts.total = counts.total + 1
        if owned == true then
            counts.collected = counts.collected + 1
            collection.collected = collection.collected + 1
        end
    end
    atlas.collection = collection
    if atlas.queuePlanBrokerRefresh then atlas.queuePlanBrokerRefresh() end
    if atlas.queueExpeditionTrackerRefresh then atlas.queueExpeditionTrackerRefresh() end
end
