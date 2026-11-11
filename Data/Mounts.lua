local _, atlas = ...

-- Rarity, DB/Mounts/TheBurningCrusade.lua. Odds are per eligible loot attempt.
atlas.mounts = {
    { id = 183, name = "Пепел Ал’ара", english = "Ashes of Al'ar", boss = "Кель’тас Солнечный Скиталец",
      expansion = "BurningCrusade", journalInstance = 749, journalEncounter = 1576,
      place = "Крепость Бурь · Око", kind = "Рейд", odds = 100, art = "Phoenix", encounter = 733, map = 550, difficulties = { [4] = true } },
    { id = 185, name = "Повелитель воронов", english = "Raven Lord", boss = "Анзу",
      expansion = "BurningCrusade", journalInstance = 252, journalEncounter = 542,
      place = "Сетеккские залы · героический", kind = "Подземелье", odds = 67, art = "Raven", encounter = 1904, map = 556, difficulties = { [2] = true } },
    { id = 168, name = "Огненный боевой конь", english = "Fiery Warhorse", boss = "Ловчий Аттумен",
      expansion = "BurningCrusade", journalInstance = 745, journalEncounter = 1553,
      place = "Каражан · рейд", kind = "Рейд", odds = 100, art = "Steed", encounter = 652, map = 532, difficulties = { [3] = true } },
}

-- Reviewed instanced raid bosses in Rarity CE v0.3.1; zone names from
-- Blizzard Mount.db2 12.1.5.70688 (ruRU/enUS). Shared raid/dungeon names
-- such as Karazhan and Zul'Gurub are deliberately absent from zone matching.
atlas.raidMounts = { [478] = true, [954] = true, [3030] = true }
atlas.raidZones = {
    "Амирдрассил, Надежда Сна", "Анторус, Пылающий Трон", "Битва за Дазар'алор",
    "Гробница Предвечных", "Гробница Саргераса", "Душа Дракона",
    "Литейная клана Черной горы", "Логово Ониксии", "Манагорн Омега", "Марш на Кель'Данас",
    "Неруб'арский дворец", "Ни'алота, Пробуждающийся Город", "Огненные Просторы",
    "Око (Крепость Бурь)", "Око Вечности", "Осада Оргриммара", "Освобождение Нижней Шахты",
    "Престол Гроз", "Святилище Господства", "Трон Четырех Ветров", "Ульдуар", "Хранилище Аркавона",
    "Цитадель Адского Пламени", "Цитадель Ледяной Короны", "Цитадель Ночи",
    "Amirdrassil, the Dream's Hope", "Antorus, the Burning Throne", "Battle of Dazar'alor",
    "Blackrock Foundry", "Dragon Soul", "Eye of Eternity", "Firelands", "Hellfire Citadel",
    "Icecrown Citadel", "Liberation of Undermine", "Manaforge Omega", "March on Quel'Danas",
    "Nerub-ar Palace", "Ny'alotha, the Waking City", "Onyxia's Lair", "Sanctum of Domination",
    "Sepulcher of the First Ones", "Siege of Orgrimmar", "The Eye, Tempest Keep", "The Nighthold",
    "Throne of the Four Winds", "Throne of Thunder", "Tomb of Sargeras", "Ulduar", "Ula'tek", "Vault of Archavon",
}

atlas.lootByNPC = {}
for _, mount in ipairs(atlas.rares) do
    mount.boss = mount.locations[1].boss
    mount.place = mount.locations[1].place
    mount.kind = mount.quest and "Квест" or "Рарка"
    if mount.id == 561 then mount.art = "Serpent" end
    for _, npc in ipairs(mount.npcs) do
        local targets = atlas.lootByNPC[npc] or {}
        targets[#targets + 1] = mount
        atlas.lootByNPC[npc] = targets
    end
    atlas.mounts[#atlas.mounts + 1] = mount
end
local lowercase = {}
local upper = "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ"
local lower = "абвгдеёжзийклмнопрстуфхцчшщъыьэюя"
for i = 1, #upper, 2 do
    lowercase[upper:sub(i, i + 1)] = lower:sub(i, i + 1)
end

-- string.lower only folds ASCII on a typical client.
function atlas.searchKey(text)
    return (text:lower():gsub("[\208\209][\128-\191]", lowercase)
        :gsub("’", ""):gsub("'", ""):gsub("ё", "е"):match("^%s*(.-)%s*$"))
end

local keyboard = {}
local englishKeys = "qwertyuiop[]asdfghjkl;'zxcvbnm,.`"
local russianKeys = "йцукенгшщзхъфывапролджэячсмитьбюё"
for i = 1, #englishKeys do keyboard[englishKeys:sub(i, i)] = russianKeys:sub(i * 2 - 1, i * 2) end
for key, value in pairs({ ["{"] = "х", ["}"] = "ъ", [":"] = "ж", ['"'] = "э",
    ["<"] = "б", [">"] = "ю", ["~"] = "ё", ["/"] = ".", ["?"] = "," }) do keyboard[key] = value end

function atlas.searchQuery(text)
    local query = { key = atlas.searchKey(text) }
    local _, letters = text:gsub("[A-Za-z]", "")
    -- Keep single-letter, numeric and already-Cyrillic queries literal. The
    -- alternate is a keyboard layout, not a transliteration or typo correction.
    if letters >= 2 and not text:find("[\208\209][\128-\191]") then
        local alternative = atlas.searchKey((text:lower():gsub(".", keyboard)))
        if alternative ~= query.key then query.layout = alternative end
    end
    return query
end

function atlas.matchesSearch(key, query)
    return key:find(query.key, 1, true) ~= nil
        or (query.layout ~= nil and key:find(query.layout, 1, true) ~= nil)
end
for _, mount in ipairs(atlas.mounts) do
    mount.countKey = mount.art or tostring(mount.id)
    local words = { mount.name, mount.english, mount.boss, mount.place, mount.kind, mount.quest or "" }
    for _, loc in ipairs(mount.locations or {}) do
        words[#words + 1] = loc.boss .. " " .. loc.place
    end
    mount.key = atlas.searchKey(table.concat(words, " "))
end
