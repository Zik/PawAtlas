local _, atlas = ...

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

-- Reviewed acquisition types and details for incomplete journal entries.
local shopSource = { "Внутриигровой магазин", "In-Game Shop" }
atlas.journalSourceDetails = {
    [221] = { spell = 48778, replacesKind = "Торговец", kind = "Класс",
        replacesSource = { "Trainer: Death Knight" } },
    -- https://www.wowhead.com/spell=73630/summon-great-exarchs-elekk
    [368] = { spell = 73630, replacesKind = "Квест", kind = "Класс",
        source = "Классовый транспорт паладина-дренея." },
    -- https://worldofwarcraft.blizzard.com/en-gb/recruit-a-friend
    [1698] = { spell = 400733, replacesKind = "Магазин", kind = "Акция",
        replacesSource = { "Пригласи друга", "Recruit-a-Friend", "Внутриигровой магазин", "In-Game Shop" },
        source = "Пригласи друга" },
    -- ATT: item211089 is awarded after attaching parts to the frame (quest90136).
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/b2d15612a1319d450ffe844ee6b9ef708aa9d2c9/.contrib/.db/standard/06%20-%20Expansion%20Features/11%20-%20The%20War%20Within/Revisited%20Horrific%20Visions.lua
    [1948] = { spell = 428068, replacesKind = "Торговец", kind = "Квест", replacesSource = {
        "Зона: видение Штормграда (возвращение)\nЗона: видение Оргриммара (возвращение)",
        "Zone: Vision of Stormwind (Revisited)\nZone: Vision of Orgrimmar (Revisited)",
    } },
    -- Blizzard 24295383 confirms the Trading Post route, without a current offer.
    [1958] = { spell = 431360, replacesKind = "Журнал", kind = "Торговая лавка", replacesSource = { "" },
        source = "Торговая лавка. Ассортимент меняется.\nПредмет: |cffffd200|Hitem:212229|h[Поводья сумеречного небесного хищника]|h|r" },
    -- ATT: five runekeys lead to quest85811 and item232639.
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/b2d15612a1319d450ffe844ee6b9ef708aa9d2c9/.contrib/.db/standard/02%20-%20Outdoor%20Zones/15%20Khaz%20Algar/Siren%20Isle/Seafury%20Tempest%20(Storm).lua
    [2322] = { spell = 471562, replacesKind = "Журнал", kind = "Квест",
        replacesSource = { "Зона: остров Сирен", "Zone: Siren Isle" },
        source = "Во время шторма используй пять разных рунных ключей в Забытом хранилище острова Сирен, затем заверши задание Трайира.\nПредмет: |cffffd200|Hitem:232639|h[Трайир Очи Сирены]|h|r" },
    -- Blizzard 24242435: the Modern mount is included in the Outland packs.
    [2719] = { spell = 1255246, replacesKind = "Событие", kind = "Акция",
        replacesSource = { "Событие: Burning Crusade Classic" } },
    -- https://www.wowhead.com/news/how-to-obtain-the-echo-of-alnsharan-mount-in-midnight-380704
    [2749] = { spell = 1260356, replacesKind = "Добыча", kind = "Квест",
        source = "Квест: «Легенда об Альн'ашаране»\nМесто: Харандар" },
    -- ATT: ritual triggers and exact reward/material IDs.
    -- https://github.com/ATTWoWAddon/AllTheThings/blob/b2d15612a1319d450ffe844ee6b9ef708aa9d2c9/.contrib/.db/standard/06%20-%20Expansion%20Features/12%20-%20Midnight/Lingering%20Shadows/Ritual%20Sites.lua
    [2779] = { spell = 1261362, replacesKind = "Добыча", kind = "Добыча",
        replacesSource = { "Место проведения ритуалов: Разрушенный трон", "Ritual Site: Broken Throne" },
        source = "В Разрушенном троне призови Пухляша у обглоданного мяса. Победи разозлённого медведя и накорми его пятью порциями „Почти свинины“." },
    [2961] = { spell = 1286606, replacesKind = "Добыча", kind = "Добыча",
        replacesSource = { "Место проведения ритуалов: Разрушенный трон", "Ritual Site: Broken Throne" },
        source = "В Разрушенном троне поставь недостающую ритуальную свечу на пустой череп и нажми на свечи в центре круга. Победи появившегося орла." },
    [2964] = { spell = 1287357, replacesKind = "Журнал", kind = "Добыча",
        replacesSource = { "Место проведения ритуалов: Высота Пронзающего Гребня", "Ritual Site: Daggerspine Point" },
        source = "В месте проведения ритуалов „Высота Пронзающего Гребня“ обыщи выброшенные на берег водоросли. Они могут выманить морского варана." },
    [2965] = { spell = 1287359, replacesKind = "Журнал", kind = "Профессия",
        replacesSource = { "Места проведения ритуалов: сокровища и редкие трофеи", "Ritual Sites: Treasure and Rare Spoils" },
        source = "Сшей упряжь кожевничеством или закажи её. Выкройка и рваный поводок рыси добываются в финальных тайниках мест проведения ритуалов. Для поводка нужна известность 8." },
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
