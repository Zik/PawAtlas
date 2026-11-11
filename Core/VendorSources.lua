local _, atlas = ...

-- Exact reviewed offer identities supplement incomplete journal entries. New
-- live sources and later seasons retain their native journal data for review.
function atlas.vendorTokenSource(mount)
    local offer = mount and atlas.vendorTokenOffers and atlas.vendorTokenOffers[mount.id]
    local rule = offer and atlas.vendorTokenRules and atlas.vendorTokenRules[offer.rule]
    if not offer or not rule or mount.spell ~= offer.spell or not GetBuildInfo then return end
    local ok, _, _, _, interface = pcall(GetBuildInfo)
    if not ok or (issecretvalue and issecretvalue(interface)) or type(interface) ~= "number"
        or interface < rule.sinceInterface or interface >= rule.untilInterface then return end
    local function normalized(text)
        return atlas.normalizeSource(text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            :match("^%s*(.-)%s*$")
    end
    local source = normalized(mount.journalSourceRaw)
    if source ~= normalized(offer.journalSource) and source ~= normalized(offer.englishJournalSource) then return end
    local english = atlas.getLocale() == "enUS"
    local vendor = english and rule.englishVendor or rule.vendor
    local place = english and rule.englishPlace or rule.place
    local item = english and rule.englishName or rule.name
    local itemLink = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(rule.item))
    if type(itemLink) ~= "string" or itemLink == "" then
        -- Gold denotes an interactive source link, not an assumed item quality.
        itemLink = "|cffffd200|Hitem:" .. rule.item .. "|h[" .. item .. "]|h|r"
    end
    local achievement = english and rule.englishAchievementName or rule.achievementName
    return table.concat({ atlas.L("Торговец") .. ": " .. vendor,
        atlas.L("Место") .. ": " .. place,
        atlas.L("Цена") .. ": " .. rule.amount .. " " .. itemLink,
        atlas.L("Достижение") .. ": |Hachievement:" .. rule.achievement .. "|h" .. achievement .. "|h",
        atlas.L("Условие") .. ": " .. atlas.L(rule.condition),
        atlas.L("Условие") .. ": " .. atlas.L(rule.expiry) }, "\n"), offer
end

local factionHeaders = { ["Орда"] = "Horde", ["Альянс"] = "Alliance", Horde = "Horde", Alliance = "Alliance" }
local vendorLabels = { ["Торговец"] = true, ["Торговцы"] = true, ["Продавец"] = true, Vendor = true, Vendors = true }
local placeLabels = { ["Место"] = true, ["Зона"] = true, ["Область"] = true, ["Зоны"] = true, Zone = true, Location = true, Area = true }
local sharedLabels = {
    ["Цена"] = true, ["Стоимость"] = true, ["Фракция"] = true, ["Репутация"] = true, ["Известность"] = true,
    ["Ковенант"] = true, ["Достижение"] = true, ["Событие"] = true, ["Праздник"] = true, ["Особое событие"] = true,
    Cost = true, Price = true, Faction = true, Reputation = true, Renown = true,
    Covenant = true, Achievement = true, Event = true, Holiday = true,
}

local function field(line)
    local label, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
    return label and label:match("^%s*(.-)%s*$"), value
end

local function factionHeader(line)
    local text = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    return factionHeaders[text]
end

local function vendorName(value)
    local name, suffix = value:match("^(.-)%s*%(([^()]*)%)%s*$")
    local faction = suffix and factionHeader(suffix)
    return faction and name:match("^%s*(.-)%s*$") or value, faction
end

-- Standalone faction headings delimit alternatives, not purchase conditions.
-- Keep each block intact so a gift or quest is never lost beside a vendor.
function atlas.factionSources(mount)
    local source = atlas.normalizeSource(mount.journalSourceOverride or mount.journalSourceRaw or mount.journalSource or "")
    local groups, prefix, current = {}, {}, nil
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local faction = factionHeader(line)
        if faction then
            current = { id = mount.id, faction = faction, factionRoute = true, lines = {},
                journalOnly = true, difficultyLocalOnly = true, trackingCompatible = false }
            groups[#groups + 1] = current
            for _, text in ipairs(prefix) do current.lines[#current.lines + 1] = text end
        elseif current then current.lines[#current.lines + 1] = line
        else prefix[#prefix + 1] = line end
    end
    if #groups == 0 then return end
    local kinds = { ["Задание"] = "Квест", ["Квест"] = "Квест", Quest = "Квест",
        ["Локальное задание"] = "Квест", ["World Quest"] = "Квест",
        ["Достижение"] = "Достижение", Achievement = "Достижение",
        ["Предмет"] = "Добыча", Item = "Добыча", ["Источник"] = "Добыча", Source = "Добыча", ["Добыча"] = "Добыча", Drop = "Добыча" }
    for _, group in ipairs(groups) do
        local priority = 0
        for _, line in ipairs(group.lines) do
            local label, value = field(line)
            local kind = kinds[label]
            if kind and value ~= "" then
                local rank = kind == "Квест" and 3 or (label == "Источник" or label == "Source") and 1 or 2
                if rank > priority then group.boss, group.sourceKind, priority = value, kind, rank end
            elseif placeLabels[label] and value ~= "" then
                group.place = group.place and (group.place .. " · " .. value) or value
            end
        end
        group.journalSourceRaw = table.concat(group.lines, "\n"):match("^%s*(.-)%s*$")
        if group.journalSourceRaw == "" then return end
        group.kind = group.sourceKind or mount.kind
        group.sourceKind = group.kind
        group.place, group.lines = group.place or "—", nil
    end
    return groups
end

local function add(group, line)
    local label, value = field(line)
    if placeLabels[label] and value ~= "" then
        group.place = group.place and (group.place .. " · " .. value) or value
    else
        group.lines[#group.lines + 1] = line
    end
end

local function sharedParagraph(lines)
    for _, line in ipairs(lines) do
        local label = field(line)
        if not sharedLabels[label] then return false end
    end
    return true
end

-- Keep the journal's acquisition blocks intact. Vendor names and places are
-- separated for layout; every other field remains rich source text for the
-- existing reputation, money and hyperlink decorators.
function atlas.vendorSources(mount)
    local source = atlas.normalizeSource(atlas.vendorTokenSource(mount)
        or mount.journalSourceOverride or mount.journalSourceRaw or mount.journalSource or "")
    local paragraphs, paragraph = {}, { lines = {}, vendors = 0 }
    local firstVendor, lastVendor
    local function flush()
        if #paragraph.lines == 0 then return end
        paragraphs[#paragraphs + 1] = paragraph
        if paragraph.vendors > 0 then
            firstVendor = firstVendor or #paragraphs
            lastVendor = #paragraphs
        end
        paragraph = { lines = {}, vendors = 0 }
    end
    for line in (source .. "\n"):gmatch("(.-)\n") do
        if line:match("%S") then
            paragraph.lines[#paragraph.lines + 1] = line
            if vendorLabels[field(line)] then paragraph.vendors = paragraph.vendors + 1 end
        else flush() end
    end
    flush()
    if not firstVendor then return end

    local groups, shared, pending = {}, {}, {}
    for index, block in ipairs(paragraphs) do
        if block.vendors == 0 then
            if (index < firstVendor or index > lastVendor) and sharedParagraph(block.lines) then
                for _, line in ipairs(block.lines) do shared[#shared + 1] = line end
            elseif index < lastVendor then
                -- A separated covenant/faction/location prefix belongs to the
                -- following vendor, not to the previous vendor's price.
                for _, line in ipairs(block.lines) do pending[#pending + 1] = line end
            else
                -- A gift, drop or other independent alternative after a vendor
                -- is not a purchase requirement. Let the full source render it.
                return
            end
        else
            local current
            for _, line in ipairs(block.lines) do
                local label, value = field(line)
                if vendorLabels[label] then
                    local name, faction = vendorName(value)
                    current = { name = name, faction = mount.faction or faction, lines = {} }
                    for _, prefix in ipairs(pending) do add(current, prefix) end
                    pending = {}
                    groups[#groups + 1] = current
                elseif current then add(current, line)
                else pending[#pending + 1] = line end
            end
        end
    end
    for _, group in ipairs(groups) do
        -- Shared requirements are explicit separate paragraphs, never copied
        -- from another vendor's individual price/reputation block.
        local lines = {}
        for _, line in ipairs(shared) do lines[#lines + 1] = line end
        for _, line in ipairs(group.lines) do lines[#lines + 1] = line end
        -- Landro's Booty Bay route redeems a TCG code, not a normal gold price.
        -- Other appearances of the NPC (events/vendors) keep their own terms.
        -- https://www.wowhead.com/guide/vanity-collections/obtaining-trading-card-loot
        local name = atlas.searchKey(group.name or "")
        local place = atlas.searchKey(group.place or "")
        if (name == atlas.searchKey("Ландро Дальнострел") or name == "landro longshot")
            and (place == atlas.searchKey("Пиратская Бухта") or place == "booty bay") then
            if mount.id == 371 and mount.spell == 74856 and #groups == 1 and #lines == 1 then
                -- The journal lists the separate Trading Post source without terms.
                local bare = lines[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
                if bare == "Trading Post" or bare == "Торговая лавка" then lines[1] = nil end
            end
            if #lines == 0 then
                lines[1] = atlas.L("Нужен код награды коллекционной карточной игры WoW (TCG). Обмен у Ландро Дальнострела")
            end
        end
        group.conditions, group.lines = table.concat(lines, "\n"), nil
    end
    return groups
end
