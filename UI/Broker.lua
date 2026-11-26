local _, atlas = ...
local broker = LibStub("LibDataBroker-1.1")
local ui, L = atlas.ui, atlas.L
local title = L("PawAtlas")
local target, targetName
local popup
local tooltipLines = {}
local tooltipMeasure = UIParent:CreateFontString(nil, "ARTWORK", "GameTooltipText")
tooltipMeasure:Hide()
local function brokerTooltip(tooltip, heading, lines, controls)
    local available = UIParent:GetWidth() * UIParent:GetEffectiveScale() / tooltip:GetEffectiveScale() - 40
    local maximum = math.max(1, math.min(340, available))
    local function add(text, color)
        text = ui.safeText(atlas.sourceInlineLinks(text)):gsub("(%d) %%", "%1\194\160%%")
        tooltipMeasure:SetText(text)
        local wrap = tooltipMeasure:GetStringWidth() > maximum
        tooltip:AddLine(text, color[1], color[2], color[3], wrap)
        if wrap then
            local name = tooltip:GetName()
            local line = name and _G[name .. "TextLeft" .. tooltip:NumLines()]
            if line then line:SetWidth(maximum) end
        end
    end
    add(title, ui.gold)
    if heading then add(heading, ui.gold) end
    if #lines > 0 then
        tooltip:AddLine(" ")
        for _, line in ipairs(lines) do add(line, ui.paper) end
    end
    if controls then
        tooltip:AddLine(" ")
        for _, line in ipairs(controls) do add(L(line), ui.paper) end
    end
end
local display = broker:NewDataObject("MountAtlas", {
    type = "data source",
    tocname = "PawAtlas",
    label = title,
    text = title,
    icon = "Interface\\AddOns\\PawAtlas\\Media\\Brand\\MountAtlasMinimap.tga",
    OnClick = function(owner, button)
        if button == "RightButton" then
            if popup then popup:Hide() end
            atlas.toggleWindow()
        elseif button == "LeftButton" then
            if IsShiftKeyDown() then
                if popup then popup:Hide() end
                atlas.setExpeditionEnabled(not atlas.expeditionSettings())
            else
                atlas.openBrokerTargetMenu(owner)
            end
        end
    end,
    OnTooltipShow = function(tooltip)
        brokerTooltip(tooltip, targetName, tooltipLines, {
            "ЛКМ — выбрать цель", "ПКМ — открыть атлас", "Shift + ЛКМ — окно слежения",
        })
    end,
})
if not display then return end

local events = CreateFrame("Frame")
local journalEvent, bagsEvent = "MOUNT_JOURNAL_SEARCH_UPDATED", "BAG_UPDATE_DELAYED"
local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function validID(id)
    return readable(id) and type(id) == "number" and id > 0 and id <= 2147483647 and id % 1 == 0
end

local function settings(write)
    if write then
        if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
        if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
    end
    local saved = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    return type(saved) == "table" and saved or nil
end

local function isCollected(id)
    local journal = C_MountJournal
    if not journal or not journal.GetMountInfoByID then return false end
    local collected = select(11, journal.GetMountInfoByID(id))
    return readable(collected) and collected == true
end

local function currentTargets(planID)
    local mounts, pending = atlas.planTargets(true, planID)
    if planID == atlas.activePlanID() then atlas.updateExpeditionAutoHeight(#mounts) end
    local ordered, byID, rank = {}, {}, {}
    for _, mount in ipairs(mounts) do
        if not mount.unavailable and not isCollected(mount.id) then
            ordered[#ordered + 1] = mount
            byID[mount.id], rank[mount.id] = mount, #ordered
        end
    end
    return ordered, byID, rank, pending
end

local function isPlanTarget(id, planID)
    return validID(id) and atlas.isPlanned({ id = id }, planID) and not isCollected(id)
end

local function manualID(saved)
    if saved and saved.brokerTargetMode == "manual" and validID(saved.brokerMountID) then
        return saved.brokerMountID
    end
end

local function targetDisplay(mount, lines)
    if not mount then return title end

    local stats = atlas.planTargetSummary(mount)
    local attempts = stats and stats.attempts ~= nil and L("Попытки: %s", stats.attempts)
    if attempts then lines[#lines + 1] = attempts end
    if not stats then
        lines[#lines + 1] = L("Нет данных")
        return lines[#lines]
    end
    local progress = stats.collected ~= nil and stats.required and stats.required > 0
        and ("%d / %d"):format(stats.collected, stats.required)
    if stats.item then lines[#lines + 1] = atlas.displayName(stats.item)
    elseif progress then lines[#lines + 1] = L("Предмет маунта") end
    if progress then lines[#lines + 1] = progress end
    local cumulative = stats.attempts and stats.attempts > 0 and stats.cumulative
    local baseChance = stats.perAttempt ~= nil and ui.probabilityText(stats.perAttempt, stats.perAttempt == 1)
    local chance = cumulative and ui.probabilityText(cumulative, stats.perAttempt == 1) or baseChance
    if stats.condition then
        if chance then lines[#lines + 1] = chance .. " / " .. L("При выполнении условий") end
        lines[#lines + 1] = L(stats.condition)
    elseif baseChance then
        lines[#lines + 1] = L("За одну попытку: %s", baseChance)
    elseif not progress then
        lines[#lines + 1] = L("За одну попытку: %s", L("Неизвестен"))
    end
    if cumulative then
        lines[#lines + 1] = L("Вероятность за все попытки: %s", chance)
    end
    if stats.rewardCondition then lines[#lines + 1] = L(stats.rewardCondition) end
    local value = progress or chance
    local text = attempts and value and attempts .. " / " .. value or attempts or value or L("Нет данных")
    return text, stats.watchBags
end

local queued, resolveQueued
local planID, ordered, byID, rank, pending
local pendingAttempts = {}
local watchTargetBags

local function updateBagEvent()
    if watchTargetBags or (popup and popup:IsShown()) then events:RegisterEvent(bagsEvent)
    else events:UnregisterEvent(bagsEvent) end
end

local function pruneAutoTargets(saved)
    if not saved or type(saved.brokerAutoTargets) ~= "table" then return end
    local profiles = {}
    for _, profile in ipairs(atlas.planProfiles()) do profiles[profile.id] = true end
    for id in pairs(saved.brokerAutoTargets) do
        if not profiles[id] then saved.brokerAutoTargets[id] = nil end
    end
end

local function applyAttempt(profileID, candidates)
    local orderedRanks, waiting = rank, pending
    if profileID ~= planID then
        local _, _, otherRanks, otherPending = currentTargets(profileID)
        orderedRanks, waiting = otherRanks, otherPending
    end
    local winner, winnerRank
    for id in pairs(candidates) do
        if (orderedRanks[id] or waiting) and isPlanTarget(id, profileID) then
            local candidateRank = orderedRanks[id] or math.huge
            if not winner or candidateRank < winnerRank or (candidateRank == winnerRank and id < winner) then
                winner, winnerRank = id, candidateRank
            end
        end
    end
    if not winner then return end
    local saved = settings(true)
    if type(saved.brokerAutoTargets) ~= "table" then saved.brokerAutoTargets = {} end
    saved.brokerAutoTargets[profileID] = winner
end

local function chooseTarget(saved)
    local id = manualID(saved)
    if id then
        if byID[id] then return byID[id] end
        if not pending or not isPlanTarget(id, planID) then
            saved.brokerTargetMode, saved.brokerMountID = "auto", nil
        end
    end
    local last = saved and type(saved.brokerAutoTargets) == "table" and saved.brokerAutoTargets[planID]
    return validID(last) and byID[last] or ordered[1]
end

function atlas.queuePlanBrokerStatsRefresh()
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        queued = nil
        local active = atlas.activePlanID()
        if resolveQueued or active ~= planID then
            resolveQueued = nil
            planID = active
            ordered, byID, rank, pending = currentTargets(active)
            pruneAutoTargets(settings())
            if pending then events:RegisterEvent(journalEvent)
            else events:UnregisterEvent(journalEvent) end
        end
        for profileID, candidates in pairs(pendingAttempts) do applyAttempt(profileID, candidates) end
        pendingAttempts = {}
        target = chooseTarget(settings())
        targetName = target and atlas.displayMountName(target)
        tooltipLines = {}
        local text
        text, watchTargetBags = targetDisplay(target, tooltipLines)
        updateBagEvent()
        display.text = ui.safeText(text)
        if popup and popup:IsShown() then popup:refresh(planID, ordered, manualID(settings())) end
    end)
end

function atlas.queuePlanBrokerRefresh()
    resolveQueued = true
    atlas.queuePlanBrokerStatsRefresh()
end

function atlas.recordBrokerAttempt(mountIDs)
    local profileID = atlas.activePlanID()
    -- Tracking and stage handlers can credit the same loot window.
    local candidates = pendingAttempts[profileID] or {}
    if type(mountIDs) == "table" then
        for id in pairs(mountIDs) do
            if isPlanTarget(id, profileID) then candidates[id] = true end
        end
    elseif isPlanTarget(mountIDs, profileID) then
        candidates[mountIDs] = true
    end
    if not next(candidates) then return end
    pendingAttempts[profileID] = candidates
    atlas.queuePlanBrokerStatsRefresh()
end

local function selectBrokerTarget(frame, mount)
    if frame.profileID ~= atlas.activePlanID() or not isPlanTarget(mount.id, frame.profileID) then return end
    local saved = settings(true)
    if manualID(saved) == mount.id then
        saved.brokerTargetMode, saved.brokerMountID = "auto", nil
    else
        saved.brokerTargetMode, saved.brokerMountID = "manual", mount.id
    end
    atlas.queuePlanBrokerStatsRefresh()
end

local function makePopup()
    local frame = atlas.createExpeditionWindow("MountAtlasBrokerTargets", selectBrokerTarget)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    function frame:position()
        self:ClearAllPoints()
        local owner = self.owner
        local top = owner and owner:GetTop()
        local bottom = owner and owner:GetBottom()
        local left = owner and owner:GetLeft()
        if not (top and bottom and left) then
            self:setResizeFromTop(false)
            self:SetPoint("CENTER", UIParent, "CENTER")
            return
        end
        local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local screenWidth, screenHeight = UIParent:GetSize()
        local width, height = self:GetSize()
        local x = left * scale - (UIParent:GetLeft() or 0)
        local screenBottom = UIParent:GetBottom() or 0
        x = math.max(0, math.min(x, screenWidth - width))
        local above = top * scale - screenBottom + 6
        local below = bottom * scale - screenBottom - 6
        local spaceAbove = screenHeight - above
        local fromTop = spaceAbove >= height or (below < height and spaceAbove >= below)
        self:setResizeFromTop(fromTop)
        if fromTop then
            self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, math.max(0, math.min(above, screenHeight - height)))
        else
            self:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, math.max(height, math.min(below, screenHeight)))
        end
    end
    frame:SetScript("OnEvent", function(self)
        if self.resizing or self.dragging then return end
        if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
    end)
    frame:HookScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self.owner = nil
        updateBagEvent()
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, frame:GetName()) end
    return frame
end

function atlas.openBrokerTargetMenu(owner)
    if popup and popup:IsShown() then popup:Hide(); return end
    local profileID = atlas.activePlanID()
    local options = ordered
    if resolveQueued or planID ~= profileID then options = currentTargets(profileID) end
    if not popup then popup = makePopup() end
    popup:refresh(profileID, options, manualID(settings()))
    if owner and owner.GetTop and owner.IsMouseOver then
        popup.owner = owner
        if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
    end
    popup:position()
    popup:Show()
    popup:RegisterEvent("GLOBAL_MOUSE_DOWN")
    updateBagEvent()
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("NEW_MOUNT_ADDED")
events:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent(event)
        atlas.queuePlanBrokerRefresh()
    elseif event == journalEvent or event == "NEW_MOUNT_ADDED" then
        atlas.queuePlanBrokerRefresh()
    else
        atlas.queuePlanBrokerStatsRefresh()
    end
end)
