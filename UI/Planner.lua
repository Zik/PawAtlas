local _, atlas = ...
local ui = atlas.ui
local L = atlas.L

local function hidePlanTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
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

local function sizeMenu(dropdown, surface, width, height)
    dropdown:SetHeight(height)
    local xs, ys = { 0, 10, width - 10, width }, { 0, 10, height - 10, height }
    for row = 1, 3 do
        for col = 1, 3 do
            local texture = surface[(row - 1) * 3 + col]
            texture:ClearAllPoints()
            ui.place(texture, dropdown, xs[col], ys[row], xs[col + 1] - xs[col], ys[row + 1] - ys[row])
        end
    end
end

local function showPlanTooltip(owner, name)
    if not name then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    ui.tooltipTitle(name)
    GameTooltip:Show()
end

local function drawShareIcon(button)
    for _, direction in ipairs({ -1, 1 }) do
        local link = ui.fill(button, 12, 16.5 + direction * 4, 12, 2, ui.paper)
        link:SetRotation(-direction * math.pi / 6)
        link:SetDrawLayer("ARTWORK")
    end
    for _, center in ipairs({ { 11, 17.5 }, { 23, 10.5 }, { 23, 24.5 } }) do
        local x, y = unpack(center)
        ui.fill(button, x - 2, y - 3, 4, 6, ui.paper):SetDrawLayer("OVERLAY")
        ui.fill(button, x - 3, y - 2, 6, 4, ui.paper):SetDrawLayer("OVERLAY")
    end
end

local function planProfileList(menu, selectProfile)
    local width = menu:GetWidth()
    local surface = ui.dropdownSurface(menu)
    local plans = ui.scrollingList(menu, 8, 8, width - 16, 31, 6)
    for _, row in ipairs(plans.rows) do
        row.name = ui.text(row, 8, 0, width - 44, 29, 14, "")
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        row:HookScript("OnEnter", function(self) showPlanTooltip(self, self.item and self.item.name) end)
        row:HookScript("OnLeave", hidePlanTooltip)
        row:HookScript("OnHide", hidePlanTooltip)
    end
    function plans:render(row, profile)
        if row.profileID ~= profile.id then hidePlanTooltip(row) end
        row.profileID = profile.id
        row.name:SetText(profile.name)
        row.name:SetTextColor(unpack(profile.id == atlas.activePlanID() and ui.gold or ui.paper))
    end
    function plans:onClick(profile)
        menu:Hide()
        if profile.id ~= atlas.activePlanID() and atlas.selectPlan(profile.id) then selectProfile() end
    end
    function plans:showProfiles(profiles, bottomSpace)
        self.items = profiles
        local height = math.min(6, #profiles) * 31
        self:SetHeight(height)
        sizeMenu(menu, surface, width, height + bottomSpace)
        self:redraw()
        return height
    end
    return plans
end

function atlas.makePlanner(parent, openMount, openExpansion)
    local page = ui.place(CreateFrame("Frame", nil, parent), parent, 35, 111, 970, 460)
    ui.text(page, 0, 0, 175, 35, 23, "Планнер")
    local add = ui.action(page, 811, 0, 159, 35, "Добавить цель", "Plus", function() openMount(nil) end)
    add:setActive(true)
    local note = ui.text(page, 0, 42, 950, 22, 12, "Данные других персонажей — по последнему входу", ui.muted)
    local saved = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
    local selectedGUID = type(saved) == "table" and type(saved.plannerCharacterGUID) == "string" and saved.plannerCharacterGUID or nil
    local menu, planMenu, planChanged
    local sources = atlas.makePlannerSources(page)
    local sharing = atlas.makePlanSharing(page, function(keepSharing) planChanged(keepSharing) end)
    local dismiss = ui.button(page, 0, 38, 970, 422, function() menu:Hide(); planMenu:Hide() end)
    dismiss:SetFrameLevel(page:GetFrameLevel() + 12)
    dismiss:ClearHighlightTexture()
    dismiss:Hide()
    local characterX, characterWidth = 480, 270
    local fieldSilver = { .87, .89, .92 }
    local picker = ui.action(page, characterX, 0, characterWidth, 35, nil, nil, function()
        planMenu:Hide()
        menu:SetShown(not menu:IsShown())
    end, true)
    picker:setFieldStyle(fieldSilver)
    picker:SetFrameLevel(page:GetFrameLevel() + 13)
    local pickerName = ui.text(picker, 12, 0, characterWidth - 44, 35, 14, "Весь отряд")
    pickerName:SetMaxLines(1)
    pickerName:SetWordWrap(false)
    ui.dropdownArrow(picker, characterWidth - 26, 9, 16):SetColor(fieldSilver)
    picker:HookScript("OnEnter", function(self) showPlanTooltip(self, pickerName:GetText()) end)
    picker:HookScript("OnLeave", hidePlanTooltip)
    picker:HookScript("OnHide", hidePlanTooltip)
    menu = ui.place(CreateFrame("Frame", nil, page), page, characterX, 41, characterWidth, 50)
    menu:SetFrameLevel(picker:GetFrameLevel() + 3)
    menu:EnableMouse(true)
    local menuSurface = ui.dropdownSurface(menu)
    local characterList = ui.scrollingList(menu, 8, 8, characterWidth - 16, 34, 10)
    local planPicker = ui.action(page, 185, 0, 279, 35, nil, nil, function()
        menu:Hide()
        planMenu:SetShown(not planMenu:IsShown())
    end, true)
    planPicker:setFieldStyle(fieldSilver)
    planPicker:SetFrameLevel(picker:GetFrameLevel())
    local planName = ui.text(planPicker, 12, 0, 235, 35, 14, "")
    planName.atlasGameText = true
    planName:SetMaxLines(1)
    ui.dropdownArrow(planPicker, 253, 9, 16):SetColor(fieldSilver)
    planMenu = ui.place(CreateFrame("Frame", nil, page), page, 185, 41, 279, 90)
    planMenu:SetFrameLevel(menu:GetFrameLevel())
    planMenu:EnableMouse(true)
    local plans = planProfileList(planMenu, function() planChanged() end)
    local activeProfile
    planPicker:HookScript("OnEnter", function(self) showPlanTooltip(self, activeProfile and activeProfile.name) end)
    planPicker:HookScript("OnLeave", hidePlanTooltip)
    planPicker:HookScript("OnHide", hidePlanTooltip)
    local share = ui.action(page, 762, 0, 35, 35, nil, nil, function()
        menu:Hide(); planMenu:Hide(); sources:Hide(); sharing:open(activeProfile)
    end)
    drawShareIcon(share)
    share:HookScript("OnEnter", function(self) showPlanTooltip(self, L("Поделиться текущим планом")) end)
    share:HookScript("OnLeave", hidePlanTooltip)
    share:HookScript("OnHide", hidePlanTooltip)
    local create = ui.action(planMenu, 8, 0, 263, 30, "Создать план", nil, function()
        planMenu:Hide(); sources:Hide(); sharing:openCreate()
    end)
    local delete = ui.action(planMenu, 8, 0, 263, 30, "Удалить план", nil, function()
        planMenu:Hide(); sources:Hide(); sharing:open(activeProfile, true)
    end)
    local function refreshPlans()
        local activeID = atlas.activePlanID()
        sharing:closeIfStale(activeID)
        local profiles = atlas.planProfiles()
        for _, profile in ipairs(profiles) do
            if profile.id == activeID then activeProfile = profile; break end
        end
        planName:SetText(activeProfile.name)
        if not planMenu:IsShown() then return end
        local imported = activeProfile.id ~= "personal"
        local height = plans:showProfiles(profiles, imported and 83 or 49)
        create:ClearAllPoints()
        ui.place(create, planMenu, 8, height + 11, 263, 30)
        delete:SetShown(imported)
        if imported then
            delete:ClearAllPoints()
            ui.place(delete, planMenu, 8, height + 45, 263, 30)
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
        local pins = type(settings) == "table" and settings.plannerPinnedCharacters
        local choices, unpinned, selected = { { label = "Весь отряд" } }, {}, nil
        for _, character in ipairs(atlas.accountCharacters()) do
            local pinned = type(pins) == "table" and pins[character.guid] == true
            local entry = { guid = character.guid, label = character.name .. " · " .. character.realm, pinned = pinned }
            local group = pinned and choices or unpinned
            group[#group + 1] = entry
            if selectedGUID == character.guid then selected = entry end
        end
        for _, entry in ipairs(unpinned) do choices[#choices + 1] = entry end
        if not selected then
            local previousGUID = selectedGUID
            selectedGUID = nil
            if type(settings) == "table" then settings.plannerCharacterGUID = nil end
            if previousGUID and atlas.queueExpeditionStatsRefresh then atlas.queueExpeditionStatsRefresh() end
        end
        pickerName:SetText(selected and selected.label or "Весь отряд")
        characterList.items = choices
    end
    local function hidePinTooltip(pin)
        if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
    end
    for _, row in ipairs(characterList.rows) do
        row.name = ui.text(row, 9, 0, characterWidth - 69, 30, 14, "")
        row.name:SetMaxLines(1)
        row.name:SetWordWrap(false)
        local pin = ui.button(row, characterWidth - 56, 0, 30, 30, function(self)
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
                characterList.offset = 0
            end
            hidePinTooltip(self)
            refreshCharacterChoices()
            characterList:redraw()
        end)
        pin.icon = ui.icon(pin, 4, 4, 22, "Place")
        pin:EnableMouseWheel(true)
        pin:SetScript("OnMouseWheel", function(_, delta) characterList:scroll(-delta) end)
        pin:SetScript("OnEnter", function(self)
            local character = row.item
            if not character or not character.guid then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L(character.pinned and "Открепить персонажа" or "Закрепить персонажа"))
            GameTooltip:Show()
        end)
        pin:SetScript("OnLeave", hidePinTooltip)
        pin:SetScript("OnHide", hidePinTooltip)
        row.pin = pin
    end
    function characterList:render(row, character)
        row.name:SetText(character.label)
        row.name:SetTextColor(unpack(character.guid == selectedGUID and ui.gold or ui.paper))
        local pin = row.pin
        if pin.guid ~= character.guid then hidePinTooltip(pin) end
        pin.guid = character.guid
        pin:SetShown(character.guid ~= nil)
        pin.icon:SetDesaturated(not character.pinned)
        pin.icon:SetAlpha(character.pinned and 1 or .70)
    end
    function characterList:onClick(character)
        selectedGUID = character.guid
        if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
        MountAtlasAccountDB.settings.plannerCharacterGUID = selectedGUID
        if atlas.queueExpeditionStatsRefresh then atlas.queueExpeditionStatsRefresh() end
        menu:Hide()
        page:update()
    end
    menu:SetScript("OnShow", function()
        hidePlanTooltip(picker)
        local first = characterList.items[2]
        if first and first.pinned then characterList.offset = 0 end
        characterList:redraw()
        if not first or not first.pinned then
            for _, character in ipairs(characterList.items) do
                if character.guid == selectedGUID then characterList:reveal(character); break end
            end
        end
        dismiss:Show()
        picker:setActive(true)
    end)
    menu:SetScript("OnHide", function() dismiss:Hide(); picker:setActive(false) end)
    menu:Hide()
    page:SetScript("OnHide", function() menu:Hide(); planMenu:Hide(); sources:Hide(); sharing:Hide() end)
    local board = expansionBoard(page, openExpansion)
    local rowStep, capacity = 76, 5
    local list = ui.scrollingList(page, 0, 76, 970, rowStep, capacity)
    local overlay = CreateFrame("Frame", nil, list)
    overlay:SetAllPoints(list)
    overlay:SetFrameLevel(list:GetFrameLevel() + 8)
    overlay:EnableMouse(false)
    local marker = ui.fill(overlay, 2, 0, 958, 2, ui.gold)
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
        if x < 0 or x > 962 or y < 0 or y >= visible * rowStep then
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
        local after = y - slot * rowStep >= (rowStep - 4) / 2
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

        local gx = math.min(x + 14, 962 - ghost:GetWidth())
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

    local labels = { boss = "Босс убит", attempt = "Попытка использована", available = "Можно идти", unknown = "Нет данных", stale = "Нужно обновить" }
    for _, row in ipairs(list.rows) do
        row:GetHighlightTexture():SetAlpha(0)
        row.surface = ui.surface(row, 0, 0, 962, 72)
        row.accent = ui.fill(row, 2, 12, 2, 48, ui.rule)
        row.accent:SetDrawLayer("ARTWORK")
        ui.surface(row, 14, 12, 48, 48)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        ui.place(row.icon, row, 18, 16, 40, 40)
        row.icon:SetTexCoord(.08, .92, .08, .92)
        row.grip = {}
        for i = 0, 5 do
            local dot = ui.fill(row, 65 + i % 2 * 4, 31 + math.floor(i / 2) * 4, 2, 2, ui.gold)
            dot:SetDrawLayer("ARTWORK")
            row.grip[#row.grip + 1] = dot
        end
        row.place = ui.text(row, 76, 10, 480, 19, 12, "", ui.gold)
        row.place:SetMaxLines(1)
        row.name = ui.text(row, 76, 31, 480, 29, 17, "")
        row.name.atlasGameText = true
        row.place.atlasGameText = true
        row.name:SetMaxLines(1)
        ui.fill(row, 574, 14, 1, 44, ui.rule)
        row.status = ui.text(row, 615, 8, 296, 25, 16, "")
        row.status:SetMaxLines(1)
        row.detail = ui.text(row, 590, 49, 321, 18, 12, "", ui.muted)
        row.detail:SetMaxLines(1)
        row.check = ui.icon(row, 589, 10, 22, "ObjectiveComplete")
        row.unknown = ui.text(row, 589, 8, 22, 25, 20, "?", ui.muted)
        row.unknown:SetJustifyH("CENTER")
        row.track = ui.fill(row, 590, 38, 321, 5, { .20, .26, .28, .65 })
        row.progress = ui.fill(row, 590, 38, 321, 5, ui.mint)
        row.track:SetDrawLayer("ARTWORK", 0)
        row.progress:SetDrawLayer("ARTWORK", 1)
        row.sourceButton = ui.button(row, 586, 4, 329, 63, function()
            if row.item then menu:Hide(); planMenu:Hide(); sources:open(row.item, selectedGUID) end
        end)
        row.sourceButton:EnableMouseWheel(true)
        row.sourceButton:GetHighlightTexture():SetAlpha(0)
        row.sourceButton:SetScript("OnMouseWheel", function(_, delta) list:scroll(-delta) end)
        registerDrag(row, row)
        registerDrag(row.sourceButton, row)
        local remove = ui.action(row, 924, 22, 28, 28, nil, "Close", function()
            local planID = atlas.activePlanID()
            if row.item and atlas.isPlanned(row.item, planID) then atlas.togglePlan(row.item, planID) end
            page:update()
        end)
        remove:HookScript("OnEnter", function(self)
            if drag then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L("Убрать из плана"))
            GameTooltip:Show()
        end)
        local function hideRemoveTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
        remove:HookScript("OnLeave", hideRemoveTooltip)
        remove:HookScript("OnHide", hideRemoveTooltip)
        local function showStatusTooltip(self)
            if drag or not row.item then return end
            if not GameTooltip:IsShown() or not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self, "ANCHOR_TOP") end
            if self == row.sourceButton then
                ui.tooltipTitle(L("Посмотреть список"))
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
                    ui.tooltipLine(L(labels[accountState]), color[1], color[2], color[3], true)
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
            local shown = 0
            for _, character in ipairs(atlas.accountCharacters()) do
                if not selectedGUID or selectedGUID == character.guid then
                    -- The full roster is scrollable in the source panel/picker.
                    -- A native tooltip cannot scroll through an entire account.
                    if shown == 10 then ui.tooltipLine("…", unpack(ui.muted)); break end
                    shown = shown + 1
                    local state, _, _, progress = atlas.planCharacterStatus(row.item, character.guid)
                    local status = L(labels[state] or labels.unknown)
                    if progress and progress.totalAttempts > 1 then
                        status = L("Выполнено: %d / %d", progress.completedAttempts, progress.totalAttempts)
                        if progress.stale then status = L(labels.stale) .. " · " .. status end
                    end
                    local complete = state == "boss" or state == "attempt"
                    local uncertain = state == "unknown" or state == "stale"
                    local color = complete and ui.mint or uncertain and ui.muted or ui.paper
                    local name = ui.safeText(character.name .. " · " .. character.realm)
                    GameTooltip:AddDoubleLine(name, ui.safeText(status), ui.paper[1], ui.paper[2], ui.paper[3], unpack(color))
                end
            end
            if shown > 0 then ui.tooltipLine(" ") end
            ui.tooltipLine(L("Показан статус сохранения. Требования уровня, фракции и призыва проверяй в карточке маунта."),
                mutedR, mutedG, mutedB, true)
            ui.tooltipLine(L("Данные других персонажей — по последнему входу"), mutedR, mutedG, mutedB, true)
            GameTooltip:Show()
        end
        row.showStatusTooltip = showStatusTooltip
        row:SetScript("OnEnter", showStatusTooltip)
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
            highlightProgress(true)
            showStatusTooltip(self)
        end)
        local function hide(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
        row:SetScript("OnLeave", hide)
        row:SetScript("OnHide", hide)
        row.sourceButton:SetScript("OnLeave", function(self) highlightProgress(false); hide(self) end)
        row.sourceButton:SetScript("OnHide", function(self) highlightProgress(false); hide(self) end)
    end
    function list:render(row, mount)
        local tooltipOwner = GameTooltip:IsShown() and GameTooltip:GetOwner()
        if tooltipOwner ~= row and tooltipOwner ~= row.sourceButton then tooltipOwner = nil end
        if row.shownMountID ~= mount.id and tooltipOwner then
            GameTooltip:Hide()
            tooltipOwner = nil
        end
        row.shownMountID = mount.id
        row:SetAlpha(drag and drag.mountID == mount.id and .48 or 1)
        for _, dot in ipairs(row.grip) do dot:SetShown(#self.items > 1) end
        local sourceButton = row.sourceButton
        sourceButton.hasPlanSources = mount.kind == "Рарка" or atlas.planOpportunityProgress(mount) ~= nil
        -- A recycled row must keep the native drag receiver visible through mouse release.
        sourceButton:SetShown(sourceButton.hasPlanSources or (drag and drag.button == sourceButton))
        row.place:SetText(atlas.displayName(mount.place))
        local frequency = atlas.lootFrequency(mount)
        if frequency == "daily" or frequency == "weekly" then
            row.place:SetText(atlas.displayName(mount.place) .. " · " .. L(frequency == "daily" and "Ежедневно" or "Еженедельно"))
        end
        row.name:SetText(atlas.displayName(mount.name))
        row.icon:SetTexture(mount.icon or 132261)
        local complete, fraction, state = false, 0, "unknown"
        local owned = select(11, C_MountJournal.GetMountInfoByID(mount.id))
        local accountState = atlas.accountLootLockout(mount)
        if not (issecretvalue and issecretvalue(owned)) and owned then
            complete = true
            fraction, state = 1, "collected"
            row.status:SetText("В коллекции")
            row.detail:SetText("")
        elseif accountState then
            state, complete = accountState, accountState == "attempt"
            fraction = complete and 1 or 0
            row.status:SetText(L(labels[state]))
            row.detail:SetText(L("На аккаунт"))
        elseif selectedGUID then
            local updated, _, progress
            state, updated, _, progress = atlas.planCharacterStatus(mount, selectedGUID)
            complete = state == "boss" or state == "attempt"
            fraction = complete and 1 or 0
            row.status:SetText(labels[state] or labels.unknown)
            row.detail:SetText(updated and date("%d.%m.%Y %H:%M", updated) or "")
            if progress and progress.totalAttempts > 1 then
                fraction = progress.completedAttempts / progress.totalAttempts
                row.status:SetText(L("Выполнено: %d / %d", progress.completedAttempts, progress.totalAttempts))
                row.detail:SetText(progress.stale and "Нужно обновить"
                    or L("Можно идти: %d · Нет данных: %d", progress.availableAttempts, progress.unknownAttempts))
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
                row.status:SetText(labels[state] or labels.unknown)
            elseif state == "unknown" then
                row.status:SetText("Нет данных")
            elseif state == "available" and counts.available == counts.total then
                row.status:SetText("Можно идти")
            end
            row.detail:SetText(L("Можно идти: %d · Нет данных: %d", counts.available, counts.unknown))
            if counts.totalAttempts and counts.totalAttempts > counts.total then
                fraction = counts.completedAttempts / counts.totalAttempts
                state = fraction == 1 and "complete" or fraction > 0 and "progress"
                    or counts.availableAttempts > 0 and "available" or "unknown"
                row.status:SetText(L("Выполнено: %d / %d", counts.completedAttempts, counts.totalAttempts))
                row.detail:SetText(L("Можно идти: %d · Нет данных: %d", counts.availableAttempts, counts.unknownAttempts))
            end
        end
        local uncertain = state == "unknown" or state == "stale"
        local color = complete and ui.mint or state == "stale" and ui.gold or uncertain and ui.muted or ui.paper
        row.icon:SetDesaturated(complete)
        row.place:SetTextColor(unpack(complete and ui.muted or ui.gold))
        row.name:SetTextColor(unpack(complete and ui.muted or ui.paper))
        local surfaceTone = complete and .72 or 1
        for _, texture in ipairs(row.surface) do texture:SetVertexColor(surfaceTone, surfaceTone, surfaceTone) end
        for _, dot in ipairs(row.grip) do dot:SetAlpha(complete and .42 or .72) end
        row.check:SetShown(not uncertain)
        row.unknown:SetShown(uncertain)
        ui.setIcon(row.check, complete and "ObjectiveComplete" or "Route")
        row.check:SetVertexColor(unpack(complete and { 1, 1, 1 } or ui.gold))
        row.statusColor = color
        row.status:SetTextColor(unpack(color))
        row.progress:SetAlpha(.85)
        row.accent:SetColorTexture(unpack(complete and ui.mint or state == "available" and ui.gold or ui.rule))
        row.progress:SetShown(fraction > 0)
        row.progress:SetWidth(math.max(1, 321 * fraction))
        row.track:SetAlpha(uncertain and .4 or 1)
        if tooltipOwner and tooltipOwner:IsVisible() then row.showStatusTooltip(tooltipOwner) end
    end
    function list:onClick(mount) openMount(mount) end
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
        local listHeight = math.min(10, #characterList.items) * 34
        local menuHeight = listHeight + 16
        characterList:SetHeight(listHeight)
        sizeMenu(menu, menuSurface, characterWidth, menuHeight)
        characterList:redraw()
        note:SetShown(#targets > 0)
        board:SetShown(#targets == 0)
        if #targets == 0 then board:update() end
        list:SetShown(#targets > 0)
        list.items = targets
        list:redraw()
        if sources:IsShown() then sources:refresh() end
    end
    page:Hide()
    return page
end
