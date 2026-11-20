local _, atlas = ...
local ui = {}
atlas.ui = ui
ui.ink = { .048, .092, .125 }
ui.panel = { .077, .131, .170 }
ui.active = { .11, .18, .21 }
ui.rule = { .24, .31, .32 }
ui.gold = { .92, .76, .44 }
ui.paper = { .918, .941, .957 }
ui.muted = { .635, .694, .737 }
ui.mint = { .63, .82, .73 }

-- Native tooltip fonts have narrower glyph coverage than bundled UI fonts.
-- Apply this only to our text, leaving Blizzard's item tooltip and fonts intact.
local approximateSymbol = "|TInterface\\AddOns\\PawAtlas\\Media\\Controls\\Approximate.tga:0:0|t"
function ui.safeText(value)
    if type(value) ~= "string" then return value end
    return (value:gsub("·", "/"):gsub("≈", approximateSymbol):gsub("›", ">"):gsub("‹", "<")
        :gsub("×", "x"):gsub("—", "-"):gsub("…", "..."))
end

-- Keep the source status readable even when the native icon is not rendered.
local unavailableTexture = "Interface\\RaidFrame\\ReadyCheck-NotReady"
function ui.unavailableText(text)
    if type(text) ~= "string" or text:find(unavailableTexture, 1, true) then return text end
    local status = atlas.L("Недоступно для получения")
    local icon = "|T" .. unavailableTexture .. ":16:16:0:0|t "
    if text:find("Недоступно для получения", 1, true) then
        text = text:gsub("Недоступно для получения", function() return icon .. status end)
    else
        text = text:gsub(status, function() return icon .. status end)
    end
    return text
end

function ui.tooltipTitle(text, ...)
    GameTooltip:SetText(ui.safeText(ui.unavailableText(text)), ...)
end

function ui.tooltipLine(text, ...)
    GameTooltip:AddLine(ui.safeText(ui.unavailableText(text)), ...)
end

function ui.coloredMountName(mount)
    return atlas.qualityText(atlas.displayMountName(mount), atlas.mountDisplayQuality(mount.id))
end

function ui.rewardText(name)
    return atlas.L("Награда") .. ": " .. name
end

local sourceTooltipLabels = {}
for _, label in ipairs({
    "Источник", "Добыча", "Босс", "Торговец", "Торговцы", "Место", "Зона", "Зоны", "Область",
    "Награда", "Фракция", "Репутация",
    "Ковенант", "Известность", "Цена", "Профессия", "Навык", "Требуется", "Режим",
    "Событие", "Особое событие", "Праздник", "Drop", "Zone", "Location", "Difficulty",
}) do
    sourceTooltipLabels[atlas.L(label)] = true
end
for _, label in ipairs({ "Задание", "Квест", "Локальное задание", "Задание гарнизона" }) do
    sourceTooltipLabels[atlas.L(label)] = "quest"
end
for _, format in ipairs({ "Был доступен: %s", "Условия: %s" }) do
    local label = atlas.L(format, ""):match("^([^:]+):")
    if label then sourceTooltipLabels[label] = true end
end

function ui.tooltipSourceText(text, color)
    if not text or text == "" then return end
    text = atlas.cardItemIcons(atlas.sourceInlineLinks(text))
    local r, g, b = unpack(color or ui.paper)
    local rewardLabel = atlas.L("Награда")
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local label = line:match("^([^:|]+):%s*%S")
        if label and sourceTooltipLabels[label] then
            local last = #label + 1
            local value = line:sub(last + 1)
            if sourceTooltipLabels[label] == "quest" and not value:find("|", 1, true) then
                value = "|cffffd200" .. value .. "|r"
            end
            line = "|cff9fddeb" .. line:sub(1, last) .. "|r" .. value
        end
        ui.tooltipLine(line ~= "" and line or " ", r, g, b, label == nil or label ~= rewardLabel)
    end
end

function ui.sourceAppearance(route)
    if route and route.requirement then return "Условие", "Scroll" end
    if route and route.historyLabel then return atlas.L("Было: %s", atlas.L(route.historyLabel)), route.icon end
    if route then
        local icon = route.key == "purchase" and route.subtype == "Внутриигровой магазин" and "Shop" or route.icon
        return route.subtype or route.label, icon
    end
    return nil, "Book"
end

function ui.sourceDate(label, value)
    local title, period = value:match("^(.*):%s+([^:]+)$")
    local styled = title and ("|cffebc270" .. title .. "|r: |cff9fddeb" .. period .. "|r")
        or ("|cff9fddeb" .. value .. "|r")
    local caption = atlas.L(label, "")
    return "|cffa2b1bc" .. caption:match("^%s*(.-)%s*$") .. "|r " .. styled
end

function ui.historicalSourceBody(mount, source)
    local detail = mount.availability
    local english = atlas.getLocale() == "enUS"
    local period = detail and ((english and detail.englishPeriod) or detail.period)
    local conditions = detail and ((english and detail.englishConditions) or detail.conditions)
    if source == atlas.L("Недоступно для получения") or source == "Недоступно для получения" then source = nil end
    local lines = {}
    if source and source ~= "" then lines[#lines + 1] = source end
    if conditions and conditions ~= source then lines[#lines + 1] = atlas.sourceItemLinks(conditions) end
    if period then lines[#lines + 1] = ui.sourceDate("Был доступен: %s", period) end
    return table.concat(lines, "\n")
end

function ui.compactSourceBody(source, route)
    if not route or source == "" then return source end
    local caption = route.subtype or route.label
    if not caption then return source end
    local trimmed = source:match("^%s*(.-)%s*$")
    local first, rest = trimmed:match("^([^\n]+)\n(.*)$")
    first = (first or trimmed):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    if route.key == "profession" then
        local profession = first:match("^Профессия:%s*(.+)$") or first:match("^Profession:%s*(.+)$")
        if profession then return rest and (profession .. "\n" .. rest) or profession end
    end
    local combinedShopLabel = route.stock ~= nil and caption == "Торговая лавка"
        and (first == "Торговая лавка / магазин" or first == "Trading Post / Shop")
    if combinedShopLabel or atlas.searchKey(first) == atlas.searchKey(caption)
        or atlas.searchKey(first) == atlas.searchKey(atlas.L(caption)) then return rest or "" end
    if route.state == "unknown" and not route.key and (trimmed == "Legacy" or trimmed == "Старинное") then return "" end
    return source
end

function ui.containerNameMatches(value, item)
    if not item or not value or value == "" then return false end
    local name = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local linked = name:match("^|Hitem:(%d+)[^|]*|h.-|h$")
    if linked then return tonumber(linked) == item.item end
    name = atlas.searchKey(name)
    return name == atlas.searchKey(item.name) or name == atlas.searchKey(item.englishName)
end

local containerLabels = { ["Источник"] = true, ["Добыча"] = true, ["Предмет"] = true,
    Source = true, Drop = true, Item = true }
function ui.containerSourceBody(body, item)
    local preserved = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^([^:]+):%s*(.+)$")
        if not ui.containerNameMatches(containerLabels[label] and value or line, item) then
            preserved[#preserved + 1] = line
        end
    end
    return table.concat(preserved, "\n"):match("^%s*(.-)%s*$")
end

local lootTargetLabels = { ["Источник"] = true, ["Добыча"] = true, ["Сокровище"] = true,
    Source = true, Drop = true, Treasure = true }
local lootPlaceLabels = { ["Место"] = true, ["Зона"] = true, ["Область"] = true,
    ["Локация"] = true, Location = true, Zone = true, Area = true }
local function sourceFieldText(value)
    return value and value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
end
local function passiveValue(value)
    value = sourceFieldText(value)
    if not value or value == "" or value == "—" or value:find("|", 1, true) then return end
    return atlas.displayName(value)
end
local function singlePlace(value)
    local name = passiveValue(value)
    if not name or name:find("[;\n]") or name:find(" · ", 1, true) or name:find(" / ", 1, true) then return end
    return name
end
function ui.sameDisplayedPlace(left, right)
    local name = singlePlace(left)
    return name ~= nil and name == singlePlace(right)
end
function ui.sameSourceAddress(left, right)
    local value = passiveValue(left)
    return value ~= nil and value == passiveValue(right)
end
function ui.singleSourcePlace(body)
    local name
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^%s*([^:]+):%s*(.+)$")
        if lootPlaceLabels[sourceFieldText(label)] then
            value = singlePlace(value)
            if not value or name and name ~= value then return end
            name = value
        end
    end
    return name
end
function ui.sourceAddress(source, place)
    local active = singlePlace(place)
    if not active then return end
    local both
    for line in (atlas.normalizeSource(source) .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^%s*([^:]+):%s*(.+)$")
        if lootPlaceLabels[sourceFieldText(label)] then
            if both then return end
            both = passiveValue(value)
            if not both then return end
        end
    end
    local first, second
    if both then first, second = both:match("^(.-) · (.-)$") end
    if not first or (active ~= singlePlace(first) and active ~= singlePlace(second)) then return end
    for _, pair in ipairs(atlas.sourceAddressParts or {}) do
        local english = atlas.getLocale() == "enUS"
        local parent = english and pair.englishParent or pair.parent
        local child = english and pair.englishChild or pair.child
        if (singlePlace(first) == parent and singlePlace(second) == child)
            or (singlePlace(first) == child and singlePlace(second) == parent) then
            return parent .. " · " .. child, both, pair.childMap
        end
    end
end
function ui.deduplicateSourceFields(body, place, covenant, addressSource)
    local preserved = {}
    local removed
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^%s*([^:]+):%s*(.+)$")
        label = sourceFieldText(label)
        local duplicate = lootPlaceLabels[label] and (ui.sameDisplayedPlace(value, place)
            or addressSource and passiveValue(value) == addressSource)
        if covenant and (label == "Ковенант" or label == "Covenant") then
            value = sourceFieldText(value)
            local sigil = "|T" .. covenant.texture .. ":16:16:0:0|t "
            if value:sub(1, #sigil) == sigil then value = value:sub(#sigil + 1) end
            local name = passiveValue(covenant.name)
            duplicate = name ~= nil and passiveValue(value) == name
        end
        if duplicate then removed = true else preserved[#preserved + 1] = line end
    end
    if not removed then return body end
    return table.concat(preserved, "\n"):gsub("\n%s*\n", "\n\n"):match("^%s*(.-)%s*$")
end
-- Russian journal captions use the genitive while the map shows the nominative.
local rareZoneNames = {
    ["зуламана"] = "Зул'Аман", ["харандара"] = "Харандар",
    ["бури бездны"] = "Буря Бездны", ["лесов вечной песни"] = "Леса Вечной Песни",
    ["спирального острова"] = "Спиральный остров",
}
local function coveredRareZone(value, placeName)
    if not value or not placeName then return false end
    local caption = atlas.searchKey(sourceFieldText(value))
    local zone = caption:match("^редкие существа (.+)$")
    zone = zone and rareZoneNames[zone] or caption:match("^(.+) rares$") or caption:match("^(.+) rare creatures$")
        or caption:match("^rares in (.+)$") or caption:match("^rare creatures in (.+)$")
    return zone and atlas.searchKey(zone) == atlas.searchKey(placeName)
end
function ui.structuredLootBody(body, targetName, placeName, points, isRare)
    local targets, places = {}, {}
    local function register(names, name)
        if not name or name == "" then return end
        names[atlas.searchKey(name)] = true
        names[atlas.searchKey(atlas.displayName(name))] = true
    end
    register(targets, targetName)
    register(places, placeName)
    for _, point in ipairs(points or {}) do
        register(targets, point.boss)
        register(targets, point.englishBoss)
        register(targets, atlas.journalNPCSourceNames and atlas.journalNPCSourceNames[point.npc])
        register(places, point.place)
        register(places, point.englishPlace)
    end
    local function covered(value, names)
        if not names or not value or value:find("|[HTA]") then return false end
        value = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        if names[atlas.searchKey(value)] then return true end
        value = value:gsub(" · ", ",")
        for name in value:gmatch("[^,]+") do
            if not names[atlas.searchKey(name)] then return false end
        end
        return value:find(",", 1, true) ~= nil and value:find("[^,%s]") ~= nil
    end
    local preserved = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^([^:]+):%s*(.+)$")
        local names = lootTargetLabels[label] and targets or lootPlaceLabels[label] and places
        local zoneCaption = isRare and targetName and targetName ~= "" and points and points[1]
            and lootTargetLabels[label] and coveredRareZone(value, placeName)
        if not zoneCaption and not covered(value, names) then preserved[#preserved + 1] = line end
    end
    return table.concat(preserved, "\n"):match("^%s*(.-)%s*$")
end

function ui.tradingPostDescription(offer, linkPrice)
    local label = offer.unknown and "Открой Торговую лавку, чтобы проверить ассортимент"
        or offer.frozen and "Заморожено у тебя"
        or offer.bonus and "Награда журнала путешественника" or "В продаже сейчас"
    local description = atlas.L(label)
    local formatDate = date or os and os.date
    if offer.expires and formatDate and GetServerTime then
        local timestamp = GetServerTime() + math.ceil(offer.expires - GetTime())
        local format = atlas.getLocale() == "enUS" and "%Y-%m-%d %H:%M" or "%d.%m.%Y %H:%M"
        description = description .. "\n" .. ui.sourceDate("Доступно до: %s", formatDate(format, timestamp))
    end
    if not offer.price then return description end
    local currency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(2032)
    local name = currency and currency.name
    local token = type(name) == "string" and name ~= "" and name or atlas.L("Торговый жетон")
    if linkPrice then
        local price = ("%s: %d |Hcurrency:2032|h[%s]|h"):format(atlas.L("Цена"), offer.price, token)
        return description, atlas.displaySourceText(price)
    end
    return description, atlas.L("Цена") .. ": " .. offer.price .. " " .. token
end

function ui.tooltipSourceAlternatives(mount, tradingPostShown)
    local detail = atlas.legacySourceDetails and atlas.legacySourceDetails(mount)
    local offer = not tradingPostShown and atlas.tradingPostOffer and atlas.tradingPostOffer(mount)
    if not detail and not offer then return end
    detail = detail or {}
    local english = atlas.getLocale() == "enUS"
    local alternatives = (english and detail.englishAlternatives) or detail.alternatives
    local previousStock = detail.tradingPost and not tradingPostShown
    if offer or previousStock or (alternatives and alternatives ~= "") then
        ui.tooltipLine(" ")
        ui.tooltipLine(atlas.L("Другие способы получения"), unpack(ui.gold))
        if alternatives and alternatives ~= "" then ui.tooltipSourceText(alternatives, ui.paper) end
        if offer then
            local description, price = ui.tradingPostDescription(offer)
            ui.tooltipSourceText(atlas.L("Торговая лавка") .. " · " .. description, offer.unknown and ui.muted or ui.paper)
            if price then ui.tooltipLine(price, unpack(ui.gold)) end
        elseif previousStock then
            ui.tooltipSourceText(atlas.L("Торговая лавка — появлялся в ассортименте. Ассортимент меняется"), ui.paper)
        end
    end
end

function ui.sourceHistory(mount)
    local former = mount.reviewedVendorOffer and mount.reviewedVendorOffer.formerAchievement
    if former then return atlas.L("Достижение") .. ": " .. atlas.dataName(former) end
    local detail = mount.availability or atlas.legacySourceDetails(mount)
    if not detail then return "" end
    local english = atlas.getLocale() == "enUS"
    local history = (english and detail.englishHistory) or detail.history
    local archive = ui.historicalSourceBody({ availability = detail }, nil)
    if not history or history == "" then return archive end
    return archive == "" and history or (archive .. "\n" .. history)
end

function ui.questChainLink(id, label)
    return atlas.sourceQuestReference(id, label)
end

local questChainLabels = { ["Квест"] = true, ["Задание"] = true, ["Локальное задание"] = true,
    Quest = true, ["World Quest"] = true }

local function questField(line)
    local label, value = line:match("^%s*([^:]+):%s*(.+)$")
    if not questChainLabels[label] then return end
    local actual = sourceFieldText(value)
    local id = actual:match("^|Hquest:(%d+)[^|]*|h[^|]*|h$")
    if id then return tonumber(id) end
    local title = actual:gsub("^%[(.-)%]$", "%1"):gsub('^"(.-)"$', "%1"):gsub("^«(.-)»$", "%1")
    return nil, title
end

function ui.withQuestRewards(body, reward)
    if not reward then return body end
    local start = reward.prerequisites and reward.prerequisites[1]
    if start then
        local link = atlas.sourceQuestReference(start.id, atlas.dataName(start))
        if link then
            local steps, names = {}, {}
            for _, quests in ipairs({ reward.prerequisites, reward.quests }) do
                for _, quest in ipairs(quests) do
                    steps[quest.id] = true
                    local title = atlas.dataName(quest)
                    if title then names[title] = true end
                end
            end
            local lines = { atlas.L("Начало цепочки") .. ": " .. link }
            for line in (body .. "\n"):gmatch("(.-)\n") do
                local id, title = questField(line)
                if line ~= "" and not (steps[id] or names[title]) then lines[#lines + 1] = line end
            end
            return table.concat(lines, "\n")
        end
    end
    local present, lines = {}, {}
    for id in body:gmatch("|Hquest:(%d+)") do present[tonumber(id)] = true end
    for _, quest in ipairs(reward.quests) do
        if not present[quest.id] then
            local link = atlas.sourceQuestReference(quest.id, atlas.dataName(quest))
            if link then
                lines[#lines + 1] = atlas.L("Задание") .. ": " .. link
                present[quest.id] = true
            end
        end
    end
    if #lines == 0 then return body end
    local first, rest = body:match("^([^\n]+)\n?(.*)$")
    if first and first:find("|Hquest:", 1, true) then
        table.insert(lines, 1, first)
        if rest ~= "" then lines[#lines + 1] = rest end
    elseif body ~= "" then
        lines[#lines + 1] = body
    end
    return table.concat(lines, "\n")
end
function ui.addRouteText(body, text)
    if not text or text == "" then return body end
    local seen, additions = {}, {}
    for line in (body .. "\n"):gmatch("(.-)\n") do seen[line] = true end
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line ~= "" and not seen[line] then additions[#additions + 1] = line; seen[line] = true end
    end
    if #additions == 0 then return body end
    return (body ~= "" and body .. "\n" or "") .. table.concat(additions, "\n")
end
function ui.withoutChainQuest(body, chain)
    local english = atlas.getLocale() == "enUS"
    local name = english and chain.englishName or chain.name
    local stage = chain.stageTitle and atlas.dataName(chain.stageTitle)
    local preserved = {}
    for line in (body .. "\n"):gmatch("(.-)\n") do
        local id, title = questField(line)
        local duplicate = title and (title == name or title == stage)
            or id and (id == chain.finalQuest or stage and atlas.questChainTitle(chain, id) == stage)
        if not duplicate then preserved[#preserved + 1] = line end
    end
    return table.concat(preserved, "\n"):match("^%s*(.-)%s*$")
end
function ui.questChainSummary(chain)
    local name = atlas.dataName(chain)
    return ui.questChainLink(chain.finalQuest, name) or name
end

local questStepStatus = { complete = "Выполнено", active = "В процессе", incomplete = "Не выполнено" }

function ui.questChainTooltip(chain, grant, hoveredQuestID, visibleNote, reward)
    local english = atlas.getLocale() == "enUS"
    local name = english and chain.englishName or chain.name
    if not reward then
        local rewardName = english and chain.englishRewardName or chain.rewardName
        reward = atlas.cardItemIcons(atlas.sourceItemReference(chain.reward, rewardName)):gsub("|H[^|]+|h(.-)|h", "%1")
    end
    local details = {}
    if hoveredQuestID ~= chain.finalQuest then
        details[#details + 1] = atlas.L("Финал цепочки: %s", "|cffffd200" .. name .. "|r")
    end
    local condition = english and grant.englishCondition or grant.condition and atlas.L(grant.condition)
    if condition and condition ~= visibleNote then details[#details + 1] = condition end
    local complete, total, _, _, states, finalCompleted = atlas.questChainProgress(chain, chain.stageTitle ~= nil)
    if complete > 0 then details[#details + 1] = atlas.L("Выполнено: %d / %d", complete, total) end
    if states then
        local prerequisite = chain.prerequisite
        local group = english and prerequisite.englishGroup or prerequisite.group
        details[#details + 1] = atlas.L("Требуется") .. ": " .. group .. " · |cffffd200" .. atlas.dataName(prerequisite) .. "|r"
        local title = atlas.dataName(chain.stageTitle)
        for index, id in ipairs(chain.quests) do
            if id ~= chain.finalQuest then
                local status = questStepStatus[finalCompleted and "complete" or states[id]]
                details[#details + 1] = ("%d. |cffffd200%s|r · %s"):format(index, title, status and atlas.L(status) or "—")
            end
        end
    end
    details[#details + 1] = ui.rewardText(reward)
    if hoveredQuestID and grant.pickupNote then
        details[#details + 1] = "|cffa2b1bc" .. atlas.L(grant.pickupNote) .. "|r"
    end
    return table.concat(details, "\n")
end

-- Displayed probability; low-to-high contrast against the dark card.
ui.chances = {
    { limit = 1, color = { .73, .76, .79 }, label = "До 1% включительно" },
    { limit = 5, color = { .48, .87, .63 }, label = "Свыше 1% и до 5%" },
    { limit = 20, color = { .51, .76, .99 }, label = "Свыше 5% и до 20%" },
    { limit = 60, color = { .78, .66, .99 }, label = "Свыше 20% и до 60%" },
    { limit = 100, color = { 1, .79, .36 }, label = "Свыше 60% и до 100%" },
}

ui.chanceFlavors = {
    "Приключение начинается", "Первый круг почёта", "Тропа уже знакома", "Босс уже узнаёт тебя",
    "Ещё один заход в копилку", "Полпути к легенде о терпении", "Здесь уже можно прописаться",
    "Местные считают тебя своим", "Терпение эпического качества", "Легендарное упорство",
}

function ui.probabilityText(fraction, guaranteed)
    if fraction == nil then return atlas.L("Неизвестен") end
    local percent = fraction * 100
    if percent == 0 then return "0 %" end
    if guaranteed then return "100 %" end
    -- Rounding and floating-point saturation must never imply a guaranteed drop.
    local russian = atlas.getLocale() == "ruRU"
    if percent >= 99.995 then return russian and "> 99,99 %" or "> 99.99 %" end
    if percent < .005 then return russian and "< 0,01 %" or "< 0.01 %" end
    local formatted = string.format("%.2f", percent):gsub("0+$", ""):gsub("%.$", "")
    if russian then formatted = formatted:gsub("%.", ",") end
    return "≈ " .. formatted .. " %"
end

function ui.place(object, parent, x, y, w, h)
    object:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    object:SetSize(w, h)
    return object
end

function ui.fill(parent, x, y, w, h, color)
    local tex = parent:CreateTexture(nil, "BACKGROUND")
    ui.place(tex, parent, x, y, w, h)
    tex:SetColorTexture(unpack(color))
    return tex
end

function ui.windowBorder(frame, w, h, trimScale)
    local bronze = { .48, .40, .28 }
    local bevel = { .22, .24, .24 }
    local scale = trimScale or 1
    local function pixels(value) return math.floor(value * scale + .5) end
    local function edge(start, endPoint, x1, y1, x2, y2)
        local texture = frame:CreateTexture(nil, "BACKGROUND")
        texture:SetPoint("TOPLEFT", frame, start, x1, y1)
        texture:SetPoint("BOTTOMRIGHT", frame, endPoint, x2, y2)
        texture:SetColorTexture(unpack(bronze))
    end
    edge("TOPLEFT", "TOPRIGHT", 0, 0, 0, -1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", 0, 1, 0, 0)
    edge("TOPLEFT", "BOTTOMLEFT", 0, -1, 1, 1)
    edge("TOPRIGHT", "BOTTOMRIGHT", -1, -1, 0, 1)
    for _, anchor in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local dx = anchor:find("LEFT") and 1 or -1
        local dy = anchor:find("TOP") and -1 or 1
        local function trim(x, y, width, height, color)
            local tex = frame:CreateTexture(nil, "BORDER")
            tex:SetPoint(anchor, frame, anchor, pixels(x) * dx, pixels(y) * dy)
            tex:SetSize(math.max(1, pixels(width)), math.max(1, pixels(height)))
            tex:SetColorTexture(unpack(color))
        end
        trim(0, 0, 32, 2, ui.gold)
        trim(0, 0, 2, 19, ui.gold)
        trim(4, 4, 17, 1, bronze)
        trim(4, 4, 1, 9, bronze)
        trim(7, 7, 3, 3, bevel)
        local ornament = frame:CreateTexture(nil, "BORDER")
        ornament:SetPoint(anchor, frame, anchor, 0, 0)
        ornament:SetSize(pixels(48), pixels(48))
        ornament:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\OrnateCorner.tga")
        ornament:SetTexCoord(dx == 1 and 0 or 1, dx == 1 and 1 or 0, dy == -1 and 0 or 1, dy == -1 and 1 or 0)
    end
end

function ui.journalWindowBackground(frame)
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints()
    background:SetColorTexture(1, 1, 1)
    background:SetGradient("VERTICAL", CreateColor(10 / 255, 22 / 255, 35 / 255), CreateColor(11 / 255, 25 / 255, 36 / 255))
end

function ui.journalPanel(frame, trimScale)
    local background = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    background:SetAllPoints()
    background:SetColorTexture(unpack(ui.ink))
    ui.windowBorder(frame, nil, nil, trimScale)
end

function ui.journalDialog(parent, name, width, height, closeOnOutside)
    local overlay = CreateFrame("Frame", name, parent)
    overlay:SetAllPoints(parent:GetParent())
    overlay:SetFrameLevel(parent:GetFrameLevel() + 60)
    overlay:SetToplevel(true)
    overlay:EnableMouse(true)
    overlay:EnableMouseWheel(true)
    local shade = overlay:CreateTexture(nil, "BACKGROUND")
    shade:SetPoint("TOPLEFT", overlay, "TOPLEFT", 1, -1)
    shade:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -1, 1)
    shade:SetColorTexture(.018, .036, .056, .72)
    if closeOnOutside then
        overlay:SetScript("OnMouseDown", function(self, button)
            if button == "LeftButton" then self:Hide() end
        end)
    end
    overlay:Hide()

    local dialog = CreateFrame("Frame", nil, overlay)
    dialog:SetPoint("CENTER", parent, "CENTER")
    dialog:SetSize(width, height)
    dialog:EnableMouse(true)
    dialog:SetFrameLevel(overlay:GetFrameLevel() + 1)
    ui.journalPanel(dialog, .52)
    if UISpecialFrames then table.insert(UISpecialFrames, name) end
    return overlay, dialog
end

function ui.text(parent, x, y, w, h, size, value, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.place(fs, parent, x, y, w, h)
    ui.setFont(fs, size)
    ui.bindText(fs)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetTextColor(unpack(color or ui.paper))
    fs:SetText(value)
    return fs
end

function ui.textTarget(text)
    local target = CreateFrame("Button", nil, text:GetParent())
    target:SetPoint("LEFT", text, "LEFT")
    target:RegisterForClicks("LeftButtonUp")
    target:EnableMouse(true)
    target:Hide()
    function target:updateBounds(visible, prefix)
        local width = text:GetStringWidth()
        if text:CanWordWrap() and text.GetWrappedWidth then width = text:GetWrappedWidth() or width end
        if prefix and prefix ~= text:GetText() then
            if not self.prefixMeasure then
                self.prefixMeasure = text:GetParent():CreateFontString(nil, "ARTWORK")
                self.prefixMeasure:Hide()
            end
            self.prefixMeasure:SetFont(text:GetFont())
            self.prefixMeasure:SetText(prefix)
            width = self.prefixMeasure:GetUnboundedStringWidth()
        end
        local height = text:GetStringHeight()
        self:SetSize(math.max(1, math.min(text:GetWidth(), width + 2)),
            math.max(1, math.min(text:GetHeight(), height + 2)))
        self:SetShown(visible and width > 0 and height > 0)
        if GameTooltip:IsOwned(self) and not self:IsMouseOver() then GameTooltip:Hide() end
    end
    return target
end

function ui.locationLink(text)
    local target = ui.textTarget(text)
    local function hide(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    target:SetScript("OnLeave", hide)
    target:SetScript("OnHide", hide)
    target:SetScript("OnEnter", function(self)
        if not self.mapID and not self.truncated then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local destination = self.mapID and atlas.mapName(self.mapID)
        local title = self.mapID and atlas.L("Открыть карту: %s", destination or self.locationText) or self.locationText
        ui.tooltipTitle(title, 1, 1, 1, 1, true)
        if destination and destination ~= self.locationText then ui.tooltipLine(self.locationText, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    target:SetScript("OnClick", function(self)
        if self.mapID then hide(self); atlas.openMap(self.mapID) end
    end)
    function target:setLocation(mapID, name, truncated, keepAction)
        if self.mapID ~= mapID or self.locationText ~= name then hide(self) end
        self.mapID, self.locationText, self.truncated = mapID, name, truncated
        self:updateBounds(name and name ~= "" and name ~= "—" and (mapID or truncated or keepAction), name)
    end
    return target
end

function ui.sourceWaypointPoints(points)
    local result, seen = {}, {}
    for _, point in ipairs(points or {}) do
        if point.navigation ~= false and atlas.hasSourceCoordinates(point) then
            local key = table.concat({ ("%d:%.17g:%.17g"):format(point.map, point.x, point.y),
                point.npc or "", point.quest or "", point.item or "", point.condition or "", point.englishCondition or "",
                point.kind == "caveEntrance" and point.kind or "" }, "\001")
            if not seen[key] then result[#result + 1], seen[key] = point, true end
        end
    end
    return result
end
function ui.waypointGroupSize(points)
    local count, seen = 0, {}
    for _, point in ipairs(points or {}) do
        if point.navigation ~= false and atlas.hasSourceCoordinates(point) then
            local key = ("%d:%.17g:%.17g"):format(point.map, point.x, point.y)
            if not seen[key] then seen[key], count = true, count + 1 end
        end
    end
    return count
end
function ui.waypointTooltip(point, points)
    ui.tooltipTitle(atlas.L("Поставить метку · %.1f, %.1f", point.x * 100, point.y * 100))
    if point.kind == "caveEntrance" then ui.tooltipLine(atlas.L("Вход в пещеру"), unpack(ui.gold)) end
    ui.tooltipLine(atlas.L("ЛКМ — поставить выбранную метку"))
    if ui.waypointGroupSize(points) > 1 then
        ui.tooltipLine(atlas.hasTomTomWaypoints() and atlas.L("ПКМ — поставить все метки") or atlas.bulkWaypointUnavailableText(),
            unpack(ui.muted))
    end
end

function ui.tooltipRareLocation(point)
    local note = point and atlas.rareEncounterNotes[point.npc]
    if note then
        local hint = atlas.getLocale() == "enUS" and note.englishHint or note.hint
        ui.tooltipSourceText(atlas.sourceInlineLinks(hint), ui.muted)
    end
end
function ui.waypointAction(mount, point, points, button)
    if button == "RightButton" then
        if atlas.hasTomTomWaypoints() and ui.waypointGroupSize(points) > 1 then
            return atlas.L("Метки поставлены: %d", atlas.addSourceWaypoints(points))
        end
    else
        return atlas.openSource(mount, point)
    end
end

function ui.waypointButton(parent, onClick, appendTooltip)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(108, 28)
    local pin = ui.icon(button, 13, 4, 20, "Place")
    pin:SetVertexColor(unpack(ui.gold))
    button.caption = ui.text(button, 0, 0, 0, 28, 14, "", ui.gold)
    button.caption:SetWordWrap(false)
    button.caption:SetMaxLines(1)
    function button:setCoordinates(text)
        self.caption:SetText(text)
        local gap = 2
        local width = math.ceil(self.caption:GetUnboundedStringWidth())
        -- The waypoint artwork has a transparent leading margin (7 of 32 texels).
        -- Centre the visible diamond and numbers together under the pager.
        local pinWidth = pin:GetWidth()
        local left = (self:GetWidth() - pinWidth - gap - width - pinWidth * 7 / 32) / 2
        pin:ClearAllPoints()
        pin:SetPoint("LEFT", self, "LEFT", left, 0)
        self.caption:ClearAllPoints()
        self.caption:SetPoint("LEFT", pin, "RIGHT", gap, 0)
        self.caption:SetSize(width, 28)
    end
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", onClick)
    function button:refreshTooltip()
        if not self.point then return end
        self.caption:SetTextColor(1, .91, .65)
        pin:SetVertexColor(1, .91, .65)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.waypointTooltip(self.point, self.points)
        if appendTooltip then appendTooltip(self.point) end
        GameTooltip:Show()
    end
    function button:clearTooltip()
        self.caption:SetTextColor(unpack(ui.gold))
        pin:SetVertexColor(unpack(ui.gold))
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    button:SetScript("OnEnter", button.refreshTooltip)
    button:SetScript("OnLeave", button.clearTooltip)
    button:SetScript("OnHide", button.clearTooltip)
    button:SetScript("OnDisable", button.clearTooltip)
    return button
end

function ui.button(parent, x, y, w, h, action)
    local btn = ui.place(CreateFrame("Button", nil, parent), parent, x, y, w, h)
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, .05)
    btn:SetHighlightTexture(hover)
    btn:SetScript("OnClick", action)
    return btn
end

local controls = "Interface\\AddOns\\PawAtlas\\Media\\Controls\\"
local nativeIcons = {
    Boss = { texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
    Rare = { atlas = "VignetteKill", texture = "Interface\\WorldMap\\Skull_64Grey" },
    Vendor = { texture = "Interface\\GossipFrame\\VendorGossipIcon" },
    Shop = { atlas = "UI-HUD-MicroMenu-Shop-Up", texture = "Interface\\Buttons\\UI-MicroButton-BStore-Up" },
    Raid = { atlas = "Raid", texture = "Interface\\Minimap\\Raid" },
    Dungeon = { atlas = "Dungeon", texture = "Interface\\Minimap\\Dungeon" },
    Place = { atlas = "Waypoint-MapPin-Untracked", texture = "Interface\\Minimap\\Minimap-Waypoint-MapPin-Untracked" },
    Chance = { texture = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    Achievement = { texture = "Interface\\AchievementFrame\\UI-Achievement-Shields-NoPoints", crop = { 0, 62/128, 0, 58/128 } },
    Quest = { texture = "Interface\\GossipFrame\\AvailableQuestIcon" },
    QuestGiver = { texture = "Interface\\GossipFrame\\GossipGossipIcon" },
    ObjectiveComplete = { atlas = "ui-questtracker-tracker-check", texture = "Interface\\RaidFrame\\ReadyCheck-Ready" },
    Lock = { texture = "Interface\\Buttons\\LockButton-Locked-Up", crop = { 6/32, 25/32, 6/32, 25/32 } },
    Unlock = { texture = "Interface\\Buttons\\LockButton-Unlocked-Up", crop = { 6/32, 25/32, 6/32, 25/32 } },
}

-- MapLegendFrame, QuestUtils, AchievementUI and the native loot-roll controls
-- provide these client assets. Built-in paths also cover an unavailable atlas.
function ui.setIcon(texture, name)
    local native = nativeIcons[name]
    texture:SetTexCoord(0, 1, 0, 1)
    if native then
        local available = native.atlas and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(native.atlas))
        if available then texture:SetAtlas(native.atlas, false)
        else
            texture:SetTexture(native.texture)
            if native.crop then texture:SetTexCoord(unpack(native.crop)) end
        end
    else texture:SetTexture(controls .. name .. ".tga") end
end

-- Nine slices keep the bevel and corners crisp at any panel size.
function ui.surface(parent, x, y, w, h, gold, asset)
    local textures = {}
    local sourceCard = asset == "SourceCard" or asset == "SourceInlay"
    local corner = math.min(sourceCard and 14 or 10, math.floor(math.min(w, h) / 3))
    local cut = sourceCard and 16/128 or 12/128
    local xs, ys = {0, corner, w - corner, w}, {0, corner, h - corner, h}
    local uv = {0, cut, 1-cut, 1}
    for row = 1, 3 do
        for col = 1, 3 do
            local tex = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
            ui.place(tex, parent, x + xs[col], y + ys[row], xs[col+1]-xs[col], ys[row+1]-ys[row])
            tex:SetTexture(controls .. (asset or (gold and "OrnateGold" or "OrnatePanel")) .. ".tga")
            tex:SetTexCoord(uv[col], uv[col+1], uv[row], uv[row+1])
            textures[#textures+1] = tex
        end
    end
    return textures
end

local sourceTints = {
    loot = { .44, .79, .50 }, Raid = { .40, .86, .48 }, Rare = { .24, .81, .64 },
    Dungeon = { .43, .76, .62 }, quest = { 1, .73, .21 }, achievement = { .30, .73, .96 },
    profession = { .77, .51, .94 }, purchase = { .64, .84, .32 }, history = { .57, .61, .66 },
    fishing = { .27, .74, .84 }, pvp = { .90, .39, .39 }, event = { .96, .57, .31 },
    progress = { .43, .71, .85 }, promotion = { .84, .51, .71 }, unknown = { .65, .66, .62 },
}

function ui.sourceCardSurface(parent, x, y, width, height)
    local face = ui.surface(parent, x, y, width, height, false, "SourceCard")
    local inlay = ui.surface(parent, x, y, width, height, false, "SourceInlay")
    for _, texture in ipairs(inlay) do texture:SetDrawLayer("BACKGROUND", 2) end
    local skin = {}
    function skin:setShown(shown)
        if self.shown == shown then return end
        self.shown = shown
        for i = 1, #face do
            face[i]:SetShown(shown)
            inlay[i]:SetShown(shown)
        end
    end
    function skin:setRoute(route, strength)
        local historical = route.state == "historical" or route.state == "unavailable"
        local tint = historical and sourceTints.history or sourceTints[route.icon] or sourceTints[route.key] or sourceTints.unknown
        strength = strength or 1
        if self.tint == tint and self.strength == strength then return end
        self.tint, self.strength = tint, strength
        for _, texture in ipairs(inlay) do texture:SetVertexColor(tint[1], tint[2], tint[3], strength) end
    end
    function skin:setHeight(newHeight)
        if height == newHeight then return end
        height = newHeight
        for _, slices in ipairs({ face, inlay }) do
            for col = 1, 3 do
                slices[3 + col]:SetHeight(height - 2*slices[col]:GetHeight())
                local bottom = slices[6 + col]
                bottom:ClearAllPoints()
                bottom:SetPoint("TOPLEFT", slices[3 + col], "BOTTOMLEFT")
            end
        end
    end
    return skin
end

local fieldTint = { .61, .70, .87 }

function ui.fieldSurface(parent, x, y, w, h)
    local textures = ui.surface(parent, x, y, w, h, true)
    for _, texture in ipairs(textures) do texture:SetVertexColor(unpack(fieldTint)) end
    return textures
end

-- Dropdowns sit above existing content and need an opaque, distinct surface.
function ui.dropdownSurface(parent)
    local textures = {}
    local background = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    background:SetAllPoints(parent)
    background:SetColorTexture(.055, .075, .105, 1)
    textures[1] = background
    for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local line = parent:CreateTexture(nil, "BORDER", nil, 1)
        line:SetColorTexture(.25, .32, .42, 1)
        if edge == "TOP" or edge == "BOTTOM" then
            line:SetPoint(edge .. "LEFT", parent, edge .. "LEFT", 0, 0)
            line:SetPoint(edge .. "RIGHT", parent, edge .. "RIGHT", 0, 0)
            line:SetHeight(1)
        else
            line:SetPoint("TOP" .. edge, parent, "TOP" .. edge, 0, 0)
            line:SetPoint("BOTTOM" .. edge, parent, "BOTTOM" .. edge, 0, 0)
            line:SetWidth(1)
        end
        textures[#textures + 1], textures[edge] = line, line
    end
    return textures
end

function ui.characterClassColor(record)
    local class = record and record.class
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return color and { color.r, color.g, color.b } or ui.paper
end

function ui.setCharacterClassIcon(texture, record)
    local coords = record and record.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[record.class]
    texture:SetTexture(coords and "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
        or "Interface\\Icons\\INV_Misc_QuestionMark")
    texture:SetTexCoord(unpack(coords or { 0, 1, 0, 1 }))
    texture:SetVertexColor(1, 1, 1)
end

-- The toast scales as a whole; a continuous texture avoids filtered slice seams.
function ui.rewardFrame(parent, x, y, w, h)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
    ui.place(texture, parent, x, y, w, h)
    texture:SetTexture(controls .. "CollectionRewardFrame.tga")
    texture:SetVertexColor(.76, .76, .76)
    -- Reuse the approved three-toed emblem instead of redrawing it in the frame.
    local emblemSize = math.floor(h * .226 + .5)
    local emblem = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    ui.place(emblem, parent, x + (w - emblemSize) / 2, y + 8, emblemSize, emblemSize)
    emblem:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Brand\\RewardPaw.tga")
    emblem:SetVertexColor(.85, .85, .85)
end

function ui.laurels(owner, x, y, width, height, branchWidth)
    for _, right in ipairs({ false, true }) do
        local branch = owner:CreateTexture(nil, "ARTWORK")
        ui.place(branch, owner, x + (right and width - branchWidth or 0), y, branchWidth, height)
        branch:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\CollectionLaurel.tga")
        if right then branch:SetTexCoord(1, 0, 0, 1) end
    end
end

function ui.icon(parent, x, y, size, name)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    ui.place(texture, parent, x, y, size, size)
    ui.setIcon(texture, name)
    return texture
end

function ui.squareIcon(parent, x, y, size, color)
    local border = ui.fill(parent, x, y, size, size, color or { .025, .035, .04, 1 })
    border:SetDrawLayer("ARTWORK", -1)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    -- Round both textures on the same pixel grid, including after scale changes.
    if border.SetRoundLayoutToNearestPixel then
        border:SetRoundLayoutToNearestPixel(true)
        icon:SetRoundLayoutToNearestPixel(true)
    end
    local inset = math.max(1, math.floor(size / 36 + .5))
    icon:SetPoint("TOPLEFT", border, "TOPLEFT", inset, -inset)
    icon:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -inset, inset)
    return icon, border
end

-- Square item artwork gets a thin slot rim, not the wide bevel of a panel.
function ui.itemIcon(parent, x, y, size)
    local slot = ui.place(CreateFrame("Frame", nil, parent), parent, x, y, size, size)
    ui.fill(slot, 0, 0, size, size, { .025, .035, .04, 1 })
    local rim = {}
    for _, edge in ipairs({ { 0, 0, size, 1 }, { 0, size - 1, size, 1 },
        { 0, 1, 1, size - 2 }, { size - 1, 1, 1, size - 2 } }) do
        local line = ui.fill(slot, edge[1], edge[2], edge[3], edge[4], ui.gold)
        line:SetDrawLayer("BORDER")
        rim[#rim + 1] = line
    end
    local icon = slot:CreateTexture(nil, "ARTWORK")
    ui.place(icon, slot, 3, 3, size - 6, size - 6)
    icon:SetTexCoord(.08, .92, .08, .92)
    return icon, rim, slot
end

-- Draw the chevron independently of the selected font's glyph coverage.
function ui.dropdownArrow(parent, x, y, size)
    local arrow = ui.place(CreateFrame("Frame", nil, parent), parent, x, y, size, size)
    local thickness = size <= 12 and 1 or 2
    local left = ui.fill(arrow, size * .15, size * .45, size * .4, thickness, ui.gold)
    local right = ui.fill(arrow, size * .4, size * .45, size * .4, thickness, ui.gold)
    left:SetDrawLayer("ARTWORK")
    right:SetDrawLayer("ARTWORK")
    left:SetRotation(-math.pi / 4)
    right:SetRotation(math.pi / 4)
    function arrow:SetColor(color)
        left:SetColorTexture(unpack(color)); right:SetColorTexture(unpack(color))
    end
    return arrow
end

function ui.brandIcon(parent, x, y, size)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    ui.place(texture, parent, x, y, size, size)
    texture:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Brand\\"
        .. (size <= 34 and "MountAtlasMinimap.tga" or "MountAtlasHeader.tga"))
    return texture
end

local buttonUV = { 0, 12/128, 1-12/128, 1 }
local function buttonStrips(parent, x, y, w, h, row, layer)
    local strips = {}
    local edge = math.min(10, math.floor(w / 3), math.floor(h / 3))
    local xs = { 0, edge, w-edge, w }
    for i = 1, 3 do
        local texture = parent:CreateTexture(nil, layer, nil, 1)
        ui.place(texture, parent, x + xs[i], y, xs[i+1] - xs[i], h)
        texture:SetTexture(controls .. "JournalButtons.tga")
        texture:SetTexCoord(buttonUV[i], buttonUV[i+1], row/8, (row+1)/8)
        strips[i] = texture
    end
    return strips
end
function ui.action(parent, x, y, w, h, label, icon, callback, field)
    local button = ui.place(CreateFrame("Button", nil, parent), parent, x, y, w, h)
    local compact = h <= 40
    local surface, glow
    if compact then
        surface = buttonStrips(button, 0, 0, w, h, 0, "BACKGROUND")
        glow = buttonStrips(button, -2, -2, w + 4, h + 4, 4, "BORDER")
    else
        surface = ui.surface(button, 0, 0, w, h)
        glow = ui.surface(button, -2, -2, w + 4, h + 4, true, "OrnateGlow")
        for _, texture in ipairs(glow) do texture:SetDrawLayer("BORDER") end
    end
    button:SetScript("OnClick", callback)
    local active, hovered, pressed = false, false, false
    local fieldStyle, dropdownStyle
    local function updateSurface()
        if dropdownStyle then
            dropdownStyle[1]:SetColorTexture(hovered and .075 or .055, hovered and .10 or .075, hovered and .14 or .105, 1)
            return
        end
        local highlight = hovered and button:IsEnabled()
        local row = ((field or active) and 2 or 0) + (highlight and 1 or 0)
        local tint = pressed and .85 or (field and active and 1.14 or 1)
        local color = fieldStyle or (field and fieldTint)
        for i, texture in ipairs(surface) do
            if compact then
                texture:SetTexCoord(buttonUV[i], buttonUV[i+1], row/8, (row+1)/8)
            else
                local name = ((field or active) and "OrnateGold" or "OrnatePanel") .. (highlight and "Hover" or "")
                texture:SetTexture(controls .. name .. ".tga")
            end
            if color then
                texture:SetVertexColor(color[1] * tint, color[2] * tint, color[3] * tint)
            else texture:SetVertexColor(tint, tint, tint) end
        end
        local light = button:IsEnabled() and not pressed and ((active or field) and (highlight and .85 or .45) or (highlight and .35 or 0)) or 0
        if fieldStyle and light > 0 then light = highlight and .35 or .15 end
        for _, texture in ipairs(glow) do texture:SetAlpha(light) end
        if button.glyph then button.glyph:SetVertexColor(unpack((active or highlight) and ui.gold or ui.paper)) end
        if button.caption then button.caption:SetTextColor(unpack((active or highlight) and ui.paper or ui.muted)) end
    end
    local function resetHover() hovered, pressed = false, false; updateSurface() end
    button:SetScript("OnEnter", function() hovered = true; updateSurface() end)
    button:SetScript("OnLeave", resetHover)
    button:SetScript("OnHide", resetHover)
    button:SetScript("OnDisable", resetHover)
    button:SetScript("OnEnable", resetHover)
    button:SetScript("OnMouseDown", function() pressed = button:IsEnabled(); updateSurface() end)
    button:SetScript("OnMouseUp", function() pressed = false; hovered = button:IsMouseOver(); updateSurface() end)
    if icon then
        local glyph = button:CreateTexture(nil, "OVERLAY")
        button.glyph = glyph
        ui.place(glyph, button, label and 10 or (w - 19) / 2, (h - 19) / 2, 19, 19)
        ui.setIcon(glyph, icon)
    end
    if label then
        local left = icon and 30 or 3
        button.caption = ui.text(button, left, 0, w - left - 3, h, 14, label)
        button.caption:SetJustifyH("CENTER")
    end
    function button:setActive(value)
        active = value
        updateSurface()
    end
    function button:setFieldStyle(color)
        fieldStyle = color
        for _, texture in ipairs(surface) do texture:SetDesaturated(color ~= nil) end
        for _, texture in ipairs(glow) do
            texture:SetDesaturated(color ~= nil)
            texture:SetVertexColor(unpack(color or { 1, 1, 1 }))
        end
        updateSurface()
    end
    function button:setDropdownStyle()
        if not dropdownStyle then
            for _, texture in ipairs(surface) do texture:Hide() end
            for _, texture in ipairs(glow) do texture:Hide() end
            dropdownStyle = ui.dropdownSurface(self)
        end
        updateSurface()
        return dropdownStyle
    end
    button:setActive(false)
    return button
end

function ui.tab(parent, x, y, w, h, label, icon, callback, glowScale)
    local tab = ui.place(CreateFrame("Button", nil, parent), parent, x, y, w, h)
    local glow = tab:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("BOTTOM", tab, "BOTTOM", 0, -5)
    glow:SetHeight(14)
    glow:SetTexture(controls .. "SoftGlow.tga")
    glow:SetVertexColor(1, .65, .20)
    local edge = ui.fill(tab, 3, h - 1, w - 6, 2, ui.gold)
    if label then
        tab.caption = ui.text(tab, 0, 0, w, h, 15, label)
        tab.caption:SetMaxLines(1)
        if not icon then tab.caption:SetJustifyH("CENTER") end
    end
    if icon then tab.glyph = ui.icon(tab, 0, 0, 18, icon) end
    function tab:setTabWidth(width)
        self:SetWidth(width)
        edge:SetWidth(width - 6)
        glow:SetWidth(width * .75)
        local inset = math.max(4, math.floor((width - 102) / 2))
        if self.glyph then
            self.glyph:ClearAllPoints()
            self.glyph:SetPoint("LEFT", self, "LEFT", label and inset or (width - 18) / 2, 0)
        end
        if self.caption then
            local left = icon and inset + 24 or 3
            self.caption:ClearAllPoints()
            self.caption:SetPoint("LEFT", self, "LEFT", left, 0)
            self.caption:SetWidth(width - left - 3)
        end
    end
    tab:setTabWidth(w)
    local active, hovered = false, false
    local function paint()
        glow:SetAlpha((active and .36 or hovered and .13 or 0) * (glowScale or 1))
        edge:SetAlpha(active and 1 or hovered and .35 or 0)
        if tab.glyph then tab.glyph:SetVertexColor(unpack((active or hovered) and ui.gold or ui.muted)) end
        if tab.caption then tab.caption:SetTextColor(unpack((active or hovered) and ui.paper or ui.muted)) end
    end
    function tab:setActive(value) active = value; paint() end
    tab:SetScript("OnClick", callback)
    tab:SetScript("OnEnter", function() hovered = true; paint() end)
    local function leave() hovered = false; paint() end
    tab:SetScript("OnLeave", leave)
    tab:SetScript("OnHide", leave)
    paint()
    return tab
end

function ui.dropdownField(button)
    local surface = button:setDropdownStyle()
    function button:SetJoined(joined) surface.BOTTOM:SetShown(not joined) end
    return surface
end

function ui.check(parent, x, y)
    local badge = parent:CreateTexture(nil, "OVERLAY")
    ui.place(badge, parent, x, y, 21, 21)
    ui.setIcon(badge, "ObjectiveComplete")
    badge:Hide()
    return badge
end

function ui.resetButton(parent, x, y, callback)
    local button = ui.place(CreateFrame("Button", nil, parent), parent, x, y, 32, 32)
    local icon = ui.icon(button, 4, 4, 24, "Reset")
    icon:SetAlpha(.8)
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function(self)
        icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(atlas.L("По умолчанию"))
        GameTooltip:Show()
    end)
    local function clearHover(self)
        icon:SetAlpha(.8)
        icon:SetVertexColor(1, 1, 1)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    button:SetScript("OnLeave", clearHover)
    button:SetScript("OnHide", clearHover)
    button:SetScript("OnDisable", clearHover)
    button:SetScript("OnMouseDown", function() icon:SetVertexColor(.7, .7, .7) end)
    button:SetScript("OnMouseUp", function() icon:SetVertexColor(1, 1, 1) end)
    return button
end
