local _, atlas = ...

-- Blizzard UiMap child/parent pairs, and the journal's named Ardenweald subzone.
atlas.sourceAddressParts = {
    { parent = "Остров Дорн", englishParent = "Isle of Dorn", child = "Дорногал", englishChild = "Dornogal",
        parentMap = 2248, childMap = 2339 },
    { parent = "Аз-Кахет", englishParent = "Azj-Kahet", child = "Город Нитей", englishChild = "City of Threads",
        parentMap = 2255, childMap = 2213 },
    { parent = "Расколотые острова", englishParent = "Broken Isles", child = "Даларан", englishChild = "Dalaran",
        parentMap = 619, childMap = 627 },
    { parent = "Арденвельд", englishParent = "Ardenweald", child = "Чащоба Туманной Завесы", englishChild = "Mistveil Tangle" },
}

-- https://www.wowhead.com/quest=92082/someone-like-me
-- https://www.wowhead.com/npc=245344/zoturu
atlas.questMountRewards[1482] = { spell = 353264,
    quests = { { id = 92082, name = "Родственные души", englishName = "Someone Like Me", item = 186639, givers = { 245344 },
        rewardItem = { item = 186639, name = "Техноглайдер попечителя картеля Зи", englishName = "Xy Trustee's Gearglider",
            icon = "Interface\\Icons\\inv_brokermount_light", quality = 4 },
    } },
    progressQuests = { 92080, 92079, 92081 }, -- Ba, Zo and Om dead drops
    journalDetail = { spell = 353264, kind = "Квест", replacesKind = "Добыча",
        replacesSource = { "Источник: [ДАННЫЕ ИЗЪЯТЫ]", "Source: [REDACTED]" },
        source = "Найди тайники трёх картелей в рейде „{journal:1302:Манагорн Омега}“, затем выполни задание"
            .. "\nЗадание: {quest:92082:Родственные души}",
        englishSource = "Find the three cartel dead drops in the {journal:1302:Manaforge Omega} raid, then complete the quest."
            .. "\nQuest: {quest:92082:Someone Like Me}",
    },
}
-- Both rewards are turned in to the same Zo'turu outside the raid.
atlas.questGiverWaypoints[92082] = atlas.questGiverWaypoints[91487]

-- One-time prerequisites of the exact reward quests, keyed by the final quest ID.
-- ATT Retail sourceQuests, bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2, and Wowhead quest series.
-- https://github.com/ATTWoWAddon/AllTheThings/tree/bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2/db/Standard/Categories
do
    local netherwing = { 10804, 10811, 10814, 10836, 10837, 10854, 10858, 10866, 10870,
        11012, 11013, 11014, 11053, 11084, 11092, 11107 }
    local cloudSerpent = { 30134, 30135, 30136, 30137, 30138, { 30139, 30140, 30141 }, 30142 }
    local dreadInfiltrators = { 46103 }
    local ghostlands = { 63519, 63522, 63487, 63488, 63489 }
    local progress = {
        [11109] = netherwing, [11110] = netherwing, [11111] = netherwing,
        [11112] = netherwing, [11113] = netherwing, [11114] = netherwing,
        [24915] = { 24545, 24743, 24547, 24749, 24756, 24757, 24548, 24549, 24914 },
        [25371] = { 25477 },
        -- The egg colours share the Pandaria intro, independently of reputation and flight training.
        [30188] = cloudSerpent, [31810] = cloudSerpent, [31811] = cloudSerpent,
        [31277] = { 31266 },
        [32399] = { 32412, 32413, 32398 },
        [32455] = { 32336, 32337, 32338, 32400, 32401 },
        -- The dedicated class mount sequences follow the class and Broken Shore campaigns.
        [45354] = { 45844, 45845, 45846, 45847 },
        [45372] = { 44719, 45417, 45420 },
        [45770] = { 46069, { 46070, 94847 }, 46071, { 46083, 91618 }, 46074 },
        [45789] = { 45788 },
        [46089] = dreadInfiltrators, [46178] = dreadInfiltrators,
        [46207] = { 46208 },
        [46243] = { 46237, { 46238, 94850 }, 46239, 46240, 46241, 46242 },
        [46334] = { 46333 },
        [46337] = { 46336 },
        [46350] = { 46353, 46341, 46342, 46343, 46344, 46346, 46347, 46348, 46349 },
        [46792] = { 46791 },
        [55622] = { 55608, 54086, 54929, 55373, 55697, 54922, 56168, 54083, 56175, 55696, 55753 },
        -- Chapter quests directly leading to each covenant reward.
        [58159] = { 61475, 61479, 58104, 58157, 58158 },
        [58181] = { 58176, 58177, 58179, 58180, 58178, 58182, 58183 },
        [58407] = { 60183, 57729, 57646, 58406 },
        [58440] = { 60673 },
        [59020] = { 61756, 61757, 61758, 61759, 61760, 61761, 62391, 58833 },
        [59555] = { 60268, 60269, 60270, 60271, 60272 },
        [60108] = { 60190, 60191, 60192, 60193, 60194 },
        [61697] = { 58937, 58938, 58939, 58857, 58995, 58997, 61135 },
        [63490] = ghostlands, [65653] = ghostlands,
        [65564] = { 63494, 63498, 63501, 63502, 65563 },
        -- https://github.com/Breeni/BtWQuestsDragonflight/tree/mainline
        [66027] = { 65844, 65845, 65846, 65848, 65847, 65849, 66210, 65850, 65911 },
        [66040] = { 66029, 66037, 66660, 66038, 66039 },
        [68795] = { 65998, 65999, 66000, 66001, 66114 },
        [70220] = { 66242, 66256, 66257, 66258, 66259, 66327, 70244, 66329, 66328, 66344 },
        [72512] = { 65901, 65907, 65770, 65761, 65711, 66676 },
        -- Otto's dance and barrel are recorded as hidden completion flags.
        [72738] = { 72676, 72808 },
        [73199] = { 73197, 73198 },
        [74563] = { 74538, 74539, 74540, 74542, 74557 },
        [75598] = { 74787 },
        [76318] = { 76317 },
        [76465] = { 76460, 76461, 77195, 76462, 77197, 76463, 77198, 76464 },
        [78189] = { { 78177, 78178 }, 78180, 78181, 78182, 78183, 78184, 78185, 78186, 78187, 78188 },
        [83722] = { 83627, 83719, 83720, 83721, 84246 },
        [84025] = { 84020, 84021, 84023, 84024 },
        [85213] = { 85155, 85184, 85185, 85186, 85196, 85212 },
        -- Each placed runekey is a distinct hidden flag. The Snapdragon feeding daily resets.
        [85811] = { 85799, 85800, 85801, 85802, 85803 },
        [86485] = { 86482, 86483, 86484 },
        [86902] = { 86842, 86843, 86844, 92136 },
        [88769] = { 88928, 88929, 88930, 88919, 88942 },
        [88976] = { 88974 },
        [90867] = { 90861, 90862 },
        [92899] = { 92895 },
    }
    for _, reward in pairs(atlas.questMountRewards) do
        local shared = progress[reward.quests[1].id]
        for _, quest in ipairs(reward.quests) do
            local steps = progress[quest.id]
            if steps then quest.progressQuests = steps end
            if steps ~= shared then shared = nil end
        end
        if shared then reward.progressQuests = shared end
    end
end


-- https://www.wowhead.com/quest=77677/some-water
-- The growth timers between these quests are not additional steps.
atlas.questMountRewards[1834].prerequisites = {
    { id = 77677, name = "Воды!..", englishName = "Some Water...", givers = { 209292 } },
    { id = 78398, name = "Порция минералов", englishName = "A Dash of Minerals..." },
    { id = 77697, name = "Правильное питание", englishName = "The Right Food..." },
    { id = 77711, name = "Щепотка магии", englishName = "And a Pinch of Magic" },
}
atlas.questGiverNames[209292] = { name = "Росток", englishName = "Sprout" }
atlas.questGiverWaypoints[77677] = { { map = 2200, x = .4868, y = .6790, npc = 209292 } }
-- https://www.wowhead.com/item=210774/reins-of-the-ochre-dreamtalon
atlas.questMountRewards[1834].quests[1].rewardItem = { item = 210774,
    name = "Поводья охряного ящера из Сна", englishName = "Reins of the Ochre Dreamtalon",
    icon = "Interface\\Icons\\inv_sabretoothraptormount_green", quality = 4 }

-- Retail covenant sanctum upgrade reward groups, checked against ATT
-- bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2 and Blizzard UiMap IDs.
atlas.covenantVariantSources = {
    [1376] = { spell = 312777, item = 181316, spirit = 178882, spiritName = "Дух гордыни",
        englishSpiritName = "Prideful Spirit", achievement = 14858, name = "Проклятие жажды",
        englishName = "Curse of Thirst" },
    [1392] = { spell = 334365, item = 180726, spirit = 177698, spiritName = "Неукрощенный дух",
        englishSpiritName = "Untamed Spirit", achievement = 14860, name = "Ничего лишнего", englishName = "Bare Necessities",
        chests = { { 356712, "Экстравагантные дары капитана-егеря Корейн", "Hunt-Captain Korayn's Extravagant Tribute" },
            { 356709, "Экстравагантные дары леди Лунной Ягоды", "Lady Moonberry's Extravagant Tribute" } } },
    [1408] = { spell = 336039, item = 181300, spirit = 178874, spiritName = "Воинственный дух",
        englishSpiritName = "Martial Spirit", achievement = 14853, name = "Все оттенки боли",
        englishName = "All The Colors of the Painbow",
        chests = { { 356697, "Экстравагантные дары Александроса Могрейна", "Alexandros Mograine's Extravagant Tribute" },
            { 356693, "Экстравагантные дары баронессы Вайш", "Baroness Vashj's Extravagant Tribute" } } },
    [1413] = { spell = 336064, item = 181317, spirit = 178881, spiritName = "Дух служения",
        englishSpiritName = "Dutiful Spirit",
        chests = { { 356728, "Экстравагантные дары Миканикоса", "Mikanikos' Extravagant Tribute" },
            { 356725, "Экстравагантные дары полемарха Адреста", "Polemarch Adrestes' Extravagant Tribute" } } },
}

atlas.covenantVariantVendors = {
    [1] = { npc = 171973, name = "Бинкира", englishName = "Binkiros", map = 1707, x = .316, y = .480, anima = 2500,
        place = "Элизийская цитадель", englishPlace = "Elysian Hold" },
    [2] = { npc = 164966, name = "Темель", englishName = "Temel", map = 1525, x = .280, y = .430, anima = 5000,
        place = "Ревендрет", englishPlace = "Revendreth",
        reputation = { id = 2445, name = "Пепельный двор", englishName = "The Ember Court" },
        alternate = { npc = 172531, map = 1699, x = .588, y = .800, place = "Грехопад", englishPlace = "Sinfall" } },
    [4] = { npc = 159238, name = "Аттикус", englishName = "Atticus", map = 1698, x = .488, y = .150, anima = 5000,
        place = "Престол Примаса", englishPlace = "Seat of the Primus",
        reputation = { id = 2462, name = "Штопальщики", englishName = "Stitchmasters" } },
}

-- These merchants sell the exact quest reward items. Choosing one free colour
-- in Shattrath or the Arboretum does not grant the other colours.
atlas.questRewardVendors = {
    { npc = 23489, name = "Продавец драконов Харлунк", englishName = "Drake Dealer Hurlunk",
        map = 104, x = .656, y = .859, place = "Долина Призрачной Луны", englishPlace = "Shadowmoon Valley",
        gold = 200, reputation = "Крылья Пустоты", englishReputation = "Netherwing",
        condition = "Получи одного дракона Пустоты в Шаттрате.",
        englishCondition = "Claim one Netherwing drake in Shattrath.",
        items = { [186] = 32857, [187] = 32858, [188] = 32859, [189] = 32860, [190] = 32861, [191] = 32862 },
        exclusiveColours = true },
    { npc = 58414, name = "Сань Рыжая Чешуя", englishName = "San Redscale",
        map = 371, x = .567, y = .443, place = "Нефритовый лес", englishPlace = "The Jade Forest",
        gold = 3000, reputation = "Орден Облачного Змея", englishReputation = "Order of the Cloud Serpent",
        items = { [448] = 79802, [464] = 85430, [465] = 85429 }, exclusiveColours = true },
    { npc = 10618, name = "Риверн Холодный Ветер", englishName = "Rivern Frostwind",
        map = 83, x = .466, y = .176, place = "Зимние Ключи", englishPlace = "Winterspring",
        gold = 100, reputation = "Укротители ледопардов", englishReputation = "Wintersaber Trainers",
        faction = "Alliance", items = { [55] = 13086 } },
}

-- ATT Standard Zones and WoWthing vendor snapshots at bab4c3d / befe8b4.
do
    local skitterflies = { [1615] = 192761, [1616] = 192762 }
    local ottuks = { [1653] = 201426, [1655] = 201425, [1657] = 198872, [1659] = 200118 }
    local vorquins = { [1683] = 201702, [1684] = 201704, [1685] = 201720, [1686] = 201719 }
    local skitterflyPrice = "5 {item:201401:Радужное перо} + 20 {item:193053:Контурное перо}"
        .. " + 750 |Hcurrency:2003|h[Припасы Драконьих островов]|h"
    local englishSkitterflyPrice = "5 {item:201401:Iridescent Plume} + 20 {item:193053:Contoured Fowlfeather}"
        .. " + 750 |Hcurrency:2003|h[Dragon Isles Supplies]|h"
    local ottukOffers = {}
    for id in pairs(ottuks) do
        local war = id == 1653 or id == 1655
        local parts, supplies = war and 5 or 2, war and 1000 or 750
        ottukOffers[id] = {
            renown = war and 30 or 25,
            price = ("%d {item:201403:Клык мастодонта} + %d {item:201400:Челюсти водного существа} + %d |Hcurrency:2003|h[Припасы Драконьих островов]|h"):format(parts, parts, supplies),
            englishPrice = ("%d {item:201403:Mastodon Tusk} + %d {item:201400:Aquatic Maw} + %d |Hcurrency:2003|h[Dragon Isles Supplies]|h"):format(parts, parts, supplies),
        }
    end
    local records = {
        { npc = 187408, name = "Дедушка Баки", englishName = "Granpap Whiskers",
            map = 2022, x = .476, y = .832, place = "Лагерь Драконьей экспедиции", englishPlace = "Dragonscale Basecamp",
            items = skitterflies, renown = 25, reputation = "Драконья экспедиция", englishReputation = "Dragonscale Expedition",
            price = skitterflyPrice, englishPrice = englishSkitterflyPrice },
        { npc = 189226, name = "Каталогизатор Джейкс", englishName = "Cataloger Jakes",
            map = 2022, x = .471, y = .826, place = "Лагерь Драконьей экспедиции", englishPlace = "Dragonscale Basecamp",
            items = skitterflies, renown = 25, reputation = "Драконья экспедиция", englishReputation = "Dragonscale Expedition",
            price = skitterflyPrice, englishPrice = englishSkitterflyPrice },
        { npc = 186462, name = "Татто", englishName = "Tatto",
            map = 2024, x = .132, y = .488, place = "Искара", englishPlace = "Iskaara",
            items = ottuks, offers = ottukOffers, reputation = "Искарские клыкарры", englishReputation = "Iskaara Tuskarr" },
        { npc = 193006, name = "Мурик", englishName = "Murik",
            map = 2024, x = .1316, y = .492, place = "Искара", englishPlace = "Iskaara",
            items = ottuks, offers = ottukOffers, reputation = "Искарские клыкарры", englishReputation = "Iskaara Tuskarr" },
        { npc = 200559, name = "Трейш", englishName = "Treysh",
            map = 2151, x = .356, y = .595, place = "Запретный край", englishPlace = "The Forbidden Reach",
            items = vorquins, gold = 40,
            alternate = { npc = 198429, map = 2118, x = .453, y = .613, condition = "Стартовая зона драктиров после задания «Без кавалерии никуда».",
                englishCondition = "Dracthyr starting zone after Cavalry Has Its Place." } },
        { npc = 196637, name = "Теталаш", englishName = "Tethalash",
            map = 2112, x = .256, y = .338, place = "Вальдраккен", englishPlace = "Valdrakken",
            items = vorquins, gold = 40 },
    }
    for _, record in ipairs(records) do atlas.questRewardVendors[#atlas.questRewardVendors + 1] = record end
end

-- Retail offers whose journal text omits the location or still names an old route.
atlas.reviewedVendorOffers = {
    -- https://www.wowhead.com/news/how-to-obtain-the-temperamental-skyclaw-secret-mount-in-dragonflight-330267
    -- https://raw.githubusercontent.com/ATTWoWAddon/AllTheThings/bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2/db/Standard/Categories/Zones.lua
    [1674] = { spell = 385738, item = 201454, npc = 190892, map = 2024, x = .190, y = .240,
        name = "Зон'воги", englishName = "Zon'Wogi", place = "Лазурный Простор", englishPlace = "The Azure Span",
        redemption = "barter", rewardIcon = "Interface\\Icons\\inv_foxwyvernmountred", itemCosts = {
            { item = 201422, amount = 20, name = "Быстрозамороженное мясо", englishName = "Flash Frozen Meat" },
            { item = 201420, amount = 20, name = "Фирменное блюдо Гнолана", englishName = "Gnolan's House Special" },
            { item = 201421, amount = 20, name = "Клыкаррские джерки", englishName = "Tuskarr Jerky" },
        },
        condition = "Собери по 20 штук каждого угощения и передай их Зон'воги. Угощения можно купить на аукционе",
        englishCondition = "Collect 20 of each treat and turn them in to Zon'Wogi. You can buy the treats at the Auction House.",
        native = { "Торговец: Зон'воги\nЗона: Лазурный Простор", "Vendor: Zon'Wogi\nZone: The Azure Span" } },
    -- Blizzard 24257260 and ATT Holidays: the event journal gives the token price without naming the vendors.
    [1941] = { spell = 427777, item = 210973, priceItem = 49927, amount = 270,
        currencyName = "Знак любви", englishCurrencyName = "Love Token",
        merchants = atlas.journalVendorCorrections[431].variants,
        condition = "Событие: Любовная лихорадка", englishCondition = "World Event: Love is in the Air",
        native = {
            "Событие: Любовная лихорадка\nЦена: 270 |Hitem:49927|h|TInterface\\ICONS\\INV_ValentinesCard01.BLP:0|t|h",
            "World Event: Love is in the Air\nCost: 270 |Hitem:49927|h|TInterface\\ICONS\\INV_ValentinesCard01.BLP:0|t|h",
        } },
    -- Blizzard 24201420; ATT Zones (Wrathion) and ExpansionFeatures (Torie). The vendors use separate currencies.
    [1321] = { spell = 316340, item = 174770, individualPrices = true, merchants = {
            { npc = 155496, name = "Гневион", englishName = "Wrathion", map = 1473, x = .462, y = .64,
                place = "Зал Сердца", englishPlace = "Chamber of Heart",
                currency = 1719, amount = 100000, currencyName = "Зараженные реликвии", englishCurrencyName = "Corrupted Mementos",
                condition = "Достижение: |Hachievement:14061|hМы знаем технологию|h",
                englishCondition = "Achievement: |Hachievement:14061|hWe Have the Technology|h" },
            { npc = 238138, name = "Тори", englishName = "Torie", map = 2339, x = .344, y = .684,
                place = "Дорногал", englishPlace = "Dornogal", currency = 3149, amount = 20000,
                currencyName = "Потерянные зараженные реликвии", englishCurrencyName = "Displaced Corrupted Mementos" },
        }, native = {
            "Торговец: Гневион\nЗона: Зал Сердца\nЦена: 100 000|Hcurrency:1719|h|TInterface\\ICONS\\Archaeology_5_0_MoguCoin.blp:0|t|h",
            "Vendor: Wrathion\nZone: Chamber of Heart\nCost: 100000|Hcurrency:1719|h|TInterface\\ICONS\\Archaeology_5_0_MoguCoin.blp:0|t|h",
        } },
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/0dd6b075fab29aacadc1fd80550577b3e30d1286/.contrib/.db/standard/02%20-%20Outdoor%20Zones/08%20Broken%20Isles/1%20-%20Dalaran/Vendors.lua#L1653-L1657
    [847] = { spell = 227956, item = 141713, npc = 107109, map = 627, x = .488, y = .135,
        name = "Ксур'иос", englishName = "Xur'ios", place = "Расколотые острова · Даларан", englishPlace = "Broken Isles · Dalaran",
        currency = 1275, amount = 150, currencyName = "Занятная монетка", englishCurrencyName = "Curious Coin",
        condition = "Ассортимент меняется ежедневно.", englishCondition = "Stock rotates daily.",
        native = { "Торговец: Ксур'иос", "Vendor: Xur'ios" } },
    -- https://www.wowhead.com/item=219391/delvers-dirigible
    -- https://warcraft.wiki.gg/wiki/Ship_It%21
    [2144] = { spell = 446052, item = 219391, npc = 226250, map = 2339, x = .476, y = .450, sinceInterface = 120001,
        name = "Рено Джексон", englishName = "Reno Jackson", place = "Остров Дорн · Дорногал", englishPlace = "Isle of Dorn · Dornogal",
        currency = 2815, amount = 10000, currencyName = "Кристаллы-резонаторы", englishCurrencyName = "Resonance Crystals",
        formerQuest = { id = 81510, name = "Прямо по адресу!", englishName = "Ship It!" },
        native = { 'Задание: "Прямо по адресу!"\nЗона: остров Дорн', "Quest: Ship It!\nZone: Isle of Dorn" } },
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/0dd6b075fab29aacadc1fd80550577b3e30d1286/.contrib/.db/standard/02%20-%20Delves/11%20-%20The%20War%20Within/Delves.lua#L2433-L2437
    [2296] = { spell = 466133, item = 229974, npc = 226250, map = 2339, x = .476, y = .450, sinceInterface = 120001,
        name = "Рено Джексон", englishName = "Reno Jackson", place = "Остров Дорн · Дорногал", englishPlace = "Isle of Dorn · Dornogal",
        currency = 2815, amount = 10000, currencyName = "Кристаллы-резонаторы", englishCurrencyName = "Resonance Crystals",
        formerQuest = { id = 85243, name = "Верните мне шляпу", englishName = "I Want My Hat Back" },
        native = { 'Локальное задание: "Верните мне шляпу"\nЗона: остров Дорн\nЗона: Дорногал',
            "World Quest: I Want My Hat Back\nZone: Isle of Dorn\nZone: Dornogal" } },
    -- https://worldofwarcraft.blizzard.com/en-us/news/24257262
    -- https://www.wowhead.com/item=238051/delvers-mana-skimmer
    [2512] = { spell = 1224048, item = 238051, npc = 226250, map = 2339, x = .476, y = .450, sinceInterface = 120001,
        name = "Рено Джексон", englishName = "Reno Jackson", place = "Остров Дорн · Дорногал", englishPlace = "Isle of Dorn · Dornogal",
        currency = 2815, amount = 10000, currencyName = "Кристаллы-резонаторы", englishCurrencyName = "Resonance Crystals",
        formerQuest = { id = 91782, name = "Изъято!", englishName = "Repossessed!" },
        native = { 'Задание: "Изъято!"\nЗона: остров Дорн', "Quest: Repossessed!\nZone: Isle of Dorn" } },
    -- https://worldofwarcraft.blizzard.com/en-us/news/24257262
    -- https://www.wowhead.com/item=246237/oc91-chariot
    [2604] = { spell = 1241263, item = 246237, npc = 226250, map = 2339, x = .476, y = .450, sinceInterface = 120001,
        name = "Рено Джексон", englishName = "Reno Jackson", place = "Остров Дорн · Дорногал", englishPlace = "Isle of Dorn · Dornogal",
        currency = 2815, amount = 10000, currencyName = "Кристаллы-резонаторы", englishCurrencyName = "Resonance Crystals",
        native = {
            "Торговец: сэр Финли Мрргглтон\nЗона: Дорногал\nЦена: 15 000|Hcurrency:2803|h|TInterface\\ICONS\\INV_Misc_ElvenCoins.blp:0|t|h",
            "Vendor: Sir Finley Mrrgglton\nZone: Dornogal\nCost: 15000|Hcurrency:2803|h|TInterface\\ICONS\\INV_Misc_ElvenCoins.blp:0|t|h",
        } },
    -- https://www.wowhead.com/ru/item=275660
    -- https://www.wowhead.com/npc=252956/construct-vanore
    [3032] = { spell = 1297408, item = 275660, npc = 252956, map = 2393, x = .557, y = .659,
        name = "голем В'аноре", englishName = "Construct V'anore", place = "Луносвет", englishPlace = "Silvermoon City",
        currency = 3392, amount = 2250, currencyName = "Отголосок страдания", englishCurrencyName = "Remnant of Anguish",
        condition = "Требуется 10-й уровень пути загонщика.", englishCondition = "Requires Preyhunter's Journey rank 10.",
        native = {
            "Торговец: голем В'аноре\nЗона: Луносвет\nЦена: 2250|Hcurrency:3392|h|TInterface\\ICONS\\INV_10_ElementalCombinedFoozles_Blood.BLP:0|t|h",
            "Vendor: Construct V'anore\nZone: Silvermoon City\nCost: 2250|Hcurrency:3392|h|TInterface\\ICONS\\INV_10_ElementalCombinedFoozles_Blood.BLP:0|t|h",
        } },
    -- The 12.1.7 PTR changes the price and removes the reputation requirement.
    -- https://www.wowhead.com/ru/npc=266188
    -- https://www.wowhead.com/ru/item=276926
    [3066] = { spell = 1301331, item = 276926, npc = 266188, map = 2393, x = .393, y = .8022,
        sinceInterface = 120105, untilInterface = 120107,
        name = "Эстелия Небесная Хранительница", englishName = "Estelia Archtender", place = "Луносвет", englishPlace = "Silvermoon City",
        currency = 3316, amount = 2500, currencyName = "Мракозарный мергель", englishCurrencyName = "Voidlight Marl",
        condition = "Репутация: Анклав акироведов (Превознесение)", englishCondition = "Reputation: Aqir Research Enclave (Exalted)",
        native = {
            "Торговец: Эстелия Небесная Хранительница\nЗона: Луносвет\nЦена: 2500|Hcurrency:3316|h|TInterface\\ICONS\\INV_112_RaidTrinkets_VoidPrism.BLP:0|t|h",
            "Vendor: Estelia Archtender\nZone: Silvermoon City\nCost: 2500|Hcurrency:3316|h|TInterface\\ICONS\\INV_112_RaidTrinkets_VoidPrism.BLP:0|t|h",
        } },
    -- https://us.forums.blizzard.com/en/wow/t/sporebearer-fungal-strider-mount-coming-in-1215/2344404/1
    -- https://www.wowhead.com/npc=274363/showena
    [3137] = { spell = 1313788, item = 282414, npc = 274363, map = 2576, x = .618, y = .6773,
        name = "Шоуэна", englishName = "Showena", place = "Харандар · Логово", englishPlace = "Harandar · The Den", gold = 5000000,
        condition = "Продаётся до окончания дополнения Midnight.", englishCondition = "Available to purchase until the end of Midnight.",
        native = {
            "Торговец: Шоуэна\nЗона: Харандар\nЦена: 5 000 000|TINTERFACE\\MONEYFRAME\\UI-GOLDICON.BLP:0|t",
            "Vendor: Showena\nZone: Harandar\nCost: 5,000,000|TINTERFACE\\MONEYFRAME\\UI-GOLDICON.BLP:0|t",
        } },
}

-- Retail item 258884: https://www.wowhead.com/ru/item=258884#sold-by
-- The journal can still describe its reward from the fifth Turbulent Timeways event.
do
    local weeks = {
        [98690] = "Wrath of the Lich King", [101759] = "Cataclysm", [118828] = "Mists of Pandaria",
        [151955] = "Warlords of Draenor", [151987] = "Warlords of Draenor", [255019] = "Dragonflight",
    }
    local merchants, waypointRoute = {}, { 1264184 }
    for index, row in ipairs(atlas.journalVendorWaypoints) do
        local npc = row[5][1][1]
        if weeks[npc] then
            merchants[#merchants + 1] = { npc = npc, name = row[1], englishName = row[2], place = row[3],
                englishPlace = row[4], timewalking = weeks[npc],
                faction = npc == 151955 and "Alliance" or npc == 151987 and "Horde" or nil }
            waypointRoute[#waypointRoute + 1] = index
        end
    end
    local badge = "|Hcurrency:1166|h|TInterface\\ICONS\\PVECurrency-Justice.blp:0|t|h"
    atlas.reviewedVendorOffers[2806] = { spell = 1264184, item = 258884, merchants = merchants, waypointRoute = waypointRoute,
        currency = 1166, amount = 5000, currencyName = "Искаженный временем знак", englishCurrencyName = "Timewarped Badge",
        formerAchievement = { id = 61463, name = "Укротитель бурных потоков времени V", englishName = "Master of the Turbulent Timeways V" },
        native = {
            'Достижение: "Укротитель бурных потоков времени V"\nКатегория: путешествия во времени',
            "Achievement: Master of the Turbulent Timeways V\nCategory: Timewalking",
            "Торговец: любой продавец товаров для путешественников во времени\nЦена: 5000" .. badge,
            "Vendor: Any Timewalking Vendor\nCost: 5000" .. badge,
        } }
end

-- https://www.wowhead.com/npc=46602/shay-pressler
-- https://www.wowhead.com/npc=46572/goram
-- https://www.wowhead.com/item=116666/blacksteel-battleboar
-- https://github.com/ATTWoWAddon/AllTheThings/blob/bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2/db/Standard/Categories/Character.lua#L7085-L7091
do
    local shay = { npc = 46602, map = 84, x = .642, y = .770, faction = "Alliance",
        name = "Шей Пресслер", englishName = "Shay Pressler", place = "Штормград", englishPlace = "Stormwind City" }
    local goram = { npc = 46572, map = 85, x = .482, y = .756, faction = "Horde",
        name = "Горам", englishName = "Goram", place = "Оргриммар", englishPlace = "Orgrimmar" }
    local guildVendors = { shay, goram }
    local coin = "|TINTERFACE\\MONEYFRAME\\UI-GOLDICON.BLP:0|t"
    local function guildOffer(id, spell, item, gold, merchants, native, achievement)
        atlas.reviewedVendorOffers[id] = { spell = spell, item = item, gold = gold, merchants = merchants,
            native = native, achievement = achievement,
            condition = "Репутация: Гильдия (Превознесение)", englishCondition = "Reputation: Guild (Exalted)" }
    end
    guildOffer(401, 88990, 63125, 3000, guildVendors, {
        "Торговец: гильдейский торговец\nЦена: 3000" .. coin,
        "Vendor: Guild Vendors\nCost: 3000" .. coin,
    }, { id = 4988, name = "Слава рейдеру Cataclysm (гильдия)", englishName = "Guild Glory of the Cataclysm Raider" })
    guildOffer(403, 90621, 62298, 1500, { shay }, {
        "Торговец: торговцы в игровых зонах\nЦена: 1500" .. coin,
        "Vendor: World Vendors\nCost: 1500" .. coin,
    })
    guildOffer(409, 93644, 67107, 1500, { goram }, {
        "Торговец: Горам\nЗона: Оргриммар\nЦена: 1500" .. coin,
        "Vendor: Goram\nZone: Orgrimmar\nCost: 1500" .. coin,
    })
    guildOffer(466, 124408, 85666, 3000, guildVendors, {
        "Торговец: Шей Пресслер (Альянс)\nЗона: Штормград\nЦена: 3000" .. coin .. "\n\n"
            .. "Торговец: Горам (Орда)\nЗона: Оргриммар\nЦена: 3000" .. coin,
        "Vendor: Shay Pressler (Alliance)\nZone: Stormwind City\nCost: 3000" .. coin .. "\n\n"
            .. "Vendor: Goram (Horde)\nZone: Orgrimmar\nCost: 3000" .. coin,
    }, { id = 6682, name = "Слава рейдеру Пандарии (гильдия)", englishName = "Guild Glory of the Pandaria Raider" })
    guildOffer(619, 171627, 116666, 4000, guildVendors, {
        'Достижение: "Слава рейдеру Дренора (гильдия)"',
        "Achievement: Guild Glory of the Draenor Raider",
    }, { id = 9669, name = "Слава рейдеру Дренора (гильдия)", englishName = "Guild Glory of the Draenor Raider" })
end

-- The Renown Quartermasters' current item listings:
-- https://www.wowhead.com/npc=174937/adjutant-galos
-- https://www.wowhead.com/npc=174710/chachi-the-artiste
-- https://www.wowhead.com/npc=174914/elwyn
-- https://www.wowhead.com/npc=172176/su-zettai
local covenantQuartermasters = {
    { npc = 174937, map = 1708, x = .6291, y = .3090, name = "Адъютант Галос", englishName = "Adjutant Galos",
        place = "Элизийская цитадель", englishPlace = "Elysian Hold", zone = "Бастион", englishZone = "Bastion" },
    { npc = 174710, map = 1699, x = .5368, y = .2490, name = "Чачи Артист", englishName = "Chachi the Artiste",
        place = "Грехопад", englishPlace = "Sinfall", zone = "Ревендрет", englishZone = "Revendreth" },
    { npc = 174914, map = 1701, x = .6014, y = .3597, name = "Элвина", englishName = "Elwyn", journalVendorName = "Элвин",
        place = "Сердце леса", englishPlace = "Heart of the Forest", zone = "Арденвельд", englishZone = "Ardenweald" },
    { npc = 172176, map = 1698, x = .5221, y = .4074, name = "Су Зеттай", englishName = "Su Zettai",
        place = "Престол Примаса", englishPlace = "Seat of the Primus", zone = "Малдраксус", englishZone = "Maldraxxus" },
}
local function covenantOffer(spell, item, covenant, renown, anima, offerings)
    local offer = { spell = spell, item = item, covenant = covenant, renown = renown, offerings = offerings,
        currency = 1813, amount = anima, currencyName = "Запасенная анима", englishCurrencyName = "Reservoir Anima" }
    for field, value in pairs(covenantQuartermasters[covenant]) do offer[field] = value end
    return offer
end
local function covenantRenownOffer(id, ...)
    atlas.reviewedVendorOffers[id] = covenantOffer(...)
end
covenantRenownOffer(1398, 334398, 180764, 1, 23, 5000)
covenantRenownOffer(1384, 332927, 183715, 2, 23, 5000)
covenantRenownOffer(1354, 332243, 180413, 3, 23, 5000)
covenantRenownOffer(1365, 332456, 182076, 4, 23, 5000)
covenantRenownOffer(1399, 334403, 180765, 1, 39, 100, 50)
covenantRenownOffer(1388, 333021, 182332, 2, 39, 100, 50)
covenantRenownOffer(1357, 332246, 180722, 3, 39, 100, 40)
covenantRenownOffer(1369, 332464, 181821, 4, 39, 100, 50)
covenantRenownOffer(1494, 353880, 186485, 1, 70, 7500)
covenantRenownOffer(1489, 353866, 186478, 2, 70, 7500)
covenantRenownOffer(1485, 353857, 186494, 3, 70, 7500)
covenantRenownOffer(1496, 353884, 186488, 4, 70, 7500)

-- These vendors sell the same reward items as the loot routes.
-- https://warcraft.wiki.gg/wiki/Chachi_the_Artiste
-- https://warcraft.wiki.gg/wiki/Elwyn
-- https://www.wowhead.com/item=181815/armored-bonehoof-tauralus
-- https://www.wowhead.com/item=180762/phalynx-of-humility
atlas.covenantPurchaseAlternatives = {
    [1310] = covenantOffer(332882, 180461, 2, 1, 5000, 100),
    [1370] = covenantOffer(332466, 181815, 4, 1, 5000, 100),
    [1393] = covenantOffer(334366, 180730, 3, 3, 5000, 75),
    [1395] = covenantOffer(334386, 180762, 1, nil, 5000, 100),
}

-- Retail item and merchant listings resolve these covenant-only journal entries.
-- https://www.wowhead.com/item=180415/winterborn-runestag
atlas.reviewedVendorOffers[1356] = { spell = 332245, item = 180415, covenant = 3,
    npc = 162447, map = 1565, x = .596, y = .529, name = "Веретенос", englishName = "Spindlenose",
    zone = "Арденвельд", englishZone = "Ardenweald", place = "Арденвельд", englishPlace = "Ardenweald",
    currency = 1813, amount = 5000, offerings = 5, currencyName = "Запасенная анима", englishCurrencyName = "Reservoir Anima",
    condition = "Репутация: Двор Ночи (Почтение)", englishCondition = "Reputation: Court of Night (Revered)" }

-- https://www.wowhead.com/item=180724/enchanted-winterborn-runestag
-- https://www.wowhead.com/quest=57583/through-the-veil
atlas.reviewedVendorOffers[1359] = { spell = 332248, item = 180724, covenant = 3,
    npc = 174766, map = 1819, x = .561, y = .513, name = "Паутинник", englishName = "Cortinarius",
    zone = "Арденвельд", englishZone = "Ardenweald", place = "Арденвельд · Кольцо", englishPlace = "Ardenweald · The Ring",
    currency = 1813, amount = 5000, currencyName = "Запасенная анима", englishCurrencyName = "Reservoir Anima",
    condition = "Репутация: Чесночник (Почтение)\nУсловие: выполнить {quest:57583:Сквозь завесу}.",
    englishCondition = "Reputation: Marasmius (Revered)\nRequirement: Complete {quest:57583:Through the Veil}." }

-- https://www.wowhead.com/item=182954/inquisition-gargon
atlas.reviewedVendorOffers[1382] = { spell = 332923, item = 182954, covenant = 2,
    zone = "Ревендрет", englishZone = "Revendreth", currency = 1816, amount = 2000,
    currencyName = "Фрагменты камня грехов", englishCurrencyName = "Sinstone Fragments",
    condition = "Репутация: Нераскаявшиеся (Превознесение)", englishCondition = "Reputation: The Avowed (Exalted)",
    merchants = {
        { npc = 173705, map = 1525, x = .730, y = .520, name = "Архивариус Джанира", englishName = "Archivist Janeera",
            place = "Ревендрет", englishPlace = "Revendreth" },
        { npc = 176368, map = 1670, x = .461, y = .777, name = "Архивариус Леонара", englishName = "Archivist Leonara",
            place = "Орибос", englishPlace = "Oribos" },
    } }

-- https://www.wowhead.com/npc=171973/binkiros
do
    local merchant = atlas.covenantVariantVendors[1]
    for _, mount in ipairs({
        { 1401, 334408, 180767, 14863, "Четыре лика одной личины", "Death Foursworn" },
        { 1402, 334409, 180768, 14861, "Учиться у мастеров", "Learning from the Masters" },
    }) do
        local id, spell, item, achievement, name, englishName = unpack(mount)
        local link = "|Hachievement:%d|h%s|h"
        atlas.reviewedVendorOffers[id] = { spell = spell, item = item, covenant = 1,
            npc = merchant.npc, map = merchant.map, x = merchant.x, y = merchant.y,
            name = merchant.name, englishName = merchant.englishName, place = merchant.place, englishPlace = merchant.englishPlace,
            zone = "Бастион", englishZone = "Bastion",
            currency = 1813, amount = merchant.anima, currencyName = "Запасенная анима", englishCurrencyName = "Reservoir Anima",
            condition = "Достижение: " .. link:format(achievement, name),
            englishCondition = "Achievement: " .. link:format(achievement, englishName) }
    end
end

-- The journal lists these purchases without their Renown requirements. Match
-- the teaching spell and the actual merchant so other routes keep their terms.
atlas.vendorRenownRequirements = {}
local function vendorRenown(faction, sellers, mounts)
    for id, mount in pairs(mounts) do
        atlas.vendorRenownRequirements[id] = { spell = mount[1], level = mount[2], faction = faction, sellers = sellers }
    end
end

local dreams = { id = 2574, name = "Стражи Сна", englishName = "Dream Wardens" }
local niffen = { id = 2564, name = "Лоаммские ниффы", englishName = "Loamm Niffen" }
-- https://www.wowhead.com/guide/reputation/dream-wardens-renown-rewards
vendorRenown(dreams, { "жрица луны Ласара", "Moon Priestess Lasara" }, {
    [1809] = { 423873, 17 }, [1811] = { 423891, 17 },
})
vendorRenown(dreams, { "Талиса Шелестоцвет", "Talisa Whisperbloom", "Сильвия Шелестоцвет", "Sylvia Whisperbloom" }, {
    [1808] = { 423871, 18 }, [1810] = { 423877, 18 }, [1816] = { 424479, 18 },
    [1817] = { 424482, 18 }, [1833] = { 426955, 18 }, [1835] = { 427043, 18 },
})
-- https://www.wowhead.com/guide/reputation/loamm-niffen-renown-rewards
-- https://www.wowhead.com/guide/zaralek-cavern
vendorRenown(niffen, { "Гарлоу Марл", "Harlowe Marl" }, { [1738] = { 408655, 18 } })
vendorRenown(niffen, { "Понзо", "Ponzo" }, { [1736] = { 408653, 3 } })

-- https://www.wowhead.com/guide/collections/the-war-within/mounts
vendorRenown({ id = 2590, name = "Совет Дорногала", englishName = "Council of Dornogal" },
    { "ревизор Балвурз", "Auditor Balwurz" }, { [2213] = { 449418, 18 }, [2148] = { 447057, 23 } })
vendorRenown({ id = 2570, name = "Арати Тайносводья", englishName = "Hallowfall Arathi" },
    { "Ауралия Стилстрайк", "Auralia Steelstrike" }, { [2193] = { 448978, 21 }, [2191] = { 448939, 23 } })
vendorRenown({ id = 2600, name = "Отрезанные нити", englishName = "The Severed Threads" },
    { "леди Виназиан", "Lady Vinazian", "И'теки", "Y'tekhi" },
    { [2184] = { 447957, 22 }, [2177] = { 447185, 23 } })
vendorRenown({ id = 2594, name = "Ассамблея глубин", englishName = "The Assembly of the Deeps" },
    { "воскоделец Пик-пик", "Waxmonger Squick" }, { [2209] = { 449269, 19 }, [2162] = { 447176, 23 } })
-- https://www.wowhead.com/guide/the-war-within/patch-11-1-cartels-of-undermine-renown-guide
vendorRenown({ id = 2653, name = "Картели Нижней Шахты", englishName = "The Cartels of Undermine" },
    { "Смакс Накипьсниммс", "Smaks Topskimmer" }, { [2277] = { 466002, 15 }, [2280] = { 466016, 19 } })
-- https://www.wowhead.com/npc=235621/ando-the-gat
vendorRenown({ id = 2685, name = "Клуб лояльности Галаджио", englishName = "Gallagio Loyalty Rewards Club" },
    { "Андо Пуля", "Ando the Gat" }, { [2276] = { 466000, 17 }, [2278] = { 466011, 20 }, [2279] = { 466012, 8 } })
-- https://www.wowhead.com/npc=235252/omsirik
vendorRenown({ id = 2658, name = "Концерн К'ареша", englishName = "The K'aresh Trust" },
    { "Ом'сирик", "Om'sirik" }, { [2556] = { 1233546, 15 }, [2510] = { 1223187, 19 } })
-- https://worldofwarcraft.blizzard.com/en-us/news/24198669
vendorRenown({ id = 2688, name = "Сияние Пламени", englishName = "Flame's Radiance" },
    { "Ларс Бронсмэльт", "Lars Bronsmaelt" }, { [2519] = { 1226421, 9 } })

-- https://www.wowhead.com/guide/collections/midnight-mounts-locations-appearances
vendorRenown({ id = 2710, name = "Двор Луносвета", englishName = "Silvermoon Court" },
    { "Церис Чистый Рассвет", "Caeris Fairdawn" }, { [2761] = { 1261322, 17 }, [2753] = { 1261291, 19 } })
vendorRenown({ id = 2696, name = "Племя Амани", englishName = "Amani Tribe" },
    { "Магову", "Magovu" }, { [2776] = { 1261357, 17 }, [2694] = { 1251630, 19 } })
-- https://www.wowhead.com/npc=240407/naynar
vendorRenown({ id = 2704, name = "Хара'ти", englishName = "Hara'ti" },
    { "Найнар", "Naynar" }, { [2614] = { 1243593, 16 }, [2710] = { 1253929, 19 } })
vendorRenown({ id = 2699, name = "Сингулярность", englishName = "The Singularity" },
    { "исследователь Бездны Аномандер", "Void Researcher Anomander" },
    { [2789] = { 1261579, 17 }, [2828] = { 1266702, 19 } })
-- https://www.wowhead.com/guide/midnight/zuljarras-forces-renown-reputation-farming-rewards
vendorRenown({ id = 2772, name = "Силы Зул'джарры", englishName = "Zul'jarra's Forces" },
    { "Джан'сари Внимательная", "Jan'sari the Watchful" }, { [3060] = { 1300778, 17 }, [3054] = { 1299963, 19 } })

-- These levels unlock the quests. The reward still comes from quest completion.
-- https://www.wowhead.com/quest=71196/to-tame-a-thunderspine
-- https://www.wowhead.com/quest=72512/a-whispering-breeze
local maruuk = { id = 2503, name = "Кентавры Маруук", englishName = "Maruuk Centaur" }
atlas.questRenownRequirements = {
    [1545] = { spell = 395644, level = 25, faction = maruuk, quest = { "Шепот ветра", "A Whispering Breeze" } },
    [1639] = { spell = 374247, level = 9, faction = maruuk,
        quest = { "Приручение громоспина", "To Tame a Thunderspine", "Дитя равнин", "Beast of the Plains" } },
}

-- https://github.com/ATTWoWAddon/AllTheThings/blob/bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2/.contrib/.db/standard/06%20-%20Expansion%20Features/07%20-%20Legion/Legion%20Class%20Halls/Sanctum%20Of%20Light%20%28Paladin%29.lua#L963-L978
-- https://nether.wowhead.com/tooltip/npc/99976?dataEnv=1&locale=0 (area 139 floor 20 is the order hall, UiMap 24).
for id, reward in pairs({ [892] = { 231587, 143503 }, [893] = { 231588, 143504 }, [894] = { 231589, 143505 } }) do
    atlas.reviewedVendorOffers[id] = {
        spell = reward[1], item = reward[2], npc = 99976, map = 24, x = .514, y = .740,
        name = "Командир рыцарей Далфорс", englishName = "Crusader Lord Dalfors",
        place = "Обитель Света", englishPlace = "Sanctum of Light",
        currency = 1220, amount = 1000, currencyName = "Ресурсы оплота класса", englishCurrencyName = "Order Resources",
        condition = "Условие: выполнить {quest:45770:Волнение во тьме}.",
        englishCondition = "Requirement: Complete {quest:45770:Stirring in the Shadows}.",
        native = { "Торговец: командир рыцарей Далфорс\nЗона: Обитель Света",
            "Vendor: Crusader Lord Dalfors\nZone: Sanctum of Light" },
    }
end

-- Retail Brawler's Guild offer identities and separate faction maps (ATT).
-- https://github.com/ATTWoWAddon/AllTheThings/blob/bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2/.contrib/.db/standard/07%20-%20Events/Brawler%27s%20Guild/Brawler%27s%20Guild.lua#L1571-L1607
-- https://github.com/ATTWoWAddon/AllTheThings/blob/bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2/.contrib/.db/standard/07%20-%20Events/Brawler%27s%20Guild/Brawler%27s%20Guild.lua#L1730-L1766
local brawlerQuartermasters = {
    { npc = 68363, map = 500, x = .543, y = .252, faction = "Alliance",
        name = "Квакенбуш", englishName = "Quackenbush", place = 'Потасовочная "У Бизмо"', englishPlace = "Bizmo's Brawlpub" },
    { npc = 68364, map = 503, x = .508, y = .294, faction = "Horde",
        name = "Пол Норт", englishName = "Paul North", place = 'Арена "Морд\'Бой"', englishPlace = "Brawl'gar Arena" },
}
local function brawlerOffer(spell, item, rank, gold, nativeRussianPrice)
    local coin = "|TInterface/MONEYFRAME/UI-GoldIcon.blp:0|t"
    return { spell = spell, item = item, gold = gold, merchants = brawlerQuartermasters,
        condition = ("Фракция: Бойцовская гильдия (%d-й ранг)"):format(rank),
        englishCondition = ("Faction: Brawler's Guild (Rank %d)"):format(rank),
        native = {
            'Торговец: Улаани\nЗона: потасовочная "У Бизмо"\n\nТорговец: Тиана Безрассветная\nЗона: арена "Морд\'Бой"\n\n'
                .. ("Фракция: бойцовская гильдия (%d-й ранг)\nЦена: %s%s"):format(rank, nativeRussianPrice, coin),
            "Vendor: Ulaani\nZone: Bizmo's Brawlpub\n\nVendor: Tiana Nevermorn\nZone: Brawl'gar Arena\n\n"
                .. ("Faction: Brawler's Guild (Rank %d)\nCost: %d%s"):format(rank, gold, coin),
        },
    }
end
atlas.reviewedVendorOffers[2807] = brawlerOffer(1264621, 259227, 6, 4000, "4000")
atlas.reviewedVendorOffers[2808] = brawlerOffer(1264643, 259238, 8, 10000, "10 000")

-- The hidden unlock quest is distinct from the seven visible quests.
-- https://www.wowhead.com/quest=61839/nipping-at-the-undergrowth
-- https://www.wowhead.com/quest=62046/a-new-pack
atlas.questAcquisitionChains = {
    -- https://www.wowhead.com/quest=64530/gravewing-crystal
    [803] = { spell = 215545, npc = 179985, starter = 187283, firstQuest = 64530,
        finalQuest = 64530, reward = 186479, guaranteedReward = true, name = "Кристалл танатокрыла", englishName = "Gravewing Crystal",
        rewardName = "Танатокрыл искусной работы", englishRewardName = "Mastercraft Gravewing",
        condition = "Вентирам нужно добыть кристалл у стигийского камнедробителя и выполнить задание.",
        englishCondition = "As Venthyr, obtain the crystal from Stygian Stonecrusher and complete the quest." },
    [1391] = { spell = 333027, npc = 160821, starter = 180583, unlock = 61188, firstQuest = 61839,
        finalQuest = 62046, reward = 182589, guaranteedReward = true, name = "Новая стая", englishName = "A New Pack",
        quests = { 61839, 61840, 61842, 61844, 62044, 62045, 62046 },
        rewardName = "Верный пожиратель", englishRewardName = "Loyal Gorger" },
    -- https://www.wowhead.com/quest=64528/wilderling-saddle
    [1487] = { spell = 353859, npc = 180014, toastItem = 187278, starter = 187281, firstQuest = 64528,
        finalQuest = 64528, reward = 186492, guaranteedReward = true, name = "Седло чащобника", englishName = "Wilderling Saddle",
        rewardName = "Упряжь летнего чащобника", englishRewardName = "Summer Wilderling Harness",
        condition = "Ночному народцу нужно получить седло после укрощения беглого чащобника и выполнить задание.",
        englishCondition = "As Night Fae, obtain the saddle after taming the Escaped Wilderling and complete the quest." },
    -- https://www.wowhead.com/quest=64529/intact-aquilon-core
    [1493] = { spell = 353877, npc = 180032, starter = 187282, firstQuest = 64529,
        finalQuest = 64529, reward = 186483, guaranteedReward = true, name = "Невредимый сердечник аквилона", englishName = "Intact Aquilon Core",
        rewardName = "Аквилон раскольников", englishRewardName = "Forsworn Aquilon" },
    -- The five identically named quests precede the single reward in 71209.
    -- https://www.wowhead.com/quest=71196/to-tame-a-thunderspine
    -- https://www.wowhead.com/quest=71209/beast-of-the-plains
    [1639] = { spell = 374247, npc = 190014, firstQuest = 71196, finalQuest = 71209,
        reward = 192799, guaranteedReward = true, name = "Дитя равнин", englishName = "Beast of the Plains",
        quests = { 71196, 71197, 71198, 71199, 71195, 71209 },
        stageTitle = { name = "Приручение громоспина", englishName = "To Tame a Thunderspine" },
        prerequisite = { id = 66676, name = "Скрытное проникновение", englishName = "Sneaking In",
            group = "Выходной посвященной", englishGroup = "Initiate's Day Out" },
        rewardName = "Поводья Яши", englishRewardName = "Lizi's Reins" },
}
-- The journal captions and creature names differ for these exact NPCs.
-- https://www.wowhead.com/ru/npc=95054
-- https://www.wowhead.com/ru/npc=157466
atlas.journalNPCSourceNames = { [95054] = "Воздаяние", [157466] = "Ан-дэ Верный" }

-- The two feeds mark the same four Tanaan champions at slightly different coordinates.
-- https://github.com/ThingEngineering/wowthing-data/blob/befe8b4a548a8ba94b9100609b1c155154b1d2db/zone-maps/05-warlords-of-draenor/tanaan_jungle.yml
atlas.sourceWaypointAliases = { [534] = {
    [95044] = { x = .146, y = .630, alternateX = .150, alternateY = .630 },
    [95053] = { x = .232, y = .404, alternateX = .230, alternateY = .402 },
    [95054] = { x = .326, y = .738, alternateX = .324, alternateY = .738 },
    [95056] = { x = .470, y = .526, alternateX = .468, alternateY = .526 },
} }

-- A single map pin does not represent these acquisition routes.
atlas.mountSourcesWithoutWaypoints = {
    [656] = 171850,   -- quest starts with the invitation
    [1395] = 334386,  -- treasure route starts with the Anima Conductor
    [1441] = 344577,  -- multi-step puzzle throughout the Maw
    [1948] = 428068,  -- parts from two visions and final assembly
    [2561] = 1233561, -- quest reward cache
    [2749] = 1260356, -- shards drop throughout Harandar
}

atlas.questRouteGuides = {
    -- https://warcraft.wiki.gg/wiki/Torn_Invitation
    -- https://www.wowhead.com/quest=44057/a-noble-event
    [656] = { spell = 171850,
        starter = {
            text = "Может выпасть из финального сундука „Строевой подготовки иссохших“, награды посланника Помраченных или тайника за репутацию сверх превознесения",
            englishText = "Can drop from the final Withered Army Training chest, the Nightfallen emissary reward, or their Paragon reputation cache",
        },
        quest = {
            text = "Выполни четыре задания соратников в оплоте класса, затем спаси Волпина в Сурамаре",
            englishText = "Complete four follower missions in your class hall, then rescue Volpin in Suramar",
        },
    },
    -- https://warcraft-secrets.com/guides/bound-shadehound
    [1441] = { spell = 344577,
        text = "Получи благодарность Ве’нари, разгадай руны у Алтаря Господства и собери страницы кодекса. Скуй оболочку для гончей, соедини её с душой волка у алтаря и укроти гончую рунами",
        englishText = "Reach Appreciative with Ve’nari, solve the runes at the Altar of Domination, and collect the codex pages. Forge the shadehound’s husk, bind it to a wolf soul at the altar, and tame the shadehound with runes",
    },
    -- https://warcraft-secrets.com/guides/voidfire-deathcycle
    -- https://worldofwarcraft.blizzard.com/en-us/news/24244442
    [1948] = { spell = 428068,
        text = "В обновлённом видении Штормграда с активной маской победи Хеймара и отправь каркас в Дорногал. Собери детали в видениях обоих городов и установи их на каркас вместе с покупными или изготовленными материалами",
        englishText = "Enter the Revisited Vision of Stormwind with a mask active, defeat Haymar, and send the frame to Dornogal. Collect parts in both cities’ Visions and fit them onto the frame using purchased or crafted materials",
    },
}

-- Direct grants whose native journal fields name the activity but do not
-- identify how the mount is awarded. Keep existing prices and prerequisites.
atlas.directMountGrants = {
    -- https://www.wowhead.com/quest=12687/into-the-realm-of-shadows
    [221] = { spell = 48778, kind = "Класс", key = "quest",
        source = { "Trainer: Death Knight", "Класс: рыцарь смерти" },
        text = "В начальной цепочке рыцаря смерти выполни задание {quest:12687:Путь в Долину Теней}.",
        englishText = "Complete {quest:12687:Into the Realm of Shadows} in the death knight starting experience.",
        alternative = { key = "progress",
            text = "Рыцари смерти из союзных рас и пандарены автоматически получают скакуна при первом входе.",
            englishText = "Allied race and pandaren death knights receive the mount on their first login." } },
    -- Mission 615 awards item 116769 upon success.
    -- https://www.wowhead.com/mission=615/its-a-boat-its-a-plane-its-just-a-riverbeast
    [631] = { spell = 171826, kind = "Квест", key = "quest", source = {
        "Задание гарнизона: Это корабль... нет, самолет... Нет, это просто речное чудище.",
        "Garrison Mission: It's a Boat, It's a Plane, It's... Just a Riverbeast.",
    },
        text = "Задание гарнизона: {mission:615:Это корабль... нет, самолет... Нет, это просто речное чудище.}\nУспешно заверши задание на верфи",
        englishText = "Garrison Mission: {mission:615:It's a Boat, It's a Plane, It's... Just a Riverbeast.}\nSuccessfully complete the mission at the Shipyard" },
    -- https://www.wowhead.com/mission=679/breaker-two
    [762] = { spell = 189364, kind = "Квест", key = "quest", source = {
        "Задание гарнизона: Разрушительная пара", "Garrison Mission: Breaker Two",
    },
        text = "Задание гарнизона: {mission:679:Разрушительная пара}",
        englishText = "Garrison Mission: {mission:679:Breaker Two}" },
    -- https://www.wowhead.com/quest=40378/enter-the-illidari-ashtongue
    [780] = { spell = 200175, kind = "Класс", key = "quest",
        source = { "Класс: охотник на демонов", "Class: Demon Hunter" },
        text = "Во время задания {quest:40378:Сбор иллидари: Пеплоусты} в начальной цепочке охотника на демонов прими дар Иллидана и взаимодействуй с саблезубом Скверны.",
        englishText = "Accept Illidan's gift and interact with the Felsaber during {quest:40378:Enter the Illidari: Ashtongue} in the demon hunter starting experience." },
    -- https://warcraft.wiki.gg/wiki/Renown_(Shadowlands)#Necrolord
    -- https://worldofwarcraft.blizzard.com/en-gb/news/23691032/new-covenant-mounts-coming-in-chains-of-domination
    [1484] = { spell = 353856, kind = "Добыча", key = "progress", subtype = "Известность", covenant = 3, renown = 45 },
    [1490] = { spell = 353872, kind = "Добыча", key = "progress", subtype = "Известность", covenant = 2, renown = 45 },
    [1492] = { spell = 353875, kind = "Добыча", key = "progress", subtype = "Известность", covenant = 1, renown = 45 },
    [1495] = { spell = 353883, kind = "Добыча", key = "progress", subtype = "Известность", covenant = 4, renown = 45 },
    -- https://worldofwarcraft.blizzard.com/en-us/news/24294369/
    [2821] = { spell = 1266211, kind = "Достижение", key = "pvp", subtype = "Арена", seasonal = true,
        source = { 'Достижение: "Гладиатор: 2-й сезон Midnight"\nКатегория: PvP',
            'Achievement: "Gladiator: Midnight Season 2"\nCategory: PvP',
            'Achievement: "Gladiator: Midnight Season 2"\nCategory: Player vs. Player',
            'Achievement: Gladiator: Midnight Season 2\nCategory: Player vs. Player' } },
    -- https://news.blizzard.com/en-us/article/24316983/last-call-to-pre-purchase-craft-new-adventures-with-d-d-world-of-warcraft
    [3133] = { spell = 1311627, kind = "Акция", key = "promotion", state = "unknown",
        source = { "Промоакция", "Promotion" },
        text = "Код входит в печатные специздания D&D: World of Warcraft. Тираж ограничен.\nДля активации нужны учётная запись Blizzard, лицензия WoW и активная подписка.\nПредзаказ на D&D Beyond завершился 17 ноября 2026 года.",
        englishText = "The code comes with limited-run D&D: World of Warcraft print special editions.\nTo redeem it, you need a Blizzard account, a WoW license and an active subscription.\nThe D&D Beyond preorder ended on November 17, 2026." },
}

for _, id in ipairs({ 1357, 1369, 1388, 1399 }) do
    local offer = atlas.reviewedVendorOffers[id]
    atlas.directMountGrants[id] = { spell = offer.spell, kind = "Торговец", key = "progress", subtype = "Известность",
        covenant = offer.covenant, renown = offer.renown, alternate = true }
end

-- https://www.warcraftmounts.com/class.php
local function classLevelGrant(spells, source, text, englishText)
    for id, spell in pairs(spells) do
        atlas.directMountGrants[id] = { spell = spell, kind = "Класс", key = "progress",
            source = source, text = text, englishText = englishText }
    end
end
classLevelGrant({
    [41] = 13819, [84] = 23214, [149] = 34767, [150] = 34769, [350] = 69820, [351] = 69826,
    [367] = 73629, [368] = 73630, [1046] = 270562, [1047] = 270564, [1225] = 290608,
    [1568] = 363613, [2233] = 453785,
}, { "Паладин", "Paladin", "Старинное", "Legacy", "Задание.", "Quest" },
    "Открывается при повышении уровня паладина подходящей расы.",
    "Unlocked by leveling a paladin of the appropriate race.")
classLevelGrant({ [17] = 5784, [83] = 23161 }, { "Класс: чернокнижник", "Class: Warlock" },
    "Открывается при повышении уровня чернокнижника.", "Unlocked by leveling a warlock.")

-- The exact journal amount and seller delimit each missing price link.
do
    local function offer(spell, name, englishName, legacyPrice, price)
        return { spell = spell, name = name, englishName = englishName, legacyPrice = legacyPrice, price = price }
    end
    local function iconPrice(amount, resource, texture)
        return ("%d|H%s|h|TInterface\\ICONS\\%s:0|t|h"):format(amount, resource, texture)
    end
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/bab4c3ddab11ddec2143d3c589b29c51c9e0c4a2/.contrib/.db/standard/08%20-%20PvP/Battlegrounds/Alterac%20Valley.lua
    local function honorOffer(spell, faction, name, englishName)
        return offer(spell, name, englishName, "2000|tinterface\\pvpframe\\pvpcurrency-honor-" .. faction .. ".blp:0|t",
            iconPrice(15, "item:137642", "Ability_PVP_GladiatorMedallion.BLP"))
    end
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/f2c9335ec4eeafc87c83d0e525ad84f6c4d5491f/.contrib/.db/standard/08%20-%20PvP/Mounts.lua
    local function saddleOffer(spell, alliance)
        return offer(spell, alliance and "некролорд Сайп" or "страж смерти Нетариан",
            alliance and "Necrolord Sipe" or "Deathguard Netharian",
            "1|tinterface\\icons\\achievement_bg_kill_on_mount.blp:0|t",
            iconPrice(1, "item:103533", "ACHIEVEMENT_BG_KILL_ON_MOUNT.BLP"))
    end
    local function marlOffer(spell, name, englishName, amount)
        return offer(spell, name, englishName, tostring(amount),
            iconPrice(amount, "currency:3316", "INV_112_RaidTrinkets_VoidPrism.BLP"))
    end
    atlas.reviewedMerchantPrices = {
        [108] = honorOffer(23509, "horde", "Джорек Железнобок", "Jorek Ironside"),
        [109] = honorOffer(23510, "alliance", "Тантальдис Снегоблеск", "Thanthaldis Snowgleam"),
        -- https://worldofwarcraft.blizzard.com/en-us/news/9135375
        -- https://www.wowhead.com/item=44791/noblegarden-chocolate
        [430] = offer(102349, "торговец Сада чудес", "Noblegarden Merchant",
            "500|tinterface\\icons\\achievement_noblegarden_chocolate_egg.blp:0|t",
            iconPrice(500, "item:44791", "ACHIEVEMENT_NOBLEGARDEN_CHOCOLATE_EGG.BLP")),
        [755] = saddleOffer(183889, true),
        [844] = saddleOffer(223578, true),
        [873] = saddleOffer(229487, true),
        [876] = saddleOffer(229512, true),
        [900] = saddleOffer(232523, true),
        [901] = saddleOffer(232525, false),
        [945] = saddleOffer(242896, true),
        [1027] = saddleOffer(261433, true),
        [1045] = saddleOffer(270560, false),
        [1050] = saddleOffer(272481, true),
        [1196] = saddleOffer(281890, false),
        [1197] = saddleOffer(281889, false),
        -- Blizzard 12.1.5.70688 Mount.db2 includes the currency ID on all four prices.
        -- https://worldofwarcraft.blizzard.com/en-us/news/24244461
        [2915] = marlOffer(1271698, "сержант Ворнин", "Sergeant Vornin", 6000),
        [2988] = marlOffer(1294648, "Кифаан", "Kifaan", 15),
        [2990] = marlOffer(1294663, "Кифаан", "Kifaan", 15),
        [3033] = marlOffer(1297427, "Кифаан", "Kifaan", 15),
    }

    local function sellerPrice(name, englishName, price)
        return { name = name, englishName = englishName, price = price }
    end
    local function missingPrice(spell, name, englishName, price, native)
        return { spell = spell, native = native or { "Торговец: " .. name, "Vendor: " .. englishName },
            prices = { sellerPrice(name, englishName, price) } }
    end
    local function missingZonePrice(spell, name, englishName, price, zone, englishZone)
        return missingPrice(spell, name, englishName, price, {
            "Торговец: " .. name .. "\nЗона: " .. zone,
            "Vendor: " .. englishName .. "\nZone: " .. englishZone,
        })
    end
    local function goldPrice(amount)
        return amount .. "|TInterface\\MoneyFrame\\UI-GoldIcon.blp:0|t"
    end
    local orderResources = iconPrice(1000, "currency:1220", "INV_OrderHall_OrderResources")
    local anima = iconPrice(5000, "currency:1813", "Spell_AnimaBastion_Orb.BLP")
    -- 2,000 gold with the required Exalted standing at each quartermaster.
    -- https://www.wowhead.com/guide/vanity-collections/warlords-of-draenor-mount-collectors-guide
    local felboarGold = goldPrice(2000)
    local denjai = sellerPrice("темный охотник Дэнжай", "Shadow Hunter Denjai", felboarGold)
    local krethos = sellerPrice("воздаятель Кретос", "Vindicator Krethos", felboarGold)
    -- Exact Blizzard Mount.db2 12.1.5 source blocks with no Cost field.
    atlas.reviewedMissingMerchantPrices = {
        -- https://www.wowhead.com/currency=391/tol-barad-commendation
        [394] = missingPrice(88741, "интендант Брейзи", "Quartermaster Brazie",
            iconPrice(200, "currency:391", "Achievement_Zone_TolBarad.blp"), {
                "Торговец: интендант Брейзи\nЗона: полуостров Тол Барад\nФракция: защитники Тол Барада – превознесение",
                "Vendor: Quartermaster Brazie\nZone: Tol Barad Peninsula\nFaction: Baradin's Wardens - Exalted",
            }),
        -- https://www.wowhead.com/item=87774/reins-of-the-heavenly-golden-cloud-serpent
        [475] = missingPrice(127164, "ткач туманов Ку", "Mistweaver Ku", iconPrice(100000, "currency:777", "TimelessCoin"), {
            "Торговец: ткач туманов Ку\nЗона: Вневременный остров\nФракция: император Шаохао - превознесение",
            "Vendor: Mistweaver Ku\nZone: Timeless Isle\nFaction: Emperor Shaohao - Exalted",
        }),
        -- https://www.wowhead.com/guide/legion-mounts
        [663] = missingPrice(213115, "безумный торговец", "The Mad Merchant", goldPrice(2000000)),
        [768] = { spell = 190977, prices = { denjai, krethos }, native = {
            "Торговец: темный охотник Дэнжай\nЗона: Танаанские джунгли\nФракция: Охотники за головами - превознесение"
                .. "\n\nТорговец: воздаятель Кретос\nЗона: Танаанские джунгли\nФракция: Длань Пророка - превознесение",
            "Vendor: Shadow Hunter Denjai\nZone: Tanaan Jungle\nFaction: Vol'jin's Headhunters - Exalted"
                .. "\n\nVendor: Vindicator Krethos\nZone: Tanaan Jungle\nFaction: Hand of the Prophet - Exalted",
        } },
        -- https://www.wowhead.com/item=142398/darkwater-skate
        [855] = missingZonePrice(228919, "Галисса Солнечная Роса", "Galissa Sundew",
            iconPrice(500, "item:124669", "INV_Misc_Fish_51"), "остров Новолуния", "Darkmoon Island"),
        -- https://www.wowhead.com/npc=100661/pan-the-kind-hand
        [870] = missingZonePrice(229438, "Пань Добрые Руки", "Pan the Kind Hand", orderResources, "Приют Стрелка", "Trueshot Lodge"),
        [872] = missingZonePrice(229439, "Пань Добрые Руки", "Pan the Kind Hand", orderResources, "Приют Стрелка", "Trueshot Lodge"),
        -- https://www.wowhead.com/spell=231434/shadowblades-murderous-omen
        [889] = missingZonePrice(231523, "Зан Кругореззик", "Zan Shivsproket", orderResources, "Даларан", "Dalaran"),
        [890] = missingZonePrice(231524, "Зан Кругореззик", "Zan Shivsproket", orderResources, "Даларан", "Dalaran"),
        [891] = missingZonePrice(231525, "Зан Кругореззик", "Zan Shivsproket", orderResources, "Даларан", "Dalaran"),
        -- https://www.wowhead.com/item=143637/hellblazing-reins-of-the-brimstone-wrathsteed
        [930] = missingZonePrice(238452, "Калид", "Calydus", orderResources, "разлом Зловещего Шрама", "Dreadscar Rift"),
        -- https://www.wowhead.com/currency=1813/reservoir-anima
        -- https://www.wowhead.com/guide/grateful-offering-anima-conductor-currency-shadowlands
        [1420] = missingZonePrice(340503, "Веретенос", "Spindlenose",
            anima .. " + " .. iconPrice(5, "currency:1885", "INV_Misc_OrnateBox"), "Арденвельд", "Ardenweald"),
        [1429] = missingZonePrice(342667, "Паутинник", "Cortinarius", anima, "Арденвельд", "Ardenweald"),
        -- https://www.wowhead.com/item=232901/lunar-launcher
        [2327] = missingPrice(472253, "Лунный фестиваль", "Lunar Festival",
            iconPrice(75, "item:21100", "INV_Misc_ElvenCoins"), { "Продавец: Лунный фестиваль", "Vendor: Lunar Festival" }),
        -- https://www.wowhead.com/item=233058/soweezis-vintage-waveshredder
        [2333] = missingPrice(473137, "Спокс", "Soweezi", iconPrice(10000, "currency:3090", "INV_Siren_Isle_FlameBlessed_Iron"),
            { "Зона: остров Сирен\nПродавец: Спокс", "Zone: Siren Isle\nVendor: Soweezi" }),
        -- https://www.wowhead.com/guide/collections/the-war-within/mounts
        [2519] = missingZonePrice(1226421, "Ларс Бронсмэльт", "Lars Bronsmaelt",
            iconPrice(8125, "currency:2815", "Spell_Azerite_Essence14.BLP"), "Тайносводье", "Hallowfall"),
        -- https://www.wowhead.com/currency=3546/coiled-filament
        [3019] = missingZonePrice(1297216, "вторая помощница Склизз", "Second Mate Sluggs",
            iconPrice(2500, "currency:3546", "INV_12_Profession_QuestandCrafting_SparkShard_Green"), "Спиральный остров", "The Coiled Isle"),
    }
end

-- Vicious Saddle merchant stock, matched to the Retail teaching spells.
-- https://github.com/ATTWoWAddon/AllTheThings/blob/f2c9335ec4eeafc87c83d0e525ad84f6c4d5491f/.contrib/.db/standard/08%20-%20PvP/Mounts.lua#L5-L167
local saddleMerchants = {
    Alliance = { npc = 73190, map = 84, x = .768, y = .656, name = "Некролорд Сайп", englishName = "Necrolord Sipe",
        place = "Штормград", englishPlace = "Stormwind City" },
    Horde = { npc = 73151, map = 85, x = .418, y = .730, name = "Страж смерти Нетариан", englishName = "Deathguard Netharian",
        place = "Оргриммар", englishPlace = "Orgrimmar" },
}
atlas.saddlePurchases = {}
local function saddlePurchase(expansion, season, alliance, horde)
    for faction, reward in pairs({ Alliance = alliance, Horde = horde }) do
        atlas.saddlePurchases[reward[1]] = {
            spell = reward[2], item = reward[3], faction = faction,
            merchant = saddleMerchants[faction], expansion = expansion, season = season,
        }
    end
end
saddlePurchase("Shadowlands", 1, { 1351, 327407, 184014 }, { 1352, 327408, 184013 })
saddlePurchase("Shadowlands", 2, { 1460, 348770, 186178 }, { 1459, 348769, 186179 })
saddlePurchase("Shadowlands", 3, { 1452, 347256, 187681 }, { 1451, 347255, 187680 })
saddlePurchase("Shadowlands", 4, { 1465, 349824, 187644 }, { 1466, 349823, 187642 })
saddlePurchase("Dragonflight", 1, { 1688, 394737, 201789 }, { 1689, 394738, 201788 })
saddlePurchase("Dragonflight", 2, { 1740, 409034, 205246 }, { 1741, 409032, 205245 })
saddlePurchase("Dragonflight", 3, { 1819, 424534, 210070 }, { 1820, 424535, 210069 })
saddlePurchase("Dragonflight", 4, { 2056, 434470, 213439 }, { 2057, 434477, 213440 })
saddlePurchase("The War Within", 1, { 2211, 449325, 223511 }, { 2150, 447405, 221813 })
saddlePurchase("The War Within", 2, { 2300, 466146, 229989 }, { 2299, 466145, 229988 })
saddlePurchase("The War Within", 3, { 2570, 1234820, 243157 }, { 2571, 1234821, 243159 })
saddlePurchase(nil, nil, { 422, 100332, 70909 }, { 423, 100333, 70910 })

-- Repeatable quest steps needed for acquisition, not the final reward quest
-- or the NPC's loot lockout. Unlisted mounts have unknown frequency.
-- Sources: https://www.warcraftmounts.com/mounts/<slug>.php
atlas.questFrequencies = {
    [55] = "daily",    -- winterspringfrostsaber
    [311] = "daily",   -- venomhideravasaur
    [1329] = "daily",  -- springfuralpaca
    [1391] = "daily",  -- loyalgorger
    [2561] = "weekly", -- curiousslateback (quest reward cache)
}

local function stablesTraining(spell, allianceFirst, allianceLast, hordeFirst, hordeLast)
    local function training(first, last)
        local quests = {}
        for id = first, last do quests[#quests + 1] = id end
        return { quests = quests, finalQuest = last }
    end
    return { spell = spell, variants = {
        Alliance = training(allianceFirst, allianceLast), Horde = training(hordeFirst, hordeLast),
    } }
end

atlas.periodicQuestChains = {
    -- These daily rewards accumulate as quest items until the final turn-in.
    -- https://www.wowhead.com/quest=29034/they-grow-up-so-fast
    -- https://www.wowhead.com/quest=13906/they-grow-up-so-fast
    [55] = { spell = 17229, faction = "Alliance", finalQuest = 29034, item = 68644, required = 20 },
    [311] = { spell = 64659, faction = "Horde", finalQuest = 13906, item = 47196, required = 20 },
    -- The taming quest precedes the daily training sequence.
    -- https://www.wowhead.com/guide/garrisons/buildings/guide-to-the-garrison-stables
    [609] = stablesTraining(171617, 36983, 36994, 37048, 37059),
    [615] = stablesTraining(171623, 37015, 37021, 37063, 37069),
    [628] = stablesTraining(171637, 36995, 37004, 37032, 37041),
    [629] = stablesTraining(171638, 37005, 37013, 37071, 37079),
    [637] = stablesTraining(171831, 36971, 36982, 37093, 37104),
    [647] = stablesTraining(171841, 37022, 37028, 37105, 37111),
    -- Each falcosaur has one visit to the player's faction capital.
    -- https://www.wowhead.com/guide/falcosaur-obtaining-falcosaur-mounts-pets-toys-4788
    [793] = { spell = 213158, finalQuest = 45020, quests = {
        44990, { 44991, 44993 }, 44996, 44998, 45000, 45002, 45004, 45006, 45008, 45010, 45012, 45014, 45016, 45018, 45020,
    } },
    [794] = { spell = 213164, finalQuest = 44988, quests = {
        44973, { 44974, 44975 }, 44976, 44977, 44978, 44979, 44980, 44981, 44982, 44983, 44984, 44985, 44986, 44987, 44988,
    } },
    [795] = { spell = 213163, finalQuest = 44969, quests = {
        44948, { 44949, 44971 }, 44950, 44953, 44954, 44956, 44957, 44958, 44959, 44960, 44961, 44962, 44967, 44968, 44969,
    } },
    [796] = { spell = 213165, finalQuest = 45019, quests = {
        44989, { 44992, 44994 }, 44995, 44997, 44999, 45001, 45003, 45005, 45007, 45009, 45011, 45013, 45015, 45017, 45019,
    } },
    -- Persistent quest checkpoints from achievements 13030 and 13542.
    -- https://www.wowhead.com/guide/raising-kuafon-your-loyal-pterrordax-companion-6122
    -- https://www.wowhead.com/item=168408/child-of-torcali
    [1043] = { spell = 267270, faction = "Horde", finalQuest = 50944, quests = { 52305, 52447, 52748, 50944 } },
    [1249] = { spell = 297560, faction = "Horde", finalQuest = 55798, quests = { 47310, 52857, 55258, 55507, 55798 } },
    -- Milestones are the three completed growth phases.
    -- https://www.wowhead.com/guide/shadowbarb-drone-mount-pet-toy
    [1320] = { spell = 316339, finalQuest = 58866, quests = { 58810, 58829, 58863 } },
    -- The hidden objective records all feedings; the visible daily flag resets.
    -- https://www.wowhead.com/item=174859/reins-of-the-springfur-alpaca
    [1329] = { spell = 316802, finalQuest = 58887, objectiveQuest = 58881, required = 7 },
    [1391] = { spell = 333027, chain = true },
    -- Each offering has a persistent flag and the daily lockout has a separate flag.
    -- https://www.wowhead.com/npc=173468/dead-blanchy
    [1414] = { spell = 339588, npc = 173468, finalQuest = 62050, quests = { 62038, 62042, 62047, 62048, 62049, 62050 } },
    -- Six sightings can be credited on separate days when Maelie is present.
    -- https://www.wowhead.com/npc=179912/maelie-the-wanderer
    [1511] = { spell = 354362, finalQuest = 64292, quests = { 64293, 64294, 64295, 64296, 64297, 64299 } },
    -- The seven feedings precede the reward quest.
    -- https://www.wowhead.com/quest=65732/the-patient-bufonid
    [1569] = { spell = 363701, finalQuest = 65732, quests = { 65727, 65725, 65726, 65728, 65729, 65730, 65731 } },
    [1639] = { spell = 374247, chain = true },
    -- The checkpoints are the last quests in each of the four daily batches.
    -- https://www.wowhead.com/quest=90769/a-blue-for-you
    [2560] = { spell = 1233559, finalQuest = 90769, quests = { 90663, 90729, 90773, 90769 } },
    -- Use the one-time quests, whose names are reused by the post-reward dailies.
    -- https://worldofwarcraft.blizzard.com/en-gb/news/24293963
    -- https://www.wowhead.com/quest=96305/the-innocent-essence
    [2980] = { spell = 1292668, finalQuest = 96305, quests = { 96267, 96276, 96273, 96275, 96271, 96305 } },
}
for mountID in pairs(atlas.periodicQuestChains) do atlas.questFrequencies[mountID] = "daily" end

-- Reviewed acquisition types and details for incomplete journal entries.
local shopSource = { "Внутриигровой магазин", "In-Game Shop" }
-- https://worldofwarcraft.blizzard.com/en-us/news/24242435
local outlandPacks = {
    native = { "Событие: Burning Crusade Classic", "Промоакция: Burning Crusade Classic", "Promotion: Burning Crusade Classic" },
    source = "Входит в героический и эпический комплекты Запределья.",
    englishSource = "Included in the Outland Heroic Pack and the Outland Epic Pack.",
}
-- https://worldofwarcraft.blizzard.com/en-us/news/24177508
local pandariaPacks = {
    native = { "Промоакция: Mists of Pandaria Classic", "Promotion: Mists of Pandaria Classic" },
    source = "Входит в «Зараженный ша героический комплект» и «Зараженный ша эпический комплект».",
    englishSource = "Included in the Sha-Infused Heroic Pack and the Sha-Infused Epic Pack.",
}
local function classicPackReward(spell, packs)
    return { spell = spell, replacesKind = "Акция", alternateKind = "Событие", kind = "Магазин",
        replacesSource = packs.native, source = packs.source, englishSource = packs.englishSource }
end
local alteracAchievement = {
    'Достижение: "И все дружно до Альтерака..."\nКатегория: Альтеракская долина',
    'Достижение: "А вот раньше на Альтераке..."\nКатегория: Альтеракская долина',
    "Achievement: Alterac Valley of Olde\nCategory: Alterac Valley",
}
local korrakSource = "Задание: Месть Коррака\nЗона: Альтеракская долина\nТребуется: заработать 200 искаженных временем знаков на поле боя."
local function sourceRequirement(spell, detail, replacesSource)
    local reward = detail.reward
    local function rewardToken(name) return ("{item:%d:%s}"):format(reward.item, name) end
    return { spell = spell, replacesKind = detail.replacesKind or "Исследование", kind = detail.kind or "Исследование",
        requirements = detail, replacesSource = replacesSource or { "Зона: " .. detail.place, "Zone: " .. detail.englishPlace },
        source = "Зона: " .. detail.place .. "\nТребуется: " .. detail.condition .. "\nНаграда: " .. rewardToken(reward.name),
        englishSource = "Zone: " .. detail.englishPlace .. "\nRequires: " .. detail.englishCondition
            .. "\nReward: " .. rewardToken(reward.englishName),
    }
end
local covenantQuestRegions = {
    kyrian = { "кирии", "Kyrian", "Бастион", "Bastion" },
    venthyr = { "вентиры", "Venthyr", "Ревендрет", "Revendreth" },
    nightFae = { "ночной народец", "Night Fae", "Арденвельд", "Ardenweald" },
    necrolord = { "некролорды", "Necrolord", "Малдраксус", "Maldraxxus" },
}
local function covenantQuestReward(spell, item, quest, title, englishTitle, covenant, renown, originalKind)
    local name, englishName, place, englishPlace = unpack(covenantQuestRegions[covenant])
    local russian = "Ковенант: " .. name .. "\nЗона: " .. place
    local english = "Covenant: " .. englishName .. "\nZone: " .. englishPlace
    local russianRequirement = renown and ("\nИзвестность: " .. renown) or ""
    local englishRequirement = renown and ("\nRenown: " .. renown) or ""
    return { spell = spell, item = item, quests = { quest }, kind = "Квест",
        replacesKind = originalKind or "Добыча", replacesSource = { russian, english },
        source = "Задание: " .. title .. "\n" .. russian .. russianRequirement,
        englishSource = "Quest: " .. englishTitle .. "\n" .. english .. englishRequirement }
end

-- https://www.wowhead.com/item=94295/primal-egg
local function primalEggSource(spell)
    local russian = "Источник: треснутое древнее яйцо"
    local english = "Drop: Cracked Primal Egg"
    return { spell = spell, kind = "Добыча", replacesKind = "Добыча", replacesSource = { russian, english },
        source = russian .. "\nЗона: Остров Великанов\n{item:94295:Древнее яйцо} можно добыть с динозавров острова. Оно созревает за три дня.",
        englishSource = english .. "\nZone: Isle of Giants\nDinosaurs on the island can drop the {item:94295:Primal Egg}. It takes three days to hatch." }
end

-- https://www.wowhead.com/guide/garrisons/garrison-invasions
-- The faction quests award the gold bag. Gold's weekly loot flag is shared by the two quest IDs.
local invasionGoldQuests = {
    Alliance = { id = 37307, weeklyFlag = 37640, name = "Золотая победа", englishName = "Gold Victory" },
    Horde = { id = 35788, weeklyFlag = 37640, name = "Золотая победа", englishName = "Gold Victory" },
}
local function invasionSpoils(spell)
    return { spell = spell, kind = "Добыча", replacesKind = "Добыча",
        replacesSource = { "Источник: забытые припасы налетчика", "Drop: Invader's Forgotten Treasure" },
        weeklyRewardQuests = invasionGoldQuests,
        source = "Золото — {item:116980:Забытые припасы налетчика}"
            .. "\nПлатина — {item:122163:Сундук трофеев поверженного завоевателя}",
        englishSource = "Gold — {item:116980:Invader's Forgotten Treasure}"
            .. "\nPlatinum — {item:122163:Routed Invader's Crate of Spoils}",
    }
end

atlas.journalSourceDetails = {
    [616] = invasionSpoils(171624),
    [626] = invasionSpoils(171635),
    [642] = invasionSpoils(171836),
    [649] = invasionSpoils(171843),
    [221] = { spell = 48778, replacesKind = "Торговец", kind = "Класс",
        replacesSource = { "Trainer: Death Knight" } },
    -- https://www.wowhead.com/spell=73630/summon-great-exarchs-elekk
    [368] = { spell = 73630, replacesKind = "Квест", kind = "Класс",
        source = "Классовый транспорт паладина-дренея." },
    [538] = primalEggSource(138641),
    [539] = primalEggSource(138642),
    [540] = primalEggSource(138643),
    -- https://www.wowhead.com/guide/reins-of-the-long-forgotten-hippogryph-mount
    [802] = sourceRequirement(215159, {
        name = "Эфемерный кристалл", englishName = "Ephemeral Crystal", place = "Азсуна", englishPlace = "Azsuna",
        respawn = { min = 120, max = 480, condition = "Время до появления следующего набора из пяти кристаллов." },
        condition = "Первым активируй пять разных эфемерных кристаллов за восемь часов с момента первого и не погибни.",
        englishCondition = "Be the first to activate five different Ephemeral Crystals within eight hours of the first without dying.",
        guarantee = { condition = "Поводья получает тот, кто первым активирует пять кристаллов в срок и не погибнет.",
            englishCondition = "The reins go to the first player who activates five crystals in time without dying." },
        reward = { item = 138258, name = "Поводья давно брошенного гиппогрифа", englishName = "Reins of the Long-Forgotten Hippogryph" },
    }),
    -- Nazjatar's two faction paragon caches, linked to item 169198 by Rarity CE.
    -- https://www.warcraftmounts.com/mounts/royalsnapdragon.php
    [1237] = { spell = 294038, kind = "Добыча", replacesKind = "Добыча",
        replacesSource = { "Источник: припасы анкоа\nИсточник: припасы Освобожденных",
            "Drop: Ankoan Supplies\nDrop: Unshackled Supplies" },
        source = "Альянс\nИсточник: припасы анкоа\nЗона: Назжатар\n\nОрда\nИсточник: припасы Освобожденных\nЗона: Назжатар",
        englishSource = "Alliance\nDrop: Ankoan Supplies\nZone: Nazjatar\n\nHorde\nDrop: Unshackled Supplies\nZone: Nazjatar" },
    -- Blizzard 23873404 corrected the mount reward to the battleground bonus objective.
    -- https://www.wowhead.com/quest=63953/korraks-revenge
    [1285] = { spell = 306421, quests = { 63953 }, replacesKind = "Достижение", kind = "Квест",
        replacesSource = alteracAchievement, source = korrakSource },
    [1292] = { spell = 308250, quests = { 63953 }, replacesKind = "Достижение", kind = "Квест",
        replacesSource = alteracAchievement, source = korrakSource },
    -- Campaign chapter gates: https://www.wowhead.com/guide/renown-shadowlands-covenant-progression-rewards
    -- Final quest of Venthyr chapter 9: https://www.wowhead.com/quest=58407/the-medallion-of-dominion
    [1299] = covenantQuestReward(312754, 180948, 58407, "Медальон Господства", "The Medallion of Dominion", "venthyr", 22),
    -- https://www.wowhead.com/quest=58159/whats-my-motivation
    [1302] = covenantQuestReward(312759, 180263, 58159, "Что мною движет?", "What's My Motivation?", "nightFae"),
    -- https://www.wowhead.com/quest=60108/drust-and-ashes
    [1303] = covenantQuestReward(312761, 180721, 60108, "Друсты и пепел", "Drust and Ashes", "nightFae", 22),
    -- https://www.wowhead.com/news/visions-of-nzoth-mount-preview-elusive-quickhoof-302589
    [1324] = sourceRequirement(316493, {
        npc = 162681, name = "Неуловимый быстроног", englishName = "Elusive Quickhoof", place = "Вол'дун", englishPlace = "Vol'dun",
        condition = "Купить {item:161128:Салат из приморской зелени} у торговца едой и покормить Неуловимого быстронога.",
        englishCondition = "Buy {item:161128:Seaside Leafy Greens Mix} from a food vendor and feed the Elusive Quickhoof.",
        guarantee = { condition = "Ты получишь поводья, когда найдёшь Неуловимого быстронога и покормишь его, используя {item:161128:Салат из приморской зелени}.",
            englishCondition = "You receive the reins when you find the Elusive Quickhoof and feed it {item:161128:Seaside Leafy Greens Mix}." },
        reward = { item = 174860, name = "Поводья неуловимого быстронога", englishName = "Reins of the Elusive Quickhoof" },
    }),
    -- Necrolord chapter 3: https://www.wowhead.com/guide/necrolords-covenant-campaign-story-rewards
    [1364] = covenantQuestReward(332455, 182077, 59555, "Враг на пороге", "Enemy at the Door", "necrolord", 5),
    -- https://www.wowhead.com/quest=59020/the-third-fall-of-kelthuzad
    [1368] = covenantQuestReward(332462, 181822, 59020, "Третье падение Кел'Тузада", "The Third Fall of Kel'Thuzad", "necrolord", 22),
    -- Venthyr chapter 5: https://www.wowhead.com/guide/venthyr-covenant-campaign-story-rewards
    [1385] = covenantQuestReward(332932, 180945, 58440, "Зеркало, зеркало на стене...", "Mirror, Mirror...", "venthyr", 11, "Квест"),
    -- https://www.wowhead.com/object=356818/penitence-of-purity
    [1395] = { spell = 334386, kind = "Добыча", replacesKind = "Добыча", alternateKind = "Журнал",
        replacesSource = { "Ковенант: кирии\nЗона: Бастион", "Covenant: Kyrian\nZone: Bastion" },
        source = "Сокровище: Покаяние Чистоты\nЗона: Бастион\nКовенант: кирии",
        englishSource = "Treasure: Penitence of Purity\nZone: Bastion\nCovenant: Kyrian" },
    -- Kyrian chapters 4 and 7: https://www.wowhead.com/guide/kyrian-covenant-campaign-story-rewards
    [1396] = covenantQuestReward(334391, 180763, 58181, "Прочный фундамент", "Building the Base", "kyrian", 8),
    -- https://www.wowhead.com/quest=61697/a-new-age
    [1400] = covenantQuestReward(334406, 180766, 61697, "Новая эпоха", "A New Age", "kyrian", 17),
    -- https://www.wowhead.com/npc=173468/dead-blanchy
    -- https://www.wowhead.com/item=182614/blanchys-reins
    [1414] = sourceRequirement(339588, {
        kind = "Взаимодействие", replacesKind = "Добыча", npc = 173468,
        name = "Мертвая Савраска", englishName = "Dead Blanchy", place = "Ревендрет", englishPlace = "Revendreth",
        condition = "Сделай шесть подношений Мёртвой Савраске, по одному в день. Для последнего принеси {item:179271:Яблоко Жуткой Лощины} ×3. Дни могут идти с перерывами.",
        englishCondition = "Make six offerings to Dead Blanchy, one per day. Bring {item:179271:Dredhollow Apple} ×3 for the final offering. The days do not have to be consecutive.",
        guarantee = { condition = "Савраска отдаст поводья за {item:179271:Яблоко Жуткой Лощины} ×3 после пяти предыдущих ежедневных подношений.",
            englishCondition = "Blanchy gives you the reins for {item:179271:Dredhollow Apple} ×3 after the first five daily offerings." },
        reward = { item = 182614, name = "Поводья Савраски", englishName = "Blanchy's Reins" },
    }, { "NPC: мертвая Савраска\nЗона: Ревендрет", "NPC: Dead Blanchy\nZone: Revendreth" }),
    -- https://news.blizzard.com/en-us/article/23891317/dragonflight-mounts-pets-and-more-await-in-the-dragon-isles
    [1469] = sourceRequirement(350219, {
        kind = "Взаимодействие", replacesKind = "Добыча", npc = 199010,
        name = "Усиленная улитка", englishName = "Empowered Snail", place = "Берега Пробуждения", englishPlace = "The Waking Shores",
        condition = "Добудь {item:201883:Пустой магмовый панцирь} и принеси его улитке в лаве.",
        englishCondition = "Obtain an {item:201883:Empty Magma Shell} and bring it to the snail in the lava.",
        guarantee = { condition = "Панцирь может выпасть с лавового глотателя. Заверши взаимодействие с усиленной улиткой, чтобы получить маунта.",
            englishCondition = "A Lavaslurper can drop the shell. Complete the interaction with the Empowered Snail to receive the mount." },
        reward = { item = 192777, name = "Магмапанцирь", englishName = "Magmashell" },
    }, { "Предмет: пустой магмовый панцирь\nЗона: Берега Пробуждения", "Item: Empty Magma Shell\nZone: The Waking Shores" }),
    -- Alternate final rewards: quest63490 for paladins, quest65653 for other classes.
    -- https://worldofwarcraft.blizzard.com/en-gb/news/23801631
    [1600] = { spell = 370620, quests = { 63490, 65653 }, replacesKind = "Квест", kind = "Квест", replacesSource = {
        'Задание: "Рыцарь крови"\nЗона: Призрачные земли\n\nЗадание: "Слава син\'дорай"\nЗона: Призрачные земли',
        "Quest: Blood Knight\nZone: Ghostlands\n\nQuest: Victory for the Sin'dorei\nZone: Ghostlands",
        'Quest: "Blood Knight"\nZone: Ghostlands\n\nQuest: "Victory for the Sin\'dorei"\nZone: Ghostlands',
    }, source = "Задание: Рыцарь крови — для паладинов\nЗона: Призрачные земли\n\nЗадание: Слава син’дорай — для остальных классов\nЗона: Призрачные земли" },
    -- The journal names the start of Lizi's chain; quest 71209 gives the mount.
    -- https://www.wowhead.com/quest=71196/to-tame-a-thunderspine
    [1639] = { spell = 374247, quests = { 71196 }, replacesSource = {
        'Задание: "Приручение громоспина"\nЗона: равнины Он\'ары',
        "Quest: To Tame A Thunderspine\nZone: Ohn'ahran Plains",
    } },
    -- https://worldofwarcraft.blizzard.com/en-gb/recruit-a-friend
    [1698] = { spell = 400733, replacesKind = "Магазин", kind = "Акция",
        replacesSource = { "Пригласи друга", "Recruit-a-Friend", "Внутриигровой магазин", "In-Game Shop" },
        source = "Пригласи друга" },
    -- https://warcraft-secrets.com/guides/naxxramas-ancient-secrets
    [1774] = { spell = 413922, kind = "Добыча", replacesKind = "Добыча",
        replacesSource = { "Открытие: Отвага\nЗона: Наксрамас", "Discovery: Valiance\nLocation: Naxxramas" },
        source = "Зона: Наксрамас\nОткрой тайны Наксрамаса и войди в рейд на 10 игроков."
            .. "\nКупи у Закетта {item:208068:Гнилая вкуснятина} за 30 × {item:206576:Жетон сделки со смертью} и предложи её Отваге."
            .. "\nКристаллом повиновения возьми под контроль ученика и подведи его к коню."
            .. "\nВернись верхом к Разувию, отпусти ученика и победи обоих. Забери поводья у Разувия.",
        englishSource = "Zone: Naxxramas\nUnlock the secrets of Naxxramas and enter the 10-player raid."
            .. "\nBuy a {item:208068:Rotten Delicious} from Zackett for 30 × {item:206576:Death's Bargaining Chip} and offer it to Valiance."
            .. "\nUse an Obedience Crystal to control a Death Knight Understudy and lead it to the horse."
            .. "\nRide back to Razuvious, release the understudy and defeat them both. Loot the reins from Razuvious." },
    -- https://shop.battle.net/product/world-of-warcraft-mount-runebound-firelord
    [1812] = { spell = 424009, replacesKind = "Акция", kind = "Магазин",
        replacesSource = { "Промоакция: Cataclysm Classic", "Promotion: Cataclysm Classic" },
        source = "Продаётся отдельно в магазине Battle.net.", englishSource = "Sold separately in the Battle.net Shop." },
    -- ATT: item211089 is awarded after attaching parts to the frame (quest90136).
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/b2d15612a1319d450ffe844ee6b9ef708aa9d2c9/.contrib/.db/standard/06%20-%20Expansion%20Features/11%20-%20The%20War%20Within/Revisited%20Horrific%20Visions.lua
    -- https://news.blizzard.com/en-us/article/24179881/the-making-of-ratts-revenge-deciphering-incognitro-the-indecipherable-felcycle
    -- https://www.wowhead.com/guide/secrets/ratts-revenge-incognitro-felcycle-guide
    [1943] = { spell = 428013, replacesKind = "Событие", kind = "Исследование",
        replacesSource = { "Событие: 20-я годовщина World of Warcraft?", "World Event: WoW's 20th Anniversary?" },
        source = "Головоломки «Месть Раттс»\nВыбери звание «Детектив» и поговори с Уцелевшей жительницей Даларана в Дорногале, чтобы начать «Поиски Раттс». После девятой головоломки забери {item:229348:Ключи от Инкогнитро, непостижимого скверноцикла} из сундука.",
        englishSource = "Ratts' Revenge puzzles\nUse the Detective title and speak to the Dalaran Survivor in Dornogal to start Ratts' Race. After the ninth puzzle, collect {item:229348:Keys to Incognitro, the Indecipherable Felcycle} from the chest." },
    [1948] = { spell = 428068, replacesKind = "Торговец", kind = "Квест", replacesSource = {
        "Зона: видение Штормграда (возвращение)\nЗона: видение Оргриммара (возвращение)",
        "Zone: Vision of Stormwind (Revisited)\nZone: Vision of Orgrimmar (Revisited)",
    } },
    -- Blizzard 24295383 confirms the Trading Post route, without a current offer.
    [1958] = { spell = 431360, replacesKind = "Журнал", kind = "Торговая лавка", replacesSource = { "" },
        source = "Предмет: |cffffd200|Hitem:212229|h[Поводья сумеречного небесного хищника]|h|r" },
    -- ATT: five runekeys lead to quest85811 and item232639.
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/b2d15612a1319d450ffe844ee6b9ef708aa9d2c9/.contrib/.db/standard/02%20-%20Outdoor%20Zones/15%20Khaz%20Algar/Siren%20Isle/Seafury%20Tempest%20(Storm).lua
    [2322] = { spell = 471562, replacesKind = "Журнал", kind = "Квест",
        replacesSource = { "Зона: остров Сирен", "Zone: Siren Isle" },
        source = "Во время шторма используй пять разных рунных ключей в Забытом хранилище острова Сирен, затем заверши задание Трайира.\nПредмет: |cffffd200|Hitem:232639|h[Трайир Очи Сирены]|h|r" },
    [2476] = classicPackReward(1216422, pandariaPacks),
    [2477] = classicPackReward(1216430, pandariaPacks),
    [2719] = classicPackReward(1255246, outlandPacks),
    [2732] = classicPackReward(1256677, outlandPacks),
    -- https://www.wowhead.com/news/how-to-obtain-the-echo-of-alnsharan-mount-in-midnight-380704
    [2749] = { spell = 1260356, quests = { 90467 }, replacesKind = "Добыча", kind = "Квест",
        source = "Квест: «Легенды о небе»\nМесто: Харандар" },
    -- ATT: ritual triggers and exact reward/material IDs.
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/b2d15612a1319d450ffe844ee6b9ef708aa9d2c9/.contrib/.db/standard/06%20-%20Expansion%20Features/12%20-%20Midnight/Lingering%20Shadows/Ritual%20Sites.lua
    [2779] = { spell = 1261362, replacesKind = "Добыча", kind = "Добыча",
        replacesSource = { "Место проведения ритуалов: Разрушенный трон", "Ritual Site: Broken Throne" },
        source = "В Разрушенном троне призови питомца {item:269836:Пухляш} у обглоданного мяса. Победи разозлённого медведя и накорми его, используя {item:242639:Почти свинина} ×5." },
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/0dd6b075fab29aacadc1fd80550577b3e30d1286/.contrib/.db/standard/17%20-%20NYI/Unsorted.lua#L620
    [2781] = { spell = 1261369, replacesKind = "Журнал", kind = "Журнал", replacesSource = { "" },
        unknownSourceNote = "В справочниках отмечен как ещё не выпущенный." },
    [2961] = { spell = 1286606, replacesKind = "Добыча", kind = "Добыча",
        replacesSource = { "Место проведения ритуалов: Разрушенный трон", "Ritual Site: Broken Throne" },
        source = "В Разрушенном троне помести {item:271999:Недостающая ритуальная свеча} на пустой череп и нажми на свечи в центре круга. Победи появившегося орла." },
    [2964] = { spell = 1287357, replacesKind = "Журнал", kind = "Добыча",
        replacesSource = { "Место проведения ритуалов: Высота Пронзающего Гребня", "Ritual Site: Daggerspine Point" },
        source = "В месте проведения ритуалов „Высота Пронзающего Гребня“ обыщи выброшенные на берег водоросли. Они могут выманить морского варана." },
    [2965] = { spell = 1287359, replacesKind = "Журнал", kind = "Профессия",
        replacesSource = { "Места проведения ритуалов: сокровища и редкие трофеи", "Ritual Sites: Treasure and Rare Spoils" },
        source = "Сшей упряжь кожевничеством или закажи её. {item:272391:Выкройка} и {item:272392:Рваный поводок рыси} добываются в финальных тайниках мест проведения ритуалов. Для поводка нужна известность 8." },
    -- These achievements unlock a purchase. Retain the journal's own vendor,
    -- price links and requirements, and let a changed live source take priority.
    -- https://github.com/ThingEngineering/wowthing-data/tree/27dcab420fb2f17880635fceb9974805544adbb5/db/11-midnight
    [2915] = { spell = 1271698, replacesKind = "Достижение", kind = "Торговец", replacesSource = {
        'Достижение: "Команда безднореагирования"\nТорговец: сержант Ворнин\nЗона: Луносвет\nЦена: 6000',
        "Achievement: Void Response Team\nVendor: Sergeant Vornin\nZone: Silvermoon City\nCost: 6000",
    } },
    [2988] = { spell = 1294648, replacesKind = "Достижение", kind = "Торговец", replacesSource = {
        'Достижение: "Кругозвездное путешествие"\nЗона: Вал\nТорговец: Кифаан\nЦена: 15',
        "Achievement: A Trip Around the Stars\nZone: Val\nVendor: Kifaan\nCost: 15",
    } },
    [2990] = { spell = 1294663, replacesKind = "Достижение", kind = "Торговец", replacesSource = {
        'Достижение: "Межзвездное путешествие"\nЗона: Найтал\nТорговец: Кифаан\nЦена: 15',
        "Achievement: A Trip Through the Stars\nZone: Naigtal\nVendor: Kifaan\nCost: 15",
    } },
    [3033] = { spell = 1297427, replacesKind = "Достижение", kind = "Торговец", replacesSource = {
        'Зоны: Вал и Найтал\nДостижение: "Героические решающие сражения"\nТорговец: Кифаан\nЦена: 15',
        "Zones: Val and Naigtal\nAchievement: Heroic Showdowns\nVendor: Kifaan\nCost: 15",
    } },
    -- https://worldofwarcraft.blizzard.com/en-gb/news/24310658
    [3106] = { spell = 1305612, replacesKind = "Магазин", replacesSource = shopSource, kind = "Акция",
        source = "Подписка на 12 месяцев" },
    [3143] = { spell = 1314189, replacesKind = "Магазин", replacesSource = shopSource, kind = "Акция",
        source = "Подписка на 12 месяцев" },
}
