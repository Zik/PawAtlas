local _, atlas = ...
local ui, L = atlas.ui, atlas.L
local width, headerHeight, rowHeight, maxRows = 336, 36, 44, 5
local emptyHeight, textX, statsWidth = 28, 46, 102
atlas.expeditionTransparencyMax = 100
local tracker, queued, statsQueued
local events = CreateFrame("Frame")
local journalEvent = "MOUNT_JOURNAL_SEARCH_UPDATED"
local bagsEvent = "BAG_UPDATE_DELAYED"

local function settings(write)
    if write then
        if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
        if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
    end
    local saved = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    return type(saved) == "table" and saved or nil
end

local function transparency(value)
    if type(value) ~= "number" or value ~= value then return 0 end
    return math.max(0, math.min(atlas.expeditionTransparencyMax, math.floor(value + .5)))
end

function atlas.expeditionSettings()
    local saved = settings()
    if not saved then return false, false, 0 end
    return saved.expeditionEnabled == true, saved.expeditionPinned == true, transparency(saved.expeditionTransparency)
end

function atlas.setExpeditionEnabled(value)
    local enabled = value == true
    settings(true).expeditionEnabled = enabled
    if atlas.refreshExpeditionEnabledSetting then atlas.refreshExpeditionEnabledSetting(enabled) end
    atlas.refreshExpeditionTracker()
end

local function applyTransparency(frame, percent)
    for _, texture in ipairs(frame.background) do texture:SetAlpha(1 - percent / 100) end
end

function atlas.setExpeditionTransparency(value)
    local percent = transparency(value)
    settings(true).expeditionTransparency = percent
    if tracker then applyTransparency(tracker, percent) end
end

local function applyPosition(frame)
    local saved = settings()
    local position = saved and saved.expeditionPosition
    frame:ClearAllPoints()
    if type(position) == "table" and type(position.x) == "number" and position.x >= 0 and position.x <= 1
        and type(position.y) == "number" and position.y >= 0 and position.y <= 1 then
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", position.x * UIParent:GetWidth(), -position.y * UIParent:GetHeight())
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -168)
    end
end

local function stopMoving(frame)
    if not frame.dragging then return end
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    frame.dragging = nil
    local x, y = frame:GetLeft(), frame:GetTop()
    local screenWidth, screenHeight = UIParent:GetSize()
    if not x or not y or screenWidth <= 0 or screenHeight <= 0 then return end
    settings(true).expeditionPosition = {
        x = math.max(0, math.min(1, (x - (UIParent:GetLeft() or 0)) / screenWidth)),
        y = math.max(0, math.min(1, ((UIParent:GetTop() or screenHeight) - y) / screenHeight)),
    }
    applyPosition(frame)
end

function atlas.setExpeditionPinned(value)
    local pinned = value == true
    settings(true).expeditionPinned = pinned
    if tracker then
        if pinned then stopMoving(tracker) end
        ui.setIcon(tracker.lockIcon, pinned and "Lock" or "Unlock")
        tracker.lockIcon:SetDesaturated(true)
        tracker.lockIcon:SetVertexColor(unpack(pinned and ui.gold or ui.muted))
    end
    if atlas.refreshExpeditionPinSetting then atlas.refreshExpeditionPinSetting(pinned) end
end

local function openTarget(mount)
    local points = atlas.mountLocations(mount)
    local point = #points == 1 and points[1]
    if point and type(point.map) == "number" and type(point.x) == "number" and type(point.y) == "number"
        and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1 then
        return atlas.openSource({}, point)
    end
    if not atlas.openMountCard(mount.id) then return L("Нет данных") end
end

function atlas.planTargetSummary(mount)
    if not mount.kind or (mount.journalOnly and not mount.indexed) then return end
    if mount.unavailable or mount.availability or mount.trackingCompatible == false then return end
    local vendor = mount.kind == "Торговец" and not atlas.verifiedRewardDropRoute(mount)
    if vendor then return end
    local perAttempt, cumulative, attempts = atlas.dropProbability(mount)
    local reward = atlas.guaranteedRewards and atlas.guaranteedRewards[mount.id]
    local item = atlas.itemAttemptProgress(mount)
    local itemStats = item and (item.attempts ~= nil or item.perAttempt ~= nil)
    if item and (item.collection or item.collected ~= nil or (itemStats and (reward or not perAttempt))) then
        return {
            attempts = item.attempts, perAttempt = item.perAttempt, cumulative = item.cumulative,
            collected = item.collected, required = item.required, item = item.name,
            itemChance = true, watchBags = item.collection or item.collected ~= nil,
            rewardCondition = reward and reward.condition,
        }
    end
    if reward then return { perAttempt = 1, condition = reward.condition } end
    if attempts == nil and perAttempt == nil and atlas.rewardChanceEligible(mount) then
        local progress = atlas.rewardAttemptProgress(mount)
        if progress then attempts = progress.attempts
        elseif atlas.usesKillAPI(mount) or (not mount.journalOnly and (mount.npcs or mount.encounter)) then
            attempts = atlas.kills(mount)
        end
    end
    if attempts ~= nil or perAttempt ~= nil then
        return { attempts = attempts, perAttempt = perAttempt, cumulative = cumulative }
    end
end

local function formatStats(stats)
    if not stats then return "", "", ui.muted end
    local attempts = stats.attempts ~= nil and L("Попытки: %s", stats.attempts) or ""
    if stats.collected ~= nil and stats.required and stats.required > 0 then
        return attempts, ("%d / %d"):format(stats.collected, stats.required), ui.mint
    end
    local cumulative = stats.attempts and stats.attempts > 0 and stats.cumulative
    local probability = cumulative or stats.perAttempt
    if probability == nil then return attempts, "", ui.muted end
    local color = ui.muted
    for _, tier in ipairs(ui.chances) do
        if probability * 100 <= tier.limit then color = tier.color; break end
    end
    return attempts, ui.probabilityText(probability, stats.perAttempt == 1), color
end

local function lootCompletion(mount, guid)
    if not mount.kind or (mount.journalOnly and not mount.indexed) then return end
    local accountState = atlas.accountLootLockout(mount)
    if accountState then
        if accountState == "attempt" then return L("Попытка использована"), true end
        return
    end
    if guid then
        local state, _, _, progress = atlas.planCharacterStatus(mount, guid)
        if progress and progress.totalAttempts > 1 then
            local done, total = progress.completedAttempts, progress.totalAttempts
            if done > 0 then return L("Выполнено: %d / %d", done, total), done == total end
            return
        end
        if state == "boss" then return L("Босс убит"), true end
        if state == "attempt" then return L("Попытка использована"), true end
        return
    end
    local counts = atlas.planSummary(mount)
    local done, total = counts.done, counts.total
    if counts.totalAttempts > counts.total then done, total = counts.completedAttempts, counts.totalAttempts end
    if done > 0 then
        return L("Выполнено: %d / %d", done, total), done == total and counts.done == counts.total
    end
end

local function showRowTooltip(row)
    if not row.mount then return end
    if not GameTooltip:IsOwned(row) then GameTooltip:SetOwner(row, "ANCHOR_RIGHT") end
    ui.tooltipTitle(atlas.displayName(row.mount.name))
    if row.lootStatus then ui.tooltipLine(row.lootStatus, unpack(row.complete and ui.mint or ui.muted)) end
    local stats = row.stats
    if stats then
        if stats.item then ui.tooltipLine(atlas.displayName(stats.item), unpack(ui.muted)) end
        if stats.attempts ~= nil then ui.tooltipLine(L("Попытки: %s", stats.attempts)) end
        if stats.condition then ui.tooltipLine(L(stats.condition), 1, 1, 1, true)
        elseif stats.perAttempt ~= nil then
            ui.tooltipLine(L("За одну попытку: %s", ui.probabilityText(stats.perAttempt, stats.perAttempt == 1)))
        end
        if stats.attempts and stats.attempts > 0 and stats.cumulative ~= nil then
            ui.tooltipLine(L("Вероятность за все попытки: %s", ui.probabilityText(stats.cumulative, stats.perAttempt == 1)))
        end
        if stats.collected ~= nil and stats.required and stats.required > 0 then
            ui.tooltipLine(("%d / %d"):format(stats.collected, stats.required), unpack(ui.mint))
        end
        if stats.rewardCondition then ui.tooltipLine(L(stats.rewardCondition), 1, 1, 1, true) end
    end
    if row.feedback then ui.tooltipLine(row.feedback, unpack(ui.muted)) end
    GameTooltip:Show()
end

local function hideRowTooltip(row)
    row.feedback = nil
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function refreshStats()
    local saved = settings()
    local selected = saved and saved.plannerCharacterGUID
    local characters = atlas.accountCharacters()
    local guid = #characters == 1 and characters[1].guid or nil
    if selected then
        for _, character in ipairs(characters) do
            if character.guid == selected then guid = selected; break end
        end
    end
    local watchBags
    for _, row in ipairs(tracker.rows) do
        if row.mount then
            local stats = atlas.planTargetSummary(row.mount)
            row.stats = stats
            watchBags = watchBags or (stats and stats.watchBags)
            local attempts, value, color = formatStats(stats)
            local status, complete = lootCompletion(row.mount, guid)
            row.lootStatus, row.complete = status, complete
            local hasMetric = value ~= "" or status ~= nil
            row.name:SetWidth(width - textX - 26 - (hasMetric and statsWidth or 0))
            row.attempts:SetText(attempts)
            row.value:SetText(value)
            row.value:SetTextColor(unpack(color))
            row.status:SetText(status or "")
            row.status:SetTextColor(unpack(complete and ui.mint or ui.muted))
            row.icon:SetDesaturated(complete == true)
            row.check:SetShown(complete == true)
            row.arrow:SetShown(not hasMetric)
            if GameTooltip:IsShown() and GameTooltip:IsOwned(row) then showRowTooltip(row) end
        else
            row.stats, row.lootStatus, row.complete = nil, nil, nil
        end
    end
    if watchBags then events:RegisterEvent(bagsEvent)
    else events:UnregisterEvent(bagsEvent) end
end

function atlas.queueExpeditionStatsRefresh()
    if statsQueued or queued or not tracker or not tracker:IsShown() then return end
    statsQueued = true
    C_Timer.After(0, function()
        statsQueued = nil
        if not queued and tracker:IsShown() and atlas.expeditionSettings() then refreshStats() end
    end)
end

local function makeTracker()
    local frame = CreateFrame("Frame", "MountAtlasExpeditionTracker", UIParent)
    frame:Hide()
    local initialHeight = headerHeight + emptyHeight + 6
    frame:SetSize(width, initialHeight)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame.background = ui.surface(frame, 0, 0, width, initialHeight)
    for column = 1, 3 do
        local middle, bottom = frame.background[column + 3], frame.background[column + 6]
        local _, _, _, left = bottom:GetPoint()
        middle:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, 10)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", left, 0)
    end
    ui.fill(frame, 12, headerHeight - 2, width - 24, 1, ui.rule):SetDrawLayer("BORDER")

    local grip = ui.place(CreateFrame("Frame", nil, frame), frame, 0, 0, width - 34, headerHeight)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    ui.brandIcon(grip, 12, 7, 21)
    frame.title = ui.text(grip, 39, 2, width - 83, headerHeight - 5, 16, "", ui.gold)
    frame.title.atlasGameText = true
    frame.title:SetMaxLines(1)
    local function hideTitleTooltip()
        if GameTooltip:IsOwned(grip) then GameTooltip:Hide() end
    end
    local function showTitleTooltip()
        if frame.dragging or not (frame.title:IsTruncated() or frame.title:GetStringWidth() > frame.title:GetWidth()) then
            hideTitleTooltip()
            return
        end
        if not GameTooltip:IsOwned(grip) then GameTooltip:SetOwner(grip, "ANCHOR_TOP") end
        ui.tooltipTitle(frame.title:GetText())
        GameTooltip:Show()
    end
    grip:SetScript("OnEnter", showTitleTooltip)
    grip:SetScript("OnLeave", hideTitleTooltip)
    grip:SetScript("OnHide", hideTitleTooltip)
    grip:SetScript("OnDragStart", function()
        local _, pinned = atlas.expeditionSettings()
        if pinned then return end
        hideTitleTooltip()
        frame.dragging = true
        frame:StartMoving()
    end)
    grip:SetScript("OnDragStop", function() stopMoving(frame) end)
    local lock = ui.place(CreateFrame("Button", nil, frame), frame, width - 32, 4, 26, 26)
    frame.lockIcon = ui.icon(lock, 5, 5, 16, "Unlock")
    lock:SetScript("OnClick", function()
        local _, pinned = atlas.expeditionSettings()
        atlas.setExpeditionPinned(not pinned)
    end)
    lock:SetScript("OnEnter", function(self)
        frame.lockIcon:SetVertexColor(unpack(ui.gold))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Закрепление"))
        GameTooltip:Show()
    end)
    local function leaveLock(self)
        local _, pinned = atlas.expeditionSettings()
        frame.lockIcon:SetVertexColor(unpack(pinned and ui.gold or ui.muted))
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    lock:SetScript("OnLeave", leaveLock)
    lock:SetScript("OnHide", leaveLock)
    frame:SetScript("OnHide", stopMoving)
    function frame:setTitle(name)
        self.title:SetText(name)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(grip) then showTitleTooltip() end
    end
    frame.empty = ui.text(frame, 12, headerHeight, width - 24, emptyHeight, 13, "", ui.muted)
    frame.more = ui.text(frame, 12, headerHeight + maxRows * rowHeight, width - 24, 20, 12, "", ui.muted)
    frame.more:SetJustifyH("RIGHT")
    frame.rows = {}
    for index = 1, maxRows do
        local row = ui.button(frame, 8, headerHeight + (index - 1) * rowHeight, width - 16, rowHeight, function(self)
            if not self.mount then return end
            local feedback = openTarget(self.mount)
            self.feedback = type(feedback) == "string" and feedback or nil
            if self.feedback then showRowTooltip(self) end
        end)
        local icon, _, iconSlot = ui.itemIcon(row, 5, 5, 34)
        row.icon = icon
        row.check = ui.icon(iconSlot, 22, 22, 14, "ObjectiveComplete")
        row.check:SetDrawLayer("OVERLAY")
        row.check:Hide()
        row.name = ui.text(row, textX, 3, width - textX - 26, 20, 14, "")
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.attempts = ui.text(row, textX, 23, width - textX - statsWidth - 24, 14, 11, "", ui.muted)
        row.attempts:SetMaxLines(1)
        row.value = ui.text(row, width - statsWidth - 20, 3, statsWidth, 23, 17, "", ui.gold)
        row.value:SetJustifyH("RIGHT")
        row.value:SetMaxLines(1)
        row.status = ui.text(row, width - statsWidth - 20, 25, statsWidth, 15, 11, "", ui.muted)
        row.status:SetJustifyH("RIGHT")
        row.status:SetMaxLines(1)
        row.arrow = ui.text(row, width - 39, 0, 20, rowHeight, 14, "›", ui.gold)
        row:SetScript("OnEnter", showRowTooltip)
        row:SetScript("OnLeave", hideRowTooltip)
        row:SetScript("OnHide", hideRowTooltip)
        frame.rows[index] = row
    end
    applyPosition(frame)
    return frame
end

function atlas.refreshExpeditionTracker()
    local enabled, pinned, percent = atlas.expeditionSettings()
    if not enabled then
        events:UnregisterEvent(journalEvent)
        events:UnregisterEvent(bagsEvent)
        if tracker then tracker:Hide() end
        return
    end
    if not tracker then tracker = makeTracker() end
    atlas.setExpeditionPinned(pinned)
    applyTransparency(tracker, percent)
    local planID = atlas.activePlanID()
    for _, profile in ipairs(atlas.planProfiles()) do
        if profile.id == planID then tracker:setTitle(profile.name); break end
    end
    local targets, pendingJournal = atlas.planTargets(true, planID)
    if pendingJournal then events:RegisterEvent(journalEvent)
    else events:UnregisterEvent(journalEvent) end
    for index, row in ipairs(tracker.rows) do
        local mount = targets[index]
        local changed = mount and (not row.mount or row.mount.id ~= mount.id)
        if changed then row.feedback = nil end
        row.mount = mount
        row:SetShown(mount ~= nil)
        if mount then
            row.name:SetText(atlas.displayName(mount.name))
            local icon = mount.icon
            if not icon and C_MountJournal and C_MountJournal.GetMountInfoByID then
                icon = select(3, C_MountJournal.GetMountInfoByID(mount.id))
            end
            if issecretvalue and issecretvalue(icon) then icon = nil end
            row.icon:SetTexture(icon or 132261)
        end
    end
    refreshStats()
    tracker.empty:SetShown(#targets == 0)
    tracker.empty:SetText(L("В плане: %d", 0))
    tracker.more:SetShown(#targets > maxRows)
    tracker.more:SetText(("+%d"):format(math.max(0, #targets - maxRows)))
    tracker:SetHeight(headerHeight + (#targets == 0 and emptyHeight or math.min(#targets, maxRows) * rowHeight)
        + (#targets > maxRows and 20 or 0) + 6)
    tracker:Show()
end

function atlas.queueExpeditionTrackerRefresh()
    if queued or not atlas.expeditionSettings() then return end
    queued = true
    C_Timer.After(0, function()
        queued = nil
        atlas.refreshExpeditionTracker()
    end)
end

events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:SetScript("OnEvent", function(self, event)
    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        if tracker then
            stopMoving(tracker)
            applyPosition(tracker)
        end
    elseif event == bagsEvent then
        atlas.queueExpeditionStatsRefresh()
    else
        if event == "PLAYER_ENTERING_WORLD" then self:UnregisterEvent(event) end
        atlas.queueExpeditionTrackerRefresh()
    end
end)
