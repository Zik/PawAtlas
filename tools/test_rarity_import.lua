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
C_MountJournal = { GetMountInfoByID = function(id) return "Mount " .. id, cageSpells[id] or reportedSpells[id] or 100 + id end }

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

print("PawAtlas Rarity import passed: account history, idempotence, profile changes, skips, reset, cages and collection counters")
