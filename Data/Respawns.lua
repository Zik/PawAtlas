local _, atlas = ...

-- Minutes between appearances on one shard. Conditions describe what starts
-- the interval when it is not simply the death of this creature.
atlas.npcRespawns = {}
local function add(ids, minimum, maximum, condition)
    local window = { min = minimum, max = maximum or minimum, condition = condition }
    for _, id in ipairs(ids) do atlas.npcRespawns[id] = window end
end

-- https://github.com/fstenstrom/world-boss-timers/blob/master/BossData.lua
-- https://www.wowhead.com/npc=73167/huolon#comments
add({73167}, 20)
add({62346, 69161, 83746}, 15)
add({60491}, 10, 20)
-- https://www.wowhead.com/npc=69099/nalak#comments
add({69099}, 10, 15)

-- https://warcraft-secrets.com/guides/time-lost-proto-drake#respawn-information
add({32491}, 120, 480, "Отсчёт начинается после исчезновения тела. Вместо протодракона может появиться Вирагоса.")

-- https://www.wowhead.com/guide/aeonaxx-mount#spawn-information
add({50062}, 120, 480, "У Эонакса и кровопийцы общий интервал появления.")

-- https://www.wowhead.com/guide/poseidus-mount#spawn-information
add({50005}, 120, 480)

-- https://warcraft-secrets.com/guides/grey-riding-camel
add({50409, 50410}, 120, 480, "Общий интервал для фигурок. Только одна из них переносит к Дормусу.")

-- https://github.com/fstenstrom/world-boss-timers/blob/master/BossData.lua#L515-L539
add({69769, 69841, 69842}, 20, nil, "У каждой точки свой таймер. Цвет появившегося дикорога может отличаться.")

-- https://www.wowhead.com/guide/rare-mounts-in-wow#draenor-rares
add({50992, 50883, 50985, 51015, 50981, 50990}, 120, 480, "Отсчёт начинается после исчезновения тела.")
add({81001}, 15, 30)
add({95044, 95053, 95054, 95056}, 60, 120)

-- https://www.wowhead.com/guide/argus-rares-mounts-pets-toys#how-rare-spawning-works-on-argus
local argusRotation = "Пока рарка активна в ротации Аргуса или доступно её локальное задание."
-- Per-NPC observations: https://www.curseforge.com/wow/addons/rarescanner/files/9770804
add({122958, 126199, 126419, 126898}, 1, nil, argusRotation)
add({126040, 127288, 126912, 126852, 126867, 126208}, nil, 2, argusRotation)

-- https://www.wowhead.com/guide/mount-collecting-battle-for-azeroth
add({142437, 142692, 142423, 142739, 142741, 142709, 149652, 149660, 148787, 149655, 149663}, 1, nil, "В фазе военного фронта, в которой доступен этот противник.")

-- https://www.wowhead.com/npc=138794/dunegorger-kraulok#comments
add({138794}, 1, nil, "В неделю, когда активно локальное задание Краулока.")

-- https://www.reddit.com/r/wow/comments/1r305vf/ and https://www.wowhead.com/npc=151934/arachnoid-harvester#comments
add({152182, 151934}, 15, 30)

-- https://github.com/fstenstrom/world-boss-timers/blob/master/BossData.lua and https://www.wowhead.com/npc=157153/ha-li#comments
add({157153, 157162}, 30, 60, "Во время вторжения могу в Вечноцветущий дол.")
add({157146}, 30, 90, "Во время вторжения аматетов в Ульдум.")
add({162147}, 5, 30, "Во время вторжения акиров в Ульдум. Сжигание заражённых тел может ускорить появление.")

-- https://www.wowhead.com/npc=162819/warbringer-malkorak#comments and https://www.wowhead.com/npc=162690/nerissa-heartless#comments
add({162819}, 45, 90)
add({162690}, 30, 60)

-- https://www.wowhead.com/npc=166679/hopecrusher#comments
add({166679}, 60, nil, "Время до повторного появления туши, которая приманивает рарку.")

-- https://www.wowhead.com/npc=166521/famu-the-infinite#comments and https://github.com/fstenstrom/world-boss-timers/blob/master/BossData.lua
add({166521}, 25, 35, "Поговори с Искательницей Хильдой и отбей волны противников.")

-- https://www.wowhead.com/npc=179684/malbog#comments
add({179684}, 5, nil, "Время до повторного появления мяса для призыва.")

-- https://www.wowhead.com/npc=173468/dead-blanchy#comments
add({173468}, 60, 120)

-- https://www.wowhead.com/object=344732/damp-loam#comments
add({164112}, 10, nil, "Примерно столько восстанавливается влажный суглинок. Посади в него необычайно большой гриб.")

-- https://www.wowhead.com/npc=162586/tahonta#comments and https://www.curseforge.com/wow/addons/rarescanner/files/9770804
add({162586}, 10, 20)

-- https://www.wowhead.com/guide/lotr-dragonflight-mount-manuscript-guide-17891
add({195353}, 60)
-- https://www.wowhead.com/guide/azerothian-archives-public-event
add({208029}, 60, nil, "Большие раскопки начинаются каждый час в :30. Босс появляется в конце раскопок.")
-- https://www.wowhead.com/npc=203625/karokta#comments
add({203625}, 50, nil, "Пока активны редкие противники Мерцающего Огга в пещере Заралек.")

-- https://www.wowhead.com/guide/lotr-war-within-mount-guide-22393
add({219281}, 60)
add({232195}, 15, 30)
add({234845}, 60)

-- https://www.wowhead.com/news/beledar-crystal-timer-now-live-how-to-earn-the-beledars-spawn-mount-346234
add({207802}, 180, nil, "Появляется в начале тёмной фазы Беледара, которая длится 30 минут.")

-- https://www.wowhead.com/guide/lotr-midnight-mount-guide-31520 (named outdoor rares only)
add({246332, 240129, 250719, 250754, 250841, 250826, 255302, 255348, 246633, 250582, 250683, 250876, 250806, 255329}, 10)
add({242023, 242025, 245975, 242031, 242033, 242035, 242027, 242024, 242028, 247976, 242032, 242026}, 10)
add({248741, 249849, 249962, 250226, 250246, 249844, 249902, 249997, 250180, 250347}, 10)
add({244272, 241443, 256923, 256925, 256770, 245044, 238498, 256922, 256924, 257027, 245182}, 10)

-- https://www.curseforge.com/wow/addons/rarescanner/files/9770804 (Retail NPC observations, NpcSpawnInfoTables.lua)
add({200584}, 20, 32)
add({200600, 200721, 200978}, 24, 32)
add({200885}, 23, 32)
add({200960}, 25, 32)
add({242034}, 5, 15)
add({250231}, 8, 15)
add({250321}, 7, 15)
add({257199}, 5)
-- https://www.wowhead.com/npc=256926/queen-o-war#comments
add({256926}, 30, 60, "Время до появления короны. Нажми на неё, чтобы вызвать рарку.")

-- https://www.wowhead.com/guide/lotr-midnight-mount-guide-31520 and https://www.curseforge.com/wow/addons/rarescanner/files/9770804 (Coiled Isle; summoned rares excluded)
add({256631, 257906, 258920, 263456, 268049, 258916, 261109, 261142, 265237, 268090}, 5, 10)
add({265262}, 10)

-- https://www.wowhead.com/guide/rare-mounts-in-wow (Soundless) and https://www.wowhead.com/npc=152290/soundless#comments
add({152290}, 120, 480)

-- https://www.wowhead.com/npc=157134/ishak-of-the-four-winds#comments and https://github.com/fstenstrom/world-boss-timers/blob/master/BossData.lua
add({157134}, 120, 270, "В Ульдуме во время вторжений Ни’алоты.")

-- https://www.wowhead.com/npc=199010/empowered-snail#comments
add({199010}, 20, 35, "После успешного взаимодействия с улиткой.")

-- https://www.wowhead.com/npc=200681/bonesifter-marwak#comments
add({200681}, 60)

-- https://www.wowhead.com/npc=174861/gorged-shadehound#comments
add({174861}, 5, nil, "Интервал между запусками активной охоты на гончих в Утробе.")

-- https://www.wowhead.com/npc=179460/fallen-charger#comments and https://www.reddit.com/r/wow/comments/1ntd5lb/
add({179460}, 60, nil, "Если скакун добрался до Кортии и исчез. После убийства ожидание может занять несколько часов.")

-- https://www.wowhead.com/npc=250780/waverly#comments and https://www.wowhead.com/guide/lotr-midnight-mount-guide-31520
add({250780}, 10, nil, "Время до появления цветка. Нажми на него, чтобы вызвать рарку.")

-- Exact mount spells and journal labels from Blizzard Mount.db2 (ruRU/enUS).
-- The creature IDs are used only for the matching journal acquisition route.
atlas.journalRespawnSources = {
    [393] = { spell = 88718, npc = 50062, map = 207, boss = "Эонакс", englishBoss = "Aeonaxx" },
    [420] = { spell = 98718, npc = 50005, map = 203, boss = "Посейдус", englishBoss = "Poseidus" },
    [612] = { spell = 171620, npc = 50990, map = 550, boss = "Накк Громогласный", englishBoss = "Nakk the Thunderer" },
    [614] = { spell = 171622, npc = 50981, map = 550, boss = "Лук'хок", englishBoss = "Luk'hok" },
    [627] = { spell = 171636, npc = 50992, map = 525, boss = "Горок", englishBoss = "Gorok" },
    [630] = { spell = 171824, npc = 51015, map = 535, boss = "Сильфида", englishBoss = "Silthide" },
    [636] = { spell = 171830, npc = 50883, map = 539, boss = "Торопун", englishBoss = "Pathrunner" },
    [655] = { spell = 171849, npc = 50985, map = 543, boss = "Пудовый Кулак", englishBoss = "Poundfist" },
    [657] = { spell = 171851, npc = 81001, map = 525, boss = "Нок-Карош", englishBoss = "Nok-Karosh" },
    [1415] = { spell = 339632, npc = 164112, map = 1565, boss = "Вел'иккан", englishBoss = "Humon'gozz" },
    -- The egg is reached through the Edge of Reality portal (object 239828).
    -- https://www.wowhead.com/guide/voidtalon-of-the-dark-star-mount#spawn-timers
    [682] = { spell = 179478, boss = "яйцо Когтя Бездны", englishBoss = "Voidtalon Egg", respawn = {
        min = 120, condition = "Портал появляется от 2 ч после исчезновения без использования или от 8 ч после использования. После сброса мира — не раньше чем через 48 ч.",
    } },
}
