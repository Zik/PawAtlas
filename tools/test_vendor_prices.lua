-- Run from PawAtlas: lua5.1 tools/test_vendor_prices.lua
assert(_VERSION == "Lua 5.1")
local frames, merchant, vendor = {}, {}, "Trellis Morningsun"
local language = "enUS"
RETRIEVING_ITEM_INFO = "Retrieving item information"
function CreateFrame()
    local frame = { RegisterEvent = function() end, SetScript = function(self, _, callback) self.callback = callback end }
    frames[#frames + 1] = frame
    return frame
end
function UnitName() return vendor end
function GetMerchantNumItems() return #merchant end
function GetMerchantItemID(index) return merchant[index].item end
function GetMerchantItemCostInfo(index) return merchant[index].count or #merchant[index].costs end
function GetMerchantItemCostItem(index, cost) return unpack(merchant[index].costs[cost], 1, 4) end
C_CurrencyInfo = { GetCoinTextureString = function(price) return (price / 10000).."|TInterface\\MoneyFrame\\UI-GoldIcon:16|t" end }
C_MerchantFrame = { GetItemInfo = function(index) return merchant[index].info end }
local mountsByItem = { [46751] = 320, [19029] = 108, [19030] = 109 }
C_MountJournal = { GetMountFromItem = function(item) return mountsByItem[item] end }
local atlas = {
    normalizeSource = function(value) return value end,
    searchKey = function(value) return value:lower() end,
    L = function(value) return value end,
    displayName = function(value) return value end,
    getLocale = function() return language end,
}
assert(loadfile("Core/VendorSources.lua"))("PawAtlas", atlas)
local mount = { id=320, spell=65639, journalSourceRaw="Vendor: Trellis Morningsun\nZone: Icecrown\nCost: 500|TInterface\\MoneyFrame\\UI-GoldIcon:16|t\n\n"
    .."Vendor: Other merchant\nZone: Somewhere\nCost: 500|TInterface\\MoneyFrame\\UI-GoldIcon:16|t" }
local function refresh(event) frames[1].callback(nil, event or "MERCHANT_UPDATE") end
local function contains(value, text) assert(value:find(text,1,true), text.." missing from "..value) end
local currencyLink = "|cff00ccff|Hcurrency:241:17|h[Champion's Seal]|h|r"
local itemLink = "|cff0070dd|Hitem:888:0:1|h[Trade item]|h|r"
merchant = {{ item=46751, info={price=4000000,hasExtendedCost=true}, costs={
    {123,5,currencyLink},
    {124,3,itemLink},
    {125,2,"|Hcurrency:999|h[Second currency]|h"},
    {126,7,nil,"|cffffffffUnidentified currency: test|r"},
    {129,8},
} }}
refresh("MERCHANT_SHOW")
local groups = atlas.vendorSources(mount)
contains(groups[1].conditions,"400|T")
contains(groups[1].conditions,"5 |cff00ccff|Hcurrency:241:17|h|T123:18:18|t|h|r")
contains(groups[1].conditions,"3 |cff0070dd|Hitem:888:0:1|h|T124:18:18|t|h|r")
contains(groups[1].conditions,"2 |Hcurrency:999|")
contains(groups[1].conditions,"7 |Hpawatlascost:0:Unidentified currency: test|h|T126:18:18|t|h")
contains(groups[1].conditions,"8 |Hpawatlascost:0:" .. RETRIEVING_ITEM_INFO .. "|h|T129:18:18|t|h")
contains(groups[2].conditions,"500|T")
assert(not groups[2].conditions:find("currency:",1,true), "another vendor inherits the quote")
local missingPrice = { id = mount.id, spell = mount.spell,
    journalSourceRaw = "Vendor: Trellis Morningsun\nZone: Icecrown\nReputation: Exalted\n"
        .. "Vendor: Other merchant\nZone: Somewhere\nReputation: Friendly\n\nHorde\nQuest: Other route" }
local missingPriceJournal = missingPrice.journalSourceRaw
local liveText = "Цена: 400|T"
local rawPrice = atlas.merchantPriceSource(missingPrice, missingPrice.journalSourceRaw)
contains(rawPrice, "Reputation: Exalted\n" .. liveText)
contains(rawPrice, "\nVendor: Other merchant\nZone: Somewhere\nReputation: Friendly\n\nHorde\nQuest: Other route")
local directPrice = atlas.merchantPriceSource(mount, "", "Trellis Morningsun")
assert(directPrice:find(liveText, 1, true) == 1, "an empty vendor route starts with the live price")
assert(atlas.merchantPriceSource(mount, "", "Other merchant") == "")
assert(atlas.merchantPriceSource(missingPrice, missingPrice.journalSourceRaw, "Trellis Morningsun") == rawPrice)
missingPrice.journalSourceRaw = "Vendor: Other merchant\nReputation: Friendly\n\n"
    .. "Vendor: Trellis Morningsun\nZone: Icecrown\nReputation: Exalted"
groups = atlas.vendorSources(missingPrice)
assert(groups[1].conditions == "Reputation: Friendly")
contains(groups[2].conditions, "Reputation: Exalted\n" .. liveText)
missingPrice.journalSourceRaw = missingPrice.journalSourceRaw .. "\n\nCost: 500|TInterface\\MoneyFrame\\UI-GoldIcon:16|t"
groups = atlas.vendorSources(missingPrice)
contains(groups[1].conditions, "Cost: 500|T")
contains(groups[2].conditions, "Cost: 400|T")
assert(not groups[2].conditions:find("\nЦена:", 1, true), "a shared price occupies the existing row")
merchant[1].costs[1][1], merchant[1].costs[2][1] = nil, nil
refresh()
contains(atlas.vendorSources(mount)[1].conditions, currencyLink)
contains(atlas.vendorSources(mount)[1].conditions, itemLink)
C_CurrencyInfo.GetCurrencyInfo = function(id) if id == 241 then return { iconFileID = 127 } end end
C_Item = { GetItemIconByID = function(id) if id == 888 then return 128 end end }
refresh()
contains(atlas.vendorSources(mount)[1].conditions, "|Hcurrency:241:17|h|T127:18:18|t|h")
contains(atlas.vendorSources(mount)[1].conditions, "|Hitem:888:0:1|h|T128:18:18|t|h")
merchant[2] = merchant[1]
refresh()
contains(atlas.vendorSources(mount)[1].conditions, "400|T")
merchant[2] = { item = 46751, info = { price = 5000000 }, costs = {} }
refresh()
contains(atlas.vendorSources(mount)[1].conditions, "500|T")
assert(atlas.merchantPriceSource(mount, "", "Trellis Morningsun") == "", "conflicting prices are not inserted")
merchant[2] = nil
merchant[1].costs[2] = {nil,3}
refresh()
contains(atlas.vendorSources(mount)[1].conditions, RETRIEVING_ITEM_INFO)
assert(atlas.merchantPriceSource(mount, "", "Trellis Morningsun") == "", "partial prices are not inserted")
merchant[1].info.hasExtendedCost=false
refresh()
groups=atlas.vendorSources(mount)
contains(groups[1].conditions,"400|T")
assert(not groups[1].conditions:find("currency:",1,true), "removed extended cost remains cached")
refresh("MERCHANT_CLOSED")
contains(atlas.vendorSources(mount)[1].conditions,"500|T")
merchant[1].info.hasExtendedCost=true
merchant[1].costs[2]={124,3,"|Hitem:888|h[Trade item]|h"}
vendor="Other merchant"
refresh("MERCHANT_SHOW")
groups=atlas.vendorSources(mount)
contains(groups[1].conditions,"500|T")
contains(groups[2].conditions,"400|T")
assert(loadfile("Core/SourceDetails.lua"))("PawAtlas", atlas)
function GetMoney() return 999999999 end
local source = atlas.decorateSource({ id=320, vendorName="Other merchant", journalSourceRaw="Cost: 500|TInterface\\MoneyFrame\\UI-GoldIcon:16|t" })
contains(source, "400 |Hpawatlascoin:10000|h|TInterface\\MoneyFrame\\UI-GoldIcon:0:0|t|h")
contains(source, "5 |cff00ccff|Hcurrency:241:17|h|T127:0:0|t|h|r")
contains(source, "3 |Hitem:888|h|T124:0:0|t|h")
contains(source, "7 |Hpawatlascost:0:Unidentified currency: test|h|T126:0:0|t|h")
assert(not source:find("ui-questtracker-tracker-check", 1, true), "gold alone must not complete a mixed price")
source = atlas.decorateSource({ id=320, vendorName="Other merchant", journalSourceRaw="" })
contains(source, "400 |Hpawatlascoin:10000|h|T")
refresh("MERCHANT_CLOSED")
source = atlas.decorateSource({ id=320, vendorName="Other merchant", journalSourceRaw="Cost: 500|TInterface\\MoneyFrame\\UI-GoldIcon:16|t" })
contains(source, "500 |Hpawatlascoin:10000|h|T")

local oldPrice = "300|TInterface\\MoneyFrame\\UI-GoldIcon:16|t"
atlas.reviewedMissingMerchantPrices = {
    [mount.id] = { spell = mount.spell, native = { missingPriceJournal },
        prices = { { name = "Треллис Утреннее Солнце", englishName = "Trellis Morningsun", price = oldPrice } } },
}
missingPrice.journalSourceRaw = missingPriceJournal
local reviewedText = "Цена: " .. oldPrice
local reviewedSource = atlas.merchantPriceSource(missingPrice, missingPriceJournal)
contains(reviewedSource, "Reputation: Exalted\n" .. reviewedText)
contains(reviewedSource, "\nVendor: Other merchant\nZone: Somewhere\nReputation: Friendly\n\nHorde\nQuest: Other route")
assert(atlas.merchantPriceSource(missingPrice, "No price", "Other merchant") == "No price")
local newer = "Cost: 900|TInterface\\MoneyFrame\\UI-GoldIcon:16|t"
assert(atlas.merchantPriceSource(missingPrice, newer, "Trellis Morningsun") == newer)
missingPrice.journalSourceRaw = missingPriceJournal .. "\nAdditional requirement"
assert(atlas.merchantPriceSource(missingPrice, missingPriceJournal) == missingPriceJournal)
missingPrice.journalSourceRaw, missingPrice.spell = missingPriceJournal, mount.spell + 1
assert(atlas.merchantPriceSource(missingPrice, missingPriceJournal) == missingPriceJournal)
missingPrice.spell = mount.spell
vendor = "Trellis Morningsun"
refresh("MERCHANT_SHOW")
contains(atlas.merchantPriceSource(missingPrice, missingPriceJournal), "Reputation: Exalted\n" .. liveText)
merchant[2] = { item = 46751, info = { price = 5000000 }, costs = {} }
refresh()
assert(atlas.merchantPriceSource(missingPrice, missingPriceJournal) == missingPriceJournal)
merchant[2] = nil
refresh("MERCHANT_CLOSED")
assert(loadfile("Data/JournalData.lua"))("PawAtlas", atlas)
assert(loadfile("Data/QuestSources.lua"))("PawAtlas", atlas)
for id, item in pairs({ [892] = 143503, [893] = 143504, [894] = 143505 }) do
    local reviewed = atlas.reviewedVendorOffers[id]
    local view = { id = id, spell = reviewed.spell, journalSourceRaw = "Vendor: Crusader Lord Dalfors\nZone: Sanctum of Light" }
    view.journalSourceOverride, view.reviewedVendorOffer = atlas.reviewedVendorSource(view)
    assert(view.reviewedVendorOffer.item == item)
    local listing = atlas.vendorSources(view)[1]
    assert(listing.npc == 99976 and listing.map == 24 and listing.x == .514 and listing.y == .740,
        "the seller's coordinates belong to the Sanctum of Light floor")
    contains(listing.conditions, "1000 |Hcurrency:1220|")
    contains(atlas.sourceInlineLinks(listing.conditions), "|Hquest:45770:0|h[Stirring in the Shadows]|h")
    assert(not listing.conditions:find("Power Ascended", 1, true), "no removed artifact gate")
    view.journalSourceRaw = "Vendor: Another vendor\nZone: Sanctum of Light"
    assert(not atlas.reviewedVendorSource(view), "a newer native route keeps its own terms")
end
local honorIcons = "2000|TINTERFACE\\PVPFRAME\\PVPCurrency-Honor-%s.blp:0|t"
for _, listing in ipairs({
    { 108, 23509, 19029, "Jorek Ironside", "Horde" },
    { 109, 23510, 19030, "Thanthaldis Snowgleam", "Alliance" },
}) do
    local id, spell, item, seller, faction = unpack(listing)
    local nativePrice = honorIcons:format(faction)
    local stale = "Cost: " .. nativePrice
    local unrelated = "Vendor: Other merchant\n" .. stale
    local sourceText = "Vendor: " .. seller .. "\nZone: Hillsbrad Foothills\n" .. stale .. "\n\n" .. unrelated
    local view = { id = id, spell = spell, journalSourceRaw = sourceText }
    local listings = atlas.vendorSources(view)
    assert(listings[1].name == seller and listings[1].place == "Hillsbrad Foothills")
    contains(listings[1].conditions, "15|Hitem:137642|")
    assert(listings[2].conditions == stale)
    assert(atlas.merchantPriceSource(view, unrelated) == unrelated)
    assert(atlas.merchantPriceSource({ id = id, spell = spell + 100 }, sourceText) == sourceText)
    local repriced = "Vendor: " .. seller .. "\nCost: 25|Hitem:137642|h[Mark of Honor]|h"
    assert(atlas.merchantPriceSource(view, repriced) == repriced)

    vendor = seller
    merchant = { { item = item, info = { price = 0, hasExtendedCost = true },
        costs = { { 123, 22, "|Hitem:137642|h[Mark of Honor]|h" } } } }
    refresh("MERCHANT_SHOW")
    contains(atlas.vendorSources(view)[1].conditions, "22 |Hitem:137642|")
    refresh("MERCHANT_CLOSED")
    contains(atlas.vendorSources(view)[1].conditions, "15|Hitem:137642|")
end

assert(loadfile("Data/JournalData.lua"))("PawAtlas", atlas)
local wolf = { id = 7, spell = 459, journalSourceRaw = "Vendor: Ogunaro Wolfrunner\nZone: Orgrimmar" }
local listing = atlas.vendorSources(wolf)[1]
assert(listing.npc == 3362 and listing.map == 85 and listing.x == .616 and listing.y == .356)
wolf.spell = 1234
assert(not atlas.vendorSources(wolf)[1].x, "a teaching spell change invalidates the coordinate lookup")
wolf.spell = 459
wolf.journalSourceRaw = "Vendor: Ogunaro Wolfrunner\nZone: Another place"
assert(not atlas.vendorSources(wolf)[1].x, "a name alone does not resolve a vendor in another zone")

for _, test in ipairs({
    { "enUS", "Elwyn", "Elwyn", 1783, 414334, "Vendor: Baron Silver\nZone: Tyrhold Reservoir", 208338, "Baron Sliver" },
    { "ruRU", "Элвин", "Элвина", 1016, 260173, "Торговец: интендант Эндарин\nЗона: Друствар", 135815, "Интендант Элкорн" },
}) do
    local locale, journalName, elwyn, mountID, spell, rawSource, npc, name = unpack(test)
    language = locale
    local route = assert(atlas.vendorSources({ id = mountID, spell = spell, journalSourceRaw = rawSource }))[1]
    assert(route.npc == npc and route.name == name, "the vendor caption and NPC ID come from the same waypoint")
    for _, id in ipairs({ 1354, 1357, 1485 }) do
        local view = { id = id, spell = atlas.reviewedVendorOffers[id].spell,
            journalSourceRaw = "Covenant: Night Fae\nVendor: " .. journalName }
        view.journalSourceOverride, view.reviewedVendorOffer = atlas.reviewedVendorSource(view)
        local listing = assert(atlas.vendorSources(view))[1]
        assert(listing.npc == 174914 and listing.name == elwyn, "the journal alias resolves to Elwyn's Retail name")
    end
    local alternative = assert(atlas.extraCovenantPurchase({ id = 1393, spell = 334366 }))
    assert(alternative.npc == 174914 and alternative.name == elwyn, "the alternative purchase uses the same name and NPC")
end
language = "enUS"

local paired = { id = 635, spell = 171829,
    journalSourceRaw = "Vendor: Ravenspeaker Skeega / Shadow-Sage Brakoss\nZone: Stormshield / Warspear" }
local points = atlas.vendorSources(paired)[1].waypoints
assert(#points == 2 and points[1].npc == 86037 and points[1].map == 624
    and points[2].npc == 85946 and points[2].map == 622, "paired vendors use their own map IDs")
local factionOffer = { id = 1776, spell = 414316, journalSourceRaw = "Horde\nVendor: Warden Krizzik\nZone: Tyrhold Reservoir"
    .. "\n\nAlliance\nItem: Gift of the White War Wolf" }
local block = atlas.factionSources(factionOffer)[1]
listing = atlas.vendorSources(block)[1]
assert(listing.npc == 208346 and listing.map == 2025 and listing.faction == "Horde",
    "a faction page retains the seller, coordinates and faction")
local goblin = { id = 4, spell = 999, journalSourceRaw = "Vendor: Goram\nZone: Orgrimmar" }
assert(not atlas.vendorSources(goblin)[1].npc, "a seller reference is scoped to the recorded mount")

local alliance = { id = 618, spell = 171626, journalSourceRaw = "Vendor:\nFaction: Sha'tari Defense - Exalted"
    .. "\nLocation: Garrison Trading Post\nCost: 5000g + 5000|Hcurrency:823|h[Apexis Crystal]|h" }
local horde = { id = 645, spell = 171839, journalSourceRaw = "Vendor: Kil'rip\nFaction: Laughing Skull - Exalted"
    .. "\nLocation: Horde Garrison Trading Post" }
listing = atlas.vendorSources(alliance)[1]
assert(listing.name == "Maaria" and listing.npc == 85427 and listing.map == 582 and not listing.x,
    "the missing journal vendor resolves to the exact vendor and map before plot data is known")
contains(listing.conditions, "Sha'tari Defense - Exalted")
contains(listing.conditions, "5000|Hcurrency:823|")

local faction, building, constructing, canActivate, plotX = "Alliance", 144, false, false, .24
function UnitFactionGroup() return faction end
C_Garrison = {
    GetGarrisonPlotsInstancesForMap = function(map)
        assert(map == (faction == "Alliance" and 582 or 590))
        return { { buildingPlotInstanceID = 63, position = { GetXY = function() return plotX, .76 end } } }
    end,
    GetOwnedBuildingInfoAbbrev = function(plot)
        assert(plot == 63)
        return building, nil, nil, nil, nil, constructing, nil, nil, canActivate
    end,
}
listing = atlas.vendorSources(alliance)[1]
assert(listing.x == .24 and listing.y == .76, "the waypoint uses the character's active Trading Post plot")
plotX, building = .53, 145
refresh("GARRISON_BUILDING_ACTIVATED")
assert(atlas.vendorSources(alliance)[1].x == .53, "a new finished plot replaces the old plot position")
building = 111
assert(not atlas.vendorSources(alliance)[1].x, "level 1 Trading Post does not unlock the quartermaster")
building, constructing, canActivate = 144, true, false
assert(not atlas.vendorSources(alliance)[1].x, "construction has no confirmed seller waypoint")
constructing, canActivate = false, true
assert(not atlas.vendorSources(alliance)[1].x, "the completed building needs to be activated")
faction, canActivate = "Horde", false
assert(not atlas.vendorSources(alliance)[1].x, "the other faction's plot data does not guide this route")
listing = atlas.vendorSources(horde)[1]
assert(listing.npc == 87015 and listing.map == 590 and listing.x == .53, "the Horde quartermaster uses its own map")

local pale = { id = 639, spell = 171833, journalSourceRaw = "Vendor: Crafticus Mindbender\nZone: Stormshield"
    .. "\nFaction: Wrynn's Vanguard - Exalted\nCost: 5000g + 5000|Hcurrency:823|h[Apexis Crystal]|h" }
listing = atlas.vendorSources(pale)[1]
assert(listing.name == "Magister Langley" and listing.npc == 128756 and listing.map == 622 and listing.x == .548)
contains(listing.conditions, "Wrynn's Vanguard - Exalted")
contains(listing.conditions, "5000g + 100|Hitem:137642|")
local deepseeker = { id = 1262, spell = 300151, journalSourceRaw = "Vendor: Crafticus Mindbender\nZone: Nazjatar"
    .. "\nCost: 150|Hitem:168802|h[Commendation]|h\n\nVendor: Dazzerian\nZone: Nazjatar" }
local vendors = atlas.vendorSources(deepseeker)
assert(vendors[1].name == "Tomas Riogain" and vendors[1].npc == 154653 and vendors[1].map == 1355 and vendors[1].x == .381)
assert(vendors[2].name == "Dazzerian" and vendors[2].npc == 154652,
    "the confirmed other faction's seller keeps a separate route")
contains(vendors[1].conditions, "150|Hitem:168802|")

local lovebird = { id = 431, spell = 102350, journalSourceRaw = "World Event: Love is in the Air\n\n"
    .. "Vendor: Lovely Merchant (Alliance)\nZone: Stormwind City\nCost: 270|Hitem:49927|h[Love Token]|h\n\n"
    .. "Vendor: Lovely Merchant (Horde)\nZone: Orgrimmar\nCost: 270|Hitem:49927|h[Love Token]|h" }
vendors = atlas.vendorSources(lovebird)
assert(#vendors == 2 and vendors[1].npc == 211812 and vendors[1].map == 37 and vendors[1].place == "Elwynn Forest"
    and vendors[1].x == .322 and vendors[1].faction == "Alliance")
assert(vendors[2].npc == 214481 and vendors[2].map == 1 and vendors[2].place == "Durotar"
    and vendors[2].x == .419 and vendors[2].faction == "Horde")
for _, route in ipairs(vendors) do
    contains(route.conditions, "World Event: Love is in the Air")
    contains(route.conditions, "270|Hitem:49927|")
end

for _, journal in ipairs({
    { "enUS", "Vendor", "Zone", "Nagrand, Outland", "Faction", "Cost",
        "Provisioner Nasela", "Trader Narasu", "The Mag'har - Exalted", "The Kurenai - Exalted" },
    { "ruRU", "Торговец", "Зона", "Награнд (Запределье)", "Фракция", "Цена",
        "поставщик Несела", "торговец Нарасу", "маг'хары – превознесение", "куренай – превознесение" },
}) do
    local locale, sellerLabel, zoneLabel, zone, repLabel, costLabel, nasela, narasu, maghar, kurenai = unpack(journal)
    language = locale
    for _, talbuk in ipairs({
        { 153, 34896, 100 }, { 154, 34897, 100 }, { 155, 34898, 100 }, { 156, 34899, 100 },
        { 170, 39315, 70 }, { 172, 39317, 70 }, { 173, 39318, 70 }, { 174, 39319, 70 },
    }) do
        local id, spell, price = unpack(talbuk)
        local cost = costLabel .. ": " .. price .. "|TInterface\\MoneyFrame\\UI-GoldIcon.blp:0|t"
        local function listingText(seller, reputation)
            return table.concat({ sellerLabel .. ": " .. seller, zoneLabel .. ": " .. zone,
                repLabel .. ": " .. reputation, cost }, "\n")
        end
        local view = { id = id, spell = spell,
            journalSourceRaw = listingText(nasela, maghar) .. "\n\n" .. listingText(narasu, kurenai) }
        local offers = atlas.vendorSources(view)
        assert(#offers == 2 and not view.faction, "talbuk vendors are faction-specific but the mount is shared")
        local hordeOffer, allianceOffer = unpack(offers)
        assert(hordeOffer.npc == 20241 and hordeOffer.faction == "Horde" and hordeOffer.map == 107
            and hordeOffer.x == .535 and hordeOffer.y == .37)
        assert(allianceOffer.npc == 20240 and allianceOffer.faction == "Alliance" and allianceOffer.map == 107
            and allianceOffer.x == .545 and allianceOffer.y == .751)
        assert(hordeOffer.conditions == repLabel .. ": " .. maghar .. "\n" .. cost)
        assert(allianceOffer.conditions == repLabel .. ": " .. kurenai .. "\n" .. cost)
    end
end
language = "enUS"

local frayfeather = { id = 2224, spell = 452643, journalSourceRaw = "Vendor: Bobadormu\nZone: Tanaris\n"
    .. "Cost: 5000|Hcurrency:1166|h[Timewarped Badge]|h\n\nVendor: Grannadormu\nZone: Tanaris\n"
    .. "Cost: 5000|Hcurrency:1166|h[Timewarped Badge]|h" }
vendors = atlas.vendorSources(frayfeather)
assert(#vendors == 2 and vendors[1].npc == 234555 and vendors[1].map == 84 and vendors[1].x == .56
    and vendors[2].npc == 234555 and vendors[2].map == 85 and vendors[2].x == .528)
for _, route in ipairs(vendors) do
    contains(route.conditions, "Classic Timewalking")
    contains(route.conditions, "5000|Hcurrency:1166|")
end

local ando = atlas.vendorSources({ id = 2279, spell = 466012,
    journalSourceRaw = "Vendor: Ando the Gat\nZone: Liberation of Undermine" })[1]
assert(ando.npc == 235621 and not ando.x and not ando.y, "raid vendor identity does not imply a floor waypoint")
assert(not ando.faction, "a neutral vendor does not receive a faction emblem")
contains(ando.conditions, "8")

local whiteGoat
for _, row in ipairs({
    { "enUS", "Vendor", "Zone", "Gina Mudclaw", "Timeless Isle", "Valley of the Four Winds",
        "Faction: The Tillers - Exalted\nCost: " },
    { "ruRU", "Торговец", "Зона", "Джина Грязный Коготь", "Вневременный остров", "долина Четырех Ветров",
        "Фракция: Земледельцы - превознесение\nЦена: " },
}) do
    local locale, vendorLabel, zoneLabel, seller, island, valley, requirements = unpack(row)
    language = locale
    for _, goat in ipairs({ { 510, 130137, 3250 }, { 511, 130138, 1500 } }) do
        local id, spell, price = unpack(goat)
        local function listingText(zone, cost)
            return ("%s: %s\n%s: %s\n%s%d|TInterface\\MoneyFrame\\UI-GoldIcon:16|t"):format(
                vendorLabel, seller, zoneLabel, zone, requirements, cost)
        end
        local view = { id = id, spell = spell, journalSourceRaw = listingText(island, price) .. "\n\n" .. listingText(valley, price) }
        local offers = atlas.vendorSources(view)
        assert(#offers == 1 and offers[1].name == seller and offers[1].groupedLocations)
        local locations = offers[1].waypoints
        assert(#locations == 2 and locations[1].place == island and locations[1].map == 554 and not locations[1].x)
        assert(not locations[1].npc, "the reviewed alternate place does not borrow the main seller's NPC or coordinates")
        assert(locations[2].place == valley and locations[2].npc == 58706 and locations[2].map == 376
            and locations[2].x == .532 and locations[2].y == .516)
        assert(locations[1].conditions == locations[2].conditions)
        if locale == "enUS" and id == 510 then whiteGoat = view end
        view = { id = id, spell = spell, journalSourceRaw = listingText(island, price) .. "\n\n" .. listingText(valley, price - 10) }
        offers = atlas.vendorSources(view)
        assert(#offers == 2 and not offers[1].groupedLocations, "different native prices stay separate")
        view.spell = 0
        view.journalSourceRaw = listingText(island, price) .. "\n\n" .. listingText(valley, price)
        assert(#atlas.vendorSources(view) == 2, "a repeated seller name and price alone do not identify the same merchant")
    end
end
language = "enUS"

for id, spell in pairs({ [2586] = 1237631, [2587] = 1237703 }) do
    local suffix = "\nCost: 5000|Hcurrency:1166|h[Timewarped Badge]|h"
    local view = { id = id, spell = spell, journalSourceRaw = "Vendor: Churbro\nZone: Boralus Harbor" .. suffix
        .. "\n\nVendor: Churbro\nZone: Zuldazar" .. suffix }
    local offers = atlas.vendorSources(view)
    assert(#offers == 1 and #offers[1].waypoints == 2)
    local boralus, zuldazar = unpack(offers[1].waypoints)
    assert(boralus.npc == 239840 and boralus.map == 1161 and boralus.x == .708)
    assert(zuldazar.npc == 239840 and zuldazar.map == 862 and zuldazar.x == .461)
end

mountsByItem[89390] = 510
vendor = "Gina Mudclaw"
merchant = { { item = 89390, info = { price = 27625000 }, costs = {} } }
function UnitGUID() return "Creature-0-0000-0-0-58706-0000000000" end
local merchantMap
C_Map = { GetBestMapForUnit = function() return merchantMap end }
refresh("MERCHANT_SHOW")
vendors = atlas.vendorSources(whiteGoat)
assert(#vendors == 1 and vendors[1].waypoints[1].conditions == vendors[1].waypoints[2].conditions,
    "an unlocated quote does not replace either purchase price")
merchantMap = 376
refresh()
vendors = atlas.vendorSources(whiteGoat)
assert(#vendors == 1 and #vendors[1].waypoints == 2, "a live discount does not split the offer")
local island, valley = unpack(vendors[1].waypoints)
contains(island.conditions, "3250|T")
contains(valley.conditions, "2762.5|T")
local islandDetails = atlas.decorateSource({ id = 510, spell = 130137, journalSourceRaw = island.conditions,
    vendorName = island.name, vendorPriceResolved = island.priceResolved })
contains(islandDetails, "3,250")
assert(not islandDetails:find("2762", 1, true), "formatting the card must not re-apply another location's live quote")
refresh("MERCHANT_CLOSED")

print("passed: live merchant prices, delayed components, reviewed offers and vendor waypoints")
