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

do
    local originalCreateFrame, originalUI, originalL = CreateFrame, atlas.ui, atlas.L
    local originalPreview = atlas.previewPlanImport
    local edits, labels, buttons, previewCalls = {}, {}, {}, 0
    local methods = {}
    for _, method in ipairs({ "SetToplevel", "EnableMouse", "Raise", "SetPoint", "ClearAllPoints",
        "SetMultiLine", "SetAutoFocus", "SetTextColor", "SetMaxLetters", "SetMaxLines", "HighlightText",
        "SetAlpha", "setActive", "SetVertexColor" }) do methods[method] = function() end end
    function methods:GetParent() return self.parent end
    function methods:SetFrameLevel(value) self.level = value end
    function methods:GetFrameLevel() return self.level or 1 end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:GetScript(event) return self.scripts[event] end
    function methods:SetShown(value)
        if self.shown == value then return end
        self.shown = value
        if not value and self.scripts.OnHide then self.scripts.OnHide(self) end
    end
    function methods:Show() self:SetShown(true) end
    function methods:Hide() self:SetShown(false) end
    function methods:IsShown() return self.shown end
    function methods:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
    function methods:SetSize(width, height) self.width, self.height = width, height end
    function methods:SetWidth(value) self.width = value end
    function methods:SetHeight(value) self.height, self.heightWrites = value, (self.heightWrites or 0) + 1 end
    function methods:GetHeight() return self.height end
    function methods:SetScrollChild(value) self.child = value end
    function methods:GetVerticalScroll() return self.scroll or 0 end
    function methods:SetVerticalScroll(value) self.scroll = value end
    function methods:GetText() return self.text or "" end
    function methods:SetText(value)
        self.text = value
        if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
    end
    function methods:SetFocus() self.focused = true end
    function methods:ClearFocus() self.focused = false end
    function methods:SetEnabled(value) self.enabled = value end
    local function widget(kind, parent)
        local object = setmetatable({ parent = parent, scripts = {}, shown = true }, { __index = methods })
        if kind == "EditBox" then edits[#edits + 1] = object end
        return object
    end
    CreateFrame = function(kind, _, parent) return widget(kind, parent) end
    atlas.ui = {
        gold = {}, paper = {}, muted = {}, setFont = function() end, fieldSurface = function() end,
        place = function(object, _, x, y, width, height)
            object.x, object.y = x, y
            object:SetSize(width, height)
            return object
        end,
        surface = function()
            local surface = {}
            for index = 1, 9 do surface[index] = widget("Texture") end
            return surface
        end,
        text = function(parent, x, y, _, _, _, text)
            local label = widget("FontString", parent)
            label.x, label.y, label.text = x, y, text
            labels[#labels + 1] = label
            return label
        end,
        action = function(parent, _, _, _, _, text, _, callback)
            local button = widget("Button", parent)
            button.click = callback
            buttons[text] = button
            return button
        end,
    }
    atlas.L = function(text, ...) return string.format(text, ...) end
    atlas.previewPlanImport = function(value)
        previewCalls = previewCalls + 1
        return originalPreview(value)
    end
    assert(loadfile("UI/PlanSharing.lua"))("PawAtlas", atlas)
    local window = widget("Frame")
    local parent = widget("Frame", window)
    local changed, summary = 0
    local dialog = atlas.makePlanSharing(parent, function() changed = changed + 1 end)
    for _, label in ipairs(labels) do if label.y == 237 then summary = label end end
    assert(summary and #edits == 4 and #timers == 0)
    local code, input, name = edits[1], edits[2], edits[3]
    local function notify() input:GetScript("OnTextChanged")(input, false) end
    local function rename(value)
        name.text = value
        name:GetScript("OnTextChanged")(name, true)
    end
    local function openImport()
        dialog:open({ id = "personal", name = "Личный план" })
        assert(code:GetText() == atlas.exportPlan("personal"))
        buttons["Импорт"].click()
    end
    openImport()
    input:SetText(payload("3", "Предложенное"))
    for _ = 1, 5 do notify() end
    assert(#timers == 1 and not buttons["Импортировать"].enabled and summary:GetText() == "",
        "identical layout notifications must preserve the pending validation timer")
    runTimer()
    assert(previewCalls == 1 and buttons["Импортировать"].enabled and summary:GetText() ~= "")
    rename("Мой импорт")
    local validSummary = summary:GetText()
    for _ = 1, 5 do notify() end
    assert(#timers == 0 and previewCalls == 1 and buttons["Импортировать"].enabled
        and summary:GetText() == validSummary and name:GetText() == "Мой импорт",
        "identical notifications must preserve a valid preview and a manually edited name")

    input:SetText(payload("3", "Устаревшее"))
    input:SetText(export)
    assert(#timers == 2 and summary:GetText() == "" and not buttons["Импортировать"].enabled)
    table.remove(timers, 1)()
    assert(previewCalls == 1 and summary:GetText() == "" and not buttons["Импортировать"].enabled,
        "a changed input must cancel the older validation")
    runTimer()
    local expected = assert(originalPreview(export))
    assert(previewCalls == 2 and #expected.ids > 0 and buttons["Импортировать"].enabled
        and name:GetText() == "Мой импорт", "personal-plan exports validate without overwriting a manual name")
    local beforeDialogImport, previousActive = personalBytes(), atlas.activePlanID()
    buttons["Импортировать"].click()
    local dialogProfile = atlas.activePlanID()
    assert(dialogProfile ~= previousActive and entries[dialogProfile].name == "Мой импорт"
        and #atlas.planTargets(false, dialogProfile) == #expected.ids and changed == 1,
        "the dialog imports an own personal-plan export as a named separate profile")
    assert(personalBytes() == beforeDialogImport and db.plan == personalPlan and db.planOrder == personalOrder)
    assert(atlas.deletePlanProfile(dialogProfile) and atlas.selectPlan(previousActive))

    local beforeReopen = previewCalls
    openImport()
    input:SetText(export)
    rename("Повторный импорт")
    dialog:Hide()
    dialog:Show()
    buttons["Импорт"].click()
    assert(#timers == 2, "reopening the same input must schedule a fresh validation")
    table.remove(timers, 1)()
    assert(previewCalls == beforeReopen, "a hidden dialog's pending timer must remain stale after reopening")
    runTimer()
    assert(previewCalls == beforeReopen + 1 and buttons["Импортировать"].enabled and summary:GetText() ~= ""
        and name:GetText() == "Повторный импорт", "the same string revalidates when the import dialog reopens")

    local scroll, cursor = input:GetParent(), input:GetScript("OnCursorChanged")
    scroll:SetVerticalScroll(100)
    local heightWrites = input.heightWrites or 0
    cursor(input, 0, -110, 1, 15)
    assert(scroll:GetVerticalScroll() == 100, "a visible caret must not reset the current scroll position")
    cursor(input, 0, -60, 1, 15)
    assert(scroll:GetVerticalScroll() == 60, "a caret above the viewport scrolls upward")
    cursor(input, 0, -160, 1, 15)
    assert(scroll:GetVerticalScroll() == 175 - scroll:GetHeight(), "a caret below the viewport scrolls downward")
    assert((input.heightWrites or 0) == heightWrites, "caret movement must not resize the multiline edit box")
    dialog:Hide()
    CreateFrame, atlas.ui, atlas.L, atlas.previewPlanImport = originalCreateFrame, originalUI, originalL, originalPreview
end

for _ = 2, 20 do assert(atlas.importPlan(payload("3"))) end
assert(#atlas.planProfiles() == 21 and select(2, atlas.importPlan(payload("3"))) == "profiles_limit")
assert(select(2, atlas.createPlan("Лимит")) == "profiles_limit")
local store = db.planProfiles
store.version = 99
assert(atlas.activePlanID() == "personal" and select(2, atlas.importPlan(payload("3"))) == "profiles_version")
assert(db.planProfiles == store and store.version == 99)
assert(select(2, atlas.createPlan("Версия")) == "profiles_version" and db.planProfiles == store)
print("PawAtlas plan sharing passed: isolated profiles, dialog validation, ordered transfer, revalidation, limits and acquisition")

-- Faction alternatives use the selected character's identity, including old
-- per-NPC snapshots. Their existing attempt keys must remain independent.
do
    local faction, now, completed = "Horde", 1000, {}
    local testAtlas = { L = function(text, ...) return text:format(...) end, addTranslations = function() end }
    local environment = setmetatable({
        UnitGUID = function() return "Player-faction" end,
        UnitFactionGroup = function() return faction end,
        GetServerTime = function() return now end,
        IsLoggedIn = function() return true end,
        C_DateAndTime = { GetSecondsUntilDailyReset = function() return 500 end },
        C_QuestLog = { IsQuestFlaggedCompleted = function(id) return completed[id] == true end },
        MountAtlasDB = { planMigrated = true, lastAttempts = {}, kills = {} },
        MountAtlasAccountDB = { characters = {} },
    }, { __index = _G })
    environment._G = environment
    for _, path in ipairs({ "Data/Rares.lua", "Data/JournalData.lua", "Data/LootSources.lua",
        "Core/Tracking.lua", "Core/WarbandPlan.lua", "Core/Sources.lua" }) do
        setfenv(assert(loadfile(path)), environment)("PawAtlas", testAtlas)
    end
    local characters = environment.MountAtlasAccountDB.characters
    testAtlas.currentAttemptCharacter()
    assert(characters["Player-faction"].faction == "Horde", "current faction is saved for offline views")
    faction = "Alliance"
    testAtlas.currentAttemptCharacter()
    assert(characters["Player-faction"].faction == "Alliance", "faction change updates existing character")
    faction = nil
    assert(testAtlas.characterFaction() == nil, "unavailable live faction must not reuse a possibly stale identity")
    testAtlas.currentAttemptCharacter()
    assert(characters["Player-faction"].faction == "Alliance", "unavailable API does not erase saved faction")
    faction = "Horde"
    for _, mount in ipairs(testAtlas.rares) do
        if mount.id == 2751 or mount.id == 2827 then
            local function key(npc) return testAtlas.lootOpportunityKey(mount, npc, "daily") end
            assert(key(257199) ~= key(257231), "faction alternatives must not merge loot keys")
            for _, side in ipairs({ "Horde", "Alliance" }) do
                faction, completed = side, {}
                local wanted = side == "Horde" and 257199 or 257231
                local other = side == "Horde" and 257231 or 257199
                local progress = testAtlas.planOpportunityProgress(mount)
                assert(progress.totalAttempts == 20 and progress.availableAttempts == 20, "one accessible faction source")
                local seen = {}
                for _, entry in ipairs(progress.entries) do
                    assert(#entry.npcs == 1, "unrelated rares stay independent")
                    seen[entry.npc] = true
                end
                assert(seen[wanted] and not seen[other], "progress follows active faction")
                seen = {}
                for _, point in ipairs(testAtlas.mountLocations(mount, "Player-faction")) do
                    assert(point.npc ~= other, "navigation must omit the opposite faction source")
                    if point.npc then seen[point.npc] = true end
                end
                assert(seen[wanted], "navigation retains own faction source")
                completed[94461] = true
                progress = testAtlas.planOpportunityProgress(mount)
                assert(progress.completedAttempts == 1 and progress.availableAttempts == 19, "shared quest counts the accessible NPC once")
                completed = {}
                local attempts = { [key(wanted)] = 1500, [key(other)] = 1500 }
                environment.MountAtlasDB.lastAttempts = attempts
                assert(testAtlas.planOpportunityProgress(mount).completedAttempts == 1, "old local NPC marks are not duplicated")
                assert(attempts[key(other)] == 1500, "opposite NPC history is preserved")
                environment.MountAtlasDB.lastAttempts = {}

                local status = { frequency = "daily", updated = 950, expires = 1500, state = "partial", opportunities = {} }
                for _, npc in ipairs(mount.npcs) do
                    status.opportunities[key(npc)] = { state = "available", expires = 1500 }
                end
                status.opportunities[key(wanted)].state = "attempt"
                status.opportunities[key(other)].state = "attempt"
                characters.Alt = { faction = side, planStatus = { [tostring(mount.id)] = status } }
                faction = side == "Horde" and "Alliance" or "Horde"
                progress = testAtlas.planOpportunityProgress(mount, "Alt")
                assert(progress.totalAttempts == 20 and progress.completedAttempts == 1, "offline alt uses own faction and old keys")
                for _, point in ipairs(testAtlas.mountLocations(mount, "Alt")) do
                    assert(point.npc ~= other, "offline navigation does not inherit the active faction")
                end
                characters.Alt.faction = nil
                local unknown, missingFaction = testAtlas.planOpportunityProgress(mount, "Alt")
                assert(not unknown and missingFaction, "legacy alt without faction stays unknown")
                assert(testAtlas.planCharacterStatus(mount, "Alt") == "unknown", "old total cannot override missing faction")
                for _, point in ipairs(testAtlas.mountLocations(mount, "Alt")) do
                    assert(not testAtlas.npcSourceFactions[point.npc], "unknown faction cannot select either faction target")
                end
                assert(status.opportunities[key(wanted)].state == "attempt", "reading legacy alt preserves its marks")
                characters.Alt.faction = side
                now = 1600
                progress = testAtlas.planOpportunityProgress(mount, "Alt")
                assert(progress.completedAttempts == 0 and progress.stale, "expired offline marks do not count")
                now = 1000
            end
        end
    end
    local checked = 0
    faction, completed = "Horde", {}
    for _, mount in ipairs(testAtlas.rares) do
        if mount.expansion == "Midnight" and #mount.npcs > 1 then
            local expected = (mount.id == 2751 or mount.id == 2827) and #mount.npcs - 1 or #mount.npcs
            assert(testAtlas.planOpportunityProgress(mount).totalAttempts == expected, "Midnight source counts")
            checked = checked + 1
        end
    end
    assert(checked == 10, "all multi-source Midnight fixtures checked")
    print("PawAtlas faction sources passed: both factions, offline legacy snapshots, expiry, navigation and 10 Midnight mounts")
end
