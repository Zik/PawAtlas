local _, atlas = ...
local loader = CreateFrame("Frame")
local pending

local function activeChat()
    local focused = type(WIM) == "table" and WIM.EditBoxInFocus
    if focused and focused.HasFocus and focused:HasFocus() and focused.IsVisible and focused:IsVisible() then
        return focused, true
    end
    local getter = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
    return getter and getter()
end

local function insertLink(link)
    if type(link) ~= "string" or link == "" then return false end
    local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    -- InsertLink also targets macros and auction searches. With no active chat,
    -- open a chat draft explicitly, as Blizzard's own LinkItem does.
    local chat, external = activeChat()
    if external then
        if not chat.Insert then return false end
        chat:Insert(link)
        return true
    end
    if chat and insert and insert(link) then return true end
    if open then open(link); return true end
    return false
end

function atlas.cancelPendingLink(owner)
    if pending and (not owner or pending.owner == owner) then
        loader:UnregisterEvent(pending.event)
        pending = nil
        loader:SetScript("OnUpdate", nil)
    end
end

local function positiveID(value)
    value = tonumber(value)
    return value and value > 0 and value < math.huge and value == math.floor(value) and value or nil
end

local function itemLink(id)
    if not C_Item or not C_Item.GetItemInfo then return nil end
    return select(2, C_Item.GetItemInfo(id))
end

function atlas.nativeAchievementLink(id)
    local reference = GetAchievementLink and GetAchievementLink(id)
    if type(reference) == "string" and not (issecretvalue and issecretvalue(reference))
        and tonumber(reference:match("|Hachievement:(%d+)[^|]*|h")) == id then return reference end
end

local function awaitLink(id, owner, event)
    local chat = activeChat()
    local request = {
        id = id, owner = owner, chat = chat, event = event,
        text = chat and chat:GetText(), expires = GetTime() + 5,
    }
    pending = request
    loader:RegisterEvent(event)
    loader:SetScript("OnUpdate", function()
        local current = activeChat()
        if GetTime() >= request.expires or (owner and not owner:IsVisible())
            or current ~= chat or (current and current:GetText() ~= request.text)
            or (IsKeyDown and IsKeyDown("ESCAPE")) then
            atlas.cancelPendingLink()
        end
    end)
    C_Timer.After(5, function()
        if pending == request then atlas.cancelPendingLink() end
    end)
end

function atlas.linkItem(itemID, owner)
    atlas.cancelPendingLink()
    local id = positiveID(itemID)
    if not id then return false end
    local link = itemLink(id)
    if link then return insertLink(link) end
    if not C_Item or not C_Item.RequestLoadItemDataByID then return false end
    awaitLink(id, owner, "ITEM_DATA_LOAD_RESULT")
    C_Item.RequestLoadItemDataByID(id)
    return true
end

loader:SetScript("OnEvent", function(_, event, id, success)
    local request = pending
    if not request or request.event ~= event then return end
    local link
    if event == "ITEM_DATA_LOAD_RESULT" then
        if request.id ~= id then return end
        if success then link = itemLink(id) end
    else
        link = atlas.nativeAchievementLink(request.id)
        if not link then return end
    end
    atlas.cancelPendingLink()
    if not link or GetTime() >= request.expires then return end
    if request.owner and not request.owner:IsVisible() then return end
    local chat = activeChat()
    if chat ~= request.chat or (chat and chat:GetText() ~= request.text) then return end
    insertLink(link)
end)

local function mountSpellLink(mount)
    local id = positiveID(type(mount) == "table" and mount.id or mount)
    if not id or not C_MountJournal or not C_Spell or not C_Spell.GetSpellLink then return end
    local _, spellID = C_MountJournal.GetMountInfoByID(id)
    if spellID then return C_Spell.GetSpellLink(spellID) end
end

function atlas.linkMount(mount)
    atlas.cancelPendingLink()
    return insertLink(mountSpellLink(mount))
end

local function insertAttempts(reference, count)
    if not reference or type(count) ~= "number" or count < 0 or count ~= math.floor(count) then return false end
    atlas.cancelPendingLink()
    return insertLink(reference .. " · " .. atlas.L("Попыток: %s", count))
end

function atlas.shareMountAttempts(mount, count)
    if not mount then return false end
    local name = mountSpellLink(mount)
    if not name then
        name = atlas.displayMountName(mount)
        if not name or name == "" then return false end
        name = "[" .. name .. "]"
    end
    return insertAttempts(name, count)
end

function atlas.canShareItemAttempts(progress)
    return progress and progress.item and type(progress.attempts) == "number" and not progress.acquired
        and not (type(progress.required) == "number" and progress.required > 1 and not progress.perAttempt)
end

function atlas.shareItemAttempts(progress)
    if not atlas.canShareItemAttempts(progress) then return false end
    return insertAttempts(atlas.sourceItemReference(progress.item, progress.name), progress.attempts)
end

function atlas.previewMount(mount)
    atlas.cancelPendingLink()
    local id = positiveID(type(mount) == "table" and mount.id or mount)
    if not id or not DressUpMount then return false end
    return DressUpMount(id) == true
end

function atlas.itemPreviewMount(itemID)
    local id = positiveID(itemID)
    local mount = id and C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(id)
    return positiveID(mount)
end

function atlas.mountModifiedClick(mount, button)
    if button and button ~= "LeftButton" then return false end
    if IsModifiedClick and IsModifiedClick("DRESSUP") then
        atlas.previewMount(mount)
        return true
    end
    if IsShiftKeyDown() then atlas.linkMount(mount); return true end
    return false
end

do
    local owner, target, ownsCursor, settingCursor, blocked
    local listener = CreateFrame("Frame")
    local function release()
        if ownsCursor and ResetCursor then
            settingCursor = true
            ResetCursor()
            settingCursor = false
        end
        ownsCursor = false
    end
    local function update()
        local mount = owner and owner:IsVisible() and target and target()
        if not mount or not DressUpMount or not IsModifiedClick or not IsModifiedClick("DRESSUP")
            or (GetCursorInfo and GetCursorInfo()) then release(); return end
        if not ownsCursor and not blocked and SetCursor then
            settingCursor = true
            ownsCursor = SetCursor("INSPECT_CURSOR") == true
            settingCursor = false
        end
    end
    listener:RegisterEvent("MODIFIER_STATE_CHANGED")
    listener:RegisterEvent("CURSOR_CHANGED")
    listener:SetScript("OnEvent", function(_, event, isDefault)
        if event == "CURSOR_CHANGED" then
            if not settingCursor then ownsCursor, blocked = false, not isDefault end
        else update() end
    end)
    function atlas.bindMountPreviewCursor(widget, getMount)
        widget:HookScript("OnEnter", function()
            if owner ~= widget then release() end
            owner, target, blocked = widget, getMount, false
            update()
        end)
        local function leave()
            if owner ~= widget then return end
            release()
            owner, target, blocked = nil, nil, false
        end
        widget:HookScript("OnLeave", leave)
        widget:HookScript("OnHide", leave)
    end
    function atlas.refreshMountPreviewCursor(widget)
        if owner == widget then update() end
    end
end

function atlas.linkSourceName(view, name, place)
    atlas.cancelPendingLink()
    local link
    if place and view and view.journalInstance and EJ_GetInstanceInfo then
        link = select(8, EJ_GetInstanceInfo(view.journalInstance))
    elseif not place and view and view.journalEncounter and EJ_GetEncounterInfo then
        link = select(5, EJ_GetEncounterInfo(view.journalEncounter))
    end
    -- Vendors and open-world NPCs have no journal chat link. Insert their
    -- visible name rather than fabricating a unit GUID or an unsupported link.
    if type(link) ~= "string" or not link:find("|H", 1, true) then link = name end
    return insertLink(link)
end

local function sourceLabel(text)
    if type(text) ~= "string" then return end
    local label = text:match("|h(.-)|h") or text
    return label:match("^%[(.*)%]$") or label
end

local function nativeJournalInstanceID(payload)
    return positiveID(payload:match("^journal:0:(%d+):%d+$") or payload:match("^journal:0:(%d+)$"))
end

function atlas.sourceJournalInstanceID(payload)
    return nativeJournalInstanceID(payload) or positiveID(payload:match("^pawatlasjournal:(%d+)$"))
end

local function journalInstanceReference(id, fallback)
    local label = fallback
    if EJ_GetInstanceInfo then
        local name, _, _, _, _, _, _, reference = EJ_GetInstanceInfo(id)
        local payload = type(reference) == "string" and reference:match("|H([^|]+)|h")
        if payload and nativeJournalInstanceID(payload) == id then return reference end
        if type(name) == "string" and name ~= "" then label = name end
    end

    local linkTypes = Enum and Enum.JournalLinkTypes
    if not linkTypes or not linkTypes.Instance or not C_EncounterJournal or not C_EncounterJournal.GetEncounterJournalLink
        or type(label) ~= "string" or label == "" or label:find("[|\r\n]") then return end
    local reference = C_EncounterJournal.GetEncounterJournalLink(linkTypes.Instance, id, label, 0)
    local payload = type(reference) == "string" and reference:match("|H([^|]+)|h")
    if payload and nativeJournalInstanceID(payload) == id then return reference end
end

function atlas.sourceJournalInstanceLink(id, label)
    id = positiveID(id)
    if not id or type(label) ~= "string" or label == "" or label:find("[|\r\n]") then return end
    local reference = journalInstanceReference(id, label)
    if reference then
        return (reference:gsub("(|h).-|h", function(start) return start .. label .. "|h" end, 1))
    end
    return ("|cff66bbff|Hpawatlasjournal:%d|h%s|h|r"):format(id, label)
end

local function questReference(link, id, displayedText)
    local label = sourceLabel(displayedText or link:match("|h(.-)|h"))
    return atlas.sourceQuestReference(id, label) or link:match("(|Hquest:[^|]+|h.-|h)")
end

local pendingQuestPreview

local function questTitle(id)
    local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
    if not (issecretvalue and issecretvalue(title)) and type(title) == "string" and title ~= "" then return title end
end

local function showQuestTooltip(tooltip, id, payload, title)
    if not tooltip:IsShown() then tooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
    tooltip:ClearLines()
    local displayed = tooltip:SetHyperlink(payload)
    if displayed and tooltip:IsShown() and tooltip:NumLines() > 0 then return true end
    if not title then return false end

    -- Some quests outside the log have no hyperlink tooltip. Their title and
    -- objectives still come from the client once it has loaded the quest.
    if not tooltip:IsShown() then tooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
    tooltip:ClearLines()
    tooltip:AddLine(title, 1, .82, 0, true)
    local objectives = C_QuestLog and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    if not (issecretvalue and issecretvalue(objectives)) and type(objectives) == "table" then
        for _, objective in ipairs(objectives) do
            local text = objective.text
            if not (issecretvalue and issecretvalue(text)) and type(text) == "string" and text ~= "" then
                tooltip:AddLine(text, 1, 1, 1, true)
            end
        end
    end
    tooltip:Show()
    return tooltip:IsShown()
end

local function openQuestReference(link, id, owner, displayedText)
    pendingQuestPreview = nil
    local active = C_QuestLog and C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(id)
    if not (issecretvalue and issecretvalue(active)) and active == true and QuestUtil and QuestUtil.OpenQuestDetails then
        local wasShowing = QuestUtil.IsShowingQuestDetails and QuestUtil.IsShowingQuestDetails(id)
        QuestUtil.OpenQuestDetails(id)
        if wasShowing or (QuestUtil.IsShowingQuestDetails and QuestUtil.IsShowingQuestDetails(id)) then return true end
    end

    local reference = questReference(link, id, displayedText)
    local payload = reference and reference:match("|H([^|]+)|h")
    local tooltip = ItemRefTooltip
    if not payload or not tooltip or not tooltip.SetHyperlink then return false end
    local info = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
    if tooltip:IsShown() and info and info.getterName == "GetHyperlink" and info.getterArgs and info.getterArgs[1] == payload then
        tooltip:Hide()
        return true
    end

    local title = questTitle(id)
    local shown = showQuestTooltip(tooltip, id, payload, title or sourceLabel(reference))
    if shown and not title and QuestEventListener and QuestEventListener.AddCallback then
        local line = tooltip.GetLeftLine and tooltip:GetLeftLine(1)
        local previousText = line and line:GetText()
        local previousInfo = tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo()
        local request = {}
        pendingQuestPreview = request
        QuestEventListener:AddCallback(id, function()
            if pendingQuestPreview ~= request then return end
            pendingQuestPreview = nil
            if not tooltip:IsShown() or (owner and not owner:IsVisible()) then return end
            if tooltip.GetPrimaryTooltipInfo and tooltip:GetPrimaryTooltipInfo() ~= previousInfo then return end
            if line and line:GetText() ~= previousText then return end
            local loadedLink = questReference(link, id, displayedText)
            local loadedPayload = loadedLink and loadedLink:match("|H([^|]+)|h")
            if not loadedPayload then return end
            -- The native ItemRef template hides when given the same hyperlink.
            tooltip:Hide()
            showQuestTooltip(tooltip, id, loadedPayload, questTitle(id) or sourceLabel(loadedLink))
        end)
    end
    return shown
end

local function missionReference(id)
    local link = C_Garrison and C_Garrison.GetMissionLink and C_Garrison.GetMissionLink(id)
    if type(link) ~= "string" then return end
    local payload, missionID, instance = link:match("|H(garrmission:(%d+):(%x+))|h")
    if tonumber(missionID) == id and #instance == 16 then return link, payload end
end

function atlas.openSourceReference(link, owner, displayedText)
    if type(link) ~= "string" then return false end
    local payload = link:match("|H([^|]+)|h") or link
    local questID = positiveID(payload:match("^quest:(%d+):") or payload:match("^quest:(%d+)$"))
    local itemID = positiveID(payload:match("^item:(%d+):") or payload:match("^item:(%d+)$"))
    local missionID = positiveID(payload:match("^pawatlasmission:(%d+)$"))
    if questID then return openQuestReference(link, questID, owner, displayedText) end
    pendingQuestPreview = nil
    local instanceID = atlas.sourceJournalInstanceID(payload)
    if instanceID and atlas.openPlace then
        local err = atlas.openPlace({ journalInstance = instanceID })
        return not err, err
    end
    local reference
    if itemID then
        local textPayload = type(displayedText) == "string" and displayedText:match("|H([^|]+)|h")
        reference = textPayload == payload and displayedText or link:match("(|Hitem:[^|]+|h.-|h)") or itemLink(itemID)
        if not reference then
            local label = sourceLabel(displayedText)
            if label and label ~= "" and not label:find("[|\r\n]") then
                reference = ("|H%s|h[%s]|h"):format(payload, label)
            end
        end
    elseif missionID then
        reference, payload = missionReference(missionID)
        -- A static mission ID can open the Blizzard tooltip without an offer instance.
        if not reference and FloatingGarrisonMission_Toggle and C_Garrison and C_Garrison.GetMissionName
            and C_Garrison.GetMissionName(missionID) then
            FloatingGarrisonMission_Toggle(missionID)
            return true
        end
    end
    if reference and SetItemRef then
        SetItemRef(payload, reference, "LeftButton", owner)
        return true
    end
    return false
end

function atlas.linkSource(link, owner, displayedText)
    atlas.cancelPendingLink()
    if type(link) ~= "string" then return false end
    local payload = link:match("|H([^|]+)|h") or link
    local instanceID = atlas.sourceJournalInstanceID(payload)
    if instanceID then
        return insertLink(journalInstanceReference(instanceID, sourceLabel(displayedText or link:match("|h(.-)|h"))))
    end
    local kind, id = payload:match("^(%a+):(%d+)")
    id = positiveID(id)
    if not id then return false end
    if kind == "item" then return atlas.linkItem(id, owner) end
    if kind == "currency" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
        return insertLink(C_CurrencyInfo.GetCurrencyLink(id))
    end
    if kind == "achievement" and GetAchievementLink then
        local reference = atlas.nativeAchievementLink(id)
        if reference then return insertLink(reference) end
        awaitLink(id, owner, "RECEIVED_ACHIEVEMENT_LIST")
        return true
    end
    if kind == "quest" then
        return insertLink(questReference(link, id, displayedText))
    end
    if kind == "pawatlasmission" then
        return insertLink(missionReference(id) or sourceLabel(displayedText or link:match("|h(.-)|h")))
    end
    return false
end
