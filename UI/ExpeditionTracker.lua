local _, atlas = ...
local ui, L = atlas.ui, atlas.L
local headerHeight, rowHeight, bottomPadding = 47, 44, 11
local emptyHeight, inset, textX = 34, 14, 46
local minWidth, minHeight = 300, headerHeight + rowHeight + bottomPadding
local autoHeight = minHeight
atlas.expeditionDefaultWidth = 420
atlas.expeditionTransparencyMax = 100
local tracker, queued, statsQueued
local windows = {}
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
    frame.background:SetAlpha(1 - percent / 100)
end

function atlas.setExpeditionTransparency(value)
    local percent = transparency(value)
    settings(true).expeditionTransparency = percent
    for _, frame in ipairs(windows) do applyTransparency(frame, percent) end
end

local function applyPosition(frame)
    local saved = settings()
    local position = saved and saved.expeditionPosition
    local screenWidth, screenHeight = UIParent:GetSize()
    local x, y = 24, 168
    if type(position) == "table" and type(position.x) == "number" and position.x >= 0 and position.x <= 1
        and type(position.y) == "number" and position.y >= 0 and position.y <= 1 then
        x, y = position.x * screenWidth, position.y * screenHeight
    end
    x = math.max(0, math.min(x, screenWidth - frame:GetWidth()))
    y = math.max(0, math.min(y, screenHeight - frame:GetHeight()))
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", x, -y)
end

function atlas.expeditionSizeLimits()
    local screenWidth, screenHeight = UIParent:GetSize()
    return minWidth, math.max(minWidth, math.floor(screenWidth - 16)),
        minHeight, math.max(minHeight, math.floor(screenHeight - 16))
end

local function dimension(value, default, minimum, maximum)
    if type(value) ~= "number" or value ~= value then value = default end
    return math.max(minimum, math.min(maximum, math.floor(value + .5)))
end

function atlas.expeditionSize()
    local saved = settings()
    local minimumW, maximumW, minimumH, maximumH = atlas.expeditionSizeLimits()
    return dimension(saved and saved.expeditionWidth, atlas.expeditionDefaultWidth, minimumW, maximumW),
        dimension(saved and saved.expeditionHeight, autoHeight, minimumH, maximumH)
end

local function applySize(frame, width, height)
    if frame.resizing then return end
    frame:SetSize(width, height)
    if frame == tracker then applyPosition(frame)
    elseif frame.position and frame:IsShown() and not frame.dragging then frame:position() end
end

local function applySharedSize()
    local width, height = atlas.expeditionSize()
    for _, frame in ipairs(windows) do applySize(frame, width, height) end
    if atlas.refreshExpeditionSizeSettings then atlas.refreshExpeditionSizeSettings(width, height) end
end

function atlas.setExpeditionSize(width, height)
    local currentWidth, currentHeight = atlas.expeditionSize()
    local minimumW, maximumW, minimumH, maximumH = atlas.expeditionSizeLimits()
    local saved = settings(true)
    if width ~= nil then saved.expeditionWidth = dimension(width, currentWidth, minimumW, maximumW) end
    if height ~= nil then saved.expeditionHeight = dimension(height, currentHeight, minimumH, maximumH) end
    applySharedSize()
end

function atlas.resetExpeditionSize()
    local saved = settings()
    if saved then saved.expeditionWidth, saved.expeditionHeight = nil, nil end
    applySharedSize()
end

function atlas.updateExpeditionAutoHeight(count)
    local newHeight = headerHeight + math.max(1, count) * rowHeight + bottomPadding
    if newHeight == autoHeight then return end
    local _, previousHeight = atlas.expeditionSize()
    autoHeight = newHeight
    local _, height = atlas.expeditionSize()
    if height ~= previousHeight then applySharedSize() end
end

local function stopMoving(frame)
    if not frame.dragging then return end
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    frame.dragging = nil
    if frame ~= tracker then return end
    local x, y = frame:GetLeft(), frame:GetTop()
    local screenWidth, screenHeight = UIParent:GetSize()
    if not x or not y or screenWidth <= 0 or screenHeight <= 0 then return end
    settings(true).expeditionPosition = {
        x = math.max(0, math.min(1, (x - (UIParent:GetLeft() or 0)) / screenWidth)),
        y = math.max(0, math.min(1, ((UIParent:GetTop() or screenHeight) - y) / screenHeight)),
    }
    applyPosition(frame)
end

local function stopResizing(frame)
    local initialSize = frame.resizing
    if not initialSize then return end
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    local width, height = frame:GetSize()
    local newWidth = math.abs(width - initialSize.width) >= .5 and width or nil
    local newHeight = math.abs(height - initialSize.height) >= .5 and height or nil
    if newWidth or newHeight then atlas.setExpeditionSize(newWidth, newHeight) end
    frame.resizing = nil
    frame:SetSize(atlas.expeditionSize())
end

local function setupResizeHandle(frame)
    local handle = CreateFrame("Button", nil, frame)
    frame.resizeHandle = handle
    handle:SetSize(14, 14)
    handle:SetFrameLevel(frame:GetFrameLevel() + 5)
    local marks = {}
    for i = 1, 3 do
        local stroke = handle:CreateTexture(nil, "OVERLAY")
        stroke:SetSize(16 - i * 4, 1)
        stroke:SetColorTexture(unpack(ui.muted))
        marks[i] = stroke
    end
    function frame:setResizeFromTop(fromTop)
        if self.resizeFromTop == fromTop then return end
        self.resizeFromTop = fromTop
        local corner = fromTop and "TOPRIGHT" or "BOTTOMRIGHT"
        handle:ClearAllPoints()
        handle:SetPoint(corner, self, corner, -2, fromTop and -2 or 2)
        for i, stroke in ipairs(marks) do
            stroke:ClearAllPoints()
            stroke:SetPoint("CENTER", handle, corner, -8 + i * 2, (fromTop and -1 or 1) * (9 - i * 2))
            stroke:SetRotation((fromTop and -1 or 1) * math.pi / 4)
        end
    end
    frame:setResizeFromTop(false)
    handle:SetScript("OnEnter", function()
        for _, stroke in ipairs(marks) do stroke:SetColorTexture(unpack(ui.gold)) end
    end)
    local function clearHover()
        for _, stroke in ipairs(marks) do stroke:SetColorTexture(unpack(ui.muted)) end
    end
    handle:SetScript("OnLeave", clearHover)
    handle:SetScript("OnHide", clearHover)
    handle:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not frame:IsResizable() or frame.dragging or frame.resizing then return end
        local left, top, bottom = frame:GetLeft(), frame:GetTop(), frame:GetBottom()
        if not (left and top and bottom) then return end
        local minimumW, maximumW, minimumH, maximumH = atlas.expeditionSizeLimits()
        local screenBottom = UIParent:GetBottom() or 0
        local screenWidth, screenHeight = UIParent:GetSize()
        local horizontalSpace = (UIParent:GetLeft() or 0) + screenWidth - left
        local verticalSpace = frame.resizeFromTop and (screenBottom + screenHeight - bottom) or (top - screenBottom)
        frame:SetResizeBounds(minimumW, minimumH, math.max(minimumW, math.min(maximumW, horizontalSpace)),
            math.max(minimumH, math.min(maximumH, verticalSpace)))
        frame.resizing = { width = frame:GetWidth(), height = frame:GetHeight() }
        frame:StartSizing(frame.resizeFromTop and "TOPRIGHT" or "BOTTOMRIGHT")
    end)
    handle:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then stopResizing(frame) end
    end)
end

local function applyPin(frame, pinned)
    if pinned then
        stopResizing(frame)
        stopMoving(frame)
    end
    frame:SetResizable(not pinned)
    frame.resizeHandle:SetShown(not pinned)
    ui.setIcon(frame.lockIcon, pinned and "Lock" or "Unlock")
    frame.lockIcon:SetDesaturated(true)
    frame.lockIcon:SetVertexColor(unpack(pinned and ui.gold or ui.muted))
end

function atlas.setExpeditionPinned(value)
    local pinned = value == true
    settings(true).expeditionPinned = pinned
    for _, frame in ipairs(windows) do applyPin(frame, pinned) end
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
    local condition = reward and (atlas.getLocale() == "enUS" and reward.englishCondition or L(reward.condition))
    local item = atlas.itemAttemptProgress(mount)
    local itemStats = item and (item.attempts ~= nil or item.perAttempt ~= nil)
    if item and (item.collection or item.collected ~= nil or (itemStats and (reward or not perAttempt))) then
        return {
            attempts = item.attempts, perAttempt = item.perAttempt, cumulative = item.cumulative,
            collected = item.collected, required = item.required, item = item.name,
            itemChance = true, watchBags = item.collection or item.collected ~= nil,
            rewardCondition = condition,
        }
    end
    if reward then return { perAttempt = 1, condition = condition } end
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
    return attempts, ui.probabilityText(probability, stats.perAttempt == 1), ui.probabilityColor(probability)
end

function atlas.planLootCompletion(mount, guid)
    if not mount.kind or (mount.journalOnly and not mount.indexed) then return end
    local accountState, _, accountExpires = atlas.accountLootLockout(mount)
    if accountState then
        if accountState == "attempt" then return L("Попытка использована"), true, accountExpires end
        return
    end
    if guid then
        local state, _, expires, progress = atlas.planCharacterStatus(mount, guid)
        if progress and progress.totalAttempts > 1 then
            local done, total = progress.completedAttempts, progress.totalAttempts
            if done > 0 then return L("Выполнено: %d / %d", done, total), done == total, expires end
            return
        end
        if state == "boss" then return L("Босс убит"), true, expires end
        if state == "attempt" then return L("Попытка использована"), true, expires end
        return
    end
    local counts = atlas.planSummary(mount)
    local done, total = counts.done, counts.total
    if counts.totalAttempts > counts.total then done, total = counts.completedAttempts, counts.totalAttempts end
    if done > 0 then
        return L("Выполнено: %d / %d", done, total), done == total and counts.done == counts.total, counts.expires
    end
end

local function tooltipStat(label, value, color)
    GameTooltip:AddDoubleLine(L(label), ui.safeText(value), ui.muted[1], ui.muted[2], ui.muted[3], unpack(color))
end

local function showRowTooltip(row)
    if not row.item then return end
    if not GameTooltip:IsOwned(row) then GameTooltip:SetOwner(row, "ANCHOR_RIGHT") end
    ui.tooltipTitle(ui.coloredMountName(row.item), unpack(ui.paper))
    if row.lootStatus then ui.tooltipLine(row.lootStatus, unpack(row.complete and ui.mint or ui.muted)) end
    local stats = row.stats
    if stats then
        if stats.item then ui.tooltipLine(atlas.displayName(stats.item), unpack(ui.muted)) end
        if stats.attempts ~= nil then tooltipStat("Попытки", tostring(stats.attempts), ui.paper) end
        if stats.condition then ui.tooltipSourceText(atlas.sourceInlineLinks(stats.condition))
        elseif stats.perAttempt ~= nil then
            tooltipStat("За одну попытку", ui.probabilityText(stats.perAttempt, stats.perAttempt == 1), ui.probabilityColor(stats.perAttempt))
        end
        if stats.attempts and stats.attempts > 0 and stats.cumulative ~= nil then
            tooltipStat("Вероятность за все попытки", ui.probabilityText(stats.cumulative, stats.perAttempt == 1), ui.probabilityColor(stats.cumulative))
        end
        if stats.collected ~= nil and stats.required and stats.required > 0 then
            ui.tooltipLine(("%d / %d"):format(stats.collected, stats.required), unpack(ui.mint))
        end
        if stats.rewardCondition then ui.tooltipSourceText(atlas.sourceInlineLinks(stats.rewardCondition)) end
    end
    if row.feedback then ui.tooltipLine(row.feedback, unpack(ui.muted)) end
    GameTooltip:Show()
end

local function hideRowTooltip(row)
    row.feedback = nil
    if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
end

local function fitRowName(label, name)
    label:SetText(name)
    local width = label:GetWidth()
    if label:GetUnboundedStringWidth() <= width then return end
    local length = #name
    repeat
        local byte = name:byte(length)
        while byte and byte >= 128 and byte < 192 do
            length = length - 1
            byte = name:byte(length)
        end
        length = math.max(0, length - 1)
        label:SetText(name:sub(1, length):gsub("%s+$", "") .. "…")
    until length == 0 or label:GetUnboundedStringWidth() <= width
end

local function selectedCharacter()
    local saved = settings()
    local selected = saved and saved.plannerCharacterGUID
    local characters = atlas.accountCharacters()
    local guid = #characters == 1 and characters[1].guid or nil
    if selected then
        for _, character in ipairs(characters) do
            if character.guid == selected then guid = selected; break end
        end
    end
    return guid
end

function atlas.queueExpeditionStatsRefresh()
    if statsQueued or queued or not tracker or not tracker:IsShown() then return end
    statsQueued = true
    C_Timer.After(0, function()
        statsQueued = nil
        if not queued and tracker:IsShown() and atlas.expeditionSettings() then tracker:refreshRows() end
    end)
end

function atlas.createExpeditionWindow(name, onTargetClick)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:Hide()
    local width, height = atlas.expeditionSize()
    local rowWidth = width - 2 * inset
    frame:SetSize(width, height)
    frame:SetFrameStrata("LOW")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame.background = CreateFrame("Frame", nil, frame)
    frame.background:SetAllPoints(frame)
    frame.background:SetFrameLevel(frame:GetFrameLevel())
    ui.journalPanel(frame.background, 0)
    local divider = ui.fill(frame, inset, headerHeight - 6, rowWidth, 1, ui.rule)
    divider:SetDrawLayer("ARTWORK")

    local grip = ui.place(CreateFrame("Frame", nil, frame), frame, 0, 0, width - 34, headerHeight)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    local paw = ui.place(CreateFrame("Button", nil, grip), grip, 11, 6, 31, 31)
    paw:RegisterForClicks("LeftButtonUp")
    local icon = ui.brandIcon(paw, 5, 5, 21)
    paw:SetHighlightTexture(icon:GetTexture(), "ADD")
    local highlight = paw:GetHighlightTexture()
    highlight:ClearAllPoints()
    highlight:SetAllPoints(icon)
    highlight:SetAlpha(.3)
    paw:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        if frame ~= tracker then frame:Hide() end
        MountAtlasWindow:Show()
    end)
    frame.title = ui.text(grip, 45, 6, width - 91, 31, 17, "", ui.gold)
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
        if pinned or frame.resizing then return end
        hideTitleTooltip()
        frame.dragging = true
        frame:StartMoving()
    end)
    grip:SetScript("OnDragStop", function() stopMoving(frame) end)
    local lock = CreateFrame("Button", nil, frame)
    lock:SetSize(26, 26)
    lock:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -11, -9)
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
    setupResizeHandle(frame)
    frame:SetScript("OnHide", function(self)
        stopResizing(self)
        stopMoving(self)
    end)
    function frame:setTitle(name)
        self.title:SetText(name)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(grip) then showTitleTooltip() end
    end
    frame.empty = ui.text(frame, 22, headerHeight, width - 44, emptyHeight, 15, L("В плане: %d", 0), ui.muted)
    local list = ui.scrollingList(frame, inset, headerHeight, rowWidth, rowHeight, 1, true)
    frame.list = list
    function list:setupRow(row)
        local contentWidth = row:GetWidth()
        row:SetScript("OnClick", function(self)
            if not self.item then return end
            if onTargetClick then onTargetClick(frame, self.item); return end
            local feedback = openTarget(self.item)
            self.feedback = type(feedback) == "string" and feedback or nil
            if self.feedback then showRowTooltip(self) end
        end)
        local icon, _, iconSlot = ui.itemIcon(row, 5, 5, 34)
        row.icon = icon
        row.check = ui.icon(iconSlot, 22, 22, 14, "ObjectiveComplete")
        row.check:SetDrawLayer("OVERLAY")
        row.check:Hide()
        row.name = ui.text(row, textX, 3, contentWidth - textX - 8, 20, 15, "", ui.paper)
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        row.attempts = ui.text(row, textX, 23, contentWidth - textX - 8, 14, 12, "", ui.muted)
        row.attempts:SetMaxLines(1)
        row.value = ui.text(row, 0, 3, 1, 23, 17, "", ui.gold)
        row.value:ClearAllPoints()
        row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -3)
        row.value:SetJustifyH("RIGHT")
        row.value:SetMaxLines(1)
        row.value:SetWordWrap(false)
        row.status = ui.text(row, 0, 25, 1, 15, 11, "", ui.muted)
        row.status:ClearAllPoints()
        row.status:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -25)
        row.status:SetJustifyH("RIGHT")
        row.status:SetMaxLines(1)
        row.status:SetWordWrap(false)
        function row:resize()
            local available = self:GetWidth() - textX - 8
            local valueWidth = math.min(available - 9, math.ceil(self.value:GetUnboundedStringWidth()) + 2)
            local statusWidth = math.min(available - 9, math.ceil(self.status:GetUnboundedStringWidth()) + 2)
            self.value:SetWidth(valueWidth)
            self.status:SetWidth(statusWidth)
            self.name:SetWidth(available - ((self.value:GetText() or "") ~= "" and valueWidth + 8 or 0))
            self.attempts:SetWidth(available - ((self.status:GetText() or "") ~= "" and statusWidth + 8 or 0))
            if self.item then fitRowName(self.name, self.displayName) end
        end
        row:SetScript("OnEnter", showRowTooltip)
        row:SetScript("OnLeave", hideRowTooltip)
        row:SetScript("OnHide", hideRowTooltip)
    end
    for _, row in ipairs(list.rows) do list:setupRow(row) end
    local resetTimer, refreshAt
    local function cancelResetTimer()
        if resetTimer then resetTimer:Cancel() end
        resetTimer, refreshAt = nil, nil
    end
    local function refreshAtReset(expires)
        if not expires or (refreshAt and refreshAt <= expires) then return end
        cancelResetTimer()
        refreshAt = expires
        resetTimer = C_Timer.NewTimer(math.max(1, expires - GetServerTime()), function()
            resetTimer, refreshAt = nil, nil
            if frame:IsShown() then frame:refreshRows() end
        end)
    end
    frame:HookScript("OnHide", cancelResetTimer)
    function list:render(row, mount)
        local icon = mount.icon
        if issecretvalue and issecretvalue(icon) then icon = nil end
        if not icon and C_MountJournal and C_MountJournal.GetMountInfoByID then
            icon = select(3, C_MountJournal.GetMountInfoByID(mount.id))
            if issecretvalue and issecretvalue(icon) then icon = nil end
        end
        local stats = atlas.planTargetSummary(mount)
        local attempts, value, color = formatStats(stats)
        local status, complete, expires = atlas.planLootCompletion(mount, frame.characterGUID)
        row.stats, row.lootStatus, row.complete = stats, status, complete
        row.displayName = atlas.displayMountName(mount)
        row.name:SetTextColor(unpack(frame.pinnedID == mount.id and ui.gold or ui.paper))
        local textAlpha = complete and .7 or 1
        row.name:SetAlpha(textAlpha)
        row.attempts:SetText(attempts)
        row.attempts:SetAlpha(textAlpha)
        row.value:SetText(value)
        row.value:SetTextColor(unpack(complete and ui.muted or color))
        row.value:SetAlpha(textAlpha)
        row.status:SetText(status or "")
        row.status:SetAlpha(textAlpha)
        row.icon:SetTexture(icon or 132261)
        row.icon:SetDesaturated(complete == true)
        row.check:SetShown(complete == true)
        row:resize()
        refreshAtReset(expires)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(row) then showRowTooltip(row) end
    end
    function frame:refreshRows()
        self.characterGUID = selectedCharacter()
        list:redraw()
    end
    function frame:refresh(profileID, mounts, pinnedID)
        if self.profileID ~= profileID then list:resetScroll() end
        if self.profileID ~= profileID or list.items ~= mounts then
            for _, profile in ipairs(atlas.planProfiles()) do
                if profile.id == profileID then self:setTitle(profile.name); break end
            end
        end
        self.profileID, self.pinnedID = profileID, pinnedID
        list.items = mounts
        list:SetShown(#mounts > 0)
        self.empty:SetShown(#mounts == 0)
        self:refreshRows()
    end
    local function updateLayout(_, newWidth, newHeight)
        divider:SetWidth(newWidth - 2 * inset)
        grip:SetWidth(newWidth - 34)
        frame.title:SetWidth(newWidth - 91)
        frame.empty:SetWidth(newWidth - 44)
        list:resizeViewport(newWidth - 2 * inset, newHeight - headerHeight - bottomPadding)
    end
    updateLayout(frame, width, height)
    frame:SetScript("OnSizeChanged", updateLayout)
    windows[#windows + 1] = frame
    local _, pinned, percent = atlas.expeditionSettings()
    applyPin(frame, pinned)
    applyTransparency(frame, percent)
    return frame
end

function atlas.refreshExpeditionTracker()
    local enabled = atlas.expeditionSettings()
    if not enabled then
        events:UnregisterEvent(journalEvent)
        events:UnregisterEvent(bagsEvent)
        if tracker then tracker:Hide() end
        return
    end
    local planID = atlas.activePlanID()
    local targets, pendingJournal = atlas.planTargets(true, planID)
    atlas.updateExpeditionAutoHeight(#targets)
    if not tracker then
        tracker = atlas.createExpeditionWindow("MountAtlasExpeditionTracker")
        applyPosition(tracker)
    end
    if pendingJournal then events:RegisterEvent(journalEvent)
    else events:UnregisterEvent(journalEvent) end
    if #targets > 0 then events:RegisterEvent(bagsEvent)
    else events:UnregisterEvent(bagsEvent) end
    tracker:refresh(planID, targets)
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
        for _, frame in ipairs(windows) do
            stopResizing(frame)
            stopMoving(frame)
        end
        applySharedSize()
    elseif event == bagsEvent then
        for _, row in ipairs(tracker.list.rows) do
            if row.item and row.stats and row.stats.watchBags then
                atlas.queueExpeditionStatsRefresh()
                break
            end
        end
    else
        if event == "PLAYER_ENTERING_WORLD" then self:UnregisterEvent(event) end
        atlas.queueExpeditionTrackerRefresh()
    end
end)
