-- Run from PawAtlas: lua5.1 tools/test_source_details.lua
assert(_VERSION == "Lua 5.1")
local atlas = { rares = {} }
local timers, frames, calls, elapsed, categoryQueries, countQueries = {}, {}, 0, 0, 0, 0
function CreateFrame()
    local frame = { RegisterEvent = function() end, SetScript = function(self, _, callback) self.callback = callback end }
    frames[#frames + 1] = frame
    return frame
end
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
function debugprofilestop() return elapsed end
function GetTime() return 0 end
function atlas.L(value, ...) return select('#', ...) > 0 and value:format(...) or value end
function atlas.getLocale() return "enUS" end
function atlas.displayName(value) return value end
function atlas.normalizeSource(value) return value or "" end
assert(loadfile("Data/Mounts.lua"))("PawAtlas", atlas)
assert(loadfile("Data/JournalData.lua"))("PawAtlas", atlas)
assert(loadfile("Data/QuestSources.lua"))("PawAtlas", atlas)
assert(loadfile("Data/LootSources.lua"))("PawAtlas", atlas)
assert(loadfile("Core/SourceDetails.lua"))("PawAtlas", atlas)

local reward, purchaseInfo, directInfo = 168055, false, true
local offensiveID, offensiveDone
local vendorAchievements = { [15035]=true, [62563]=true, [62873]=true, [62874]=true, [63264]=true }
function GetAchievementInfo(id, index)
    calls, elapsed = calls + 1, elapsed + 1
    if index then
        local names = { [91] = "Shared Season", [92] = "Shared Season", [93] = "Double Meaning!", [94] = "Double Meaning?" }
        return index, names[index] or "Achievement " .. index
    end
    if id == 63690 and not purchaseInfo then return end
    if id == 13517 and not directInfo then return end
    if vendorAchievements[id] then
        if id == 15035 and offensiveID then return offensiveID, "On the Offensive", 15, offensiveDone end
        return
    end
    return id, id == 13517 and "Two Sides to Every Tale" or "Achievement " .. id
end
function GetAchievementCategory() return 1 end
function GetCategoryInfo() return "Achievements", -1 end
function GetCategoryList() categoryQueries = categoryQueries + 1; return { 1 } end
function GetCategoryNumAchievements() countQueries = countQueries + 1; return 100 end
C_AchievementInfo = { GetRewardItemID = function(id) return id == 13517 and reward end }
C_MountJournal = {
    GetMountFromItem = function(item) return ({ [168055] = 1245, [168056] = 1246 })[item] end,
    GetMountInfoByID = function(id) return "Mount", ({ [1245] = 295387, [1246] = 295386, [1600] = 370620 })[id] end,
}
local function has(text, expected) assert(text:find(expected, 1, true), expected .. " missing in " .. text) end
do
    local coin = "|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
    local linkedCoin = " |Hpawatlascoin:10000|h|TInterface\\MoneyFrame\\UI-GoldIcon:0:0|t|h"
    local locale = atlas.getLocale
    atlas.getLocale = function() return "ruRU" end
    local expected = "Цена: 500 000" .. linkedCoin .. " (Не хватает: 484 517" .. linkedCoin .. ")"
    for _, price in ipairs({ "500000", "500 000", "500 000" }) do
        assert(atlas.displaySourceText("Цена: " .. price .. coin .. " (Не хватает: 484517" .. coin .. ")") == expected)
    end
    assert(atlas.displaySourceText(expected) == expected, "redrawing a price keeps exactly one link per coin")
    atlas.getLocale = locale
    has(atlas.displaySourceText("Цена: 1000000" .. coin), "1,000,000" .. linkedCoin)
    for _, row in ipairs({ {864, 229385, "Испытание Бань Лу", 46350}, {1545, 395644, '"Шепот ветра"', 72512} }) do
        has(atlas.decorateSource({id=row[1], spell=row[2], journalSourceRaw="Задание: " .. row[3]}), "|Hquest:" .. row[4] .. ":")
        assert(not atlas.decorateSource({id=row[1], spell=row[2], journalSourceRaw="Задание: Другое"}):find("|Hquest:"))
    end
end
do
    local previousItems, previousCurrencies, previousMoney = C_Item, C_CurrencyInfo, GetMoney
    local held, currency, gold = 0, 5, 10000
    C_Item = { GetItemCount = function(id) assert(id == 174230); return held end }
    C_CurrencyInfo = { GetCurrencyInfo = function() return { quantity = currency } end }
    GetMoney = function() return gold end
    local scale = "1|Hitem:174230|h|Tscale:0|t|h"
    local function checked(price)
        local text = atlas.decorateSource({ id = 1313, journalSourceRaw = "Cost: " .. price })
        return text:find("ui-questtracker-tracker-check", 1, true) ~= nil
    end
    assert(not checked(scale))
    held = 1
    assert(checked(scale) and not checked(scale .. " + " .. scale))
    local mixed = scale .. " + 5|Hcurrency:1885|h[Offering]|h + 1|TInterface\\MoneyFrame\\UI-GoldIcon:0|t"
    assert(checked(mixed) and not checked(scale .. " or " .. scale))
    currency = 4
    assert(not checked(mixed))
    held = 0
    assert(not checked(scale), "consuming the scale removes the check")
    C_Item, C_CurrencyInfo, GetMoney = previousItems, previousCurrencies, previousMoney
end
for _, factionReward in ipairs({168055,168056}) do
    reward = factionReward
    for _, pair in ipairs({ {1245,295387}, {1246,295386} }) do
        local text = atlas.decorateSource({ id=pair[1], spell=pair[2], journalSourceRaw="Achievement: Two Sides to Every Tale" })
        has(text, "|Hachievement:13517|")
    end
end
assert(#timers == 0 and calls == 4, "exact candidates reuse their native row without beginning a catalog scan")
do
    directInfo = false
    has(atlas.decorateSource({ id=1245, spell=295387, journalSourceRaw="Achievement: Two Sides to Every Tale" }),
        '|Hachievement:13517|h"Two Sides to Every Tale"|h')
    directInfo = true
    local check = "ui-questtracker-tracker-check"
    for mountID, achievementID in pairs({ [1436]=15035, [1486]=15035, [1491]=15035, [1497]=15035,
        [2915]=62563, [2988]=62873, [2990]=62874, [3033]=63264 }) do
        local record = atlas.achievementSources[mountID]
        for _, locale in ipairs({ "name", "englishName" }) do
            local title = record.candidates[1][locale]
            local source = atlas.decorateSource({ id=mountID, spell=record.spell, vendorName="Merchant",
                journalSourceRaw="Achievement: " .. title })
            has(source, '|Hachievement:' .. achievementID .. '|h"' .. title .. '"|h')
            assert(not source:find(check, 1, true), "a cold verified link has no completion check")
        end
    end
    local function seller(spell, title)
        return { id=1491, spell=spell, purchaseRequirement=true, journalSourceRaw="Achievement: " .. title }
    end
    local purchase = seller(353873, '"On the Offensive"')
    offensiveID, offensiveDone = 15035, false
    has(atlas.decorateSource(purchase), "|cffffd200|Hachievement:15035|")
    offensiveID, offensiveDone = 15064, true
    assert(not atlas.decorateSource(purchase):find(check, 1, true), "completion from a different ID is ignored")
    offensiveID = 15035
    local completed = atlas.decorateSource(purchase)
    has(completed, "|cff999999")
    has(completed, '|Hachievement:15035|h"On the Offensive"|h')
    has(completed, check)
    assert(not atlas.decorateSource(seller(1, "On the Offensive")):find("|Hachievement:", 1, true))
    assert(not atlas.decorateSource(seller(353873, "Other purchase condition")):find("|Hachievement:", 1, true))
    assert(not atlas.sourceAchievementReward(purchase, purchase), "purchase criteria do not confirm a direct reward")
    offensiveID, offensiveDone = nil, nil
end
do
    local oldFaction, oldAchievementInfo, oldAPI, oldJournal = UnitFactionGroup, GetAchievementInfo, C_AchievementInfo, C_MountJournal
    local oldSourceLabel, oldCategories = atlas.isAchievementSourceLabel, GetCategoryList
    local rewards = { [62096] = 265656, [62103] = 265656, [15833] = 198654, [15834] = 198654,
        [8302] = 98104, [8304] = 98259, [5823] = 70909, [5824] = 70910 }
    local rewardMounts = { [265656] = 2917, [198654] = 1654, [98104] = 548, [98259] = 549,
        [70909] = 422, [70910] = 423 }
    local requirements = { [62096] = 600, [62103] = 600, [15833] = 500, [15834] = 500,
        [8302] = 200, [8304] = 200, [5823] = 150, [5824] = 150, [6] = 1 }
    local wins = { [5823] = 37, [5824] = 58 }
    local faction, quantity, criteriaLoaded = "Neutral", 426, true
    UnitFactionGroup = function(unit) assert(unit == "player"); return faction end
    GetCategoryList = nil
    GetAchievementInfo = function() end
    atlas.isAchievementSourceLabel = function(label) return label == "Achievement" end
    C_AchievementInfo = { GetRewardItemID = function(id) return rewards[id] end,
        IsValidAchievement = function(id) return criteriaLoaded and (requirements[id] ~= nil or id == 2136) end }
    C_MountJournal = { GetMountFromItem = function(item) return rewardMounts[item] end }
    function GetAchievementNumCriteria(id)
        if criteriaLoaded then return id == 2136 and 3 or 1 end
    end
    function GetAchievementCriteriaInfo(id, index)
        if id == 2136 then return "Meta objective", 8, index == 2 end
        if wins[id] then return "Win ranked battlegrounds", 130, false, wins[id], requirements[id] end
        return "Obtain mounts", 75, nil, quantity, requirements[id]
    end
    local function progress(id, value, target)
        local current, required = atlas.achievementProgress(id)
        assert(current == value and required == target, "unexpected progress for achievement " .. id)
    end
    local function verifyLink(mountID, title, id, routeFaction)
        local mount = { id = mountID, spell = atlas.achievementSources[mountID].spell }
        local route = { id = mount.id, spell = mount.spell, faction = routeFaction, journalSourceRaw = "Achievement: " .. title }
        local link = atlas.decorateSource(route)
        has(link, "|Hachievement:" .. id .. "|")
        assert(atlas.sourceAchievementReward(mount, route) == rewards[id])
        return tonumber(link:match("|Hachievement:(%d+)"))
    end
    local owl = { id = 2917, spell = 1276650, journalSourceRaw = "Achievement: Insurmountable Collection" }
    assert(not atlas.decorateSource(owl):find("|Hachievement:", 1, true))
    local oldRefresh, refreshed = atlas.refreshSourceDetails
    atlas.refreshSourceDetails = function() refreshed = atlas.decorateSource(owl) end
    faction = "Alliance"
    frames[1].callback(nil, "NEUTRAL_FACTION_SELECT_RESULT")
    assert(#timers == 1, "choosing a faction refreshes the already open achievement card")
    table.remove(timers, 1)[2]()
    has(refreshed, "|Hachievement:62103|")
    atlas.refreshSourceDetails = oldRefresh
    for _, row in ipairs({ { "Alliance", 62103, 15834, 423, "Veteran of the Horde II", 5824, "Horde" },
            { "Horde", 62096, 15833, 422, "Veteran of the Alliance II", 5823, "Alliance" } }) do
        faction = row[1]
        has(atlas.decorateSource(owl), "|Hachievement:" .. row[2] .. "|")
        progress(verifyLink(2917, "Insurmountable Collection", row[2]), 426, 600)
        progress(verifyLink(1654, "Приятной поездки!", row[3]), 426, 500)
        progress(verifyLink(row[4], row[5], row[6], row[7]), wins[row[6]], 150)
    end
    progress(verifyLink(2917, "Страховка на коллекцию", 62103, "Alliance"), 426, 600)
    progress(verifyLink(549, "Mount Parade", 8304), 200, 200)
    progress(2136, 1, 3)
    progress(6)
    progress(999999)
    quantity = 0
    progress(62096, 0, 600)
    quantity = nil
    progress(62096)
    criteriaLoaded = false
    progress(62096)
    has(atlas.decorateSource(owl), "|Hachievement:62096|")
    assert(not atlas.sourceAchievementReward(owl, owl), "the retained identity alone does not establish a reward")
    local parade = { id = 549, spell = 142478, journalSourceRaw = 'Достижение: "Парад ездовых животных"' }
    C_MountJournal.GetMountInfoByID = function() return "Mount", 142478, nil, nil, nil, nil, nil, true, 1 end
    has(atlas.decorateSource(parade), "|Hachievement:8304|")
    parade.faction = "Орда"
    has(atlas.decorateSource(parade), "|Hachievement:8302|")
    parade.faction = nil
    has(atlas.decorateSource(parade), "|Hachievement:8304|")
    UnitFactionGroup, GetAchievementInfo, C_AchievementInfo, C_MountJournal = oldFaction, oldAchievementInfo, oldAPI, oldJournal
    GetAchievementNumCriteria, GetAchievementCriteriaInfo = nil, nil
    atlas.isAchievementSourceLabel, GetCategoryList = oldSourceLabel, oldCategories
end
assert(#timers == 0 and categoryQueries == 0, "verified claims stay outside category discovery")
local beforeUnknown = calls
local unknown = atlas.decorateSource({ id=999999, journalSourceRaw="Achievement: Unresolved" })
assert(not unknown:find("|Hachievement:"), "unknown achievement must not acquire an invented ID")
assert(calls == beforeUnknown and categoryQueries == 0, "cold rendering does not synchronously request or enumerate categories")
local purchase = { id=3005, purchaseRequirement=true,
    journalSourceRaw="Achievement: |Hachievement:63690|hMidnight Keystone Myth: Season 2|h" }
local cold = atlas.decorateSource(purchase)
has(cold, '|Hachievement:63690|h"Midnight Keystone Myth: Season 2"|h')
assert(categoryQueries == 0 and #timers == 1, "the exact link opens before the deferred global index")
local timer = table.remove(timers, 1)
local beforeScan = calls
timer[2]()
assert(categoryQueries == 1 and calls - beforeScan <= 2, "first scan tick exceeds the elapsed time budget")
assert(#timers > 0, "scan must yield before finishing the catalog")
purchaseInfo = true
local warm = atlas.decorateSource(purchase)
has(warm, '|Hachievement:63690|h"Achievement 63690"|h')
assert(#timers > 0, "the direct link is available on repeat while the full index still runs")
local unlinked = atlas.decorateSource({ id=3005, purchaseRequirement=true, journalSourceRaw="Achievement: Unresolved" })
assert(not unlinked:find("|Hachievement:",1,true), "plain purchase requirement does not resolve loosely by name")
while #timers > 0 do table.remove(timers, 1)[2]() end
assert(countQueries == 1, "a complete category count persists between scan ticks")
local fallbackAchievement = { id=999999, journalSourceRaw="Achievement: Achievement 100" }
has(atlas.decorateSource(fallbackAchievement), "|Hachievement:100|")
for _, title in ipairs({ "Shared Season", "Double Meaning." }) do
    local unresolved = atlas.decorateSource({ id=999999, journalSourceRaw = "Achievement: " .. title })
    assert(not unresolved:find("|Hachievement:", 1, true), "ambiguous name must not resolve: " .. title)
end
atlas.decorateSource({ id=999999, journalSourceRaw="Achievement: Unresolved" })
assert(#timers == 0, "an unresolved name does not repeat a completed scan")
frames[1].callback(nil, "ACHIEVEMENT_EARNED", 100, false)
has(atlas.decorateSource(fallbackAchievement), "|Hachievement:100|")
assert(categoryQueries == 1 and #timers == 1, "completion refreshes the card without rebuilding the achievement index")

do
    local oldInfo, oldLocale = GetAchievementInfo, atlas.getLocale
    local phase, language, queried = "cold", "enUS", 0
    function GetAchievementInfo(id)
        queried = queried + 1
        if phase == "warm" and id == 9713 then return id, "Awake the Drakes", 10, true end
    end
    function atlas.getLocale() return language end
    local beforeTimers = #timers
    for _, row in ipairs({
        { 664, 175700, 9713, "Drake Collector", "Коллекционер драконов" },
        { 1416, 339956, 15089, "Flawless Master", "Безупречное мастерство" },
        { 3021, 1297220, 63254, "Glory of the Venomous Abyss Raider", "Слава рейдеру Отравленной бездны" },
    }) do
        local mountID, spell, achievementID, english, russian = unpack(row)
        for _, entry in ipairs({ { "enUS", english }, { "ruRU", russian } }) do
            language = entry[1]
            local view = { id = mountID, spell = spell, journalSourceRaw = "Achievement: " .. entry[2] }
            has(atlas.decorateSource(view), "|Hachievement:" .. achievementID .. "|")
            assert(not atlas.sourceAchievementReward(view, view), "matching an exact ID leaves the live reward undecided")
        end
    end
    for _, entry in ipairs({ { "enUS", "Umbral Champion: Midnight Season One" }, { "ruRU", "Теневой защитник: 1-й сезон Midnight" } }) do
        language = entry[1]
        local archived = { id = 3069, spell = 1301775, unavailable = true, journalSourceRaw = "Achievement: " .. entry[2] }
        has(atlas.historicalAchievementSource(archived), "|Hachievement:63104|")
        assert(not atlas.decorateSource(archived):find("|Hachievement:", 1, true), "retired achievements belong in the source tooltip")
    end
    assert(queried == 8, "exact mount/spell and caption skip native title discovery and read live display data once")
    language, phase = "enUS", "warm"
    local drake = { id = 664, spell = 175700, journalSourceRaw = "Achievement: Drake Collector" }
    has(atlas.decorateSource(drake), '|Hachievement:9713|h"Awake the Drakes"|h')
    has(atlas.decorateSource(drake), "ui-questtracker-tracker-check")
    GetAchievementInfo = function(id)
        queried = queried + 1
        return id, "Renamed native title", 10, true
    end
    drake.journalSourceRaw = "Achievement: Renamed native title"
    has(atlas.decorateSource(drake), "|Hachievement:9713|")
    local beforeRevisit = queried
    has(atlas.decorateSource(drake), "|Hachievement:9713|")
    assert(queried == beforeRevisit + 1, "revisit reads current achievement state without resolving its ID again")
    drake.purchaseRequirement = true
    assert(not atlas.decorateSource(drake):find("|Hachievement:", 1, true), "an acquisition ID must stay out of purchase conditions")
    drake.purchaseRequirement, drake.spell = nil, 1
    assert(not atlas.decorateSource(drake):find("|Hachievement:", 1, true), "a reused mount ID must resolve its own spell")
    local wolf = { id = 558, spell = 148396, unavailable = true,
        journalSourceRaw = "Achievement: Ahead of the Curve: Garrosh Hellscream (10/25 player)" }
    local combined = atlas.historicalAchievementSource(wolf)
    has(combined, "|Hachievement:8398|")
    has(combined, "|Hachievement:8399|")
    local serpent = { id = 1282, spell = 305182, kind = "Достижение" }
    local choices = assert(atlas.achievementRouteChoices(serpent))
    assert(#choices == 2, "both verified routes are available with cold title and reward data")
    has(atlas.decorateSource(choices[1].view), "|Hachievement:13994|")
    has(atlas.decorateSource(choices[2].view), "|Hachievement:41929|")
    assert(not atlas.sourceAchievementReward(serpent, choices[1].view))
    assert(#timers == beforeTimers, "verified or explicitly disambiguated routes do not start the global scan")
    GetAchievementInfo, atlas.getLocale = oldInfo, oldLocale
end

do
    local previousAchievementInfo, previousFaction, previousAPI = GetAchievementInfo, UnitFactionGroup, C_AchievementInfo
    C_AchievementInfo = nil
    local infoLoaded, completed = false, false
    function GetAchievementInfo(id)
        if id == 5823 or id == 5824 then
            if infoLoaded then
                return id, id == 5823 and "Veteran of the Alliance II" or "Veteran of the Horde II", 10, completed
            end
        end
    end
    for _, row in ipairs({ { 422, 100332, 5823, "Horde", "Ветеран Альянса II", "Veteran of the Alliance II" },
            { 423, 100333, 5824, "Alliance", "Ветеран Орды II", "Veteran of the Horde II" } }) do
        local mountID, spell, id, faction, russian, english = unpack(row)
        UnitFactionGroup = function() return faction end
        for _, title in ipairs({ russian, english }) do
            local view = { id = mountID, spell = spell, journalSourceRaw = 'Achievement: "' .. title .. '"' }
            has(atlas.decorateSource(view), "|Hachievement:" .. id .. "|")
            assert(not atlas.sourceAchievementReward(view, view), "a known link alone does not confirm an item reward")
        end
    end
    infoLoaded, completed = true, true
    local done = atlas.decorateSource({ id = 423, spell = 100333, journalSourceRaw = 'Achievement: "Ветеран Орды II"' })
    has(done, "|Hachievement:5824|")
    has(done, "ui-questtracker-tracker-check")
    local unrelated = atlas.decorateSource({ id = 423, spell = 100333, journalSourceRaw = "Achievement: Something else" })
    assert(not unrelated:find("|Hachievement:", 1, true), "a different journal caption does not inherit the faction achievement")
    GetAchievementInfo, UnitFactionGroup, C_AchievementInfo = previousAchievementInfo, previousFaction, previousAPI
end

function GetQuestLink(id) return "|cffffff00|Hquest:"..id..":80|h[Quest "..id.."]|h|r" end
local quests = atlas.decorateSource({ id=1600, spell=370620,
    journalSourceRaw=atlas.journalSourceDetails[1600].source })
has(quests, "|Hquest:63490:")
has(quests, "|Hquest:65653:")
has(quests, "— для паладинов")
local newRoute = atlas.decorateSource({ id=1600, spell=370620, journalSourceRaw="Quest: New native route" })
assert(not newRoute:find("|Hquest:"), "changed source must not inherit old quest IDs")
local changed = atlas.decorateSource({ id=1600, spell=1, journalSourceRaw="Quest: Different quest" })
assert(not changed:find("|Hquest:"), "reused mount ID must not inherit quest IDs")
assert(changed == "Задание: Different quest", "an unidentified quest name is plain text")
assert(not quests:find("Controls\\Quest.tga",1,true), "quest names have no duplicate inline source icon")
local punctuation = atlas.decorateSource({ id=999999, journalSourceRaw="Quest: Look out!" })
assert(punctuation == "Задание: Look out!", "plain quest names retain punctuation")
assert(not punctuation:find("Controls\\Quest.tga",1,true), "ordinary quest prefix has no inline icon")
local mission = atlas.decorateSource({ id=1600, spell=370620, journalSourceRaw="Garrison Mission: Mission" })
assert(not mission:find("|Hquest:"), "a mission must not be treated as a normal quest")
assert(not mission:find("Controls\\Quest.tga",1,true), "garrison mission prefix has no duplicate inline icon")
local riverbeast = atlas.decorateSource({ id=631, spell=171826, journalSourceRaw=atlas.directMountGrants[631].englishText })
has(riverbeast, "|Hpawatlasmission:615|h[It's a Boat, It's a Plane, It's... Just a Riverbeast.]|h")
assert(not riverbeast:find("|Hquest:", 1, true), "a verified mission retains its own reference type")
do
    local requested, loaded, current, refreshed = {}, {}, 1600, nil
    C_QuestLog = { RequestLoadQuestByID=function(id) requested[id]=(requested[id] or 0)+1 end }
    GetQuestLink = function(id) if loaded[id] then return "|Hquest:"..id..":80|h[Loaded quest]|h" end end
    atlas.refreshSourceDetails=function() refreshed=current end
    local pending=atlas.decorateSource({id=1600,spell=370620,journalSourceRaw=atlas.journalSourceDetails[1600].source})
    has(pending, "|Hquest:63490:0|")
    has(pending, "|Hquest:65653:0|")
    assert(pending:find("— для паладинов", 1, true), "source qualifiers stay outside the link")
    atlas.decorateSource({id=1600,spell=370620,journalSourceRaw=atlas.journalSourceDetails[1600].source})
    assert(requested[63490]==1 and requested[65653]==1,"pending quest requests coalesce by exact ID")
    current=999999
    loaded[63490]=true
    frames[1].callback(nil,"QUEST_DATA_LOAD_RESULT",63490,true)
    local remaining=500
    while #timers>0 and remaining>0 do table.remove(timers,1)[2](); remaining=remaining-1 end
    assert(refreshed==current,"late quest response refreshes the current card, not its old owner")
    has(atlas.sourceQuestLink(63490),"|Hquest:63490:")
    frames[1].callback(nil,"QUEST_DATA_LOAD_RESULT",65653,false)
    atlas.sourceQuestLink(65653)
    assert(requested[65653]==1,"failed quest load does not create a retry loop")
    assert(atlas.sourceQuestLink(-1)==nil and requested[-1]==nil,"invalid quest ID is never requested")
    local grant = atlas.directMountGrants[221]
    local russian = atlas.sourceInlineLinks(grant.text)
    local english = atlas.sourceInlineLinks(grant.englishText)
    has(russian, "|Hquest:12687:0|h[Путь в Долину Теней]|h")
    has(english, "|Hquest:12687:0|h[Into the Realm of Shadows]|h")
    assert(requested[12687] == 1, "cold inline references share one request")
    local raw = "Фраза «в кавычках» и {quest:0:неверный ID}."
    assert(atlas.sourceInlineLinks(raw) == "Фраза «в кавычках» и неверный ID.", "arbitrary quotation stays plain")
end
do
    local requested, loaded = {}, {}
    C_Item = {
        GetItemInfo = function(id)
            if loaded[id] then return "Real item " .. id, "|cffa335ee|Hitem:" .. id .. ":0|h[Real item " .. id .. "]|h|r", loaded[id] end
        end,
        RequestLoadItemDataByID = function(id) requested[id] = (requested[id] or 0) + 1 end,
    }
    local source = "Bring {item:10:First item} and {item:20:Second item}; |Hitem:30|h[Existing link]|h."
    local formatted = atlas.sourceItemLinks(source)
    has(formatted, "Bring |Hitem:10|h[First item]|h and |Hitem:20|h[Second item]|h; |Hitem:30|h[Existing link]|h.")
    has(atlas.sourceItemLinks("Reward: {Item:10:First item}"), "Reward: |Hitem:10|h[First item]|h")
    atlas.sourceItemLinks(source)
    assert(requested[10] == 1 and requested[20] == 1 and requested[30] == nil, "exact item markup requests once")
    loaded[20] = 4
    frames[1].callback(nil, "ITEM_DATA_LOAD_RESULT", 20, true)
    has(atlas.sourceItemLinks(source), "|cffa335ee|Hitem:20:0|h[Real item 20]|h|r")
    assert(requested[20] == 1, "source links use the native cached quality link")
    C_Item.GetItemIconByID = function(id) if loaded[id] then return 1000 + id end end
    local decorated = atlas.cardItemIcons(atlas.sourceItemLinks(source))
    has(decorated, "|cffa335ee|Hitem:20:0|h|T1020:16:16|t [Real item 20]|h|r")
    has(decorated, "|Hitem:10|h[First item]|h")
    assert(atlas.cardItemIcons(decorated) == decorated and requested[10] == 1 and requested[30] == 1)
    local priced = "2 |Hitem:20|h|T1020:18:18|t|h"
    local withIcon = "|T1020:18:18|t |cffffffff|Hitem:20|h[Existing icon]|h|r"
    assert(atlas.cardItemIcons(priced) == priced)
    assert(atlas.cardItemIcons(withIcon) == "|T1020:18:18|t |cffa335ee|Hitem:20|h[Existing icon]|h|r")
    has(atlas.cardItemIcons("|T123:16:16|t |Hitem:20|h[Named item]|h"), "|Hitem:20|h|T1020:16:16|t [Named item]|h")
    local name, _, quality = atlas.sourceItemInfo(224025)
    assert(name == nil and quality == nil and requested[224025] == 1)
    assert(atlas.qualityText("Crackling Shard", quality) == "Crackling Shard")
    loaded[224025] = 4
    frames[1].callback(nil, "ITEM_DATA_LOAD_RESULT", 224025, true)
    quality = select(3, atlas.sourceItemInfo(224025))
    assert(atlas.qualityText("Crackling Shard", quality) .. " ×10" == "|cffa335eeCrackling Shard|r ×10")
    assert(atlas.mountDisplayQuality(2176) == 4 and requested[224025] == 1)
end
do
    local locale = "ruRU"
    local savedLocale = atlas.getLocale
    atlas.getLocale = function() return locale end
    local entry = { name = "Упряжь боевой медведицы Сухокожих", englishName = "Witherbark Warbear Harness" }
    assert(atlas.itemDisplayName(entry) == entry.name)
    assert(atlas.itemDisplayName(entry, "[Witherbark Warbear Harness]") == entry.name)
    assert(atlas.itemDisplayName(entry, "Witherbark Warbear Harness") == entry.name)
    assert(atlas.itemDisplayName(entry, "Имя из текущего клиента") == "Имя из текущего клиента")
    assert(atlas.itemDisplayName({ name = "[Untranslated]", englishName = "Untranslated" }) == nil)
    C_Item.GetItemInfo = function()
        return "[Witherbark Warbear Harness]", "|cffa335ee|Hitem:257225:0|h[Witherbark Warbear Harness]|h|r"
    end
    has(atlas.sourceItemLinks("{item:257225:Упряжь боевой медведицы Сухокожих}"),
        "|cffa335ee|Hitem:257225:0|h[Упряжь боевой медведицы Сухокожих]|h|r")
    locale = "enUS"
    assert(atlas.itemDisplayName(entry) == entry.englishName)
    assert(atlas.itemDisplayName(entry, "Witherbark Warbear Harness") == entry.englishName)
    C_Item.GetItemInfo = function() end
    has(atlas.sourceItemLinks("{item:257225:Witherbark Warbear Harness}"), "|Hitem:257225|h[Witherbark Warbear Harness]|h")
    atlas.getLocale = savedLocale
end
do
    assert(loadfile("Core/Sources.lua"))("PawAtlas", atlas)
    function atlas.sourceAvailableToCharacter(npc, guid) return not (npc == 3 and guid == "other") end
    local function point(map, npc, x, y, condition)
        return { map = map, npc = npc, x = x, y = y, boss = "Same name", condition = condition }
    end
    local base = point(1, 1, .3, .4)
    local rounded = point(1, 1, .3001, .4001)
    local differentMap = point(2, 1, .3, .4)
    local differentNPC = point(1, 3, .3, .4)
    local condition = point(1, 1, .3, .4, { mode = 16 })
    local noX = point(1, nil, nil, .5)
    local noY = point(1, nil, .5, nil)
    local duplicateNoX = point(1, nil, nil, .5)
    noX.boss, noY.boss, duplicateNoX.boss = "Object", "Object", "Object"
    atlas.navigationPoints[900001] = { rounded, differentMap, differentNPC, condition, point(1, 1, .3, .4, { mode = 16 }),
        noX, noY, duplicateNoX }
    local mount = { id = 900001, npcs = { 1 }, locations = { base } }
    local points = atlas.mountLocations(mount, "other", true)
    assert(#points == 5 and points[1] == base and points[2] == differentMap and points[3] == condition
        and points[4] == noX and points[5] == noY, "preserve order, context, map, and each missing coordinate independently")
    points = atlas.mountLocations(mount, "player", true)
    assert(#points == 6 and points[3] == differentNPC, "identical coordinates preserve a different NPC when eligible")

    local anotherRounded = point(1, 1, .3002, .4002)
    atlas.navigationPoints[mount.id] = { rounded, anotherRounded }
    points = atlas.mountLocations(mount, "player", true)
    assert(#points == 3 and points[2] == rounded and points[3] == anotherRounded, "ambiguous cross-feed matches retain both points")
    assert(#atlas.mountLocations({ id = 802 }, "player", true) == 120, "all reviewed crystal positions remain accessible")

    local faction = atlas.sourcePointFaction
    local savedFactions = atlas.npcSourceFactions
    atlas.npcSourceFactions = { [1] = "Horde" }
    assert(faction(point(1, 1, .3, .4)) == "Horde")
    assert(faction(point(1, 3, .3, .4)) == nil, "same position and name must not leak eligibility to another NPC")
    assert(faction(point(1, 1, .3, .4, "Альянс")) == "Alliance", "the specific point takes priority")
    assert(faction(point(1, 1, .3, .4, "Альянс\nОрда")) == nil, "ambiguous point metadata has no fixed faction")
    local explicit = point(1, 1, .3, .4, { mode = 16 })
    explicit.faction = "Alliance"
    assert(faction(explicit) == "Alliance", "explicit point faction works with structured conditions")
    atlas.npcSourceFactions = savedFactions
end
do
    local calls, disabled = {}, false
    local waypoint, tracking = { mapID = 1 }, true
    C_Map = {
        GetMapInfo = function(id)
            local row = atlas.sourceUiMaps[id]
            if row then return { mapID = id, name = row[2], parentMapID = row[3] } end
        end,
        SetUserWaypoint = function() error("opening the map must not write a waypoint") end,
        GetUserWaypoint = function() return waypoint end,
    }
    C_SuperTrack = {
        SetSuperTrackedUserWaypoint = function() error("opening the map must keep supertracking") end,
        IsSuperTrackingUserWaypoint = function() return tracking end,
    }
    Enum = { GameRule = { WorldMapDisabled = 9 } }
    C_GameRules = { IsGameRuleActive = function(rule) assert(rule == 9); return disabled end }
    OpenWorldMap = function(id) calls[#calls + 1] = id end
    local function source(place, map, mount)
        return atlas.sourceMapID(place, map and { map = map }, mount)
    end

    assert(source("Вневременный остров") == 554 and source("Timeless Isle") == 554, "verified names work without coordinates")
    assert(source("Oceanus Cove", 632, { sourceMap = 630 }) == 632, "active cave is distinct from its parent")
    assert(source("Azsuna", 632) == 630, "an unmatching active map must not replace the visible zone")
    assert(source("Азсуна · Бухта Океания") == 632, "resolve a confirmed generic parent/child address")
    assert(source("Isle of Dorn · Dornogal", 2248) == 2339, "confirmed child city overrides the parent")
    assert(source("Аз-Кахет · Город Нитей") == 2213, "child city is identified by the full address")
    assert(source("Ardenweald · Mistveil Tangle") == 1565, "reviewed subzone can fall back to its actual parent")
    assert(source("Расколотые острова · Даларан") == 627 and source("Broken Isles · Dalaran") == 627,
        "the Legion vendor address selects the Broken Isles Dalaran")
    assert(source("Шаттрат (Запределье)", 111) == 111 and source("Shattrath City (Outland)", 594) == 111
        and source("Shattrath City, Outland", 594) == 111,
        "qualified Shattrath selects the quest city in both locales")
    assert(source("Nagrand (Outland)") == 107 and source("Nagrand (Draenor)") == 550,
        "the parent distinguishes zones with the same name")
    assert(source("Nagrand (Northrend)", 107) == nil, "an unrelated parent must not match the active zone")
    assert(source("Karazhan") == nil and source("Karazhan", nil, { map = 532 }) == nil, "ambiguous name and instance ID are insufficient")
    assert(source("Karazhan", nil, { id = 168 }) == 350 and source("Return to Karazhan", 794) == 794, "distinct route maps retain the right instance")
    assert(source("Sethekk Halls", nil, { id = 185 }) == 258, "a curated route can identify a dungeon floor")
    assert(source("Крепость Бурь · Око") == 334 and source("Tempest Keep · The Eye") == 334,
        "both names open The Eye's instance map and not Netherstorm")
    assert(source("A place never seen", 554) == nil and source("Revendreth", nil, { id = 1391 }) == 1525, "avoid inventing a location")
    for place, id in pairs({ ["Изумрудный Сон"] = 2200, ["Stormsong"] = 942,
        ["Eye of Eternity"] = 141, ["The Isle of Dorn"] = 2248, ["Заралек"] = 2133, ["Обитель Света"] = 24 }) do
        assert(source(place) == id, "reviewed map alias drift: " .. place)
    end
    local prowler = { id = 1949, spell = 430225 }
    assert(source("Гилнеас") == nil and source("Гилнеас", nil, prowler) == 217 and source("Gilneas", nil, prowler) == 217,
        "the quest-specific route goes to the Ruins of Gilneas in both locales")
    assert(atlas.mapName(1565) == "Ardenweald", "tooltip names the actual fallback destination")

    for _, id in ipairs({ 554, 632, 630 }) do assert(atlas.openMap(id)) end
    assert(not atlas.openMap(nil) and not atlas.openMap(-1) and not atlas.openMap(900001), "invalid and unconfirmed IDs cannot open a map")
    disabled = true
    assert(not atlas.openMap(2339), "native disabled-map rule is respected")
    OpenWorldMap = nil
    assert(not atlas.openMap(2339), "a missing native API does not throw")
    assert(#calls == 3 and calls[1] == 554 and calls[2] == 632 and calls[3] == 630, "world map receives the exact click sequence")
    assert(C_Map.GetUserWaypoint() == waypoint and C_SuperTrack.IsSuperTrackingUserWaypoint(), "existing user waypoint stays tracked")
end
do
    local journal, faction = C_EncounterJournal, UnitFactionGroup
    local configured, delves = atlas.instanceEntranceWaypoints, atlas.delveEntranceWaypoints
    local instanceForMap, instanceInfo = EJ_GetInstanceForMap, EJ_GetInstanceInfo
    atlas.instanceEntranceWaypoints = { [9001] = {
        { map = 630, x = .6, y = .7 },
        { map = 554, x = .5, y = .6, faction = "Alliance", specific = true },
    } }
    atlas.delveEntranceWaypoints = { [9002] = { { map = 630, x = .7, y = .8 } } }
    local requested = {}
    C_EncounterJournal = { GetDungeonEntrancesForMap = function(map)
        requested[#requested + 1] = map
        return {
            { journalInstanceID = 123, position = { GetXY = function() return .1, .2 end } },
            { journalInstanceID = 9001, position = { GetXY = function() return .3, .4 end } },
        }
    end }
    UnitFactionGroup = function() return "Alliance" end
    EJ_GetInstanceForMap = function(map) if map == 632 then return 9001 end end
    EJ_GetInstanceInfo = function(id) if id == 9001 then return "Dungeon" end end
    local view = { sourcePlaceKind = "Подземелье", sourceMap = 632, place = "Dungeon" }
    atlas.resolveSourceInstance(view)
    assert(view.journalInstance == 9001, "the native UiMap lookup identifies the verified instance without encounter pins")
    local points = assert(atlas.instanceEntrancePoints(view))
    assert(#points == 2 and #requested == 1 and requested[1] == 630, "the service entrance and faction scope restrict native map queries")
    assert(points[1].entrance and points[1].map == 630 and points[1].x == .3 and not points[1].npc,
        "the exact native journal entrance replaces a single fallback on its map")
    assert(points[2].entrance and points[2].map == 554 and points[2].x == .5, "a specific portal preserves verified coordinates")
    UnitFactionGroup = function() return "Horde" end
    points = assert(atlas.instanceEntrancePoints(view))
    assert(#points == 1 and points[1].map == 630, "another faction does not inherit the restricted entrance")
    view.journalInstance = 9002
    assert(atlas.instanceEntrancePoints(view) == nil, "another JournalInstanceID does not inherit the native point")
    view.sourcePlaceKind, view.journalInstance, view.sourceMap = "Вылазка", nil, 9002
    points = assert(atlas.instanceEntrancePoints(view))
    assert(#points == 1 and points[1].map == 630 and points[1].x == .7, "a confirmed delve entrance uses its UiMapID")
    atlas.instanceEntranceWaypoints, atlas.delveEntranceWaypoints = configured, delves
    C_EncounterJournal, UnitFactionGroup = journal, faction
    EJ_GetInstanceForMap, EJ_GetInstanceInfo = instanceForMap, instanceInfo
end
do
    local locale = "ruRU"
    atlas.getLocale = function() return locale end
    GetLocale = function() return "ruRU" end
    C_CreatureInfo = { GetClassInfo = function(id) if id == 10 then return { className = "Native monk" } end end }
    local count = 0
    for id in pairs(atlas.mountClassRequirements) do
        locale = "ruRU"
        assert(atlas.mountClassName({ id = id }), "Russian class is visible with incomplete native API")
        locale = "enUS"
        assert(atlas.mountClassName({ id = id }), "English class is visible with a Russian native API")
        count = count + 1
    end
    assert(count >= 40 and atlas.mountClassName({ id = 893 }) == "Paladin", "Vigilant Charger requires Paladin")
    locale = "ruRU"
    assert(atlas.mountClassName({ id = 893 }) == "Паладин" and atlas.mountClassName({ id = 864 }) == "Native monk")
    assert(atlas.mountClassName({ id = 990 }) == nil, "Divine Steed movement appearance is not a class mount")
end
do
    local nativeCount, tomTomCount, tracking = 0, 0, false
    local nativePoint, tomTomTitle
    local function waypoint(map, x, y) return { map = map, x = x, y = y, name = "Vendor", place = "Zone" } end
    local first, second = waypoint(554, .4, .5), waypoint(554, .5, .6)
    local points = { first, second }
    C_Map = { CanSetUserWaypointOnMap = function() return true end,
        SetUserWaypoint = function(point) nativePoint = point; nativeCount = nativeCount + 1; return true end }
    UiMapPoint = { CreateFromCoordinates = waypoint }
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) tracking = on end }
    local installed = { AddWaypoint = function(_, _, _, _, options)
        tomTomTitle = options.title
        tomTomCount = tomTomCount + 1
        return {}
    end }
    TomTom, MountAtlasAccountDB = installed, { settings = { other = true } }
    assert(atlas.waypointPreference() == nil and atlas.waypointProvider() == "tomtom", "legacy auto-pick prefers available TomTom")
    assert(atlas.addSourceWaypoints(points) == 2 and tomTomCount == 2 and nativeCount == 0)
    assert(atlas.setWaypointProvider("wow") and not atlas.hasTomTomWaypoints() and atlas.addSourceWaypoints(points) == 0)
    assert(nativeCount == 0 and tomTomCount == 2, "changing provider and disabled bulk action preserve existing waypoints")
    atlas.openSource({}, first)
    assert(nativeCount == 1 and tomTomCount == 2 and tracking, "explicit WoW adds one tracked marker")
    assert(nativePoint.x == first.x and nativePoint.y == first.y, "WoW receives the selected marker")
    assert(atlas.setWaypointProvider("tomtom"))
    TomTom = nil
    assert(atlas.waypointPreference() == "tomtom" and atlas.waypointProvider() == "wow", "missing addon falls back without rewriting settings")
    atlas.openSource({}, second)
    assert(nativeCount == 2 and atlas.addSourceWaypoints(points) == 0, "WoW fallback is still a single waypoint only")
    TomTom = installed
    atlas.openSource({}, second)
    assert(atlas.waypointProvider() == "tomtom" and tomTomCount == 3 and nativeCount == 2 and MountAtlasAccountDB.settings.other,
        "reappearing TomTom restores the preference and preserves sibling settings")
    assert(tomTomTitle == "Vendor", "a single vendor marker keeps the seller's name")
end
do
    C_Reputation = nil
    local levels = { [2736] = 11, [2507] = 27, [2792] = 8 }
    local names = { [2736] = "Manaforge Vandals", [2507] = "Dragonscale Expedition", [2792] = "Ritual Sites" }
    C_MajorFactions = {
        GetMajorFactionIDs = function() return { 2736, 2507, 2792 } end,
        GetMajorFactionData = function(id)
            return names[id] and { name = names[id], isUnlocked = levels[id] ~= nil, renownLevel = levels[id] or 0 }
        end,
    }
    frames[1].callback(nil, "MAJOR_FACTION_UNLOCKED", 2736)
    local vandals = { id = 2555, journalSourceRaw = "Faction: Manaforge Vandals\nRenown: 14" }
    local expedition = { id = 1615, journalSourceRaw = "Faction: Dragonscale Expedition\nRenown: 25" }
    local ritual = { id = 2935, journalSourceRaw = "Renown: Ritual Sites Rank 8" }
    has(atlas.decorateSource(vandals), "14  (Текущая известность: 11)")
    local completed = atlas.decorateSource(expedition)
    has(completed, "25  (Текущая известность: 27)")
    has(completed, "ui-questtracker-tracker-check")
    has(atlas.decorateSource(ritual), "Ritual Sites Rank 8  (Текущая известность: 8)")
    levels[2736] = 0
    has(atlas.decorateSource(vandals), "14  (Текущая известность: 0)")
    levels[2736] = nil
    local unknown = atlas.decorateSource(vandals)
    has(unknown, "14  (Текущая известность: —)")
    assert(not unknown:find("ui-questtracker-tracker-check", 1, true))
    has(atlas.decorateSource(expedition), "25  (Текущая известность: 27)")
    C_MajorFactions = nil
    has(atlas.decorateSource(expedition), "25  (Текущая известность: —)")
end
do
    local active, level = 3, 45
    C_Covenants = { GetActiveCovenantID = function() return active end }
    C_CovenantSanctumUI = { GetRenownLevel = function() return level end }
    local nightFae = { id = 1484, journalSourceRaw = "Covenant: Night Fae\nRenown: 45" }
    local kyrian = { id = 1492, journalSourceRaw = "Ковенант: кирии\nИзвестность: 45" }
    has(atlas.decorateSource(nightFae), "45  (Текущая известность: 45)")
    has(atlas.decorateSource(nightFae), "ui-questtracker-tracker-check")
    has(atlas.decorateSource(kyrian), "45  (Текущая известность: —)")
    active, level = 1, 31
    has(atlas.decorateSource(kyrian), "45  (Текущая известность: 31)")
    assert(not atlas.decorateSource(kyrian):find("ui-questtracker-tracker-check", 1, true))
    has(atlas.decorateSource(nightFae), "45  (Текущая известность: —)")
    C_Covenants, C_CovenantSanctumUI = nil, nil
end
do
    local oldEncounter, oldInfo, oldMap = EJ_GetCreatureInfo, EJ_GetEncounterInfo, C_EncounterJournal
    local oldIndex, oldInstance = EJ_GetEncounterInfoByIndex, EJ_GetInstanceInfo
    local oldGUID, oldSecret = UnitGUID, issecretvalue
    local oldPortrait, oldDisplay = SetPortraitTexture, SetPortraitTextureFromCreatureDisplayID
    local oldDisplays, oldFaction, oldSuffix = atlas.sourceNpcDisplayIDs, atlas.characterFaction, atlas.sourceDifficultySuffix
    atlas.sourceNpcDisplayIDs = { [73167] = 51161, [142423] = 87654 }
    atlas.sourceDifficultySuffix = function(place) return place:match("^(.*) · Mythic$") end
    SetPortraitTexture, SetPortraitTextureFromCreatureDisplayID = function() end, function() end
    local units = { target = "Creature-0-0-0-0-314-0001" }
    UnitGUID = function(unit) return units[unit] end
    local function portrait(npc) return select(2, atlas.sourcePortrait(nil, { npc = npc })) end
    assert(portrait(73167) == 51161 and portrait(142423) == 87654)
    local _, _, _, unit, guid = atlas.sourcePortrait(nil, { npc = 314 })
    assert(unit == "target" and guid == units.target)
    units.target = "Creature-0-0-0-0-271-0002"
    assert(portrait(314) == nil and select(4, atlas.sourcePortrait(nil, { npc = 314 })) == nil,
        "an unverified NPC never inherits the previous unit's face")
    local function modelNpc(view, point) return select(6, atlas.sourcePortrait(nil, view, point)) end
    assert(modelNpc({ npc = 314 }) == 314, "an exact NPC without a texture can be loaded by the client")
    assert(modelNpc({ npc = 314 }, { npc = 152290, boss = "Soundless" }) == 152290)
    assert(modelNpc({ npcs = { 245692 } }) == 245692 and modelNpc({ npcs = { 245692, 152290 } }) == nil)
    assert(modelNpc({ npc = 314 }, { boss = "Different target" }) == nil,
        "an unrelated point never uses the previous NPC model")
    issecretvalue = function(value) return value == 9003 end
    assert(modelNpc({ npc = 9003 }) == nil and modelNpc({ npc = 3.5 }) == nil)
    local delayedPortrait
    function EJ_GetCreatureInfo(index, encounter)
        if encounter == 123 and index == 1 then return 1, "Anzu", nil, 18036, 607544 end
        if encounter == 456 and index <= 2 then return index, "Guardian", nil, 3000 + index end
        if encounter == 2343 and index == 1 then return 4982, "Lady Jaina Proudmoore", nil, 87892, 2497785 end
        if encounter == 2343 and index == 2 then return 8080, "Tide Elemental", nil, 9004, 9002 end
        if encounter == 457 and index == 1 then return 314, "Armor", nil, 9003, 9003 end
        if encounter == 458 and index == 1 then
            return 315, delayedPortrait and "Delayed boss", nil, delayedPortrait
        end
        if encounter == 459 and index == 1 then return 316, "No portrait", nil, 0, 0 end
        if encounter == 460 and index == 1 then return 317, "Placeholder", nil, 9900, 521744 end
        if encounter == 461 and index == 1 then return 318, "Placeholder", nil, 9900, 134400 end
        if encounter == 462 and index == 1 then return 319, "Placeholder", nil, 9900, "Interface\\Icons\\INV_Misc_QuestionMark.blp" end
        if encounter == 2439 and index == 1 then return 5265, "Kyra", nil, 100852, 4071445 end
        if encounter == 2439 and index == 2 then return 5263, "Skyja", nil, 100851, 0 end
    end
    local view = { npc = 73167, boss = "Anzu", journalEncounter = 123 }
    local file, display = atlas.sourcePortrait(nil, view, { npc = 142423, boss = "Anzu" })
    assert(file == nil and display == 87654, "the current point's NPC wins over the view and journal names")
    assert(atlas.sourcePortrait(nil, view) == 607544, "the matching journal icon wins over a local model display")
    units.target = "Creature-0-0-0-0-73167-0003"
    assert(select(4, atlas.sourcePortrait(nil, view)) == "target", "the exact live NPC wins over the journal")
    units.target = nil
    file, display = atlas.sourcePortrait(nil, view, { boss = "Different target" })
    assert(file == nil and display == nil, "a point without an NPC cannot inherit an unrelated portrait")
    assert(atlas.sourcePortrait(nil, { boss = "Anzu", journalEncounter = 123 }) == 607544)
    assert(atlas.sourcePortrait(nil, { boss = "Different target", journalEncounter = 123 }) == nil,
        "a lone journal creature is not a substitute for a differently named target")
    assert(select(2, atlas.sourcePortrait(nil, { boss = "Guardian", journalEncounter = 456 })) == nil,
        "ambiguous journal names do not select a portrait")
    assert(modelNpc({ npc = 9005, boss = "Armor", journalEncounter = 457 }) == 9005,
        "secret display and file IDs do not prevent exact NPC fallback")
    assert(modelNpc({ npc = 9005, boss = "Different target", journalEncounter = 457 }) == 9005,
        "the journal creature row ID is never passed to the NPC model API")
    local delayed = { boss = "Delayed boss", journalEncounter = 458 }
    assert(select(2, atlas.sourcePortrait(nil, delayed)) == nil)
    delayedPortrait = 9100
    assert(select(2, atlas.sourcePortrait(nil, delayed)) == 9100, "an incomplete journal creature is retried")
    file, display = atlas.sourcePortrait(nil, { boss = "No portrait", journalEncounter = 459 })
    assert(file == nil and display == nil, "zero file and display IDs produce the category fallback")
    for encounter = 460, 462 do
        file, display = atlas.sourcePortrait(nil, { boss = "Placeholder", journalEncounter = encounter })
        assert(file == nil and display == 9900, "a placeholder journal file does not replace a valid creature display")
    end

    C_EncounterJournal = { GetEncountersOnMap = function(map)
        return map == 1352 and { { encounterID = 2343 } } or {}
    end }
    EJ_GetEncounterInfo = function(id)
        if id == 2343 then return "Lady Jaina Proudmoore", nil, id, nil, nil, 1176 end
        if id == 2439 then return "The Nine", nil, id, nil, nil, 1193 end
        if id == 1997 then return "Antoran High Command", nil, id, nil, nil, 946 end
    end
    for _, name in ipairs({ "Джайна Праудмур", "Jaina Proudmoore" }) do
        local jaina = { id = 1219, boss = name, hasSourcePanels = true, sourceKind = "Босс", sourceMap = 1352 }
        atlas.resolveSourceEncounter(jaina)
        assert(jaina.journalEncounter == 2343 and jaina.journalInstance == 1176 and jaina.journalDifficulty == 16)
        file, display = atlas.sourcePortrait(nil, jaina)
        assert(file == 2497785 and display == 87892, "the named raid boss is selected separately from the other journal creatures")
    end
    local otherMap = { id = 1, boss = "Jaina Proudmoore", hasSourcePanels = true, sourceKind = "Босс", sourceMap = 1 }
    atlas.resolveSourceEncounter(otherMap)
    assert(otherMap.journalEncounter == nil, "the encounter alias is only used on a source map containing that encounter")
    assert(atlas.sourcePortrait(nil, { boss = "Different target", journalEncounter = 2343 }) == nil)
    assert(atlas.sourcePortrait(nil, { boss = "Jaina Proudmoore", journalEncounter = 2343 }, { boss = "Jaina Proudmoore" }) == nil,
        "an independently selected point does not inherit the encounter-title alias")
    assert(atlas.sourcePortrait(nil, { boss = "The Nine", journalEncounter = 2439 }) == 4071445,
        "the exact named encounter uses its native first creature portrait")
    assert(select(2, atlas.sourcePortrait(nil, { boss = "Skyja", journalEncounter = 2439 })) == 100851,
        "an explicitly named council member keeps its own display")

    C_EncounterJournal.GetEncountersOnMap = function(map) return map == 910 and { { encounterID = 1997 } } or {} end
    EJ_GetInstanceInfo = function(id)
        if id == 946 then return "Antorus", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, true end
    end
    local duplicate = false
    EJ_GetEncounterInfoByIndex = function(index, instance)
        assert(instance == 946, "the scan is restricted to the source map's verified journal instance")
        if index == 1 then return "Argus the Unmaker", nil, 8766, nil, nil, 947 end
        if index == 2 then return "Argus the Unmaker", nil, 2031, nil, nil, 946 end
        if index == 3 and duplicate then return "Argus the Unmaker", nil, 8767, nil, nil, 946 end
    end
    local function argus()
        return { id = 954, boss = "Argus the Unmaker", sourceKind = "Босс", sourcePlaceKind = "Рейд", hasSourcePanels = true, sourceMap = 910 }
    end
    local offFloor = argus()
    atlas.resolveSourceEncounter(offFloor)
    assert(offFloor.journalEncounter == 2031 and offFloor.journalInstance == 946, "an encounter can be on another floor of the instance")
    duplicate, offFloor = true, argus()
    atlas.resolveSourceEncounter(offFloor)
    assert(offFloor.journalEncounter == nil, "two same-named encounters remain ambiguous")

    local function reviewed(mountID, boss, place, map)
        local route = { sourceKind = "Босс", boss = boss, place = place, sourceMap = map }
        local mount = { id = mountID, sourceGroups = { route } }
        return select(6, atlas.sourcePortrait(mount, route))
    end
    assert(reviewed(883, "Nightbane", "Return to Karazhan", 814) == 114895)
    assert(reviewed(883, "Nightbane", "Return to Karazhan · Mythic", 814) == 114895)
    assert(reviewed(883, "Nightbane", "Karazhan", 814) == nil and reviewed(883, "Attumen", "Return to Karazhan", 814) == nil)
    local journalQueries = 0
    C_EncounterJournal.GetEncountersOnMap = function() journalQueries = journalQueries + 1; return {} end
    local nightbane = { id = 883, boss = "Nightbane", place = "Return to Karazhan", sourceMap = 814,
        sourceKind = "Босс", hasSourcePanels = true }
    atlas.resolveSourceEncounter(nightbane)
    assert(journalQueries == 0, "the reviewed seasonal or hidden boss route does not scan the guide")
    nightbane.boss = "Different target"
    atlas.resolveSourceEncounter(nightbane)
    assert(journalQueries == 1, "the no-journal fact belongs to the reviewed target only")
    local side = "Alliance"
    atlas.characterFaction = function() return side end
    assert(reviewed(2023, "Daetan Swiftplume", "Durotar · Elwynn Forest") == 213665)
    assert(reviewed(2023, "Daetan Swiftplume", "Durotar · Elwynn Forest", 1) == nil)
    side = "Horde"
    assert(reviewed(2023, "Daetan Swiftplume", "Durotar · Elwynn Forest") == 218738)
    side = nil
    assert(reviewed(2023, "Daetan Swiftplume", "Durotar · Elwynn Forest") == nil)

    atlas.sourceNpcDisplayIDs = oldDisplays
    atlas.characterFaction, atlas.sourceDifficultySuffix = oldFaction, oldSuffix
    EJ_GetCreatureInfo, EJ_GetEncounterInfo, C_EncounterJournal = oldEncounter, oldInfo, oldMap
    EJ_GetEncounterInfoByIndex, EJ_GetInstanceInfo = oldIndex, oldInstance
    UnitGUID, issecretvalue = oldGUID, oldSecret
    SetPortraitTexture, SetPortraitTextureFromCreatureDisplayID = oldPortrait, oldDisplay
end
do
    local savedMapName, savedFaction = atlas.mapName, UnitFactionGroup
    atlas.mapName = function(id) return "Map " .. id end
    local faction = "Alliance"
    UnitFactionGroup = function() return faction end
    local function waypoints(id, existing, properties)
        local mount = { id = id, spell = atlas.questMountRewards[id].spell }
        local choice = properties or { classification = { key = "quest", state = "current" } }
        return atlas.questRewardWaypoints(mount, choice, existing)
    end
    local cobalt = assert(waypoints(188))[1]
    local letter = assert(waypoints(865))[1]
    assert(letter.map == 739 and letter.x == .429 and letter.y == .457 and letter.npc == 119943)
    assert(letter.boss == atlas.dataName(atlas.questGiverNames[119943]))
    has(letter.condition, "|Hquest:46337:")
    assert(cobalt.map == 111 and cobalt.npc == 23462 and cobalt.quest == 11109 and cobalt.x == .678 and cobalt.y == .172)
    local original = { map = 124, x = .5259, y = .3449, quest = 12687, npc = 28653 }
    local knight = assert(waypoints(221, { original }))[1]
    assert(knight.x == original.x and knight.y == original.y and original.questNavigation == nil,
        "preserve verified existing precision without modifying the base point")
    local gorgon = assert(waypoints(1385))[1]
    assert(gorgon.map == 1525 and gorgon.quest == 58440 and gorgon.npc == 160941)
    assert(waypoints(55)[1].quest == 29034 and waypoints(311) == nil,
        "Rivern Frostwind is Alliance-only, Mor'vek is Horde-only")
    assert(waypoints(1683, nil, { classification = { key = "purchase", state = "current" }, vendor = {} }) == nil)
    assert(waypoints(1385, nil, { classification = { key = "quest", state = "current" }, questChain = {} }) == nil)
    local otto = assert(waypoints(1656))[1]
    assert(otto.npc == 199563 and otto.map == 2022 and otto.x == .20 and otto.y == .40 and not atlas.questGiverWaypoints[72738],
        "the hidden Otto trigger remains a final interaction, not an ordinary quest giver")
    has(otto.condition, "Финальное взаимодействие")
    local sameGiver = assert(waypoints(861))
    assert(#sameGiver == 2 and sameGiver[1].quest == 45789 and sameGiver[1].npc == sameGiver[2].npc)
    assert(waypoints(1043) == nil, "a restricted quest waypoint stays on its confirmed faction")
    faction = "Horde"
    assert(waypoints(311)[1].quest == 13906 and waypoints(55) == nil)
    local kuafon = assert(waypoints(1043))[1]
    assert(kuafon.quest == 50944 and kuafon.npc == 135744 and kuafon.x == .706 and kuafon.y == .506,
        "the two Kua'fon spawns have different known coordinates")
    assert(waypoints(656) == nil, "the invitation starts the quest without a fixed map point")
    local deathlord = assert(waypoints(866))[1]
    assert(deathlord.quest == 46719 and deathlord.map == 646 and deathlord.npc == 117573
        and deathlord.x == .44 and deathlord.y == .626, "Thalanor gives the first quest on the Broken Shore")
    local questChoice = { classification = { key = "quest", state = "current" } }
    local invitation = { id = 656, spell = 171850 }
    local reward = assert(atlas.directQuestReward(invitation, questChoice))
    assert(reward.starter == 140495 and reward.prerequisites[1].id == 44057 and reward.quests[1].id == 44058)
    assert(atlas.questRouteGuide(invitation, questChoice).starter.englishText:find("Paragon", 1, true))
    assert(atlas.questRouteGuide(invitation, { classification = questChoice.classification, contextOnly = true }) == nil)
    assert(atlas.sourceNavigationHidden({ id = 1441, spell = 344577 }))
    assert(atlas.sourceNavigationHidden({ id = 1948, spell = 428068 }))
    assert(atlas.sourceNavigationHidden({ id = 2561, spell = 1233561 }))
    assert(atlas.sourceNavigationHidden({ id = 2749, spell = 1260356 }))
    local humility = { id = 1395, spell = 334386, kind = "Добыча" }
    assert(atlas.sourceNavigationHidden(humility) and not atlas.navigationPoints[humility.id])
    assert(loadfile("Core/VendorSources.lua"))("PawAtlas", atlas)
    local vendor = assert(atlas.extraCovenantPurchase(humility))
    assert(vendor.npc == 174937 and vendor.map == 1708 and vendor.x == .6291 and vendor.y == .3090)
    assert(not atlas.sourceNavigationHidden(humility, { vendor = vendor }))
    assert(atlas.classifyMountSource(humility).key == "loot")
    assert(atlas.classifyMountSource(humility, { vendor = vendor }).key == "purchase")
    has(vendor.conditions, "5000 |Hcurrency:1813|h")
    has(vendor.conditions, "100 |Hcurrency:1885|h")
    assert(not vendor.conditions:find("Известность", 1, true) and not vendor.conditions:find("Renown", 1, true))
    local dugal = assert(waypoints(2980))[1]
    assert(dugal.map == 2509 and dugal.quest == 96305 and dugal.npc == 264611,
        "the vault waypoint refers only to Du'gal")
    faction = nil
    assert(waypoints(55) == nil and waypoints(311) == nil and waypoints(188)[1].quest == 11109,
        "unknown player faction may only see unrestricted quest waypoints")
    atlas.mapName, UnitFactionGroup = savedMapName, savedFaction
end
do
    local guildOffer = atlas.reviewedVendorOffers[619]
    local boar = { id = 619, spell = guildOffer.spell, journalSourceRaw = guildOffer.native[2] }
    boar.journalSourceOverride, boar.reviewedVendorOffer = atlas.reviewedVendorSource(boar)
    local guildVendors = assert(atlas.vendorSources(boar))
    assert(#guildVendors == 2 and guildVendors[1].faction == "Alliance" and guildVendors[2].faction == "Horde")
    local terms = guildVendors[1].conditions
    has(terms, "|Hachievement:9669|h")
    has(terms, "4000|TInterface")
    local savedReputation, standing = C_Reputation, 7
    C_Reputation = { GetGuildFactionData = function() return standing and { reaction = standing } end }
    local function standingText()
        return atlas.decorateSource({ id = 619, journalSourceRaw = terms, purchaseRequirement = true })
    end
    has(standingText(), "Почтение")
    standing = 8
    has(standingText(), "ui-questtracker-tracker-check")
    standing = nil
    has(standingText(), "Текущая репутация: —")
    C_Reputation = savedReputation
end
do
    local savedLocale, savedItem, savedTradeSkill = atlas.getLocale, C_Item, C_TradeSkillUI
    local craftText = atlas.mountCraftReagentText
    local recipes = atlas.protoformMountRecipes
    C_Item, C_TradeSkillUI = nil, nil
    atlas.getLocale = function() return "enUS" end
    local function slotText(count, id)
        local reagent = assert(atlas.protoformReagentNames[id])
        return ("%d |Hitem:%d|h|TInterface\\Icons\\%s:0:0|t|h"):format(count, id, reagent.icon)
    end
    local known = 0
    for itemID, recipe in pairs(recipes) do
        local text = assert(craftText(itemID))
        known = known + 1
        assert(atlas.mountCraftRecipes[itemID] == recipe.spell and #recipe.slots == 3)
        local slots = {}
        for _, slot in ipairs(recipe.slots) do
            slots[#slots + 1] = slotText(slot[1], slot[2])
        end
        assert(text == "Реагенты: " .. table.concat(slots, " + "), "each ingredient has a separate icon link")
    end
    assert(known == 24 and not craftText(188808), "the quest reward Patient Bufonid has no crafting recipe")
    for itemID, slots in pairs(atlas.mountCraftFallbackSlots) do
        local text = assert(craftText(itemID))
        for _, slot in ipairs(slots) do
            local id = slot[2]
            local info = assert(atlas.craftReagentInfo[id])
            has(text, ("%d |Hitem:%d|h|TInterface\\Icons\\%s:0:0|t|h"):format(slot[1], id, info.icon))
        end
    end
    atlas.getLocale = function() return "ruRU" end
    has(craftText(188809), table.concat({ slotText(350, 188957), slotText(1, 189178), slotText(1, 187633) }, " + "))

    local output, slots = 188808, {}
    C_TradeSkillUI = { GetRecipeSchematic = function(id, recraft)
        assert(id == 365062 and recraft == false)
        return { outputItemID = output, reagentSlotSchematics = slots }
    end }
    has(craftText(188809), slotText(350, 188957))
    output = 188809
    for _, slot in ipairs(recipes[188809].slots) do
        slots[#slots + 1] = {
            required = true, quantityRequired = slot[1] + 1, reagents = { { itemID = slot[2] } },
        }
        if #slots < 3 then has(craftText(188809), slotText(350, 188957)) end
    end
    has(craftText(188809), slotText(351, 188957))
    local requested = {}
    C_Item = {
        GetItemIconByID = function(id) return id == 188957 and 123456 or nil end,
        GetItemInfo = function(id)
            if id == 188957 then return "Частица творения", "|cffffffff|Hitem:188957:0:0|h[Частица творения]|h|r" end
        end,
        RequestLoadItemDataByID = function(id) requested[id] = (requested[id] or 0) + 1 end,
    }
    has(craftText(188809), "351 |cffffffff|Hitem:188957:0:0|h|T123456:0:0|t|h|r")
    has(craftText(188809), slotText(2, 189178))
    assert(requested[189178] == 1 and requested[187633] == 1 and requested[188957] == nil)
    atlas.getLocale, C_Item, C_TradeSkillUI = savedLocale, savedItem, savedTradeSkill
end
do
    local craftText = atlas.mountCraftReagentText
    local savedSlots, savedInfo = atlas.mountCraftFallbackSlots, atlas.craftReagentInfo
    local savedItem, savedTradeSkill = C_Item, C_TradeSkillUI
    atlas.mountCraftFallbackSlots = { [65891] = { { 1, 65892 }, { 8, 65893, 65894 } } }
    atlas.craftReagentInfo = {
        [65892] = { icon = "inv_alchemy_enchantedvial" },
        [65893] = { icon = "inv_misc_dust_06" },
        [65894] = { icon = "inv_misc_truegold" },
    }
    C_Item, C_TradeSkillUI = nil, nil
    local fallback = assert(craftText(65891))
    has(fallback, "1 |Hitem:65892|h|TInterface\\Icons\\inv_alchemy_enchantedvial:0:0|t|h + "
        .. "8 |Hitem:65893|h|TInterface\\Icons\\inv_misc_dust_06:0:0|t|h/|Hitem:65894|h|TInterface\\Icons\\inv_misc_truegold:0:0|t|h")
    local slots = { { required = true, quantityRequired = 2, reagents = { { itemID = 65892 } } } }
    C_TradeSkillUI = { GetRecipeSchematic = function(id, recraft)
        assert(id == 93328 and recraft == false)
        return { outputItemID = 65891, reagentSlotSchematics = slots }
    end }
    assert(craftText(65891) == fallback, "partial recipe schematics preserve all verified fallback slots")
    slots[2] = { required = true, quantityRequired = 11, reagents = { {} } }
    assert(craftText(65891) == fallback, "a required reagent without an item ID is incomplete")
    slots[2].reagents = { { itemID = 65893 }, { itemID = 65894 } }
    slots[3] = { required = true, hiddenInCraftingForm = true, quantityRequired = 20, reagents = { { itemID = 65894 } } }
    local live = assert(craftText(65891))
    has(live, "2 |Hitem:65892")
    has(live, " + 11 |Hitem:65893")
    assert(not live:find("20 |Hitem:", 1, true), "hidden slots are excluded from the reagent row")
    atlas.mountCraftFallbackSlots, atlas.craftReagentInfo = savedSlots, savedInfo
    C_Item, C_TradeSkillUI = savedItem, savedTradeSkill
end
do
    local mount = { id = 1834, spell = 427041, kind = "Квест" }
    local direct = assert(atlas.directQuestReward(mount, {}))
    assert(direct.quests[1].id == 77762 and direct.quests[1].item == 210774)
    local item = assert(atlas.questRewardItem(mount, direct))
    assert(item.item == 210774 and item.quality == 4 and item.icon)
    assert(item.name == "Поводья охряного ящера из Сна" and item.englishName == "Reins of the Ochre Dreamtalon")
    assert(not atlas.questRewardItem(mount, atlas.directQuestReward(mount, { separateSource = true })))
    assert(not atlas.questRewardItem({ id = mount.id, spell = mount.spell + 1 }, direct))

    local gearglider = { id = 1482, spell = 353264, kind = "Квест" }
    local geargliderReward = assert(atlas.directQuestReward(gearglider, {}))
    local geargliderItem = assert(atlas.questRewardItem(gearglider, geargliderReward, geargliderReward.journalDetail.source))
    assert(geargliderItem.item == 186639 and geargliderItem.quality == 4)
    assert(geargliderItem.icon == "Interface\\Icons\\inv_brokermount_light")
    assert(geargliderItem.name == "Техноглайдер попечителя картеля Зи"
        and geargliderItem.englishName == "Xy Trustee's Gearglider")
    assert(atlas.questRewardItem(gearglider, geargliderReward, geargliderReward.journalDetail.englishSource))
    has(geargliderReward.journalDetail.source, "{journal:1302:Манагорн Омега}")
    has(geargliderReward.journalDetail.englishSource, "{journal:1302:Manaforge Omega}")
    assert(not atlas.questRewardItem(gearglider, geargliderReward, "|Hitem:186639:0|h[Reward]|h"))

    local beforeFaction, faction = UnitFactionGroup, nil
    function UnitFactionGroup() return faction end
    local branches = { spell = mount.spell, quests = {
        { id = 1, item = 210774, faction = "Alliance" }, { id = 2, item = 100, faction = "Horde" },
    } }
    assert(not atlas.questRewardItem(mount, branches), "different rewards do not pick an arbitrary branch")
    faction = "Alliance"
    assert(atlas.questRewardItem(mount, branches).item == 210774)
    faction = "Horde"
    assert(atlas.questRewardItem(mount, branches).item == 100)
    assert(not atlas.questRewardItem(mount, { spell = mount.spell, quests = { branches.quests[1] } }))
    UnitFactionGroup = beforeFaction
end
print("passed: achievement counterparts, source links, waypoint identity, world map routing, class labels, renown, NPC portrait identity, quest givers, quest reward items and protoform recipes")
