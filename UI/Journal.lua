local _, atlas = ...
local ui = atlas.ui
local L = atlas.L
local w, h = 1040, 620
local frame = CreateFrame("Frame", "MountAtlasWindow", UIParent)
frame:SetSize(w, h)
frame:SetPoint("CENTER")
frame:SetFrameStrata("DIALOG")
frame:SetClampedToScreen(true)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:Hide()
ui.fill(frame, 0, 0, w, h, ui.ink)
ui.windowBorder(frame, w, h)
local headerRule = ui.fill(frame, 18, 86, w - 36, 1, ui.rule)
headerRule:SetAlpha(.6)
local headerLight = frame:CreateTexture(nil, "ARTWORK")
ui.place(headerLight, frame, 24, 83, 370, 5)
headerLight:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\SoftGlow.tga")
headerLight:SetVertexColor(1, .76, .30, .8)
local catalogShells = { ui.surface(frame, 12, 96, 300, 478), ui.surface(frame, 320, 96, 708, 478) }
local plannerShell = ui.surface(frame, 12, 96, 1016, 478)
ui.brandIcon(frame, 22, 22, 46)
ui.fill(frame, 1, 584, w - 2, 1, ui.gold)
local guide = ui.text(frame, 76, 13, 325, 19, 10, "ПОЛЕВОЙ СПРАВОЧНИК   /   АЗЕРОТ", ui.gold)
guide:SetMaxLines(1)
local shared
ui.text(frame, 75, 33, 335, 37, 29, "PawAtlas", ui.gold)
local collectionBadge = ui.place(CreateFrame("Button", nil, frame), frame, 405, 17, 182, 54)
do
    for _, side in ipairs({ "left", "right" }) do
        local branch = collectionBadge:CreateTexture(nil, "ARTWORK")
        ui.place(branch, collectionBadge, side == "left" and -8 or 154, -7, 36, 72)
        branch:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\CollectionLaurel.tga")
        if side == "right" then branch:SetTexCoord(1, 0, 0, 1) end
    end
    collectionBadge.count = ui.text(collectionBadge, 12, 3, 158, 25, 20, "", ui.gold)
    collectionBadge.count:SetJustifyH("CENTER")
    collectionBadge.count:SetMaxLines(1)
    local label = ui.text(collectionBadge, 12, 28, 158, 15, 10, "В коллекции", ui.muted)
    label:SetJustifyH("CENTER")
    local track = ui.fill(collectionBadge, 36, 46, 110, 2, ui.rule)
    track:SetDrawLayer("ARTWORK")
    track:SetAlpha(.55)
    collectionBadge.fill = ui.fill(collectionBadge, 36, 46, 1, 2, ui.gold)
    collectionBadge.fill:SetDrawLayer("ARTWORK", 1)
    collectionBadge.fill:SetGradient("HORIZONTAL", CreateColor(.55, .42, .22), CreateColor(.92, .76, .44))
    collectionBadge:RegisterForClicks("LeftButtonUp")
    collectionBadge:SetScript("OnClick", function()
        if not shared and IsShiftKeyDown() then atlas.shareCollectionLink() end
    end)
    collectionBadge:SetScript("OnEnter", function(self)
        if shared then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("В коллекции"))
        ui.tooltipLine(L("Shift + ЛКМ — вставить ссылку в открытый чат"), unpack(ui.muted))
        GameTooltip:Show()
    end)
    local function hideTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    collectionBadge:SetScript("OnLeave", hideTooltip)
    collectionBadge:SetScript("OnHide", hideTooltip)
end
local commandHint = ui.text(frame, 25, 592, 350, 19, 11, "PAWATLAS     /     Открыть в игре: /paw", ui.muted)
commandHint:SetWordWrap(false)
local feedback = ui.text(frame, 530, 592, 481, 19, 12, "", ui.muted)
feedback:SetWordWrap(false)
feedback:SetJustifyH("RIGHT")

local page = ui.place(CreateFrame("Frame", nil, frame), frame, 0, 102, w, 473)
local function setFooter(message)
    feedback:SetText(message or (page:IsShown() and "Shift на названии — 3D-модель" or ""))
    feedback:SetTextColor(unpack(message and ui.gold or ui.muted))
end
local selected, planner, settings
local locationIndex = 1
local refresh, showPage, returnToCollection
local catalogTab = ui.action(frame, 630, 25, 148, 43, "Каталог", "Book", function() showPage(false) end)
local planTab = ui.action(frame, 786, 25, 146, 43, "Планнер", "Route", function() showPage(true) end)
local settingsTab = ui.action(frame, 940, 27, 34, 39, nil, "Settings", function() atlas.toggleSettings() end)
local returnTab = ui.action(frame, 786, 25, 188, 43, "Вернуться к своей коллекции", nil,
    function() returnToCollection() end)
ui.setFont(returnTab.caption, 12)
returnTab.caption:SetMaxLines(2)
returnTab:Hide()
ui.action(frame, 982, 27, 34, 39, nil, "Close", function() frame:Hide() end)


local sourceFilter, expansionFilter
local found = ui.text(page, 220, 87, 72, 21, 12, "", ui.muted)
found:SetJustifyH("RIGHT")
local catalog = ui.scrollingList(page, 26, 212, 272, 48, 5, true)
local search = ui.place(CreateFrame("EditBox", "MountAtlasSearch", page), page, 56, 8, 210, 37)
local searchQuery = atlas.searchQuery("")
search:SetAutoFocus(false)
ui.setFont(search, 15)
search:SetTextColor(unpack(ui.paper))
search:SetTextInsets(4, 4, 0, 0)
local hint = ui.text(search, 4, 0, 204, 37, 14, "Имя, босс или место", ui.muted)
do
    local rim = ui.surface(page, 26, 8, 272, 37)
    local loupe = ui.icon(page, 36, 18, 18, "Search")
    hint:SetAlpha(.72)
    local function updateFocus(focused)
        local r, g, b = 1, 1, 1
        if not focused then r, g, b = .67, .73, .79 end
        for _, texture in ipairs(rim) do texture:SetVertexColor(r, g, b) end
        loupe:SetVertexColor(unpack(focused and ui.paper or ui.muted))
        hint:SetShown(not focused and search:GetText() == "")
    end
    search:HookScript("OnEditFocusGained", function() updateFocus(true) end)
    search:HookScript("OnEditFocusLost", function() updateFocus(false) end)
    search:HookScript("OnHide", function(self) self:ClearFocus() end)
    updateFocus(false)
end
local clear = ui.place(CreateFrame("Button", nil, page), page, 266, 8, 30, 37)
clear:SetScript("OnClick", function() expansionFilter = nil; search:SetText(""); refresh(); search:SetFocus() end)
local clearIcon = ui.icon(clear, 7, 11, 15, "Close")
clearIcon:SetVertexColor(unpack(ui.muted))
clear:SetScript("OnEnter", function() clearIcon:SetVertexColor(unpack(ui.gold)) end)
clear:SetScript("OnLeave", function() clearIcon:SetVertexColor(unpack(ui.muted)) end)
local filters = {}
local activeFilter = 1
for _, entry in ipairs({ { "Не получены", 0, 85, 3 }, { "Получены", 91, 85, 2 }, { "Все", 182, 85, 1 } }) do
    local filterID = entry[4]
    filters[filterID] = ui.action(page, 26 + entry[2], 51, entry[3], 28, entry[1], nil, function()
        activeFilter = shared and 2 or filterID
        refresh()
    end)
    ui.setFont(filters[filterID].caption, 12)
end

ui.icon(page, 30, 89, 19, "Scroll")
ui.text(page, 57, 87, 162, 23, 14, "Фильтры", ui.gold)
local questFilters, questOnly, frequency = {}, false, nil
for i, entry in ipairs({
    { "Все", 26, 113, 130, "All" },
    { "Квест", 163, 113, 130, "Quest" },
    { "Рарки", 26, 145, 130, "Rare" },
    { "Рейд", 163, 145, 130, "Boss" },
    { "Ежедневно", 26, 177, 130, "Calendar" },
    { "Еженедельно", 163, 177, 130, "Calendar" },
}) do
    questFilters[i] = ui.action(page, entry[2], entry[3], entry[4], 27, entry[1], entry[5], function()
        if i == 1 then questOnly, frequency, sourceFilter, expansionFilter = false, nil, nil, nil
        elseif i == 2 then questOnly = not questOnly
        elseif i == 3 or i == 4 then
            local value = i == 3 and "rare" or "raid"
            sourceFilter = sourceFilter ~= value and value or nil
        else
            local value = i == 5 and "daily" or "weekly"
            frequency = frequency ~= value and value or nil
        end
        refresh()
    end)
    ui.setFont(questFilters[i].caption, 12)
end

local showEmpty = atlas.emptyCatalog(page, function()
    activeFilter, questOnly, frequency, sourceFilter, expansionFilter = shared and 2 or 1, false, nil, nil, nil
    search:SetText("")
    refresh()
end)
local collectionStatus = ui.text(page, 340, 184, 668, 56, 17, "", ui.muted)
collectionStatus:SetJustifyH("CENTER")
collectionStatus:Hide()
local card = ui.place(CreateFrame("Frame", nil, page), page, 340, 8, 668, 454)
local headerArt = card:CreateTexture(nil, "BACKGROUND", nil, -1)
ui.place(headerArt, card, 0, -2, 668, 105)
headerArt:SetTexCoord(0, 1, .06, .532)
headerArt:SetAlpha(.85)
local headerMask = card:CreateMaskTexture()
headerMask:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\HeaderMask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
headerMask:SetAllPoints(headerArt)
headerArt:AddMaskTexture(headerMask)
local expansionLogo = card:CreateTexture(nil, "ARTWORK")
ui.place(expansionLogo, card, 468, 0, 196, 96)
expansionLogo:SetAlpha(.85)
local sourcePanel = ui.surface(card, 0, 182, 296, 64)
local placePanel = ui.surface(card, 308, 182, 360, 64)
local chancePanel = ui.surface(card, 0, 329, 668, 81, true)
for _, texture in ipairs(chancePanel) do
    texture:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\OrnateChance.tga")
end
local killsPanel = ui.surface(card, 0, 422, 320, 38)
local bindHover = atlas.bindModelPreview(frame)
local titleArea = ui.place(CreateFrame("Frame", nil, card), card, 0, 0, 462, 100)
titleArea:EnableMouse(true)
local title = ui.text(titleArea, 0, 0, 462, 100, 27, "")
title.atlasGameText = true
bindHover(titleArea, function() return selected end)
titleArea:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" and IsShiftKeyDown() and selected then atlas.linkMount(selected) end
end)
title:SetMaxLines(2)
titleArea.classRequirement = ui.text(card, 8, 96, 454, 15, 13, "", ui.gold)
local lore = ui.text(card, 8, 111, 652, 62, 15, "", ui.muted)
lore.atlasGameText = true
lore:SetMaxLines(3)
local function locations()
    return selected and atlas.mountLocations(selected) or {}
end
local sourceChoices, vendorIndex, vendorMount = {}, 1, nil
local function currentChoice() return sourceChoices[vendorIndex] end
local function currentVendor() local choice = currentChoice(); return choice and choice.vendor end
local function currentSource() local choice = currentChoice(); return choice and choice.view or selected end
local function location(points)
    points = points or locations()
    locationIndex = math.max(1, math.min(locationIndex, #points))
    local point = points[locationIndex]
    if selected and (selected.locations or (selected.hasSourcePanels and #sourceChoices <= 1
        and not currentVendor() and atlas.hasSourceCoordinates(point))) then return point end
end
local function buildSourceChoices(mount)
    local choices, hasVendor = {}, false
    local blocks = atlas.factionSources and atlas.factionSources(mount)
    for _, block in ipairs(blocks or { mount }) do
        local vendors = atlas.vendorSources and atlas.vendorSources(block)
        if vendors then
            hasVendor = true
            for _, vendor in ipairs(vendors) do choices[#choices + 1] = { vendor = vendor, view = block } end
        elseif blocks then
            choices[#choices + 1] = { view = block, compact = true }
        else
            for _, group in ipairs(mount.sourceGroups or {}) do
                choices[#choices + 1] = { view = group, separated = true }
            end
        end
    end
    -- These alternatives are reviewed acquisition routes, not another copy of
    -- the journal/vendor text. Their rate and attempts stay in the core stages.
    local route = hasVendor and atlas.verifiedRewardDropRoute and atlas.verifiedRewardDropRoute(mount)
    if route then
        for _, entry in ipairs(route.routes or { route }) do
            local boss, place = entry.boss or route.boss, entry.place or route.place
            if boss and place then
                local condition = entry.condition or route.condition
                local faction = entry.faction or route.faction
                local view = {
                    id = mount.id, boss = boss, place = place, faction = faction,
                    englishBoss = entry.englishBoss or route.englishBoss,
                    englishPlace = entry.englishPlace or route.englishPlace,
                    sourceKind = entry.sourceKind or route.sourceKind or "Добыча",
                    sourcePlaceKind = entry.placeKind or route.placeKind or "Открытый мир",
                    sourceMap = entry.map or route.map, conditions = condition,
                    difficultyLocalOnly = true, trackingCompatible = true, hasSourcePanels = true,
                    journalSourceRaw = "Источник: " .. boss .. "\nМесто: " .. place .. (condition and "\n" .. condition or ""),
                }
                choices[#choices + 1] = { view = view, separated = true, verifiedDrop = true }
            end
        end
    end
    return choices
end
local function groupName(group)
    local name = group.name or group.boss
    return name and name ~= "" and atlas.displayName(name) or L("Источник не указан")
end
local sourceButton = ui.place(CreateFrame("Button", nil, card), card, 11, 207, 272, 34)
sourceButton:SetScript("OnClick", function(_, button)
    GameTooltip:Hide()
    if button == "LeftButton" and IsShiftKeyDown() then
        local vendor, loc, view = currentVendor(), location(), currentSource()
        atlas.linkSourceName(not vendor and not loc and view or nil,
            vendor and groupName(vendor) or atlas.displayName(loc and loc.boss or view.boss))
        return
    end
    if currentVendor() then return end
    local view = currentSource()
    if view.journalEncounter then setFooter(atlas.openSource(view)) end
end)
local source = ui.text(sourceButton, 0, 0, 272, 34, 14, "", ui.gold)
source.atlasGameText = true
source:SetMaxLines(2)
local bossCheck = ui.place(CreateFrame("Frame", nil, sourceButton), sourceButton, 244, 3, 28, 28)
bossCheck:EnableMouse(true)
ui.icon(bossCheck, 2, 2, 24, "ObjectiveComplete")
bossCheck:Hide()
bossCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ui.tooltipTitle(L(self.statusLabel or "Босс убит"), unpack(ui.mint))
    GameTooltip:Show()
end)
local function hideBossTooltip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
bossCheck:SetScript("OnLeave", hideBossTooltip)
bossCheck:SetScript("OnHide", hideBossTooltip)
local function refreshBossCheck(view, visible, link, point, progress)
    local route = selected.encounter and #sourceChoices <= 1 and selected or view
    local killed = visible and not point and atlas.bossLockout
        and (view.sourceKind == "Босс" or (route == selected and selected.encounter))
        and atlas.bossLockout(selected, route) == "boss" or false
    local statusLabel = "Босс убит"
    if visible and point and point.npc and progress and view.trackingCompatible ~= false then
        for _, entry in ipairs(progress.entries or {}) do
            for _, npc in ipairs(entry.npcs or {}) do
                if npc == point.npc and entry.state == "attempt" then
                    killed, statusLabel = true, "Попытка использована"
                end
            end
        end
    end
    bossCheck.statusLabel = statusLabel
    if killed and GameTooltip:IsOwned(bossCheck) then
        ui.tooltipTitle(L(statusLabel), unpack(ui.mint))
        GameTooltip:Show()
    end
    local inset = sourceButton.pagerInset or 0
    if bossCheck:IsShown() ~= killed or bossCheck.layoutInset ~= inset then
        bossCheck.layoutInset = inset
        bossCheck:SetShown(killed)
        bossCheck:ClearAllPoints()
        ui.place(bossCheck, sourceButton, 244 - inset, 3, 28, 28)
        source:ClearAllPoints()
        ui.place(source, sourceButton, 0, 0, (killed and 236 or 272) - inset, 34)
    end
    source:SetTextColor(unpack(killed and ui.muted or (link and ui.gold or ui.paper)))
    if killed then source:SetShadowColor(0, 0, 0, 1) end
end
local sourceIcon
local sourceProgress
sourceButton.atlasTradingPostSource = true
sourceButton:SetScript("OnEnter", function(self)
    local view = currentSource()
    if not bossCheck:IsShown() and not currentVendor() and view.journalEncounter then
        source:SetTextColor(1, .91, .65)
        source:SetShadowColor(.95, .65, .18, .65)
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local point = location()
    local vendor = currentVendor()
    if vendor then
        ui.tooltipTitle(groupName(vendor))
        if vendor.place and vendor.place ~= "" then ui.tooltipLine(atlas.displayName(vendor.place), 1, 1, 1, true) end
        local offer = selected and selected.vendorTokenOffer
        if offer and offer.previousAchievement then
            local previousName
            if GetAchievementInfo then
                local ok, _, name = pcall(GetAchievementInfo, offer.previousAchievement)
                if ok and not (issecretvalue and issecretvalue(name)) and type(name) == "string" and name ~= "" then previousName = name end
            end
            if not previousName then
                local raw = atlas.getLocale() == "enUS" and offer.englishJournalSource or offer.journalSource
                previousName = atlas.normalizeSource(raw or ""):match("^[^:\n]+:%s*([^\n]+)")
            end
            if previousName and previousName ~= "" then
                ui.tooltipLine(" ")
                ui.tooltipSourceText(L("Был доступен: %s", previousName), ui.muted)
            end
        end
    elseif currentChoice() and currentChoice().separated and not point then
        ui.tooltipTitle(view.journalEncounter and L("Открыть босса в путеводителе") or atlas.displayName(view.boss))
        local text = atlas.displaySourceText(atlas.normalizeSource(view.journalSourceRaw or ""))
        if text ~= "" then ui.tooltipSourceText(text)
        elseif view.place then ui.tooltipLine(atlas.displayName(view.place), 1, 1, 1, true) end
    elseif point then
        ui.tooltipTitle(atlas.displayName(point.boss))
        ui.tooltipLine(atlas.displayName(point.place))
        if point.condition then
            ui.tooltipLine(" ")
            ui.tooltipSourceText(atlas.displaySourceText(point.condition), ui.gold)
        end
    elseif view.journalEncounter then
        ui.tooltipTitle(L("Открыть босса в путеводителе"))
    else
        ui.tooltipTitle(atlas.displayName(view.boss))
        ui.tooltipLine(atlas.displayName(view.place), 1, 1, 1, true)
    end
    local stages = not vendor and view.trackingCompatible ~= false and atlas.attemptStages[selected.id]
    local condition = stages and stages.reward and stages.reward.condition
    if condition then
        ui.tooltipLine(" ")
        ui.tooltipSourceText(L(condition), ui.gold)
    end
    ui.tooltipSourceAlternatives(selected)
    GameTooltip:Show()
end)
local function leaveSource(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    local view = currentSource()
    local link = view and view.journalEncounter
    source:SetTextColor(unpack(bossCheck:IsShown() and ui.muted or ((currentVendor() or link) and ui.gold or ui.paper)))
    source:SetShadowColor(0, 0, 0, 1)
end
sourceButton:SetScript("OnLeave", leaveSource)
sourceButton:SetScript("OnHide", leaveSource)
local placeArea = ui.place(CreateFrame("Button", nil, card), card, 322, 207, 334, 34)
placeArea:EnableMouse(true)
local place = ui.text(placeArea, 0, 0, 334, 34, 14, "")
place.atlasGameText = true
place:SetMaxLines(2)
local function placeLink()
    local view = currentSource()
    return not currentVendor() and view and view.journalInstance and view or nil
end
placeArea:SetScript("OnClick", function(_, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        local vendor, loc, view = currentVendor(), location(), currentSource()
        atlas.linkSourceName(not vendor and not loc and view or nil,
            atlas.displayName(atlas.placeWithoutDifficulty(view, vendor and vendor.place or loc and loc.place or view.place)), true)
        return
    end
    local view = placeLink()
    if view and atlas.openPlace then GameTooltip:Hide(); setFooter(atlas.openPlace(view)) end
end)
placeArea:SetScript("OnEnter", function(self)
    if not placeLink() and not place:IsTruncated() then
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        return
    end
    if placeLink() then place:SetTextColor(1, .91, .65) end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    ui.tooltipTitle(place:GetText(), 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
local function hidePlaceTooltip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    place:SetTextColor(unpack(placeLink() and ui.gold or ui.paper))
end
placeArea:SetScript("OnLeave", hidePlaceTooltip)
placeArea:SetScript("OnHide", hidePlaceTooltip)
local function setFieldIcon(texture, name, x, y)
    -- Native map icons include transparent margins. Keep their aspect ratio
    -- while giving the visible glyph the same height as the other headings.
    local size = ({ Boss = 23, Rare = 28, Vendor = 22, Raid = 32, Dungeon = 32, Place = 32, Chance = 23, Quest = 22 })[name] or 20
    texture:ClearAllPoints()
    ui.place(texture, card, x + 11 - size / 2, y + 9.5 - size / 2, size, size)
    ui.setIcon(texture, name)
end
local function fieldLabel(x, y, icon, label)
    local tex = card:CreateTexture(nil, "ARTWORK")
    setFieldIcon(tex, icon, x, y)
    return ui.text(card, x + 29, y, 220, 19, 13, label, ui.muted), tex
end
local sourceType
sourceType, sourceIcon = fieldLabel(12, 189, "Boss", "")
sourceProgress = ui.place(CreateFrame("Frame", nil, card), card, 205, 186, 78, 22)
sourceProgress:EnableMouse(true)
ui.icon(sourceProgress, 0, 3, 16, "Calendar")
sourceProgress.label = ui.text(sourceProgress, 20, 0, 58, 22, 12, "", ui.mint)
sourceProgress.label:SetJustifyH("RIGHT")
sourceProgress:SetScript("OnEnter", function(self)
    local progress = self.progress
    if not progress then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ui.tooltipTitle(L(progress.frequency == "weekly" and "Еженедельно" or "Ежедневно"))
    ui.tooltipLine(L("Персонаж") .. ": " .. (UnitName("player") or ""), 1, 1, 1)
    ui.tooltipLine(L("Выполнено: %d / %d", progress.completedAttempts, progress.totalAttempts), 1, 1, 1)
    ui.tooltipLine(L("Можно идти: %d · Нет данных: %d", progress.availableAttempts, progress.unknownAttempts), unpack(ui.muted))
    GameTooltip:Show()
end)
sourceProgress:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
sourceProgress:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
local placeLabel, placeIcon = fieldLabel(322, 189, "Place", "Место")
placeLabel:SetWidth(180)
local detail = ui.text(card, 8, 262, 652, 48, 13, "", ui.muted)
local sourcePager = ui.place(CreateFrame("Frame", nil, card), card, 530, 186, 127, 21)
sourcePager:SetFrameLevel(card:GetFrameLevel() + 5)
local counter = ui.text(sourcePager, 29, 0, 66, 21, 12, "", ui.muted)
counter:SetJustifyH("CENTER")
local function cycle(delta, pointOnly)
    if not pointOnly and #sourceChoices > 1 then
        vendorIndex = (vendorIndex - 1 + delta) % #sourceChoices + 1
        locationIndex = 1
    else
        local count = #locations()
        if count < 2 then return end
        locationIndex = (locationIndex - 1 + delta) % count + 1
    end
    GameTooltip:Hide()
    setFooter()
    atlas.refreshDetails()
end
local prev = ui.action(sourcePager, 0, 0, 25, 21, "‹", nil, function() cycle(-1) end)
local following = ui.action(sourcePager, 102, 0, 25, 21, "›", nil, function() cycle(1) end)

do
    local pager = ui.place(CreateFrame("Frame", nil, card), card, 570, 188, 86, 21)
    local pointCounter = ui.text(pager, 21, 0, 44, 21, 12, "", ui.muted)
    pointCounter:SetJustifyH("CENTER")
    for _, direction in ipairs({ -1, 1 }) do
        local arrow = ui.place(CreateFrame("Button", nil, pager), pager, direction < 0 and 0 or 65, 0, 21, 21)
        local label = ui.text(arrow, 0, 0, 21, 21, 20, direction < 0 and "‹" or "›", ui.gold)
        label:SetJustifyH("CENTER")
        arrow:SetScript("OnClick", function() cycle(direction, true) end)
        arrow:SetScript("OnEnter", function() label:SetTextColor(1, .91, .65) end)
        local function reset() label:SetTextColor(unpack(ui.gold)) end
        arrow:SetScript("OnLeave", reset)
        arrow:SetScript("OnHide", reset)
    end
    local coords = ui.place(CreateFrame("Button", nil, card), card, 566, 212, 90, 25)
    coords.caption = ui.text(coords, 0, 0, 90, 25, 14, "", ui.gold)
    coords.caption:SetJustifyH("CENTER")
    coords:SetScript("OnClick", function(self)
        if not self.point then return end
        GameTooltip:Hide()
        setFooter(atlas.openSource({ id = selected.id }, self.point))
    end)
    placeArea.waypoint = coords
    function coords:refreshTooltip()
        if not self.point then return end
        self.caption:SetTextColor(1, .91, .65)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Поставить метку"))
        GameTooltip:Show()
    end
    coords:SetScript("OnEnter", coords.refreshTooltip)
    local function clearWaypointTooltip(self)
        self.caption:SetTextColor(unpack(self.point and ui.gold or ui.muted))
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    coords:SetScript("OnLeave", clearWaypointTooltip)
    coords:SetScript("OnHide", clearWaypointTooltip)
    coords:SetScript("OnDisable", clearWaypointTooltip)
    function placeArea:updateNavigation(visible, point, count, badge)
        local exact = visible and point and type(point.map) == "number" and type(point.x) == "number"
            and type(point.y) == "number" and point.x >= 0 and point.x <= 1 and point.y >= 0 and point.y <= 1
        local multiple = visible and count > 1
        local inset = badge and 52 or 0
        if pager.inset ~= inset then
            pager.inset = inset
            pager:ClearAllPoints()
            pager:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12 - inset, -188)
            coords:ClearAllPoints()
            coords:SetPoint("TOPRIGHT", card, "TOPRIGHT", -12 - inset, -212)
        end
        pager:SetShown(multiple == true)
        pointCounter:SetText(multiple and locationIndex .. " / " .. count or "")
        coords.point = exact and point or nil
        coords:SetShown(exact == true)
        coords:SetEnabled(exact == true)
        if not GameTooltip:IsShown() or not GameTooltip:IsOwned(coords) then
            coords.caption:SetTextColor(unpack(exact and ui.gold or ui.muted))
        end
        coords.caption:SetText(exact and ("%.1f, %.1f"):format(point.x * 100, point.y * 100) or "")
        local textWidth = 334 - inset - (exact and 98 or 0)
        placeArea:SetWidth(textWidth)
        place:SetWidth(textWidth)
        return multiple == true
    end
end

local oddsLabel, oddsIcon = fieldLabel(16, 341, "Chance", "Шанс выпадения")
oddsLabel:SetWidth(328)
local baseOdds = ui.text(card, 382, 341, 264, 19, 12, "", ui.muted)
baseOdds:SetJustifyH("RIGHT")
baseOdds:SetWordWrap(false)
local displayedAttempts, displayedReward, displayedProbability
local probabilityText = ui.probabilityText
local attemptsLabel, attemptsIcon = fieldLabel(14, 431, "Kills", "")
local oddsArea = ui.place(CreateFrame("Frame", nil, card), card, 16, 364, 211, 37)
oddsArea:EnableMouse(true)
local odds = ui.text(oddsArea, 0, 0, 211, 37, 30, "")
local oddsGlow = {}
for _, offset in ipairs({ {-1, 0}, {1, 0}, {0, -1}, {0, 1} }) do
    local glow = ui.text(oddsArea, offset[1], offset[2], 211, 37, 30, "", { 1, .72, .24 })
    glow:SetDrawLayer("OVERLAY", -1)
    glow:SetShadowColor(0, 0, 0, 0)
    glow:Hide()
    oddsGlow[#oddsGlow + 1] = glow
end
oddsArea:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ui.tooltipTitle(oddsLabel:GetText(), unpack(ui.gold))
    if displayedReward then
        ui.tooltipLine(L(displayedReward.condition), 1, 1, 1, true)
        local progress = selected and atlas.itemAttemptProgress and atlas.itemAttemptProgress(selected)
        if progress and progress.perAttempt ~= nil then
            local item = atlas.lootItems[selected.id]
            local name = progress.name or (C_Item.GetItemInfo and C_Item.GetItemInfo(progress.item))
                or (item and item.item == progress.item and (atlas.dataName and atlas.dataName(item) or item.name)) or RETRIEVING_ITEM_INFO
            ui.tooltipLine(atlas.displayName(name) .. ": " .. probabilityText(progress.perAttempt, progress.perAttempt == 1), 1, 1, 1, true)
            if progress.rateEstimated then ui.tooltipLine(L("Предположительный шанс")) end
        end
    elseif displayedAttempts ~= nil then
        ui.tooltipLine(L("Попыток: %s", displayedAttempts), 1, 1, 1, true)
        ui.tooltipLine(baseOdds:GetText(), 1, 1, 1, true)
        ui.tooltipLine(" ")
        ui.tooltipLine(L("Вероятность хотя бы одного выпадения за все учтённые попытки при постоянном шансе и независимых попытках."), ui.muted[1], ui.muted[2], ui.muted[3], true)
        ui.tooltipLine(L("Шанс следующей попытки не увеличивается."), ui.muted[1], ui.muted[2], ui.muted[3], true)
    else
        ui.tooltipLine(baseOdds:GetText(), 1, 1, 1, true)
        ui.tooltipLine(" ")
        for _, tier in ipairs(ui.chances) do ui.tooltipLine(L(tier.label), unpack(tier.color)) end
    end
    local progress = selected and atlas.itemAttemptProgress and atlas.itemAttemptProgress(selected)
    if progress and progress.contentsPerOpening then
        ui.tooltipLine(L("Учитывает выпадение клетки и маунта из неё. При открытии клетки — %s на этого маунта",
            probabilityText(progress.contentsPerOpening)), 1, 1, 1, true)
        if progress.rateEstimated then ui.tooltipLine(L("Предположительный шанс")) end
    end
    GameTooltip:Show()
end)
local function hideOdds(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
oddsArea:SetScript("OnLeave", hideOdds)
oddsArea:SetScript("OnHide", hideOdds)
local kills = ui.text(card, 222, 426, 84, 29, 22, "")
kills:SetJustifyH("RIGHT")
local killsHelp = ui.place(CreateFrame("Frame", nil, card), card, 0, 422, 320, 38)
killsHelp:EnableMouse(true)
killsHelp:SetScript("OnEnter", function(self)
    if not selected then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    ui.tooltipTitle(attemptsLabel:GetText(), unpack(ui.gold))
    if self.encounterEstimate then
        ui.tooltipLine("Rarity " .. kills:GetText(), 1, 1, 1)
        ui.tooltipLine(L(self.encounterEstimate), ui.muted[1], ui.muted[2], ui.muted[3], true)
        GameTooltip:Show()
        return
    end
    ui.tooltipLine(L("Попыток: %s", kills:GetText()), 1, 1, 1)
    ui.tooltipLine(" ")
    local help = self.localBossCounter
        and "История убийств до установки аддона не загружается. Учитываются убийства, записанные аддоном, и импорт из Rarity."
        or "Попытки всех учтённых персонажей аккаунта. Доступная история загружается при входе на каждого персонажа; остальные попытки считаются с момента установки аддона"
    ui.tooltipLine(L(help), ui.muted[1], ui.muted[2], ui.muted[3], true)
    GameTooltip:Show()
end)
local function hideKillsTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
killsHelp:SetScript("OnLeave", hideKillsTooltip)
killsHelp:SetScript("OnHide", hideKillsTooltip)
local chanceTrack = ui.place(CreateFrame("Frame", nil, card), card, 265, 367, 381, 22)
chanceTrack:EnableMouse(true)
chanceTrack:SetScript("OnEnter", function(self)
    if displayedProbability == nil or displayedReward then return end
    local step = math.max(1, math.min(#ui.chanceFlavors, math.ceil(displayedProbability * 10)))
    local r, g, b = odds:GetTextColor()
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ui.tooltipTitle(L(ui.chanceFlavors[step]), r, g, b)
    GameTooltip:Show()
end)
chanceTrack:SetScript("OnLeave", hideOdds)
chanceTrack:SetScript("OnHide", hideOdds)
local chanceRail = ui.fill(chanceTrack, 0, 1, 381, 5, ui.rule)
chanceRail:SetGradient("HORIZONTAL", CreateColor(.28, .32, .35, 1), CreateColor(.21, .49, .33, 1))
for i = 1, 3 do ui.fill(chanceTrack, 381 * i / 4, 9, 1, 3, ui.muted) end
local chanceFill = ui.fill(chanceTrack, 0, 1, 1, 5, { 1, 1, 1 })
chanceFill:SetDrawLayer("ARTWORK", 1)
local chanceGlow = {}
for i, y in ipairs({ -4, 6 }) do
    local glow = ui.fill(chanceTrack, 0, y, 381, 5, { 1, .72, .24 })
    glow:SetDrawLayer("ARTWORK")
    glow:SetBlendMode("ADD")
    local clearGold, brightGold = CreateColor(1, .72, .24, 0), CreateColor(1, .72, .24, .38)
    glow:SetGradient("VERTICAL", i == 1 and brightGold or clearGold, i == 1 and clearGold or brightGold)
    glow:Hide()
    chanceGlow[#chanceGlow + 1] = glow
end
local chanceMarker = ui.fill(chanceTrack, 0, 0, 2, 8, ui.gold)
do
    local halo = ui.fill(chanceTrack, 0, -4, 1, 5, { 1, 1, 1 })
    halo:SetDrawLayer("ARTWORK")
    halo:SetBlendMode("ADD")
    halo:Hide()
    local rays, active = {}, false
    local shapes = {
        { .031, 8, 7 }, { .083, 11, 14 }, { .150, 7, 8 }, { .202, 9, 11 }, { .282, 8, 6 },
        { .340, 10, 12 }, { .395, 8, 8 }, { .468, 11, 15 }, { .542, 9, 7 }, { .607, 10, 11 },
        { .660, 8, 8 }, { .728, 9, 13 }, { .805, 7, 7 }, { .872, 10, 12 }, { .955, 8, 8 },
    }
    for index, shape in ipairs(shapes) do
        local ray = chanceTrack:CreateTexture(nil, "ARTWORK")
        ray:SetSize(shape[2], shape[3])
        ray:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
        -- The cropped upper tip tapers to a point and meets the fill at its bright base.
        ray:SetTexCoord(0, 1, 3 / 32, 13 / 32)
        ray:SetBlendMode("ADD")
        ray:Hide()
        local motion = ray:CreateAnimationGroup()
        motion:SetLooping("REPEAT")
        local peak = .62 + (index % 4) * .045
        local fadeIn = motion:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(.14)
        fadeIn:SetToAlpha(peak)
        fadeIn:SetDuration(.74)
        fadeIn:SetStartDelay((index % 4) * .13)
        fadeIn:SetOrder(1)
        fadeIn:SetSmoothing("IN_OUT")
        local fadeOut = motion:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(peak)
        fadeOut:SetToAlpha(.14)
        fadeOut:SetDuration(1.36 + ((index * 3) % 5) * .11)
        fadeOut:SetOrder(2)
        fadeOut:SetSmoothing("IN_OUT")
        rays[index] = { texture = ray, motion = motion, position = shape[1] }
    end
    local function play()
        if active then for _, ray in ipairs(rays) do ray.motion:Play() end end
    end
    local function stop()
        for _, ray in ipairs(rays) do ray.motion:Stop() end
    end
    chanceTrack:HookScript("OnShow", play)
    chanceTrack:HookScript("OnHide", stop)
    local lastWidth, lastRed, lastGreen, lastBlue
    function chanceTrack:setRays(width, showHalo, red, green, blue)
        if not width then
            if active then
                active = false
                stop()
                halo:Hide()
                for _, ray in ipairs(rays) do ray.texture:Hide() end
            end
            return
        end
        if lastWidth ~= width then
            lastWidth = width
            halo:SetWidth(width)
            for _, ray in ipairs(rays) do
                ray.texture:ClearAllPoints()
                ray.texture:SetPoint("BOTTOM", self, "TOPLEFT", width * ray.position, -2)
            end
        end
        if lastRed ~= red or lastGreen ~= green or lastBlue ~= blue then
            lastRed, lastGreen, lastBlue = red, green, blue
            halo:SetGradient("VERTICAL", CreateColor(red, green, blue, .17), CreateColor(red, green, blue, 0))
        end
        halo:SetShown(showHalo)
        if not active then
            active = true
            for _, ray in ipairs(rays) do ray.texture:Show() end
            if self:IsVisible() then play() end
        end
    end
end
ui.text(chanceTrack, 0, 10, 60, 14, 10, "0 %", ui.muted)
local fullChance = ui.text(chanceTrack, 320, 10, 61, 14, 10, "100 %", ui.muted)
fullChance:SetJustifyH("RIGHT")
local pulseTime = 0
local function pulseChance(_, elapsed)
    pulseTime = (pulseTime + elapsed) % 3
    local pulse = .5 - .5 * math.cos(pulseTime * 2 * math.pi / 3)
    for _, glow in ipairs(oddsGlow) do glow:SetAlpha(.10 + .08 * pulse) end
    for _, glow in ipairs(chanceGlow) do glow:SetAlpha(.55 + .25 * pulse) end
    odds:SetTextColor(1, .79 + .07 * pulse, .36 + .13 * pulse)
end
local function setChanceGlow(enabled)
    for _, glow in ipairs(oddsGlow) do glow:SetText(odds:GetText()); glow:SetShown(enabled) end
    for _, glow in ipairs(chanceGlow) do glow:SetShown(enabled) end
    oddsArea:SetScript("OnUpdate", enabled and pulseChance or nil)
    pulseTime = 0
    if enabled then pulseChance(nil, 0) end
end
local planButton = ui.action(card, 448, 422, 220, 38, "В план", nil, function()
    atlas.togglePlan(selected, atlas.activePlanID())
    atlas.refreshDetails()
end)
planButton:HookScript("OnEnter", function(self)
    local activeID = atlas.activePlanID()
    for _, profile in ipairs(atlas.planProfiles()) do
        if profile.id == activeID then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L("Текущий план: %s", profile.name), 1, 1, 1, 1, true)
            GameTooltip:Show()
            return
        end
    end
end)
local function hidePlanButtonTooltip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
planButton:HookScript("OnLeave", hidePlanButtonTooltip)
planButton:HookScript("OnHide", hidePlanButtonTooltip)

local cardDetails = atlas.cardDetails(card, setFooter)
local collectedState = atlas.collectedState(card)
local difficultyBadge = atlas.difficultyBadge(card)

-- Keep each renderer below the client's Lua 5.1 upvalue limit. The browser
-- runtime accepts larger closures, so it cannot enforce this client constraint.
local function refreshHeader(collected)
    collectedState:SetShown(collected)
    if collected then collectedState:update(selected, shared ~= nil) end
    local expansion = selected.expansion ~= "Classic" and selected.expansion or nil
    headerArt:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Headers\\" .. (expansion or "Azeroth") .. ".tga")
    expansionLogo:SetShown(expansion ~= nil)
    if expansion then expansionLogo:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Expansions\\" .. expansion .. ".tga") end
    titleArea:SetWidth(expansion and 462 or 668)
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", titleArea, "TOPLEFT", 0, 0)
    title:SetWidth(titleArea:GetWidth())
    local classID = atlas.mountClassRequirements and atlas.mountClassRequirements[selected.id]
    local classInfo = classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(classID)
    local className = classInfo and classInfo.className or (classID and GetClassInfo and GetClassInfo(classID))
    title:SetHeight(collected and 65 or className and 91 or 100)
    title:SetText(atlas.displayName(selected.name))
    titleArea.classRequirement:SetText(className and L("Классовый маунт · %s", className) or "")
    titleArea.classRequirement:SetShown(className ~= nil)
    titleArea.refreshModelPreview()
    local _, description = C_MountJournal.GetMountInfoExtraByID(selected.id)
    lore:SetText(description or "")
    local included = not shared and atlas.isPlanned(selected, atlas.activePlanID())
    local canPlan = included or (not selected.unavailable and not collected)
    planButton:SetShown(not shared and not collected)
    planButton.caption:SetText(included and "Убрать из плана" or "+ В план")
    planButton:SetEnabled(canPlan)
    planButton:SetAlpha(canPlan and 1 or .45)
    planButton:setActive(canPlan and not included)
end

local function refreshSources(collected)
    local official = selected.journalOnly == true
    if vendorMount ~= selected then vendorIndex, vendorMount = 1, selected end
    sourceChoices = buildSourceChoices(selected)
    vendorIndex = math.max(1, math.min(vendorIndex, #sourceChoices))
    local choice = currentChoice()
    local vendor = currentVendor()
    local view = currentSource()
    if not vendor and atlas.resolveSourceInstance then atlas.resolveSourceInstance(view) end
    if not vendor and atlas.resolveSourceEncounter then atlas.resolveSourceEncounter(view) end
    local hasChoices = #sourceChoices > 1
    local sourcePanels = not selected.availability and not (choice and choice.compact) and (vendor ~= nil or (choice and choice.separated)
        or not official or selected.hasSourcePanels == true)
    difficultyBadge:update(view, sourcePanels and card or cardDetails.sourceFrame,
        sourcePanels and "TOPLEFT" or "TOPRIGHT", sourcePanels and 658 or -10, sourcePanels and -190 or -7)
    if selected.availability then difficultyBadge:Hide(); view.difficultyBadgeVisible = false end
    local points = locations()
    local point = location(points)
    -- Only curated source locations participate in loot and lockout rules.
    local loc = selected.locations and point
    local pointPager = placeArea:updateNavigation(sourcePanels and not vendor and point ~= nil,
        point, #points, view.difficultyBadgeVisible)
    local splitPagers = pointPager and hasChoices
    local badgeInset = view.difficultyBadgeVisible and 52 or 0
    sourceButton.pagerInset = splitPagers and 128 or 0
    placeLabel:SetWidth(math.min(180, 297 - badgeInset - (pointPager and 86 or hasChoices and 127 or 0)))
    for _, texture in ipairs(sourcePanel) do texture:SetShown(sourcePanels) end
    for _, texture in ipairs(placePanel) do texture:SetShown(sourcePanels) end
    local kind = (selected.quest or selected.kind == "Квест" or view.sourceKind == "Квест") and "Quest"
        or ((loc or view.sourceKind == "Рарка") and "Rare" or (view.sourceKind == "Добыча" and "Loot" or "Boss"))
    setFieldIcon(sourceIcon, vendor and "Vendor" or kind, 12, 189)
    sourceIcon:SetShown(sourcePanels)
    sourceType:SetShown(sourcePanels)
    sourceType:SetText(vendor and "Источник · Торговец" or selected.quest and "Квест · предмет с рарки"
        or (loc and "Источник · Рарка" or L("Источник · %s", L(view.sourceKind or "Босс"))))
    local progress = not shared and not vendor and atlas.planOpportunityProgress and atlas.planOpportunityProgress(selected, UnitGUID("player"))
    local multipleSources = progress and progress.totalAttempts > 1
    if progress and not multipleSources then
        for _, entry in ipairs(progress.entries or {}) do
            if #entry.npcs > 1 then multipleSources = true; break end
        end
    end
    local showProgress = sourcePanels and not collected and multipleSources == true and progress.totalAttempts > 0
    sourceProgress.progress = showProgress and progress or nil
    sourceProgress:SetShown(showProgress == true)
    sourceType:SetWidth(showProgress and 162 or 220)
    if showProgress then
        if selected.quest then sourceType:SetText(L("Источник · %s", L("Квест"))) end
        sourceProgress.label:SetText(progress.completedAttempts .. " / " .. progress.totalAttempts)
        sourceProgress.label:SetTextColor(unpack(progress.completedAttempts > 0 and ui.mint or ui.muted))
    end
    local link = not vendor and view.journalEncounter
    sourceButton:SetShown(sourcePanels)
    placeArea:SetShown(sourcePanels)
    placeLabel:SetShown(sourcePanels)
    placeIcon:SetShown(sourcePanels)
    source:SetText((vendor and groupName(vendor) or atlas.displayName(point and point.boss or view.boss)) .. (link and "  ›" or ""))
    refreshBossCheck(view, not shared and sourcePanels and not vendor, vendor or link, loc, progress)
    place:SetText(atlas.displayName(atlas.placeWithoutDifficulty(view, vendor and (vendor.place or "—") or (point and point.place or view.place))))
    place:SetTextColor(unpack(placeLink() and ui.gold or ui.paper))
    local placeKind = not vendor and (loc and "Открытый мир" or view.sourcePlaceKind
        or (selected.isRaid and "Рейд")
        or ((selected.kind == "Рейд" or selected.kind == "Подземелье") and selected.kind))
    placeLabel:SetText(placeKind and L("Место · %s", L(placeKind)) or "Место")
    setFieldIcon(placeIcon, placeKind == "Рейд" and "Raid" or placeKind == "Подземелье" and "Dungeon" or "Place", 322, 189)
    cardDetails.sourceChoiceCount = #sourceChoices
    cardDetails.shared = shared ~= nil
    local item = cardDetails:update(selected, loc, vendor, choice and view or nil, points)
    detail:SetText(not vendor and not (choice and (choice.verifiedDrop or choice.compact))
        and not (cardDetails.item and cardDetails.item.name) and L(selected.note) or "")
    local many = hasChoices or (not sourcePanels and not vendor and selected.locations and #points > 1)
    local pagerX, pagerY = splitPagers and 159 or 530 - badgeInset, splitPagers and 213 or 186
    if sourcePager.layoutX ~= pagerX or sourcePager.layoutY ~= pagerY then
        sourcePager.layoutX, sourcePager.layoutY = pagerX, pagerY
        sourcePager:ClearAllPoints()
        ui.place(sourcePager, card, pagerX, pagerY, 127, 21)
    end
    sourcePager:SetShown(many)
    prev:SetShown(many)
    following:SetShown(many)
    counter:SetText(many and ((hasChoices and vendorIndex or locationIndex) .. " / " .. (hasChoices and #sourceChoices or #points)) or "")
    return vendor, view, official, item
end

local function refreshChance(collected, vendor, view, official, item)
    local perAttempt, cumulative, attempts
    if not shared then perAttempt, cumulative, attempts = atlas.dropProbability(selected) end
    displayedReward = atlas.guaranteedRewards and atlas.guaranteedRewards[selected.id]
    if displayedReward then perAttempt, cumulative, attempts = 1, nil, nil end
    -- Before farming starts, show the chance of one drop instead of an empty
    -- historical probability. Never add a synthetic attempt to the counter.
    if attempts == 0 then cumulative, attempts = nil, nil end
    displayedAttempts = attempts
    local probability = cumulative or perAttempt
    displayedProbability = probability
    local guaranteed = perAttempt == 1 and (cumulative == nil or cumulative == 1)
    odds:SetText(probabilityText(probability, guaranteed))
    oddsLabel:SetText(displayedReward and "Шанс выпадения"
        or cumulative ~= nil and "Вероятность за все попытки" or selected.oddsLabel
        or (item and item.basis == "open" and "Шанс при открытии")
        or (selected.quest and "Шанс предмета") or "Шанс выпадения")
    baseOdds:SetText(displayedReward and "При выполнении условий"
        or L("За одну попытку: %s", probabilityText(perAttempt, perAttempt == 1)))
    odds:SetTextColor(unpack(ui.muted))
    for _, tier in ipairs(ui.chances) do
        if probability and probability * 100 <= tier.limit then odds:SetTextColor(unpack(tier.color)); break end
    end
    local trackingCompatible = view.trackingCompatible ~= false
    local chanceEligible = not atlas.rewardChanceEligible or atlas.rewardChanceEligible(selected, vendor ~= nil)
    local sharedRaidLoot = atlas.raidLootReward and atlas.raidLootReward(selected)
    local rewardProgress = not shared and atlas.rewardAttemptProgress and atlas.rewardAttemptProgress(selected)
    local definitions = atlas.attemptStages and atlas.attemptStages[selected.id]
    local reward = definitions and definitions.reward
    local estimate = not shared and reward and reward.rarityEncounterEstimate and atlas.kills(selected)
    local showChance = trackingCompatible and not selected.availability and not collected and not vendor and not sharedRaidLoot
        and probability ~= nil and (displayedReward ~= nil or chanceEligible)
    for _, texture in ipairs(chancePanel) do texture:SetShown(showChance) end
    local showKills = trackingCompatible and chanceEligible and not displayedReward and not collected and not vendor
        and (type(estimate) == "number" or rewardProgress ~= nil or not official or atlas.killStatistics[selected.id] ~= nil)
    for _, texture in ipairs(killsPanel) do texture:SetShown(showKills) end
    baseOdds:SetShown(showChance and (cumulative ~= nil or displayedReward ~= nil))
    chanceTrack:SetShown(showChance and probability ~= nil)
    chanceFill:SetShown(probability ~= nil and probability > 0)
    local fillWidth
    if probability then
        local fraction = math.max(0, math.min(guaranteed and 1 or .9999, probability))
        fillWidth = 381 * fraction
        chanceFill:SetWidth(math.max(.01, fillWidth))
        chanceMarker:ClearAllPoints()
        chanceMarker:SetPoint("TOPLEFT", chanceTrack, "TOPLEFT", math.min(379, fillWidth), 0)
        chanceFill:SetVertexColor(odds:GetTextColor())
    end
    chanceTrack:setRays(showChance and probability > .60 and fillWidth, not guaranteed, odds:GetTextColor())
    setChanceGlow(showChance and guaranteed)
    oddsArea:SetShown(showChance)
    oddsLabel:SetShown(showChance)
    oddsIcon:SetShown(showChance)
    kills:SetShown(showKills)
    killsHelp:SetShown(showKills)
    attemptsLabel:SetShown(showKills)
    attemptsIcon:SetShown(showKills)
    killsHelp.encounterEstimate = estimate and reward.condition or nil
    killsHelp.localBossCounter = not rewardProgress and not selected.npcs and not atlas.usesKillAPI(selected)
    attemptsLabel:SetText(estimate and "Rarity" or rewardProgress and "Попытки:" or selected.npcs and "Попыток с добычей"
        or killsHelp.localBossCounter and "Учтено убийств" or "Убийств босса")
    kills:SetText(tostring(estimate or rewardProgress and rewardProgress.attempts or (not shared and atlas.kills(selected)) or "—"))
end

local function viewedCollection()
    if shared then return shared end
    return atlas.collection
end

function atlas.refreshDetails(cardOnly)
    if cardOnly ~= true then
        if atlas.queueExpeditionStatsRefresh then atlas.queueExpeditionStatsRefresh() end
        if atlas.queuePlanBrokerStatsRefresh then atlas.queuePlanBrokerStatsRefresh() end
    end
    if not frame:IsShown() then return end
    if planner and planner:IsShown() then planner:update(); return end
    if not page:IsShown() then return end
    local waypoint = placeArea.waypoint
    local showingWaypoint = GameTooltip:IsShown() and GameTooltip:IsOwned(waypoint)
    catalog:redraw()
    if not selected then card:Hide(); return end
    card:Show()
    local collection = viewedCollection()
    local collected = collection and collection.byID[selected.id] == true
    refreshHeader(collected)
    refreshChance(collected, refreshSources(collected))
    if showingWaypoint and waypoint:IsVisible() and waypoint:IsMouseOver() then waypoint:refreshTooltip() end
    if GameTooltip:IsShown() then
        local owner = GameTooltip:GetOwner()
        if (owner == sourceButton or owner == sourceProgress or owner == placeArea
            or owner == oddsArea or owner == chanceTrack or owner == killsHelp) and owner:IsVisible() then
            owner:GetScript("OnEnter")(owner)
        end
    end
end

local function selectMount(mount, queryChanged)
    if selected ~= mount or queryChanged then
        GameTooltip:Hide()
        locationIndex = 1
        if searchQuery.key ~= "" and mount and mount.locations then
            for i, loc in ipairs(atlas.mountLocations(mount)) do
                if atlas.matchesSearch(atlas.searchKey(loc.boss .. " " .. loc.place), searchQuery) then
                    locationIndex = i
                    break
                end
            end
        end
        setFooter()
    end
    selected = mount
    atlas.refreshDetails(true)
end

function catalog:onClick(mount)
    if IsShiftKeyDown() then atlas.linkMount(mount)
    else
        selectMount(mount)
    end
end
function catalog:render(row, mount)
    local base = ui.panel
    local background = base
    local quality = ui.qualityColors[atlas.mountQuality[mount.id]]
    row.icon:SetTexture(mount.icon or 134400)
    row.iconBorder:SetColorTexture(unpack(quality or ui.rule))
    if quality then
        background = { base[1]*.90 + quality[1]*.10, base[2]*.90 + quality[2]*.10, base[3]*.90 + quality[3]*.10 }
        row.name:SetTextColor(.38 + quality[1]*.62, .38 + quality[2]*.62, .38 + quality[3]*.62)
    else
        row.name:SetTextColor(unpack(ui.paper))
    end
    if mount == selected then background = { .165, .137, .247 } end
    for _, texture in ipairs(row.bg) do texture:SetVertexColor(unpack(background)) end
    local collection = viewedCollection()
    local owned = collection and collection.byID[mount.id] == true
    local planned = not shared and not owned and atlas.isPlanned(mount, atlas.activePlanID())
    row.bookmark:SetShown(owned)
    row.tracked:SetShown(planned)
    row.name:SetWidth((owned or planned) and 183 or 203)
    local killed = not shared and atlas.isKilled(mount)
    local status = owned and (killed and "В коллекции  ·  Босс убит" or "В коллекции") or (killed and "Босс убит" or "")
    row.status:SetText(status)
    row.status:SetTextColor(unpack(owned and ui.mint or ui.muted))
    row.name:SetHeight(status == "" and 41 or 24)
    row.name:SetMaxLines(status == "" and 2 or 1)
    row.line:SetShown(mount == selected)
    for _, texture in ipairs(row.selection) do texture:SetShown(mount == selected) end
    row.name:SetText(atlas.displayName(mount.name))
end
for _, row in ipairs(catalog.rows) do
    row.bg = ui.surface(row, 0, 0, 264, 44, false, "RoundedFill")
    row:GetHighlightTexture():SetAlpha(0)
    local hover = ui.surface(row, 0, 0, 264, 44, false, "RoundedFill")
    for _, texture in ipairs(hover) do
        texture:SetDrawLayer("HIGHLIGHT")
        texture:SetAlpha(0)
    end
    row:HookScript("OnEnter", function() for _, texture in ipairs(hover) do texture:SetAlpha(.06) end end)
    local function clearRowHover() for _, texture in ipairs(hover) do texture:SetAlpha(0) end end
    row:HookScript("OnLeave", clearRowHover)
    row:HookScript("OnHide", clearRowHover)
    row.selection = ui.surface(row, 0, 0, 264, 44, true)
    for _, texture in ipairs(row.selection) do
        texture:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\OrnateOutline.tga")
    end
    row.line = ui.fill(row, 1, 7, 2, 30, ui.gold)
    row.line:SetDrawLayer("BORDER")
    row.iconBorder = ui.fill(row, 10, 6, 32, 32, ui.rule)
    row.iconBorder:SetDrawLayer("ARTWORK", -1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    ui.place(row.icon, row, 11, 7, 30, 30)
    row.icon:SetTexCoord(.07, .93, .07, .93)
    row.name = ui.text(row, 50, 2, 203, 40, 15, "")
    row.name.atlasGameText = true
    row.bookmark = row:CreateTexture(nil, "ARTWORK")
    ui.place(row.bookmark, row, 240, 0, 18, 22)
    row.bookmark:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\Bookmark.tga")
    row.tracked = ui.icon(row, 239, 12, 19, "Route")
    row.tracked:SetVertexColor(unpack(ui.gold))
    row.tracked:Hide()
    row.status = ui.text(row, 50, 25, 203, 17, 11, "", ui.muted)
    bindHover(row, function() return row.item end)
end

local lastKey, lastFilter, lastSourceFilter, lastQuestOnly, lastFrequency, lastExpansion
local lastCollection
refresh = function()
    searchQuery = atlas.searchQuery(search:GetText())
    local key = searchQuery.key .. "\n" .. (searchQuery.layout or "")
    hint:SetShown(search:GetText() == "" and not search:HasFocus())
    clear:SetShown(search:GetText() ~= "" or expansionFilter ~= nil)
    hint:SetText(expansionFilter and expansionFilter.name or "Имя, босс или место")
    local matches, keep = {}, false
    local collection = viewedCollection()
    if shared or collection ~= lastCollection then
        lastCollection = collection
        local collected, total = 0, 0
        if shared then
            total = #atlas.mounts
            collected = shared.collected or 0
        elseif collection then
            collected, total = collection.collected, collection.total
        end
        collectionBadge.count:SetText(collection and (not shared or not shared.status)
            and (collected .. " |cff9eaeb0/ " .. total .. "|r") or "—")
        collectionBadge.fill:SetShown(collected > 0 and total > 0)
        collectionBadge.fill:SetWidth(math.max(.01, 110 * (total > 0 and math.min(1, collected / total) or 0)))
    end
    for i, button in ipairs(filters) do button:setActive(i == activeFilter) end
    collectionStatus:SetText(shared and shared.status or "")
    collectionStatus:SetShown(shared ~= nil and shared.status ~= nil)
    questFilters[1]:setActive(not questOnly and not frequency and not sourceFilter)
    questFilters[2]:setActive(questOnly)
    questFilters[3]:setActive(sourceFilter == "rare")
    questFilters[4]:setActive(sourceFilter == "raid")
    questFilters[5]:setActive(frequency == "daily")
    questFilters[6]:setActive(frequency == "weekly")
    for _, mount in ipairs(atlas.mounts) do
        if (not sourceFilter or (sourceFilter == "rare" and mount.locations)
            or (sourceFilter == "raid" and (mount.isRaid or mount.kind == "Рейд")))
            and atlas.matchesSearch(mount.key, searchQuery)
            and (not expansionFilter or atlas.collectionCategory(mount) == expansionFilter.id)
            and (not questOnly or mount.hasQuest)
            and (not frequency or mount.questFrequency == frequency or atlas.lootFrequency(mount) == frequency)
            and (activeFilter == 1 or (collection and collection.byID[mount.id] == (activeFilter == 2))) then
            matches[#matches + 1] = mount
            if selected == mount then keep = true end
        end
    end
    local queryChanged = lastKey ~= key
    if queryChanged or lastFilter ~= activeFilter or lastSourceFilter ~= sourceFilter or lastQuestOnly ~= questOnly or lastFrequency ~= frequency or lastExpansion ~= expansionFilter then catalog:resetScroll() end
    lastExpansion = expansionFilter
    lastKey, lastFilter, lastSourceFilter, lastQuestOnly, lastFrequency = key, activeFilter, sourceFilter, questOnly, frequency
    catalog.items = matches
    local n = #matches
    showEmpty(n == 0 and not collectionStatus:IsShown())
    found:SetText(collectionStatus:IsShown() and "" or tostring(n))
    selectMount(keep and selected or matches[1], queryChanged)
end

local function openCatalogMount(mount)
    if shared then returnToCollection() end
    showPage(false)
    activeFilter = 1
    questOnly, frequency = false, nil
    sourceFilter = nil
    expansionFilter = nil
    search:SetText("")
    refresh()
    if mount then
        selectMount(mount)
        catalog:reveal(mount)
    else search:SetFocus() end
end

function atlas.openMountCard(mountID)
    if type(mountID) ~= "number" then return false end
    if frame:IsShown() then atlas.syncJournal()
    else frame:Show() end
    for _, mount in ipairs(atlas.mounts) do
        if mount.id == mountID then
            openCatalogMount(mount)
            return true
        end
    end
    return false
end

planner = atlas.makePlanner(frame, openCatalogMount, function(expansion)
    expansionFilter = expansion
    activeFilter, questOnly, frequency, sourceFilter = expansion.event and 1 or 3, false, nil, nil
    search:SetText("")
    refresh()
    showPage(false)
end)
showPage = function(plan)
    if shared then plan = false end
    if settings then settings:Hide() end
    settingsTab:setActive(false)
    search:ClearFocus()
    page:SetShown(not plan)
    for _, shell in ipairs(catalogShells) do
        for _, texture in ipairs(shell) do texture:SetShown(not plan) end
    end
    for _, texture in ipairs(plannerShell) do texture:SetShown(plan) end
    setFooter()
    planner:SetShown(plan)
    planTab:setActive(plan)
    catalogTab:setActive(not plan)
    if plan then atlas.refreshPlanSnapshot() end
    if viewedCollection() ~= lastCollection then refresh()
    elseif plan then planner:update()
    else atlas.refreshDetails() end
    if plan then RequestRaidInfo() end
end
search:SetScript("OnTextChanged", refresh)
frame:RegisterEvent("NEW_MOUNT_ADDED")
frame:RegisterEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
local function fitWindow()
    frame:SetScale(math.min(1, (UIParent:GetWidth() - 24) / w, (UIParent:GetHeight() - 24) / h))
end
local function refreshJournal()
    atlas.syncJournal()
    if planner:IsShown() then atlas.refreshPlanSnapshot() end
    refresh()
end
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:SetScript("OnEvent", function(_, event)
    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then fitWindow()
    elseif frame:IsShown() then refreshJournal() end
end)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
frame:SetScript("OnShow", function()
    fitWindow()
    refreshJournal()
end)
showPage(false)
settings = atlas.makeSettings(frame)
local previousPageWasPlanner = false
function atlas.toggleSettings()
    if shared then return end
    local closeSettings = frame:IsShown() and settings:IsShown()
    frame:Show()
    if closeSettings then showPage(previousPageWasPlanner); return end
    if not settings:IsShown() then previousPageWasPlanner = planner:IsShown() end
    search:ClearFocus()
    page:Hide()
    planner:Hide()
    for _, shell in ipairs(catalogShells) do
        for _, texture in ipairs(shell) do texture:Hide() end
    end
    for _, texture in ipairs(plannerShell) do texture:Hide() end
    catalogTab:setActive(false)
    planTab:setActive(false)
    settingsTab:setActive(true)
    settings:Show()
    setFooter()
end
local ownCatalog
local function setCatalogSearch(value)
    search:SetScript("OnTextChanged", nil)
    search:SetText(value)
    search:SetScript("OnTextChanged", refresh)
end

local function setSharedControls(show)
    planTab:SetShown(not show)
    settingsTab:SetShown(not show)
    returnTab:SetShown(show)
    filters[1]:SetShown(not show)
    filters[3]:SetShown(not show)
    filters[2]:ClearAllPoints()
    ui.place(filters[2], page, show and 26 or 117, 51, 85, 28)
    collectionBadge:EnableMouse(not show)
    guide:SetText(show and L("Коллекция: %s", shared.owner:match("^[^-]+") or shared.owner)
        or "ПОЛЕВОЙ СПРАВОЧНИК   /   АЗЕРОТ")
end

returnToCollection = function()
    if not shared then return end
    GameTooltip:Hide()
    shared = nil
    setSharedControls(false)
    activeFilter, questOnly, frequency = ownCatalog.activeFilter, ownCatalog.questOnly, ownCatalog.frequency
    sourceFilter, expansionFilter, selected = ownCatalog.sourceFilter, ownCatalog.expansionFilter, ownCatalog.selected
    setCatalogSearch(ownCatalog.search)
    local previous = ownCatalog
    ownCatalog = nil
    showPage(false)
    if selected == previous.selected then
        locationIndex, vendorIndex, vendorMount = previous.locationIndex, previous.vendorIndex, selected
    end
    catalog.offset = previous.offset
    atlas.refreshDetails(true)
end

function atlas.showSharedCatalog(owner)
    if not shared then
        ownCatalog = {
            activeFilter = activeFilter, questOnly = questOnly, frequency = frequency,
            sourceFilter = sourceFilter, expansionFilter = expansionFilter,
            search = search:GetText(), selected = selected, offset = catalog.offset,
            locationIndex = locationIndex, vendorIndex = vendorIndex,
        }
    end
    GameTooltip:Hide()
    shared = { owner = owner, byID = {}, status = "Загрузка коллекции…" }
    activeFilter, questOnly, frequency, sourceFilter, expansionFilter = 2, false, nil, nil, nil
    selected = nil
    catalog:resetScroll()
    setCatalogSearch("")
    setSharedControls(true)
    showPage(false)
    frame:Show()
    return shared
end

function atlas.finishSharedCatalog(request, snapshot)
    if shared ~= request then return end
    if snapshot then
        local collected = snapshot.count
        if collected == nil then
            collected = 0
            for _, owned in pairs(snapshot.collected) do
                if owned == true then collected = collected + 1 end
            end
        end
        shared.owner, shared.byID, shared.collected, shared.status = snapshot.owner, snapshot.collected, collected, nil
        setSharedControls(true)
    else
        shared.status = "Не удалось загрузить коллекцию"
    end
    refresh()
end

frame:HookScript("OnHide", returnToCollection)
refresh()
function atlas.toggleWindow() frame:SetShown(not frame:IsShown()) end
do
    local function handleSlash(message)
        local command = (message or ""):lower():match("^%s*(.-)%s*$")
        if command == "minimap" or command:match("^minimap%s+show$") then
            atlas.showMinimapButton()
        elseif command:match("^minimap%s+hide$") then
            atlas.hideMinimapButton()
        elseif command == "" then atlas.toggleWindow() end
    end
    for _, alias in ipairs({ "paw", "pawatlas" }) do
        atlas:RegisterChatCommand(alias, handleSlash)
    end
end
if UISpecialFrames then table.insert(UISpecialFrames, "MountAtlasWindow") end
