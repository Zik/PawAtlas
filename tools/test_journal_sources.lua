-- Run from the repository root: lua5.1 tools/test_journal_sources.lua
assert(_VERSION == "Lua 5.1", "This test requires Lua 5.1")

local function equal(actual, expected, scenario)
    assert(actual == expected, ("%s: expected %s, got %s"):format(scenario, tostring(expected), tostring(actual)))
end

local atlas = { mounts = {}, rares = {} }
local translations, language = {}, "ruRU"
local journalEvents
function GetLocale() return language end
function atlas.getLocale() return language end
function GetTime() return 0 end
function CreateFrame()
    return {
        RegisterEvent = function(self, event)
            self[event] = true
            if event == "NEW_MOUNT_ADDED" then journalEvents = self end
        end,
        SetScript = function(self, script, callback) self[script] = callback end,
    }
end
local function journalEvent(event, ...)
    assert(journalEvents[event], "journal event is registered: " .. event)
    journalEvents:OnEvent(event, ...)
end
function atlas.addTranslations(locale, values)
    if locale == "enUS" then for key, value in pairs(values) do translations[key] = value end end
end
function atlas.L(text, ...)
    local localized = language == "enUS" and translations[text] or text
    return select("#", ...) > 0 and localized:format(...) or localized
end
assert(loadfile("Locales/enUS_Sources.lua"))("PawAtlas", atlas)
assert(loadfile("Data/JournalData.lua"))("PawAtlas", atlas)
assert(loadfile("Data/QuestSources.lua"))("PawAtlas", atlas)
assert(loadfile("Data/LootSources.lua"))("PawAtlas", atlas)
assert(loadfile("Data/Mounts.lua"))("PawAtlas", atlas)
for _, mountID in ipairs({ 538, 539, 540 }) do
    local container = assert(atlas.mountRewardContainerRewards[mountID], "Primal Raptor source must identify its opening container")
    equal(container.item, 94296, "Primal Raptor uses the Cracked Primal Egg container")
    equal(container.contentsRate, 3, "Each Primal Raptor has an estimated one-in-three chance per opened egg")
    equal(atlas.attemptStages[mountID].item.rate, 100, "The chance to loot the egg is separate from its contents")
    equal(#container.mountIDs, 3, "Cracked Primal Egg has three documented mount outcomes")
    equal(container.text, "Из созревшего яйца выпадет один из трёх древних ящеров.", "container outcome wording")
    for index, outcomeID in ipairs({ 538, 539, 540 }) do
        equal(container.mountIDs[index], outcomeID, "container outcome IDs are stable and ordered")
    end
end
equal(atlas.mountRewardContainerRewards[538], atlas.mountRewardContainerRewards[539], "container metadata is shared across the three outcomes")
equal(atlas.mountRewardContainerRewards[539], atlas.mountRewardContainerRewards[540], "container metadata is shared across the three outcomes")
for _, route in ipairs({ { 16, 260916, 268730, 2500 }, { 1407, 181818, 184104, 500 }, { 1449, 186489, 187181, 100 } }) do
    local id, reward, egg, rate = unpack(route)
    local grant, stages = atlas.guaranteedRewards[id], atlas.attemptStages[id]
    equal(grant.item, reward, "the guarantee is for the mount item")
    equal(grant.method, "egg", "the guarantee requires hatching the egg")
    equal(grant.rate, 1, "hatching the egg guarantees this mount")
    equal(grant.reagent.item, egg, "the guarantee names the correct prerequisite")
    equal(atlas.lootItems[id].basis, "egg", "the card identifies the incubation stage")
    equal(stages.item.item, egg, "the tracked attempt still targets the egg")
    equal(stages.item.rate, rate, "getting the egg keeps its own drop estimate")
end
do
    local lasso, stage = atlas.guaranteedRewards[1311], atlas.attemptStages[1311]
    equal(lasso.item, 174752, "using the lasso guarantees the mount item")
    equal(lasso.rate, 1, "successful capture is deterministic")
    equal(lasso.reagent.item, stage.item.item, "the guaranteed route uses the tracked lasso")
    equal(stage.item.rate, 100, "the rate of looting the lasso is kept separate")
end
atlas.collectionCategory = function() return "Other" end
assert(loadfile("Core/JournalIndex.lua"))("PawAtlas", atlas)
assert(loadfile("Core/Sources.lua"))("PawAtlas", atlas)
assert(loadfile("Core/VendorSources.lua"))("PawAtlas", atlas)
assert(loadfile("Core/SourceDetails.lua"))("PawAtlas", atlas)
assert(loadfile("UI/Theme.lua"))("PawAtlas", atlas)
assert(loadfile("UI/DifficultyBadge.lua"))("PawAtlas", atlas)
local inlineItems = "Bring {item:10:First item} and {item:20:Second item}."
equal(atlas.normalizeSource(inlineItems), inlineItems, "inline item markup is not a source heading")
equal(atlas.normalizeSource("|cFFFFD200Торговец:|r искатель зари Крисек|n|cFFFFD200в:|r Танаанские джунгли"),
    "Торговец: искатель зари Крисек\nМесто: Танаанские джунгли", "native ruRU location header is a structured field")
equal(atlas.normalizeSource("в: обычный текст\nИщи в: Танаанских джунглях"),
    "в: обычный текст\nИщи в: Танаанских джунглях", "an unstyled preposition is not a place field")
local deathKnightGrant = atlas.directMountGrants[221]
for _, sentence in ipairs({ deathKnightGrant.text, deathKnightGrant.englishText }) do
    equal(atlas.normalizeSource(sentence), sentence, "inline quest markup is not a source heading")
end
equal(atlas.decorateSource({ id = 221, journalSourceRaw = deathKnightGrant.text }),
    "В начальной цепочке рыцаря смерти выполни задание |cffffff00|Hquest:12687:0|h[Путь в Долину Теней]|h|r.",
    "native hyperlink survives the full card decoration path with a cold quest cache")
local alternativeQuestMounts = { 1615, 1616, 1653, 1655, 1657, 1659, 1683, 1684, 1685, 1686 }
for _, locale in ipairs({ "ruRU", "enUS" }) do
    language = locale
    for _, id in ipairs(alternativeQuestMounts) do
        local reward = atlas.questMountRewards[id]
        local choice = assert(atlas.extraQuestRewardSource({ id = id, spell = reward.spell }))
        local rendered = atlas.decorateSource(choice.view)
        for _, quest in ipairs(reward.quests) do
            local link = ("|Hquest:%d:0|h[%s]|h"):format(quest.id, atlas.dataName(quest))
            assert(rendered:find(link, 1, true), "alternate quest route must contain the exact native link " .. id)
        end
        assert(not rendered:find("{[Qq]uest:") and not rendered:find("[[", 1, true),
            "alternative quest UI must not expose its markup " .. id)
    end
end
language = "ruRU"

local entries, ids = {}, {}
local journalCalls = { list = 0, info = 0, extra = 0 }
local function add(id, category, source, spell)
    entries[id] = { category = category, source = source, spell = spell or id,
        name = atlas.englishNames[id] or tostring(id), collected = false }
    ids[#ids + 1] = id
end
C_MountJournal = {
    GetMountIDs = function()
        journalCalls.list = journalCalls.list + 1
        return ids
    end,
    GetMountInfoByID = function(id)
        journalCalls.info = journalCalls.info + 1
        journalCalls.lastID = id
        local entry = entries[id]
        if entry then return entry.name, entry.spell, nil, false, true, entry.category, false, false, nil, false, entry.collected, id end
    end,
    GetMountInfoExtraByID = function(id)
        journalCalls.extra = journalCalls.extra + 1
        local entry = entries[id]
        if entry then return nil, "", entry.source end
    end,
}

-- API indices are BATTLE_PET_SOURCE_1..12, rather than DB2's 0..11.
local expected = { "Добыча", "Квест", "Торговец", "Профессия", "Битвы питомцев", "Достижение",
    "Событие", "Акция", "Карточная игра", "Магазин", "Исследование", "Торговая лавка" }
for category = 1, #expected do add(90000 + category, category, "") end
for _, category in ipairs({ -1, 0, 13 }) do add(91000 + category, category, "") end

-- Real zone-only journal sources have no Drop heading to mask a wrong index.
-- Rarity CE DB/Mounts/BattleForAzeroth.lua links each spell/item to NPC loot.
local zoneDrops = {
    { 928, 237286, 163576, "Vol'dun" },
    { 956, 243795, 163575, "Nazmir" },
    { 1018, 260174, 163574, "Drustvar" },
    { 1019, 260175, 163573, "Stormsong Valley" },
}
for _, entry in ipairs(zoneDrops) do add(entry[1], 1, "Zone: " .. entry[4], entry[2]) end
add(92001, 1, "Quest: Current route")
add(92002, 2, "Drop: Current source\nZone: Open world")
add(92003, 1, "Задание: Текущий маршрут")
add(92004, 2, "Источник: Текущая добыча\nЗона: Открытый мир")
add(92005, 1, "Legacy")
add(92006, 2, nil)
add(92008, 1, "Drop: Rare\n\nAchievement: A separate route")
add(92009, 1, "Drop: A note mentions an achievement")
add(631, 1, "|cFFFFD200Задание гарнизона:|r Это корабль... нет, самолет... Нет, это просто речное чудище.|n", 171826)
add(92010, 0, "Feats of Strength: A real source")
add(92011, 1, "Exploration: A real source")
add(92012, 1, "Bring supplies: food and water.\nZone: Open world")
add(92013, 1, "Drop: {item:269836:Chubs}\nZone: Open world")
add(1324, 11, "Zone: Vol'dun", 316493)
add(802, 11, "Зона: Азсуна", 215159)
add(1414, 1, "|cFFFFD200NPC:|r мертвая Савраска |n|cFFFFD200Зона:|r Ревендрет|n |n", 339588)
add(16, 4, "Profession: Fishing in Voidstorm", 3363)
add(312, 4, "Профессия: рыбная ловля", 64731)
add(982, 4, "Profession: Fishing", 253711)
add(1166, 4, "Profession: Fishing", 278803)
add(1434, 1, "Drop: Hirukon\nZone: Zereth Mortis", 342680)
add(250, 1, "Drop: Sartharion\nZone: The Obsidian Sanctum", 59571)
add(253, 1, "|cFFFFD200Источник:|r Сартарион", 59650)
add(2805, 1, "Drop: The Restless Heart\nZone: Windrunner Spire (Mythic)", 1263635)
add(2817, 1, "Drop: Degentrius\nZone: Magisters' Terrace (Mythic)", 1265784)
add(1369, 3, "Covenant: Necrolords\nVendor: Su Zettai\nZone: Maldraxxus\nCost: 3000", 332464)
add(1484, 1, "Covenant: Night Fae\nZone: Ardenweald", 353856)
add(1395, 1, "|cFFFFD200Ковенант: |rкирии|n|cFFFFD200Зона: |rБастион", 334386)
add(2950, 1, "Drop: Rotmire\nLocation: Sporefall", 1284973)
add(2821, 6, '|cFFFFD200Достижение: |r"Гладиатор: 2-й сезон Midnight"|n|cFFFFD200Категория: |rPvP', 1266211)
add(1351, 1, "|cFFFFD200PvP:|r Shadowlands, 1-й сезон|nСезонная награда", 327407)
add(2571, 1, "|cFFFFD200PvP:|r The War Within: Season 3|nRated Arena and Rated Battleground Season Reward", 1234821)
add(422, 6, "Achievement: Veteran of the Alliance II\nCategory: Rated Battleground", 100332)
add(3133, 8, "|cFFFFD200Промоакция|r", 1311627)
add(2781, -1, "", 1261369)
for _, id in ipairs({ 2779, 2961 }) do
    local detail = atlas.journalSourceDetails[id]
    add(id, 1, "|cFFFFD200Место проведения ритуалов:|r Разрушенный трон", detail.spell)
end
add(1943, 7, "|cFFFFD200Событие:|r 20-я годовщина World of Warcraft?|n", 428013)
add(1794, 6, "|cFFFFD200Achievement: |rWhodunnit?|n|cFFFFD200Event: |rSecrets of Azeroth", 418078)
add(17, 1, "|cFFFFD200Класс: |rчернокнижник", 5784)
add(84, 1, "|cFFFFD200Paladin|r", 23214)
add(367, 1, "|cFFFFD200Legacy|r|n", 73629)
add(368, 2, "|cFFFFD200Задание.|r |n", 73630)
add(780, 1, "|cFFFFD200Класс:|r охотник на демонов", 200175)
add(221, 3, "|cFFFFD200Trainer:|r Death Knight|n", 48778)
add(937, 1, "|cFFFFD200Legacy|r |n", 239770)
add(1735, 7, "Zone: Zaralek Cavern\nEvent: Researchers Under Fire", 408651)
add(196, 9, "Vendor: Landro Longshot\nZone: Booty Bay", 42776)
add(1285, 6, 'Достижение: "А вот раньше на Альтераке..."\nКатегория: Альтеракская долина', 306421)
add(1958, 0, "", 431360)
add(222, 8, "Recruit-a-Friend", 48954)
add(224, 8, "Recruit-a-Friend", 49322)
-- Equal names are not identities: keep a distinct collectible with this name.
add(92007, 8, "Recruit-a-Friend", 999007)
entries[92007].name = entries[224].name
add(1600, 2, '|cFFFFD200Задание: |r"Рыцарь крови"|n|cFFFFD200Зона: |rПризрачные земли|n|n'
    .. '|cFFFFD200Задание: |r"Слава син\'дорай"|n|cFFFFD200Зона: |rПризрачные земли', 370620)
add(1039, 3, "Vendor: Talutu\nZone: Zuldazar\n\nVendor: Tricky Nick\nZone: Tiragarde Sound", 264058)
add(606, 6, "Achievement: Boldly, You Sought the Power of Ragnaros", 170347)
add(1240, 6, "Achievement: Memories of Fel, Frost and Fire", 294197)
add(1944, 3, "|cFFFFD200Черный рынок|r", 428060)
add(2265, 10, "In-Game Shop", 465235)
for _, id in ipairs({ 2807, 2808 }) do
    local offer = atlas.reviewedVendorOffers[id]
    add(id, 7, offer.native[1]:gsub("\n", "|n"), offer.spell)
end

local covenantQuests = {
    { 1299, 312754, 58407 }, { 1302, 312759, 58159 }, { 1303, 312761, 60108 },
    { 1364, 332455, 59555 }, { 1368, 332462, 59020 }, { 1385, 332932, 58440 },
    { 1396, 334391, 58181 }, { 1400, 334406, 61697 },
}
for _, row in ipairs(covenantQuests) do
    local source = atlas.journalSourceDetails[row[1]].replacesSource[1]
    add(row[1], row[1] == 1385 and 2 or 1, source:gsub("\n", "|n"), row[2])
end
local drakeQuests = { [1563] = 66027, [1588] = 74563, [1589] = 68795, [1590] = 70220, [1591] = 66040 }
for id in pairs(drakeQuests) do
    local detail = atlas.questMountRewards[id].journalDetail
    add(id, 5, detail.replacesSource[1], detail.spell)
end

local eggAndCacheMounts = { 538, 539, 540, 1237 }
for _, id in ipairs(eggAndCacheMounts) do
    local detail = atlas.journalSourceDetails[id]
    add(id, 1, detail.replacesSource[1]:gsub("\n", "|n"), detail.spell)
end
local function checkEggAndCachePlaces(eggPlace, cachePlace)
    for _, id in ipairs(eggAndCacheMounts) do
        local mount = assert(atlas.mountByID(id))
        equal(mount.kind, "Добыча", "container keeps its loot source type")
        equal(#atlas.mountLocations(mount, nil, true), 0, "the confirmed zone gives no exact waypoint")
        if id == 1237 then
            local routes = assert(atlas.factionSources(mount))
            equal(#routes, 2, "both faction cache routes are retained")
            equal(routes[1].faction, "Alliance", "Ankoan Supplies belong to the Alliance")
            equal(routes[2].faction, "Horde", "Unshackled Supplies belong to the Horde")
            for _, route in ipairs(routes) do equal(route.place, cachePlace, "both cache routes belong to Nazjatar") end
        else
            equal(mount.place, eggPlace, "the fresh egg drops on the Isle of Giants")
            assert(atlas.decorateSource(mount):find("|Hitem:94295", 1, true), "link to the egg that drops")
        end
    end
end

do
    local readyIDs, timers, notifications = ids, {}, 0
    C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
    atlas.onJournalChanged = function()
        notifications = notifications + 1
        equal(atlas.collection.total, #atlas.mounts, "only the final catalog is published")
    end
    local function flush(delay)
        local job = assert(table.remove(timers, 1), "expected a journal timer")
        equal(job[1], delay, "journal timer delay")
        job[2]()
    end
    local curatedTotal = #atlas.mounts
    ids = {}
    journalEvent("PLAYER_ENTERING_WORLD", false, false)
    equal(#timers, 0, "journal loading stays dormant without a consumer")
    equal(atlas.prepareJournal(), false, "preparation lets the window show before indexing")
    equal(atlas.prepareJournal(), false, "a second request shares the same queue")
    equal(#timers, 1, "only one initial timer is scheduled")
    equal(journalCalls.list, 0, "preparation defers membership enumeration")
    equal(journalCalls.info, 0, "preparation defers record reads")
    equal(atlas.collection, nil, "no collection exists before the first timer")

    local selectedID = readyIDs[1]
    local selected = assert(atlas.resolveJournalMount(selectedID), "a cold card can resolve its exact native ID")
    equal(atlas.resolveJournalMount(selectedID), selected, "reopening the early card reuses its data")
    equal(journalCalls.list, 0, "opening a cold card avoids membership reads")
    equal(journalCalls.info, 1, "opening a cold card reads just one native entry")
    equal(journalCalls.extra, 1, "opening a cold card indexes just one source")
    equal(atlas.collection, nil, "an early card never publishes a partial collection")
    equal(#atlas.mounts, curatedTotal, "an early result stays outside the catalog until publication")

    flush(0)
    equal(atlas.ensureJournal(), false, "synchronous consumers also report a missing membership list")
    equal(atlas.collection, nil, "empty membership does not publish a partial collection")
    equal(journalCalls.info, 1, "empty membership avoids mass record reads")
    for i = 1, 40 do ids[i] = readyIDs[i] end
    journalEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
    journalEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
    equal(#timers, 1, "empty-list retry survives an explicit ensure and coalesces search events")
    flush(.25)
    equal(journalCalls.list, 3, "each list request is explicit or queued once")
    equal(journalCalls.info, 33, "one frame reads at most 32 journal rows")
    equal(atlas.collection, nil, "a suspended scan keeps ownership and counters unpublished")
    equal(#atlas.mounts, curatedTotal, "a suspended scan keeps journal membership unpublished")
    equal(atlas.resolveJournalMount(selectedID), selected, "direct lookup after the background sample preserves identity")
    equal(journalCalls.info, 33, "the sampled card opens without another native call")

    ids = readyIDs
    journalEvent("PLAYER_ENTERING_WORLD", true, false)
    flush(0)
    equal(journalCalls.list, 4, "a pre-login scan is reconciled on world entry")
    equal(journalCalls.info, 65, "the restarted scan still has a frame budget")
    entries[selectedID].collected = true
    journalEvent("NEW_MOUNT_ADDED", selectedID)
    equal(atlas.ensureJournal(), true, "a competing synchronous consumer completes the active scan")
    equal(journalCalls.list, 4, "the synchronous consumer resumes the same membership list")
    equal(atlas.collection.byID[selectedID], true, "acquisition after the first sample is present at publication")
    equal(atlas.collection.collected, 1, "the early acquisition is counted exactly once")
    equal(atlas.resolveJournalMount(selectedID), selected, "published direct lookup retains the same card")
    local matches = 0
    for _, mount in ipairs(atlas.mounts) do
        if mount.id == selectedID then
            equal(mount, selected, "the published catalog uses the original card")
            matches = matches + 1
        end
    end
    equal(matches, 1, "an early card appears once in the final catalog")
    equal(notifications, 1, "a synchronous completion wakes the waiting view once")
    local finalInfoCalls = journalCalls.info
    flush(0)
    equal(journalCalls.info, finalInfoCalls, "the stale scheduled timer does not resume completed work")
    equal(notifications, 1, "the stale timer does not republish")
    equal(atlas.collection.byID[92001], false, "initial catalog reads uncollected ownership")
    C_Timer, atlas.onJournalChanged = nil, nil
end
do
    local catalog, mainEvents, allIDs = {}, journalEvents, ids
    for key, value in pairs(atlas) do catalog[key] = value end
    local lateID, staticID, nativeSpell = allIDs[3], 990010, 990011
    local lateName, lateSpell = entries[lateID].name, entries[lateID].spell
    entries[staticID] = { name = "Native fallback mount", spell = nativeSpell, category = 1, source = "", collected = false }
    catalog.mounts = { { id = staticID, name = "Curated fallback mount", spell = 990012 } }
    catalog.collection = nil
    catalog.usesKillAPI, catalog.rawKills = function() return true end, function() return 0 end
    assert(loadfile("Core/JournalIndex.lua"))("PawAtlas", catalog)
    assert(loadfile("Core/RarityImport.lua"))("PawAtlas", catalog)
    local accountDB, characterDB, rarity = MountAtlasAccountDB, MountAtlasDB, Rarity
    local savedAccount, savedCharacter = {}, {}
    MountAtlasAccountDB, MountAtlasDB = savedAccount, savedCharacter
    Rarity = { db = { profile = { groups = { mounts = {
        { type = "MOUNT", method = "NPC", spellId = lateSpell, attempts = 7 },
        { type = "MOUNT", method = "NPC", spellId = nativeSpell, attempts = 4 },
    } } } } }
    local unreadable, timers, time, notifications = {}, {}, 0, 0
    local oldSecretValue, oldProfileStop, oldServerTime = issecretvalue, debugprofilestop, GetServerTime
    issecretvalue = function(value) return value == unreadable end
    debugprofilestop = function() time = time + 2; return time end
    GetServerTime = function() return 1 end
    C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
    catalog.onJournalChanged = function() notifications = notifications + 1 end
    local function flush(delay)
        local job = assert(table.remove(timers, 1), "expected a journal timer")
        equal(job[1], delay, "journal backoff or continuation")
        local before = journalCalls.info
        job[2]()
        assert(journalCalls.info - before <= 2, "the time budget can yield before the row limit")
    end

    ids = { allIDs[1], allIDs[2], unreadable }
    equal(catalog.prepareJournal(), false, "the second view starts with a cold journal")
    flush(0)
    flush(0)
    flush(0)
    equal(catalog.collection, nil, "one unreadable membership ID prevents publication")
    equal(catalog.importRarity().status, "unavailable", "import cannot use a partial journal")
    assert(catalog.startRarityImport(), "the async import can report unavailable")
    equal(catalog.rarityImportProgress().result.status, "unavailable", "async import cannot use a partial journal")
    assert(MountAtlasAccountDB == savedAccount and MountAtlasDB == savedCharacter
        and not next(savedAccount) and not next(savedCharacter), "an unavailable journal leaves saved data intact")
    equal(#timers, 1, "unavailable import leaves the existing journal retry queued")
    flush(.25)
    flush(0)
    flush(0)
    equal(catalog.collection, nil, "the first fallback can run before the client is ready")
    ids[3] = lateID
    entries[lateID].name, entries[lateID].spell = nil, nil
    flush(.75)
    flush(0)
    flush(0)
    equal(catalog.collection.total, 3, "the backoff can finish membership without a native event")
    equal(notifications, 1, "asynchronous completion publishes one full catalog")
    equal(catalog.importRarity().status, "unavailable", "an unresolved listed identity can still match Rarity history later")
    assert(not next(savedAccount) and not next(savedCharacter), "unresolved identity leaves saved data intact")
    entries[lateID].name, entries[lateID].spell = lateName, lateSpell
    local beforeImport = journalCalls.info
    local result = catalog.importRarity()
    equal(result.status, "imported", "import can retry after the missing mount identity arrives")
    equal(result.updated, 2, "the late and curated mounts are both imported")
    equal(savedAccount.rarityImport.entries[lateID].total, 7, "cached live spell matches the late mount's history")
    equal(savedAccount.rarityImport.entries[staticID].total, 4, "native lookup overrides the unconfirmed static spell")
    equal(journalCalls.info - beforeImport, 2, "import only samples the pending identity and the unconfirmed static spell")
    equal(catalog.collection.total, 4, "the confirmed identity increases the catalog size")
    equal(catalog.prepareJournal(), true, "the loaded catalog is ready for reopening")
    equal(#timers, 0, "readiness stops background retries")

    journalEvents, ids = mainEvents, allIDs
    entries[staticID] = nil
    MountAtlasAccountDB, MountAtlasDB, Rarity = accountDB, characterDB, rarity
    issecretvalue, debugprofilestop, GetServerTime = oldSecretValue, oldProfileStop, oldServerTime
    C_Timer = nil
end
do
    local mount = atlas.mountByID(1395)
    equal(mount.boss, "Покаяние Чистоты", "the journal's drop category resolves to the named Kyrian chest")
    equal(atlas.extraCovenantPurchase(mount).npc, 174937, "the chest also has a separate Galos offer")
end
checkEggAndCachePlaces("Остров Великанов", "Назжатар")
for id, questID in pairs(drakeQuests) do
    local mount = assert(atlas.mountByID(id))
    equal(mount.kind, "Квест", "the mount reward comes from its confirmed quest")
    local decorated = atlas.decorateSource(mount)
    assert(decorated:find("|Hquest:" .. questID .. ":", 1, true), "the verified quest has a clickable link")
    assert(not decorated:find("|Hachievement:", 1, true), "the related learning achievement does not become an acquisition route")
    equal(assert(atlas.directQuestReward(mount, {})).quests[1].id, questID, "the direct quest identifies the teaching reward")
end
local riverbeast = assert(atlas.mountByID(631))
local function checkRiverbeastMission(condition)
    local guarantee = assert(atlas.sourceGuaranteedReward(riverbeast, {}), "the naval mission guarantees its reward on success")
    equal(guarantee.method, "quest", "the naval mission belongs to the quest category")
    assert(atlas.decorateSource(riverbeast):find(condition, 1, true), "the mission success condition appears on the card")
    assert(guarantee.condition:find(condition, 1, true), "the mission success condition appears in the guarantee tooltip")
    equal(atlas.sourceGuaranteedReward(riverbeast, { separateSource = true }), nil, "other routes do not inherit the mission reward")
end
checkRiverbeastMission("Успешно заверши задание на верфи")
do
    for _, case in ipairs({ { 250, 43954, 4, 25, 3 }, { 253, 43986, 3, 10, 4 } }) do
        local id, item, mode, size, wrongMode = unpack(case)
        local mount = assert(atlas.mountByID(id))
        local view = mount.sourceGroups and mount.sourceGroups[1] or mount
        local choice = { view = view, category = "loot" }
        local raid = assert(atlas.raidLootGuaranteeForSource(mount, choice))
        assert(raid.scope == "raid" and raid.quantity == 1 and raid.groupRate == 1)
        equal(raid.item, item, "Sartharion loot item is mode-specific")
        equal(raid.difficultyID, mode, "Sartharion uses the actual legacy raid size difficulty")
        assert(raid.condition:find("на " .. size .. " игроков", 1, true) and raid.condition:find("всех трёх", 1, true))
        assert(raid.englishCondition:find(size .. "-player", 1, true) and raid.englishCondition:find("all three", 1, true))
        assert(not atlas.attemptStages[id] and not atlas.guaranteedRewards[id], "the raid drop is not a personal probability")
        equal(atlas.raidLootReward({ id = id, spell = 1 }), nil, "no loot is inherited by a different spell")
        equal(atlas.raidLootGuaranteeForSource(mount, { blackMarket = {}, view = view }), nil, "other routes do not share raid loot")
        local difficulties, boss = view.difficulties, view.boss
        view.difficulties = { [wrongMode] = true }
        equal(atlas.raidLootGuaranteeForSource(mount, choice), nil, "the opposite raid size does not guarantee this item")
        view.difficulties, view.boss = difficulties, "Another boss"
        equal(atlas.raidLootGuaranteeForSource(mount, choice), nil, "a changed live source cannot inherit the guarantee")
        view.boss = boss
    end
end
for id, items in pairs({ [2779] = { 269836, 242639 }, [2961] = { 271999 } }) do
    local mount = atlas.mountByID(id)
    equal(mount.boss, mount.kind, "ritual instructions stay out of the target row " .. id)
    assert(not mount.hasSourcePanels, "ritual instructions stay in the full source " .. id)
    for _, item in ipairs(items) do
        assert(atlas.decorateSource(mount):find("|Hitem:" .. item .. "|h", 1, true),
            "ritual item stays linked " .. item)
    end
end
for _, id in ipairs({ 92012, 92013 }) do
    local mount = atlas.mountByID(id)
    equal(mount.boss, mount.kind, "free text and item references cannot become target names " .. id)
    equal(mount.place, "Open world", "structured location remains available")
    assert(not mount.hasSourcePanels, "full source stays available")
end
equal(atlas.mountByID(1434).boss, "Hirukon", "a structured loot target is still a source target")
local blackMarketCount = 0
local primaryAuction = { [110] = true, [111] = true, [266] = true, [606] = true, [1039] = true, [1240] = true }
for id, listing in pairs(atlas.blackMarketMounts) do
    blackMarketCount = blackMarketCount + 1
    local mount = (primaryAuction[id] or id == 1944) and atlas.mountByID(id)
        or { id = id, spell = listing.spell, kind = "Добыча" }
    if primaryAuction[id] then mount.availability = atlas.legacySources[id] end
    local choice = atlas.extraBlackMarketSource(mount)
    if primaryAuction[id] or id == 1944 then
        equal(choice, nil, "native or reviewed direct auction listing cannot duplicate itself")
        equal(atlas.classifyMountSource(mount).subtype, "Чёрный рынок", "auction route takes precedence over outdated acquisition")
    else
        assert(choice and choice.blackMarket.item == listing.item and choice.contextOnly
            and choice.view.trackingCompatible == false and not choice.vendor, "auction is a distinct purchase route " .. id)
        equal(atlas.classifyMountSource(mount, choice).key, "purchase", "auction appears in the purchase filter")
        equal(atlas.extraBlackMarketSource({ id = id, spell = listing.spell + 1 }), nil, "wrong spell cannot inherit an auction")
    end
end
equal(blackMarketCount, 66, "all reviewed auction identities")
equal(atlas.vendorSources(atlas.mountByID(1039)), nil, "retired brutosaur vendors never become active")
equal(atlas.legacySources[1039].routes[2].container, 169430, "explicit brutosaur container match")
equal(#atlas.legacySources[606].routes, 1, "no extrapolated Core Hound container")
equal(#atlas.legacySources[1240].routes, 1, "no extrapolated Worldbreaker container")
equal(atlas.mountByID(2265).journalSourceRaw, "In-Game Shop", "shop brutosaur remains distinct")
equal(atlas.extraBlackMarketSource(atlas.mountByID(2265)), nil, "shop brutosaur has no auction listing")
for _, locale in ipairs({ "ruRU", "enUS" }) do
    language = locale
    do
        local raw = locale == "ruRU" and 'Достижение: "Укротитель бурных потоков времени V"\nКатегория: путешествия во времени'
            or "Achievement: Master of the Turbulent Timeways V\nCategory: Timewalking"
        local mount = { id = 2806, spell = 1264184, journalSourceRaw = raw }
        mount.journalSourceOverride, mount.reviewedVendorOffer = atlas.reviewedVendorSource(mount)
        local vendors = atlas.vendorSources(mount)
        equal(#vendors, 6, "Spawn of Vyranoth has six documented Timewalking vendors")
        for _, vendor in ipairs(vendors) do
            assert(vendor.conditions:find("5000 |Hcurrency:1166", 1, true), "each vendor takes Timewarped Badges")
            assert(not vendor.conditions:find("61463", 1, true), "former achievement is not a purchase requirement")
            if vendor.npc == 101759 then equal(#vendor.waypoints, 2, "Kiatke serves both capitals") end
        end
        assert(atlas.ui.sourceHistory(mount):find(atlas.dataName(mount.reviewedVendorOffer.formerAchievement), 1, true))
        equal(atlas.rewardItem(mount, nil, true).item, 258884, "the purchasable item teaches the correct mount")
    end
    for _, id in ipairs({ 2807, 2808 }) do
        local expected = atlas.reviewedVendorOffers[id]
        local raw = expected.native[locale == "enUS" and 2 or 1]
        local source, review = atlas.reviewedVendorSource({ id = id, spell = expected.spell, journalSourceRaw = raw })
        local offers = atlas.vendorSources({ id = id, spell = expected.spell, journalSourceOverride = source, reviewedVendorOffer = review })
        equal(#offers, 2, "both faction quartermasters remain selectable")
        equal(offers[1].npc, 68363, "Alliance quartermaster order and identity")
        equal(offers[1].faction, "Alliance", "Alliance quartermaster faction")
        equal(offers[1].map, 500, "Bizmo's Brawlpub is the lower map floor")
        equal(offers[2].npc, 68364, "Horde quartermaster order and identity")
        equal(offers[2].faction, "Horde", "Horde quartermaster faction")
        equal(offers[2].map, 503, "Brawl'gar arena map")
        for _, offer in ipairs(offers) do
            assert(offer.conditions:find(expected.gold .. "|T", 1, true), "exact gold cost reaches both factions")
            assert(offer.conditions:find(id == 2807 and "6" or "8", 1, true), "rank reaches both factions")
        end
        assert(not atlas.reviewedVendorSource({ id = id, spell = expected.spell, journalSourceRaw = "Vendor: Later route" }),
            "unrelated journal vendor must not be overwritten")
    end
end
language = "ruRU"
for _, row in ipairs(covenantQuests) do
    local id, _, quest = unpack(row)
    local mount = atlas.mountByID(id)
    equal(mount.kind, "Квест", "covenant campaign reward is indexed as quest " .. id)
    assert(mount.place and #atlas.mountCovenantRequirements(mount) == 1, "zone and covenant remain in source data")
    local link = "|Hquest:" .. quest .. ":0|h["
    assert(atlas.decorateSource(mount):find(link, 1, true), "cold Russian campaign quest has a native link")
    local detail = atlas.journalSourceDetails[id]
    local source = detail.englishSource
    language = "enUS"
    assert(atlas.decorateSource({ id = id, spell = row[2], journalSourceOverride = source }):find(link, 1, true),
        "English source override can resolve the exact quest")
    language = "ruRU"
end
equal(atlas.mountByID(1324).kind, "Исследование", "Elusive Quickhoof API exploration index")
for _, entry in ipairs({ { 1324, 174860, 10 }, { 802, 138258, 120 }, { 1414, 182614, 1 } }) do
    local mount = atlas.mountByID(entry[1])
    local details = assert(mount.sourceRequirements)
    equal(details.reward.item, entry[2], "interaction reward identity")
    assert(details.guarantee.condition ~= "" and details.guarantee.englishCondition ~= "", "verified guarantee needs explicit conditions")
    equal(#atlas.navigationPoints[entry[1]], entry[3], "navigation points are retained")
    assert(not mount.hasQuest, "interaction requirements do not enter the quest filter")
end
equal(atlas.mountByID(1414).kind, "Взаимодействие", "Blanchy is an interaction")
equal(atlas.navigationPoints[802][120].map, 632, "crystals in a subzone keep their own map")
local kuri = atlas.mountLocations({ id = 2749 }, nil, true)
assert(#kuri == 2 and kuri[1].map == 2413 and kuri[1].npc == 242358 and kuri[1].x == .678 and kuri[1].y == .275
    and kuri[1].quest == 90467 and kuri[1].item == nil and kuri[2].item == 255826 and kuri[2].x == .6615 and kuri[2].y == .2547,
    "Kuri's quest giver and offering stay separate waypoints for their own stages")
local alsoAtKuri = { map = 2413, npc = 242358, x = .678, y = .275, item = 255826 }
local kuriPager = atlas.ui.sourceWaypointPoints({ kuri[1], kuri[1], kuri[2], alsoAtKuri, { map = 2413 } })
assert(#kuriPager == 3 and kuriPager[1] == kuri[1] and kuriPager[2] == kuri[2] and kuriPager[3] == alsoAtKuri,
    "one coordinator groups the stages, removes identical entries, and retains separate actions at a shared point")
assert(not atlas.mountByID(92011).sourceRequirements, "exploration by itself does not imply a guarantee")
local classify = atlas.classifyMountSource
for _, id in ipairs({ 312, 982, 1166 }) do
    equal(classify(atlas.mountByID(id)).key, "fishing", "actual teaching item is fished")
end
equal(classify(atlas.mountByID(16)).key, "fishing", "the guaranteed outcome of a fished egg belongs to fishing")
equal(classify(atlas.mountByID(1434)).key, "loot", "fishing a reagent is not direct fishing")
equal(classify({ id = 1, kind = "Профессия" }).key, "profession", "native profession source")
equal(classify(atlas.mountByID(1324)).key, "loot", "exploration presentation remains loot")
equal(classify(atlas.mountByID(1735)).key, "event", "direct public event reward")
local alterac = classify(atlas.mountByID(1285))
equal(alterac.key, "quest", "current Russian journal title resolves to the actual Alterac quest")
equal(alterac.eventID, 1808, "anniversary quest keeps its seasonal condition")
equal(classify(atlas.mountByID(2821)).key, "pvp", "reviewed rated arena reward")
for _, id in ipairs({ 2805, 2817 }) do
    local mount = assert(atlas.mountByID(id))
    local route = classify(mount)
    equal(route.state, "historical", "Season 1 dungeon drop is outside the Season 2 pool")
    equal(route.seasonal, true, "the dungeon drop is temporarily unavailable")
    equal(route.historyKey, "loot", "historical dungeon source remains loot")
    assert(mount.availability.englishConditions:find("Challenger’s Cache", 1, true), "history keeps the second drop source")
end
local oldAlliance = atlas.mountByID(1351)
local oldHorde = atlas.mountByID(2571)
equal(oldAlliance.kind, "Торговец", "old rated season has the verified current saddle purchase")
assert(oldAlliance.journalSourceRaw:find("Shadowlands", 1, true), "native seasonal source retained")
local allianceVendor = atlas.vendorSources(oldAlliance)[1]
local hordeVendor = atlas.vendorSources(oldHorde)[1]
equal(allianceVendor.npc, 73190, "Alliance saddle merchant")
equal(hordeVendor.npc, 73151, "Horde saddle merchant")
equal(allianceVendor.x, .768, "Alliance waypoint is normalized")
equal(hordeVendor.y, .730, "Horde waypoint is normalized")
assert(allianceVendor.conditions:find("{item:103533:Седло ярости}", 1, true), "purchase uses a localized item link")
equal(classify(oldAlliance, { vendor = allianceVendor }).key, "purchase", "old PvP season vendor classification")
equal(atlas.reviewSaddlePurchase(1351, 327407, "PvP", "PvP: Shadowlands: Season 2"), nil, "unexpected native season is preserved")
equal(atlas.reviewSaddlePurchase(1351, 327408, "PvP", "PvP: Shadowlands: Season 1"), nil, "wrong teaching spell never inherits an offer")
local veteran = atlas.mountByID(422)
equal(classify(veteran).key, "achievement", "current Veteran II achievement preserved")
local veteranVendor = atlas.extraSaddlePurchase(veteran)
equal(classify(veteran, { vendor = veteranVendor }).key, "purchase", "Veteran mount retains independent purchase")
local blackMalice = atlas.mountByID(3133)
equal(classify(blackMalice).key, "promotion", "Black Malice keeps the promotion category")
equal(classify(blackMalice).state, "unknown", "promotion is subject to a valid code and store stock")
assert(blackMalice.journalSourceOverride:find("17 ноября 2026 года", 1, true), "ended preorder shown with the valid code condition")
local felcycle = atlas.mountByID(1943)
local puzzleRoute = classify(felcycle)
equal(puzzleRoute.key, "loot", "Felcycle comes from a puzzle reward chest")
equal(puzzleRoute.eventID, nil, "Felcycle is available outside its debut event")
assert(felcycle.journalSourceOverride:find("{item:229348:", 1, true), "Felcycle override has the exact mount reward link")
assert(felcycle.journalSourceRaw:find("?", 1, true), "Felcycle preserves the original journal source")
assert(atlas.mountByID(1794).journalSource:find("Whodunnit?", 1, true), "punctuation in a verified achievement is preserved")
for _, id in ipairs({ 17, 84, 367, 368 }) do
    equal(classify(atlas.mountByID(id)).key, "progress", "reviewed class level grant " .. id)
end
assert(atlas.decorateSource(atlas.mountByID(367)):find("повышении уровня", 1, true),
    "updated class acquisition is shown for the reviewed legacy journal entry")
equal(classify(atlas.mountByID(780)).key, "quest", "Felsaber is acquired during the starting quest")
local deathKnight = atlas.mountByID(221)
equal(classify(deathKnight).key, "quest", "starting death knight quest replaces misleading trainer heading")
equal(classify(deathKnight, atlas.extraDirectGrantSource(deathKnight)).key, "progress",
    "automatic deathcharger grant remains a separate route")
local scarab = classify(atlas.mountByID(937))
equal(scarab.key, "progress", "Scarab Lord grant has a known method")
equal(scarab.state, "unknown", "Scarab Lord grant is conditional on historic title eligibility")
language = "enUS"
assert(atlas.vendorSources(oldHorde)[1].conditions:find("{item:103533:Vicious Saddle}", 1, true), "English saddle purchase link")
language = "ruRU"
equal(classify(atlas.mountByID(1484)).key, "progress", "reviewed covenant Renown grant")
local tauralus = atlas.mountByID(1369)
equal(classify(tauralus).key, "purchase", "native Renown vendor retains the purchase")
equal(classify(tauralus, assert(atlas.extraDirectGrantSource(tauralus))).key, "progress", "free Renown grant is a separate route")
do
    local originalDifficulty, originalLocks, originalTooltip = GetDifficultyInfo, atlas.bossDifficultyLockouts, GameTooltip
    local modes = { [3] = { "10 Player", 10 }, [4] = { "25 Player", 25 },
        [5] = { "10 Player (Heroic)", 10, true }, [6] = { "25 Player (Heroic)", 25, true },
        [7] = { "Looking For Raid", 25 }, [14] = { "Normal", 30 }, [15] = { "Heroic", 30, true },
        [17] = { "Raid Finder", 25 }, [233] = { "Mythic – Flexible Raid", 25, true, true } }
    function GetDifficultyInfo(id)
        local mode = assert(modes[id], "unexpected difficulty " .. id)
        return mode[1], "raid", mode[3], false, mode[3], mode[4], nil, id == 7 or id == 17,
            id == 233 and 15 or mode[2], mode[2]
    end
    local sporeglider = assert(atlas.mountByID(2950))
    local view = assert(sporeglider.sourceGroups[1])
    equal(view.sourceKind, "Босс", "the reagent drops from a boss")
    equal(classify(sporeglider, { view = view }).subtype, "Сбор предметов", "the mount needs a guaranteed collection")
    local reward = atlas.guaranteedRewards[sporeglider.id]
    equal(reward.item, 269240, "collection produces the mount item")
    equal(reward.reagent.required, 4, "four snacks guarantee the result")
    local sporefall = atlas.sourceDifficulty(view, true)
    equal(#sporefall, 4, "Sporefall has four eligible difficulties")
    for index, id in ipairs({ 17, 14, 15, 233 }) do
        equal(sporefall[index].name, modes[id][1], "Sporefall display order")
    end
    equal(sporefall[4].sizes[1], "15–25", "Sporefall uses flexible Mythic")
    local legacy = atlas.sourceDifficulty({ isRaid = true, difficulties = { [6] = true, [5] = true,
        [4] = true, [3] = true, [7] = true } }, true)
    for index, id in ipairs({ 7, 3, 4, 5, 6 }) do
        equal(legacy[index].name, modes[id][1], "legacy display order and group size")
    end
    local lines = {}
    GameTooltip = { AddDoubleLine = function(_, value) lines[#lines + 1] = value end }
    atlas.bossDifficultyLockouts = function()
        return { { difficultyID = 6, difficultyIDs = { 6, 5 } }, { difficultyID = 4 }, { difficultyID = 7 }, { difficultyID = 3 } }
    end
    atlas.appendBossDifficultyTooltip({})
    equal(table.concat(lines, ","), "  Looking For Raid,  10 Player,  25 Player,  10 Player (Heroic)/25 Player (Heroic)",
        "lockout tooltip matches the mode order and sorts legacy aliases by size")
    GetDifficultyInfo, atlas.bossDifficultyLockouts, GameTooltip = originalDifficulty, originalLocks, originalTooltip
end
for _, locale in ipairs({ "ruRU", "enUS" }) do
    language = locale
    local en = locale == "enUS"
    local rank = en and "Renown: " or "Известность: "
    for _, id in ipairs({ 1354, 1357, 1365, 1369, 1384, 1388, 1398, 1399, 1485, 1489, 1494, 1496 }) do
        local offer = atlas.reviewedVendorOffers[id]
        local source = ("Covenant: %s\nZone: %s"):format(
            ({ "Kyrian", "Venthyr", "Night Fae", "Necrolord" })[offer.covenant], offer.englishZone)
        local mount = { id = id, spell = offer.spell, journalSourceRaw = source }
        mount.journalSourceOverride, mount.reviewedVendorOffer = atlas.reviewedVendorSource(mount)
        local vendor = assert(atlas.vendorSources(mount))[1]
        equal(vendor.npc, offer.npc, "covenant Renown vendor identity " .. id)
        assert(vendor.conditions:find(rank .. offer.renown, 1, true))
        assert(vendor.conditions:find(offer.amount .. " |Hcurrency:1813|h", 1, true))
        if offer.renown == 39 then
            assert(vendor.conditions:find(offer.offerings .. " |Hcurrency:1885|h", 1, true),
                "the purchased replacement also costs Grateful Offerings")
            mount.directSourceGrant = atlas.directMountGrants[id]
            local grant = assert(atlas.extraDirectGrantSource(mount))
            assert(grant.view.journalSourceRaw:find(rank .. "39", 1, true))
            assert(not grant.view.journalSourceRaw:find("1813", 1, true), "a free grant has no price")
        end
        mount.journalSourceRaw = "Vendor: Another seller\n" .. source
        equal(atlas.reviewedVendorSource(mount), nil, "unrelated merchant keeps the native source")
    end
    for _, id in ipairs({ 1310, 1393 }) do
        local offer = atlas.covenantPurchaseAlternatives[id]
        local mount = { id = id, spell = offer.spell, kind = "Добыча" }
        local vendor = assert(atlas.extraCovenantPurchase(mount))
        assert(vendor.conditions:find(rank .. offer.renown, 1, true))
        equal(classify(mount).key, "loot", "the Renown offer does not replace the rare drop")
        equal(classify(mount, { vendor = vendor }).key, "purchase", "the extra vendor is a paid route")
    end
    local dreamstag = { id = 1808, spell = 423871, journalSourceRaw = "Vendor: Talisa Whisperbloom\nCost: 1\n\nVendor: Other merchant\nCost: 2" }
    local vendors = atlas.vendorSources(dreamstag)
    assert(vendors[1].conditions:find(rank .. "18", 1, true))
    equal(vendors[2].conditions, "Cost: 2", "unrelated route never inherits a Renown requirement")
    local lizi = { id = 1639, spell = 374247, journalSourceRaw = "Quest: To Tame a Thunderspine\nZone: Ohn'ahran Plains" }
    assert(atlas.decorateSource(lizi):find(rank .. "9", 1, true), "known quest displays the Renown unlock")
    lizi.journalSourceRaw = "Quest: Some other quest"
    assert(not atlas.decorateSource(lizi):find(rank, 1, true), "unrelated quest does not inherit the unlock")
end
language = "ruRU"
local tiger = atlas.mountByID(196)
local landro = assert(atlas.vendorSources(tiger))[1]
equal(landro.redemption, "tcg", "Landro code redemption is typed")
equal(classify(tiger, { vendor = landro }).key, "promotion", "redemption is not purchase")
equal(classify(tiger, { vendor = { name = "Landro Longshot", price = 10 } }).key, "purchase", "actual sale is not redemption")
local gorger = { id = 1391, kind = "Квест", locations = { {} }, npcs = { 160821 } }
local chain, grant = atlas.questAcquisitionChain({ id = 1391, spell = 333027 })
assert(chain and chain.starter == 180583 and chain.firstQuest == 61839 and chain.finalQuest == 62046,
    "the native Gorger spell binds to one verified acquisition chain")
equal(atlas.questAcquisitionChain({ id = 1391, spell = 332256 }), nil, "wrong teaching spell cannot bind the chain")
equal(atlas.ui.withoutChainQuest("Задание: |cffffff00[Новая стая]|r\nТребуется: ключ", chain),
    "Требуется: ключ", "the cold final quest headline is removed without hiding unrelated conditions")
local chainLink = "|cffffff00|Hquest:62046:0|h[Новая стая]|h|r"
do
    local reward = assert(atlas.questMountRewards[866])
    local final = atlas.sourceQuestReference(46813, "Затерянный ледник")
    local start = atlas.sourceQuestReference(46719, "Послание Амал'тазада")
    local condition = "Требуется: " .. final
    local body = "Задание: " .. final .. "\nЗадание: [Послание Амал'тазада]\n" .. condition
    equal(atlas.ui.withQuestRewards(body, reward), "Начало цепочки: " .. start .. "\n" .. condition,
        "a direct questline has one linked start and keeps independent conditions")
end
equal(atlas.ui.withoutChainQuest("Задание: " .. chainLink .. "\nЗадание: " .. chainLink .. " после сдачи ключа", chain),
    "Задание: " .. chainLink .. " после сдачи ключа", "a real quest link is removed only if it is the entire duplicate value")
local chainText = atlas.ui.questChainTooltip(chain, grant)
assert(chainText:find("Новая стая", 1, true) and chainText:find("Верный пожиратель", 1, true)
    and not chainText:find("|H", 1, true), "quest and reward names are present without noninteractive hyperlink markup")
local aquilon = atlas.questAcquisitionChain({ id = 1493, spell = 353877 })
assert(aquilon and aquilon.firstQuest == 64529 and aquilon.starter == 187282, "a different verified rare starter has the same chain model")
local gravewing = atlas.questAcquisitionChain({ id = 803, spell = 215545 })
assert(gravewing and gravewing.firstQuest == 64530 and gravewing.starter == 187283, "the Venthyr chain preserves its exact quest and starter")
local wilderling = atlas.questAcquisitionChain({ id = 1487, spell = 353859 })
do
    local lizi = { id = 1639, spell = 374247, kind = "Квест" }
    local choice = { category = "quest" }
    choice.questChain, choice.chainGrant = atlas.questChainForSource(lizi, choice)
    local liziChain = assert(atlas.questChainGuaranteedReward(choice))
    equal(liziChain.finalQuest, 71209, "only Beast of the Plains rewards Lizi")
    equal(liziChain.reward, 192799, "the Lizi chain uses the actual mount item")
    equal(atlas.questChainForSource(lizi, { category = "vendor", vendor = {} }), nil,
        "the quest chain does not attach to a purchase")
    equal(atlas.directQuestReward(lizi, choice), nil, "the standalone reward row does not duplicate the chain")
    equal(atlas.questChainTitle(liziChain, 71197), "Приручение громоспина", "numbered links retain a full tooltip title")
    equal(atlas.questChainTitle(liziChain, 66676), "Скрытное проникновение", "the prerequisite links the actual quest")
    local previousLog, previousLink = C_QuestLog, GetQuestLink
    C_QuestLog, GetQuestLink = nil, nil
    local summary = atlas.ui.questChainSummary(liziChain)
    assert(summary:find("|Hquest:71209:0|h[Дитя равнин]|h", 1, true) and not summary:find(" / ", 1, true))
    for _, id in ipairs({ 66676, 71196, 71197, 71198, 71199, 71195 }) do
        assert(not summary:find("|Hquest:" .. id .. ":", 1, true), "the compact card keeps only the real reward link")
    end
    local points = assert(atlas.questRewardWaypoints(lizi, choice))
    equal(#points, 2, "the route shows the verified start and finish points when progress is unknown")
    equal(points[1].quest, 71196, "the first default pin sends a fresh character to the start")
    equal(points[1].x, .561, "the first day points to the spring")
    equal(atlas.questRewardTarget(atlas.questNavigationReward(lizi, choice), points[1]).boss,
        "Посвященная Радия", "coordinates and target share the exact NPC")
    C_QuestLog = { IsOnQuest = function(id) return id == 71195 end,
        IsQuestFlaggedCompleted = function(id) return id ~= 71195 and id ~= 71209 end }
    equal(atlas.questRewardWaypoints(lizi, choice)[1].quest, 71195,
        "the fifth accepted quest keeps its own ID at the final questgiver's location")
    local complete, total = atlas.questChainProgress(liziChain)
    equal(complete, 4, "the side storyline is a prerequisite, separate from the visible reward chain count")
    equal(total, 5, "the five training days count and the finisher is separate")
    C_QuestLog = { IsOnQuest = function(id) return id == 71198 end,
        IsQuestFlaggedCompleted = function(id) return id == 71196 or id == 71197 end }
    local thirdStage = assert(atlas.questRewardWaypoints(lizi, choice))[1]
    equal(thirdStage.quest, 71198, "the active third day does not keep a pin from the first day")
    equal(thirdStage.x, .5709, "the third day points to the cauldron area")
    equal(atlas.questGiverWaypoints[71197][1].x, .562, "the second day's observation is scoped to its own stage")
    equal(atlas.questGiverWaypoints[71199][1].y, .776, "the fourth day points to where Radiya takes the pelts")
    equal(atlas.questChainProgress(liziChain), 2, "the progress bar counts completed taming days")
    local tooltip = atlas.ui.questChainTooltip(liziChain, choice.chainGrant, 71209)
    assert(tooltip:find("|cffffd200Приручение громоспина|r", 1, true))
    tooltip = tooltip:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    assert(tooltip:find("3. Приручение громоспина · В процессе", 1, true)
        and tooltip:find("1. Приручение громоспина · Выполнено", 1, true)
        and tooltip:find("4. Приручение громоспина · Не выполнено", 1, true)
        and tooltip:find("Выходной посвященной", 1, true))
    C_QuestLog = { IsQuestFlaggedCompleted = function(id) return id == 71209 end }
    equal(atlas.questChainProgress(liziChain), 5, "the reward quest completes the progress bar")
    equal(atlas.questRewardWaypoints(lizi, choice)[1].quest, 71209, "a finished chain shows the reward location")
    C_QuestLog, GetQuestLink = previousLog, previousLink
end
do
    local oldLog, oldItem, oldFaction, oldObjective = C_QuestLog, C_Item, UnitFactionGroup, GetQuestObjectiveInfo
    local completed, active, faction, items = {}, nil, "Alliance", 4
    UnitFactionGroup = function() return faction end
    C_QuestLog = { IsQuestFlaggedCompleted = function(id) return completed[id] == true end,
        IsOnQuest = function(id) return id == active end }
    C_Item = { GetItemCount = function(id, bank, uses, reagents, warband)
        assert(id == 68644 and bank and not uses and not reagents and not warband,
            "training items belong to this character and its personal bank")
        return items
    end }

    local function progress(id, count, total, choice)
        local row = atlas.periodicQuestChains[id]
        local mount = { id = id, spell = row.spell, kind = "Квест" }
        choice = choice or { category = "quest" }
        if row.chain then choice.questChain, choice.chainGrant = atlas.questChainForSource(mount, choice) end
        local n, max, reset = atlas.periodicQuestProgress(mount, choice)
        equal(n, count, "done stages for mount " .. id)
        equal(max, total, "total stages for mount " .. id)
        equal(reset, total and "daily" or nil, "verified cadence for mount " .. id)
    end

    progress(55)
    active = 29034
    progress(55, 4, 20)
    items = 30
    progress(55, 20, 20)
    active, completed = nil, { [29034] = true }
    progress(55, 20, 20) -- The turn-in consumed all the quest items.
    faction = "Horde"
    progress(55)

    completed = { [44990] = true, [44991] = true, [44993] = true }
    progress(793, 2, 15) -- Faction visits are alternatives at a single step.
    progress(793, nil, nil, { vendor = {} })
    completed = { [37048] = true, [37049] = true, [36990] = true }
    progress(609, 2, 12)
    faction = "Alliance"
    progress(609, 1, 12)

    completed = { [71196] = true, [71197] = true, [66676] = true }
    progress(1639, 2, 5)
    completed = { [71209] = true }
    progress(1639, 5, 5)
    progress(1329)
    GetQuestObjectiveInfo = function(id, index, displayComplete)
        assert(id == 58881 and index == 0 and displayComplete == false, "the persistent feeding objective is queried")
        return nil, nil, nil, 3, 7
    end
    completed = { [58879] = true }
    progress(1329, 3, 7) -- Today's daily flag is independent of the cumulative count.
    completed = { [58887] = true }
    progress(1329, 7, 7)
    C_QuestLog, C_Item, UnitFactionGroup, GetQuestObjectiveInfo = oldLog, oldItem, oldFaction, oldObjective
end

local sourceGorger = { id = 1391, spell = 333027, kind = "Рарка" }
local gorgerChoice = { category = "loot" }
gorgerChoice.questChain, gorgerChoice.chainGrant = atlas.questChainForSource(sourceGorger, gorgerChoice)
equal(atlas.questChainGuaranteedReward(gorgerChoice).finalQuest, 62046,
    "the guaranteed rare-to-quest reward belongs to the final quest, not the starter drop")
equal(atlas.questChainForSource(sourceGorger, { category = "quest", contextOnly = true }), nil,
    "a context-only route does not inherit the completed chain reward")
equal(atlas.questChainForSource(sourceGorger, { category = "loot", view = {}, verifiedDrop = true }), nil,
    "a separate drop does not inherit the completed chain reward")
local cobalt = { id = 188, spell = 41515, kind = "Квест" }
local questChoice = { classification = { key = "quest", state = "current" } }
local jorus = assert(atlas.directQuestReward(cobalt, questChoice)).quests[1]
assert(jorus.id == 11109 and jorus.item == 32859 and not jorus.mode,
    "Jorus directly rewards one mount item from its own chosen quest")
equal(atlas.directQuestReward({ id = 188, spell = 999 }, questChoice), nil, "another spell does not inherit that quest reward")
equal(atlas.directQuestReward({ id = 2561, spell = 123 }, questChoice), nil, "an unverified quest cache is not a fixed reward")
local vorquin = { id = 1683, spell = 394216, kind = "Торговец" }
local vonChoice = assert(atlas.extraQuestRewardSource(vorquin))
vonChoice.classification = atlas.classifyMountSource(vorquin, vonChoice)
local cavalry = assert(atlas.directQuestReward(vorquin, vonChoice)).quests[1]
assert(cavalry.id == 72263 and cavalry.item == 201702 and cavalry.mode == "choice",
    "the alternate Vorquin route guarantees only the item chosen at quest turn-in")
equal(atlas.directQuestReward(vorquin, { vendor = {}, classification = { key = "purchase" } }), nil,
    "the vendor does not inherit the independent choice-reward guarantee")
equal(atlas.directQuestReward({ id = 2606, spell = 1242272, unavailable = true }, questChoice), nil,
    "a retired quest reward never appears active")
assert(wilderling and wilderling.firstQuest == 64528 and wilderling.starter == 187281, "the Night Fae chain validates its existing toast trigger")
local toast = atlas.attemptStages[1487].item.toastItems
atlas.attemptStages[1487].item.toastItems = { 187279 }
equal(atlas.questAcquisitionChain({ id = 1487, spell = 353859 }), nil, "a different event trigger cannot bind the chain")
atlas.attemptStages[1487].item.toastItems = toast
equal(classify(gorger, { category = "loot" }).subtype, "Рарка", "same mount's predecessor is a rare")
local quest = classify(gorger, { category = "quest", contextOnly = true, questStep = true })
equal(quest.key, "quest", "current last quest is distinct from the drop")
equal(quest.requirement, false, "final quest is a direct reward route")
local purchase = { id = 3005, kind = "Торговец" }
local achievement = classify(purchase, { category = "achievement", contextOnly = true, view = { purchaseRequirement = true } })
equal(achievement.key, "achievement", "purchase can be found through a tied achievement")
equal(achievement.requirement, true, "achievement does not grant the purchase")
equal(classify(purchase, { vendor = {} }).key, "purchase", "vendor stays canonical")
local doom = { id = 293, spell = 62048, kind = "Добыча" }
equal(classify(doom).key, "loot", "anniversary drop is loot")
equal(classify(doom).eventID, 1808, "anniversary is a constraint on that drop")
local holidayPurchase = classify(doom, { vendor = { holiday = 1808 } })
equal(holidayPurchase.key, "purchase", "anniversary vendor remains a purchase")
equal(holidayPurchase.eventID, 1808, "anniversary constraint stays on purchase too")
local retired = { id = 313, unavailable = true, availability = atlas.legacySources[313] }
equal(classify(retired).state, "historical", "archive has no current route")
equal(classify(retired).key, nil, "archive is outside the ten actual categories")
equal(classify(retired).historyKey, "pvp", "typed archive evidence is retained separately")
equal(classify(retired).historyLabel, "PvP", "verified former method is available for the summary")
local unverifiedArchive = classify({ id = 90002, unavailable = true })
equal(unverifiedArchive.label, "Способ не указан", "an archive without evidence has no inferred method")
equal(unverifiedArchive.historyLabel, nil, "unverified archive has no historical method caption")
local inarius = atlas.legacySourceDetails({ id = 2605, spell = 1241429 })
equal(classify({ id = 2605, unavailable = true, availability = inarius }).historyLabel, "Добыча",
    "Inarius Charger retains the confirmed former goblin drop method")
local historicText = atlas.ui.historicalSourceBody({ availability = inarius }, "Недоступно для получения")
assert(historicText:find("|cffebc270Алчный посланец|r: |cff9fddeb1–29 июля 2025 года.|r", 1, true),
    "history uses the localized event and bounded date colors")
assert(not historicText:find("Недоступно для получения", 1, true), "archive body does not repeat the status")
local closedSource = atlas.mountByID(2781)
assert(closedSource.unknownSourceNote and classify(closedSource).state == "unknown" and not closedSource.unavailable,
    "empty Amani Hex Bear has an attributed note without a confirmed availability claim")
local box = { item = 54537, name = "Коробочка в виде сердца", englishName = "Heart-Shaped Box" }
equal(atlas.ui.containerSourceBody("Источник: коробочка в виде сердца\nПраздник: Любовная лихорадка", box),
    "Праздник: Любовная лихорадка", "container name is merged into the action, retaining actual event details")
equal(atlas.ui.containerSourceBody("Use a Heart-Shaped Box to see other rewards.", box),
    "Use a Heart-Shaped Box to see other rewards.", "container names in source instructions are preserved")
equal(atlas.ui.compactSourceBody("Награда журнала путешественника\nДоступно до: 30.11.2026",
    { subtype = "Награда журнала путешественника" }), "Доступно до: 30.11.2026",
    "standalone repeated source heading is removed while its dates stay")
equal(atlas.ui.compactSourceBody("|cffffd200Торговая лавка|r\nЦена: 500", { subtype = "Торговая лавка" }),
    "Цена: 500", "native color on a redundant shop caption does not hide its price")
for _, locale in ipairs({ "ruRU", "enUS" }) do
    language = locale
    local mixed = locale == "enUS" and "Trading Post / Shop" or "Торговая лавка / магазин"
    for id, spell in pairs({ [1266] = 302361, [1267] = 302362, [1577] = 366962, [1583] = 367875 }) do
        local mount = { id = id, spell = spell, kind = "Торговая лавка" }
        local route = classify(mount)
        equal(route.stock, "unknown", "cold Trading Post stays unknown for historical shop mounts")
        equal(atlas.ui.compactSourceBody("|cffffd200" .. mixed .. "|r", route), "",
            "the combined native label does not survive in the active Trading Post body")
        assert(atlas.ui.sourceHistory(mount):find(locale == "enUS" and "In-Game Shop" or "Магазин", 1, true),
            "verified former shop offer remains available in source history")
    end
    local shopRoute = classify({ kind = "Магазин" })
    equal(atlas.ui.compactSourceBody(mixed, shopRoute), mixed, "a different acquisition route keeps its own source text")
    equal(atlas.ui.compactSourceBody(mixed .. "\nPrice: 500", { subtype = "Торговая лавка", stock = "current" }),
        "Price: 500", "a current offer retains its price when the redundant heading is removed")
end
language = "ruRU"
local venthyr = { name = "Вентиры", texture = "Interface\\Icons\\UI_Sigil_Venthyr" }
local venthyrLine = "Ковенант: |T" .. venthyr.texture .. ":16:16:0:0|t Вентиры"
equal(atlas.ui.deduplicateSourceFields(venthyrLine .. "\nМесто: Ревендрет", "Ревендрет", venthyr), "",
    "location and the covenant already visible on the item disappear together")
equal(atlas.ui.deduplicateSourceFields(venthyrLine .. "\nЗона: Ревендрет", "Ревендрет"), venthyrLine,
    "a covenant remains when there is no visible item covenant")
equal(atlas.ui.deduplicateSourceFields("Location: Shattrath City, Outland\nRequires: Key", "Shattrath City, Outland"),
    "Requires: Key", "the comma-qualified exact location is removed without its neighboring condition")
local differentPlaces = "Место: Ревендрет · Арденвельд\nМесто: Замок Нафрия\nМесто: |Hworldmap:1525:4400:4100|h[Ревендрет]|h"
equal(atlas.ui.deduplicateSourceFields(differentPlaces, "Ревендрет", venthyr), differentPlaces,
    "location alternatives, subzones and map links preserve their own meaning")
equal(atlas.ui.deduplicateSourceFields("Ковенант: Вентиры · известность 45", "—", venthyr),
    "Ковенант: Вентиры · известность 45", "a covenant with an additional condition stays")
equal(atlas.ui.singleSourcePlace("Covenant: Venthyr\nLocation: Revendreth"), "Revendreth", "active covenant page location")
equal(atlas.ui.singleSourcePlace("Location: Revendreth\nArea: Ardenweald"), nil,
    "multiple locations do not overwrite the summary with an arbitrary one")
local address, sourceAddress, child = atlas.ui.sourceAddress("Зона: остров Дорн\nЗона: Дорногал", "Остров Дорн")
equal(address, "Остров Дорн · Дорногал", "verified active parent and city compose one address")
equal(child, 2339, "Dornogal's map is used for the full active address")
equal(atlas.ui.deduplicateSourceFields("Место: Остров Дорн · Дорногал", address, nil, sourceAddress), "",
    "the same full verified address is no longer a second body row")
equal(atlas.ui.sourceAddress("Зона: Видение Штормграда\nЗона: Видение Оргриммара", "Видение Штормграда"), nil,
    "the independent Visions do not form one address")
equal(atlas.summaryLocationName({ kind = "Подземелье" }, "Сетеккские залы · героический"), "Сетеккские залы",
    "recognized difficulty suffix stays out of the summary")
equal(atlas.summaryLocationName({ kind = "Рейд" }, "Каражан · рейд"), "Каражан", "raid context stays out of the summary")
equal(atlas.summaryLocationName({ kind = "Подземелье" }, "Возвращение в Каражан"), "Возвращение в Каражан",
    "actual instance names remain intact")
equal(atlas.ui.sameSourceAddress("Крепость Бурь · Око", "Крепость Бурь · Око"), true,
    "the complete displayed instance address may be shown once")
equal(atlas.ui.sameSourceAddress("Tempest Keep · The Eye", "Tempest Keep"), false,
    "a named wing is not a duplicate of its parent location")
equal(atlas.ui.sameSourceAddress("Возвращение в Каражан", "Каражан"), false,
    "the separate Karazhan instance remains distinct")
equal(atlas.sourcePlaceValue("|cffffd200Торговец|r", "Торговец"), nil, "localized source type is not a place")
equal(atlas.sourcePlaceValue("Vendor", "Торговец"), nil, "English source type is not a place")
equal(atlas.sourcePlaceValue("Запретный край", "Торговец"), "Запретный край", "proper vendor place is preserved")
local oldBuild = GetBuildInfo
GetBuildInfo = function() return "12.1.5", "", "", 120105 end
local xurSource, xur = atlas.reviewedVendorSource({ id = 847, spell = 227956, journalSourceRaw = "Торговец: Ксур'иос" })
assert(xur and xur.npc == 107109 and xur.map == 627 and xur.x == .488 and xur.y == .135
    and xurSource:find("|Hcurrency:1275|", 1, true), "Xur'ios matches the verified Legion vendor and price")
local renoSource, reno = atlas.reviewedVendorSource({ id = 2296, spell = 466133,
    journalSourceRaw = 'Локальное задание: "Верните мне шляпу"\nЗона: остров Дорн\nЗона: Дорногал' })
assert(reno and reno.npc == 226250 and reno.item == 229974 and reno.formerQuest.id == 85243
    and renoSource:find("|Hcurrency:2815|", 1, true), "confirmed purchase replaces the outdated quest source")
local skimmerSource, skimmer = atlas.reviewedVendorSource({ id = 2512, spell = 1224048,
    journalSourceRaw = 'Задание: "Изъято!"\nЗона: остров Дорн' })
assert(skimmer and skimmer.item == 238051 and skimmer.npc == 226250 and skimmer.formerQuest.id == 91782
    and skimmerSource:find("10000 |Hcurrency:2815|", 1, true), "the former season-three quest is replaced by the confirmed Reno purchase")
equal(atlas.reviewedVendorSource({ id = 847, spell = 1, journalSourceRaw = "Vendor: Xur'ios" }), nil,
    "the same vendor name does not override a different teaching spell")
language = "enUS"
assert(atlas.reviewedVendorSource({ id = 847, spell = 227956, journalSourceRaw = "Vendor: Xur'ios" })
    :find("Broken Isles · Dalaran", 1, true), "the active English route keeps its full address")
language = "ruRU"
do
    local expected = {
        { 3032, 252956, 2393, "2250 |Hcurrency:3392|h", "10-й уровень", "rank 10" },
        { 3066, 266188, 2393, "2500 |Hcurrency:3316|h", "Анклав акироведов (Превознесение)", "Aqir Research Enclave (Exalted)" },
        { 3137, 274363, 2576, "5000000|T", "до окончания дополнения Midnight", "until the end of Midnight" },
    }
    for _, route in ipairs(expected) do
        local id, npc, map, price, russianCondition, englishCondition = unpack(route)
        local offer = atlas.reviewedVendorOffers[id]
        for index, locale in ipairs({ "ruRU", "enUS" }) do
            language = locale
            local source, match = atlas.reviewedVendorSource({ id = id, spell = offer.spell, journalSourceRaw = offer.native[index] })
            assert(match and match.npc == npc and match.map == map and match.x > 0 and match.y > 0, "reviewed Retail vendor waypoint " .. id)
            assert(source:find(price, 1, true), "reviewed Retail vendor price " .. id)
            assert(source:find(index == 1 and russianCondition or englishCondition, 1, true), "localized purchase requirement " .. id)
        end
    end
    local offer = atlas.reviewedVendorOffers[3066]
    local liveSource = { id = 3066, spell = offer.spell, journalSourceRaw = offer.native[2] }
    assert(atlas.reviewedVendorSource(liveSource), "the current Aqir reputation requirement is applied")
    GetBuildInfo = function() return "12.1.7", "", "", 120107 end
    equal(atlas.reviewedVendorSource(liveSource), nil, "the next patch must use its own price and standing requirement")
    language = "ruRU"
end
GetBuildInfo = oldBuild
local testPoints = { { map = 627, x = .1, y = .2 }, { map = 627, x = .3, y = .4 }, { map = 627, x = .1, y = .2 } }
equal(atlas.ui.waypointGroupSize(testPoints), 2, "the waypoint action counts distinct markers only")
local previousTomTom = TomTom
TomTom = nil
equal(atlas.ui.waypointAction({}, testPoints[1], testPoints, "RightButton"), nil,
    "without TomTom bulk click does not overwrite the game's single waypoint")
local markers = 0
TomTom = { AddWaypoint = function() markers = markers + 1; return markers end }
local previousAccount = MountAtlasAccountDB
MountAtlasAccountDB = { settings = { waypointProvider = "wow" } }
equal(atlas.ui.waypointAction({}, testPoints[1], testPoints, "RightButton"), nil,
    "the selected WoW provider disables bulk click even when TomTom is installed")
equal(atlas.bulkWaypointUnavailableText(), "Для нескольких меток выбери TomTom",
    "the tooltip recognizes an installed TomTom in WoW mode")
atlas.setWaypointProvider("tomtom")
atlas.ui.waypointAction({}, testPoints[1], testPoints, "RightButton")
equal(markers, 2, "TomTom right-click adds all distinct current waypoints")
MountAtlasAccountDB = previousAccount
TomTom = previousTomTom
local rares = { rare = {} }
assert(loadfile("Data/Rares.lua"))("PawAtlas", rares)
local warfrontFactions = {
    [1173] = { [142739] = 2, horde = 2 },
    [1174] = { [142741] = 2, alliance = 2 },
    [1199] = { [149652] = 2, [149660] = 1, alliance = 2, horde = 1 },
    [1203] = { [147701] = 2, [148037] = 2, alliance = 2, horde = 2 },
}
local warfrontSide = {
    [142739] = "Horde", [142741] = "Alliance", [149652] = "Alliance",
    [149660] = "Horde", [147701] = "Alliance", [148037] = "Horde",
}
local locatedRares = {
    [1514] = { count = 21, npc = 179472, map = 1961, x = .444, y = .294 },
    [2038] = { count = 1, npc = 208029, map = 2024, x = .278, y = .46 },
}
for _, rare in ipairs(rares.rares) do
    if warfrontFactions[rare.id] then
        local counts = {}
        for _, point in ipairs(atlas.mountLocations(rare, nil, true)) do
            local faction = atlas.sourcePointFaction(point)
            equal(faction, warfrontSide[point.npc], "warfront faction belongs to the exact NPC and point")
            counts[point.npc] = (counts[point.npc] or 0) + 1
            local side = faction:lower()
            counts[side] = (counts[side] or 0) + 1
        end
        for key, count in pairs(warfrontFactions[rare.id]) do
            equal(counts[key], count, "warfront faction/coordinate coverage " .. rare.id)
        end
        warfrontFactions[rare.id] = nil
    elseif rare.id == 1182 then
        local points = atlas.mountLocations(rare, nil, true)
        equal(#points, 4, "Krix retains both phase positions, the entrance and the unlabelled observation")
        equal(points[1].kind, "caveEntrance", "Krix cave entrance is the first waypoint")
        equal(points[1].x, .3344, "Krix entrance X")
        equal(points[1].y, .3694, "Krix entrance Y")
        equal(points[2].englishCondition, "Horde controls Stromgarde", "Krix Horde-controlled phase")
        equal(points[3].englishCondition, "Alliance controls Stromgarde", "Krix Alliance-controlled phase")
        equal(points[4].condition, nil, "an observation with no known phase must stay unlabelled")
        equal(atlas.sourcePointCondition(points[1]), nil, "the cave entrance is not a Russian loot condition")
        language = "enUS"
        equal(atlas.sourcePointCondition(points[1]), nil, "the cave entrance is not an English loot condition")
        equal(atlas.sourcePointCondition({ condition = "Альянс", englishCondition = "" }), "Альянс",
            "missing localized detail falls back to the stored condition")
        language = "ruRU"
        for _, point in ipairs(points) do
            equal(atlas.sourcePointFaction(point), nil, "control phase is distinct from loot eligibility")
        end
    elseif rare.id == 1200 then
        for _, point in ipairs(atlas.mountLocations(rare, nil, true)) do
            equal(atlas.sourcePointFaction(point), nil, "shared Darkshore NPC stays faction neutral")
        end
    elseif rare.id == 1298 or rare.id == 1319 then
        local points = atlas.mountLocations(rare, nil, true)
        equal(#points, 1, "reviewed rounded source waypoint merges for " .. rare.id)
        equal(points[1].x, rare.id == 1298 and .5198 or .3085, "the exact original coordinate wins")
        if rare.id == 1298 then
            equal(points[1].condition, "Вентиры", "Hopecrusher keeps its specific covenant requirement")
            local alternative = atlas.navigationPoints[rare.id]
            alternative[#alternative + 1] = { map = 1525, npc = 166679, x = .520, y = .518,
                boss = "Сокрушитель Надежд", condition = "Другая фаза" }
            equal(#atlas.mountLocations(rare, nil, true), 2, "equal-looking coordinates do not merge different conditions")
            alternative[#alternative] = nil
            language = "enUS"
            equal(atlas.displayMountName(rare), "Hopecrusher Gargon", "actual mount title")
            equal(atlas.displayName(points[1].boss, "target"), "Hopecrusher", "distinct encounter name")
            language = "ruRU"
        end
    elseif rare.id == 1229 then
        local points = atlas.mountLocations(rare, nil, true)
        equal(#points, 3, "distinct Arachnoid NPCs and their alternate point are retained")
        assert(points[1].npc ~= points[2].npc, "separate phases sharing coordinates remain distinct")
    elseif locatedRares[rare.id] then
        local expected = locatedRares[rare.id]
        local points = atlas.mountLocations(rare, nil, true)
        equal(#points, expected.count, "a sighting replaces the redundant zone page for " .. rare.id)
        local first = points[1]
        assert(first.npc == expected.npc and first.map == expected.map and first.x == expected.x and first.y == expected.y,
            "the first page has the original sighting for " .. rare.id)
        for _, point in ipairs(points) do assert(atlas.hasSourceCoordinates(point)) end
        locatedRares[rare.id] = nil
    elseif rare.id == 2751 or rare.id == 2827 then
        local points = atlas.mountLocations(rare, nil, true)
        local factionPoints = {}
        for _, point in ipairs(points) do
            local faction = atlas.npcSourceFactions[point.npc]
            if faction then
                assert(atlas.hasSourceCoordinates(point), "a fixed faction label does not leave a redundant zone page")
                equal(atlas.sourcePointFaction(point), faction, "the faction of the accurate point is preserved")
                factionPoints[faction] = true
            end
        end
        assert(factionPoints.Alliance and factionPoints.Horde, "both distinct faction targets retain their waypoints")
    elseif rare.id == 3051 or rare.id == 3061 then
        local points = atlas.mountLocations(rare, nil, true)
        equal(#points, 61, "precise rare points and the one unknown location are kept for " .. rare.id)
        equal(points[1].npc, 263456, "the rare with no reviewed coordinates retains its own page")
        for i = 2, #points do assert(atlas.hasSourceCoordinates(points[i])) end
    end
    if rare.id == 611 or rare.id == 622 or rare.id == 643 then
        local points = atlas.mountLocations(rare, nil, true)
        equal(#points, 4, "Tanaan sources with reviewed equivalent waypoints " .. rare.id)
        local names = {}
        for _, point in ipairs(points) do names[point.npc] = true end
        for _, npc in ipairs({ 95044, 95053, 95054, 95056 }) do
            equal(names[npc], true, "each Tanaan target retains a waypoint")
        end
        if rare.id == 622 then
            local extra = atlas.navigationPoints[rare.id]
            extra[#extra + 1] = { map = 534, x = .487, y = .535, npc = 95056,
                boss = "Пушка Смерти", place = "Танаанские джунгли" }
            equal(#atlas.mountLocations(rare, nil, true), 5, "a separate point for the same NPC remains distinct")
            extra[#extra] = nil
        end
        local source = "Добыча: Воздаяние, Коготь Смерти, Кулак Страха, Пушка Смерти\nМесто: Танаанские джунгли\nТребуется: ключ"
        equal(atlas.ui.structuredLootBody(source, "Пушка Смерти", "Танаанские джунгли", points), "Требуется: ключ",
            "covered structured fields disappear while their condition remains")
        assert(atlas.ui.structuredLootBody(source, "Пушка Смерти", "Танаанские джунгли", { points[1] })
            :find("Коготь Смерти", 1, true), "raw targets absent from the active pager are preserved")
        language = "enUS"
        equal(atlas.ui.structuredLootBody("Drop: Vengeance, Deathtalon, Terrorfist, Doomroller\nLocation: Tanaan Jungle\nRequires: key",
            "Doomroller", "Tanaan Jungle", points), "Requires: key", "covered English Tanaan sources")
        language = "ruRU"
    end
end
assert(next(warfrontFactions) == nil, "exercise every reviewed warfront mount")
assert(next(locatedRares) == nil, "exercise both reported cards")
do
    for _, sample in ipairs({
        { "ruRU", "Сокровище: тайник претендента", "Тайник претендента", "Вольная Гавань", "Красавчик Харлан", "Требуется: ключ" },
        { "enUS", "Treasure: Challenger's Cache", "Challenger's Cache", "Freehold", "Harlan Sweete", "Requires: key" },
    }) do
        local locale, line, target, place, boss, condition = unpack(sample)
        language = locale
        local body = line .. "\nМесто: " .. place .. "\n" .. condition
        equal(atlas.ui.structuredLootBody(atlas.displaySourceText(body), target, place), atlas.displaySourceText(condition),
            "the displayed treasure and place are omitted from the body while the requirement remains")
        equal(atlas.ui.structuredLootBody(line, boss, place), line, "a different target's treasure remains visible")
        local qualified = line .. " (Mythic+)"
        equal(atlas.ui.structuredLootBody(qualified, target, place), qualified, "a qualifier on the treasure remains visible")
    end
    language = "ruRU"
end
do
    local points = { { boss = "Аш'ан Усиленный", place = "Зул'Аман", npc = 245692 } }
    local line = "Источник: Редкие существа Зул'Амана"
    local function rareBody(body, place, list)
        return atlas.ui.structuredLootBody(body, points[1].boss, place, list, true)
    end
    equal(rareBody(line .. "\nТребуется: ключ", "Зул'Аман", points), "Требуется: ключ", "covered rare group")
    equal(rareBody(line, "Харандар", points), line, "keep the source of another zone")
    equal(rareBody(line, "Зул'Аман", nil), line, "keep the source without a target list")
    equal(rareBody(line .. " после события", "Зул'Аман", points), line .. " после события", "keep rare group conditions")
    equal(rareBody("Source: Zul'Aman Rare Creatures\nRequires: key", "Zul'Aman", points), "Requires: key",
        "English rare group captions preserve additional requirements")
end
do
    local zone = { map = 1, npc = 10 }
    local precise = { map = 1, npc = 10, x = .3, y = .4, kind = "sighting" }
    local phase = { map = 1, npc = 10, condition = "Separate phase" }
    local quest = { map = 1, npc = 10, kind = "quest", quest = 123 }
    local differentMap = { map = 2, npc = 10 }
    local differentNPC = { map = 1, npc = 11 }
    local mount = { id = 99001, locations = { zone, precise } }
    local points = atlas.mountLocations(mount, nil, true)
    assert(#points == 1 and points[1] == precise, "a zone can be upgraded within the original feed")

    mount.locations = { precise }
    atlas.navigationPoints[mount.id] = { zone, phase, quest, differentMap, differentNPC }
    points = atlas.mountLocations(mount, nil, true)
    assert(#points == 5 and points[1] == precise and points[2] == phase and points[3] == quest
        and points[4] == differentMap and points[5] == differentNPC,
        "a navigation feed zone can be upgraded without merging separate phases, routes, maps or NPCs")

    mount.locations = { zone }
    local forbidden = { map = 1, npc = 10, x = .3, y = .4, navigation = false }
    local invalid = { map = 1, npc = 10, x = 2, y = .4 }
    atlas.navigationPoints[mount.id] = { forbidden, invalid }
    points = atlas.mountLocations(mount, nil, true)
    assert(#points == 2 and points[1] == zone and points[2] == invalid,
        "an invalid or prohibited waypoint cannot remove the zone page")
    atlas.navigationPoints[mount.id] = nil
end
equal(classify(retired, { tradingPost = { price = 450 } }).key, "purchase", "a verified new live offer is its own route")
equal(classify({ id = 42, kind = "Торговая лавка" }).state, "unknown", "unconfirmed Trading Post stock stays unknown")
equal(classify({ id = 2793, kind = "PvP", sourceReview = atlas.legacySources[2793] }).state, "unknown",
    "a finished season is not proof of current availability")
equal(classify({ id = 42, kind = "Журнал", covenantSourceOnly = true }).key, nil, "a covenant alone cannot prove acquisition")
equal(atlas.mountByID(1958).kind, "Торговая лавка", "reviewed missing Trading Post source")
assert(atlas.mountByID(1958).journalSourceOverride:find("212229", 1, true), "Trading Post reward item")
equal(atlas.mountByID(222), nil, "replaced Swift Zhevra prototype")
assert(atlas.mountByID(224), "released Swift Zhevra is kept")
assert(atlas.mountByID(92007), "same name is not deduplicated")
for category, kind in ipairs(expected) do
    local mount = assert(atlas.mountByID(90000 + category))
    equal(mount.kind, kind, "numeric source " .. category)
end
for _, category in ipairs({ -1, 0, 13 }) do
    equal(atlas.mountByID(91000 + category).kind, "Журнал", "unknown source " .. category)
end
for _, entry in ipairs(zoneDrops) do
    local mount = assert(atlas.mountByID(entry[1]))
    equal(mount.spell, entry[2], "zone drop spell " .. entry[1])
    equal(atlas.attemptStages[entry[1]].reward.item, entry[3], "zone drop item " .. entry[1])
    equal(mount.kind, "Добыча", "zone drop kind " .. entry[1])
    assert(not mount.hasQuest, "zone drop included by quest filter: " .. entry[1])
    assert(mount.key:find(atlas.searchKey("Добыча"), 1, true), "drop missing from search: " .. entry[1])
    assert(not mount.key:find(atlas.searchKey("Квест"), 1, true), "quest leaked into search: " .. entry[1])
end
for _, id in ipairs({ 92001, 92003 }) do
    equal(atlas.mountByID(id).kind, "Квест", "explicit quest overrides category " .. id)
    equal(atlas.mountByID(id).hasQuest, true, "explicit quest filter " .. id)
end
for _, id in ipairs({ 92002, 92004 }) do
    equal(atlas.mountByID(id).kind, "Добыча", "explicit drop overrides category " .. id)
    assert(not atlas.mountByID(id).hasQuest, "explicit drop included by quest filter: " .. id)
end
equal(atlas.mountByID(92005).kind, "Журнал", "Legacy remains journal-only")
assert(atlas.mountByID(92008).hasAchievement and #atlas.mountByID(92008).achievementSteps == 1,
    "a separate native achievement route joins the achievement filter")
assert(not atlas.mountByID(92009).hasAchievement, "text mentioning an achievement is not an acquisition route")
assert(atlas.mountByID(92010).hasAchievement, "Feats of Strength belongs to the achievement filter")
equal(atlas.mountByID(92011).kind, "Исследование", "exploration journal heading preserves the acquisition type")
equal(atlas.mountByID(92006).indexed, false, "unavailable source is retried")
entries[92006].source = "Drop: Loaded later\nZone: Open world"
do
    local listCalls, infoCalls, extraCalls = journalCalls.list, journalCalls.info, journalCalls.extra
    equal(atlas.ensureJournal(), true, "opening publishes the late source")
    equal(journalCalls.list, listCalls, "opening with a late source keeps membership cached")
    equal(journalCalls.info, infoCalls + 1, "only the unresolved source is sampled")
    equal(journalCalls.extra, extraCalls + 1, "late source extra info is fetched once")
end
equal(atlas.mountByID(92006).kind, "Добыча", "loaded source replaces numeric fallback")
equal(atlas.mountByID(92006).indexed, true, "loaded source finishes indexing")

local hawk = atlas.mountByID(1600)
equal(hawk.journalSourceOverride, "Задание: Рыцарь крови — для паладинов\nЗона: Призрачные земли\n\n"
    .. "Задание: Слава син’дорай — для остальных классов\nЗона: Призрачные земли", "RU class alternatives")
language = "enUS"
for _, id in ipairs(eggAndCacheMounts) do
    entries[id].source = atlas.journalSourceDetails[id].replacesSource[2]:gsub("\n", "|n")
    atlas.mountByID(id).indexed = false
end
for id in pairs(drakeQuests) do
    entries[id].source = atlas.questMountRewards[id].journalDetail.replacesSource[2]
    atlas.mountByID(id).indexed = false
end
local quickhoof = atlas.mountByID(1324)
quickhoof.indexed = false
riverbeast.indexed = false
entries[631].source = "|cFFFFD200Garrison Mission:|r It's a Boat, It's a Plane, It's... Just a Riverbeast.|n"
felcycle.indexed = false
entries[1943].source = "|cFFFFD200World Event:|r WoW's 20th Anniversary?|n"
blackMalice.indexed = false
entries[3133].source = "|cFFFFD200Promotion|r"
closedSource.indexed = false
entries[2781].source = "Quest: A confirmed new route"
entries[1600].source = "Quest: Blood Knight\nZone: Ghostlands\n\nQuest: Victory for the Sin'dorei\nZone: Ghostlands"
hawk.indexed = false
atlas.syncJournal()
checkEggAndCachePlaces("Isle of Giants", "Nazjatar")
for id, questID in pairs(drakeQuests) do
    local mount = assert(atlas.mountByID(id))
    equal(mount.kind, "Квест", "the English mount source uses the verified quest too")
    assert(atlas.decorateSource(mount):find("|Hquest:" .. questID .. ":", 1, true))
end
checkRiverbeastMission("Successfully complete the mission at the Shipyard")
assert(felcycle.journalSourceOverride:find("Ratts' Revenge", 1, true), "EN Felcycle route")
assert(blackMalice.journalSourceOverride:find("November 17, 2026", 1, true), "EN ended preorder terms")
equal(closedSource.unknownSourceNote, nil, "a real native route replaces the earlier collector note")
assert(quickhoof.journalSourceOverride:find("Seaside Leafy Greens Mix", 1, true), "EN exploration condition")
equal(hawk.journalSourceOverride, "Quest: Blood Knight — for paladins\nZone: Ghostlands\n\n"
    .. "Quest: Victory for the Sin'dorei — for other classes\nZone: Ghostlands", "EN class alternatives")
entries[1600].spell = 1
hawk.indexed = false
entries[631].source = "Garrison Mission: A different mission"
riverbeast.indexed = false
atlas.syncJournal()
equal(hawk.journalSourceOverride, nil, "different source spell keeps native text")
equal(atlas.sourceGuaranteedReward(riverbeast, {}), nil, "a changed mission does not inherit the guarantee")
entries[1600].spell, entries[1600].source = 370620, "Quest: New native route\nZone: Ghostlands"
hawk.indexed = false
atlas.syncJournal()
equal(hawk.journalSourceOverride, nil, "changed native source keeps its text")
entries[1324].source = "Zone: New native location"
quickhoof.indexed = false
atlas.syncJournal()
equal(quickhoof.sourceRequirements, nil, "a changed native source must not inherit old conditions")

local variantMounts = { [1376] = 181316, [1392] = 180726, [1408] = 181300, [1413] = 181317 }
local questVendors = { [55] = { [10618] = 83 }, [186] = { [23489] = 104 }, [187] = { [23489] = 104 },
    [188] = { [23489] = 104 }, [189] = { [23489] = 104 }, [190] = { [23489] = 104 }, [191] = { [23489] = 104 },
    [448] = { [58414] = 371 }, [464] = { [58414] = 371 }, [465] = { [58414] = 371 },
    [1615] = { [187408] = 2022, [189226] = 2022 }, [1616] = { [187408] = 2022, [189226] = 2022 },
    [1653] = { [186462] = 2024, [193006] = 2024 }, [1655] = { [186462] = 2024, [193006] = 2024 },
    [1657] = { [186462] = 2024, [193006] = 2024 }, [1659] = { [186462] = 2024, [193006] = 2024 },
    [1683] = { [200559] = 2151, [196637] = 2112 }, [1684] = { [200559] = 2151, [196637] = 2112 },
    [1685] = { [200559] = 2151, [196637] = 2112 }, [1686] = { [200559] = 2151, [196637] = 2112 },
}
for _, locale in ipairs({ "ruRU", "enUS" }) do
    language = locale
    local en = locale == "enUS"
    local native = en and ("Covenant Feature: The Ember Court\nCovenant: Venthyr\n\n"
        .. "Covenant Feature: Queen's Conservatory\nCovenant: Night Fae\n\n"
        .. "Covenant Feature: Path of Ascension\nCovenant: Kyrian\n\nCovenant Feature: Abomination Factory\nCovenant: Necrolord")
        or ("Особенность ковенанта: Пепельный двор\nКовенант: вентиры\n\n"
            .. "Особенность ковенанта: королевский зимний сад\nКовенант: ночной народец\n\n"
            .. "Особенность ковенанта: Путь Перерождения\nКовенант: кирии\n\nОсобенность ковенанта: фабрика поганищ\nКовенант: некролорды")
    for id, item in pairs(variantMounts) do
        local data = atlas.covenantVariantSources[id]
        local mount = { id = id, spell = data.spell, kind = "Торговец", journalSourceRaw = native }
        equal(data.item, item, "exact covenant mount teaching item")
        local choices = atlas.covenantVariantChoices(mount)
        equal(#choices, 4, "each covenant has a page")
        for page, choice in ipairs(choices) do
            local covenant = ({ 2, 3, 1, 4 })[page]
            local isVendor = covenant == 4 or covenant == 2 and id == 1376 or covenant == 1 and id ~= 1413
            local route = atlas.classifyMountSource(mount, choice)
            equal(choice.covenantVariant, covenant, "stable covenant order")
            equal(route.key, isVendor and "purchase" or "loot", "use the selected covenant acquisition path")
            equal(route.icon, isVendor and "Vendor" or "Loot", "use the corresponding summary glyph")
            equal(choice.view.sourceMap, ({ 1707, id == 1376 and 1525 or 1644, 1662, 1698 })[covenant], "exact route map")
            equal(choice.view.trackingCompatible, false, "a new path cannot invent an attempt rate")
            local covenants = atlas.mountCovenantRequirements(choice.view)
            equal(#covenants, 1, "scope the selected covenant independently")
            equal(covenants[1].id, covenant, "selected covenant matches its requirement")
            if isVendor then
                local vendor = choice.vendor
                equal(vendor.npc, ({ 171973, 164966, false, 159238 })[covenant], "exact merchant")
                assert(vendor.conditions:find((covenant == 1 and "2500" or "5000") .. " |Hcurrency:1813|h", 1, true))
                equal(vendor.x, ({ .316, .280, false, .488 })[covenant], "exact normalized merchant x")
                equal(vendor.y, ({ .480, .430, false, .150 })[covenant], "exact normalized merchant y")
                if covenant == 2 then equal(vendor.waypoints[2].map, 1699, "alternate Temel spawn retains its map") end
                if covenant == 1 then assert(vendor.conditions:find("|Hachievement:" .. data.achievement .. "|h", 1, true)) end
                if covenant == 2 or covenant == 4 then
                    local expectedID = covenant == 2 and 2445 or 2462
                    local reputationAPI, gossipAPI = C_Reputation, C_GossipInfo
                    local standing = covenant == 2 and 7 or 6
                    local nativeName = en and "Native faction name" or "Название фракции из клиента"
                    C_Reputation = { GetFactionDataByID = function(factionID)
                        equal(factionID, expectedID, "the merchant's exact faction is read by ID")
                        if covenant == 2 and standing then return { name = nativeName, reaction = standing } end
                    end }
                    C_GossipInfo = { GetFriendshipReputation = function(factionID)
                        equal(factionID, expectedID, "friendship data is read by the same faction ID")
                        if covenant == 4 and standing then
                            return { friendshipFactionID = 1, name = nativeName,
                                reaction = atlas.L(standing == 8 and "Превознесение" or "Уважение") }
                        end
                    end }
                    local sourceMount = { id = id, journalSourceRaw = vendor.conditions, vendorName = vendor.name }
                    local expectedStanding = atlas.L(covenant == 2 and "Почтение" or "Уважение")
                    local text = atlas.decorateSource(sourceMount)
                    assert(text:find(nativeName .. " (" .. atlas.L("Превознесение") .. ")", 1, true))
                    assert(text:find(atlas.L("  (Текущая репутация: %s)", expectedStanding), 1, true))
                    standing = 8
                    assert(atlas.decorateSource(sourceMount):find("ui-questtracker-tracker-check", 1, true))
                    standing = nil
                    assert(atlas.decorateSource(sourceMount):find(atlas.L("  (Текущая репутация: —)"), 1, true))
                    C_Reputation, C_GossipInfo = reputationAPI, gossipAPI
                end
            elseif covenant == 3 then
                assert(choice.view.journalSourceRaw:find("{item:176832:", 1, true))
                assert(choice.view.journalSourceRaw:find("{item:" .. data.spirit .. ":", 1, true))
            elseif covenant == 2 then
                assert(choice.view.journalSourceRaw:find(data.chests[2][en and 3 or 2], 1, true))
            else
                assert(choice.view.journalSourceRaw:find(en and "Azaruux" or "Азаруукса", 1, true))
            end
        end
        mount.spell = 1
        equal(atlas.covenantVariantChoices(mount), nil, "different teaching spell keeps the native route")
        mount.spell, mount.journalSourceRaw = data.spell, "Vendor: New source"
        equal(atlas.covenantVariantChoices(mount), nil, "changed source keeps the native route")
    end
    for id, vendors in pairs(questVendors) do
        local reward = atlas.questMountRewards[id]
        local mount = { id = id, spell = reward.spell, kind = "Квест" }
        local primary = { view = mount, classification = atlas.classifyMountSource(mount) }
        local choices, found = { primary }, {}
        atlas.addQuestRewardVendors(mount, choices)
        assert(atlas.directQuestReward(mount, primary), "a purchase leaves the direct quest reward intact")
        for index = 2, #choices do
            local choice = choices[index]
            local vendor = choice.vendor
            equal(atlas.classifyMountSource(mount, choice).key, "purchase", "merchant is a distinct paid route")
            equal(vendor.map, vendors[vendor.npc], "verified quest merchant map")
            assert(vendor.x > 0 and vendor.x < 1 and vendor.y > 0 and vendor.y < 1)
            equal(found[vendor.npc], nil, "merchant appears once")
            found[vendor.npc] = true
            if vendor.npc == 200559 then equal(vendor.waypoints[2].map, 2118, "Treysh starter phase stays separate") end
        end
        for npc in pairs(vendors) do equal(found[npc], true, "expected merchant reachable") end
        if id == 188 or id == 448 then assert(atlas.questRewardHasExclusiveColours(mount, reward)) end
        mount.spell = 1
        local changed = {}
        atlas.addQuestRewardVendors(mount, changed)
        equal(#changed, 0, "reused mount ID cannot acquire the old vendor")
    end
    local existing = { name = en and "дедушка Баки" or "Granpap Whiskers",
        conditions = en and "Renown: 25" or "Известность: 25" }
    local skitterfly = { id = 1615, spell = atlas.questMountRewards[1615].spell }
    local choices = { { vendor = existing } }
    atlas.addQuestRewardVendors(skitterfly, choices)
    equal(#choices, 2, "existing journal seller in either locale is enriched, not duplicated")
    equal(existing.npc, 187408, "native journal seller gains exact identity")
    equal(existing.name, en and "Granpap Whiskers" or "Дедушка Баки", "matched seller displays in the active locale")
    assert(existing.conditions:find("201401", 1, true), "missing stock price gains the verified items")
end
do
    local guaranteed = atlas.sourceGuaranteedReward
    local warserpent = { id = 1313, spell = 315427, kind = "Торговец" }
    local sources = {
        "|cFFFFD200Торговец: |rЧжан Ку|n|cFFFFD200Зона: |rВечноцветущий дол|n|cFFFFD200Цена: |r1|Hitem:174230|h|TInterface\\ICONS\\INV_Misc_MonsterScales_18.blp:0|t|h",
        "Vendor: Zhang Ku\nZone: Vale of Eternal Blossoms\nCost: 1 |Hitem:174230|h[Pristine Cloud Serpent Scale]|h",
    }
    for _, source in ipairs(sources) do
        warserpent.journalSourceRaw = source
        local merchant = assert(atlas.vendorSources(warserpent))[1]
        local final = assert(guaranteed(warserpent, { vendor = merchant }))
        equal(final.method, "purchase", "exact mount is a conditional purchase")
        equal(final.item, 174649, "purchased mount is distinct from its 174230 payment")
        equal(atlas.attemptStages[1313].item.rate, 50, "exchange does not change the scale drop chance")
    end
    equal(guaranteed(warserpent, { vendor = { name = "Zhang Ku", conditions = "Cost: ?" } }), nil,
        "a merchant without a known price is not inferred to grant the mount")
    equal(guaranteed(warserpent, { vendor = { name = "Other vendor", conditions = "Cost: 1\nItem: |Hitem:174230|h[Cache]|h" } }), nil,
        "a vendor selling another item does not guarantee the mount")
    equal(guaranteed(warserpent, { verifiedDrop = true }), nil, "a drop cannot inherit a purchase guarantee")
    equal(guaranteed(warserpent, { blackMarket = {} }), nil, "Black Market offers no guarantee")
    equal(guaranteed(warserpent, { vendor = assert(atlas.vendorSources(warserpent))[1], historical = true }), nil,
        "historical vendors give no current guarantee")
    local ram = { id = 296, spell = 63636, kind = "Торговец",
        journalSourceRaw = "Vendor: Derrick Brindlebeard\nPrice: r100|Hcurrency:241|h[Champion's Seal]|h" }
    local ramVendor = assert(atlas.vendorSources(ram))[1]
    assert(ramVendor.conditions:find("Price: 100|Hcurrency", 1, true), "stray journal color marker is removed from the price")
    equal(guaranteed(ram, { vendor = ramVendor }).item, 45586, "a malformed color marker cannot hide a confirmed purchase")
    local irontusk = { id = 618, spell = 171626, kind = "Торговец",
        journalSourceRaw = "Vendor: \nZone: Garrison Trading Post\nPrice: 5000 + 5000|Hcurrency:823|h[Apexis Crystal]|h" }
    equal(guaranteed(irontusk, { vendor = assert(atlas.vendorSources(irontusk))[1] }).item, 116665,
        "explicit merchant location and mount identity can compensate for a blank journal vendor name")

    local protoDrake = { id = 278, spell = 61294, kind = "Добыча",
        journalSourceRaw = "Source: Cracked Egg\nVendor: Geen\nPrice: 3" }
    local eggVendor = assert(atlas.vendorSources(protoDrake))[1]
    equal(guaranteed(protoDrake, { vendor = eggVendor }), nil, "buying the Green Proto-Drake egg is not a fixed reward")
    local rift = { id = 1778, spell = 414324, kind = "Добыча",
        journalSourceRaw = "Source: Time Rifts\nVendor: Sorotis\nZone: Tyrhold Reservoir\nPrice: 3000" }
    equal(assert(guaranteed(rift, { vendor = assert(atlas.vendorSources(rift))[1] })).item, 206675,
        "an independent direct Time Rift purchase is distinct from its random box")

    local vial = { id = 407, kind = "Профессия", spell = 93326 }
    equal(assert(guaranteed(vial, {})).item, 65891, "a recipe with exact mount output is deterministic")
    equal(assert(guaranteed({ id = 2965, kind = "Профессия", spell = 1287359 }, {})).item, 270058,
        "the Void-Corrupted Lynx craft is guaranteed after obtaining its rare materials")
    equal(atlas.attemptStages[2965].item.rate, 300, "recipe does not change the leash drop chance")
    equal(guaranteed({ id = 386, kind = "Профессия", spell = 84751 }, {}), nil,
        "the Archaeology source label does not prove a recipe output")
    equal(guaranteed(vorquin, vonChoice).method, "quest", "a verified selectable quest reward is deterministic")
    equal(guaranteed(tauralus, assert(atlas.extraDirectGrantSource(tauralus))).method, "progress", "Renown reward is deterministic")
    equal(guaranteed(warserpent, { tradingPost = { unknown = true } }), nil, "unconfirmed Trading Post stock gives no guarantee")
    equal(guaranteed(warserpent, { tradingPost = { frozen = true, price = 500 } }).method, "tradingPost",
        "a known frozen Trading Post offer still gives a fixed item")

    local achievementApi, mountFromItem = C_AchievementInfo, C_MountJournal.GetMountFromItem
    C_AchievementInfo = { GetRewardItemID = function(id) return id == 2136 and 44160 or nil end }
    C_MountJournal.GetMountFromItem = function(id) return id == 44160 and 262 or nil end
    local drake = { id = 262, kind = "Достижение", spell = 59976,
        journalSourceRaw = "Achievement: |Hachievement:2136|h[Glory of the Hero]|h" }
    equal(assert(guaranteed(drake, {})).item, 44160, "achievement's own native reward identifies the mount")
    equal(guaranteed(drake, { view = { kind = "Достижение", purchaseRequirement = true,
        journalSourceRaw = drake.journalSourceRaw } }), nil, "purchase requirements never grant the mount themselves")
    drake.journalSourceRaw = "Achievement: |Hachievement:99|h[Another achievement]|h"
    equal(guaranteed(drake, {}), nil, "a changed achievement must confirm its own reward")
    C_AchievementInfo, C_MountJournal.GetMountFromItem = achievementApi, mountFromItem
end
do
    local timers, notifications = {}, 0
    C_Timer = { After = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
    atlas.onJournalChanged = function() notifications = notifications + 1 end
    local function flush(delay)
        local timer = assert(table.remove(timers, 1), "expected journal retry")
        equal(timer[1], delay, "journal timer delay")
        timer[2]()
    end

    local id = 92001
    local initialCollection = atlas.collection
    local sourceRevision = atlas.journalSourceRevision
    local listCalls, infoCalls, extraCalls = journalCalls.list, journalCalls.info, journalCalls.extra
    equal(atlas.ensureJournal(), false, "reopening uses the ready catalog")
    equal(atlas.ensureJournal(), false, "opening a specific card uses the same cache")
    journalEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
    journalEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
    journalEvent("PLAYER_ENTERING_WORLD", false, false)
    equal(#timers, 0, "native search and filters leave the ready cache alone")
    equal(journalCalls.list, listCalls, "reopening never enumerates membership")
    equal(journalCalls.info, infoCalls, "reopening never rereads resolved mounts")
    equal(journalCalls.extra, extraCalls, "reopening never rereads resolved sources")
    equal(atlas.collection, initialCollection, "idle refresh preserves snapshot identity")

    local collected = atlas.collection.collected
    local expansionCollected = atlas.collection.expansions.Other.collected
    journalEvent("NEW_MOUNT_ADDED", id)
    journalEvent("NEW_MOUNT_ADDED", id)
    equal(#timers, 1, "coalesce duplicate acquisition events")
    flush(0)
    equal(journalCalls.info, infoCalls + 1, "acquisition reads one mount")
    equal(journalCalls.lastID, id, "acquisition uses the event's mount ID")
    equal(atlas.collection.collected, collected, "stale ownership cannot increase totals")
    equal(notifications, 0, "stale ownership does not refresh the UI")
    entries[id].collected = true
    flush(.25)
    equal(journalCalls.list, listCalls, "acquisition never reloads membership")
    equal(journalCalls.info, infoCalls + 2, "delayed acquisition retries only its ID")
    equal(journalCalls.extra, extraCalls, "acquisition keeps the original resolved source")
    equal(atlas.collection.byID[id], true, "acquisition updates the collection even while the UI is hidden")
    equal(atlas.collection.collected, collected + 1, "collection total increases once")
    equal(atlas.collection.expansions.Other.collected, expansionCollected + 1, "expansion total increases once")
    assert(atlas.collection ~= initialCollection, "ownership change publishes a new snapshot identity")
    equal(atlas.journalSourceRevision, sourceRevision, "acquisition keeps resolved source caches intact")
    equal(notifications, 1, "confirmed acquisition refreshes the UI once")
    journalEvent("NEW_MOUNT_ADDED", id)
    equal(#timers, 0, "duplicate confirmation is ignored")

    local newID, total = 990001, atlas.collection.total
    -- The acquisition can first expose an entry absent from the old list.
    entries[newID] = { name = "[PH] Future mount", spell = newID, category = 1, source = "", collected = false }
    extraCalls = journalCalls.extra
    journalEvent("NEW_MOUNT_ADDED", newID)
    flush(0)
    equal(atlas.mountByID(newID), nil, "unconfirmed placeholder remains filtered")
    equal(journalCalls.extra, extraCalls, "the placeholder is filtered before reading extra info")
    entries[newID].collected = true
    flush(.25)
    assert(atlas.mountByID(newID), "confirmed acquisition can expose a previously filtered mount")
    equal(journalCalls.extra, extraCalls + 1, "the collected placeholder has its extra info indexed")
    equal(atlas.collection.total, total + 1, "new mount updates membership by ID")
    equal(atlas.collection.collected, collected + 2, "new mount counts once")
    assert(atlas.journalSourceRevision > sourceRevision, "new catalog membership invalidates source caches")
    equal(journalCalls.list, listCalls, "new membership from acquisition still avoids a full scan")

    entries[id].collected = false
    journalEvent("COMPANION_UNLEARNED", "CRITTER")
    equal(#timers, 0, "pet removal does not affect mount ownership")
    journalEvent("COMPANION_UNLEARNED", "MOUNT")
    flush(0)
    equal(journalCalls.list, listCalls + 1, "mount removal invalidates the catalog")
    equal(atlas.collection.byID[id], false, "mount removal refreshes ownership")
    equal(atlas.collection.collected, collected + 1, "mount removal reduces the collected total")
    equal(notifications, 3, "only visible changes notify consumers")

    sourceRevision = atlas.journalSourceRevision
    entries[newID].collected = false
    journalEvent("COMPANION_UNLEARNED", "MOUNT")
    flush(0)
    equal(atlas.mountByID(newID), nil, "an unowned placeholder is filtered again")
    equal(atlas.collection.total, total, "the removed placeholder reduces the catalog size")
    assert(atlas.journalSourceRevision > sourceRevision, "catalog removal invalidates source caches")

    local lateID = 990002
    add(lateID, 1, "Drop: Late journal record")
    entries[lateID].name, entries[lateID].collected = nil, nil
    atlas.syncJournal()
    equal(atlas.mountByID(lateID), nil, "missing journal identity is kept pending")
    listCalls, infoCalls = journalCalls.list, journalCalls.info
    entries[lateID].name = "Late journal record"
    journalEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
    flush(0)
    assert(atlas.mountByID(lateID), "the ready identity appears on the next search notification")
    equal(atlas.collection.byID[lateID], "unknown", "missing ownership is distinct from uncollected")
    entries[lateID].collected = false
    journalEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
    flush(0)
    equal(atlas.collection.byID[lateID], false, "confirmed uncollected ownership resolves the retry")
    equal(journalCalls.list, listCalls, "late data does not invalidate membership")
    equal(journalCalls.info, infoCalls + 2, "each retry samples just the pending ID")

    local requestedID = 990003
    infoCalls = journalCalls.info
    equal(atlas.resolveJournalMount(requestedID), nil, "a direct request can miss before its data is ready")
    journalEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
    equal(#timers, 0, "an unresolved external ID does not keep the event retry active")
    entries[requestedID] = { name = "Late requested mount", spell = requestedID, category = 1, source = "", collected = false }
    local requested = assert(atlas.resolveJournalMount(requestedID), "a later request can resolve an ID outside cached membership")
    equal(atlas.resolveJournalMount(requestedID), requested, "a resolved card can be opened from cache")
    equal(journalCalls.info, infoCalls + 2, "each uncached request reads just the requested ID")
    equal(journalCalls.list, listCalls, "direct lookup reuses cached membership")

    add(222, 1, "Drop: Invalid movement ability", atlas.nonCollectibleMounts[222])
    entries[222].collected = true
    add(2186, 12, nil, atlas.unreleasedMounts[2186])
    entries[2186].name = "Reviewed unreleased mount"
    extraCalls = journalCalls.extra
    atlas.syncJournal()
    equal(atlas.mountByID(222), nil, "ownership cannot turn a movement ability into a mount")
    equal(atlas.mountByID(2186), nil, "unreleased mount waits for a current source")
    equal(journalCalls.extra, extraCalls + 1, "only the source-dependent exclusion reads extra info")
    entries[2186].source = "Vendor: New source"
    atlas.ensureJournal()
    assert(atlas.mountByID(2186), "a live source can confirm an old unreleased entry")

    C_Timer, atlas.onJournalChanged = nil, nil
end
print("passed: journal caching, acquisition and availability updates, source filters, class alternatives and conditional rewards")
