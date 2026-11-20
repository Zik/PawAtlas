local _, atlas = ...

function atlas.reviewSaddlePurchase(id, spell, kind, source)
    local offer = (atlas.saddlePurchases or {})[id]
    if not offer or spell ~= offer.spell then return end
    if not offer.season then return kind == "Достижение" and offer or nil end
    if kind ~= "PvP" then return end
    local heading = source:match("^([^\n]+)")
    if heading == ("PvP: %s: Season %d"):format(offer.expansion, offer.season)
        or heading == ("PvP: %s, %d-й сезон"):format(offer.expansion, offer.season) then
        return offer
    end
end

local function saddleVendor(offer)
    local merchant = offer.merchant
    local english = atlas.getLocale() == "enUS"
    local saddle = english and "Vicious Saddle" or "Седло ярости"
    return {
        name = english and merchant.englishName or merchant.name,
        place = english and merchant.englishPlace or merchant.place,
        faction = offer.faction, npc = merchant.npc, map = merchant.map, x = merchant.x, y = merchant.y,
        conditions = ("%s: 1 {item:103533:%s}"):format(atlas.L("Цена"), saddle),
    }
end

function atlas.saddlePurchaseSource(offer)
    local vendor = saddleVendor(offer)
    return atlas.L("Торговец") .. ": " .. vendor.name .. "\n" .. atlas.L("Место") .. ": "
        .. vendor.place .. "\n" .. vendor.conditions
end

local function reviewedVendorConditions(offer)
    local english = atlas.getLocale() == "enUS"
    local price = offer.priceItem and ("%d %s"):format(offer.amount,
            atlas.sourceItemReference(offer.priceItem, english and offer.englishCurrencyName or offer.currencyName))
        or offer.gold and ("%d|TInterface\\MoneyFrame\\UI-GoldIcon.blp:0|t"):format(offer.gold)
        or ("%d |Hcurrency:%d|h[%s]|h"):format(offer.amount, offer.currency, english and offer.englishCurrencyName or offer.currencyName)
    if offer.offerings then
        price = price .. (" + %d |Hcurrency:1885|h[%s]|h"):format(offer.offerings,
            english and "Grateful Offering" or "Благодарственное подношение")
    end
    local lines = {}
    if offer.covenant then lines[#lines + 1] = atlas.covenantRenownSource(offer.covenant, offer.renown) end
    lines[#lines + 1] = atlas.L("Цена") .. ": " .. price
    local achievement = offer.achievement
    if achievement then
        lines[#lines + 1] = ("%s: |Hachievement:%d|h%s|h"):format(atlas.L("Достижение"), achievement.id, atlas.dataName(achievement))
    end
    if offer.condition then lines[#lines + 1] = english and offer.englishCondition or offer.condition end
    return table.concat(lines, "\n")
end

local function covenantVendorMatches(raw, offer)
    local covenant, vendor, zone
    for line in raw:gmatch("[^\n]+") do
        local label, value = line:match("^([^:]+):%s*(.+)$")
        if label == "Ковенант" or label == "Covenant" then
            if covenant then return end
            covenant = atlas.covenantSourceID(value)
            if covenant ~= offer.covenant then return end
        elseif label == "Торговец" or label == "Vendor" then
            if vendor then return end
            vendor = atlas.searchKey(value)
            local journalName = offer.journalVendorName and atlas.searchKey(offer.journalVendorName)
            if vendor ~= atlas.searchKey(offer.name) and vendor ~= atlas.searchKey(offer.englishName)
                and vendor ~= journalName then return end
        elseif label == "Место" then
            if zone then return end
            zone = atlas.searchKey(value)
            if zone ~= atlas.searchKey(offer.zone) and zone ~= atlas.searchKey(offer.englishZone)
                and zone ~= atlas.searchKey(offer.place) and zone ~= atlas.searchKey(offer.englishPlace) then return end
        elseif label == "Известность" or label == "Renown" then
            if tonumber(value) ~= offer.renown then return end
        elseif label ~= "Цена" and label ~= "Стоимость" and label ~= "Cost" and label ~= "Price" then return end
    end
    return covenant and (vendor or zone)
end

function atlas.reviewedVendorSource(mount)
    local offer = (atlas.reviewedVendorOffers or {})[mount.id]
    if not offer or offer.spell ~= mount.spell or type(mount.journalSourceRaw) ~= "string" then return end
    if offer.sinceInterface or offer.untilInterface then
        local interface = GetBuildInfo and select(4, GetBuildInfo())
        if (issecretvalue and issecretvalue(interface)) or type(interface) ~= "number"
            or offer.sinceInterface and interface < offer.sinceInterface
            or offer.untilInterface and interface >= offer.untilInterface then return end
    end
    local function normalized(value)
        return atlas.normalizeSource(value):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    end
    local raw, matches = normalized(mount.journalSourceRaw), false
    for _, native in ipairs(offer.native or {}) do
        if raw == normalized(native) then matches = true; break end
    end
    if offer.covenant then matches = covenantVendorMatches(raw, offer) end
    if not matches then return end
    local english = atlas.getLocale() == "enUS"
    local lines = {}
    for _, merchant in ipairs(offer.merchants or { offer }) do
        if #lines > 0 then lines[#lines + 1] = "" end
        lines[#lines + 1] = atlas.L("Торговец") .. ": " .. (english and merchant.englishName or merchant.name)
        lines[#lines + 1] = atlas.L("Место") .. ": " .. (english and merchant.englishPlace or merchant.place)
        if merchant.timewalking then
            lines[#lines + 1] = atlas.L("Событие") .. ": " .. atlas.L("Путешествия во времени") .. " · " .. merchant.timewalking
        end
        if offer.individualPrices then lines[#lines + 1] = reviewedVendorConditions(merchant) end
    end
    if not offer.individualPrices then
        if offer.merchants then lines[#lines + 1] = "" end
        lines[#lines + 1] = reviewedVendorConditions(offer)
    end
    return table.concat(lines, "\n"), offer
end

function atlas.extraCovenantPurchase(mount)
    local offer = (atlas.covenantPurchaseAlternatives or {})[mount.id]
    if not offer or mount.spell ~= offer.spell then return end
    local english = atlas.getLocale() == "enUS"
    return { name = atlas.dataName(offer), place = english and offer.englishPlace or offer.place,
        npc = offer.npc, map = offer.map, x = offer.x, y = offer.y, conditions = reviewedVendorConditions(offer) }
end

function atlas.extraSaddlePurchase(mount)
    local offer = mount and mount.saddlePurchase
    if offer and not offer.season then return saddleVendor(offer) end
end

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
        atlas.L(rule.condition), atlas.L(rule.expiry) }, "\n"), offer
end

local factionHeaders = { ["Орда"] = "Horde", ["Альянс"] = "Alliance", Horde = "Horde", Alliance = "Alliance" }
local vendorLabels = { ["Торговец"] = true, ["Торговцы"] = true, ["Продавец"] = true, Vendor = true, Vendors = true }
local priceLabels = { ["Цена"] = true, ["Стоимость"] = true, Cost = true, Price = true }
local placeLabels = { ["Место"] = true, ["Зона"] = true, ["Область"] = true, ["Зоны"] = true, Zone = true, Zones = true,
    Location = true, Area = true }
local sharedLabels = {
    ["Цена"] = true, ["Стоимость"] = true, ["Фракция"] = true, ["Репутация"] = true, ["Известность"] = true,
    ["Ковенант"] = true, ["Достижение"] = true, ["Событие"] = true, ["Праздник"] = true, ["Особое событие"] = true,
    Cost = true, Price = true, Faction = true, Reputation = true, Renown = true,
    Covenant = true, Achievement = true, Event = true, Holiday = true, ["World Event"] = true,
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

-- The mount journal names both dragon turtle vendors without faction headings.
-- https://www.wowhead.com/item=87797/reins-of-the-brown-dragon-turtle
local vendorFaction = { [66022] = "Horde", [65068] = "Alliance" }

local function addVendorWaypoints(mount, group)
    if group.waypoints or group.x then return end
    local route = mount.reviewedVendorOffer and mount.reviewedVendorOffer.waypointRoute or (atlas.journalVendorRoutes or {})[mount.id]
    if not route or mount.spell ~= route[1] then return end
    local name, place = atlas.searchKey(group.name), atlas.searchKey(group.place or "")
    if name == "" then return end
    for _, merchant in ipairs(atlas.questRewardVendors or {}) do
        if merchant.alternate and merchant.items[mount.id]
            and (name == atlas.searchKey(merchant.name) or name == atlas.searchKey(merchant.englishName)) then return end
    end
    for index = 2, #route do
        local row = atlas.journalVendorWaypoints[route[index]]
        if (name == atlas.searchKey(row[1]) and place == atlas.searchKey(row[3]))
            or (name == atlas.searchKey(row[2]) and place == atlas.searchKey(row[4])) then
            local points = {}
            for _, coords in ipairs(row[5]) do
                if not group.npc or group.npc == coords[1] then
                    local mapName = #row[5] > 1 and atlas.mapName and atlas.mapName(coords[2])
                    points[#points + 1] = { npc = coords[1], map = coords[2], x = coords[3], y = coords[4],
                        boss = atlas.getLocale() == "enUS" and coords[6] or coords[5], place = mapName or group.place }
                end
            end
            if #points == 1 then
                local point = points[1]
                group.npc, group.map, group.x, group.y = point.npc, point.map, point.x, point.y
                group.name = point.boss or group.name
            elseif #points > 1 then
                group.waypoints = points
            end
            return
        end
    end
end

-- The journal can omit extended costs. A live merchant quote is authoritative
-- only for that merchant and teaching item; never reuse it at another vendor.
local merchantPrices = {}
local function merchantNumber(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value >= 0 and value < math.huge
end

local function garrisonVendorPosition(route)
    if not UnitFactionGroup or UnitFactionGroup("player") ~= route.faction or not C_Garrison
        or not C_Garrison.GetGarrisonPlotsInstancesForMap or not C_Garrison.GetOwnedBuildingInfoAbbrev then return end
    local plots = C_Garrison.GetGarrisonPlotsInstancesForMap(route.map)
    if type(plots) ~= "table" then return end
    for _, plot in ipairs(plots) do
        if merchantNumber(plot.buildingPlotInstanceID) and plot.position and plot.position.GetXY then
            local building, _, _, _, _, constructing, _, _, canActivate = C_Garrison.GetOwnedBuildingInfoAbbrev(plot.buildingPlotInstanceID)
            if merchantNumber(building) and (building == 144 or building == 145)
                and constructing == false and canActivate == false then
                local x, y = plot.position:GetXY()
                if merchantNumber(x) and x <= 1 and merchantNumber(y) and y <= 1 then
                    return x, y
                end
            end
        end
    end
end

local function vendorIdentityMatches(value, localized, english)
    return localized and value == atlas.searchKey(localized) or english and value == atlas.searchKey(english)
end

local function correctVendorRoute(mount, group)
    local review = (atlas.journalVendorCorrections or {})[mount.id]
    if not review or review.spell ~= mount.spell then return end
    local name, place = atlas.searchKey(group.name), atlas.searchKey(group.place or "")
    local english = atlas.getLocale() == "enUS"
    for _, route in ipairs(review.variants or { review }) do
        local known = vendorIdentityMatches(name, route.name, route.englishName)
        local former = vendorIdentityMatches(name, route.formerName, route.formerEnglishName)
        local blankSeller = route.garrison and name == ""
        local current = vendorIdentityMatches(place, route.place, route.englishPlace) and (known or former or blankSeller)
        local obsolete = vendorIdentityMatches(place, route.formerPlace, route.formerEnglishPlace)
            and (former or (not route.formerName and known))
        if current or obsolete then
            group.name, group.place = english and route.englishName or route.name, english and route.englishPlace or route.place
            group.npc, group.map, group.faction = route.npc, route.map, route.faction or group.faction
            group.merchantIdentity = route.merchantIdentity
            if route.garrison then group.x, group.y = garrisonVendorPosition(route)
            else group.x, group.y = route.x, route.y end
            return route, english and review.englishEvent or review.event
        end
    end
end

local function merchantText(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "string" and value ~= ""
end
local function merchantTexture(value)
    return merchantText(value) or merchantNumber(value) and value > 0
end
local function merchantCostName(value)
    if merchantText(value) then
        return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            :gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
            :gsub("[%c|]", " "):match("^%s*(.-)%s*$")
    end
end
local function merchantCostText(texture, link, name)
    local kind, rawID
    if merchantText(link) then kind, rawID = link:match("|H(%a+):(%d+)[^|]*|h.-|h") end
    if kind == "item" or kind == "currency" then
        if not merchantTexture(texture) then
            local id = tonumber(rawID)
            if kind == "item" then
                texture = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
            elseif C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                local info = C_CurrencyInfo.GetCurrencyInfo(id)
                texture = info and info.iconFileID
            end
        end
        if merchantTexture(texture) then
            local icon = ("|h|T%s:18:18|t|h"):format(texture)
            return (link:gsub("|h.-|h", function() return icon end, 1))
        end
        return link
    end
    name = merchantCostName(name)
    if merchantTexture(texture) then
        local label = merchantText(name) and name or RETRIEVING_ITEM_INFO
        return ("|Hpawatlascost:0:%s|h|T%s:18:18|t|h"):format(label, texture)
    end
    if merchantText(name) then return name end
end
local function refreshMerchantPrices(_, event)
    if event == "GARRISON_BUILDING_ACTIVATED" or event == "GARRISON_BUILDING_PLACED"
        or event == "GARRISON_BUILDING_REMOVED" then
        if atlas.refreshSourceDetails then atlas.refreshSourceDetails() end
        return
    end
    merchantPrices = {}
    if event ~= "MERCHANT_CLOSED" and C_MerchantFrame and C_MerchantFrame.GetItemInfo
        and GetMerchantNumItems and GetMerchantItemID and C_MountJournal and C_MountJournal.GetMountFromItem then
        local vendor = UnitName and UnitName("npc")
        local guid = UnitGUID and UnitGUID("npc")
        local npc = merchantText(guid) and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
        local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local count = GetMerchantNumItems()
        if merchantText(vendor) and merchantNumber(count) then
            for index = 1, count do
                local item = GetMerchantItemID(index)
                local id = merchantNumber(item) and C_MountJournal.GetMountFromItem(item)
                local info = id and C_MerchantFrame.GetItemInfo(index)
                if info and merchantNumber(info.price) then
                    local costs, complete = {}, true
                    local coin = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString or GetCoinTextureString
                    if info.price > 0 then
                        if coin then costs[#costs + 1] = coin(info.price) else complete = false end
                    end
                    if info.hasExtendedCost then
                        local total = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index)
                        if not merchantNumber(total) or total < 1 or not GetMerchantItemCostItem then complete = false
                        else
                            for cost = 1, total do
                                local texture, amount, link, name = GetMerchantItemCostItem(index, cost)
                                local text = merchantNumber(amount) and amount > 0 and merchantCostText(texture, link, name)
                                if text then costs[#costs + 1] = amount .. " " .. text else complete = false end
                            end
                        end
                    end
                    if not complete then costs[#costs + 1] = RETRIEVING_ITEM_INFO end
                    if #costs > 0 then
                        local quote = { vendor = vendor, npc = npc, map = merchantNumber(map) and map or nil,
                            item = item, text = table.concat(costs, " + "), complete = complete }
                        local previous = merchantPrices[id]
                        if previous == nil then merchantPrices[id] = quote
                        elseif previous.item ~= item or previous.text ~= quote.text then merchantPrices[id] = { vendor = vendor } end
                    end
                end
            end
        end
    end
    if atlas.refreshSourceDetails then atlas.refreshSourceDetails() end
end
local merchantEvents = CreateFrame("Frame")
for _, event in ipairs({ "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED", "MERCHANT_FILTER_ITEM_UPDATE",
    "GARRISON_BUILDING_ACTIVATED", "GARRISON_BUILDING_PLACED", "GARRISON_BUILDING_REMOVED" }) do
    merchantEvents:RegisterEvent(event)
end
merchantEvents:SetScript("OnEvent", refreshMerchantPrices)

local function reviewedMissingPrices(mount)
    local review = (atlas.reviewedMissingMerchantPrices or {})[mount.id]
    if not review or review.spell ~= mount.spell or not merchantText(mount.journalSourceRaw) then return end
    local function normalized(source)
        return atlas.normalizeSource(source):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    end
    local source = normalized(mount.journalSourceRaw)
    for _, native in ipairs(review.native) do
        if source == normalized(native) then
            local prices = {}
            for _, seller in ipairs(review.prices) do
                prices[atlas.searchKey(seller.name)] = seller.price
                prices[atlas.searchKey(seller.englishName)] = seller.price
            end
            return prices
        end
    end
end

function atlas.merchantPriceSource(mount, source, vendor, ignoreLive)
    local quote = not ignoreLive and merchantPrices[mount.id]
    local reviewed = (atlas.reviewedMerchantPrices or {})[mount.id]
    if reviewed and reviewed.spell ~= mount.spell then reviewed = nil end
    local missingPrices = reviewedMissingPrices(mount)
    if not quote and not reviewed and not missingPrices then return source end
    local quotedVendor = quote and atlas.searchKey(quote.vendor)
    local reviewedVendor = reviewed and atlas.searchKey(reviewed.name)
    local reviewedEnglish = reviewed and atlas.searchKey(reviewed.englishName)
    local lines, seller = {}, vendor and atlas.searchKey(vendorName(vendor))
    local sellerPriced, explicitSeller
    local function finishSeller()
        if seller and not sellerPriced then
            local price
            if seller == quotedVendor then
                if quote.complete then price = quote.text end
            elseif missingPrices then
                price = missingPrices[seller]
            end
            if price then lines[#lines + 1] = atlas.L("Цена") .. ": " .. price end
        end
        seller, sellerPriced = nil, false
    end
    for line in (source ~= "" and source .. "\n" or ""):gmatch("(.-)\n") do
        local label, value = field(line)
        if vendorLabels[label] then
            if explicitSeller then finishSeller() end
            seller, sellerPriced, explicitSeller = atlas.searchKey(vendorName(value)), false, true
        elseif priceLabels[label] then
            sellerPriced = true
            if seller and seller == quotedVendor and quote.text then
                line = label .. ": " .. quote.text
            elseif reviewed and (seller == reviewedVendor or seller == reviewedEnglish)
                and value:lower() == reviewed.legacyPrice then
                line = label .. ": " .. reviewed.price
            end
        elseif factionHeader(line) or explicitSeller and line:match("^%s*$") then
            finishSeller()
        end
        lines[#lines + 1] = line
    end
    finishSeller()
    return table.concat(lines, "\n")
end

-- Standalone faction headings delimit alternatives, not purchase conditions.
-- Keep each block intact so a gift or quest is never lost beside a vendor.
function atlas.factionSources(mount)
    local source = atlas.normalizeSource(mount.journalSourceOverride or mount.journalSourceRaw or mount.journalSource or "")
    local groups, prefix, current = {}, {}, nil
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local faction = factionHeader(line)
        if faction then
            current = { id = mount.id, spell = mount.spell, faction = faction, factionRoute = true, lines = {},
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
            local kind = kinds[label] or atlas.isAchievementSourceLabel and atlas.isAchievementSourceLabel(label) and "Достижение"
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
        -- Some native prices keep the closing colour marker's r without its pipe.
        if priceLabels[label] and value:match("^r%d[%d%s,.]*|[HT]") then line = label .. ": " .. value:sub(2) end
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

local function matchingMerchantQuote(mount, groups)
    local quote = merchantPrices[mount.id]
    if not quote then return end
    local seller = atlas.searchKey(quote.vendor)
    local sole, exact, sellerCount, exactCount = nil, nil, 0, 0
    for _, group in ipairs(groups) do
        if atlas.searchKey(group.name) == seller then
            sole, sellerCount = group, sellerCount + 1
            if quote.npc and quote.npc == group.npc and quote.map and quote.map == group.map then
                exact, exactCount = group, exactCount + 1
            end
        end
    end
    if sellerCount == 1 then return sole end
    if exactCount == 1 then return exact end
end

local function vendorWaypoint(group)
    return { name = group.name, place = group.place, npc = group.npc, map = group.map,
        x = group.x, y = group.y, faction = group.faction, conditions = group.conditions,
        formerQuest = group.formerQuest, redemption = group.redemption, priceResolved = group.priceResolved }
end

local function groupVendorLocations(groups, terms)
    local offers = {}
    for _, group in ipairs(groups) do
        local offer
        local identity = group.merchantIdentity or group.npc
        local seller = atlas.searchKey(group.name)
        if identity and seller ~= "" and group.place and not group.waypoints then
            for _, candidate in ipairs(offers) do
                if (candidate.merchantIdentity or candidate.npc) == identity
                    and candidate.place and atlas.searchKey(candidate.name) == seller
                    and candidate.faction == group.faction and terms[candidate] == terms[group]
                    and candidate.redemption == group.redemption and candidate.formerQuest == group.formerQuest
                    and (not candidate.waypoints or candidate.groupedLocations) then
                    offer = candidate
                    break
                end
            end
        end
        if offer then
            if not offer.waypoints then
                offer.waypoints = { vendorWaypoint(offer) }
                offer.groupedLocations = true
                offer.merchantIdentity = identity
                offer.npc, offer.map, offer.x, offer.y = nil, nil, nil, nil
            end
            offer.waypoints[#offer.waypoints + 1] = vendorWaypoint(group)
        else
            offers[#offers + 1] = group
        end
    end
    return offers
end

-- Keep the journal's acquisition blocks intact. Vendor names and places are
-- separated for layout; every other field remains rich source text for the
-- existing reputation, money and hyperlink decorators.
function atlas.vendorSources(mount)
    local offer = mount.saddlePurchase
    if offer and offer.season then return { saddleVendor(offer) } end
    local tokenSource, tokenOffer = atlas.vendorTokenSource(mount)
    local source = atlas.normalizeSource(tokenSource
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
        local corrected, event = correctVendorRoute(mount, group)
        -- Shared requirements are explicit separate paragraphs, never copied
        -- from another vendor's individual price/reputation block.
        local lines = {}
        if event then lines[#lines + 1] = atlas.L("Событие") .. ": " .. event end
        for _, line in ipairs(shared) do lines[#lines + 1] = line end
        for _, line in ipairs(group.lines) do lines[#lines + 1] = line end
        if corrected and corrected.marksOfHonor then
            local price = ("+ %d|Hitem:137642|h|TInterface\\Icons\\Ability_PVP_GladiatorMedallion.BLP:0|t|h"):format(corrected.marksOfHonor)
            for index, line in ipairs(lines) do
                if priceLabels[field(line)] then
                    lines[index] = line:gsub("%+%s*[%d%s,.]+|Hcurrency:823|h.-|h", price)
                end
            end
        end
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
                group.redemption = "tcg"
                lines[1] = atlas.L("Нужен код награды коллекционной карточной игры WoW (TCG). Обмен у Ландро Дальнострела")
            end
        end
        group.conditions, group.lines = table.concat(lines, "\n"), nil
    end
    local reviewed = mount.reviewedVendorOffer
    if tokenOffer and #groups == 1 then
        local merchant = atlas.vendorTokenRules[tokenOffer.rule]
        local group = groups[1]
        group.npc, group.map, group.x, group.y = merchant.npc, merchant.map, merchant.x, merchant.y
    elseif reviewed then
        local merchants = reviewed.merchants or { reviewed }
        local english = atlas.getLocale() == "enUS"
        if #groups == #merchants then
            for index, group in ipairs(groups) do
                local merchant = merchants[index]
                local name = english and merchant.englishName or merchant.name
                if group.name == name then
                    group.npc, group.map, group.x, group.y = merchant.npc, merchant.map, merchant.x, merchant.y
                    group.faction = merchant.faction or group.faction
                    group.formerQuest = reviewed.formerQuest
                end
            end
        end
    end
    for _, group in ipairs(groups) do
        addVendorWaypoints(mount, group)
        group.faction = group.faction or vendorFaction[group.npc]
    end
    local quoteGroup = matchingMerchantQuote(mount, groups)
    local renown = (atlas.vendorRenownRequirements or {})[mount.id]
    local terms = {}
    for _, group in ipairs(groups) do
        -- A live quote belongs to one location and can vary with the character.
        terms[group] = group.conditions
        group.conditions = atlas.merchantPriceSource(mount, group.conditions, group.name, group ~= quoteGroup)
        group.priceResolved = true
        if renown and renown.spell == mount.spell then
            for _, seller in ipairs(renown.sellers) do
                if atlas.searchKey(group.name) == atlas.searchKey(seller) then
                    group.conditions = atlas.appendMajorRenown(group.conditions, renown)
                    break
                end
            end
        end
    end
    return groupVendorLocations(groups, terms)
end

function atlas.vendorAchievementRequirements(mount)
    local requirements, seen = {}, {}
    for _, view in ipairs(atlas.factionSources(mount) or { mount }) do
        for _, vendor in ipairs(atlas.vendorSources(view) or {}) do
            for line in (vendor.conditions .. "\n"):gmatch("(.-)\n") do
                local label, value = field(line)
                if atlas.isAchievementSourceLabel(label) and value ~= "" then
                    local id = tonumber(value:match("|Hachievement:(%d+)"))
                    local faction = vendor.faction or view.faction
                    local key = (faction or "") .. ":" .. (id or value)
                    if not seen[key] then
                        seen[key] = true
                        requirements[#requirements + 1] = { text = line, faction = faction, purchase = true }
                    end
                end
            end
        end
    end
    return requirements
end
