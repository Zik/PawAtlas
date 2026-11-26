local addonName, atlas = ...
local ui = atlas.ui
local L = atlas.L
local controls = "Interface\\AddOns\\PawAtlas\\Media\\Controls\\"
local projectURL = "https://github.com/Zik/PawAtlas"
local projectPopup = "PAWATLAS_PROJECT_URL"
StaticPopupDialogs[projectPopup] = {
    text = "",
    button1 = CLOSE,
    hasEditBox = true,
    editBoxWidth = 280,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnShow = function(self)
        local edit = self:GetEditBox()
        edit:SetText(projectURL)
        edit:SetFocus()
        edit:HighlightText()
    end,
    OnHide = function(self)
        local edit = self:GetEditBox()
        edit:ClearFocus()
        edit:SetText("")
    end,
    EditBoxOnTextChanged = function(self)
        local dialog = self:GetParent()
        if dialog.which ~= projectPopup or not dialog:IsShown() or self:GetText() == projectURL then return end
        self:SetText(projectURL)
        self:HighlightText()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function settingSlider(parent, name, x, y, width, minimum, maximum, step)
    local slider = ui.place(CreateFrame("Slider", name, parent), parent, x, y, width, 20)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(minimum, maximum)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    ui.fill(slider, 0, 9, width, 3, { .32, .39, .44 })
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(unpack(ui.gold))
    thumb:SetSize(5, 17)
    slider:SetThumbTexture(thumb)
    return slider
end

local function makeReminderList(parent, x, label)
    ui.text(parent, x, 129, 338, 24, 17, label, ui.gold)
    local list = ui.scrollingList(parent, x, 162, 338, 38, 8)
    local function showRewards(row)
        local event = row.item
        if not event then return end
        if not GameTooltip:IsOwned(row) then GameTooltip:SetOwner(row, "ANCHOR_TOP") end
        ui.tooltipTitle(atlas.displayName(event.name), unpack(ui.gold))
        for _, reward in ipairs(event.rewards) do
            local icon = ("|T%s:16:16:0:0|t "):format(reward.icon or 134400)
            local name = icon .. atlas.displayName(reward.name)
            ui.tooltipLine(atlas.qualityText(name, atlas.mountDisplayQuality(reward.mount)), ui.paper[1], ui.paper[2], ui.paper[3], true)
        end
        GameTooltip:Show()
    end
    local function hideRewards(row)
        if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    end
    for _, row in ipairs(list.rows) do
        ui.fill(row, 0, 33, 330, 1, ui.rule):SetAlpha(.55)
        row.icon = ui.squareIcon(row, 4, 2, 30)
        row.name = ui.text(row, 44, 0, 254, 33, 15, "")
        row.name.atlasGameText = true
        row.name:SetMaxLines(2)
        row.check = ui.place(CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate"), row, 301, 3, 26, 26)
        row.check:EnableMouse(false)
        row.mixed = ui.fill(row.check, 8, 12, 10, 2, ui.gold)
        row.mixed:SetDrawLayer("OVERLAY")
        row:SetScript("OnEnter", showRewards)
        row:SetScript("OnLeave", hideRewards)
        row:SetScript("OnHide", hideRewards)
    end
    function list:render(row, event)
        row.name:SetText(atlas.displayName(event.name))
        row.name:SetTextColor(unpack(event.muted and ui.muted or ui.paper))
        row.icon:SetTexture(event.icon or 134400)
        if event.icon == 2176723 then
            -- A square crop of Kraulok's head within the 128 × 64 portrait.
            row.icon:SetTexCoord(44 / 128, 108 / 128, 0, 1)
        elseif event.icon == 235442 or event.icon == 235485 then
            -- Brewfest and Winter Veil use a shorter banner at the top left.
            row.icon:SetTexCoord(14 / 128, 78 / 128, 2 / 128, 66 / 128)
        elseif not event.worldQuest and event.icon then
            -- Blizzard calendar artwork occupies the first 91 pixels of a 128px tile.
            row.icon:SetTexCoord(2 / 128, 89 / 128, 2 / 128, 89 / 128)
        else
            row.icon:SetTexCoord(.08, .92, .08, .92)
        end
        row.check:SetChecked(not event.muted and not event.mixed)
        row.mixed:SetShown(event.mixed == true)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(row) then showRewards(row) end
    end
    function list:onClick(event)
        if atlas.setEventReminderGroupMuted then
            atlas.setEventReminderGroupMuted(event.key, not event.muted and not event.mixed)
        end
    end
    return list
end

function atlas.makeSettings(parent)
    local panel = CreateFrame("Frame", "MountAtlasSettings", parent)
    panel:Hide()
    ui.place(panel, parent, 12, 83, 1016, 478)
    panel:EnableMouse(true)
    ui.fill(panel, 236, 18, 1, 438, ui.rule):SetAlpha(.65)
    ui.icon(panel, 17, 23, 23, "Settings"):SetVertexColor(unpack(ui.gold))
    ui.text(panel, 51, 16, 177, 38, 22, "Настройки", ui.gold)
    local sections = {}
    local function selectSection(selected)
        for _, section in ipairs(sections) do
            local active = section.frame == selected
            section.frame:SetShown(active)
            section.tab:setActive(active)
        end
    end
    local function makeSection(label, icon, hasTabs)
        local frame = ui.place(CreateFrame("Frame", nil, panel), panel, 266, 0, 706, 478)
        ui.text(frame, 0, 20, 690, 38, 22, label):SetMaxLines(1)
        if not hasTabs then ui.fill(frame, 0, 70, 706, 1, ui.rule):SetAlpha(.8) end
        local tab = ui.button(panel, 3, 70 + #sections * 45, 233, 43, function() selectSection(frame) end)
        local highlight = ui.fill(tab, 0, 0, 233, 43, { .12, .19, .25 })
        highlight:SetGradient("HORIZONTAL", CreateColor(.12, .20, .26, .95), CreateColor(.12, .20, .26, 0))
        local marker = ui.fill(tab, 0, 0, 3, 43, ui.gold)
        marker:SetDrawLayer("ARTWORK")
        local artwork = tab:CreateTexture(nil, "ARTWORK")
        ui.place(artwork, tab, 19, 11, 20, 20)
        artwork:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\" .. icon .. ".tga")
        local caption = ui.text(tab, 53, 0, 168, 43, 16, label)
        caption:SetMaxLines(2)
        function tab:setActive(active)
            highlight:SetShown(active)
            marker:SetShown(active)
            artwork:SetVertexColor(unpack(active and ui.gold or { .72, .61, .40 }))
            caption:SetTextColor(unpack(active and ui.paper or ui.muted))
        end
        sections[#sections + 1] = { frame = frame, tab = tab }
        return frame
    end
    local fonts = makeSection("Интерфейс", "Scroll")
    local expeditionSection = makeSection("Режим похода", "Route")
    local notifications = makeSection("Уведомления", "Bell", true)
    local eventSection = makeSection("События", "Calendar")
    local account = makeSection("Статистика", "Chance")
    local integrations = makeSection("Интеграции", "All")
    local information = makeSection("Об аддоне", "Book")
    ui.brandIcon(information, 1, 99, 64)
    ui.text(information, 84, 96, 600, 36, 25, "PawAtlas", ui.gold)
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version") or ""
    local author = ui.text(information, 84, 133, 600, 24, 14, "", ui.muted)
    information:EnableMouse(true)
    information:SetHyperlinksEnabled(true)
    information:SetScript("OnHyperlinkClick", function(_, link)
        if link ~= "pawatlas:project" then return end
        StaticPopupDialogs[projectPopup].text = L("Проект PawAtlas")
        StaticPopup_Show(projectPopup)
    end)
    ui.fill(information, 0, 189, 706, 1, ui.rule)
    ui.text(information, 0, 204, 194, 28, 16, "Языки интерфейса", ui.muted)
    for index, language in ipairs({ { "ruRU", "Русский" }, { "enUS", "English" } }) do
        local x = 198 + (index - 1) * 124
        local flag = ui.place(information:CreateTexture(nil, "ARTWORK"), information, x, 210, 24, 16)
        flag:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Flags\\" .. language[1] .. ".tga")
        local name = ui.text(information, x + 32, 204, 90, 28, 16, "")
        name.atlasGameText = true
        name:SetText(language[2])
    end
    ui.fill(information, 0, 246, 706, 1, ui.rule)
    ui.text(information, 0, 254, 690, 54, 16,
        "Данные: журнал коллекции Blizzard, Rarity: Collector’s Edition, Simple Armory, WoWthing, HandyNotes и Wowhead", ui.paper)
    ui.text(information, 0, 318, 690, 50, 16,
        "Библиотеки: Ace3, LibStub, CallbackHandler, LibSharedMedia и LibDataBroker", ui.paper)
    ui.text(information, 0, 385, 690, 48, 15,
        "Спасибо авторам этих проектов и сообществу коллекционеров", ui.gold)
    local refreshNotifications = atlas.makeNotificationSettings(notifications)
    local characterCount = ui.text(account, 0, 99, 280, 34, 22, "", ui.gold)
    characterCount:SetMaxLines(1)
    ui.text(integrations, 0, 87, 440, 26, 17, "Rarity", ui.gold)
    local importResult = ui.text(integrations, 0, 169, 550, 30, 15, "", ui.muted)
    importResult:SetMaxLines(1)
    local importDetails = ui.place(CreateFrame("Frame", nil, integrations), integrations, 300, 204, 406, 249)
    importDetails:SetFrameLevel(integrations:GetFrameLevel() + 8)
    importDetails:EnableMouse(true)
    ui.dropdownSurface(importDetails)
    local skippedHeading = ui.text(importDetails, 12, 5, 382, 24, 15, "", ui.gold)
    local skippedEntries = ui.scrollingList(importDetails, 8, 30, 390, 42, 5)
    local skipReasons = {
        unmapped = "Маунт не сопоставлен", incompatible = "Несовместимый счётчик", unverified = "Источник не подтверждён",
        unsupported = "Источник не поддерживается", untracked = "Источник не отслеживается",
        unit_mismatch = "Разные единицы учёта", multiple_items = "Требуется несколько предметов",
    }
    for _, row in ipairs(skippedEntries.rows) do
        row:ClearHighlightTexture()
        ui.fill(row, 0, 39, 382, 1, ui.rule):SetAlpha(.6)
        row.name = ui.text(row, 8, 1, 366, 20, 15, "")
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.reason = ui.text(row, 8, 19, 366, 19, 14, "", ui.muted)
        row.reason:SetMaxLines(1)
    end
    function skippedEntries:onClick() end
    function skippedEntries:render(row, entry)
        local name = type(entry.name) == "string" and atlas.displayName(entry.name)
        row.name:SetText(name and name:gsub("|", "||") or "—")
        row.reason:SetText(skipReasons[entry.reason] or skipReasons.incompatible)
    end
    local detailsButton = ui.action(integrations, 570, 169, 136, 30, "Подробности", nil, function()
        importDetails:SetShown(not importDetails:IsShown())
    end)
    importDetails:SetScript("OnShow", function() detailsButton:setActive(true) end)
    importDetails:SetScript("OnHide", function() detailsButton:setActive(false) end)
    importDetails:Hide()
    detailsButton:Hide()
    local shownEntries, shownSkipped
    local refreshImport, clearImportButton, clearAcceptButton, clearImportOnly
    local importButton = ui.action(integrations, 0, 120, 224, 38, "Импорт из Rarity", nil, function()
        if atlas.startRarityImport then atlas.startRarityImport(refreshImport) end
    end)
    refreshImport = function(state)
        state = state or (atlas.rarityImportProgress and atlas.rarityImportProgress())
        local running = state and state.running
        importButton:SetEnabled(not running)
        importButton:SetAlpha(running and .55 or 1)
        local canClearImport = not running and type(atlas.clearRarityImport) == "function"
        if clearImportButton then
            clearImportButton:SetEnabled(canClearImport)
            clearImportButton:SetAlpha(canClearImport and 1 or .55)
        end
        if clearAcceptButton and clearImportOnly then
            clearAcceptButton:SetEnabled(canClearImport)
            clearAcceptButton:SetAlpha(canClearImport and 1 or .55)
        end
        local result = not running and (state and state.result or (atlas.rarityImportSummary and atlas.rarityImportSummary()))
        local skipped = result and result.skipped or 0
        local entries = result and result.skipEntries or nil
        if shownEntries ~= entries or shownSkipped ~= skipped then
            importDetails:Hide()
            shownEntries, shownSkipped = entries, skipped
            detailsButton:SetShown(skipped > 0)
            local shown = entries and #entries or 0
            local remaining = shown > 0 and skipped - shown or 0
            skippedHeading:SetText(remaining > 0 and (L("Пропущено: %d", shown) .. "  +" .. remaining)
                or L("Пропущено: %d", skipped))
            skippedEntries.offset = 0
            skippedEntries.items = entries or {}
            skippedEntries:redraw()
            importDetails:SetHeight(39 + 42 * math.min(shown, 5))
        end
        if running then
            importResult:SetText(L("Импорт: %d / %d", state.processed, state.total))
        else
            local message = ""
            if result then
                if result.status == "unavailable" then message = "Rarity: нет данных"
                elseif result.status == "error" then message = "Не удалось завершить импорт"
                elseif result.status == "empty" then message = skipped > 0 and L("Пропущено: %d", skipped) or "Rarity: нет данных"
                elseif type(result.updated) == "number" then
                    message = result.updated > 0 and L("Обновлено маунтов: %d", result.updated) or "Всё актуально"
                elseif result.time then message = L("Импортировано маунтов: %d", result.count or 0) end
            end
            importResult:SetText(message)
        end
    end
    local function showImportTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Импорт из Rarity"))
        ui.tooltipLine(L("Включи Rarity для этого персонажа. Импортируются совместимые счётчики маунтов из активного профиля; повторный импорт не складывает одну историю дважды."), 1, 1, 1, true)
        GameTooltip:Show()
    end
    importButton:HookScript("OnEnter", showImportTooltip)
    local function hideImportTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
    importButton:HookScript("OnLeave", hideImportTooltip)
    importButton:HookScript("OnHide", hideImportTooltip)
    ui.text(account, 42, 138, 80, 24, 14, "Персонаж", ui.gold)
    do
        local help = ui.place(CreateFrame("Frame", nil, account), account, 118, 138, 24, 24)
        help:EnableMouse(true)
        local glyph = ui.text(help, 0, 0, 24, 24, 15, "?", ui.gold)
        glyph:SetJustifyH("CENTER")
        help:SetScript("OnEnter", function(self)
            glyph:SetTextColor(1, .91, .65)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L("Персонаж"))
            ui.tooltipLine(L("Чтобы добавить персонажа, зайди им в игру с включённым аддоном"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        local function clearHelp(self)
            glyph:SetTextColor(unpack(ui.gold))
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end
        help:SetScript("OnLeave", clearHelp)
        help:SetScript("OnHide", clearHelp)
    end
    ui.text(account, 300, 138, 240, 24, 14, "Сервер", ui.gold)
    local levelHeading = ui.text(account, 560, 138, 80, 24, 14, "Уровень", ui.gold)
    levelHeading:SetJustifyH("RIGHT")
    local confirm, dialog = ui.journalDialog(panel, "MountAtlasRemoveCharacter", 460, 222)
    local prompt = ui.text(dialog, 20, 20, 420, 30, 19, "Убрать персонажа из учтённых?", ui.gold)
    prompt:SetJustifyH("CENTER")
    ui.fill(dialog, 24, 54, 412, 1, ui.rule)
    local characterName = ui.text(dialog, 24, 64, 412, 24, 16, "")
    characterName.atlasGameText = true
    characterName:SetJustifyH("CENTER")
    characterName:SetMaxLines(1)
    local explanation = ui.text(dialog, 28, 91, 404, 55, 15, "При следующем входе с включённым аддоном персонаж появится снова", ui.muted)
    explanation:SetJustifyH("CENTER")
    local pendingGUID
    ui.action(dialog, 60, 164, 160, 35, "Убрать", nil, function()
        if pendingGUID and atlas.removeAccountCharacter then atlas.removeAccountCharacter(pendingGUID) end
        confirm:Hide()
        atlas.refreshAccountSettings()
        if atlas.refreshDetails then atlas.refreshDetails() end
    end)
    ui.action(dialog, 240, 164, 160, 35, "Отмена", nil, function() confirm:Hide() end)
    confirm:SetScript("OnHide", function() pendingGUID = nil end)
    local clearConfirm, clearDialog = ui.journalDialog(panel, "MountAtlasClearStatistics", 580, 268)
    local clearTitle = ui.text(clearDialog, 24, 20, 532, 30, 20, "Очистить всю статистику", ui.gold)
    clearTitle:SetJustifyH("CENTER")
    ui.fill(clearDialog, 24, 54, 532, 1, ui.rule)
    local clearExplanation = ui.text(clearDialog, 28, 66, 524, 124, 16,
        "Удалить сохранённую статистику попыток всех персонажей, включая данные, импортированные из Rarity? История убийств из WoW будет загружена снова.", ui.paper)
    clearExplanation:SetJustifyH("CENTER")
    clearAcceptButton = ui.action(clearDialog, 110, 214, 170, 35, "Очистить", nil, function()
        if clearImportOnly then
            local state = atlas.rarityImportProgress and atlas.rarityImportProgress()
            if (state and state.running) or type(atlas.clearRarityImport) ~= "function" then return end
            atlas.clearRarityImport()
        elseif atlas.clearAttemptStatistics then atlas.clearAttemptStatistics() end
        clearConfirm:Hide()
    end)
    ui.action(clearDialog, 300, 214, 170, 35, "Отмена", nil, function() clearConfirm:Hide() end)
    local function showClearConfirmation(importOnly)
        clearImportOnly = importOnly
        clearTitle:SetText(importOnly and "Удалить импорт Rarity" or "Очистить всю статистику")
        clearExplanation:SetText(importOnly
            and "Удалить импортированные счётчики Rarity? Попытки, записанные Атласом маунтов, и история убийств из WoW сохранятся"
            or "Удалить сохранённую статистику попыток всех персонажей, включая данные, импортированные из Rarity? История убийств из WoW будет загружена снова.")
        clearAcceptButton.caption:SetText(importOnly and "Удалить" or "Очистить")
        clearAcceptButton:SetEnabled(true)
        clearAcceptButton:SetAlpha(1)
        refreshImport()
        clearConfirm:Show()
    end
    clearImportButton = ui.action(integrations, 470, 120, 236, 38, "Удалить импорт Rarity", nil, function() showClearConfirmation(true) end)
    ui.action(account, 480, 26, 226, 34, "Очистить всю статистику", nil, function() showClearConfirmation(false) end)
    clearConfirm:SetScript("OnHide", function() clearImportOnly = nil end)
    account:SetScript("OnHide", function() confirm:Hide(); clearConfirm:Hide() end)
    integrations:SetScript("OnHide", function() clearConfirm:Hide(); importDetails:Hide() end)
    local characters = ui.scrollingList(account, 0, 170, 706, 42, 7)
    local function showVisibilityTooltip(button)
        local record = button:GetParent().item
        if not record then return end
        local hidden = atlas.isWarbandCharacterHidden(record.guid)
        if not GameTooltip:IsOwned(button) then GameTooltip:SetOwner(button, "ANCHOR_TOP") end
        ui.tooltipTitle(L(hidden and "Показать в отряде" or "Скрыть из отряда"))
        GameTooltip:Show()
    end
    local function hideVisibilityTooltip(button)
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end
    for _, row in ipairs(characters.rows) do
        ui.fill(row, 0, 39, 698, 1, ui.rule):SetAlpha(.6)
        row.icon = ui.icon(row, 42, 7, 24, "Unknown")
        row.name = ui.text(row, 76, 0, 208, 38, 16, "")
        row.realm = ui.text(row, 300, 0, 240, 38, 15, "", ui.muted)
        row.name.atlasGameText = true
        row.realm.atlasGameText = true
        row.level = ui.text(row, 560, 0, 80, 38, 16, "", ui.gold)
        row.visibility = ui.button(row, 6, 5, 28, 28, function()
            local record = row.item
            if not record then return end
            if atlas.setWarbandCharacterHidden(record.guid, not atlas.isWarbandCharacterHidden(record.guid)) then
                atlas.refreshAccountSettings()
            end
        end)
        row.visibility:ClearHighlightTexture()
        local eye = row.visibility:CreateTexture(nil, "ARTWORK")
        eye:SetPoint("CENTER")
        eye:SetSize(18, 18)
        eye:SetVertexColor(.65, .65, .65)
        row.visibility.glyph = eye
        row.visibility:HookScript("OnEnter", showVisibilityTooltip)
        row.visibility:HookScript("OnLeave", hideVisibilityTooltip)
        row.visibility:HookScript("OnHide", hideVisibilityTooltip)
        row.remove = ui.action(row, 659, 5, 28, 28, nil, "Close", function()
            if not row.item then return end
            pendingGUID = row.item.guid
            characterName:SetText(row.item.name .. " · " .. row.item.realm)
            confirm:Show()
        end)
        row.level:SetJustifyH("RIGHT")
        row.name:SetMaxLines(1)
        row.realm:SetMaxLines(1)
    end
    function characters:onClick() end
    function characters:render(row, record)
        local hidden = atlas.isWarbandCharacterHidden(record.guid)
        row.name:SetText(record.name)
        row.name:SetTextColor(unpack(ui.characterClassColor(record)))
        ui.setCharacterClassIcon(row.icon, record)
        row.realm:SetText(record.realm)
        row.level:SetText(record.level or "—")
        row.visibility.glyph:SetTexture(controls .. (hidden and "VisibilityOff.tga" or "VisibilityOn.tga"))
        if GameTooltip:IsOwned(row.visibility) then showVisibilityTooltip(row.visibility) end
    end
    atlas.refreshAccountSettings = function()
        if not account:IsVisible() then return end
        refreshImport()
        characterCount:SetText(L("Учтено персонажей: %d", atlas.accountCharacterCount()))
        characters.items = atlas.accountCharacters(true)
        characters:redraw()
    end
    account:SetScript("OnShow", atlas.refreshAccountSettings)
    local menu
    local dismiss = ui.button(fonts, 0, 74, 706, 404, function() menu:Hide() end)
    dismiss:SetFrameLevel(fonts:GetFrameLevel() + 3)
    dismiss:ClearHighlightTexture()
    dismiss:Hide()
    ui.text(fonts, 0, 96, 338, 26, 16, "Шрифт интерфейса", ui.muted)
    local picker = ui.action(fonts, 0, 126, 338, 36, nil, nil, function()
        menu:SetShown(not menu:IsShown())
    end)
    picker:SetFrameLevel(fonts:GetFrameLevel() + 4)
    local selectedName = ui.text(picker, 12, 0, 284, 36, 16, "")
    selectedName:SetMaxLines(1)
    ui.dropdownArrow(picker, 308, 9, 18)
    menu = ui.place(CreateFrame("Frame", nil, fonts), fonts, 0, 167, 338, 288)
    menu:SetFrameLevel(picker:GetFrameLevel() + 5)
    menu:EnableMouse(true)
    ui.dropdownSurface(menu)
    local choices = ui.scrollingList(menu, 8, 8, 322, 34, 8)
    for _, row in ipairs(choices.rows) do
        row.name = ui.text(row, 12, 0, 290, 30, 16, "")
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        row:SetScript("OnEnter", function(self) self.name:SetTextColor(unpack(ui.gold)) end)
        row:SetScript("OnLeave", function(self)
            if self.item then self.name:SetTextColor(unpack(self.item.id == ui.selectedFont().id and ui.gold or ui.paper)) end
        end)
    end
    function choices:render(row, font)
        row.name:SetText(font.name)
        ui.setFont(row.name, 16, font.path)
        row.name:SetTextColor(unpack((font.id == ui.selectedFont().id or row:IsMouseOver()) and ui.gold or ui.paper))
    end
    function choices:onClick(font)
        ui.applyFont(font.id)
        atlas.refreshFontSettings()
        menu:Hide()
    end
    local sliderWidth, percentX, percentWidth, resetX = 226, 245, 50, 306
    ui.text(fonts, 0, 175, 338, 26, 16, "Размер шрифта", ui.muted)
    local selectedSize = ui.text(fonts, percentX, 201, percentWidth, 32, 15, "", ui.gold)
    selectedSize:SetJustifyH("RIGHT")
    local minimum, maximum = ui.fontScales[1], ui.fontScales[#ui.fontScales]
    local size = settingSlider(fonts, "MountAtlasFontSize", 0, 207, sliderWidth, minimum, maximum, ui.fontScales[2] - minimum)
    local function refreshSize()
        local value = ui.selectedFontScale()
        size:SetValue(value)
        selectedSize:SetText(string.format("%d%%", value))
    end
    size:SetScript("OnValueChanged", function(_, value)
        if value ~= ui.selectedFontScale() then ui.applyFontScale(value) end
        selectedSize:SetText(string.format("%d%%", ui.selectedFontScale()))
    end)
    ui.resetButton(fonts, resetX, 201, function()
        ui.applyFontScale(100)
        refreshSize()
    end)
    ui.text(fonts, 0, 254, 338, 26, 16, "Масштаб окна", ui.muted)
    local windowSize = settingSlider(fonts, "MountAtlasWindowScale", 0, 286, sliderWidth, 75, 125, 5)
    local windowPercent = ui.text(fonts, percentX, 280, percentWidth, 32, 15, "", ui.gold)
    local effectivePercent = ui.text(fonts, percentX, 306, percentWidth, 22, 14, "", ui.muted)
    windowPercent:SetJustifyH("RIGHT")
    effectivePercent:SetJustifyH("RIGHT")
    function atlas.refreshWindowScaleSetting(scale)
        local chosen = atlas.windowScale()
        local effective = math.floor((scale or atlas.effectiveWindowScale()) * 100 + .5)
        if windowSize:GetValue() ~= chosen then windowSize:SetValue(chosen) end
        windowPercent:SetText(("%d%%"):format(chosen))
        effectivePercent:SetText(chosen == effective and "" or ("(%d%%)"):format(effective))
    end
    windowSize:SetScript("OnValueChanged", function(_, value)
        if value ~= atlas.windowScale() then atlas.setWindowScale(value) end
    end)
    ui.resetButton(fonts, resetX, 280, function() atlas.setWindowScale(100) end)
    local movementX = 368
    local movementFade = ui.accountCheckbox(fonts, movementX, 142, 338, "Прозрачность при движении", "windowMovementFade",
        atlas.refreshWindowMovementAlpha)
    ui.setFont(movementFade.caption, 16)
    movementFade.caption:SetMaxLines(1)
    ui.text(fonts, movementX, 175, 338, 26, 16, "Степень прозрачности", ui.muted)
    local movementOpacity = settingSlider(fonts, "MountAtlasWindowMovementTransparency", movementX, 207, sliderWidth,
        0, atlas.windowMovementTransparencyMax, 5)
    local movementPercent = ui.text(fonts, movementX + percentX, 201, percentWidth, 32, 15, "", ui.gold)
    movementPercent:SetJustifyH("RIGHT")
    local function refreshMovementTransparency()
        local enabled, percent = atlas.windowMovementSettings()
        movementFade:SetChecked(enabled)
        movementOpacity:SetValue(percent)
        movementPercent:SetText(("%d%%"):format(percent))
    end
    movementOpacity:SetScript("OnValueChanged", function(_, value, userInput)
        if userInput then atlas.setWindowMovementTransparency(value) end
        movementPercent:SetText(("%d%%"):format(math.floor(value + .5)))
    end)
    ui.resetButton(fonts, movementX + resetX, 201, function()
        atlas.setWindowMovementTransparency()
        refreshMovementTransparency()
    end)
    atlas.refreshFontSettings = function()
        local selected = ui.selectedFont()
        selectedName:SetText(selected.name)
        ui.setFont(selectedName, 16, selected.path)
        choices.items = ui.fonts
        local listHeight = math.min(8, #choices.items) * 34
        choices:SetHeight(listHeight)
        menu:SetHeight(listHeight + 16)
        choices:redraw()
        refreshSize()
        atlas.refreshWindowScaleSetting()
        refreshMovementTransparency()
    end
    menu:SetScript("OnShow", function()
        atlas.refreshFontSettings()
        choices:reveal(ui.selectedFont())
        dismiss:Show()
        picker:setActive(true)
    end)
    local function resetFontPicker()
        dismiss:Hide()
        picker:setActive(false)
    end
    menu:SetScript("OnHide", resetFontPicker)
    fonts:SetScript("OnHide", function()
        menu:Hide()
        resetFontPicker()
    end)
    menu:Hide()
    do
        local faint = CreateColor(.59, .46, .25, 0)
        local bronze = CreateColor(.59, .46, .25, .45)
        local middle = CreateColor(.37, .43, .44, .44)
        local stops = { { 92, faint }, { 126, bronze }, { 213, middle }, { 292, bronze }, { 327, faint } }
        for i = 2, #stops do
            local top, bottom = stops[i - 1], stops[i]
            local line = ui.fill(fonts, 353, top[1], 1, bottom[1] - top[1], { 1, 1, 1 })
            line:SetGradient("VERTICAL", bottom[2], top[2])
        end
    end
    local gameTooltips = ui.accountCheckbox(fonts, 368, 96, 338, "Подсказки в игре", "gameTooltips", function()
        if atlas.initializeGameTooltips then atlas.initializeGameTooltips() end
    end)
    local function settingTooltip(control, label, description)
        control:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L(label))
            ui.tooltipLine(L(description), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        local function hide(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
        control:HookScript("OnLeave", hide)
        control:HookScript("OnHide", hide)
    end
    settingTooltip(gameTooltips, "Подсказки в игре", "Показывать в игровых подсказках информацию PawAtlas: связанного маунта, учтённые попытки и статус «В плане» или «В коллекции».")
    ui.fill(integrations, 0, 222, 706, 1, ui.rule):SetAlpha(.65)
    ui.text(integrations, 0, 234, 690, 26, 17, "Интерфейс", ui.gold)
    local minimap = ui.accountCheckbox(integrations, 0, 272, 338, "Значок миникарты", "minimapIcon")
    settingTooltip(minimap, "Значок миникарты", "ЛКМ — открыть / закрыть")
    minimap:SetScript("OnClick", function(self) atlas.setMinimapButtonShown(self:GetChecked() == true) end)
    atlas.refreshMinimapSetting = function(shown) minimap:SetChecked(shown) end
    local compartment = ui.accountCheckbox(integrations, 368, 272, 338, "Меню модификаций", "addonCompartment")
    settingTooltip(compartment, "Меню модификаций", "ЛКМ — открыть / закрыть")
    compartment:SetScript("OnClick", function(self) atlas.setAddonCompartmentEnabled(self:GetChecked() == true) end)
    ui.fill(integrations, 0, 322, 706, 1, ui.rule):SetAlpha(.65)
    ui.text(integrations, 0, 334, 690, 26, 17, "Метки на карте", ui.gold)
    local function chooseWaypoint(provider)
        atlas.setWaypointProvider(provider)
        atlas.refreshIntegrationSettings()
    end
    local wowWaypoints = ui.action(integrations, 0, 370, 158, 33, "Метки WoW", nil, function() chooseWaypoint("wow") end)
    local tomTomWaypoints = ui.action(integrations, 169, 370, 158, 33, "TomTom", nil, function() chooseWaypoint("tomtom") end)
    local waypointStatus = ui.text(integrations, 342, 366, 356, 40, 14, "", ui.muted)
    waypointStatus:SetMaxLines(2)
    atlas.refreshIntegrationSettings = function()
        compartment:SetChecked(atlas.addonCompartmentEnabled())
        local preference = atlas.waypointPreference() or atlas.waypointProvider()
        local available = atlas.tomTomAvailable()
        wowWaypoints:setActive(preference == "wow")
        tomTomWaypoints:setActive(preference == "tomtom")
        tomTomWaypoints:SetEnabled(available)
        waypointStatus:SetText(available and "" or preference == "tomtom" and "TomTom недоступен. Используются метки WoW."
            or "TomTom недоступен")
    end
    integrations:HookScript("OnShow", function()
        minimap:SetChecked(atlas.minimapButtonShown())
        atlas.refreshIntegrationSettings()
    end)
    integrations:RegisterEvent("ADDON_LOADED")
    integrations:SetScript("OnEvent", function(self, _, name)
        if name == "TomTom" and self:IsVisible() then atlas.refreshIntegrationSettings() end
    end)

    local reminders = ui.accountCheckbox(eventSection, 0, 87, 706, "Напоминания о событиях", "eventRemindersEnabled")
    settingTooltip(reminders, "Напоминания о событиях", "Сообщать в чат, когда действует событие, связанное с ещё не полученной наградой. Условия получения проверяются отдельно.")
    reminders:SetScript("OnClick", function(self)
        if atlas.setEventRemindersEnabled then atlas.setEventRemindersEnabled(self:GetChecked() == true) end
    end)
    ui.fill(eventSection, 352, 131, 1, 330, ui.rule):SetAlpha(.65)
    local holidays = makeReminderList(eventSection, 0, "Праздники")
    local worldBosses = makeReminderList(eventSection, 368, "Мировые боссы")
    atlas.refreshEventReminderSettings = function()
        if not eventSection:IsVisible() then return end
        reminders:SetChecked(atlas.eventRemindersEnabled and atlas.eventRemindersEnabled() or false)
        holidays.items, worldBosses.items = {}, {}
        for _, event in ipairs(atlas.eventReminderEvents and atlas.eventReminderEvents() or {}) do
            local group = type(event.worldQuest) == "number" and worldBosses.items or holidays.items
            group[#group + 1] = event
        end
        holidays:redraw()
        worldBosses:redraw()
    end
    eventSection:SetScript("OnShow", atlas.refreshEventReminderSettings)
    local expedition = ui.accountCheckbox(expeditionSection, 0, 96, 245, "Режим похода", "expeditionEnabled", atlas.refreshExpeditionTracker)
    settingTooltip(expedition, "Режим похода", "Показывать окно слежения за целями текущего плана.")
    atlas.refreshExpeditionEnabledSetting = function(enabled) expedition:SetChecked(enabled) end
    local expeditionPin = ui.accountCheckbox(expeditionSection, 0, 133, 245, "Закрепление", "expeditionPinned", function()
        local _, pinned = atlas.expeditionSettings()
        atlas.setExpeditionPinned(pinned)
    end)
    settingTooltip(expeditionPin, "Закрепление", "Закреплять окно слежения, чтобы его нельзя было перемещать.")
    atlas.refreshExpeditionPinSetting = function(pinned) expeditionPin:SetChecked(pinned) end
    ui.fill(expeditionSection, 267, 95, 1, 61, ui.rule):SetAlpha(.65)
    ui.text(expeditionSection, 308, 96, 338, 26, 16, "Прозрачность", ui.muted)
    local opacityValue = ui.text(expeditionSection, 644, 115, 62, 32, 15, "", ui.gold)
    opacityValue:SetJustifyH("RIGHT")
    local opacity = settingSlider(expeditionSection, "MountAtlasExpeditionTransparency", 308, 121, 318, 0, atlas.expeditionTransparencyMax, 5)
    settingTooltip(opacity, "Прозрачность", "Изменять прозрачность фона окна слежения.")
    opacity:SetHitRectInsets(0, 0, -4, -4)
    opacity:SetScript("OnValueChanged", function(_, value, userInput)
        if userInput then atlas.setExpeditionTransparency(value) end
        opacityValue:SetText(("%d%%"):format(math.floor(value + .5)))
    end)
    local function expeditionSizeSlider(name, label, y, minimum, maximum, setValue)
        ui.text(expeditionSection, 308, y, 338, 26, 16, label, ui.muted)
        local readout = ui.text(expeditionSection, 644, y + 19, 62, 32, 15, "", ui.gold)
        readout:SetJustifyH("RIGHT")
        local slider = settingSlider(expeditionSection, name, 308, y + 25, 318, minimum, maximum, 1)
        slider:SetHitRectInsets(0, 0, -4, -4)
        slider:SetScript("OnValueChanged", function(_, value, userInput)
            if userInput then setValue(value) end
        end)
        return slider, readout
    end
    local minWidth, maxWidth, minHeight, maxHeight = atlas.expeditionSizeLimits()
    local expeditionWidth, widthValue = expeditionSizeSlider("MountAtlasExpeditionWidth", "Ширина", 164, minWidth, maxWidth,
        function(value) atlas.setExpeditionSize(value, nil) end)
    local expeditionHeight, heightValue = expeditionSizeSlider("MountAtlasExpeditionHeight", "Высота", 232, minHeight, maxHeight,
        function(value) atlas.setExpeditionSize(nil, value) end)
    local function refreshExpeditionDimension(slider, readout, minimum, maximum, value)
        local currentMin, currentMax = slider:GetMinMaxValues()
        if currentMin ~= minimum or currentMax ~= maximum then slider:SetMinMaxValues(minimum, maximum) end
        if slider:GetValue() ~= value then slider:SetValue(value) end
        readout:SetText(("%d"):format(value))
    end
    atlas.refreshExpeditionSizeSettings = function(width, height)
        local minWidth, maxWidth, minHeight, maxHeight = atlas.expeditionSizeLimits()
        refreshExpeditionDimension(expeditionWidth, widthValue, minWidth, maxWidth, width)
        refreshExpeditionDimension(expeditionHeight, heightValue, minHeight, maxHeight, height)
    end
    ui.action(expeditionSection, 308, 306, 178, 33, "По умолчанию", nil, function()
        atlas.resetExpeditionSize()
    end)
    expeditionSection:SetScript("OnShow", function()
        atlas.refreshExpeditionSizeSettings(atlas.expeditionSize())
    end)
    for _, control in ipairs({ gameTooltips, minimap, compartment, reminders, expedition, expeditionPin }) do
        ui.setFont(control.caption, 16)
        control.caption:SetMaxLines(2)
    end
    local function update()
        local link = ("|Hpawatlas:project|h|cff%02x%02x%02xZik|r|h"):format(
            math.floor(ui.gold[1] * 255), math.floor(ui.gold[2] * 255), math.floor(ui.gold[3] * 255))
        local developer = L("Разработчик: Zik"):gsub("Zik", function() return link end)
        author:SetText(developer .. (version ~= "" and ("  ·  " .. version) or ""))
        gameTooltips:SetChecked(atlas.gameTooltipsEnabled())
        minimap:SetChecked(atlas.minimapButtonShown())
        atlas.refreshIntegrationSettings()
        local enabled, pinned, percent = atlas.expeditionSettings()
        expedition:SetChecked(enabled)
        expeditionPin:SetChecked(pinned)
        opacity:SetValue(percent)
        opacityValue:SetText(("%d%%"):format(percent))
        atlas.refreshFontSettings()
        refreshNotifications()
    end
    selectSection(fonts)
    panel:SetScript("OnShow", update)
    return panel
end
