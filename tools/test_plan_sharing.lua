-- Run from the repository root: lua5.1 tools/test_plan_sharing.lua
assert(_VERSION == "Lua 5.1", "This test requires Lua 5.1")

local frames = {}
function CreateFrame()
    local frame = {
        events = {},
        RegisterEvent = function(self, event) self.events[event] = true end,
        RegisterUnitEvent = function(self, event) self.events[event] = true end,
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

local function fire(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.onEvent(frame, event, ...) end
    end
end

function UnitGUID() return "Player-fixture" end
function GetServerTime() return 1000 end
function GetTime() return 1 end
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
    achievementRouteChoices = function() end,
    verifiedRewardDropRoute = function() end,
    extraSaddlePurchase = function() end,
    extraCovenantPurchase = function() end,
    refreshBossLockouts = function() end,
    isWarbandCharacterHidden = function() return false end,
}
local refreshes, trackerRefreshes = 0, 0
local catalogByID = {}
for _, mount in ipairs(atlas.mounts) do catalogByID[mount.id] = mount end
function atlas.mountByID(id) return catalogByID[id] end
local sources = {
    [2] = { id = 2, spell = 102, kind = "Добыча", indexed = true },
    [3] = { id = 3, spell = 103, kind = "Квест", indexed = true },
    [6] = { id = 6, spell = 106, kind = "Акция", indexed = true },
    [7] = { id = 7, spell = 107, kind = "Подземелье", indexed = true },
    [8] = { id = 8, spell = 108, kind = "Добыча", indexed = true },
}
function atlas.resolveJournalMount(id) return sources[id] end
function atlas.queuePlanBrokerRefresh() refreshes = refreshes + 1 end
function atlas.queueExpeditionTrackerRefresh() trackerRefreshes = trackerRefreshes + 1 end
for _, path in ipairs({ "Libs/LibStub/LibStub.lua", "Libs/AceSerializer-3.0/AceSerializer-3.0.lua",
    "Core/WarbandPlan.lua", "Core/PlanSharing.lua", "Core/Sources.lua" }) do assert(loadfile(path))("PawAtlas", atlas) end
local serializer = LibStub("AceSerializer-3.0")
local function payload(csv, name, version)
    return serializer:Serialize("PawAtlasPlan", version or 1, name or "Shared", csv)
end

MountAtlasDB = { plan = { [8] = true, [9] = true } }
MountAtlasAccountDB = {
    plan = { ["1"] = true, ["2"] = true, ["999"] = true },
    planOrder = { "2", "1", "2", "999" }, planRemoved = { ["9"] = true },
    characters = { ["Player-fixture"] = { private = "private fixture character data" }, ["Player-alt"] = {} },
    settings = { plannerCharacterGUID = "Player-alt" },
}
local db = MountAtlasAccountDB
assert(atlas.activePlanID() == "personal" and #atlas.planProfiles() == 1)
assert(#atlas.planTargets() == 2 and MountAtlasDB.planMigrated == nil, "read migrated legacy personal data")
fire("PLAYER_ENTERING_WORLD", true, false)
assert(db.settings.plannerCharacterGUID == "Player-fixture", "login selects the current character over the previous alt")
atlas.selectPlanCharacter("Player-alt")
fire("PLAYER_ENTERING_WORLD", false, false)
assert(db.settings.plannerCharacterGUID == "Player-alt", "zoning preserves the manual character selection")
atlas.selectPlanCharacter(nil)
assert(db.settings.plannerCharacterGUID == nil, "the whole warband remains selectable")
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

do
    local alternative = sources[6]
    alternative.kind = "Магазин"
    assert(not atlas.canAddMountToPlan(alternative))
    atlas.blackMarketMounts = { [6] = { spell = alternative.spell } }
    assert(atlas.canAddMountToPlan(alternative), "a current in-game route may supplement the shop")
    assert(#assert(atlas.previewPlanImport(payload("6"))).ids == 1)
    atlas.blackMarketMounts = nil
    alternative.kind = "Акция"
    sources[3].indexed = false
    local cold, reason = atlas.previewPlanImport(payload("2,3"))
    assert(cold == nil and reason == "journal", "pending source data must not silently drop an import target")
    sources[3].indexed = true
    assert(#assert(atlas.previewPlanImport(payload("2,3"))).ids == 2)
end

local first, imported = atlas.importPlan(input, "  Набег  ")
assert(first and imported == 2)
assert(not atlas.movePlanProfile(first, "personal", false))
local second = assert(atlas.importPlan(input, "Набег"))
assert(first ~= second and atlas.activePlanID() == second)
local descriptors = atlas.planProfiles()
assert(#descriptors == 3 and descriptors[2].name == "Набег" and descriptors[3].name == "Набег")
assert(atlas.previewPlanImport(assert(atlas.exportPlan(first))).name == "Набег")
local entries = db.planProfiles.entries
do
    local function assertOrder(...)
        local profiles, expected = atlas.planProfiles(), { ... }
        assert(#profiles == #expected + 1 and profiles[1].id == "personal")
        for index, id in ipairs(expected) do
            assert(profiles[index + 1].id == id and db.planProfiles.order[index] == id)
        end
    end

    local firstRecord, secondRecord = entries[first], entries[second]
    local nextID = db.planProfiles.nextID
    local brokerBefore, trackerBefore = refreshes, trackerRefreshes
    assert(not atlas.movePlanProfile("personal", second, true))
    assert(not atlas.movePlanProfile(first, "missing", false))
    assert(not atlas.movePlanProfile(first, first, true))
    assert(not atlas.movePlanProfile(first, second, false))
    assertOrder(first, second)
    assert(refreshes == brokerBefore and trackerRefreshes == trackerBefore)

    assert(atlas.movePlanProfile(second, first, false))
    assertOrder(second, first)
    assert(atlas.activePlanID() == second and db.planProfiles.nextID == nextID)
    assert(entries[first] == firstRecord and entries[second] == secondRecord and personalBytes() == personalBefore)
    assert(refreshes == brokerBefore + 1 and trackerRefreshes == trackerBefore + 1)

    local added = assert(atlas.createPlan("Новый план"))
    assertOrder(second, first, added)
    assert(atlas.movePlanProfile(second, added, true))
    assertOrder(first, added, second)
    assert(atlas.renamePlan(added, "Переименованный план"))
    assertOrder(first, added, second)
    local shared = assert(atlas.importPlan(input, "Общий план"))
    assertOrder(first, added, second, shared)
    assert(atlas.deletePlanProfile(added) and atlas.deletePlanProfile(shared) and atlas.selectPlan(second))
    assertOrder(first, second)
end
assert(entries[first].plan ~= entries[second].plan and entries[first].planOrder ~= entries[second].planOrder)
assert(entries[first].plan ~= db.plan and entries[first].planOrder ~= db.planOrder)
assert(atlas.isPlanned({ id = 3 }, second) and not atlas.isPlanned({ id = 3 }))
assert(atlas.isPlanned({ id = 1 }) and not atlas.isPlanned({ id = 1 }, second))
assert(#atlas.planTargets(false, second) == 2)
assert(atlas.movePlanTarget(3, 2, false, second))
assert(atlas.planTargets(false, second)[1].id == 3 and atlas.planTargets(false, first)[1].id == 2)
assert(atlas.togglePlan({ id = 7 }, second) and not atlas.isPlanned({ id = 7 }, first))
assert(not atlas.togglePlan({ id = 6 }, second) and not atlas.isPlanned({ id = 6 }, second))
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
sources[3].indexed = false
assert(not atlas.togglePlan({ id = 3 }, created) and not atlas.isPlanned({ id = 3 }, created),
    "a saved target can be removed while its source is unavailable")
assert(not atlas.togglePlan({ id = 3 }, created) and not atlas.isPlanned({ id = 3 }, created))
sources[3].indexed = true
assert(atlas.togglePlan({ id = 3 }, created) and atlas.isPlanned({ id = 3 }, created))
do
    local store, entry = db.planProfiles, entries[created]
    local order, goals, goalOrder, nextID = store.order, entry.plan, entry.planOrder, store.nextID
    local brokerBefore, trackerBefore = refreshes, trackerRefreshes
    assert(select(2, atlas.renamePlan("personal", "Новое имя")) == "profile")
    assert(select(2, atlas.renamePlan("missing", "Новое имя")) == "profile")
    for _, name in ipairs({ "", "   ", "|Hbad", ("Я"):rep(49) }) do
        assert(select(2, atlas.renamePlan(created, name)) == "name")
    end
    assert(entry.name == "Мой маршрут" and refreshes == brokerBefore and trackerRefreshes == trackerBefore)
    assert(atlas.renamePlan(created, "  Новый маршрут  ") and atlas.activePlanID() == created)
    assert(store.order == order and order[#order] == created and entries[created] == entry and store.nextID == nextID)
    assert(entry.plan == goals and entry.planOrder == goalOrder and goalOrder[1] == "3" and goals["3"])
    assert(personalBytes() == beforeCreate and entries[activeBeforeCreate].name == "Набег")
    assert(refreshes == brokerBefore + 1 and trackerRefreshes == trackerBefore + 1)
    assert(atlas.previewPlanImport(assert(atlas.exportPlan(created))).name == "Новый маршрут")
    assert(atlas.renamePlan(created, "Новый маршрут") and refreshes == brokerBefore + 1)
end
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
    local originalCreateFrame, originalCreateColor, originalUI, originalL = CreateFrame, CreateColor, atlas.ui, atlas.L
    local originalPreview = atlas.previewPlanImport
    local edits, labels, buttons, previewCalls = {}, {}, {}, 0
    local methods = {}
    for _, method in ipairs({ "SetToplevel", "EnableMouse", "Raise", "SetPoint", "ClearAllPoints",
        "SetMultiLine", "SetAutoFocus", "SetTextColor", "SetMaxLetters", "SetMaxLines", "SetJustifyH", "SetJustifyV", "HighlightText",
        "SetAlpha", "setActive", "SetVertexColor", "SetColorTexture", "SetAllPoints", "SetTexture",
        "SetTexCoord", "AddMaskTexture", "SetDrawLayer", "SetGradient" }) do methods[method] = function() end end
    function methods:GetParent() return self.parent end
    function methods:SetFrameLevel(value) self.level = value end
    function methods:GetFrameLevel() return self.level or 1 end
    function methods:SetScript(event, callback) self.scripts[event] = callback end
    function methods:HookScript(event, callback)
        local previous = self.scripts[event]
        self.scripts[event] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
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
    function methods:CreateTexture() return widget("Texture", self) end
    function methods:CreateMaskTexture() return self:CreateTexture() end
    CreateFrame = function(kind, _, parent) return widget(kind, parent) end
    CreateColor = function(...) return { ... } end
    atlas.ui = {
        gold = {}, paper = {}, muted = {}, setFont = function() end, fieldSurface = function() end,
        place = function(object, _, x, y, width, height)
            object.x, object.y = x, y
            object:SetSize(width, height)
            return object
        end,
        journalDialog = function(parent, _, width, height)
            local overlay = widget("Frame", parent)
            overlay:Hide()
            local panel = widget("Frame", overlay)
            panel:SetSize(width, height)
            return overlay, panel
        end,
        fill = function(parent) return parent:CreateTexture() end,
        dropdownSurface = function()
            local surface = { widget("Texture") }
            for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                surface[edge] = widget("Texture")
                surface[#surface + 1] = surface[edge]
            end
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
            button.caption = widget("FontString", button)
            button.caption:SetText(text)
            buttons[text] = button
            return button
        end,
    }
    atlas.ui.tab = atlas.ui.action
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
    assert(#edits == 4 and #timers == 0)
    local code, input, name = edits[1], edits[2], edits[3]
    for _, label in ipairs(labels) do
        if label.text == "" and label.parent == input.parent.parent.parent then summary = label end
    end
    assert(summary)
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
    sources[3].indexed = false
    input:SetText(payload("3", "Источник загружается"))
    runTimer()
    assert(#timers == 1 and not buttons["Импортировать"].enabled and summary:GetText() == "",
        "the import dialog waits while a known target's source is loading")
    sources[3].indexed = true
    runTimer()
    assert(#timers == 0 and buttons["Импортировать"].enabled and summary:GetText() ~= "",
        "a pending import revalidates when its source becomes available")
    dialog:Hide()

    local planName, confirmName = edits[4], buttons["Создать план"]
    local profile = { id = previousActive, name = entries[previousActive].name }
    dialog:openName()
    assert(planName:GetText() == "" and planName.focused and not confirmName.enabled)
    buttons["Отмена"].click()
    dialog:openName(profile)
    assert(planName:GetText() == profile.name and planName.focused and confirmName.caption:GetText() == "Переименовать")
    planName:SetText("|Hbad")
    confirmName.click()
    assert(dialog:IsShown() and entries[profile.id].name == profile.name and changed == 1)
    planName:SetText("  Имя из диалога  ")
    planName:GetScript("OnEnterPressed")()
    assert(not dialog:IsShown() and atlas.activePlanID() == profile.id and entries[profile.id].name == "Имя из диалога"
        and changed == 2)
    profile.name = entries[profile.id].name
    dialog:openName(profile)
    planName:SetText("Устаревшее")
    assert(atlas.selectPlan("personal"))
    dialog:closeIfStale(atlas.activePlanID())
    assert(not dialog:IsShown() and entries[profile.id].name == profile.name and changed == 2)
    assert(atlas.selectPlan(previousActive))

    CreateFrame, CreateColor, atlas.ui, atlas.L, atlas.previewPlanImport =
        originalCreateFrame, originalCreateColor, originalUI, originalL, originalPreview
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

do
    local mount = { id = 42, countKey = "target", npcs = { 401, 402 } }
    local attempts = { ["npc:401:daily"] = 1300, ["npc:402:daily"] = 1300 }
    local current = { kills = { target = 4 }, statistics = { [42] = 8 }, planStatus = {}, migrated = true }
    local alt = { kills = { target = 3 }, statistics = { [42] = 7 }, planStatus = { ["42"] = {
        frequency = "daily", opportunities = {
            ["npc:401:daily"] = { state = "attempt", expires = 1400 },
            ["npc:402:daily"] = { state = "available", expires = 1400 },
        },
    } } }
    local characters = { ["Player-fixture"] = current, Alt = alt }
    local settings = { plannerCharacterGUID = "Player-fixture", plannerPinnedCharacters = { ["Player-fixture"] = true } }
    local environment = setmetatable({
        MountAtlasDB = { planMigrated = true, lastAttempts = attempts },
        MountAtlasAccountDB = { characters = characters, settings = settings },
        C_DateAndTime = { GetSecondsUntilDailyReset = function() return 500 end },
    }, { __index = _G })
    local refreshes, tracker, broker = 0, 0, 0
    local warband = {
        mounts = { mount }, killStatistics = {}, lootFrequencies = { [42] = "daily" },
        lootFrequency = function() return "daily" end,
        addTranslations = function() end,
        refreshBossLockouts = function() end,
        refreshDetails = function() refreshes = refreshes + 1 end,
        queueExpeditionStatsRefresh = function() tracker = tracker + 1 end,
        queuePlanBrokerStatsRefresh = function() broker = broker + 1 end,
    }
    for _, path in ipairs({ "Core/Tracking.lua", "Core/WarbandPlan.lua" }) do
        setfenv(assert(loadfile(path)), environment)("PawAtlas", warband)
    end
    local planEvents = frames[#frames]
    local counts = warband.planSummary(mount)
    assert(counts.total == 2 and counts.done == 1 and counts.completedAttempts == 3 and counts.totalAttempts == 4)
    assert(warband.setWarbandCharacterHidden("Player-fixture", true) and warband.isWarbandCharacterHidden("Player-fixture"))
    assert(settings.plannerCharacterGUID == nil and settings.plannerPinnedCharacters["Player-fixture"])
    assert(refreshes == 1 and tracker == 1 and broker == 1, "hiding the selection refreshes visible views")
    assert(warband.setWarbandCharacterHidden("Player-fixture", true) and refreshes == 1, "repeat toggle is idempotent")
    assert(not warband.setWarbandCharacterHidden("Missing", true))
    assert(warband.accountCharacters()[1].guid == "Alt" and #warband.accountCharacters() == 1)
    assert(#warband.accountCharacters(true) == 2 and warband.accountCharacterCount() == 2)
    counts = warband.planSummary(mount)
    assert(counts.total == 1 and counts.done == 0 and counts.completedAttempts == 1 and counts.totalAttempts == 2)
    assert(counts.expires == 1400 and warband.rawKills(mount) == 7 and warband.savedStatisticAttempts(42) == 15)

    -- Login while this character is hidden keeps the entire visible warband selected.
    settings.plannerCharacterGUID = "Alt"
    planEvents.onEvent(planEvents, "PLAYER_ENTERING_WORLD", true)
    assert(settings.plannerCharacterGUID == nil)
    warband.capturePlanSnapshot(true)
    assert(current.planStatus["42"].state == "attempt" and attempts["npc:401:daily"] == 1300)

    assert(warband.setWarbandCharacterHidden("Alt", true))
    counts = warband.planSummary(mount)
    assert(#warband.accountCharacters() == 0 and counts.total == 0 and counts.totalAttempts == 0)
    assert(warband.setWarbandCharacterHidden("Player-fixture", false) and warband.setWarbandCharacterHidden("Alt", false))
    assert(settings.plannerCharacterGUID == nil and characters["Player-fixture"] == current and characters.Alt == alt)
    assert(warband.planSummary(mount).completedAttempts == 3)
    print("PawAtlas warband visibility passed: selection, login, summaries, preserved attempts and snapshots")
end

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
    local camel
    for _, mount in ipairs(testAtlas.rares) do if mount.id == 400 then camel = mount; break end end
    assert(camel and #camel.npcs == 1 and camel.npcs[1] == 50245, "Dormus remains the camel loot source")
    local all, manual = testAtlas.mountLocations(camel), testAtlas.mountLocations(camel, nil, true)
    assert(#all == 51 and #manual == 50, "manual navigation omits Dormus and preserves all figurine points")
    local dormant, identities = false, {}
    for _, point in ipairs(all) do
        if point.npc == 50245 then dormant = point.navigation == false end
    end
    assert(dormant and not testAtlas.sourceNavigationAllowed(camel, 50245), "Dormus manual route is explicitly disabled")
    assert(testAtlas.sourceNavigationAllowed(camel, 50409) and testAtlas.sourceNavigationAllowed(camel, 99999),
        "only explicit manual navigation restrictions apply")
    for _, point in ipairs(manual) do
        assert(point.npc == 50409 and point.map == 249 and testAtlas.hasSourceCoordinates(point), "figurine route retains exact identity and coordinates")
        identities[point.npc .. ":" .. point.map .. ":" .. point.boss] = true
    end
    local identityCount = 0
    for _ in pairs(identities) do identityCount = identityCount + 1 end
    assert(identityCount == 1, "50 figurine points remain one named planner source")
    local waypointCalls = 0
    environment.TomTom = { AddWaypoint = function() waypointCalls = waypointCalls + 1; return {} end }
    local inaccessible = { map=69, npc=50245, x=.5, y=.5, navigation=false }
    assert(testAtlas.addSourceWaypoints({ inaccessible }) == 0, "bulk navigation rejects disabled coordinates")
    assert(testAtlas.openSource({}, inaccessible) == nil and waypointCalls == 0, "single navigation rejects disabled coordinates")
    environment.TomTom = nil
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

do
    local deathroc, aquilon, ratstallion = { id = 1410 }, { id = 1493 }, { id = 804 }
    local ascended = { id = 1426 }
    local now, reset, covenant, reads = 1000, 1500, 1, 0
    local completed = { [64529] = true, [60933] = true }
    local characters = { Current = {}, Kyrian = {}, Venthyr = {}, Legacy = {} }
    local testAtlas = { mounts = { deathroc, aquilon, ratstallion, ascended }, addTranslations = function() end,
        refreshBossLockouts = function() end }
    local environment = setmetatable({
        UnitGUID = function() return "Current" end,
        GetServerTime = function() return now end,
        IsLoggedIn = function() return true end,
        C_Covenants = { GetActiveCovenantID = function() return covenant end },
        C_DateAndTime = { GetSecondsUntilDailyReset = function() return reset - now end },
        C_QuestLog = { IsQuestFlaggedCompleted = function(id)
            assert(id == 61720 or id == 64338 or id == 60977, "planner must read the personal loot flag")
            reads = reads + 1
            return completed[id] == true
        end },
        MountAtlasDB = { planMigrated = true, lastAttempts = {} },
        MountAtlasAccountDB = { characters = characters },
    }, { __index = _G })
    for _, path in ipairs({ "Data/JournalData.lua", "Data/LootSources.lua", "Core/Tracking.lua", "Core/WarbandPlan.lua" }) do
        setfenv(assert(loadfile(path)), environment)("PawAtlas", testAtlas)
    end
    local function state(mount, guid) return testAtlas.planCharacterStatus(mount, guid or "Current") end
    local cacheKey = "stage:mount:1426:daily"
    local oldCache = { frequency = "daily", opportunities = { [cacheKey] = { state = "attempt", expires = reset } } }
    characters.Current.planStatus = { ["1426"] = oldCache }
    characters.Legacy.planStatus = { ["1426"] = oldCache }
    local before = reads
    assert(state(ascended, "Legacy") == "unknown" and reads == before,
        "an offline snapshot without the personal loot flag ID needs an update")
    assert(state(ascended) == "available", "the old council flag must not confirm current cache loot")
    assert(state(deathroc) == "available" and state(aquilon) == "available")
    testAtlas.capturePlanSnapshot(true)
    assert(characters.Current.planStatus["1426"].state == "available", "capture replaces the old council snapshot")
    completed[60977] = true
    assert(state(ascended) == "attempt", "the personal loot flag confirms current cache loot")
    testAtlas.capturePlanSnapshot(true)
    characters.Kyrian.planStatus = characters.Current.planStatus
    characters.Current.planStatus = {}
    completed[60977] = nil
    before = reads
    assert(characters.Kyrian.planStatus["1426"].opportunities[cacheKey].lootQuestID == 60977)
    assert(state(ascended, "Kyrian") == "attempt" and reads == before, "an offline snapshot retains precise loot evidence")
    local key = "npc:180032:daily"
    local old = { state = "available", frequency = "daily", expires = reset,
        opportunities = { [key] = { state = "available", expires = reset } } }
    characters.Legacy.planStatus["1493"] = old

    covenant = 2
    local frame = frames[#frames]
    assert(frame.events.COVENANT_CHOSEN)
    frame.onEvent(frame, "COVENANT_CHOSEN")
    runTimer()
    assert(state(deathroc) == "available" and state(aquilon) == "unknown", "only Aquilon requires Kyrian")
    characters.Venthyr.planStatus = characters.Current.planStatus
    characters.Current.planStatus = {}
    before = reads
    assert(state(aquilon, "Kyrian") == "available" and state(aquilon, "Venthyr") == "unknown")
    assert(state(aquilon, "Legacy") == "unknown" and old.opportunities[key].state == "available")
    old.opportunities[key].state = "attempt"
    assert(state(aquilon, "Legacy") == "attempt" and reads == before,
        "offline results use saved proof and retain legacy completed rolls")

    covenant = nil
    assert(state(aquilon) == "unknown", "an unreadable covenant cannot prove a free roll")
    completed[61720], completed[64338] = true, true
    local deathrocState, _, deathrocReset = state(deathroc)
    local aquilonState, _, aquilonReset = state(aquilon)
    assert(deathrocState == "attempt" and deathrocReset == reset and aquilonState == "attempt" and aquilonReset == reset)
    testAtlas.capturePlanSnapshot(true)
    completed[64338] = nil
    assert(state(aquilon) == "attempt", "a confirmed roll survives a transient flag change")

    now, reset, covenant = reset, 2000, 1
    completed[61720] = nil
    assert(state(deathroc) == "available" and state(aquilon) == "available", "daily reset opens both current character rolls")
    assert(state(aquilon, "Kyrian") == "stale" and state(aquilon, "Legacy") == "stale")
    assert(state(ascended, "Kyrian") == "stale" and oldCache.opportunities[cacheKey].state == "attempt")
    before = reads
    assert(testAtlas.achievementSources[804].candidates[1].id == 11066 and testAtlas.lootFrequency(ratstallion) == "repeatable")
    local ratstallionState, _, ratstallionReset = state(ratstallion)
    assert(ratstallionState == "available" and ratstallionReset == nil and testAtlas.planOpportunityProgress(ratstallion) == nil)
    local summary = testAtlas.planSummary(ratstallion)
    assert(summary.total == 4 and summary.available == 4 and summary.totalAttempts == 0 and reads == before,
        "Ratstallion farming stays available with no daily or weekly attempts")
    print("PawAtlas daily availability passed: Deathroc, Aquilon, covenant changes, offline expiry and repeatable Ratstallion")
end

do
    local now, shared, calls = 1000, false, 0
    local mount = { id=77, kind="Рейд", encounter=999, map=100, difficulties={ [14]=true,[15]=true } }
    local characters = { Current={kills={legacy=5}}, Old={planStatus={ ["77"]={state="boss",expires=1500,updated=900} }} }
    local env = setmetatable({ MountAtlasAccountDB={characters=characters,plan={ ["77"]=true }}, MountAtlasDB={planMigrated=true} }, {__index=_G})
    env.UnitGUID=function() return "Current" end
    env.GetServerTime=function() return now end
    env.GetNumSavedInstances=function() return 0 end
    env.GetSavedInstanceInfo=function() end
    env.GetNumSavedWorldBosses=function() return 0 end
    env.GetSavedWorldBossInfo=function() end
    env.C_DateAndTime={GetSecondsUntilWeeklyReset=function() return 500 end}
    env.C_RaidLocks={GetRedirectedDifficultyID=function(map,id) assert(map==100); return shared and 14 or id end,
        IsEncounterComplete=function(map,encounter,id)
            assert(map==100 and encounter==999,"lock query keeps exact source identity")
            calls=calls+1
            return id==14
        end}
    local locks={mounts={mount},worldBossLocks={},lootFrequency=function() return "weekly" end,
        L=function(value) return value end}
    setfenv(assert(loadfile("Core/Lockouts.lua")),env)("PawAtlas",locks)
    setfenv(assert(loadfile("Core/WarbandPlan.lua")),env)("PawAtlas",locks)
    local rows=locks.bossDifficultyLockouts(mount)
    assert(#rows==2 and rows[1].state=="unknown" and rows[2].state=="unknown","unloaded raid data remains unknown")
    locks.capturePlanSnapshot(true)
    local saved=characters.Current.planStatus["77"]
    assert(saved.state=="available" and #saved.difficultyStates==2,"aggregate status preserves remaining difficulty")
    assert(saved.difficultyStates[1].state=="boss" and saved.difficultyStates[2].state=="available","independent mode locks remain separate")
    assert(calls==2,"snapshot queries each independent lock once")
    local checks, classify = 0, locks.isBossLockoutSource
    locks.isBossLockoutSource = function(source)
        if source.id == 78 then checks = checks + 1 end
        return classify(source)
    end
    locks.mounts[#locks.mounts+1] = { id = 78 }
    locks.journalSourceRevision = 1
    locks.capturePlanSnapshot(true)
    locks.capturePlanSnapshot(true)
    assert(checks == 1, "a journal update reclassifies sources once and subsequent snapshots skip unrelated mounts")
    assert(characters.Current.kills.legacy==5 and #characters.Current.planStatus["77"].difficultyStates==2,
        "repeated capture preserves history and keeps an idempotent snapshot shape")
    local old=locks.bossDifficultyLockouts(mount,nil,"Old")
    assert(old[1].state=="unknown" and old[2].state=="unknown","old aggregate snapshots do not invent per-mode history")
    characters.Saved={planStatus={ ["77"]=saved }}
    local before=calls
    local offline=locks.bossDifficultyLockouts(mount,nil,"Saved")
    assert(offline[1].state=="boss" and offline[2].state=="available" and calls==before,"offline modes use the saved snapshot only")
    now=1600
    offline=locks.bossDifficultyLockouts(mount,nil,"Saved")
    assert(offline[1].state=="unknown" and offline[1].stale and saved.difficultyStates[1].state=="boss",
        "expired offline locks become unknown without rewriting saved history")
    now,shared=1000,true
    rows=locks.bossDifficultyLockouts(mount)
    assert(#rows==1 and rows[1].shared and not rows[1].independent and #rows[1].difficultyIDs==2,
        "redirected difficulties share one lock rather than two independent attempts")
    env.C_RaidLocks.GetRedirectedDifficultyID=nil
    rows=locks.bossDifficultyLockouts(mount)
    assert(#rows==2 and rows[1].state=="unknown" and rows[1].independent==nil,"missing redirect API cannot promise independent attempts")
    print("PawAtlas raid modes passed: independent locks, redirects, old/new snapshots, repeated capture and offline expiry")
end
