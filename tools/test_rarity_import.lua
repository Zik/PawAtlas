-- Run from the repository root: lua5.1 tools/test_rarity_import.lua
assert(_VERSION == "Lua 5.1", "This test requires Lua 5.1")

local function equal(actual, expected, scenario)
    assert(actual == expected, ("%s: expected %s, got %s"):format(scenario, tostring(expected), tostring(actual)))
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = copy(entry) end
    return result
end

local function same(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return left == right end
    for key, value in pairs(left) do if not same(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

local player, offline = "Player-current", "Player-offline"
local time, timers = 1000, {}
local trackingEvents, stageEvent, lootSource = {}, nil, nil
local availableItems = {}
function GetTime() return time end
function GetServerTime() return time end
function GetRealmName() return "Realm" end
function UnitName() return "Tester" end
function UnitGUID() return player end
function GetStatistic(id) if id == 504 then return "4" end end
function GetNumLootItems() return lootSource and 1 or 0 end
function GetLootSourceInfo() return lootSource, 1 end
function CreateFrame()
    return { SetScript = function(self, _, handler) stageEvent = function(...) handler(self, ...) end end,
        RegisterEvent = function() end, RegisterUnitEvent = function() end }
end
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
C_DateAndTime = { GetSecondsUntilDailyReset = function() return 3600 end }
C_Item = { GetItemCount = function(id, bank, uses, reagentBank, accountBank)
    if bank and not uses and reagentBank and accountBank then return availableItems[id] end
end }
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %1$s ×%2$d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
local cageSpells = { [611] = 171619, [622] = 171630, [643] = 171837 }
local reportedSpells = { [304] = 63796, [1507] = 354358, [2176] = 447213 }
local eggSpells = { [538] = 138641, [539] = 138642, [540] = 138643 }
local islandSpells = { [993] = 254811, [1169] = 278979, [1175] = 279466, [1176] = 279467, [1178] = 279469,
    [1209] = 288712, [1211] = 288720, [1212] = 288721, [1213] = 288722 }
C_MountJournal = { GetMountInfoByID = function(id)
    return "Mount " .. id, cageSpells[id] or reportedSpells[id] or eggSpells[id] or islandSpells[id] or 100 + id
end }

local function nextTimer() table.remove(timers, 1)() end
local function drain()
    while #timers > 0 do nextTimer() end
end

local rare = { id = 1, name = "Rare", countKey = "rare" }
local stage = { key = "stage:shared", item = 702, method = "ENCOUNTER", encounters = { 902 } }
local incompatible = { key = "mount:3", item = 703, method = "ENCOUNTER",
    encounters = { 903 }, rarityIncompatible = true }
local mechsuit = { key = "item:226683", item = 226683, method = "BOSS", statisticId = { 40722 } }
local atlas = {
    mounts = { rare, { id = 2, journalOnly = true }, { id = 3, name = "Incompatible" },
        { id = 4 }, { id = 5 }, { id = 6 }, { id = 7, journalOnly = true }, { id = 2119, journalOnly = true } },
    attemptStages = { [2] = { item = stage }, [3] = { reward = incompatible }, [7] = { item = stage },
        [2119] = { item = mechsuit } },
    killStatistics = { [4] = { 504 }, [6] = { 506, 507 } },
    lootItems = {},
    lootByNPC = {},
    lootFrequencies = {},
    addTranslations = function() end,
    RegisterEvent = function(_, event, handler) trackingEvents[event] = handler end,
}
local cageMounts, catalog = {}, {}
for _, file in ipairs({ "Data/Rares.lua", "Data/JournalData.lua", "Data/LootSources.lua" }) do
    assert(loadfile(file))("PawAtlas", catalog)
end
for _, mount in ipairs(catalog.rares) do
    local id = mount.id
    if cageSpells[id] then
        cageMounts[#cageMounts + 1] = mount
        atlas.mounts[#atlas.mounts + 1] = mount
        atlas.lootItems[id] = catalog.lootItems[id]
        atlas.attemptStages[id] = catalog.attemptStages[id]
        atlas.lootFrequencies[id] = catalog.lootFrequencies[id]
        for _, npc in ipairs(mount.npcs) do
            atlas.lootByNPC[npc] = atlas.lootByNPC[npc] or {}
            table.insert(atlas.lootByNPC[npc], mount)
        end
    end
end
local reportedMounts = {}
for id in pairs(reportedSpells) do
    local definitions = catalog.attemptStages[id]
    local mount = { id = id, name = definitions.reward.name, journalOnly = id ~= 2176 }
    reportedMounts[id] = mount
    atlas.mounts[#atlas.mounts + 1] = mount
    atlas.lootItems[id] = catalog.lootItems[id]
    atlas.attemptStages[id] = definitions
end
for _, id in ipairs({ 488, 624, 765 }) do
    atlas.mounts[#atlas.mounts + 1] = { id = id, journalOnly = true }
    atlas.attemptStages[id] = catalog.attemptStages[id]
end
atlas.islandSalvageMounts = catalog.islandSalvageMounts
for id in pairs(atlas.islandSalvageMounts) do
    atlas.mounts[#atlas.mounts + 1] = { id = id, journalOnly = true }
    atlas.attemptStages[id] = catalog.attemptStages[id]
    atlas.lootItems[id] = catalog.lootItems[id]
end
local eggMounts = {}
for _, id in ipairs({ 538, 539, 540 }) do
    local mount = { id = id, journalOnly = true }
    eggMounts[#eggMounts + 1] = mount
    atlas.mounts[#atlas.mounts + 1] = mount
    atlas.attemptStages[id] = catalog.attemptStages[id]
end
local eventSpells = { [769] = 191314, [781] = 201098, [1735] = 408651, [2328] = 472479 }
local eventMounts = {}
for id in pairs(eventSpells) do
    local mount = { id = id, journalOnly = true, journalSourceRaw = "World Event: Event" }
    eventMounts[id] = mount
    atlas.mounts[#atlas.mounts + 1] = mount
    atlas.attemptStages[id] = catalog.attemptStages[id]
end
local ascendedID, ascendedKey = 1426, "mount:1426"
local ascended = { id = ascendedID, name = "Ascended Skymane", npcs = { 170832, 170833, 170834, 170835, 170836 } }
atlas.mounts[#atlas.mounts + 1] = ascended
atlas.attemptStages[ascendedID], atlas.lootItems[ascendedID] = catalog.attemptStages[ascendedID], catalog.lootItems[ascendedID]
for id = 20, 100 do atlas.mounts[#atlas.mounts + 1] = { id = id } end
for _, file in ipairs({ "Core/Tracking.lua", "Core/AttemptStages.lua", "Core/RarityImport.lua" }) do
    assert(loadfile(file))("PawAtlas", atlas)
end
MountAtlasDB = { kills = { rare = 2 } }
MountAtlasAccountDB = { characters = { [player] = { stageAttempts = { [stage.key] = 1 } } } }
atlas.initializeTracking()
atlas.initializeAttemptStages()

local alpha = { groups = {
    mounts = {
        { type = "MOUNT", method = "NPC", spellId = 101, attempts = 8, lastAttempts = 90 },
        { type = "MOUNT", method = "NPC", spellId = 101, attempts = 5 },
        { type = "MOUNT", method = "ENCOUNTER", spellId = 103, itemId = 703, attempts = 40, name = "Wrong unit" },
        { type = "MOUNT", method = "NPC", spellId = 105, found = true, realAttempts = 3 },
    },
    items = {
        { type = "ITEM", method = "ENCOUNTER", itemId = 702, attempts = 10 },
        { type = "ITEM", method = "NPC", itemId = 999, attempts = 1000 },
    },
}, accountWideStatistics = {
    [offline] = { statistics = { [504] = 12, [506] = 5 } },
} }
local beta = { groups = { mounts = {
    { type = "MOUNT", method = "NPC", spellId = 101, attempts = 4 },
} } }
RarityDB = { profileKeys = { ["Tester - Realm"] = "Alpha" }, profiles = { Alpha = alpha, Beta = beta } }

local accountBefore, characterBefore, rarityBefore = copy(MountAtlasAccountDB), copy(MountAtlasDB), copy(RarityDB)
assert(atlas.startRarityImport())
assert(not atlas.startRarityImport(), "second concurrent import started")
nextTimer()
assert(atlas.rarityImportProgress().running, "index should yield before applying")
atlas.cancelRarityImport()
drain()
assert(same(accountBefore, MountAtlasAccountDB) and same(characterBefore, MountAtlasDB),
    "cancelled preparation changed PawAtlas saved data")
assert(same(rarityBefore, RarityDB), "cancelled preparation changed Rarity saved data")

local getMountInfo = C_MountJournal.GetMountInfoByID
C_MountJournal.GetMountInfoByID = function() error("test journal failure") end
assert(atlas.startRarityImport())
drain()
equal(atlas.rarityImportProgress().result.status, "error", "preparation failure status")
assert(same(accountBefore, MountAtlasAccountDB) and same(characterBefore, MountAtlasDB),
    "failed preparation changed PawAtlas saved data")
C_MountJournal.GetMountInfoByID = getMountInfo

local function run()
    assert(atlas.startRarityImport())
    drain()
    local state = atlas.rarityImportProgress()
    assert(not state.error, state.error)
    return state.result
end
local first = run()
equal(first.status, "imported", "initial import status")
equal(first.updated, 5, "unique updates including both stage owners, snapshot and award")
equal(first.unchanged, 0, "initial unchanged mounts")
equal(first.skipped, 1, "only relevant incompatibilities counted")
equal(first.skipEntries[1].name, "Incompatible", "skipped mount display name")
equal(first.skipEntries[1].reason, "incompatible", "skip reason")
equal(atlas.kills(rare), 8, "duplicate Rarity records use the larger lifetime count")
equal(atlas.withImportedAttempts({ id = stage.key }, atlas.rawStageAttempts(stage.key)), 10, "shared stage total")
equal(atlas.rawKills({ id = 4 }), 16, "current and offline game-stat snapshots")
equal(atlas.rawKills({ id = 6 }), nil, "incomplete game-stat snapshot remains unknown")
equal(atlas.acquisitionAttempts("mount:5").attempts, 3, "frozen award count")
equal(atlas.rarityImportSummary().profile, "Alpha", "stored profile")
equal(atlas.rarityImportSummary().time, time, "stored import date")
assert(same(rarityBefore, RarityDB), "import changed Rarity saved data")

local again = atlas.importRarity()
equal(again.updated, 0, "same snapshot has no updates")
equal(again.unchanged, 5, "same snapshot matches all previous mounts")
assert(atlas.startRarityImport())
local character = MountAtlasAccountDB.characters[player]
character.kills.rare = character.kills.rare + 1
atlas.recordImportedAttempt(rare, player)
RarityDB.profileKeys["Tester - Realm"] = "Beta"
drain()
local switched = atlas.rarityImportProgress().result
equal(switched.profile, "Beta", "profile switch during indexing uses the active profile")
equal(switched.count, 1, "different profiles are not combined")
equal(switched.updated, 0, "smaller Rarity counter leaves existing history intact")
equal(atlas.kills(rare), 9, "new attempt survives reimport without double counting")

Rarity = { db = { profile = beta, GetCurrentProfile = function() return "Runtime profile" end } }
beta.groups.mounts[1].attempts = 14
local localAward = atlas.rememberAcquisition("mount:6", 7)
beta.groups.mounts[2] = { type = "MOUNT", method = "NPC", spellId = 106, found = true, realAttempts = 10 }
local larger = run()
equal(larger.profile, "Runtime profile", "runtime profile is preferred")
equal(larger.updated, 1, "existing award does not count as an update")
equal(larger.unchanged, 1, "existing award is preserved")
equal(atlas.kills(rare), 14, "larger compatible Rarity count increases the total")
assert(atlas.clearRarityImport())
equal(atlas.kills(rare), 3, "clear keeps locally recorded attempts")
equal(atlas.rawStageAttempts(stage.key), 1, "clear keeps locally recorded stage attempts")
equal(atlas.rawKills({ id = 4 }), 16, "clear retains merged game-stat snapshots")
equal(atlas.acquisitionAttempts("mount:5"), nil, "clear removes Rarity-only award")
equal(atlas.acquisitionAttempts("mount:6"), localAward, "clear preserves PawAtlas award")
equal(atlas.rarityImportSummary().time, nil, "clear removes import metadata")

Rarity.db.profile = { groups = { items = {} }, accountWideStatistics = { [offline] = { statistics = { [40722] = 6 } } } }
local stageOnly = run()
equal(stageOnly.status, "imported", "stats-only stage snapshot is importable")
equal(stageOnly.updated, 1, "stats-only prerequisite updates its owning mount")
equal(atlas.rawStageAttempts(mechsuit.key), 6, "stats-only prerequisite attempt total")
stageOnly = run()
equal(stageOnly.updated, 0, "reimporting the prerequisite snapshot does not update the mount")
equal(stageOnly.unchanged, 1, "reimporting the prerequisite snapshot still matches the mount")

Rarity.db.profile = beta
beta.groups.mounts = {}
for id = 1, 51 do
    beta.groups.mounts[id] = { type = "MOUNT", method = "NPC", attempts = 1, name = "Unknown " .. id }
end
beta.groups.mounts[1].spellId = 101.9
local empty = run()
equal(empty.status, "empty", "unmatched sources produce empty status")
equal(empty.skipped, 51, "every incompatible source is counted")
equal(#empty.skipEntries, 50, "saved skip details are bounded")
equal(atlas.kills(rare), 3, "fractional spell ID does not match the mount")
equal(atlas.rarityImportSummary().status, "empty", "empty remains distinct after reload")

equal(#cageMounts, 3, "all three Rattling Iron Cage mounts are available")
local cageHistory = { [611] = 18, [622] = 24, [643] = 31 }
local cageProfile = { groups = { mounts = {} } }
for _, mount in ipairs(cageMounts) do
    local reward = atlas.attemptStages[mount.id].reward
    table.insert(cageProfile.groups.mounts, { type = "MOUNT", method = "NPC", spellId = cageSpells[mount.id],
        itemId = reward.item, attempts = cageHistory[mount.id] })
end
Rarity.db.profile = cageProfile
local function checkCageAttempts(extra)
    for _, mount in ipairs(cageMounts) do
        local attempts = cageHistory[mount.id] + extra
        equal(atlas.kills(mount), attempts, "imported cage mount kills " .. mount.id)
        local rate, _, rewardAttempts = atlas.dropProbability(mount)
        equal(rate, 1 / 30, "mount chance per eligible kill " .. mount.id)
        equal(rewardAttempts, attempts, "reward probability uses imported kills " .. mount.id)
        local progress = atlas.itemAttemptProgress(mount)
        equal(progress.item, 128025, "separate cage item " .. mount.id)
        equal(progress.attempts, attempts, "cage probability reuses the same kills " .. mount.id)
        equal(progress.perAttempt, 1 / 10, "cage chance per eligible kill " .. mount.id)
        equal(progress.contentsPerOpening, 1 / 3, "mount chance per cage " .. mount.id)
        equal(progress.rateEstimated, true, "cage odds are explicitly estimated " .. mount.id)
    end
    equal(atlas.stageAttemptDefinition("item:128025"), nil, "no separate cage attempt counter")
end
equal(run().updated, 3, "all three cage mount histories are imported")
checkCageAttempts(0)
equal(run().updated, 0, "cage mount reimport does not increase any count")
checkCageAttempts(0)
lootSource = "Creature-0-1-2-3-95044-001"
trackingEvents.LOOT_OPENED("LOOT_OPENED", false, false)
stageEvent("LOOT_OPENED", false, false)
checkCageAttempts(1)
lootSource = "Item-0-1-2-3-128025-002"
trackingEvents.LOOT_OPENED("LOOT_OPENED", false, true)
stageEvent("LOOT_OPENED", false, true)
checkCageAttempts(1)

local reportedProfile = { groups = { mounts = {
    { type = "MOUNT", method = "ENCOUNTER", spellId = 63796, itemId = 45693,
        encounters = { 1143 }, attempts = 51, found = true, realAttempts = 51 },
    { type = "MOUNT", method = "COLLECTION", spellId = 354358, itemId = 186646,
        collectedItemId = { 187153 }, attempts = 10, found = true, realAttempts = 10 },
    { type = "MOUNT", method = "COLLECTION", spellId = 447213, itemId = 223270,
        collectedItemId = { 224025 }, attempts = 10, found = true, realAttempts = 10 },
}, items = {} } }
Rarity.db.profile = reportedProfile
local function itemLink(id)
    return ("|cff1eff00|Hitem:%d::::::::|h[Item %d]|h|r"):format(id, id)
end
local function lootMessage(message, lineID)
    stageEvent("CHAT_MSG_LOOT", message, nil, nil, nil, nil, nil, nil, nil, nil, nil, lineID)
end
local shardLink = itemLink(224025)
local oneShard = LOOT_ITEM_SELF:format((shardLink:gsub("^|cff1eff00", "|cnIQ3:")))
equal(atlas.itemCollectionCount(reportedMounts[2176]), nil, "item receipt history is unknown at first")
lootMessage("You receive loot: " .. shardLink .. " ×2.", 100)
equal(atlas.itemCollectionCount(reportedMounts[2176]), 2, "stack quantity from a localized self-loot template")
local reported = run()
equal(reported.count, 3, "both collection histories and the reviewed Rarity estimate import")
equal(reported.skipped, 0, "matching imported counters are not skipped")
equal(atlas.rarityImportedCollection(reportedMounts[2176]), 10, "Alunira's imported item quantity")
equal(atlas.itemCollectionCount(reportedMounts[2176]), 10, "native loot predating import is not added twice")
equal(atlas.rarityImportedCollection(reportedMounts[1507]), 10, "Darkmaul's imported item quantity")
equal(atlas.kills(reportedMounts[304]), 51, "Mimiron's Head displays the Rarity tally")
equal(atlas.rawKills(reportedMounts[304]), 0, "the Rarity tally does not enter native kills")
equal(atlas.isMountAttemptEligible(reportedMounts[304], 33288), false, "the native zero-Keeper safeguard remains")
local _, mimironProbability = atlas.dropProbability(reportedMounts[304])
equal(mimironProbability, nil, "the unverified tally never enters cumulative probability")
atlas.recordImportedStatistic(304, player, 1)
stageEvent("ENCOUNTER_END", 1143, "Yogg-Saron", 4, 25, 1)
equal(atlas.kills(reportedMounts[304]), 51, "a generic Yogg-Saron kill cannot increase the Rarity tally")
equal(MountAtlasAccountDB.rarityImport.entries["item:224025"], nil, "collection does not provide a shard attempt history")

local shard = { type = "ITEM", method = "NPC", itemId = 224025, spellId = 450842,
    zones = { "2248" }, attempts = 450, repeatable = true }
reportedProfile.groups.items[1] = shard
reportedProfile.groups.mounts[2].collectedItemId = 187153
reported = run()
equal(reported.updated, 0, "matching item without matching detection method does not update history")
equal(reported.count, 3, "scalar and single-item array collection definitions both match")
equal(reported.skipReasons.unit_mismatch, 1, "incompatible item history is reported separately")

shard.method = "ZONE"
reported = run()
equal(reported.updated, 1, "separate Crackling Shard history imports for Alunira")
equal(reported.skipped, 0, "both Alunira item histories import")
equal(atlas.rarityImportedCollection(reportedMounts[2176]), 10, "item attempts do not replace the item quantity")
equal(atlas.itemAttemptProgress(reportedMounts[2176]).attempts, 450, "shard attempts use the zone counter")
equal(atlas.kills(reportedMounts[2176]), 0, "shard and inventory counts are separate from mount kills")
equal(atlas.itemAttemptProgress(reportedMounts[1507]).attempts, nil, "mushroom counts are not historical rolls")
for id in pairs(reportedMounts) do
    equal(atlas.acquisitionAttempts("mount:" .. id), nil, "no imported acquisition for " .. id)
end
equal(run().updated, 0, "reimporting the shard history is idempotent")

lootMessage(oneShard, 101)
equal(atlas.itemCollectionCount(reportedMounts[2176]), 11, "self-loot with a named item quality color counts")
lootMessage(oneShard, 101)
equal(atlas.itemCollectionCount(reportedMounts[2176]), 11, "repeated chat event does not add the same receipt twice")
lootMessage(oneShard, 102)
equal(atlas.itemCollectionCount(reportedMounts[2176]), 12, "same text with a new chat line counts as new loot")
lootMessage(oneShard)
lootMessage(LOOT_ITEM_PUSHED_SELF:format(shardLink), 103)
availableItems[224025] = 4
stageEvent("BAG_UPDATE_DELAYED")
equal(atlas.itemCollectionCount(reportedMounts[2176]), 12, "missing line IDs and inventory movements do not add history")
equal(atlas.itemAttemptProgress(reportedMounts[2176]).collected, 4, "current inventory uses the game API")
reportedProfile.groups.mounts[3].attempts = 12
equal(run().updated, 0, "Rarity can already include the same native receipts")
reportedProfile.groups.mounts[3].attempts = 14
equal(run().updated, 1, "larger Rarity item snapshot replaces the floor")
equal(atlas.itemCollectionCount(reportedMounts[2176]), 14, "larger snapshot does not add the same native receipts")
lootMessage(oneShard, 104)
equal(atlas.itemCollectionCount(reportedMounts[2176]), 15, "loot advances the rebased item history")

local claw = catalog.attemptStages[624].item.item
lootMessage(LOOT_ITEM_SELF:format(itemLink(claw)), 105)
equal(atlas.itemCollectionCount({ id = 624 }), 1, "shared reagent receipt is tracked for the first mount")
equal(atlas.itemCollectionCount({ id = 765 }), 1, "shared reagent receipt is tracked once for both mounts")
equal(MountAtlasAccountDB.characters[player].collectionItems[claw], 1, "the native receipt is keyed by reagent ID")

local aggregate = catalog.attemptStages[488]
local components = copy(aggregate.item.collectedItems)
local firstComponent = table.remove(components, 1)
components[#components + 1] = tostring(firstComponent)
local aggregateSource = { type = "MOUNT", method = "COLLECTION", spellId = 588, itemId = aggregate.reward.item,
    collectedItemId = components, attempts = 27 }
table.insert(reportedProfile.groups.mounts, aggregateSource)
equal(run().updated, 1, "the same collection set matches regardless of ID order and number representation")
equal(atlas.itemCollectionCount({ id = 488 }), 27, "aggregate collections import as item quantities")
table.remove(components, 1)
aggregateSource.attempts = 99
reported = run()
equal(reported.skipReasons.unit_mismatch, 1, "an incomplete item set is incompatible")
equal(atlas.itemCollectionCount({ id = 488 }), 27, "a different collection cannot overwrite the saved quantity")

assert(atlas.clearRarityImport())
equal(atlas.itemCollectionCount(reportedMounts[2176]), 5, "clearing Rarity preserves native receipts")
equal(atlas.kills(reportedMounts[304]), nil, "clearing Rarity removes the encounter estimate")
assert(atlas.clearAttemptStatistics())
equal(atlas.itemCollectionCount(reportedMounts[2176]), nil, "clearing all statistics clears native receipts")
equal(atlas.itemAttemptProgress(reportedMounts[2176]).collected, 4, "clearing statistics keeps current inventory")

Rarity, RarityDB = nil, nil
equal(run().status, "unavailable", "missing active profile is unavailable")

atlas.mountRewardContainerRewards = catalog.mountRewardContainerRewards
local function checkEggProbability(count)
    for _, mount in ipairs(eggMounts) do
        local perAttempt, cumulative, attempts = atlas.dropProbability(mount)
        equal(perAttempt, 1 / 300, "egg and selected colour per eligible loot attempt")
        equal(attempts, count, "all three colours reuse the egg farm history")
        equal(cumulative, 1 - (1 - 1 / 300) ^ count, "raptor chance across recorded attempts")
        equal(atlas.itemAttemptProgress(mount).perAttempt, .01, "egg drop chance is separate")
    end
end
local eggKey = "item:94295"
for _, count in ipairs({ 0, 1 }) do
    MountAtlasAccountDB.characters[player].stageAttempts[eggKey] = count
    checkEggProbability(count)
end

-- Rarity CE DB/Toys/MistsOfPandaria.lua: one egg source lists all three spells.
Rarity = { db = { profile = { groups = { items = { ["Primal Egg"] = {
    type = "ITEM", method = "NPC", itemId = 94295, spellId = { 138642, 138643, 138641 },
    unique = true, attempts = 100,
} } } } } }
local eggResult = run()
equal(eggResult.updated, 3, "one egg source updates every raptor")
equal(eggResult.skipped, 0, "the shared egg source is not skipped")
local eggEntries = MountAtlasAccountDB.rarityImport.entries
assert(same(eggEntries, { [eggKey] = { total = 100, source = 100, deltaByGUID = {}, mountIDs = { 538, 539, 540 } } }),
    "Rarity egg history must be stored only once, under the prerequisite item")
equal(atlas.rawStageAttempts(eggKey), 1, "the local egg counter is preserved")
checkEggProbability(100)

eggResult = run()
equal(eggResult.updated, 0, "the same egg source adds no attempts on reimport")
equal(eggResult.unchanged, 3, "reimport recognizes all three raptors")
checkEggProbability(100)

C_MountJournal.GetMountInfoByID = function(id)
    if eventSpells[id] then return "Event mount " .. id, eventSpells[id] end
    return getMountInfo(id)
end

local bagCounts = { [128670] = 1, [205368] = 1, [205374] = 1, [54537] = 3, [173989] = 0 }
local getItemCount = C_Item.GetItemCount
C_Item.GetItemCount = function(id, bank, uses, reagentBank, accountBank)
    if not bank and bagCounts[id] then return bagCounts[id] end
    return getItemCount(id, bank, uses, reagentBank, accountBank)
end
GetTime = GetServerTime
lootSource = nil
stageEvent("PLAYER_ENTERING_WORLD")

local function checkEventAttempts(id, count)
    local perAttempt, cumulative, attempts = atlas.dropProbability(eventMounts[id])
    equal(attempts, count, "tracked attempts for event mount " .. id)
    equal(cumulative, count == 0 and 0 or 1 - (1 - perAttempt) ^ count, "event cumulative probability " .. id)
end
for id in pairs(eventMounts) do checkEventAttempts(id, 0) end
equal(atlas.rewardAttemptProgress(eventMounts[1735]).rateEstimated, true, "researcher gifts have an averaged rate")

local function openContainer(item)
    stageEvent("LOOT_OPENED", false, true)
    bagCounts[item] = bagCounts[item] - 1
    stageEvent("BAG_UPDATE_DELAYED")
    stageEvent("LOOT_CLOSED")
    stageEvent("BAG_UPDATE_DELAYED")
end
do
    local entries = MountAtlasAccountDB.rarityImport.entries
    local key = "mount:1212"
    -- Rarity's older history counts expedition completions alongside bag openings.
    entries[key] = { total = 25, deltaByGUID = {}, mountIDs = { 1212 } }
    local function openings(id)
        return atlas.rewardAttemptProgress({ id = id, journalOnly = true, journalSourceRaw = "Drop: Island Expeditions" })
    end
    equal(openings(1212).attempts, 0, "mixed imported history cannot count as salvage openings")
    bagCounts[173989] = 1
    stageEvent("BAG_UPDATE_DELAYED")
    equal(openings(1212).attempts, 0, "buying salvage does not roll a reward")
    openContainer(173989)
    equal(openings(1212).attempts, 1, "a Jorundall opening counts once for the thunderscale")
    equal(openings(1176).attempts, 1, "the same opening counts once for the chasm-leaper")
    equal(openings(1212).perAttempt, nil, "a salvage attempt has no published drop rate")
    equal(openings(1212).cumulative, nil, "there is no cumulative chance without a drop rate")
    entries[key] = nil
end
do
    local entries = MountAtlasAccountDB.rarityImport.entries
    local legacyKey = "mount:1212"
    entries[legacyKey] = { total = 60, source = 25, deltaByGUID = { [player] = 2 }, mountIDs = { 1212 } }
    entries[1175] = { total = 300, source = 8, deltaByGUID = {} }
    MountAtlasAccountDB.rarityImport.islandHistory = { [1176] = 30 }
    MountAtlasAccountDB.characters[player].islandExpeditionCompletions = 4
    local function attempts(id)
        return atlas.islandExpeditionProgress({ id = id })
    end
    atlas.initializeIslandImports()
    equal(attempts(1212), 25, "legacy stage snapshot keeps its original Rarity value")
    equal(attempts(1175), 8, "legacy mount snapshot keeps its original Rarity value")
    equal(attempts(1176), 30, "a legacy numeric history is not added to previous local attempts")
    local function openJorundall()
        bagCounts[173989] = 1
        stageEvent("BAG_UPDATE_DELAYED")
        openContainer(173989)
    end
    openJorundall()
    equal(attempts(1212), 26, "a fresh opening increases a migrated stage snapshot immediately")
    equal(attempts(1176), 31, "a fresh opening increases a migrated numeric history immediately")
    equal(attempts(1175), 9, "a fresh opening increases a migrated mount snapshot immediately")
    local sources = {}
    for id, spell in pairs(islandSpells) do
        local reward = catalog.attemptStages[id].reward
        sources[id] = setmetatable({ attempts = 20, found = true, realAttempts = 18 }, {
            __index = { type = "MOUNT", method = "USE", itemId = reward.item, spellId = spell },
        })
    end
    sources.duplicate = { type = "MOUNT", method = "USE", itemId = 166467, spellId = 288721, attempts = 24 }
    sources.wrongItem = { type = "MOUNT", method = "USE", itemId = 166466, spellId = 288721, attempts = 100 }
    Rarity.db.profile.groups = { mounts = sources }
    local firstIslands = run()
    equal(firstIslands.count, 9, "all nine Island Expedition mounts can import their Rarity history")
    equal(firstIslands.updated, 7, "smaller snapshots preserve the previously imported history")
    equal(firstIslands.skipped, 1, "a mismatched reward item is skipped")
    for id in pairs(islandSpells) do
        local expected = id == 1212 and 26 or id == 1176 and 31 or 20
        local count, cumulative, perAttempt = attempts(id)
        equal(count, expected, "shared island history for mount " .. id)
        equal(perAttempt, 0.01, "shared chance follows the mount's Rarity rate")
        assert(math.abs(cumulative - (1 - 0.99 ^ expected)) < 0.000000001, "chance follows the shared count")
        equal(atlas.acquisitionAttempts("mount:" .. id), nil, "mixed history cannot supply acquisition attempts")
    end
    equal(attempts(1208), nil, "buying a mount for dubloons has no shared count")
    local replay = run()
    equal(replay.updated, 0, "the same mixed snapshots do not add attempts")
    equal(replay.unchanged, 9, "the same mixed snapshots match all nine mounts")

    local previousInstance = GetInstanceInfo
    local function finishIsland(map)
        GetInstanceInfo = function() return "Island", "scenario", 0, nil, nil, nil, nil, map end
        trackingEvents.ISLAND_COMPLETED("ISLAND_COMPLETED", map)
    end
    finishIsland(1879)
    equal(attempts(1212), 27, "a new completion adds to Rarity history for the thunderscale")
    equal(attempts(1178), 21, "the same completion adds to the hound's history")
    openJorundall()
    equal(attempts(1212), 28, "a new eligible salvage opening adds to the same count")
    equal(attempts(1178), 21, "an unrelated salvage opening does not increase the hound's count")
    sources[1212].attempts = 27
    equal(run().updated, 0, "Rarity's matching new events do not count twice")
    equal(attempts(1212), 28, "a partially overlapping snapshot preserves the extra local attempt")
    sources[1212].attempts = 32
    equal(run().updated, 1, "a larger snapshot updates only its mount")
    equal(attempts(1212), 32, "larger Rarity snapshots reconcile by their maximum possible overlap")

    local removed = "Player-island-alt"
    MountAtlasAccountDB.characters[removed] = { islandExpeditionCompletions = 2 }
    equal(attempts(1178), 23, "a second character adds to the shared account total")
    sources[1178].attempts = 23
    equal(run().updated, 0, "the imported history can overlap both characters' runs")
    assert(atlas.removeAccountCharacter(removed))
    equal(attempts(1178), 23, "removing a character preserves Rarity's account history")
    finishIsland(1813)
    GetInstanceInfo = previousInstance
    equal(attempts(1178), 24, "removing a character does not consume the next known local attempt")
    equal(attempts(1212), 33, "another completion adds to the updated Rarity snapshot")
    equal(atlas.islandExpeditionCompletions(), 6, "mixed history does not increase the raw expedition count")
    equal(atlas.rawStageAttempts(legacyKey), 3, "mixed history does not increase the raw salvage count")
    assert(atlas.clearRarityImport())
    equal(attempts(1212), 9, "clearing Rarity retains only local expeditions and eligible openings")
    equal(attempts(1178), 6, "clearing Rarity retains the hound's local expeditions")
end
stageEvent("QUEST_TURNED_IN", 74905)
checkEventAttempts(1735, 0)
openContainer(205368)
checkEventAttempts(1735, 1)
openContainer(128670)
checkEventAttempts(769, 1)
openContainer(54537)
openContainer(54537)
checkEventAttempts(2328, 1)
time = time + 3600
openContainer(54537)
checkEventAttempts(2328, 2)

local difficulty = 1
function GetInstanceInfo() return "Dungeon", "party", difficulty end
stageEvent("ENCOUNTER_END", 343, "Timewalking boss", 1, 5, 1)
difficulty = 24
stageEvent("ENCOUNTER_END", 343, "Timewalking boss", 24, 5, 0)
checkEventAttempts(781, 0)
stageEvent("ENCOUNTER_END", 343, "Timewalking boss", 24, 5, 1)
stageEvent("BOSS_KILL", 343, "Timewalking boss")
checkEventAttempts(781, 1)

local shalewing = { type = "MOUNT", method = "USE", spellId = 408651, itemId = 205204, attempts = 8 }
Rarity.db.profile.groups = { mounts = { shalewing } }
equal(run().updated, 1, "Rarity container openings import into the event counter")
checkEventAttempts(1735, 8)
openContainer(205374)
checkEventAttempts(1735, 9)
shalewing.attempts = 9
equal(run().updated, 0, "an overlapping Rarity opening is not counted again")
checkEventAttempts(1735, 9)

local previousMountInfo = C_MountJournal.GetMountInfoByID
C_MountJournal.GetMountInfoByID = function(id)
    if id == ascendedID then return ascended.name, 342335, nil, nil, nil, nil, nil, nil, nil, nil, false end
    return previousMountInfo(id)
end
atlas.L = function(s) return s end
atlas.getLocale = function() return "enUS" end
local cacheMessages = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) cacheMessages[#cacheMessages + 1] = message end }
stageEvent("PLAYER_ENTERING_WORLD")

-- Rarity CE DB/Mounts/Shadowlands.lua and LOOT_READY SPECIAL handler.
local cache = { type = "MOUNT", method = "SPECIAL", spellId = 342335, itemId = 183741, attempts = 3 }
Rarity.db.profile.groups = { mounts = { [ascended.name] = cache } }
local function afterNativeCache(instance)
    lootSource = "GameObject-0-1-2-3-354175-" .. instance
    stageEvent("LOOT_READY")
    stageEvent("LOOT_OPENED", true, false)
    stageEvent("LOOT_CLOSED")
end
local function cacheAttempts(raw, expected, message)
    equal(atlas.rawStageAttempts(ascendedKey), raw, "local cache attempts")
    local rate, chance, attempts = atlas.dropProbability(ascended)
    equal(rate, .05, "cache per-attempt chance")
    equal(chance, 1 - .95 ^ expected, "cache cumulative probability")
    equal(attempts, expected, "merged cache attempts")
    if message then assert(cacheMessages[#cacheMessages]:find(message, 1, true), "incorrect cache chat message") end
end

afterNativeCache("000000001")
cacheAttempts(1, 1, "5.00%")
equal(#cacheMessages, 1, "a Rarity profile does not implicitly install its older attempts")
equal(cache.attempts, 3, "native attempt leaves Rarity alone")
assert(MountAtlasAccountDB.rarityImport.entries[ascendedKey] == nil, "cache history is opt-in")

equal(run().updated, 1, "manually importing adds the shared history floor for the chest stage")
equal(MountAtlasAccountDB.rarityImport.entries[ascendedID], nil, "SPECIAL import only updates the stage key")
cacheAttempts(1, 3)
equal(#cacheMessages, 1, "history import emits no attempt chat message")
cache.attempts = 4 -- Rarity may observe this opening before PawAtlas.
afterNativeCache("000000002")
cacheAttempts(2, 4, "18.55%")
equal(run().updated, 0, "reimport does not double-credit the shared opening")

afterNativeCache("000000003")
cache.attempts = 5 -- Rarity may also observe this opening after PawAtlas.
cacheAttempts(3, 5, "22.62%")
equal(run().updated, 0, "a Rarity update after PawAtlas also overlaps on reimport")
equal(#cacheMessages, 3, "each opening writes its own PawAtlas message once")

print("PawAtlas Rarity import passed: account history, idempotence, profile changes, skips, reset, cages, eggs, collections, events and chest attempts")
