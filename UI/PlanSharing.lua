local _, atlas = ...
local ui, L = atlas.ui, atlas.L

function atlas.makePlanSharing(parent, changed)
    local shareTabTop, shareTabWidth, shareTabHeight = 119, 146, 32
    local shareDividerY = shareTabTop + shareTabHeight
    local codeTop = shareDividerY + 17
    local footerInset, footerHeight, footerGap = 16, 32, 14
    local exportCodeHeight, importCodeHeight = 36, 48
    local exportHeight = codeTop + exportCodeHeight + footerGap + footerHeight + footerInset
    local importHeight = codeTop + importCodeHeight + footerGap + footerHeight + footerInset
    local overlay, panel = ui.journalDialog(parent, "MountAtlasPlanSharing", 560, exportHeight)
    local landscape = panel:CreateTexture(nil, "BACKGROUND", nil, -5)
    landscape:SetPoint("TOPLEFT", panel, "TOPLEFT", 1, -1)
    landscape:SetSize(558, 154)
    landscape:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Illustrations\\PlanSharingLandscape.tga")
    local banner = panel:CreateTexture(nil, "ARTWORK")
    banner:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -20)
    banner:SetSize(65, 83)
    banner:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Illustrations\\PlanSharingBanner.tga")
    banner:SetTexCoord(0, 1, 0, .665)
    banner:SetVertexColor(.92, .92, .94)

    local divider = ui.fill(panel, 22, shareDividerY, 516, 1, ui.rule)
    divider:SetDrawLayer("ARTWORK")
    divider:SetGradient("HORIZONTAL", CreateColor(.61, .49, .29, .85), CreateColor(.32, .39, .42, .24))
    local shareTextLeft, shareTextWidth = 107, 431
    local heading = ui.text(panel, shareTextLeft, 19, shareTextWidth, 38, 23, "Поделиться планом", ui.gold)
    local introduction = ui.text(panel, shareTextLeft, 60, shareTextWidth, 51, 16,
        "Экспортируй план, чтобы отправить код другу. Если у тебя уже есть код, вставь его во вкладке «Импорт».", ui.paper)
    introduction:SetJustifyV("TOP")
    local export = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 560, exportHeight)
    local import = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 560, importHeight)
    local remove = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 420, 174)
    local nameForm = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 420, 174)
    local profile, revision, editedName = nil, 0, false

    local function makeEdit(owner, x, y, width, height, multiline)
        local field = ui.place(CreateFrame("Frame", nil, owner), owner, x, y, width, height)
        local fieldSurface = ui.dropdownSurface(field)
        field:EnableMouse(true)
        local holder = field
        if multiline then
            holder = ui.place(CreateFrame("ScrollFrame", nil, field), field, 10, 7, width - 20, height - 14)
        end
        local edit = CreateFrame("EditBox", nil, holder, "InputBoxScriptTemplate")
        if multiline then
            edit:SetMultiLine(true)
            edit:SetSize(width - 20, height - 14)
            holder:SetScrollChild(edit)
            edit:SetScript("OnCursorChanged", function(self, _, cursorY, _, lineHeight)
                local top = math.max(0, -cursorY)
                local visible = holder:GetHeight()
                local offset = holder:GetVerticalScroll()
                if top < offset then holder:SetVerticalScroll(top)
                elseif top + lineHeight > offset + visible then
                    holder:SetVerticalScroll(math.max(0, top + lineHeight - visible))
                end
            end)
        else
            ui.place(edit, field, 10, 0, width - 20, height)
        end
        edit:SetAutoFocus(false)
        field:SetScript("OnMouseDown", function() edit:SetFocus() end)
        edit:SetScript("OnHide", function(self) self:ClearFocus() end)
        ui.setFont(edit, 15)
        edit:SetTextColor(unpack(ui.paper))
        local function focusBorder(focused)
            for _, edge in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
                fieldSurface[edge]:SetColorTexture(unpack(focused and { .38, .49, .65, 1 } or { .25, .32, .42, 1 }))
            end
        end
        edit:HookScript("OnEditFocusGained", function() focusBorder(true) end)
        edit:HookScript("OnEditFocusLost", function() focusBorder(false) end)
        edit:SetScript("OnEscapePressed", function() overlay:Hide() end)
        return edit, field
    end

    local exportHint = ui.text(export, 338, exportHeight - footerInset - footerHeight, 200, footerHeight, 14,
        "Ctrl+C — скопировать", ui.muted)
    exportHint:SetJustifyH("RIGHT")
    local code, codeField = makeEdit(export, 22, codeTop, 516, exportCodeHeight)
    code:SetAutoFocus(true)
    local exportValue = ""
    local function selectExport(self)
        self:SetFocus()
        self:HighlightText()
    end
    code:HookScript("OnEditFocusGained", function(self) self:HighlightText() end)
    code:SetScript("OnMouseUp", selectExport)
    code:SetScript("OnTextChanged", function(self)
        -- Keep copying available while restoring typing, deletion and paste.
        if self:GetText() ~= exportValue then
            self:SetText(exportValue)
            self:HighlightText()
        end
    end)
    local exportError = ui.text(export, 22, codeTop, 516, exportCodeHeight, 15, "Не удалось прочитать план", ui.gold)
    local function updateExport(id)
        local value = id and atlas.exportPlan(id)
        exportValue = value or ""
        code:SetText(exportValue)
        codeField:SetShown(not not value)
        exportHint:SetShown(not not value)
        exportError:SetShown(id ~= nil and not value)
    end

    local input = makeEdit(import, 22, codeTop, 516, importCodeHeight, true)
    local importHint = ui.text(import, 174, importHeight - footerInset - footerHeight, 186, footerHeight, 14,
        "Ctrl+V — вставить", ui.muted)
    importHint:ClearAllPoints()
    importHint:SetPoint("BOTTOMLEFT", import, "BOTTOMLEFT", 174, footerInset)
    importHint:SetJustifyH("CENTER")
    input:SetAutoFocus(true)
    -- Leave one extra character so an oversized paste cannot become valid by truncation.
    local inputLimit = 32769
    input:SetMaxLetters(inputLimit)
    local nameTop, summaryHeight = codeTop + 60, 38
    local nameLabel = ui.text(import, 22, nameTop, 154, 30, 15, "Название плана", ui.muted)
    local name, nameField = makeEdit(import, 179, nameTop, 359, 30)
    name:SetMaxLetters(48)
    name.nextEditBox, name.previousEditBox = input, input
    local summary = ui.text(import, 22, nameTop, 516, summaryHeight, 14, "", ui.gold)
    local function layoutImport(showName, showSummary)
        nameLabel:SetShown(showName)
        nameField:SetShown(showName)
        input.nextEditBox, input.previousEditBox = showName and name or nil, showName and name or nil
        local summaryTop = showName and nameTop + 38 or nameTop
        summary:ClearAllPoints()
        ui.place(summary, import, 22, summaryTop, 516, summaryHeight)
        local height = showSummary and (summaryTop + summaryHeight + 12 + footerHeight + footerInset) or importHeight
        import:SetHeight(height)
        if import:IsShown() and overlay:IsShown() then panel:SetHeight(height) end
    end
    local confirmImport = ui.action(import, 370, 236, 168, 32, "Импортировать", nil, function()
        local id, count = atlas.importPlan(input:GetText(), name:GetText())
        if id then
            profile = { id = id }
            updateExport(id)
            editedName = false
            input:SetText("")
            name:ClearFocus()
            summary:SetText(L("Импортировано: %d", count))
            layoutImport(false, true)
            changed(true)
            if import:IsVisible() then input:SetFocus() end
        else
            summary:SetText("Не удалось прочитать план")
            layoutImport(false, true)
        end
    end)
    confirmImport:ClearAllPoints()
    confirmImport:SetPoint("BOTTOMRIGHT", import, "BOTTOMRIGHT", -22, footerInset)
    confirmImport:setActive(true)
    local function setImportEnabled(enabled)
        confirmImport:SetEnabled(enabled)
        confirmImport:SetAlpha(enabled and 1 or .5)
    end
    local importName, lastInputValue
    local function updateImportEnabled()
        setImportEnabled(importName ~= nil and (importName ~= "" or name:GetText():find("%S") ~= nil))
    end
    name:SetScript("OnTextChanged", function(_, userInput)
        if userInput then editedName = true end
        updateImportEnabled()
    end)
    input:SetScript("OnTextChanged", function(self)
        local value = self:GetText()
        -- Layout notifications must not restart validation of unchanged text.
        if value == lastInputValue then return end
        lastInputValue = value
        revision = revision + 1
        local expected = revision
        importName = nil
        setImportEnabled(false)
        if not editedName then name:SetText("") end
        summary:SetText("")
        layoutImport(false, false)
        if value == "" then return end
        if #value >= inputLimit then
            summary:SetText("Не удалось прочитать план")
            layoutImport(false, true)
            return
        end
        C_Timer.After(.12, function()
            if expected ~= revision or not import:IsVisible() then return end
            local result = atlas.previewPlanImport(value)
            if not result then
                summary:SetText("Не удалось прочитать план")
                layoutImport(false, true)
                return
            end
            if not editedName then name:SetText(result.name) end
            local counts = L("К импорту: %d", #result.ids) .. "   ·   " .. L("Уже в коллекции: %d", result.collected)
            if result.skipped > 0 then counts = counts .. "   ·   " .. L("Пропущено: %d", result.skipped) end
            summary:SetText(counts)
            importName = #result.ids > 0 and result.name or nil
            layoutImport(importName ~= nil, true)
            updateImportEnabled()
        end)
    end)

    local removeName = ui.text(remove, 22, 59, 376, 38, 18, "", ui.paper)
    removeName.atlasGameText = true
    removeName:SetMaxLines(1)
    local confirmRemove = ui.action(remove, 254, 120, 144, 32, "Удалить", nil, function()
        if profile and profile.id == atlas.activePlanID() and atlas.deletePlanProfile(profile.id) then
            overlay:Hide()
            changed()
        end
    end)
    ui.text(nameForm, 22, 62, 144, 34, 15, "Название плана", ui.muted)
    local planName = makeEdit(nameForm, 169, 62, 229, 34)
    planName:SetMaxLetters(48)
    local nameError = ui.text(nameForm, 22, 98, 376, 20, 12, "Не удалось создать план", ui.gold)
    nameError:Hide()
    local function submitName()
        if not nameForm:IsVisible() then return end
        local value = planName:GetText()
        if not value:find("%S") then return end
        local saved
        if profile then
            if profile.id ~= atlas.activePlanID() then overlay:Hide(); return end
            saved = atlas.renamePlan(profile.id, value)
        else
            saved = atlas.createPlan(value)
        end
        if saved then
            overlay:Hide()
            changed()
        else
            nameError:Show()
            planName:SetFocus()
            planName:HighlightText()
        end
    end
    local confirmName = ui.action(nameForm, 234, 120, 164, 32, "Создать план", nil, submitName)
    confirmName:setActive(true)
    planName:SetScript("OnTextChanged", function(self)
        local enabled = self:GetText():find("%S") ~= nil
        confirmName:SetEnabled(enabled)
        confirmName:SetAlpha(enabled and 1 or .5)
        nameError:Hide()
    end)
    planName:SetScript("OnEnterPressed", submitName)
    local cancel = ui.action(panel, 22, 228, 142, 32, "Отмена", nil, function() overlay:Hide() end)
    local exportTab, importTab
    local function showMode(mode)
        code:ClearFocus(); input:ClearFocus(); name:ClearFocus(); planName:ClearFocus()
        local naming, deleting, exporting = mode == "name", mode == "remove", mode == "export"
        local compact = naming or deleting
        local width = compact and 420 or 560
        panel:SetSize(width, compact and 174 or (exporting and exportHeight or importHeight))
        heading:ClearAllPoints()
        ui.place(heading, panel, compact and 22 or shareTextLeft, compact and 14 or 19,
            compact and width - 44 or shareTextWidth, 38)
        landscape:SetShown(not compact)
        banner:SetShown(not compact)
        introduction:SetShown(not compact)
        divider:ClearAllPoints()
        ui.place(divider, panel, 22, compact and 53 or shareDividerY, width - 44, 1)
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 22, compact and 22 or footerInset)
        if naming then
            heading:SetText(profile and "Переименовать план" or "Создать план")
            confirmName.caption:SetText(profile and "Переименовать" or "Создать план")
            nameError:SetText(profile and "Не удалось переименовать план" or "Не удалось создать план")
        else
            heading:SetText(deleting and "Удалить этот план?" or "Поделиться планом")
        end
        export:SetShown(exporting)
        import:SetShown(mode == "import")
        remove:SetShown(deleting)
        nameForm:SetShown(naming)
        exportTab:SetShown(not compact)
        importTab:SetShown(not compact)
        exportTab:setActive(mode == "export")
        importTab:setActive(mode == "import")
        if exporting and not exportError:IsShown() then code:SetFocus() end
        if naming then
            planName:SetFocus()
            if profile then planName:HighlightText() end
        end
        if mode == "import" then
            lastInputValue = nil
            input:GetScript("OnTextChanged")(input)
            input:SetFocus()
        end
    end
    exportTab = ui.tab(panel, 22, shareTabTop, shareTabWidth, shareTabHeight, "Экспорт", nil, function() showMode("export") end, .6)
    importTab = ui.tab(panel, 30 + shareTabWidth, shareTabTop, shareTabWidth, shareTabHeight, "Импорт", nil,
        function() showMode("import") end, .6)
    cancel:SetFrameLevel(import:GetFrameLevel() + 2)
    exportTab:SetFrameLevel(import:GetFrameLevel() + 2)
    importTab:SetFrameLevel(import:GetFrameLevel() + 2)
    overlay:SetScript("OnHide", function()
        revision = revision + 1
        lastInputValue = nil
        code:ClearFocus(); input:ClearFocus(); name:ClearFocus(); planName:ClearFocus()
        profile = nil
    end)
    function overlay:closeIfStale(activeID)
        if profile and profile.id ~= activeID then self:Hide() end
    end
    function overlay:open(selected, delete)
        profile = selected
        updateExport(not delete and selected.id or nil)
        input:SetText("")
        name:SetText("")
        editedName = false
        removeName:SetText(selected.name)
        confirmRemove:SetEnabled(selected.id ~= "personal")
        self:Show()
        showMode(delete and "remove" or "export")
    end
    function overlay:openName(selected)
        if selected and (selected.id == "personal" or selected.id ~= atlas.activePlanID()) then return end
        profile = selected
        planName:SetText(selected and selected.name or "")
        nameError:Hide()
        self:Show()
        showMode("name")
    end
    return overlay
end
