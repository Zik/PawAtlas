-- Run from the repository root: lua5.1 tools/test_plan_sharing.lua
assert(_VERSION == "Lua 5.1", "This test requires Lua 5.1")

local frames = {}
function CreateFrame()
    local frame = {
        events = {},
        RegisterEvent = function(self, event) self.events[event] = true end,
        UnregisterEvent = function(self, event) self.events[event] = nil end,
        SetScript = function(self, _, handler) self.onEvent = handler end,
    }
    frames[#frames + 1] = frame
    return frame
end

local timers = {}
C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
local function runTimer()
    assert(#timers == 1, "journal retries must coalesce to one callback")
    table.remove(timers, 1)()
end

local function fire(event)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.onEvent(frame, event) end
    end
end

function UnitGUID() return "Player-fixture" end
function GetServerTime() return 1000 end
local owned, missing, journalReads = { [4] = true }, { [1] = true }, {}
local membershipReads = 0
local journal = {
    GetMountIDs = function()
        membershipReads = membershipReads + 1
        return { 1, 2, 3, 4, 5, 6, 7, 8 }
    end,
    GetMountInfoByID = function(id)
        journalReads[id] = (journalReads[id] or 0) + 1
        if missing[id] or id > 8 then return end
        return "Mount " .. id, id + 100, nil, nil, nil, nil, nil, nil, nil, nil, owned[id] == true
    end,
}
C_MountJournal = journal
local atlas = {
    mounts = { { id = 1, name = "One" }, { id = 2, name = "Two" }, { id = 3, name = "Three" },
        { id = 7, name = "Seven" }, { id = 8, name = "Eight" } },
    L = function(text) return text end,
    isExcludedJournalMount = function(id) return id == 5 end,
    legacySourceDetails = function(mount) if mount.id == 6 then return { state = "unavailable" } end end,
    refreshBossLockouts = function() end,
}
local refreshes = 0
function atlas.queuePlanBrokerRefresh() refreshes = refreshes + 1 end
for _, path in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/AceSerializer-3.0/AceSerializer-3.0.lua",
    "Core/WarbandPlan.lua", "Core/PlanSharing.lua" }) do assert(loadfile(path))("PawAtlas", atlas) end
local serializer = LibStub("AceSerializer-3.0")
local function payload(csv, name, version)
    return serializer:Serialize("PawAtlasPlan", version or 1, name or "Shared", csv)
end

MountAtlasDB = { plan = { [8] = true, [9] = true } }
MountAtlasAccountDB = {
    plan = { ["1"] = true, ["2"] = true, ["999"] = true },
    planOrder = { "2", "1", "2", "999" }, planRemoved = { ["9"] = true },
    characters = { ["Player-fixture"] = { private = "private fixture character data" } },
}
local db = MountAtlasAccountDB
assert(atlas.activePlanID() == "personal" and #atlas.planProfiles() == 1)
assert(#atlas.planTargets() == 2 and MountAtlasDB.planMigrated == nil, "read migrated legacy personal data")
fire("PLAYER_ENTERING_WORLD")
assert(db.plan["8"] and not db.plan["9"] and MountAtlasDB.planMigrated)
local reads1, reads8, reads999 = journalReads[1], journalReads[8], journalReads[999]
fire("MOUNT_JOURNAL_SEARCH_UPDATED")
fire("MOUNT_JOURNAL_SEARCH_UPDATED")
assert(journalReads[1] == reads1, "search did reconciliation before the next frame")
runTimer()
assert(journalReads[1] == reads1 + 1 and journalReads[8] == reads8 and journalReads[999] == reads999,
    "only an unreadable journal member should be retried")
assert(membershipReads == 1, "journal membership was re-read after resolving stale IDs")

local function personalBytes()
    return serializer:Serialize(db.plan, db.planOrder, db.planRemoved, db.planMigrations, MountAtlasDB.plan)
end
local personalPlan, personalOrder = db.plan, db.planOrder
local personalBefore = personalBytes()
owned[1] = true
local export = assert(atlas.exportPlan("personal"))
local ok, tag, version, name, csv, extra = serializer:Deserialize(export)
assert(ok and tag == "PawAtlasPlan" and version == 1 and name == "" and not extra)
assert(csv == "2,1,999,8" and not export:find("private", 1, true))
assert(#atlas.planTargets() == 3 and personalBytes() == personalBefore, "read removed a collected personal target")
local localized = atlas.L
atlas.L = function(key) return key == "Личный план" and "Personal plan" or key end
assert(atlas.exportPlan() == export, "personal export contains a localized name")
atlas.L = localized

local input = payload("2,3,3,4,4,5,6,999", "Общий план")
local preview = assert(atlas.previewPlanImport(" \n" .. input .. "\n"))
assert(preview.name == "Общий план" and table.concat(preview.ids, ",") == "2,3")
assert(preview.names[1] == "Mount 2" and preview.names[2] == "Mount 3")
assert(preview.collected == 1 and preview.skipped == 5)
assert(db.planProfiles == nil and personalBytes() == personalBefore)

local first, imported = atlas.importPlan(input, "  Набег  ")
assert(first and imported == 2)
local second = assert(atlas.importPlan(input, "Набег"))
assert(first ~= second and atlas.activePlanID() == second)
local descriptors = atlas.planProfiles()
assert(#descriptors == 3 and descriptors[2].name == "Набег" and descriptors[3].name == "Набег")
assert(atlas.previewPlanImport(assert(atlas.exportPlan(first))).name == "Набег")
local entries = db.planProfiles.entries
assert(entries[first].plan ~= entries[second].plan and entries[first].planOrder ~= entries[second].planOrder)
assert(entries[first].plan ~= db.plan and entries[first].planOrder ~= db.planOrder)
assert(atlas.isPlanned({ id = 3 }, second) and not atlas.isPlanned({ id = 3 }))
assert(atlas.isPlanned({ id = 1 }) and not atlas.isPlanned({ id = 1 }, second))
assert(#atlas.planTargets(false, second) == 2)
assert(atlas.movePlanTarget(3, 2, false, second))
assert(atlas.planTargets(false, second)[1].id == 3 and atlas.planTargets(false, first)[1].id == 2)
assert(atlas.togglePlan({ id = 7 }, second) and not atlas.isPlanned({ id = 7 }, first))
assert(atlas.selectPlan("personal") and atlas.activePlanID() == "personal")
assert(atlas.selectPlan(first) and not atlas.selectPlan("missing"))
assert(not atlas.deletePlanProfile("personal") and atlas.activePlanID() == first)
assert(personalBytes() == personalBefore and db.plan == personalPlan and db.planOrder == personalOrder)

atlas.capturePlanSnapshot(true)
local status = db.characters["Player-fixture"].planStatus
assert(status["1"] and status["3"] and status["7"], "snapshots must include personal and inactive profile targets")
local beforeCompletion = refreshes
assert(atlas.completePlanTarget(2) and not atlas.completePlanTarget(2))
assert(refreshes == beforeCompletion + 1)
assert(db.planRemoved["2"] and not db.plan["2"] and not entries[first].plan["2"] and not entries[second].plan["2"])
assert(entries[first].planOrder[1] == "3" and entries[second].planOrder[1] == "3")
missing[1] = nil
fire("MOUNT_JOURNAL_SEARCH_UPDATED")
fire("MOUNT_JOURNAL_SEARCH_UPDATED")
runTimer()
assert(db.planRemoved["1"] and not db.plan["1"], "journal acquisition did not clean personal plan")
reads1 = journalReads[1]
for _ = 1, 10 do fire("MOUNT_JOURNAL_SEARCH_UPDATED") end
assert(#timers == 0 and journalReads[1] == reads1 and journalReads[8] == reads8
    and journalReads[999] == reads999, "ready journal events still trigger acquisition reconciliation")
assert(atlas.deletePlanProfile(first) and atlas.activePlanID() == "personal" and not entries[first])
assert(atlas.selectPlan(second))

local function rejected(text, reason)
    local result, err = atlas.previewPlanImport(text)
    assert(result == nil and err == reason, "expected " .. reason .. ", got " .. tostring(err))
end
rejected(("x"):rep(32769), "size")
rejected("^1^S" .. (" "):rep(32000) .. "x", "format")
rejected((" "):rep(32768), "format")
rejected(payload("2", "name", 2), "version")
for _, ids in ipairs({ ",1", "1,", "1,,2", "0", "-1", "01", "2147483648", "1e3", "1.5", "1, 2" }) do
    rejected(payload(ids), "id")
end
rejected(payload(("1,"):rep(500) .. "1"), "targets_limit")
rejected(payload("1", ("Я"):rep(49)), "name")
rejected(payload("1", "|cff000000x"), "name")
rejected(payload("1", "bad\nname"), "name")
rejected(payload("1", string.char(0xC0, 0xAF)), "name")
rejected(payload("1", "direction" .. string.char(0xE2, 0x80, 0xAE)), "name")
assert(atlas.previewPlanImport(payload("3", ("Я"):rep(48))).name == ("Я"):rep(48))

local deserialize = serializer.Deserialize
serializer.Deserialize = function() error("untrusted nested input reached AceSerializer") end
rejected("^1^SPawAtlasPlan^N1^SName" .. ("^T"):rep(2000) .. "^^", "format")
serializer.Deserialize = deserialize
rejected(payload("1") .. "^^", "format")
assert(#atlas.previewPlanImport(payload("4,999")).ids == 0)
assert(select(2, atlas.importPlan(payload("4,999"))) == "empty")
assert(#atlas.previewPlanImport(payload("")).ids == 0)
assert(select(2, atlas.importPlan(payload("3"), "|Hbad")) == "name")

local originalActive = atlas.activePlanID()
missing[3] = true
rejected(payload("3"), "journal")
assert(select(2, atlas.importPlan(payload("3"))) == "journal")
missing[3] = nil
C_MountJournal = nil
rejected(payload("3"), "journal")
C_MountJournal = journal
assert(atlas.activePlanID() == originalActive and #atlas.planProfiles() == 2)
local changedAvailability = payload("3,7")
assert(#atlas.previewPlanImport(changedAvailability).ids == 2)
owned[7] = true
assert(select(2, atlas.importPlan(payload("7"))) == "empty", "import reused a stale preview")
local revalidated, count = atlas.importPlan(changedAvailability)
assert(revalidated and count == 1 and entries[revalidated].planOrder[1] == "3")
assert(atlas.deletePlanProfile(revalidated) and atlas.selectPlan(originalActive))

local beforeCreate = personalBytes()
local activeBeforeCreate = atlas.activePlanID()
for _, name in ipairs({ "", "   ", "|Hbad", ("Я"):rep(49) }) do
    assert(select(2, atlas.createPlan(name)) == "name")
end
assert(atlas.activePlanID() == activeBeforeCreate and #atlas.planProfiles() == 2)
C_MountJournal = nil
local created = assert(atlas.createPlan("  Мой маршрут  "))
C_MountJournal = journal
assert(atlas.activePlanID() == created)
assert(db.planProfiles.entries[created].name == "Мой маршрут")
assert(#atlas.planTargets(false, created) == 0 and #db.planProfiles.entries[created].planOrder == 0)
assert(personalBytes() == beforeCreate and db.plan == personalPlan and db.planOrder == personalOrder)
assert(atlas.togglePlan({ id = 3 }, created) and atlas.isPlanned({ id = 3 }, created))
assert(atlas.deletePlanProfile(created) and atlas.activePlanID() == "personal")
assert(atlas.selectPlan(activeBeforeCreate))

assert(atlas.previewPlanImport(export).name == "")
assert(select(2, atlas.importPlan(export)) == "name")
assert(select(2, atlas.importPlan(export, "   ")) == "name")
local renamed = assert(atlas.importPlan(export, "  Маршрут друга  "))
assert(entries[renamed].name == "Маршрут друга")
assert(atlas.deletePlanProfile(renamed) and atlas.selectPlan(activeBeforeCreate))

for _, legacyName in ipairs({ "Личный план", "Personal plan" }) do
    local legacy = assert(atlas.importPlan(payload("3", legacyName)))
    assert(entries[legacy].name == legacyName)
    assert(atlas.deletePlanProfile(legacy) and atlas.selectPlan(activeBeforeCreate))
end

for _ = 2, 20 do assert(atlas.importPlan(payload("3"))) end
assert(#atlas.planProfiles() == 21 and select(2, atlas.importPlan(payload("3"))) == "profiles_limit")
assert(select(2, atlas.createPlan("Лимит")) == "profiles_limit")
local store = db.planProfiles
store.version = 99
assert(atlas.activePlanID() == "personal" and select(2, atlas.importPlan(payload("3"))) == "profiles_version")
assert(db.planProfiles == store and store.version == 99)
assert(select(2, atlas.createPlan("Версия")) == "profiles_version" and db.planProfiles == store)
print("PawAtlas plan sharing passed: isolated profiles, ordered transfer, revalidation, limits and acquisition")
