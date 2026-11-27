local _, atlas = ...
local ui = atlas.ui
local L = atlas.L

local function hidePlanTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function rosterIcon(parent, centerX, size)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("CENTER", parent, "LEFT", centerX, 0)
    icon:SetHeight(size)
    return icon
end

local function setRosterIcon(icon, character)
    local size = icon:GetHeight()
    if character and character.guid then
        icon:SetWidth(size)
        ui.setCharacterClassIcon(icon, character)
    else
        icon:SetWidth(size * 43 / 49)
        -- Trim the transparent padding of the first campfire cell in UIWarbandsIcons2x.
        icon:SetTexture(5855107)
        icon:SetTexCoord(2 / 128, 45 / 128, 4 / 64, 53 / 64)
    end
end

local function showExpansionTooltip(tile)
    local expansion = tile.expansion
    if not expansion or not expansion.event then return end
    GameTooltip:SetOwner(tile, "ANCHOR_TOP")
    ui.tooltipTitle(expansion.name)
    ui.tooltipLine(L("Эти маунты были доступны только во время события. Нажми, чтобы открыть список"), 1, 1, 1, true)
    GameTooltip:Show()
end

local function counted(count, one, few, many)
    local form
    if atlas.getLocale() == "enUS" then
        form = count == 1 and one or many
    else
        local last, lastTwo = count % 10, count % 100
        form = last == 1 and lastTwo ~= 11 and one
            or last >= 2 and last <= 4 and (lastTwo < 12 or lastTwo > 14) and few or many
    end
    return L(form, count)
end

local function expansionBoard(page, openExpansion)
    local board = ui.place(CreateFrame("Frame", nil, page), page, 0, 52, 970, 378)
    ui.text(board, 0, 0, 550, 28, 21, "Дополнения")
    ui.text(board, 0, 29, 920, 23, 14, "Выбери дополнение, чтобы найти следующую цель", ui.muted)
    local grid = ui.scrollingList(board, 0, 64, 970, 152, 2)
    grid.items = {}
    for i = 1, #atlas.expansions, 3 do
        grid.items[#grid.items + 1] = { atlas.expansions[i], atlas.expansions[i + 1], atlas.expansions[i + 2] }
    end
    for _, row in ipairs(grid.rows) do
        -- The row only groups tiles and handles scrolling; gaps are not actions.
        row:ClearHighlightTexture()
        row.tiles = {}
        for col = 1, 3 do
            local tile = ui.action(row, (col - 1) * 324, 0, 314, 142, nil, nil, function(self)
                if self.expansion then openExpansion(self.expansion) end
            end)
            local art = tile:CreateTexture(nil, "ARTWORK")
            ui.place(art, tile, 7, 7, 300, 128)
            art:SetTexCoord(0, 1, .04, .80)
            art:SetAlpha(.60)
            local mask = tile:CreateMaskTexture()
            mask:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\HeaderMask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(art)
            art:AddMaskTexture(mask)
            tile.art = art
            tile.logo = tile:CreateTexture(nil, "OVERLAY")
            ui.place(tile.logo, tile, 78, 10, 158, 78)
            tile.name = ui.text(tile, 12, 88, 290, 26, 15, "")
            tile.name:SetJustifyH("CENTER")
            tile.name:SetMaxLines(1)
            tile.count = ui.text(tile, 12, 114, 290, 20, 12, "", ui.muted)
            tile.count:SetJustifyH("CENTER")
            tile:EnableMouseWheel(true)
            tile:SetScript("OnMouseWheel", function(_, delta) grid:scroll(-delta) end)
            tile:HookScript("OnEnter", function(self)
                art:SetAlpha(.82)
                showExpansionTooltip(self)
            end)
            local function leaveTile(self)
                art:SetAlpha(.60)
                hidePlanTooltip(self)
            end
            tile:HookScript("OnLeave", leaveTile)
            tile:HookScript("OnHide", leaveTile)
            row.tiles[col] = tile
        end
    end
    function grid:onClick() end
    function grid:render(row, entries)
        for col, tile in ipairs(row.tiles) do
            local exp = entries[col]
            local changed = tile.expansion ~= exp
            if changed then hidePlanTooltip(tile) end
            tile.expansion = exp
            tile:SetShown(exp ~= nil)
            if exp then
                local counts = atlas.collection and atlas.collection.expansions[exp.id]
                local total, owned = counts and counts.total or 0, counts and counts.collected or 0
                tile.art:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Headers\\" .. (exp.art or exp.id) .. ".tga")
                tile.logo:ClearAllPoints()
                local logoWidth = exp.id == "Other" and 78 or 158
                local logoHeight = exp.logoAspect and logoWidth / exp.logoAspect or 78
                ui.place(tile.logo, tile, (314 - logoWidth) / 2, 49 - logoHeight / 2, logoWidth, logoHeight)
                -- Normalize the visible event artwork, excluding transparent
                -- press-kit padding. Reset UVs when recycled for another tile.
                if exp.logoUV then tile.logo:SetTexCoord(unpack(exp.logoUV))
                else tile.logo:SetTexCoord(0, 1, 0, 1) end
                local logo = exp.id == "Other" and "Brand\\MountAtlas" or ("Expansions\\" .. (exp.logo or exp.id))
                tile.logo:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\" .. logo .. ".tga")
                tile.name:SetText(exp.name)
                tile.count:SetText(owned .. " / " .. total)
                tile:SetEnabled(total > 0)
                tile:SetAlpha(total > 0 and 1 or .45)
                if changed and tile:IsVisible() and tile:IsMouseOver() then showExpansionTooltip(tile) end
            end
        end
    end
    function board:update() grid:redraw() end
    return board
end

local function showPlanTooltip(owner, name)
    if not name then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    ui.tooltipTitle(name)
    GameTooltip:Show()
end

local function achievementLabel(mount)
    local function currentLabel(route)
        if route.key == "achievement" and route.state == "current" and not route.requirement then
            return L(route.label)
        end
    end

    local primary = atlas.classifyMountSource(mount)
    if primary.state == "historical" then return end
    local label = currentLabel(primary)
    if label then return label end

    local grant = atlas.extraDirectGrantSource(mount)
    label = grant and currentLabel(atlas.classifyMountSource(mount, grant))
    if label then return label end

    for _, step in ipairs(mount.achievementSteps or {}) do
        if not step.purchase then
            return currentLabel(atlas.classifyMountSource(mount, {
                view = { kind = "Достижение" },
            }))
        end
    end
end

local function updateChoiceTint(row)
    local color = row.chosen and { .10, .19, .30, 1 } or { .075, .115, .17, 1 }
    row.selection:SetColorTexture(unpack(color))
    row.selection:SetShown(row.chosen or row.hovered)
    row.marker:SetShown(row.chosen)
end

local function toolbarButton(page, x, width, u, v, callback, selectedRow)
    local button = ui.place(CreateFrame("Button", nil, page), page, x, 1, width, 28)
    local surface = button:CreateTexture(nil, "BACKGROUND")
    surface:SetAllPoints()
    surface:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\PlannerButtons.tga")
    local hovered, active, pressed = false, false, false
    local function update()
        local left, row = u, v + (hovered and 32 or 0)
        if active and selectedRow then left, row = 220, selectedRow end
        surface:SetTexCoord(left / 512, (left + width) / 512, row / 128, (row + 28) / 128)
        local tint = not button:IsEnabled() and .60 or pressed and .86 or 1
        surface:SetVertexColor(tint, tint, tint)
    end
    function button:setActive(value) active = value; update() end
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function() hovered = button:IsEnabled(); update() end)
    local function clearHover()
        hovered, pressed = false, false
        update()
    end
    local function updateHover()
        hovered, pressed = button:IsEnabled() and button:IsMouseOver(), false
        update()
    end
    button:SetScript("OnLeave", clearHover)
    button:SetScript("OnHide", clearHover)
    button:SetScript("OnDisable", clearHover)
    button:SetScript("OnEnable", updateHover)
    button:SetScript("OnShow", updateHover)
    button:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton == "LeftButton" then pressed = self:IsEnabled(); update() end
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton)
        if mouseButton == "LeftButton" then updateHover() end
    end)
    update()
    return button
end

local function drawShareIcon(button)
    local offset = (button:GetWidth() - 28) / 2
    for _, direction in ipairs({ -1, 1 }) do
        local link = ui.fill(button, offset + 9, 13 + direction * 3, 10, 1.5, ui.paper)
        link:SetRotation(-direction * math.pi / 6)
        link:SetDrawLayer("ARTWORK")
    end
    for _, center in ipairs({ { 9, 14 }, { 18, 9 }, { 18, 19 } }) do
        local x, y = unpack(center)
        x = x + offset
        ui.fill(button, x - 1.5, y - 2.5, 3, 5, ui.paper):SetDrawLayer("OVERLAY")
        ui.fill(button, x - 2.5, y - 1.5, 5, 3, ui.paper):SetDrawLayer("OVERLAY")
    end
end

local menuInset = 6

local function dragGrip(row, x, y)
    local dots = {}
    for i = 0, 5 do
        local dot = ui.fill(row, x + i % 2 * 4, y + math.floor(i / 2) * 4, 2, 2, ui.gold)
        dot:SetDrawLayer("ARTWORK")
        dots[#dots + 1] = dot
    end
    return dots
end

local function planProfileList(menu, selectProfile)
    local width = menu:GetWidth() - menuInset * 2
    local step, capacity = 36, 6
    ui.dropdownSurface(menu)
    local plans = ui.scrollingList(menu, menuInset, menuInset, width, step, capacity)
    local overlay = CreateFrame("Frame", nil, plans)
    overlay:SetAllPoints(plans)
    overlay:SetFrameLevel(plans:GetFrameLevel() + 8)
    overlay:EnableMouse(false)
    local marker = ui.fill(overlay, 2, 0, width - 12, 2, ui.gold)
    marker:Hide()
    local drag

    local function updateDrag(_, elapsed)
        local x, y = GetCursorPosition()
        local scale = plans:GetEffectiveScale()
        local left, top = plans:GetLeft(), plans:GetTop()
        local height = plans:GetHeight()
        drag.anchor = nil
        if left and top then x, y = x / scale - left, top - y / scale end
        if not left or not top or x < 0 or x > width - 8 or y < 0 or y >= height then
            drag.edge, drag.elapsed = nil, 0
            marker:Hide()
            return
        end

        local edge
        if y < 12 and plans.offset > 0 then edge = -1 end
        if y > height - 12 and plans.offset + capacity < #plans.items then edge = 1 end
        if edge ~= drag.edge then drag.edge, drag.elapsed = edge, 0 end
        if edge and elapsed then
            drag.elapsed = drag.elapsed + elapsed
            if drag.elapsed >= .22 then
                drag.elapsed = 0
                plans:scroll(edge)
            end
        end

        local slot = math.floor(y / step)
        local index = plans.offset + slot + 1
        local anchor = plans.items[index]
        local after = y - slot * step >= step / 2
        local neighbor = plans.items[index + (after and 1 or -1)]
        if not anchor or anchor.id == "personal" or anchor.id == drag.id or (neighbor and neighbor.id == drag.id) then
            marker:Hide()
            return
        end

        drag.anchor, drag.after = anchor.id, after
        local line = (slot + (after and 1 or 0)) * step - 1
        if line ~= drag.line then
            marker:ClearAllPoints()
            marker:SetPoint("TOPLEFT", overlay, "TOPLEFT", 2, -line)
            drag.line = line
        end
        marker:Show()
    end

    local function stopDrag()
        if not drag then return end
        drag = nil
        overlay:SetScript("OnUpdate", nil)
        marker:Hide()
        for _, row in ipairs(plans.rows) do row:SetAlpha(1) end
    end
    menu:HookScript("OnHide", stopDrag)

    for _, row in ipairs(plans.rows) do
        row:SetSize(width - 8, step)
        row:ClearHighlightTexture()
        row.selection = ui.fill(row, 0, 0, width - 8, step, { .10, .19, .30, 1 })
        row.marker = ui.fill(row, 0, 7, 2, 22, ui.gold)
        row.name = ui.text(row, 12, 0, width - 32, 35, 14, "")
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        row.grip = dragGrip(row, width - 25, 13)
        row:HookScript("OnEnter", function(self)
            self.hovered = true; updateChoiceTint(self)
            if not drag then showPlanTooltip(self, self.item and self.item.name) end
        end)
        local function leave(self)
            self.hovered = false; updateChoiceTint(self); hidePlanTooltip(self)
        end
        row:HookScript("OnLeave", leave)
        row:HookScript("OnHide", leave)
        local click = row:GetScript("OnClick")
        row:RegisterForDrag("LeftButton")
        row:HookScript("OnMouseDown", function(self) self.draggedProfile = nil end)
        row:SetScript("OnClick", function(self, ...)
            if not self.draggedProfile then click(self, ...) end
        end)
        row:SetScript("OnDragStart", function(self, mouseButton)
            if mouseButton ~= "LeftButton" then return end
            self.draggedProfile = true
            if drag or not self.draggable or not self.item then return end
            drag = { id = self.item.id, button = self, elapsed = 0 }
            hidePlanTooltip(self)
            self:SetAlpha(.48)
            updateDrag()
            overlay:SetScript("OnUpdate", updateDrag)
        end)
        row:SetScript("OnDragStop", function(self)
            if not drag or drag.button ~= self then return end
            updateDrag()
            local move = drag
            stopDrag()
            if move.anchor and atlas.movePlanProfile(move.id, move.anchor, move.after) then
                plans.items = atlas.planProfiles()
                plans:redraw()
            end
        end)
    end
    function plans:render(row, profile)
        if row.profileID ~= profile.id then hidePlanTooltip(row) end
        row.profileID = profile.id
        row.name:SetText(profile.name)
        row.chosen = profile.id == atlas.activePlanID()
        row.name:SetTextColor(unpack(row.chosen and ui.gold or ui.paper))
        row.draggable = profile.id ~= "personal" and #self.items > 2
        row.name:SetWidth(width - (row.draggable and 43 or 32))
        for _, dot in ipairs(row.grip) do
            dot:SetShown(row.draggable)
            dot:SetAlpha(row.chosen and .86 or .62)
        end
        row:SetAlpha(drag and drag.id == profile.id and .48 or 1)
        updateChoiceTint(row)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(row) then showPlanTooltip(row, profile.name) end
    end
    function plans:onClick(profile)
        menu:Hide()
        if profile.id ~= atlas.activePlanID() and atlas.selectPlan(profile.id) then selectProfile() end
    end
    function plans:showProfiles(profiles, bottomSpace)
        self.items = profiles
        if drag then
            local retained
            for _, profile in ipairs(profiles) do
                if profile.id == drag.id then retained = true; break end
            end
            if not retained or #profiles <= 2 then stopDrag() end
        end
        local height = math.min(capacity, #profiles) * step
        self:SetHeight(height)
        menu:SetHeight(menuInset + height + bottomSpace)
        self:redraw()
        return height
    end
    return plans
end

function atlas.makePlanner(parent, openMount, openExpansion)
    local page = ui.place(CreateFrame("Frame", nil, parent), parent, 35, 92, 970, 460)
    page:Hide()
    local planX, planWidth = 222, 240
    ui.icon(page, 0, 4, 21, "Route"):SetVertexColor(unpack(ui.gold))
    ui.text(page, 32, 0, planX - 40, 30, 21, "Планнер")
    local add = toolbarButton(page, 796, 174, 42, 65, function() openMount(nil) end)
    ui.icon(add, 12, 5, 18, "Plus"):SetVertexColor(unpack(ui.gold))
    ui.text(add, 34, 0, 132, 28, 14, "Добавить цель"):SetJustifyH("CENTER")
    local selectedGUID
    local menu, planMenu, planChanged
    local sources = atlas.makePlannerSources(page)
    local sharing = atlas.makePlanSharing(page, function(keepSharing) planChanged(keepSharing) end)
    local dismiss = ui.button(page, 0, 0, 1, 1, function() menu:Hide(); planMenu:Hide() end)
    dismiss:ClearAllPoints()
    dismiss:SetAllPoints(parent)
    dismiss:SetFrameLevel(page:GetFrameLevel() + 12)
    dismiss:ClearHighlightTexture()
    dismiss:Hide()
    local characterX, characterWidth = 476, 254
    local fieldY, fieldHeight = 1, 28
    local menuY = fieldY + fieldHeight + 5
    local fieldSilver = { .87, .89, .92 }
    local picker = toolbarButton(page, characterX, characterWidth, 244, 1, function()
        planMenu:Hide()
        menu:SetShown(not menu:IsShown())
    end, 97)
    picker:SetFrameLevel(page:GetFrameLevel() + 13)
    local pickerIcon = rosterIcon(picker, 18, 18)
    local pickerName = ui.text(picker, 36, 0, characterWidth - 70, fieldHeight, 13, "Весь отряд")
    pickerName:SetMaxLines(1)
    pickerName:SetWordWrap(false)
    ui.dropdownArrow(picker, characterWidth - 23, 8, 13):SetColor(fieldSilver)
    picker:HookScript("OnEnter", function(self) showPlanTooltip(self, picker.characterLabel or pickerName:GetText()) end)
    picker:HookScript("OnLeave", hidePlanTooltip)
    picker:HookScript("OnHide", hidePlanTooltip)
    menu = ui.place(CreateFrame("Frame", "MountAtlasPlannerCharacterMenu", page), page, characterX, menuY, characterWidth, 50)
    menu:SetFrameLevel(picker:GetFrameLevel() + 3)
    menu:EnableMouse(true)
    ui.dropdownSurface(menu)
    local characterListWidth = characterWidth - menuInset * 2
    local characterList = ui.scrollingList(menu, menuInset, menuInset, characterListWidth, 42, 7)
    local planPicker = toolbarButton(page, planX, planWidth, 1, 1, function()
        menu:Hide()
        planMenu:SetShown(not planMenu:IsShown())
    end, 65)
    planPicker:SetFrameLevel(picker:GetFrameLevel())
    local planName = ui.text(planPicker, 12, 0, planWidth - 44, fieldHeight, 13, "")
    planName.atlasGameText = true
    planName:SetMaxLines(1)
    planName:SetWordWrap(false)
    ui.dropdownArrow(planPicker, planWidth - 23, 8, 13):SetColor(fieldSilver)
    planMenu = ui.place(CreateFrame("Frame", "MountAtlasPlannerProfileMenu", page), page, planX, menuY, planWidth, 90)
    planMenu:SetFrameLevel(menu:GetFrameLevel())
    planMenu:EnableMouse(true)
    local plans = planProfileList(planMenu, function() planChanged() end)
    local activeProfile
    planPicker:HookScript("OnEnter", function(self) showPlanTooltip(self, activeProfile and activeProfile.name) end)
    planPicker:HookScript("OnLeave", hidePlanTooltip)
    planPicker:HookScript("OnHide", hidePlanTooltip)
    local share = toolbarButton(page, 744, 38, 1, 65, function()
        menu:Hide(); planMenu:Hide(); sources:Hide(); sharing:open(activeProfile)
    end)
    drawShareIcon(share)
    share:HookScript("OnEnter", function(self) showPlanTooltip(self, L("Поделиться или импортировать план")) end)
    share:HookScript("OnLeave", hidePlanTooltip)
    share:HookScript("OnHide", hidePlanTooltip)
    local create = ui.action(planMenu, 8, 0, planWidth - 16, 30, "Создать план", nil, function()
        planMenu:Hide(); sources:Hide(); sharing:openName()
    end)
    local rename = ui.action(planMenu, 8, 0, planWidth - 16, 30, "Переименовать", nil, function()
        planMenu:Hide(); sources:Hide(); sharing:openName(activeProfile)
    end)
    local delete = ui.action(planMenu, 8, 0, planWidth - 16, 30, "Удалить план", nil, function()
        planMenu:Hide(); sources:Hide(); sharing:open(activeProfile, true)
    end)
    local planDivider = ui.fill(planMenu, 9, 0, planWidth - 18, 1, ui.rule)
    local function refreshPlans()
        local activeID = atlas.activePlanID()
        sharing:closeIfStale(activeID)
        local profiles = atlas.planProfiles()
        for _, profile in ipairs(profiles) do
            if profile.id == activeID then activeProfile = profile; break end
        end
        planName:SetText(activeProfile.name)
        if not planMenu:IsShown() then return end
        local custom = activeProfile.id ~= "personal"
        local listBottom = menuInset + plans:showProfiles(profiles, custom and 114 or 46)
        planDivider:ClearAllPoints()
        ui.place(planDivider, planMenu, 9, listBottom + 5, planWidth - 18, 1)
        create:ClearAllPoints()
        ui.place(create, planMenu, 8, listBottom + 10, planWidth - 16, 30)
        rename:SetShown(custom)
        delete:SetShown(custom)
        if custom then
            rename:ClearAllPoints()
            ui.place(rename, planMenu, 8, listBottom + 44, planWidth - 16, 30)
            delete:ClearAllPoints()
            ui.place(delete, planMenu, 8, listBottom + 78, planWidth - 16, 30)
        end
    end
    planMenu:SetScript("OnShow", function()
        hidePlanTooltip(planPicker)
        refreshPlans()
        plans:reveal(activeProfile)
        dismiss:Show()
        planPicker:setActive(true)
    end)
    planMenu:SetScript("OnHide", function() dismiss:Hide(); planPicker:setActive(false) end)
    planMenu:Hide()
    local function refreshCharacterChoices()
        local settings = MountAtlasAccountDB.settings
        selectedGUID = type(settings) == "table" and type(settings.plannerCharacterGUID) == "string" and settings.plannerCharacterGUID or nil
        local pins = type(settings) == "table" and settings.plannerPinnedCharacters
        local choices, unpinned, selected = { { label = "Весь отряд" } }, {}, nil
        for _, character in ipairs(atlas.accountCharacters()) do
            local pinned = type(pins) == "table" and pins[character.guid] == true
            local entry = { guid = character.guid, name = character.name, realm = character.realm, class = character.class,
                label = character.name .. " · " .. character.realm, pinned = pinned }
            local group = pinned and choices or unpinned
            group[#group + 1] = entry
            if selectedGUID == character.guid then selected = entry end
        end
        for _, entry in ipairs(unpinned) do choices[#choices + 1] = entry end
        if selectedGUID and not selected then
            selectedGUID = nil
            atlas.selectPlanCharacter(nil)
        end
        pickerName:SetText(selected and selected.name or "Весь отряд")
        setRosterIcon(pickerIcon, selected)
        picker.characterLabel = selected and selected.label or L("Весь отряд")
        characterList.items = choices
    end
    local function hidePinTooltip(pin)
        if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
    end
    local function updatePin(pin)
        pin.shade:SetShown(pin.hovered == true)
        pin.icon:SetColorTexture(unpack(pin.hovered and { 1, .90, .63 } or pin.pinned and ui.gold or ui.muted))
        pin.center:SetShown(not pin.pinned)
    end
    local function showPinTooltip(pin)
        if not pin.guid then return end
        GameTooltip:SetOwner(pin, "ANCHOR_TOP")
        ui.tooltipTitle(L(pin.pinned and "Открепить персонажа" or "Закрепить персонажа"))
        GameTooltip:Show()
    end
    for _, row in ipairs(characterList.rows) do
        row:SetSize(characterListWidth, 42)
        row:ClearHighlightTexture()
        row.selection = ui.fill(row, 0, 0, characterListWidth, 42, { .10, .19, .30, 1 })
        row.marker = ui.fill(row, 0, 9, 2, 24, ui.gold)
        row.icon = rosterIcon(row, 22, 24)
        row.name = ui.text(row, 44, 2, characterListWidth - 96, 21, 14, "")
        row.realm = ui.text(row, 44, 23, characterListWidth - 96, 17, 12, "", ui.muted)
        row.name.atlasGameText, row.realm.atlasGameText = true, true
        row.realm:SetMaxLines(1)
        row.realm:SetWordWrap(false)
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        local pin = ui.button(row, characterListWidth - 40, 7, 28, 28, function(self)
            local character = row.item
            if not character or not character.guid then return end
            if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
            local settings = MountAtlasAccountDB.settings
            if type(settings.plannerPinnedCharacters) ~= "table" then settings.plannerPinnedCharacters = {} end
            local pins = settings.plannerPinnedCharacters
            if character.pinned then
                pins[character.guid] = nil
            else
                pins[character.guid] = true
            end
            hidePinTooltip(self)
            refreshCharacterChoices()
            characterList:redraw()
        end)
        pin.shade = ui.fill(pin, 0, 0, 28, 28, { .92, .76, .44, .12 })
        pin.shade:Hide()
        pin.icon = ui.fill(pin, 8, 8, 12, 12, ui.muted)
        pin.icon:SetDrawLayer("ARTWORK")
        pin.icon:SetRotation(math.pi / 4)
        pin.center = ui.fill(pin, 11, 11, 6, 6, ui.ink)
        pin.center:SetDrawLayer("ARTWORK", 1)
        pin.center:SetRotation(math.pi / 4)
        pin:ClearHighlightTexture()
        pin:EnableMouseWheel(true)
        pin:SetScript("OnMouseWheel", function(_, delta) characterList:scroll(-delta) end)
        pin:SetScript("OnEnter", function(self)
            row.hovered = true; updateChoiceTint(row)
            self.hovered = true
            updatePin(self)
            showPinTooltip(self)
        end)
        local function clearPinHover(self)
            self.hovered = false
            updatePin(self)
            hidePinTooltip(self)
        end
        pin:SetScript("OnLeave", function(self)
            row.hovered = row:IsMouseOver(); updateChoiceTint(row)
            clearPinHover(self)
        end)
        pin:SetScript("OnHide", clearPinHover)
        row.pin = pin
        row:HookScript("OnEnter", function(self)
            self.hovered = true; updateChoiceTint(self)
            showPlanTooltip(self, self.item and self.item.label)
        end)
        row:HookScript("OnLeave", function(self)
            self.hovered = self:IsMouseOver(); updateChoiceTint(self); hidePlanTooltip(self)
        end)
        row:HookScript("OnHide", function(self)
            self.hovered = false; updateChoiceTint(self); hidePlanTooltip(self)
        end)
    end
    function characterList:render(row, character)
        if row.characterGUID ~= character.guid then row.hovered = false; hidePlanTooltip(row) end
        row.characterGUID = character.guid
        row.name:SetText(character.name or character.label)
        row.realm:SetText(character.realm or "")
        row.name:ClearAllPoints()
        ui.place(row.name, row, 44, character.guid and 2 or 0,
            character.guid and characterListWidth - 96 or characterListWidth - 56, character.guid and 21 or 41)
        row.name:SetTextColor(unpack(ui.characterClassColor(character)))
        setRosterIcon(row.icon, character)
        row.chosen = character.guid == selectedGUID
        updateChoiceTint(row)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(row) then showPlanTooltip(row, character.label) end
        local pin = row.pin
        if pin.guid ~= character.guid then hidePinTooltip(pin) end
        pin.guid, pin.pinned = character.guid, character.pinned
        pin:SetShown(character.guid ~= nil)
        updatePin(pin)
        if pin.hovered and pin:IsMouseOver() then showPinTooltip(pin) end
    end
    function characterList:onClick(character)
        atlas.selectPlanCharacter(character.guid)
        menu:Hide()
        page:update()
    end
    menu:SetScript("OnShow", function()
        hidePlanTooltip(picker)
        characterList:redraw()
        for _, character in ipairs(characterList.items) do
            if character.guid == selectedGUID then characterList:reveal(character); break end
        end
        dismiss:Show()
        picker:setActive(true)
    end)
    menu:SetScript("OnHide", function() dismiss:Hide(); picker:setActive(false) end)
    if UISpecialFrames then
        table.insert(UISpecialFrames, menu:GetName())
        table.insert(UISpecialFrames, planMenu:GetName())
    end
    local rosterTooltipOwner
    page:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        self:RegisterEvent("MODIFIER_STATE_CHANGED")
    end)
    page:SetScript("OnEvent", function(_, event, key)
        if event == "MODIFIER_STATE_CHANGED" then
            if (key == "LSHIFT" or key == "RSHIFT") and rosterTooltipOwner and GameTooltip:IsShown()
                and GameTooltip:IsOwned(rosterTooltipOwner) and rosterTooltipOwner:IsVisible() then
                rosterTooltipOwner:showStatusTooltip()
            end
            return
        end
        if menu:IsShown() and not menu:IsMouseOver() and not picker:IsMouseOver() then menu:Hide() end
        if planMenu:IsShown() and not planMenu:IsMouseOver() and not planPicker:IsMouseOver() then planMenu:Hide() end
    end)
    menu:Hide()
    page:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        self:UnregisterEvent("MODIFIER_STATE_CHANGED")
        menu:Hide()
        planMenu:Hide()
        dismiss:Hide()
        picker:setActive(false)
        planPicker:setActive(false)
        sources:Hide()
        sharing:Hide()
    end)
    local board = expansionBoard(page, openExpansion)
    local rowStep, rowWidth, capacity = 48, 962, 8
    local list = ui.scrollingList(page, 0, 38, 970, rowStep, capacity)
    ui.fill(list, 0, 0, rowWidth, 1, ui.rule):SetAlpha(.65)
    local overlay = CreateFrame("Frame", nil, list)
    overlay:SetAllPoints(list)
    overlay:SetFrameLevel(list:GetFrameLevel() + 8)
    overlay:EnableMouse(false)
    local marker = ui.fill(overlay, 2, 0, rowWidth - 4, 2, ui.gold)
    marker:Hide()
    local ghost = ui.place(CreateFrame("Frame", nil, overlay), overlay, 0, 0, 280, 38)
    ui.surface(ghost, 0, 0, 280, 38, true)
    local ghostIcon = ghost:CreateTexture(nil, "ARTWORK")
    ui.place(ghostIcon, ghost, 6, 6, 26, 26)
    ghostIcon:SetTexCoord(.08, .92, .08, .92)
    local ghostName = ui.text(ghost, 40, 0, 230, 38, 13, "")
    ghostName.atlasGameText = true
    ghostName:SetMaxLines(1)
    ghost:SetAlpha(.94)
    ghost:Hide()

    local drag
    local function updateDrag(elapsed)
        if not drag then return end
        local x, y = GetCursorPosition()
        local scale = list:GetEffectiveScale()
        local left, top = list:GetLeft(), list:GetTop()
        if not left or not top then drag.anchor = nil; return end
        x, y = x / scale - left, top - y / scale
        local visible = math.min(capacity, #list.items)
        if x < 0 or x > rowWidth or y < 0 or y >= visible * rowStep then
            drag.anchor, drag.edge, drag.elapsed = nil, nil, 0
            marker:Hide()
            ghost:Hide()
            return
        end

        local edge
        if y < 16 and list.offset > 0 then edge = -1 end
        if y > visible * rowStep - 16 and list.offset + visible < #list.items then edge = 1 end
        if edge ~= drag.edge then drag.edge, drag.elapsed = edge, 0 end
        if edge and elapsed then
            drag.elapsed = drag.elapsed + elapsed
            if drag.elapsed >= .22 then
                drag.elapsed = 0
                list:scroll(edge)
            end
        end

        local slot = math.floor(y / rowStep)
        local index = list.offset + slot + 1
        local anchor = list.items[index]
        local after = y - slot * rowStep >= rowStep / 2
        local neighbor = list.items[index + (after and 1 or -1)]
        if anchor.id ~= drag.mountID and (not neighbor or neighbor.id ~= drag.mountID) then
            drag.anchor, drag.after = anchor.id, after
            local line = (slot + (after and 1 or 0)) * rowStep - 3
            if line ~= drag.line then
                marker:ClearAllPoints()
                marker:SetPoint("TOPLEFT", overlay, "TOPLEFT", 2, -line)
                drag.line = line
            end
            marker:Show()
        else
            drag.anchor = nil
            marker:Hide()
        end

        local gx = math.min(x + 14, rowWidth - ghost:GetWidth())
        local gy = y + 12
        if gy + ghost:GetHeight() > visible * rowStep then gy = y - ghost:GetHeight() - 12 end
        if gx ~= drag.x or gy ~= drag.y then
            ghost:ClearAllPoints()
            ghost:SetPoint("TOPLEFT", overlay, "TOPLEFT", gx, -gy)
            drag.x, drag.y = gx, gy
        end
        ghost:Show()
    end

    local function stopDrag()
        if not drag then return end
        local button = drag.button
        drag = nil
        overlay:SetScript("OnUpdate", nil)
        marker:Hide()
        ghost:Hide()
        if button.hasPlanSources ~= nil then button:SetShown(button.hasPlanSources) end
        for _, row in ipairs(list.rows) do row:SetAlpha(1) end
    end
    page:HookScript("OnHide", stopDrag)
    planChanged = function(keepSharing)
        stopDrag()
        menu:Hide(); planMenu:Hide(); sources:Hide()
        if not keepSharing then sharing:Hide() end
        atlas.refreshPlanSnapshot()
        page:update()
    end

    local function registerDrag(button, row)
        local click = button:GetScript("OnClick")
        button:EnableMouse(true)
        button:RegisterForDrag("LeftButton")
        button:HookScript("OnMouseDown", function(self) self.draggedPlanTarget = nil end)
        button:HookScript("OnHide", function(self)
            if drag and drag.button == self then stopDrag() end
        end)
        button:SetScript("OnClick", function(self, ...)
            if not self.draggedPlanTarget then click(self, ...) end
        end)
        button:SetScript("OnDragStart", function(self, mouseButton)
            if mouseButton ~= "LeftButton" or drag or not row.item or #list.items < 2 then return end
            self.draggedPlanTarget = true
            local mount = row.item
            drag = { mountID = mount.id, planID = atlas.activePlanID(), button = self, elapsed = 0 }
            if GameTooltip:IsOwned(row) or GameTooltip:IsOwned(row.sourceButton) then GameTooltip:Hide() end
            ghostIcon:SetTexture(mount.icon or 132261)
            ghostName:SetText(atlas.displayName(mount.name))
            row:SetAlpha(.48)
            updateDrag()
            overlay:SetScript("OnUpdate", function(_, elapsed) updateDrag(elapsed) end)
        end)
        button:SetScript("OnDragStop", function(self)
            if not drag or drag.button ~= self then return end
            updateDrag()
            local move = drag
            stopDrag()
            if move.planID == atlas.activePlanID() and move.anchor and atlas.movePlanTarget(move.mountID, move.anchor, move.after, move.planID) then
                list.items = atlas.planTargets(nil, move.planID)
                list:redraw()
            end
        end)
    end

    local progressX, progressWidth = 530, 356
    for _, row in ipairs(list.rows) do
        row:ClearHighlightTexture()
        row:SetWidth(rowWidth)
        ui.fill(row, 0, rowStep - 1, rowWidth, 1, ui.rule):SetAlpha(.48)
        local hoverTint = ui.fill(row, 2, 1, rowWidth - 4, rowStep - 2, { .88, .71, .39, .10 })
        hoverTint:SetGradient("VERTICAL", CreateColor(.87, .73, .47, .03), CreateColor(.87, .73, .47, .14))
        local hoverRim = ui.surface(row, 0, 0, rowWidth, rowStep, false, "OrnateOutline")
        for _, texture in ipairs(hoverRim) do texture:SetVertexColor(.85, .69, .42, .65) end
        local accent = ui.fill(row, 1, 7, 2, rowStep - 14, ui.gold)
        accent:SetDrawLayer("ARTWORK")
        local accentLight = row:CreateTexture(nil, "ARTWORK")
        ui.place(accentLight, row, -10, 21, 26, 6)
        accentLight:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\SoftGlow.tga")
        accentLight:SetVertexColor(1, .76, .30, .72)
        accentLight:SetRotation(math.pi / 2)
        row.icon = ui.itemIcon(row, 15, 6, 36)
        row.grip = dragGrip(row, 57, 19)
        function row:showHover(owner)
            self.hoverOwner = owner
            local hovered = owner ~= nil
            hoverTint:SetShown(hovered)
            accent:SetShown(hovered)
            accentLight:SetShown(hovered)
            for _, texture in ipairs(hoverRim) do texture:SetShown(hovered) end
            for _, dot in ipairs(self.grip) do dot:SetShown(hovered and self.draggable) end
        end
        row:showHover(nil)
        local function leaveHover(owner)
            if row.hoverOwner == owner then row:showHover(nil) end
            hidePlanTooltip(owner)
        end
        row.place = ui.text(row, 70, 4, 446, 16, 12, "", ui.gold)
        row.place:SetMaxLines(1)
        row.place:SetWordWrap(false)
        row.placeLink = ui.locationLink(row.place)
        row.placeLink:EnableMouseWheel(true)
        row.placeLink:SetScript("OnMouseWheel", function(_, delta) list:scroll(-delta) end)
        row.placeLink:HookScript("OnEnter", function(self) row:showHover(self) end)
        row.placeLink:HookScript("OnLeave", leaveHover)
        row.placeLink:HookScript("OnHide", leaveHover)
        row.name = ui.text(row, 70, 19, 446, 24, 16, "")
        row.name.atlasGameText = true
        row.place.atlasGameText = true
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        row.status = ui.text(row, progressX + 22, 3, progressWidth - 22, 21, 14, "")
        row.status:SetMaxLines(1)
        row.status:SetWordWrap(false)
        row.detail = ui.text(row, progressX, 30, progressWidth, 16, 11, "", ui.muted)
        row.detail:SetMaxLines(1)
        row.detail:SetWordWrap(false)
        row.check = ui.icon(row, progressX, 6, 15, "ObjectiveComplete")
        row.unknown = ui.text(row, progressX, 3, 15, 21, 15, "?", ui.paper)
        row.unknown:SetJustifyH("CENTER")
        row.track = ui.fill(row, progressX, 25, progressWidth, 3, { .24, .32, .41, .75 })
        row.progress = ui.fill(row, progressX, 25, progressWidth, 3, ui.gold)
        row.track:SetDrawLayer("ARTWORK", 0)
        row.progress:SetDrawLayer("ARTWORK", 1)
        local function itemAttempts()
            if not row.item or row.collected then return end
            return atlas.itemAttemptProgress(row.item)
        end
        row.sourceButton = ui.button(row, progressX - 4, 1, progressWidth + 8, rowStep - 2, function(_, button)
            if button == "LeftButton" and IsShiftKeyDown() and atlas.shareItemAttempts(itemAttempts()) then return end
            if row.item then menu:Hide(); planMenu:Hide(); sources:open(row.item, selectedGUID) end
        end)
        row.sourceButton:EnableMouseWheel(true)
        row.sourceButton:GetHighlightTexture():SetAlpha(0)
        row.sourceButton:SetScript("OnMouseWheel", function(_, delta) list:scroll(-delta) end)
        registerDrag(row, row)
        registerDrag(row.sourceButton, row)
        local remove = ui.action(row, 925, 12, 24, 24, nil, "Close", function()
            local planID = atlas.activePlanID()
            if row.item and atlas.isPlanned(row.item, planID) then atlas.togglePlan(row.item, planID) end
            page:update()
        end)
        remove.glyph:ClearAllPoints()
        ui.place(remove.glyph, remove, 5, 5, 14, 14)
        remove:HookScript("OnEnter", function(self)
            row:showHover(self)
            if drag then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L("Убрать из плана"))
            GameTooltip:Show()
        end)
        remove:HookScript("OnLeave", leaveHover)
        remove:HookScript("OnHide", leaveHover)
        local function showStatusTooltip(self)
            rosterTooltipOwner = nil
            if drag or not row.item then return end
            if not GameTooltip:IsShown() or not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self, "ANCHOR_TOP") end
            if self == row.sourceButton then
                ui.tooltipTitle(L("Посмотреть список"))
                if atlas.canShareItemAttempts(itemAttempts()) then
                    ui.tooltipLine(L("Shift + ЛКМ — поделиться в чате"), unpack(ui.muted))
                end
                GameTooltip:Show()
                return
            end
            ui.tooltipTitle(row.item.name)
            local mutedR, mutedG, mutedB = unpack(ui.muted)
            local owned = select(11, C_MountJournal.GetMountInfoByID(row.item.id))
            local accountState = atlas.accountLootLockout(row.item)
            if accountState then
                ui.tooltipLine(L("На аккаунт"), unpack(ui.muted))
                if not (issecretvalue and issecretvalue(owned)) and not owned then
                    local color = accountState == "attempt" and ui.mint or ui.muted
                    ui.tooltipLine(L(ui.planStatusLabel(accountState)), color[1], color[2], color[3], true)
                end
                GameTooltip:Show()
                return
            end
            if not (issecretvalue and issecretvalue(owned)) and not owned then
                local characters, total = 1, 1
                if selectedGUID then
                    local _, _, _, progress = atlas.planCharacterStatus(row.item, selectedGUID)
                    total = progress and progress.totalAttempts or 1
                else
                    local counts = atlas.planSummary(row.item)
                    characters = counts.total
                    total = counts.totalAttempts > 0 and counts.totalAttempts or characters
                end
                if characters > 0 then
                    ui.tooltipLine(counted(total / characters, "%d источник", "%d источника", "%d источников")
                        .. " × " .. counted(characters, "%d персонаж", "%d персонажа", "%d персонажей")
                        .. " = " .. counted(total, "%d проверка", "%d проверки", "%d проверок"),
                        ui.gold[1], ui.gold[2], ui.gold[3], true)
                    ui.tooltipLine(L("Это сохранения отряда, а не история попыток. Для обновления данных зайди на персонажей."),
                        mutedR, mutedG, mutedB, true)
                    ui.tooltipLine(" ")
                end
            end
            local characters = atlas.accountCharacters()
            local limit = (row.item.isRaid or row.item.kind == "Рейд") and 3 or 10
            local expandable = not selectedGUID and #characters > limit
            if expandable then rosterTooltipOwner = self end
            local expanded = expandable and IsShiftKeyDown()
            for index, character in ipairs(characters) do
                if not selectedGUID or selectedGUID == character.guid then
                    if expandable and not expanded and index > limit then
                        ui.tooltipLine("…", unpack(ui.muted))
                        ui.tooltipLine(L("Зажми Shift, чтобы посмотреть весь отряд"), unpack(ui.gold))
                        break
                    end
                    local state, _, _, progress = atlas.planCharacterStatus(row.item, character.guid)
                    local status = L(ui.planStatusLabel(state))
                    if progress and progress.totalAttempts > 1 then
                        status = L("Выполнено: %d / %d", progress.completedAttempts, progress.totalAttempts)
                        if progress.stale then status = L("Нужно обновить") .. " · " .. status end
                    end
                    local complete = state == "boss" or state == "attempt"
                    local uncertain = state == "unknown" or state == "stale"
                    local color = complete and ui.mint or uncertain and ui.muted or ui.paper
                    local name = ui.safeText(character.name .. " · " .. character.realm)
                    GameTooltip:AddDoubleLine(name, ui.safeText(status), ui.paper[1], ui.paper[2], ui.paper[3], unpack(color))
                    if atlas.appendBossDifficultyTooltip then atlas.appendBossDifficultyTooltip(row.item, character.guid) end
                end
            end
            GameTooltip:Show()
        end
        row.showStatusTooltip = showStatusTooltip
        row:SetScript("OnEnter", function(self)
            row:showHover(self)
            showStatusTooltip(self)
        end)
        local function highlightProgress(hovered)
            row.progress:SetAlpha(hovered and 1 or .85)
            if row.statusColor then
                local color = row.statusColor
                row.status:SetTextColor(math.min(1, color[1] + (hovered and .12 or 0)),
                    math.min(1, color[2] + (hovered and .12 or 0)),
                    math.min(1, color[3] + (hovered and .12 or 0)))
            end
        end
        row.sourceButton:SetScript("OnEnter", function(self)
            row:showHover(self)
            highlightProgress(true)
            showStatusTooltip(self)
        end)
        row:SetScript("OnLeave", leaveHover)
        row:SetScript("OnHide", function(self)
            row:showHover(nil)
            hidePlanTooltip(self)
        end)
        local function leaveSource(self)
            highlightProgress(false)
            leaveHover(self)
        end
        row.sourceButton:SetScript("OnLeave", leaveSource)
        row.sourceButton:SetScript("OnHide", leaveSource)
        atlas.bindMountPreviewCursor(row, function() return row.item end)
    end
    function list:render(row, mount)
        local tooltipOwner = GameTooltip:IsShown() and GameTooltip:GetOwner()
        if tooltipOwner ~= row and tooltipOwner ~= row.sourceButton then tooltipOwner = nil end
        if row.shownMountID ~= mount.id and tooltipOwner then
            GameTooltip:Hide()
            tooltipOwner = nil
        end
        row.shownMountID = mount.id
        atlas.refreshMountPreviewCursor(row)
        row:SetAlpha(drag and drag.mountID == mount.id and .48 or 1)
        row.draggable = #self.items > 1
        row:showHover(row.hoverOwner)
        local sourceButton = row.sourceButton
        sourceButton.hasPlanSources = mount.kind == "Рарка" or atlas.planOpportunityProgress(mount) ~= nil
        -- A recycled row must keep the native drag receiver visible through mouse release.
        sourceButton:SetShown(sourceButton.hasPlanSources or (drag and drag.button == sourceButton))
        local place = atlas.displayName(mount.place)
        local subtitle = place ~= "" and place or achievementLabel(mount) or ""
        local frequency = atlas.lootFrequency(mount)
        if frequency == "daily" or frequency == "weekly" then
            local period = L(frequency == "daily" and "Ежедневно" or "Еженедельно")
            subtitle = subtitle ~= "" and subtitle .. " · " .. period or period
        end
        row.place:SetText(subtitle)
        row.placeLink:setLocation(atlas.sourceMapID(place, nil, mount), place)
        row.name:SetText(atlas.displayName(mount.name))
        row.icon:SetTexture(mount.icon or 132261)
        local complete, fraction, state = false, 0, "unknown"
        local owned = select(11, C_MountJournal.GetMountInfoByID(mount.id))
        local accountState = atlas.accountLootLockout(mount)
        row.collected = not (issecretvalue and issecretvalue(owned)) and owned == true
        if row.collected then
            complete = true
            fraction, state = 1, "collected"
            row.status:SetText("В коллекции")
            row.detail:SetText("")
        elseif accountState then
            state, complete = accountState, accountState == "attempt"
            fraction = complete and 1 or 0
            row.status:SetText(ui.planStatusLabel(state))
            row.detail:SetText(L("На аккаунт"))
        elseif selectedGUID then
            local updated, _, progress
            state, updated, _, progress = atlas.planCharacterStatus(mount, selectedGUID)
            complete = state == "boss" or state == "attempt"
            fraction = complete and 1 or 0
            row.status:SetText(ui.planStatusLabel(state))
            row.detail:SetText(updated and date("%d.%m.%Y %H:%M", updated) or "")
            if progress and progress.totalAttempts > 1 then
                fraction = progress.completedAttempts / progress.totalAttempts
                row.status:SetText(L("Выполнено: %d / %d", progress.completedAttempts, progress.totalAttempts))
                row.detail:SetText(progress.stale and "Нужно обновить"
                    or L("Можно идти: %d · Нужно обновить: %d", progress.availableAttempts, progress.unknownAttempts))
            end
        else
            local counts = atlas.planSummary(mount)
            complete = counts.total > 0 and counts.done == counts.total
            fraction = counts.total > 0 and counts.done / counts.total or 0
            state = complete and "complete" or counts.done > 0 and "progress"
                or counts.available > 0 and "available" or "unknown"
            row.status:SetText(L("Выполнено: %d / %d", counts.done, counts.total))
            if counts.total == 1 then
                local characters = atlas.accountCharacters()
                state = atlas.planCharacterStatus(mount, characters[1].guid)
                row.status:SetText(ui.planStatusLabel(state))
            elseif state == "unknown" then
                row.status:SetText(ui.planStatusLabel(state))
            elseif state == "available" and counts.available == counts.total then
                row.status:SetText("Можно идти")
            end
            row.detail:SetText(L("Можно идти: %d · Нужно обновить: %d", counts.available, counts.unknown))
            if counts.totalAttempts and counts.totalAttempts > counts.total then
                fraction = counts.completedAttempts / counts.totalAttempts
                state = fraction == 1 and "complete" or fraction > 0 and "progress"
                    or counts.availableAttempts > 0 and "available" or "unknown"
                row.status:SetText(L("Выполнено: %d / %d", counts.completedAttempts, counts.totalAttempts))
                row.detail:SetText(L("Можно идти: %d · Нужно обновить: %d", counts.availableAttempts, counts.unknownAttempts))
            end
        end
        local uncertain = state == "unknown" or state == "stale"
        local color = complete and ui.mint or state == "stale" and ui.gold or uncertain and ui.muted or ui.paper
        row.icon:SetDesaturated(complete)
        row.place:SetTextColor(unpack(complete and ui.muted or ui.gold))
        row.name:SetTextColor(unpack(complete and ui.muted or ui.paper))
        for _, dot in ipairs(row.grip) do dot:SetAlpha(complete and .42 or .72) end
        row.check:SetShown(not uncertain)
        row.unknown:SetShown(uncertain)
        ui.setIcon(row.check, complete and "ObjectiveComplete" or "Route")
        row.check:SetVertexColor(unpack(complete and { 1, 1, 1 } or ui.gold))
        row.statusColor = color
        row.status:SetTextColor(unpack(color))
        row.progress:SetAlpha(.85)
        row.progress:SetColorTexture(unpack(complete and ui.mint or ui.gold))
        row.progress:SetShown(fraction > 0)
        row.progress:SetWidth(math.max(1, progressWidth * fraction))
        row.track:SetAlpha(uncertain and .72 or 1)
        if tooltipOwner and tooltipOwner:IsVisible() then row.showStatusTooltip(tooltipOwner) end
    end
    function list:onClick(mount)
        if not atlas.mountModifiedClick(mount) then openMount(mount) end
    end
    local lastPlanID
    function page:update()
        local activeID = atlas.activePlanID()
        if lastPlanID ~= activeID then
            lastPlanID, list.offset = activeID, 0
        end
        local targets = atlas.planTargets(nil, activeID)
        if drag and drag.planID ~= activeID then stopDrag() end
        if drag then
            local retained = false
            for _, mount in ipairs(targets) do
                if mount.id == drag.mountID then retained = true; break end
            end
            if not retained then stopDrag() end
        end
        refreshPlans()
        refreshCharacterChoices()
        local listHeight = math.min(7, #characterList.items) * 42
        characterList:SetHeight(listHeight)
        menu:SetHeight(listHeight + menuInset * 2)
        characterList:redraw()
        board:SetShown(#targets == 0)
        if #targets == 0 then board:update() end
        list:SetShown(#targets > 0)
        list.items = targets
        list:redraw()
        if sources:IsShown() then sources:refresh() end
    end
    return page
end
