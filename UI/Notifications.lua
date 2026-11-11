local _, atlas = ...
local ui = atlas.ui
local L = atlas.L
local media = LibStub("LibSharedMedia-3.0")
atlas.addTranslations("enUS", {
    ["Скриншот при получении"] = "Screenshot on collection",
    ["Получен после %d попыток"] = "Obtained after %d attempts",
    ["Получен после %d попытки"] = "Obtained after %d attempts",
    ["Получен после 1 попытки"] = "Obtained after 1 attempt",
    ["Размер уведомления"] = "Notification size",
    ["Применить"] = "Apply",
})
local nativeSounds = {
    { id = "wow:achievement-earned", name = "WoW · Получение достижения", kit = 12891 },
    { id = "wow:reward", name = "WoW · Награда", kit = 31578 },
    { id = "wow:achievement", name = "WoW · Меню достижений", kit = 13832 },
    { id = "wow:coin", name = "WoW · Монеты", kit = 120 },
}

local function settings()
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
    return MountAtlasAccountDB.settings
end

function ui.accountCheckbox(parent, x, y, width, label, key, onChanged)
    local button = ui.place(CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate"), parent, x, y, 32, 32)
    button.caption = ui.text(parent, x + 42, y, width - 42, 32, 17, label)
    button:SetHitRectInsets(0, 32 - width, 0, 0)
    button:SetScript("OnClick", function(self)
        settings()[key] = self:GetChecked() == true
        if onChanged then onChanged() end
    end)
    return button
end

local function sounds()
    local list = {}
    for _, sound in ipairs(nativeSounds) do list[#list + 1] = sound end
    for _, name in ipairs(media:List("sound")) do
        local file = media:Fetch("sound", name, true)
        if file and file ~= 1 and file ~= "" then
            list[#list + 1] = { id = "lsm:" .. name, name = name, file = file }
        end
    end
    return list
end

local function selectedSound()
    for _, sound in ipairs(sounds()) do
        if sound.id == settings().rewardSound then return sound end
    end
    return nativeSounds[1]
end

local soundHandle
local positionUnlocked = false
local function notificationScale()
    local value = settings().rewardScale
    if type(value) ~= "number" or value ~= value then return 1 end
    return math.max(.5, math.min(1.5, value))
end
local function soundVolume()
    local value = settings().rewardVolume
    if type(value) ~= "number" or value ~= value then return 1 end
    return math.max(0, math.min(1, value))
end

local function supportsVolume(sound)
    return sound.kit and C_Sound and type(C_Sound.PlaySound) == "function"
end

function atlas.playRewardSound()
    if soundHandle and StopSound then StopSound(soundHandle) end
    soundHandle = nil
    local sound = selectedSound()
    local ok, handle
    if supportsVolume(sound) then
        local volume = soundVolume()
        if volume == 0 then return end
        -- At 100% preserve the kit's native mix, as Rarity's PlaySound(12891) does.
        ok, handle = C_Sound.PlaySound(sound.kit, "SFX", false, false, nil, volume < 1 and volume or nil)
    elseif sound.kit and PlaySound then ok, handle = PlaySound(sound.kit, "SFX")
    elseif sound.file and PlaySoundFile then ok, handle = PlaySoundFile(sound.file, "SFX") end
    soundHandle = ok and handle or nil
end

function atlas.makeNotificationSettings(parent)
    local refreshSoundControls
    local function hideTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
    local function updateSoundControls() refreshSoundControls() end
    ui.text(parent, 0, 80, 470, 26, 16, "Чат", ui.gold)
    local chat = ui.accountCheckbox(parent, 0, 108, 350, "Сообщения в чат", "chatMessages", updateSoundControls)
    ui.text(parent, 0, 140, 480, 24, 14, "Формат сообщения", ui.muted)
    ui.fieldSurface(parent, 0, 166, 614, 40)
    local edit = ui.place(CreateFrame("EditBox", "MountAtlasChatFormat", parent), parent, 10, 166, 594, 40)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(300)
    edit:SetTextInsets(4, 4, 0, 0)
    ui.setFont(edit, 14)
    edit:SetTextColor(unpack(ui.paper))
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    local sample = ui.text(parent, 12, 234, 682, 40, 14, "", ui.mint)
    sample:SetMaxLines(2)
    local applyFormat, applyCheck
    local function savedFormat()
        return settings().chatMessageFormat or atlas.defaultChatMessageFormat()
    end
    local function refreshSample()
        local value = edit:GetText()
        local template = value:match("%S") and value or atlas.defaultChatMessageFormat()
        sample:SetText(atlas.formatAttemptMessage(L("Тлеющий осколок"), 25, 1 - .999 ^ 25, .001, 224025, template))
        local dirty = value ~= savedFormat()
        applyFormat:SetEnabled(dirty)
        applyFormat:SetAlpha(dirty and 1 or .45)
        applyCheck:SetDesaturated(not dirty)
    end
    applyFormat = ui.place(CreateFrame("Button", nil, parent), parent, 622, 170, 32, 32)
    applyCheck = ui.icon(applyFormat, 5.5, 5.5, 21, "ObjectiveComplete")
    applyFormat:SetScript("OnClick", function()
        local value = edit:GetText()
        settings().chatMessageFormat = value:match("%S") and value or nil
        edit:SetText(savedFormat())
        edit:ClearFocus()
        refreshSample()
    end)
    if applyFormat.SetMotionScriptsWhileDisabled then applyFormat:SetMotionScriptsWhileDisabled(true) end
    applyFormat:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); ui.tooltipTitle(L("Применить")); GameTooltip:Show()
    end)
    applyFormat:HookScript("OnLeave", hideTooltip)
    applyFormat:HookScript("OnHide", hideTooltip)
    edit:SetText(savedFormat())
    edit:SetScript("OnTextChanged", refreshSample)
    refreshSample()
    ui.resetButton(parent, 666, 170, function()
        settings().chatMessageFormat = nil
        edit:SetText(atlas.defaultChatMessageFormat())
        refreshSample()
    end)
    -- Tokens are inserted at the current cursor, without replacing typed text.
    for i, token in ipairs({ "{название}", "{попытки}", "{вероятность}" }) do
        local x = (i - 1) * 170
        local button = ui.button(parent, x, 209, 160, 25, function()
            edit:SetFocus(); edit:Insert(L(token))
            refreshSample()
        end)
        local label = ui.text(button, 8, 0, 148, 25, 12, token, ui.gold)
        label:SetJustifyH("LEFT")
    end
    ui.fill(parent, 0, 279, 706, 1, ui.rule)
    ui.text(parent, 0, 284, 470, 28, 16, "Получение маунта", ui.gold)
    local reward = ui.accountCheckbox(parent, 0, 316, 350, "Всплывающее уведомление", "rewardToast", updateSoundControls)
    local screenshot = ui.accountCheckbox(parent, 370, 316, 336, "Скриншот при получении", "rewardScreenshot", updateSoundControls)
    ui.action(parent, 492, 284, 162, 30, "Предпросмотр", nil, function() atlas.previewMountNotification() end)
    local lock, lockIcon
    local function refreshLock()
        ui.setIcon(lockIcon, positionUnlocked and "Unlock" or "Lock")
    end
    lock = ui.place(CreateFrame("Button", nil, parent), parent, 666, 283, 32, 32)
    lock:SetScript("OnClick", function()
        atlas.setNotificationPositionUnlocked(not positionUnlocked)
        refreshLock()
    end)
    lockIcon = ui.icon(lock, 0, 0, 32, "Lock")
    lock:SetScript("OnMouseDown", function() lockIcon:SetVertexColor(.8, .8, .8) end)
    lock:SetScript("OnMouseUp", function() lockIcon:SetVertexColor(1, 1, 1) end)
    lock:SetScript("OnLeave", function() lockIcon:SetVertexColor(1, 1, 1) end)
    lock:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); ui.tooltipTitle(L("Фиксация")); GameTooltip:Show()
    end)
    lock:HookScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    lock:HookScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    ui.text(parent, 0, 351, 210, 32, 14, "Размер уведомления", ui.muted)
    local scaleValue = ui.text(parent, 644, 351, 62, 32, 14, "", ui.gold)
    scaleValue:SetJustifyH("RIGHT")
    local scale = ui.place(CreateFrame("Slider", "MountAtlasNotificationScale", parent), parent, 220, 357, 400, 20)
    scale:SetOrientation("HORIZONTAL")
    scale:SetMinMaxValues(50, 150)
    scale:SetValueStep(5)
    scale:SetObeyStepOnDrag(true)
    ui.fill(scale, 0, 9, 400, 3, ui.rule)
    -- The midpoint marks the original size, independently of the moving thumb.
    ui.fill(scale, 199, 5, 2, 11, ui.gold)
    local scaleThumb = scale:CreateTexture(nil, "OVERLAY")
    scaleThumb:SetColorTexture(unpack(ui.gold))
    scaleThumb:SetSize(5, 16)
    scale:SetThumbTexture(scaleThumb)
    local refreshingScale = false
    scale:SetScript("OnValueChanged", function(_, value)
        scaleValue:SetText(string.format("%d%%", math.floor(value + .5)))
        if not refreshingScale then atlas.setNotificationScale(value / 100) end
    end)
    local soundToggle = ui.accountCheckbox(parent, 0, 385, 282, "Звук уведомления", "rewardSoundEnabled", updateSoundControls)
    local volumeArea = ui.place(CreateFrame("Frame", nil, parent), parent, 334, 385, 372, 32)
    volumeArea:EnableMouse(true)
    local volumeLabel = ui.text(volumeArea, 0, 0, 106, 32, 14, "Громкость", ui.muted)
    local volumeValue = ui.text(volumeArea, 310, 0, 62, 32, 14, "", ui.gold)
    volumeValue:SetJustifyH("RIGHT")
    local volume = ui.place(CreateFrame("Slider", "MountAtlasNotificationVolume", volumeArea), volumeArea, 110, 6, 188, 20)
    volume:SetOrientation("HORIZONTAL")
    volume:SetMinMaxValues(0, 100)
    volume:SetValueStep(5)
    volume:SetObeyStepOnDrag(true)
    ui.fill(volume, 0, 9, 188, 3, ui.rule)
    local thumb = volume:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(unpack(ui.gold))
    thumb:SetSize(5, 16)
    volume:SetThumbTexture(thumb)
    volume:SetScript("OnValueChanged", function(_, value)
        settings().rewardVolume = math.max(0, math.min(100, value)) / 100
        volumeValue:SetText(string.format("%d%%", math.floor(value + .5)))
    end)
    volumeArea:SetScript("OnEnter", function(self)
        if not supportsVolume(selectedSound()) then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L("Для этого звука используется громкость эффектов игры"))
            GameTooltip:Show()
        end
    end)
    volumeArea:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    volumeArea:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
    local menu
    local picker = ui.action(parent, 0, 423, 654, 40, nil, nil, function() menu:SetShown(not menu:IsShown()) end, true)
    local selected = ui.text(picker, 14, 0, 600, 40, 16, "")
    ui.dropdownArrow(picker, 626, 9, 22)
    local play = ui.place(CreateFrame("Button", nil, parent), parent, 666, 427, 32, 32)
    play:SetNormalAtlas("charactercreate-customize-playbutton")
    play:SetPushedAtlas("charactercreate-customize-playbutton-down")
    play:SetScript("OnClick", atlas.playRewardSound)
    play:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP"); ui.tooltipTitle(L("Прослушать")); GameTooltip:Show()
    end)
    play:SetScript("OnLeave", hideTooltip)
    play:SetScript("OnHide", hideTooltip)
    local dismiss = ui.button(parent, 0, 74, 706, 404, function() menu:Hide() end)
    dismiss:ClearHighlightTexture()
    dismiss:SetFrameLevel(parent:GetFrameLevel() + 10)
    dismiss:Hide()
    menu = ui.place(CreateFrame("Frame", nil, parent), parent, 0, 207, 654, 210)
    menu:EnableMouse(true)
    menu:SetFrameLevel(dismiss:GetFrameLevel() + 1)
    local menuSurface = ui.dropdownSurface(menu)
    local choices = ui.scrollingList(menu, 8, 8, 638, 32, 6)
    for _, row in ipairs(choices.rows) do
        row.label = ui.text(row, 10, 0, 606, 30, 15, "")
        row.label:SetMaxLines(1)
    end
    function choices:render(row, sound)
        row.label:SetText(sound.name)
        row.label:SetTextColor(unpack(sound.id == selectedSound().id and ui.gold or ui.paper))
    end
    function choices:onClick(sound)
        settings().rewardSound = sound.id
        selected:SetText(sound.name)
        menu:Hide()
        refreshSoundControls()
    end
    menu:SetScript("OnShow", function()
        choices.items = sounds()
        local height = math.min(6, #choices.items) * 32 + 16
        menu:ClearAllPoints()
        ui.place(menu, parent, 0, 417 - height, 654, height)
        choices:SetHeight(height - 16)
        local xs, ys = { 0, 10, 644, 654 }, { 0, 10, height - 10, height }
        for row = 1, 3 do for col = 1, 3 do
            local texture = menuSurface[(row - 1) * 3 + col]
            texture:ClearAllPoints()
            ui.place(texture, menu, xs[col], ys[row], xs[col + 1] - xs[col], ys[row + 1] - ys[row])
        end end
        choices:redraw(); dismiss:Show()
    end)
    menu:SetScript("OnHide", function() dismiss:Hide() end)
    parent:HookScript("OnHide", function()
        menu:Hide(); edit:ClearFocus()
        edit:SetText(savedFormat())
        atlas.setNotificationPositionUnlocked(false)
    end)
    menu:Hide()
    refreshSoundControls = function()
        local enabled = settings().rewardToast ~= false
        soundToggle:SetEnabled(enabled)
        soundToggle:SetAlpha(enabled and 1 or .4)
        soundToggle.caption:SetAlpha(enabled and 1 or .4)
        local soundEnabled = enabled and settings().rewardSoundEnabled ~= false
        picker:SetEnabled(soundEnabled)
        picker:SetAlpha(soundEnabled and 1 or .4)
        play:SetEnabled(soundEnabled)
        play:SetAlpha(soundEnabled and 1 or .4)
        local volumeEnabled = soundEnabled and supportsVolume(selectedSound())
        if volumeEnabled then volume:Enable() else volume:Disable() end
        volume:EnableMouse(volumeEnabled == true)
        volumeArea:SetAlpha(volumeEnabled and 1 or .4)
        hideTooltip(volumeArea)
        if not soundEnabled then menu:Hide(); hideTooltip(play) end
    end
    local function refresh()
        local values = settings()
        chat:SetChecked(values.chatMessages ~= false)
        screenshot:SetChecked(values.rewardScreenshot == true)
        reward:SetChecked(values.rewardToast ~= false)
        soundToggle:SetChecked(values.rewardSoundEnabled ~= false)
        edit:SetText(savedFormat())
        selected:SetText(selectedSound().name)
        volume:SetValue(soundVolume() * 100)
        volumeValue:SetText(string.format("%d%%", math.floor(soundVolume() * 100 + .5)))
        refreshingScale = true
        scale:SetValue(notificationScale() * 100)
        scaleValue:SetText(string.format("%d%%", math.floor(notificationScale() * 100 + .5)))
        refreshingScale = false
        refreshLock()
        refreshSoundControls()
        refreshSample()
    end
    parent:SetScript("OnShow", refresh)
    return refresh
end

-- Only actual loot and learning events can announce a reward.
local pending, seen, toast = {}, {}, nil
local nextReward
local mascotPoses = { 1, 2, 3, 4, 6, 7, 8, 9 }
local lastMascotPose
local function nextMascotPose()
    -- Sample all remaining poses equally; consecutive rewards never repeat.
    local pose = math.random(lastMascotPose and #mascotPoses - 1 or #mascotPoses)
    if lastMascotPose and pose >= lastMascotPose then pose = pose + 1 end
    lastMascotPose = pose
    return mascotPoses[pose]
end
local function attemptCaption(count)
    if not count then return "" end
    if count == 1 then return L("Получен после 1 попытки") end
    local ending = count % 10 == 1 and count % 100 ~= 11
    return L(ending and "Получен после %d попытки" or "Получен после %d попыток", count)
end
local function screenshotReward(reward, frame)
    if reward.preview or settings().rewardScreenshot ~= true or type(Screenshot) ~= "function" then return end
    C_Timer.After(1, function()
        if settings().rewardScreenshot ~= true then return end
        if frame and (not frame:IsShown() or frame.reward ~= reward) then return end
        Screenshot()
    end)
end
local function applyToastPosition(frame)
    local position = settings().rewardPosition
    local function valid(value) return type(value) == "number" and value >= 0 and value <= 1 end
    frame:SetScale(notificationScale())
    -- SetPoint offsets are in the toast's units. Keep its screen-space centre
    -- stationary when its own scale differs from UIParent's scale.
    local unit = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
    frame:ClearAllPoints()
    if type(position) == "table" and valid(position.x) and valid(position.y) then
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", position.x * UIParent:GetWidth() * unit, position.y * UIParent:GetHeight() * unit)
    else
        frame:SetPoint("CENTER", UIParent, "BOTTOM", 0, (165 + frame:GetHeight() / 2) * unit)
    end
end

local function stopMoving(frame)
    if not frame.dragging then return end
    frame:StopMovingOrSizing()
    frame.dragging = nil
    local x, y = frame:GetCenter()
    local width, height = UIParent:GetSize()
    if not x or not y or width <= 0 or height <= 0 then return end
    local scale = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    settings().rewardPosition = {
        x = math.max(0, math.min(1, (x * scale - (UIParent:GetLeft() or 0)) / width)),
        y = math.max(0, math.min(1, (y * scale - (UIParent:GetBottom() or 0)) / height)),
    }
    applyToastPosition(frame)
end

function atlas.setNotificationScale(value)
    if type(value) ~= "number" or value ~= value then return end
    if toast then stopMoving(toast) end
    settings().rewardScale = math.max(.5, math.min(1.5, math.floor(value * 20 + .5) / 20))
    if toast then applyToastPosition(toast) end
    if not toast or not toast:IsShown() then atlas.previewMountNotification() end
end

local function makeToast()
    local frame = CreateFrame("Frame", "MountAtlasRewardToast", UIParent)
    frame:SetSize(480, 116)
    applyToastPosition(frame)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if positionUnlocked and self.preview then self.dragging = true; self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", stopMoving)
    frame:SetScript("OnHide", function(self) stopMoving(self); self.hovered = false end)
    frame:SetScript("OnEnter", function(self)
        self.hovered = true
        self.age = .25
        self:SetAlpha(1)
    end)
    frame:SetScript("OnLeave", function(self)
        self.hovered = false
        self.age = .25
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            stopMoving(self)
            self:SetScript("OnUpdate", nil)
            self:Hide()
            nextReward()
        end
    end)
    ui.rewardFrame(frame, 0, -12, 480, 124)
    local mascot = frame:CreateTexture(nil, "ARTWORK")
    ui.place(mascot, frame, 0, -12, 126, 126)
    frame.mascot = mascot
    mascot:SetVertexColor(.90, .90, .90)
    ui.text(frame, 130, 20, 236, 23, 13, "Новый маунт в коллекции", ui.gold)
    frame.nameGlow = {}
    for _, offset in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 },
        { -1.5, -1.5 }, { 1.5, -1.5 }, { -1.5, 1.5 }, { 1.5, 1.5 } }) do
        local glow = ui.text(frame, 130 + offset[1], 52 + offset[2], 236, 45, 18, "", { 1, .56, .12 })
        glow.atlasGameText = true
        glow.offsetX, glow.offsetY = offset[1], offset[2]
        glow:SetMaxLines(2)
        glow:SetDrawLayer("ARTWORK")
        glow:SetAlpha(0)
        frame.nameGlow[#frame.nameGlow + 1] = glow
    end
    frame.name = ui.text(frame, 130, 52, 236, 45, 18, "", { 1, .74, .28 })
    frame.name.atlasGameText = true
    frame.name:SetMaxLines(2)
    frame.attempts = ui.text(frame, 130, 87, 236, 19, 12, "", ui.muted)
    frame.attempts:SetMaxLines(1)
    local icon, _, iconSlot = ui.itemIcon(frame, 378, 26, 64)
    frame.icon = icon
    frame.iconGlow = {}
    for i = 0, 23 do
        local tail = i % 8
        local spark = iconSlot:CreateTexture(nil, "OVERLAY", nil, 2)
        spark:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\SoftGlow.tga")
        spark:SetBlendMode("ADD")
        spark:SetVertexColor(1, .62 + .30 * (1 - tail / 8), .16 + .48 * (1 - tail / 8))
        spark:SetAlpha(.95 * (1 - tail / 8) ^ 1.6)
        frame.iconGlow[#frame.iconGlow + 1] = spark
    end
    function frame:updateIconGlow(age)
        local edge = 63
        for i, spark in ipairs(self.iconGlow) do
            local tail, stream = (i - 1) % 8, math.floor((i - 1) / 8)
            local p = (age / 3.2 * edge * 4 + stream * edge * 4 / 3 - tail * 3.5) % (edge * 4)
            local x, y
            if p < edge then x, y = p, 0
            elseif p < edge * 2 then x, y = edge, p - edge
            elseif p < edge * 3 then x, y = edge * 3 - p, edge
            else x, y = 0, edge * 4 - p end
            local size = tail == 0 and 18 or 12
            spark:ClearAllPoints()
            ui.place(spark, self, 378.5 + x - size / 2, 26.5 + y - size / 2, size, size)
        end
    end
    frame:Hide()
    return frame
end

nextReward = function()
    if toast and toast:IsShown() then return end
    local reward = table.remove(pending, 1)
    if not reward then return end
    local values = settings()
    if values.rewardToast ~= false and values.rewardSoundEnabled ~= false then atlas.playRewardSound() end
    if values.rewardToast == false and not reward.preview then screenshotReward(reward); nextReward(); return end
    toast = toast or makeToast()
    applyToastPosition(toast)
    toast.reward = reward
    toast.preview = reward.preview
    -- Choose only when a new toast starts, not on hover, fading or repositioning.
    toast.mascotPose = nextMascotPose()
    toast.mascot:SetTexture(string.format("Interface\\AddOns\\PawAtlas\\Media\\Illustrations\\Rewards\\GryphonReward%02d.tga", toast.mascotPose))
    toast.name:SetText(reward.name)
    local nameY, nameHeight = reward.attempts and 44 or 52, reward.attempts and 40 or 45
    toast.name:ClearAllPoints(); ui.place(toast.name, toast, 130, nameY, 236, nameHeight)
    toast.attempts:SetText(attemptCaption(reward.attempts))
    toast.attempts:SetShown(reward.attempts ~= nil)
    for _, glow in ipairs(toast.nameGlow) do
        glow:ClearAllPoints(); ui.place(glow, toast, 130 + glow.offsetX, nameY + glow.offsetY, 236, nameHeight)
        glow:SetText(reward.name); glow:SetAlpha(0)
    end
    toast.icon:SetTexture(reward.icon)
    toast:SetAlpha(0)
    toast.age = 0
    toast.glowAge = 0
    toast:updateIconGlow(0)
    toast.hovered = false
    toast:SetScript("OnUpdate", function(self, elapsed)
        self.glowAge = self.glowAge + elapsed
        self:updateIconGlow(self.glowAge)
        local pulse = math.sin(math.pi * math.min(1, self.glowAge / 1.8)) ^ 2
        for _, glow in ipairs(self.nameGlow) do glow:SetAlpha(.025 + .16 * pulse) end
        self.name:SetTextColor(1, .74 + .14 * pulse, .28 + .36 * pulse)
        if self.hovered or (self.preview and positionUnlocked) then self:SetAlpha(1); return end
        self.age = self.age + elapsed
        local age = self.age
        self:SetAlpha(math.max(0, math.min(1, age / .25, (6.8 - age) / .6)))
        if age >= 6.8 then
            self:SetScript("OnUpdate", nil); self:Hide(); nextReward()
        end
    end)
    toast:Show()
    screenshotReward(reward, toast)
end

function atlas.setNotificationPositionUnlocked(value)
    positionUnlocked = value == true
    if positionUnlocked then
        atlas.previewMountNotification()
    else
        for i = #pending, 1, -1 do if pending[i].preview then table.remove(pending, i) end end
        if toast then
            stopMoving(toast)
            if toast.preview then toast:SetScript("OnUpdate", nil); toast:Hide() end
        end
        nextReward()
    end
end

function atlas.previewMountNotification()
    local candidate
    for _, mount in ipairs(atlas.mounts or {}) do
        candidate = candidate or mount
        local collected = select(11, C_MountJournal.GetMountInfoByID(mount.id))
        if not (issecretvalue and issecretvalue(collected)) and collected == true then candidate = mount; break end
    end
    if not candidate then return end
    for i = #pending, 1, -1 do if pending[i].preview then table.remove(pending, i) end end
    local saved = atlas.acquisitionAttempts and atlas.acquisitionAttempts("mount:" .. candidate.id)
    pending[#pending + 1] = { name = candidate.name, icon = candidate.icon or 132261,
        attempts = saved and saved.attempts or 42, preview = true }
    -- Repeated clicks restart only the example, never interrupt a real reward.
    if toast and toast.preview then toast:SetScript("OnUpdate", nil); toast:Hide() end
    nextReward()
end

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function lootNotifications()
    local account = MountAtlasAccountDB
    if type(account) == "table" and type(account.mountLootNotifications) == "table" then
        return account.mountLootNotifications
    end
end

local function received(id, retry, fromLoot)
    local ok, name, _, icon, _, _, _, _, _, _, _, collected = pcall(C_MountJournal.GetMountInfoByID, id)
    if not ok or not readable(name) or type(name) ~= "string" or name == ""
        or not readable(collected) or type(collected) ~= "boolean" or (not fromLoot and not collected) then
        if retry < 60 then C_Timer.After(.5, function() received(id, retry + 1, fromLoot) end)
        else seen[id] = nil end
        return
    end
    if not fromLoot and atlas.completePlanTarget then atlas.completePlanTarget(id) end
    if atlas.mountLootAttemptsPending(id) then
        C_Timer.After(.25, function() received(id, retry, fromLoot) end)
        return
    end
    if not readable(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then icon = 132261 end
    local acquired
    for _, mount in ipairs(atlas.mounts) do
        if mount.id == id then acquired = atlas.captureMountAcquisition(mount); break end
    end
    if fromLoot and collected ~= true then
        -- Keep the loot-to-learn deduplication across reloads and characters.
        if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
        local notifications = lootNotifications() or {}
        notifications[id] = true
        MountAtlasAccountDB.mountLootNotifications = notifications
    end
    pending[#pending + 1] = { name = name, icon = icon, attempts = acquired and acquired.attempts }
    nextReward()
end

local function announceMountItem(item, trackedReward)
    local id = C_MountJournal.GetMountFromItem(item)
    if not readable(id) or type(id) ~= "number" or id <= 0 then return false end
    local collected = select(11, C_MountJournal.GetMountInfoByID(id))
    if readable(collected) and collected == false then
        if atlas.completePlanTarget then atlas.completePlanTarget(id) end
        if seen[id] then return true end
        seen[id] = true
        if trackedReward then
            -- Reserve the notification now. The existing .1s loot timer
            -- settles the tracked award before we display its attempt count.
            C_Timer.After(.2, function() received(id, 0, true) end)
        else
            received(id, 0, true)
        end
    end
    return true
end

local waitingItemData = {}
function atlas.notifyMountItemLoot(item, trackedReward)
    if not C_MountJournal.GetMountFromItem or announceMountItem(item, trackedReward) or waitingItemData[item] then return end
    if not C_Item or not C_Item.GetItemInfoInstant then return end
    local _, _, _, _, _, class, subclass = C_Item.GetItemInfoInstant(item)
    local misc = Enum and Enum.ItemMiscellaneousSubclass
    if not trackedReward and not (misc and Enum.ItemClass and readable(class) and readable(subclass)
        and class == Enum.ItemClass.Miscellaneous
        and subclass == misc.Mount) then return end
    if not Item or not Item.CreateFromItemID
        or (C_Item.IsItemDataCachedByID and C_Item.IsItemDataCachedByID(item)) then return end
    waitingItemData[item] = true
    Item:CreateFromItemID(item):ContinueOnItemLoad(function()
        waitingItemData[item] = nil
        announceMountItem(item, trackedReward)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("DISPLAY_SIZE_CHANGED")
events:RegisterEvent("UI_SCALE_CHANGED")
events:SetScript("OnEvent", function(self, event, id)
    if event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        self:RegisterEvent("NEW_MOUNT_ADDED")
    elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        if toast then toast:StopMovingOrSizing(); toast.dragging = nil; applyToastPosition(toast) end
    elseif event == "NEW_MOUNT_ADDED" and readable(id) and type(id) == "number" then
        local notifications = lootNotifications()
        if notifications and notifications[id] then
            notifications[id] = nil
            seen[id] = true
            if atlas.completePlanTarget then atlas.completePlanTarget(id) end
            return
        end
        if seen[id] then return end
        seen[id] = true
        received(id, 0)
    end
end)
