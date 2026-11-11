local addonName, atlas = ...
local ui = atlas.ui
local L = atlas.L
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
function atlas.makeSettings(parent)
    local panel = CreateFrame("Frame", "MountAtlasSettings", parent)
    ui.place(panel, parent, 12, 96, 1016, 478)
    panel:EnableMouse(true)
    ui.surface(panel, 0, 0, 1016, 478)
    ui.fill(panel, 236, 20, 1, 438, ui.rule)
    ui.icon(panel, 22, 25, 23, "Settings")
    ui.text(panel, 57, 18, 165, 38, 22, "Настройки", ui.gold)
    local sections = {}
    local function selectSection(selected)
        for _, section in ipairs(sections) do
            section.frame:SetShown(section.frame == selected)
            section.tab:setActive(section.frame == selected)
        end
    end
    local function makeSection(label)
        local frame = ui.place(CreateFrame("Frame", nil, panel), panel, 268, 0, 706, 478)
        local tab = ui.action(panel, 18, 82 + #sections * 52, 200, 44, label, nil, function() selectSection(frame) end)
        sections[#sections + 1] = { frame = frame, tab = tab }
        ui.text(frame, 0, 22, 460, 38, 23, label)
        ui.fill(frame, 0, 72, 706, 1, ui.rule)
        return frame
    end
    local fonts = makeSection("Интерфейс")
    local notifications = makeSection("Уведомления")
    local account = makeSection("Статистика")
    local integrations = makeSection("Интеграции")
    local information = makeSection("Об аддоне")
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
    local importResult = ui.text(integrations, 0, 148, 550, 30, 15, "", ui.muted)
    importResult:SetMaxLines(1)
    local importDetails = ui.place(CreateFrame("Frame", nil, integrations), integrations, 300, 188, 406, 249)
    importDetails:SetFrameLevel(integrations:GetFrameLevel() + 8)
    importDetails:EnableMouse(true)
    local detailsSurface = ui.dropdownSurface(importDetails)
    for column = 1, 3 do
        local middle, bottom = detailsSurface[column + 3], detailsSurface[column + 6]
        local _, _, _, left = bottom:GetPoint()
        middle:SetPoint("BOTTOMLEFT", importDetails, "BOTTOMLEFT", left, 10)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", importDetails, "BOTTOMLEFT", left, 0)
    end
    local skippedHeading = ui.text(importDetails, 12, 5, 382, 21, 13, "", ui.gold)
    local skippedEntries = ui.scrollingList(importDetails, 8, 30, 390, 42, 5)
    local skipReasons = {
        unmapped = "Маунт не сопоставлен", incompatible = "Несовместимый счётчик", unverified = "Источник не подтверждён",
        unsupported = "Источник не поддерживается", untracked = "Источник не отслеживается",
        unit_mismatch = "Разные единицы учёта", multiple_items = "Требуется несколько предметов",
    }
    for _, row in ipairs(skippedEntries.rows) do
        row:ClearHighlightTexture()
        ui.fill(row, 0, 0, 382, 38, ui.panel)
        row.name = ui.text(row, 8, 1, 366, 19, 14, "")
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.reason = ui.text(row, 8, 19, 366, 18, 12, "", ui.muted)
        row.reason:SetMaxLines(1)
    end
    function skippedEntries:onClick() end
    function skippedEntries:render(row, entry)
        local name = type(entry.name) == "string" and atlas.displayName(entry.name)
        row.name:SetText(name and name:gsub("|", "||") or "—")
        row.reason:SetText(skipReasons[entry.reason] or skipReasons.incompatible)
    end
    local detailsButton = ui.action(integrations, 570, 148, 136, 30, "Подробности", nil, function()
        importDetails:SetShown(not importDetails:IsShown())
    end)
    importDetails:SetScript("OnShow", function() detailsButton:setActive(true) end)
    importDetails:SetScript("OnHide", function() detailsButton:setActive(false) end)
    importDetails:Hide()
    detailsButton:Hide()
    local shownEntries, shownSkipped
    local refreshImport, clearImportButton, clearAcceptButton, clearImportOnly
    local importButton = ui.action(integrations, 0, 99, 224, 38, "Импорт из Rarity", nil, function()
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
    ui.text(account, 0, 138, 690, 40, 16, "Чтобы добавить персонажа, зайди им в игру с включённым аддоном", ui.muted)
    ui.text(account, 14, 192, 270, 24, 14, "Персонаж", ui.gold)
    ui.text(account, 300, 192, 240, 24, 14, "Сервер", ui.gold)
    local levelHeading = ui.text(account, 560, 192, 80, 24, 14, "Уровень", ui.gold)
    levelHeading:SetJustifyH("RIGHT")
    local confirm = ui.place(CreateFrame("Frame", "MountAtlasRemoveCharacter", panel), panel, 0, 0, 1016, 478)
    confirm:SetFrameLevel(panel:GetFrameLevel() + 60)
    confirm:EnableMouse(true)
    ui.fill(confirm, 0, 0, 1016, 478, {0, 0, 0, .65})
    local dialog = ui.place(CreateFrame("Frame", nil, confirm), confirm, 278, 128, 460, 222)
    ui.surface(dialog, 0, 0, 460, 222)
    local prompt = ui.text(dialog, 20, 20, 420, 30, 19, "Убрать персонажа из учтённых?", ui.gold)
    prompt:SetJustifyH("CENTER")
    local characterName = ui.text(dialog, 20, 56, 420, 24, 16, "")
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
    local clearConfirm = ui.place(CreateFrame("Frame", "MountAtlasClearStatistics", panel), panel, 0, 0, 1016, 478)
    clearConfirm:SetFrameLevel(panel:GetFrameLevel() + 60)
    clearConfirm:EnableMouse(true)
    ui.fill(clearConfirm, 0, 0, 1016, 478, {0, 0, 0, .65})
    local clearDialog = ui.place(CreateFrame("Frame", nil, clearConfirm), clearConfirm, 218, 105, 580, 268)
    ui.surface(clearDialog, 0, 0, 580, 268)
    local clearTitle = ui.text(clearDialog, 24, 20, 532, 30, 20, "Очистить всю статистику", ui.gold)
    clearTitle:SetJustifyH("CENTER")
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
    clearImportButton = ui.action(integrations, 470, 99, 236, 38, "Удалить импорт Rarity", nil, function() showClearConfirmation(true) end)
    ui.action(account, 480, 26, 226, 34, "Очистить всю статистику", nil, function() showClearConfirmation(false) end)
    clearConfirm:SetScript("OnHide", function() clearImportOnly = nil end)
    account:SetScript("OnHide", function() confirm:Hide(); clearConfirm:Hide() end)
    integrations:SetScript("OnHide", function() clearConfirm:Hide(); importDetails:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "MountAtlasRemoveCharacter") end
    if UISpecialFrames then table.insert(UISpecialFrames, "MountAtlasClearStatistics") end
    confirm:Hide()
    clearConfirm:Hide()
    local characters = ui.scrollingList(account, 0, 224, 706, 42, 5)
    for _, row in ipairs(characters.rows) do
        ui.fill(row, 0, 0, 698, 38, ui.panel)
        row.name = ui.text(row, 14, 0, 270, 38, 16, "")
        row.realm = ui.text(row, 300, 0, 240, 38, 15, "", ui.muted)
        row.name.atlasGameText = true
        row.realm.atlasGameText = true
        row.level = ui.text(row, 560, 0, 80, 38, 16, "", ui.gold)
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
        row.name:SetText(record.name)
        row.realm:SetText(record.realm)
        row.level:SetText(record.level or "—")
    end
    atlas.refreshAccountSettings = function()
        refreshImport()
        characterCount:SetText(L("Учтено персонажей: %d", atlas.accountCharacterCount()))
        characters.items = atlas.accountCharacters()
        characters:redraw()
    end
    local menu
    local dismiss = ui.button(fonts, 0, 74, 706, 404, function() menu:Hide() end)
    dismiss:SetFrameLevel(fonts:GetFrameLevel() + 3)
    dismiss:ClearHighlightTexture()
    dismiss:Hide()
    ui.text(fonts, 0, 91, 360, 26, 16, "Шрифт интерфейса", ui.muted)
    local picker = ui.action(fonts, 0, 121, 360, 42, nil, nil, function()
        menu:SetShown(not menu:IsShown())
    end, true)
    picker:SetFrameLevel(fonts:GetFrameLevel() + 4)
    local selectedName = ui.text(picker, 16, 0, 300, 42, 18, "")
    selectedName:SetMaxLines(1)
    ui.dropdownArrow(picker, 324, 11, 20)
    menu = ui.place(CreateFrame("Frame", nil, fonts), fonts, 0, 169, 420, 288)
    menu:SetFrameLevel(picker:GetFrameLevel() + 5)
    menu:EnableMouse(true)
    ui.dropdownSurface(menu)
    local choices = ui.scrollingList(menu, 8, 8, 404, 34, 8)
    for _, row in ipairs(choices.rows) do
        row:ClearHighlightTexture()
        row.name = ui.text(row, 12, 0, 372, 30, 17, "")
        row.name:SetMaxLines(1)
        row:SetScript("OnEnter", function(self) self.name:SetTextColor(unpack(ui.gold)) end)
        row:SetScript("OnLeave", function(self)
            if self.item then self.name:SetTextColor(unpack(self.item.id == ui.selectedFont().id and ui.gold or ui.paper)) end
        end)
    end
    function choices:render(row, font)
        row.name:SetText(font.name)
        ui.setFont(row.name, 17, font.path)
        row.name:SetTextColor(unpack(font.id == ui.selectedFont().id and ui.gold or ui.paper))
    end
    function choices:onClick(font)
        ui.applyFont(font.id)
        atlas.refreshFontSettings()
        menu:Hide()
    end
    ui.text(fonts, 400, 91, 306, 26, 16, "Размер шрифта", ui.muted)
    local selectedSize = ui.text(fonts, 625, 121, 43, 42, 14, "", ui.gold)
    selectedSize:SetJustifyH("RIGHT")
    local trackWidth = 222
    local size = ui.place(CreateFrame("Slider", "MountAtlasFontSize", fonts), fonts, 400, 132, trackWidth, 20)
    local minimum, maximum = ui.fontScales[1], ui.fontScales[#ui.fontScales]
    size:SetOrientation("HORIZONTAL")
    size:SetMinMaxValues(minimum, maximum)
    size:SetValueStep(ui.fontScales[2] - minimum)
    size:SetObeyStepOnDrag(true)
    ui.fill(size, 0, 9, trackWidth, 3, ui.rule)
    ui.fill(size, trackWidth * (100 - minimum) / (maximum - minimum) - 1, 5, 2, 11, ui.gold)
    local thumb = size:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(unpack(ui.gold))
    thumb:SetSize(5, 16)
    size:SetThumbTexture(thumb)
    local function refreshSize()
        local value = ui.selectedFontScale()
        size:SetValue(value)
        selectedSize:SetText(string.format("%d%%", value))
    end
    size:SetScript("OnValueChanged", function(_, value)
        if value ~= ui.selectedFontScale() then ui.applyFontScale(value) end
        selectedSize:SetText(string.format("%d%%", ui.selectedFontScale()))
    end)
    ui.resetButton(fonts, 674, 126, function()
        ui.applyFontScale(100)
        refreshSize()
    end)
    atlas.refreshFontSettings = function()
        local selected = ui.selectedFont()
        selectedName:SetText(selected.name)
        ui.setFont(selectedName, 18, selected.path)
        choices.items = ui.fonts
        choices:redraw()
        refreshSize()
    end
    menu:SetScript("OnShow", function()
        atlas.refreshFontSettings()
        choices:reveal(ui.selectedFont())
        dismiss:Show()
        picker:setActive(true)
    end)
    menu:SetScript("OnHide", function() dismiss:Hide(); picker:setActive(false) end)
    fonts:SetScript("OnHide", function() menu:Hide() end)
    menu:Hide()
    ui.fill(fonts, 0, 184, 706, 1, ui.rule)
    local gameTooltips = ui.accountCheckbox(fonts, 0, 198, 350, "Подсказки в игре", "gameTooltips")
    ui.fill(fonts, 0, 248, 706, 1, ui.rule)
    local expedition = ui.accountCheckbox(fonts, 0, 262, 350, "Режим похода", "expeditionEnabled", atlas.refreshExpeditionTracker)
    atlas.refreshExpeditionEnabledSetting = function(enabled) expedition:SetChecked(enabled) end
    local expeditionPin = ui.accountCheckbox(fonts, 0, 304, 350, "Закрепление", "expeditionPinned", function()
        local _, pinned = atlas.expeditionSettings()
        atlas.setExpeditionPinned(pinned)
    end)
    atlas.refreshExpeditionPinSetting = function(pinned) expeditionPin:SetChecked(pinned) end
    ui.text(fonts, 400, 286, 306, 26, 16, "Прозрачность", ui.muted)
    local opacityValue = ui.text(fonts, 625, 304, 43, 32, 14, "", ui.gold)
    opacityValue:SetJustifyH("RIGHT")
    local opacity = ui.place(CreateFrame("Slider", "MountAtlasExpeditionTransparency", fonts), fonts, 400, 310, trackWidth, 20)
    opacity:SetOrientation("HORIZONTAL")
    opacity:SetMinMaxValues(0, atlas.expeditionTransparencyMax)
    opacity:SetValueStep(5)
    opacity:SetObeyStepOnDrag(true)
    ui.fill(opacity, 0, 9, trackWidth, 3, ui.rule)
    local opacityThumb = opacity:CreateTexture(nil, "OVERLAY")
    opacityThumb:SetColorTexture(unpack(ui.gold))
    opacityThumb:SetSize(5, 16)
    opacity:SetThumbTexture(opacityThumb)
    opacity:SetScript("OnValueChanged", function(_, value, userInput)
        if userInput then atlas.setExpeditionTransparency(value) end
        opacityValue:SetText(("%d%%"):format(math.floor(value + .5)))
    end)
    local function update()
        local link = ("|Hpawatlas:project|h|cff%02x%02x%02xZik|r|h"):format(
            math.floor(ui.gold[1] * 255), math.floor(ui.gold[2] * 255), math.floor(ui.gold[3] * 255))
        local developer = L("Разработчик: Zik"):gsub("Zik", function() return link end)
        author:SetText(developer .. (version ~= "" and ("  ·  " .. version) or ""))
        gameTooltips:SetChecked(atlas.gameTooltipsEnabled())
        local enabled, pinned, percent = atlas.expeditionSettings()
        expedition:SetChecked(enabled)
        expeditionPin:SetChecked(pinned)
        opacity:SetValue(percent)
        opacityValue:SetText(("%d%%"):format(percent))
        atlas.refreshFontSettings()
        atlas.refreshAccountSettings()
        refreshNotifications()
    end
    selectSection(fonts)
    panel:SetScript("OnShow", update)
    panel:Hide()
    return panel
end
