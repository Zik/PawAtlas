local _, atlas = ...
local ui, L = atlas.ui, atlas.L

function atlas.makePlanSharing(parent, changed)
    local window = parent:GetParent()
    local overlay = ui.place(CreateFrame("Frame", "MountAtlasPlanSharing", parent), window, 12, 96, 1016, 478)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 45)
    overlay:SetToplevel(true)
    overlay:EnableMouse(true)
    overlay:Hide()
    for _, texture in ipairs(ui.surface(overlay, 0, 0, 1016, 478, false, "RoundedFill")) do
        texture:SetVertexColor(0, 0, 0, .65)
    end
    local panel = CreateFrame("Frame", nil, overlay)
    panel:SetPoint("CENTER", overlay, "CENTER")
    local importHeight = 310
    panel:SetSize(560, importHeight)
    local surface = ui.surface(panel, 0, 0, 560, importHeight)
    local function resizePanel(width, height)
        panel:SetSize(width, height)
        local xs, ys = { 0, 10, width - 10, width }, { 0, 10, height - 10, height }
        for row = 1, 3 do
            for col = 1, 3 do
                local texture = surface[(row - 1) * 3 + col]
                texture:ClearAllPoints()
                ui.place(texture, panel, xs[col], ys[row], xs[col + 1] - xs[col], ys[row + 1] - ys[row])
            end
        end
    end
    local heading = ui.text(panel, 22, 15, 516, 34, 21, "Поделиться", ui.gold)
    local export = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 560, 240)
    local import = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 560, importHeight)
    local remove = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 420, 174)
    local create = ui.place(CreateFrame("Frame", nil, panel), panel, 0, 0, 420, 174)
    local profile, revision, editedName = nil, 0, false

    local function makeEdit(owner, x, y, width, height, multiline)
        local field = ui.place(CreateFrame("Frame", nil, owner), owner, x, y, width, height)
        ui.fieldSurface(field, 0, 0, width, height)
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
        edit:SetScript("OnEscapePressed", function() overlay:Hide() end)
        return edit
    end

    local exportHint = ui.text(export, 22, 101, 516, 30, 15, "Ctrl+C — скопировать", ui.muted)
    local code = makeEdit(export, 22, 135, 516, 40)
    code:SetAutoFocus(true)
    local exportValue = ""
    local function selectExport(self)
        self:SetFocus()
        self:HighlightText()
    end
    code:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    code:SetScript("OnMouseUp", selectExport)
    code:SetScript("OnTextChanged", function(self)
        -- Keep copying available while restoring typing, deletion and paste.
        if self:GetText() ~= exportValue then
            self:SetText(exportValue)
            self:HighlightText()
        end
    end)
    local exportError = ui.text(export, 22, 101, 516, 30, 15, "Не удалось прочитать план", ui.gold)
    local function updateExport(id)
        local value = id and atlas.exportPlan(id)
        exportValue = value or ""
        code:SetText(exportValue)
        exportHint:SetShown(not not value)
        exportError:SetShown(id ~= nil and not value)
    end

    ui.text(import, 22, 97, 516, 26, 15, "Вставь строку плана", ui.muted)
    local input = makeEdit(import, 22, 125, 516, 62, true)
    input:SetAutoFocus(true)
    -- Leave one extra character so an oversized paste cannot become valid by truncation.
    local inputLimit = 32769
    input:SetMaxLetters(inputLimit)
    ui.text(import, 22, 197, 154, 34, 15, "Название плана", ui.muted)
    local name = makeEdit(import, 179, 197, 359, 34)
    name:SetMaxLetters(48)
    input.nextEditBox, input.previousEditBox = name, name
    name.nextEditBox, name.previousEditBox = input, input
    local summary = ui.text(import, 22, 237, 516, 26, 14, "", ui.gold)
    local confirmImport = ui.action(import, 370, 264, 168, 32, "Импортировать", nil, function()
        local id, count = atlas.importPlan(input:GetText(), name:GetText())
        if id then
            profile = { id = id }
            updateExport(id)
            editedName = false
            input:SetText("")
            input:ClearFocus()
            name:ClearFocus()
            summary:SetText(L("Импортировано: %d", count))
            changed(true)
        else
            summary:SetText("Не удалось прочитать план")
        end
    end)
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
        if value == "" then return end
        if #value >= inputLimit then summary:SetText("Не удалось прочитать план"); return end
        C_Timer.After(.12, function()
            if expected ~= revision or not import:IsVisible() then return end
            local result = atlas.previewPlanImport(value)
            if not result then summary:SetText("Не удалось прочитать план"); return end
            if not editedName then name:SetText(result.name) end
            local counts = L("К импорту: %d", #result.ids) .. "   ·   " .. L("Уже в коллекции: %d", result.collected)
            if result.skipped > 0 then counts = counts .. "   ·   " .. L("Пропущено: %d", result.skipped) end
            summary:SetText(counts)
            importName = #result.ids > 0 and result.name or nil
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
    ui.text(create, 22, 62, 144, 34, 15, "Название плана", ui.muted)
    local createName = makeEdit(create, 169, 62, 229, 34)
    createName:SetAutoFocus(true)
    createName:SetMaxLetters(48)
    local createError = ui.text(create, 22, 98, 376, 20, 12, "Не удалось создать план", ui.gold)
    createError:Hide()
    local function submitCreate()
        local value = createName:GetText()
        if not value:find("%S") then return end
        if atlas.createPlan(value) then
            overlay:Hide()
            changed()
        else
            createError:Show()
            createName:SetFocus()
            createName:HighlightText()
        end
    end
    local confirmCreate = ui.action(create, 234, 120, 164, 32, "Создать план", nil, submitCreate)
    confirmCreate:setActive(true)
    createName:SetScript("OnTextChanged", function(self)
        local enabled = self:GetText():find("%S") ~= nil
        confirmCreate:SetEnabled(enabled)
        confirmCreate:SetAlpha(enabled and 1 or .5)
        createError:Hide()
    end)
    createName:SetScript("OnEnterPressed", submitCreate)
    local cancel = ui.action(panel, 22, 365, 142, 32, "Отмена", nil, function() overlay:Hide() end)
    local exportTab, importTab
    local function showMode(mode)
        code:ClearFocus(); input:ClearFocus(); name:ClearFocus(); createName:ClearFocus()
        local creating, deleting, exporting = mode == "create", mode == "remove", mode == "export"
        local compact = creating or deleting
        local width = compact and 420 or 560
        resizePanel(width, compact and 174 or exporting and 240 or importHeight)
        heading:SetWidth(width - 44)
        cancel:ClearAllPoints()
        cancel:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 22, mode == "import" and 14 or 22)
        heading:SetText(creating and "Создать план" or deleting and "Удалить этот план?" or "Поделиться")
        export:SetShown(exporting)
        import:SetShown(mode == "import")
        remove:SetShown(deleting)
        create:SetShown(creating)
        exportTab:SetShown(not compact)
        importTab:SetShown(not compact)
        exportTab:setActive(mode == "export")
        importTab:setActive(mode == "import")
        if exporting and not exportError:IsShown() then code:SetFocus() end
        if creating then createName:SetFocus() end
        if mode == "import" then
            lastInputValue = nil
            input:GetScript("OnTextChanged")(input)
            input:SetFocus()
        end
    end
    exportTab = ui.action(panel, 22, 58, 132, 30, "Экспорт", nil, function() showMode("export") end)
    importTab = ui.action(panel, 162, 58, 132, 30, "Импорт", nil, function() showMode("import") end)
    cancel:SetFrameLevel(import:GetFrameLevel() + 2)
    exportTab:SetFrameLevel(import:GetFrameLevel() + 2)
    importTab:SetFrameLevel(import:GetFrameLevel() + 2)
    overlay:SetScript("OnHide", function()
        revision = revision + 1
        lastInputValue = nil
        code:ClearFocus(); input:ClearFocus(); name:ClearFocus(); createName:ClearFocus()
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
        self:Raise()
        showMode(delete and "remove" or "export")
    end
    function overlay:openCreate()
        profile = nil
        createName:SetText("")
        createError:Hide()
        self:Show()
        self:Raise()
        showMode("create")
    end
    if UISpecialFrames then table.insert(UISpecialFrames, "MountAtlasPlanSharing") end
    overlay:Hide()
    return overlay
end
