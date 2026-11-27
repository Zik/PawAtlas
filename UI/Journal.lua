local _, atlas = ...
local ui = atlas.ui
local L = atlas.L
local w, h = 1040, 596
local minimumWindowScale, maximumWindowScale = 75, 125
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
do
    atlas.windowMovementTransparencyMax = 80
    local fadeDuration, moving = .2, nil
    local startAlpha, targetAlpha, elapsed
    local hoverTicker, hovered

    local function transparency(value)
        if type(value) ~= "number" or value ~= value then return 50 end
        return math.max(0, math.min(atlas.windowMovementTransparencyMax, math.floor(value / 5 + .5) * 5))
    end

    function atlas.windowMovementSettings()
        local saved = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
        if type(saved) ~= "table" then return false, transparency() end
        return saved.windowMovementFade == true, transparency(saved.windowMovementTransparency)
    end

    local function updateAlpha(self, delta)
        elapsed = math.min(1, elapsed + delta / fadeDuration)
        self:SetAlpha(startAlpha + (targetAlpha - startAlpha) * elapsed)
        if elapsed == 1 then self:SetScript("OnUpdate", nil) end
    end

    local function stopWatchingHover()
        if hoverTicker then hoverTicker:Cancel() end
        hoverTicker, hovered = nil, nil
    end

    local function checkHover()
        if hovered ~= frame:IsMouseOver() then atlas.refreshWindowMovementAlpha() end
    end

    function atlas.refreshWindowMovementAlpha(instant)
        if not frame:IsShown() then return end
        if moving == nil then
            local speed = GetUnitSpeed and GetUnitSpeed("player")
            if not (issecretvalue and issecretvalue(speed)) and type(speed) == "number" then moving = speed > 0 end
        end
        local enabled, percent = atlas.windowMovementSettings()
        local alpha = 1
        if enabled and moving and percent > 0 then
            -- Check the whole window, including interactive children that receive their own mouse events.
            hovered = frame:IsMouseOver()
            if not hovered then alpha = 1 - percent / 100 end
            if not hoverTicker then hoverTicker = C_Timer.NewTicker(.08, checkHover) end
        else
            stopWatchingHover()
        end
        local current = frame:GetAlpha()
        if instant or current == alpha then
            frame:SetScript("OnUpdate", nil)
            if current ~= alpha then frame:SetAlpha(alpha) end
        elseif alpha ~= targetAlpha or not frame:GetScript("OnUpdate") then
            startAlpha, targetAlpha, elapsed = current, alpha, 0
            frame:SetScript("OnUpdate", updateAlpha)
        end
    end

    function atlas.setWindowMovementTransparency(value)
        if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
        if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
        MountAtlasAccountDB.settings.windowMovementTransparency = transparency(value)
        atlas.refreshWindowMovementAlpha()
    end

    local events = CreateFrame("Frame")
    events:RegisterEvent("PLAYER_STARTED_MOVING")
    events:RegisterEvent("PLAYER_STOPPED_MOVING")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then moving = nil
        else moving = event == "PLAYER_STARTED_MOVING" end
        atlas.refreshWindowMovementAlpha()
    end)
    frame:HookScript("OnShow", function() atlas.refreshWindowMovementAlpha(true) end)
    frame:HookScript("OnHide", function(self)
        stopWatchingHover()
        self:SetScript("OnUpdate", nil)
        self:SetAlpha(1)
    end)
end
ui.journalWindowBackground(frame)
ui.windowBorder(frame, w, h, .76)
local footerRules = {}
do
    local faded = CreateColor(.59, .46, .25, 0)
    local bronze = CreateColor(.59, .46, .25, .48)
    local middle = CreateColor(.37, .43, .44, .46)
    local stops = { { 16, faded }, { 186, bronze }, { w / 2, middle }, { w - 186, bronze }, { w - 16, faded } }
    local footer = ui.place(CreateFrame("Frame", nil, frame), frame, 0, 567, w, 29)
    -- Keep the rule above the page, card, and collection ribbon levels.
    footer:SetFrameLevel(frame:GetFrameLevel() + 4)
    for _, parent in ipairs({ frame, footer }) do
        for i = 2, #stops do
            local from, to = stops[i - 1], stops[i]
            local line = ui.fill(parent, from[1], parent == footer and 0 or 68, to[1] - from[1], 1, { 1, 1, 1 })
            line:SetDrawLayer("BORDER")
            line:SetGradient("HORIZONTAL", from[2], to[2])
            if parent == footer then footerRules[#footerRules + 1] = line end
        end
    end
end
ui.brandIcon(frame, 24, 15, 43)
local guide = ui.text(frame, 74, 8, 325, 16, 10, "ПОЛЕВОЙ СПРАВОЧНИК   /   АЗЕРОТ", ui.gold)
guide:SetMaxLines(1)
local shared
ui.text(frame, 74, 24, 310, 33, 26, "PawAtlas", ui.gold)
local collectionBadge = ui.place(CreateFrame("Button", nil, frame), frame, 394, 4, 182, 62)
do
    ui.laurels(collectionBadge, 0, 2, 182, 58, 31)
    collectionBadge.count = ui.text(collectionBadge, 12, 3, 158, 25, 20, "", ui.gold)
    collectionBadge.count:SetJustifyH("CENTER")
    collectionBadge.count:SetMaxLines(1)
    local label = ui.text(collectionBadge, 12, 28, 158, 15, 10, "В коллекции", ui.muted)
    label:SetJustifyH("CENTER")
    local track = ui.fill(collectionBadge, 36, 27, 110, 2, ui.rule)
    track:SetDrawLayer("ARTWORK")
    track:SetAlpha(.55)
    collectionBadge.fill = ui.fill(collectionBadge, 36, 27, 1, 2, ui.gold)
    collectionBadge.fill:SetDrawLayer("ARTWORK", 1)
    collectionBadge.fill:SetGradient("HORIZONTAL", CreateColor(.55, .42, .22), CreateColor(.92, .76, .44))
    collectionBadge:RegisterForClicks("LeftButtonUp")
    collectionBadge:SetScript("OnClick", function()
        if atlas.collection and not shared and IsShiftKeyDown() then atlas.shareCollectionLink() end
    end)
    collectionBadge:SetScript("OnEnter", function(self)
        if shared or not atlas.collection then return end
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
do
    local war = ui.place(CreateFrame("Button", nil, collectionBadge), collectionBadge, 65, 40, 19, 19)
    local chromie = ui.place(CreateFrame("Button", nil, collectionBadge), collectionBadge, 97, 40, 19, 19)
    war:RegisterForClicks("LeftButtonUp")
    local ring = war:CreateTexture(nil, "BACKGROUND")
    ring:SetAllPoints(war)
    local swords = war:CreateTexture(nil, "ARTWORK")
    ui.place(swords, war, 1, 1, 17, 17)
    local hourglass = chromie:CreateTexture(nil, "ARTWORK")
    ui.place(hourglass, chromie, 2, 2, 15, 15)
    hourglass:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
    local modes = {}
    local function stateLine(active)
        local text = active == nil and L("Нет данных") or active and (ENABLED or L("Включено")) or (DISABLED or L("Выключено"))
        local color = active == true and ui.gold or ui.muted
        ui.tooltipLine(text, color[1], color[2], color[3], true)
    end
    function war:GetWarModeDesired()
        return C_PvP.IsWarModeDesired()
    end
    local function warTooltip(self)
        if not WarmodeButtonMixin and C_AddOns and C_AddOns.LoadAddOn then
            C_AddOns.LoadAddOn("Blizzard_PlayerSpells")
        end
        if WarmodeButtonMixin then WarmodeButtonMixin.OnEnter(self) end
    end
    local function chromieTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(CHROMIE_TIME or L("Время Хроми"))
        stateLine(modes.chromieTimeActive)
        if modes.chromieTimeActive and modes.chromieTimeName then ui.tooltipLine(modes.chromieTimeName, 1, 1, 1, true) end
        GameTooltip:Show()
    end
    local function hide(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
    war:SetScript("OnEnter", warTooltip)
    chromie:SetScript("OnEnter", chromieTooltip)
    for _, button in ipairs({ war, chromie }) do
        button:SetScript("OnLeave", hide)
        button:SetScript("OnHide", hide)
    end
    function atlas.refreshCharacterModes()
        modes = atlas.currentCharacterModes()
        local active = modes.warModeDesired == true or (modes.warModeDesired == nil and modes.warModeActive == true)
        ring:SetAtlas(active and "talents-warmode-ring" or "talents-warmode-ring-disabled", false)
        swords:SetAtlas(active and "pvptalents-warmode-swords" or "pvptalents-warmode-swords-disabled", false)
        swords:SetVertexColor(unpack(active and ui.gold or ui.muted))
        hourglass:SetDesaturated(modes.chromieTimeActive ~= true)
        hourglass:SetVertexColor(unpack(modes.chromieTimeActive == true and ui.gold or ui.muted))
        if GameTooltip:IsShown() and GameTooltip:IsOwned(war) then warTooltip(war)
        elseif GameTooltip:IsShown() and GameTooltip:IsOwned(chromie) then chromieTooltip(chromie) end
    end
    war:SetScript("OnClick", function()
        atlas.toggleWarMode()
        atlas.refreshCharacterModes()
        if war:IsMouseOver() then warTooltip(war) end
    end)
    frame:HookScript("OnShow", atlas.refreshCharacterModes)
    atlas.refreshCharacterModes()
end
local commandHint = ui.text(frame, 25, 570, 350, 19, 11, "PAWATLAS     /     Открыть в игре: /paw", ui.muted)
commandHint:SetWordWrap(false)
local feedback = ui.text(frame, 530, 570, 481, 19, 11, "", ui.muted)
feedback:SetWordWrap(false)
feedback:SetJustifyH("RIGHT")

local page = ui.place(CreateFrame("Frame", nil, frame), frame, 0, 79, w, 488)
do
    local faint = CreateColor(.59, .46, .25, 0)
    local bronze = CreateColor(.59, .46, .25, .48)
    local middle = CreateColor(.37, .43, .44, .46)
    local stops = { { 9, faint }, { 78, bronze }, { 237, middle }, { 399, bronze }, { 469, faint } }
    for i = 2, #stops do
        local top, bottom = stops[i - 1], stops[i]
        local line = ui.fill(page, 311, top[1], 1, bottom[1] - top[1], { 1, 1, 1 })
        line:SetGradient("VERTICAL", bottom[2], top[2])
    end
end
local function setFooter(message)
    feedback:SetText(ui.unavailableText(message) or (page:IsShown() and "Ctrl + ЛКМ — посмотреть маунта" or ""))
    feedback:SetTextColor(unpack(message and ui.gold or ui.muted))
end
local selected, planner, settings
local locationIndex = 1
local refresh, showPage, returnToCollection
local navUnderline = {}
local catalogTab = ui.tab(frame, 613, 10, 155, 46, "Каталог", "Book", function() showPage(false) end, nil, true, navUnderline)
local planTab = ui.tab(frame, 772, 10, 151, 46, "Планнер", "Route", function()
    if shared then returnToCollection() else showPage(true) end
end, nil, true, navUnderline)
local settingsTab = ui.tab(frame, 937, 11, 48, 44, nil, "Settings", function() atlas.toggleSettings() end)
settingsTab.divider = ui.fill(frame, 930, 23, 1, 22, ui.rule)
ui.fill(frame, 989, 23, 1, 22, ui.rule)
ui.tab(frame, 993, 11, 34, 44, nil, "Close", function() frame:Hide() end)


local sourceFilter, expansionFilter
local found = ui.text(page, 258, 70, 33, 22, 12, "", ui.muted)
found:SetJustifyH("RIGHT")
found:SetWordWrap(false)
local catalog = ui.scrollingList(page, 26, 105, 272, 46, 8, true, 10)
catalog.loading = true
catalog.loadingLabel = ui.text(catalog, 8, 20, 248, 40, 15, "Загрузка коллекции…", ui.muted)
catalog.loadingLabel:SetJustifyH("CENTER")
local search = ui.place(CreateFrame("EditBox", "MountAtlasSearch", page), page, 50, 0, 215, 29)
local searchQuery = atlas.searchQuery("")
search:SetAutoFocus(false)
ui.setFont(search, 13)
search:SetTextColor(unpack(ui.paper))
search:SetTextInsets(4, 4, 0, 0)
local hint = ui.text(search, 4, 0, 193, 29, 13, "Имя, босс или место", ui.muted)
do
    local rim = page:CreateTexture(nil, "BACKGROUND")
    ui.place(rim, page, 26, 0, 265, 29)
    rim:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\PlannerButtons.tga")
    local loupe = ui.icon(page, 32, 6, 17, "Search")
    hint:SetAlpha(.9)
    local function updateFocus(focused)
        local top = focused and 33 or 1
        rim:SetTexCoord(244 / 512, 498 / 512, top / 128, (top + 28) / 128)
        loupe:SetVertexColor(unpack(focused and ui.gold or ui.muted))
        hint:SetShown(not focused and search:GetText() == "")
    end
    search:HookScript("OnEditFocusGained", function() updateFocus(true) end)
    search:HookScript("OnEditFocusLost", function() updateFocus(false) end)
    search:HookScript("OnHide", function(self) self:ClearFocus() end)
    updateFocus(false)
end
local clear = ui.place(CreateFrame("Button", nil, page), page, 264, 0, 26, 29)
clear:SetScript("OnClick", function() expansionFilter = nil; search:SetText(""); refresh(); search:SetFocus() end)
local clearIcon = ui.icon(clear, 6, 7, 15, "Close")
clearIcon:SetVertexColor(unpack(ui.muted))
clear:SetScript("OnEnter", function() clearIcon:SetVertexColor(unpack(ui.gold)) end)
clear:SetScript("OnLeave", function() clearIcon:SetVertexColor(unpack(ui.muted)) end)
local filters = {}
local activeFilter = 1
for _, entry in ipairs({ { "Не получены", 0, 83, 3 }, { "Получены", 91, 83, 2 }, { "Все", 182, 83, 1 },
    { "Есть у меня", 0, 129, 4 }, { "Нет у меня", 136, 129, 5 } }) do
    local filterID = entry[4]
    filters[filterID] = ui.action(page, 26 + entry[2], 36, entry[3], 24, entry[1], nil, function()
        activeFilter = shared and activeFilter == filterID and 1 or filterID
        refresh()
    end)
    ui.setFont(filters[filterID].caption, 11)
    filters[filterID].flatSkin:animateSelection()
    filters[filterID].caption:SetMaxLines(1)
    filters[filterID]:SetShown(filterID <= 3)
end

local sourceCategories = {
    { key = "loot", label = "Добыча", icon = "Loot" },
    { key = "fishing", label = "Рыбалка", icon = "Fishing" },
    { key = "profession", label = "Профессия", icon = "Profession" },
    { key = "quest", label = "Квест", icon = "Quest" },
    { key = "achievement", label = "Достижение", icon = "Achievement" },
    { key = "purchase", label = "Покупка", icon = "Vendor" },
    { key = "pvp", label = "PvP", icon = "Kills" },
    { key = "event", label = "Событие", icon = "Calendar" },
    { key = "promotion", label = "Акция / код", icon = "Promotion" },
    { key = "progress", label = "Награда за прогресс", icon = "Progress" },
}
local sourceMenu, sourceSubtype, frequency = {}, nil, nil
do
    local openMenu
    local function dropdown(x, width, label, menuWidth, alignRight)
        local menu = CreateFrame("Frame", nil, page)
        menu:SetWidth(menuWidth)
        menu:SetFrameLevel(page:GetFrameLevel() + 30)
        menu:EnableMouse(true)
        ui.dropdownSurface(menu)
        menu:Hide()
        local trigger = ui.action(page, x, 69, width, 25, label, nil, function() menu:SetShown(not menu:IsShown()) end)
        trigger.flatSkin:animateSelection()
        ui.setFont(trigger.caption, 12)
        ui.place(trigger.caption, trigger, 23, 0, width - 40, 25)
        trigger.caption:SetWordWrap(false)
        ui.dropdownArrow(trigger, width - 16, 8, 11)
        menu:SetPoint(alignRight and "TOPRIGHT" or "TOPLEFT", trigger, alignRight and "BOTTOMRIGHT" or "BOTTOMLEFT", 0, -5)
        menu:SetScript("OnShow", function(self)
            if openMenu and openMenu ~= self then openMenu:Hide() end
            openMenu = self
            self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        end)
        menu:SetScript("OnEvent", function(self)
            if not self:IsMouseOver() and not trigger:IsMouseOver() then self:Hide() end
        end)
        menu:SetScript("OnHide", function(self)
            self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
            if openMenu == self then openMenu = nil end
        end)
        page:HookScript("OnHide", function() menu:Hide() end)
        return menu, trigger
    end
    local menu, toggle = dropdown(26, 98, "Фильтры", 216)
    for i, knob in ipairs({ 6, 12, 8 }) do
        local y = 7 + (i - 1) * 5
        ui.fill(toggle, 8, y, 15, 1, ui.paper):SetDrawLayer("ARTWORK")
        ui.fill(toggle, 8 + knob, y - 1, 3, 3, ui.paper):SetDrawLayer("ARTWORK")
    end
    local y = 4
    local function optionCheck(button)
        ui.fill(button, 9, 4, 16, 16, ui.rule)
        ui.fill(button, 10, 5, 14, 14, ui.ink):SetDrawLayer("BORDER")
        return ui.check(button, 7, 1)
    end
    local function row(key, label, select)
        local button = ui.button(menu, 4, y, 208, 23, function()
            select(key)
            refresh()
        end)
        ui.text(button, 35, 0, 164, 23, 13, label)
        sourceMenu[key] = optionCheck(button)
        y = y + 23
    end
    local function separator()
        ui.fill(menu, 12, y + 1, 192, 1, ui.rule):SetAlpha(.65)
        y = y + 3
    end
    row("all", "Все", function() sourceSubtype, frequency, sourceFilter, expansionFilter = nil, nil, nil, nil end)
    separator()
    for _, category in ipairs(sourceCategories) do
        row(category.key, category.label, function(key) sourceFilter = sourceFilter ~= key and key or nil end)
    end
    separator()
    row("rare", "Рарки", function(key) sourceSubtype = sourceSubtype ~= key and key or nil end)
    row("raid", "Рейд", function(key) sourceSubtype = sourceSubtype ~= key and key or nil end)
    separator()
    row("daily", "Ежедневно", function(key) frequency = frequency ~= key and key or nil end)
    row("weekly", "Еженедельно", function(key) frequency = frequency ~= key and key or nil end)
    menu:SetHeight(y + 4)
    local filtered = false
    function sourceMenu:setFiltered(value)
        filtered = value
        toggle:setActive(filtered or menu:IsShown())
    end
    menu:HookScript("OnShow", function() toggle:setActive(true) end)
    menu:HookScript("OnHide", function() toggle:setActive(filtered) end)

    function catalog:sortMode()
        local settings = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.settings
        local mode = type(settings) == "table" and settings.catalogSort
        if mode == "collected" or mode == "name" or mode == "attemptChance" or mode == "dropChance" then return mode end
        return "missing"
    end
    local sortMenu, sortButton = dropdown(130, 125, "Сортировка", 210, true)
    for i, width in ipairs({14, 10, 6}) do
        ui.fill(sortButton, 9, 8 + (i - 1) * 4, width, 1, ui.paper):SetDrawLayer("ARTWORK")
    end
    local options = {
        { "missing", "Сначала неполученные" }, { "collected", "Сначала полученные" }, { "name", "По имени" },
        { "attemptChance", "По шансу за все попытки" }, { "dropChance", "По шансу выпадения" },
    }
    for i, option in ipairs(options) do
        local mode = option[1]
        local button = ui.button(sortMenu, 4, 4 + (i - 1) * 24, 202, 24, function()
            sortMenu:Hide()
            if catalog:sortMode() == mode then return end
            if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
            if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
            MountAtlasAccountDB.settings.catalogSort = mode
            refresh()
        end)
        ui.text(button, 35, 0, 164, 24, 13, option[2]):SetWordWrap(false)
        option.check = optionCheck(button)
    end
    sortMenu:SetHeight(8 + #options * 24)
    sortMenu:HookScript("OnShow", function()
        local mode = catalog:sortMode()
        for _, option in ipairs(options) do option.check:SetShown(option[1] == mode) end
        sortButton:setActive(true)
    end)
    sortMenu:HookScript("OnHide", function() sortButton:setActive(false) end)
end

local showEmpty = atlas.emptyCatalog(page, function()
    activeFilter, sourceSubtype, frequency, sourceFilter, expansionFilter = 1, nil, nil, nil, nil
    search:SetText("")
    refresh()
end)
local collectionStatus = ui.text(page, 328, 184, 680, 56, 17, "", ui.muted)
collectionStatus:SetJustifyH("CENTER")
collectionStatus:Hide()
local card = ui.place(CreateFrame("Frame", nil, page), page, 328, 8, 680, 454)
local cardTabs = { unpack(sourceCategories) }
cardTabs[#cardTabs + 1] = { key = "garrison", label = "Гарнизон", icon = "Loot" }
cardTabs[#cardTabs + 1] = { key = "gift", label = ITEM or "Предмет маунта", icon = "Book" }
cardTabs[#cardTabs + 1] = { key = "islandExpedition", label = "Экспедиции", icon = "Loot" }
cardTabs[#cardTabs + 1] = { key = "islandSalvage", label = "Сумки", icon = "Loot" }
cardTabs[#cardTabs + 1] = { key = "history", label = "История", icon = "Book" }
cardTabs[#cardTabs + 1] = { key = "unknown", label = "Сведения", icon = "Book" }
do
    local top, width = 110, card:GetWidth()
    local panel = ui.sourceCardSurface(card, 0, top, width, 170)
    local strip = ui.fill(card, 6, top + 3, width - 11, 40, { 1, 1, 1 })
    strip:SetGradient("VERTICAL", CreateColor(.02, .04, .06, .24), CreateColor(.02, .04, .06, 0))
    strip:SetDrawLayer("BACKGROUND", 3)
    for _, y in ipairs({ 153, 191 }) do
        local line = ui.fill(card, 12, y, width - 24, 1, { .36, .45, .49, .52 })
        line:SetDrawLayer("BORDER")
        if y == 191 then cardTabs.rule = line end
    end
    function card:layoutSourcePanel(route, bottom)
        panel:setRoute(route)
        panel:setHeight(math.max(65, bottom - top))
    end
end
local headerArt = card:CreateTexture(nil, "BACKGROUND", nil, -1)
ui.place(headerArt, card, 0, -2, card:GetWidth(), 105)
headerArt:SetTexCoord(0, 1, .06, .532)
headerArt:SetAlpha(.2)
local headerMask = card:CreateMaskTexture()
headerMask:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\HeaderMask.tga", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
headerMask:SetAllPoints(headerArt)
headerArt:AddMaskTexture(headerMask)
local expansionLogo = card:CreateTexture(nil, "ARTWORK")
expansionLogo:SetAlpha(.85)
do
    local mountID
    local function reveal(amount)
        headerArt:SetAlpha(.2 * amount)
        expansionLogo:SetAlpha(.85 * amount)
    end
    function card:revealArtwork(id)
        if mountID == id then return end
        mountID = id
        if self:IsVisible() then
            ui.transition(self, .15, reveal)
        else
            ui.stopTransition(self)
            reveal(1)
        end
    end
    card:HookScript("OnHide", function(self)
        ui.stopTransition(self)
        reveal(1)
        mountID = nil
    end)
end
do
    -- Visible bounds in the 512 × 256 textures, with room for the soft edges.
    local bounds = {
        BattleForAzeroth = { 40, 468, 22, 234 }, BurningCrusade = { 29, 483, 24, 231 },
        Cataclysm = { 27, 484, 23, 233 }, Dragonflight = { 53, 458, 31, 224 },
        Legion = { 31, 479, 24, 229 }, Midnight = { 89, 411, 12, 246 },
        MistsOfPandaria = { 26, 486, 22, 233 }, Shadowlands = { 15, 498, 27, 234 },
        TheWarWithin = { 111, 402, 20, 239 }, WarlordsOfDraenor = { 32, 480, 24, 229 },
        WrathOfTheLichKing = { 43, 469, 23, 234 },
    }
    function expansionLogo:layout(logo, event)
        self:SetShown(logo ~= nil)
        if not logo then return card:GetWidth() - 16, 0 end
        local aspect = event and event.logoAspect
        if event and event.logoUV then
            self:SetTexCoord(unpack(event.logoUV))
        else
            local crop = bounds[logo]
            local left, right, top, bottom = 0, 512, 0, 256
            if crop then left, right, top, bottom = unpack(crop) end
            self:SetTexCoord(left / 512, right / 512, top / 256, bottom / 256)
            aspect = (right - left) / (bottom - top)
        end
        local height = math.min(72, 134 / aspect)
        local width, top = height * aspect, 4
        self:ClearAllPoints()
        ui.place(self, card, card:GetWidth() - 12 - width, top, width, height)
        self:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Expansions\\" .. logo .. ".tga")
        return card:GetWidth() - 32 - width, top + height + 3
    end
end
local bindHover = atlas.bindModelPreview(frame)
local titleArea = ui.place(CreateFrame("Frame", nil, card), card, 8, 6, 485, 44)
titleArea:EnableMouse(true)
local title = ui.text(titleArea, 0, 0, 485, 44, 26, "")
title.atlasGameText = true
bindHover(titleArea, function() return selected end)
titleArea:SetScript("OnMouseUp", function(_, button)
    if selected then atlas.mountModifiedClick(selected, button) end
end)
title:SetMaxLines(2)
function titleArea:updateQuality(mount)
    local r, g, b = atlas.qualityColor(atlas.mountDisplayQuality(mount.id))
    if r then title:SetTextColor(r, g, b) else title:SetTextColor(unpack(ui.paper)) end
end
titleArea.classRequirement = ui.text(card, 8, 45, 484, 14, 12, "", ui.gold)
local loreArea = ui.place(CreateFrame("Frame", nil, card), card, 8, 48, 652, 43)
loreArea:EnableMouse(true)
loreArea:SetClipsChildren(true)
local function hideLore(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
loreArea:SetScript("OnEnter", function(self)
    if not self.truncated then hideLore(self); return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ui.tooltipTitle(self.fullText, 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
loreArea:SetScript("OnLeave", hideLore)
loreArea:SetScript("OnHide", hideLore)

do
    local lead = ui.text(loreArea, 0, 0, 500, 43, 13, "", ui.muted)
    local fullWidth = card:GetWidth() - 16
    local lore = ui.text(loreArea, 0, 0, fullWidth, 43, 13, "", ui.muted)
    for _, text in ipairs({ lead, lore }) do
        text.atlasGameText = true
        text:SetJustifyV("TOP")
    end

    -- Split only at word boundaries, using the active font to measure the narrower lines.
    local function splitLore(text, height)
        lead:SetText(text)
        if lead:GetStringHeight() <= height then return text, "" end
        local breaks = {}
        for first, nextWord in text:gmatch("()%s+()") do
            breaks[#breaks + 1] = { first - 1, nextWord }
        end
        local left, right, best = 1, #breaks, 0
        while left <= right do
            local middle = math.floor((left + right) / 2)
            lead:SetText(text:sub(1, breaks[middle][1]))
            if lead:GetStringHeight() <= height then
                best, left = middle, middle + 1
            else
                right = middle - 1
            end
        end
        if best == 0 then return "", text end
        return text:sub(1, breaks[best][1]), text:sub(breaks[best][2])
    end

    local function setLorePart(text, content, width, y, lines, lineHeight)
        text:SetShown(content ~= "" and lines > 0)
        if content == "" or lines == 0 then return false end
        text:ClearAllPoints()
        text:SetPoint("TOPLEFT", loreArea, "TOPLEFT", 0, -y)
        text:SetWidth(width)
        text:SetHeight(0)
        text:SetMaxLines(0)
        text:SetText(content)
        local height = lines * lineHeight
        local truncated = text:GetStringHeight() > height
        text:SetHeight(height)
        text:SetMaxLines(lines)
        return truncated or text:IsTruncated()
    end

    function titleArea:layout(width, logoBottom, name, className, description)
        local top, bottom, gap = 6, 109, 2
        self:SetWidth(width)
        title:SetWidth(width)
        title:SetHeight(0)
        title:SetMaxLines(0)
        title:SetText(name)
        local requirement = self.classRequirement
        requirement:SetWidth(width)
        requirement:SetText(className and L("Классовый маунт · %s", className) or "")
        local classHeight = className and math.max(14, math.ceil(requirement:GetStringHeight())) or 0
        local _, loreFontSize = lore:GetFont()
        local lineHeight = math.ceil(loreFontSize * 1.2)
        local hasLore = type(description) == "string" and description ~= ""
        local descriptionHeight = 0
        if hasLore then
            lore:SetWidth(fullWidth)
            lore:SetHeight(0)
            lore:SetMaxLines(0)
            lore:SetText(description)
            descriptionHeight = (lore:GetStringHeight() > lineHeight and 2 or 1) * lineHeight + gap
        end
        local titleLimit = bottom - top - (className and classHeight + gap or 0) - descriptionHeight
        local titleHeight
        for size = 26, 18, -1 do
            ui.setFont(title, size)
            local _, fontSize = title:GetFont()
            local measured = title:GetStringHeight()
            local lines = title:GetUnboundedStringWidth() > width and 2 or 1
            titleHeight = math.ceil(math.max(measured, lines * fontSize * 1.2)) + 2
            if titleHeight <= titleLimit and measured <= math.ceil(2 * fontSize * 1.2) then break end
        end
        titleHeight = math.min(titleLimit, math.max(36, titleHeight))
        title:SetHeight(titleHeight)
        title:SetMaxLines(2)
        self:SetHeight(titleHeight)
        local y = top + titleHeight + gap
        requirement:SetShown(className ~= nil)
        if className then
            requirement:ClearAllPoints()
            ui.place(requirement, card, 8, y, width, classHeight)
            y = y + classHeight + gap
        end
        loreArea.fullText, loreArea.truncated = description, false
        loreArea:SetShown(hasLore)
        if not hasLore then return end

        local lines = math.min(3, math.floor((bottom - y) / lineHeight))
        local narrowLines = math.max(0, math.min(lines, math.ceil((logoBottom - y) / lineHeight)))
        local narrowHeight = narrowLines * lineHeight
        local first, rest = "", description
        if narrowLines == lines then
            first, rest = description, ""
        elseif narrowLines > 0 then
            lead:SetWidth(width)
            lead:SetHeight(0)
            lead:SetMaxLines(0)
            first, rest = splitLore(description, narrowHeight)
        end
        loreArea:ClearAllPoints()
        ui.place(loreArea, card, 8, y, fullWidth, lines * lineHeight)
        local leadTruncated = setLorePart(lead, first, width, 0, narrowLines, lineHeight)
        local tailTruncated = setLorePart(lore, rest, fullWidth, narrowHeight, lines - narrowLines, lineHeight)
        loreArea.truncated = leadTruncated or tailTruncated
    end
end

local sourceChoices, vendorIndex, vendorMount, sourceLocation = {}, 1, nil, nil
local function currentChoice() return sourceChoices[vendorIndex] end
local function currentVendor() local choice = currentChoice(); return choice and choice.vendor end
local function currentSource() local choice = currentChoice(); return choice and choice.view or selected end
local function isExploration(view) return view and (view.sourceKind or view.kind) == "Исследование" end
local function isInteractionRoute(view) return isExploration(view) or view and view.sourceRequirements ~= nil end
local function pointName(point, field)
    if not point then return end
    if atlas.getLocale() == "enUS" then
        local english = field == "boss" and point.englishBoss or field == "place" and point.englishPlace
        if english then return english end
    end
    return point[field]
end
local function locations()
    if not selected then return {} end
    local choice = currentChoice()
    local vendor = currentVendor()
    if vendor then return vendor.waypoints or { vendor } end
    if not choice or choice.classification.state ~= "current" or choice.contextOnly or choice.covenantVariant
        or choice.tradingPost or choice.separateSource or choice.grant then return {} end
    if atlas.sourceNavigationHidden(selected, choice) then return {} end
    local points = atlas.mountLocations(selected, UnitGUID("player"), true)
    local detail = selected.sourceRequirements
    local view = currentSource()
    local quests = not detail and atlas.questRewardWaypoints(selected, choice, points)
    if quests then return ui.sourceWaypointPoints(quests), "quest" end
    if choice.questReward then return {} end

    if detail or choice.scopedPoints or view.factionRoute then
        local interaction = isInteractionRoute(view)
        local matching = {}
        local routeName = atlas.searchKey(pointName(view, "boss") or "")
        for _, point in ipairs(points) do
            local sameTarget = not detail or (point.npc == detail.npc and point.boss == detail.name) == interaction
            local faction = atlas.sourcePointFaction(point)
            local sameFaction = not view.faction or not faction or view.faction == faction
            local sameRoute = not choice.scopedPoints or view.npc and point.npc == view.npc
                or not (view.npc and point.npc) and view.sourceMap == point.map
                    and routeName ~= "" and atlas.searchKey(pointName(point, "boss") or "") == routeName
            if sameTarget and sameFaction and sameRoute then matching[#matching + 1] = point end
        end
        points = matching
    end

    local exact = ui.sourceWaypointPoints(points)
    if #exact == 0 and choice.classification.key == "loot" then
        local entrances = atlas.instanceEntrancePoints(view)
        if entrances then return entrances, "entrance" end
    end
    return selected.locations and points or exact
end
local function pointLocation(point, choice, view, vendor, navigationKind)
    if not point or vendor or navigationKind then return end
    local reagentSource = choice.classification.subtype == "Сбор предметов" and point.npc and point.boss
    if selected.locations or reagentSource or isInteractionRoute(view) or selected.hasSourcePanels and #sourceChoices <= 1 then
        return point
    end
end
local function buildSourceChoices(mount)
    local choices = atlas.mountSourceChoices(mount)
    for _, choice in ipairs(choices) do
        if choice.tradingPost then
            local description, price = ui.tradingPostDescription(choice.tradingPost, true)
            choice.view.decoratedSource = price and (description .. "\n" .. price) or description
        end
        local route = choice.classification
        choice.tabKey = choice.tabOverride or choice.islandExpedition and "islandExpedition" or choice.islandSalvage and "islandSalvage"
            or choice.covenantVariant and "covenant" or route.key
            or (route.state == "historical" and "history") or "unknown"
    end
    return choices
end
do
    local function onTabClick(self)
        local index = self.routeIndex or 1
        if self.key == cardTabs.active and (not self.routeIndex or index == vendorIndex) then return end
        cardTabs.active, vendorIndex, locationIndex = self.key, index, 1
        ui.hideTooltipIn(card)
        setFooter()
        atlas.refreshDetails(true)
    end
    local function hideTabTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    local tabUnderlines = {}
    local function makeTab(label, icon)
        local button = ui.tab(card, 0, 153, 124, 37, label, icon, onTabClick, .72, nil, tabUnderlines)
        ui.setFont(button.caption, 12)
        button:HookScript("OnEnter", function(self)
            local caption = self.caption
            if caption:GetUnboundedStringWidth() <= caption:GetWidth() then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(caption:GetText(), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:HookScript("OnLeave", hideTabTooltip)
        button:HookScript("OnHide", hideTabTooltip)
        return button
    end
    for _, tab in ipairs(cardTabs) do
        tab.button = makeTab(tab.label, tab.icon)
        tab.button.key = tab.key
    end
    local routeTabs = { makeTab("", "Book"), makeTab("", "Book") }
    local function layoutTab(button, x, width)
        if x == button.layoutX and width == button:GetWidth() then return end
        button.layoutX = x
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", card, "TOPLEFT", x, -153)
        button:setTabWidth(width)
        button.caption:ClearAllPoints()
        button.caption:SetPoint("LEFT", button, "LEFT", 32, 0)
        button.caption:SetWidth(width - 38)
        button.glyph:ClearAllPoints()
        button.glyph:SetPoint("LEFT", button, "LEFT", 8, 0)
    end
    function cardTabs:select(choices, reset)
        local marketIndex, hasOtherRoute
        for index, choice in ipairs(choices) do
            local route = choice.classification
            if route.state == "current" and route.stock ~= "outOfRotation" then
                if choice.blackMarket then
                    marketIndex = index
                elseif not route.requirement then
                    hasOtherRoute = true
                end
            end
        end
        self.marketSource = nil
        if marketIndex then
            local market = table.remove(choices, marketIndex)
            if hasOtherRoute then self.marketSource = market.view
            else table.insert(choices, 1, market) end
        end
        local grouped, firstRoute = {}, nil
        for _, choice in ipairs(choices) do
            local key = choice.tabKey
            local list = grouped[key] or {}
            list[#list + 1] = choice
            grouped[key] = list
            firstRoute = firstRoute or (not choice.classification.requirement and choice.tabKey)
        end
        if reset or not grouped[self.active] then
            self.active = firstRoute or choices[1].tabKey
            vendorIndex = 1
            local alternatives = grouped[self.active]
            if #alternatives > 1 and alternatives[1].vendor then
                local faction = UnitFactionGroup("player")
                for index, choice in ipairs(alternatives) do
                    if choice.vendor and choice.vendor.faction and choice.vendor.faction == faction then
                        vendorIndex = index
                        break
                    end
                end
            end
        end
        local pair = #choices == 2 and choices[1].tabKey == choices[2].tabKey
            and not choices[1].covenantVariant and not choices[2].covenantVariant
            and not (choices[1].vendor and choices[2].vendor)
        local visible = {}
        for _, tab in ipairs(self) do
            local group = grouped[tab.key]
            if not pair and group then
                if tab.key == "islandSalvage" then
                    tab.button.caption:SetText(#group[1].islandSalvage == 1 and "Сумка" or tab.label)
                end
                visible[#visible + 1] = tab.button
            else
                tab.button:Hide()
            end
        end
        for index, button in ipairs(routeTabs) do
            if pair then
                local choice = choices[index]
                local view = choice.view or selected
                local label, icon = ui.sourceAppearance(choice.classification)
                local name = choice.routeCaption or atlas.displayName(view.boss, "target")
                button.key, button.routeIndex = choice.tabKey, index
                button.caption:SetText(name and name ~= "" and name or label)
                ui.setIcon(button.glyph, icon)
                visible[#visible + 1] = button
            else
                button:Hide()
            end
        end
        self.hasRouteTabs = pair
        local showTabs = #visible > 1
        self.bodyOffset = showTabs and 0 or -38
        self.rule:SetShown(showTabs)
        if not showTabs then
            if visible[1] then visible[1]:Hide() end
        else
            local total = 0
            for _, button in ipairs(visible) do
                button.desiredWidth = math.max(105, math.ceil(button.caption:GetUnboundedStringWidth()) + 43)
                total = total + button.desiredWidth
            end
            local x, fit = 8, math.min(1, (card:GetWidth() - 16) / total)
            for _, button in ipairs(visible) do
                local width = math.floor(button.desiredWidth * fit)
                layoutTab(button, x, width)
                button:setActive(button.key == self.active and (not button.routeIndex or vendorIndex == button.routeIndex))
                button:Show()
                x = x + width
            end
        end
        return grouped[self.active]
    end
end
function sourceMenu:matches(mount, key)
    if not key then return true end
    if (key == "achievement" and mount.hasAchievement)
        or (key == "quest" and (mount.hasQuest or atlas.questAcquisitionChain(mount))) then return true end
    self.categories = self.categories or setmetatable({}, { __mode = "k" })
    local available = self.categories[mount]
    if not available then
        available = {}
        self.categories[mount] = available
        for _, choice in ipairs(buildSourceChoices(mount)) do
            local route = choice.classification
            if route.key then available[route.key] = true end
        end
    end
    return available[key] == true
end
local function groupName(group)
    local name = group.name or group.boss
    return name and name ~= "" and atlas.displayName(name) or L("Источник не указан")
end
local sourceRow = {}
local containerOutcome = ui.text(card, 16, 0, 500, 22, 12, "", ui.muted)
containerOutcome:SetWordWrap(false)
containerOutcome:SetMaxLines(1)
local sourceButton = ui.place(CreateFrame("Button", nil, card), card, 16, 158, 272, 48)
sourceButton:SetScript("OnClick", function(self, button)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    if sourceButton.questTarget then
        local target = sourceButton.questTarget
        if button == "LeftButton" then
            if IsShiftKeyDown() then atlas.linkSourceName(nil, target.boss)
            elseif target.quest then
                atlas.openSourceReference("quest:" .. target.quest .. ":0", sourceButton.hitbox, target.questName)
            end
        end
        return
    end
    if button == "LeftButton" and IsShiftKeyDown() then
        local vendor, loc, view = currentVendor(), sourceLocation, currentSource()
        atlas.linkSourceName(not vendor and not loc and view or nil,
            vendor and groupName(vendor) or atlas.displayName(pointName(loc, "boss") or view.boss, "target"))
        return
    end
    if currentVendor() then return end
    local view = currentSource()
    if view.journalEncounter then setFooter(atlas.openSource(view)) end
end)
local source = ui.text(sourceButton, 0, 0, 272, 48, 16, "", ui.gold)
source.atlasGameText = true
source:SetMaxLines(2)
local bossCheck = ui.place(CreateFrame("Frame", nil, sourceButton), sourceButton, 244, 5, 28, 28)
bossCheck:EnableMouse(true)
local bossCheckIcon = ui.icon(bossCheck, 2, 2, 24, "ObjectiveComplete")
bossCheck:Hide()
bossCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ui.tooltipTitle(L(self.statusLabel or "Босс убит"), unpack(ui.mint))
    if self.sharedAttempt then
        ui.tooltipLine(L("Общая попытка для этих противников — отдельно для каждого персонажа"), 1, 1, 1, true)
    end
    GameTooltip:Show()
end)
local function hideBossTooltip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
bossCheck:SetScript("OnLeave", hideBossTooltip)
bossCheck:SetScript("OnHide", hideBossTooltip)
local function refreshBossCheck(view, visible, point, progress)
    local route = selected.encounter and #sourceChoices <= 1 and selected or view
    local killed = visible and not point and atlas.bossLockout
        and (view.sourceKind == "Босс" or (route == selected and selected.encounter))
        and atlas.bossLockout(selected, route) == "boss" or false
    local statusLabel, sharedAttempt = "Босс убит", false
    if visible and point and point.npc and progress and view.trackingCompatible ~= false then
        for _, entry in ipairs(progress.entries or {}) do
            for _, npc in ipairs(entry.npcs or {}) do
                if npc == point.npc and entry.state == "attempt" then
                    killed, statusLabel = true, "Попытка использована"
                    sharedAttempt = #entry.npcs > 1
                end
            end
        end
    end
    bossCheck.statusLabel = statusLabel
    bossCheck.sharedAttempt = sharedAttempt
    ui.setIcon(bossCheckIcon, sharedAttempt and "Lock" or "ObjectiveComplete")
    if killed and GameTooltip:IsOwned(bossCheck) then
        ui.tooltipTitle(L(statusLabel), unpack(ui.mint))
        if sharedAttempt then
            ui.tooltipLine(L("Общая попытка для этих противников — отдельно для каждого персонажа"), 1, 1, 1, true)
        end
        GameTooltip:Show()
    end
    local width = sourceButton:GetWidth()
    local leading = sourceButton.portraitInset or 0
    if bossCheck:IsShown() ~= killed or bossCheck.layoutWidth ~= width or bossCheck.layoutHeight ~= sourceButton:GetHeight()
        or bossCheck.layoutLeading ~= leading then
        bossCheck.layoutWidth = width
        bossCheck.layoutHeight = sourceButton:GetHeight()
        bossCheck.layoutLeading = leading
        bossCheck:SetShown(killed)
        bossCheck:ClearAllPoints()
        ui.place(bossCheck, sourceButton, width - 28, (sourceButton:GetHeight() - 28) / 2, 28, 28)
        source:ClearAllPoints()
        ui.place(source, sourceButton, leading, 0, width - leading - (killed and 36 or 0), sourceButton:GetHeight())
    end
    source:SetTextColor(unpack(killed and ui.muted or ui.gold))
    if killed then source:SetShadowColor(0, 0, 0, 1) end
end
local sourceProgress
sourceButton.atlasTradingPostSource = true
sourceButton:SetScript("OnEnter", function(self)
    local view = currentSource()
    local questTarget = sourceButton.questTarget
    if questTarget then
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(questTarget.boss)
        if questTarget.condition then ui.tooltipSourceText(questTarget.condition) end
        if questTarget.place then ui.tooltipLine(questTarget.place) end
        GameTooltip:Show()
        return
    end
    if not bossCheck:IsShown() and not currentVendor() and view.journalEncounter then
        source:SetTextColor(1, .91, .65)
    end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local point = sourceLocation
    local vendor = currentVendor()
    if vendor then
        local active = vendor.waypoints and vendor.waypoints[locationIndex] or vendor
        ui.tooltipTitle(groupName(active))
        if active.place and active.place ~= "" then ui.tooltipLine(atlas.displayName(active.place), 1, 1, 1, true) end
        local condition = atlas.sourcePointCondition(active)
        if condition then ui.tooltipSourceText(atlas.displaySourceText(condition), ui.gold) end
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
        ui.tooltipTitle(view.journalEncounter and L("Открыть босса в путеводителе") or atlas.displayName(view.boss, "target"))
        local text = atlas.displaySourceText(atlas.normalizeSource(view.journalSourceRaw or ""))
        if text ~= "" then ui.tooltipSourceText(text)
        elseif view.place then ui.tooltipLine(atlas.displayName(view.place), 1, 1, 1, true) end
    elseif point then
        ui.tooltipTitle(atlas.displayName(pointName(point, "boss"), "target"))
        ui.tooltipLine(atlas.displayName(pointName(point, "place")))
        ui.tooltipRareLocation(point)
        local condition = atlas.sourcePointCondition(point)
        if condition then
            ui.tooltipLine(" ")
            ui.tooltipSourceText(atlas.displaySourceText(condition), ui.gold)
        end
    elseif view.journalEncounter then
        ui.tooltipTitle(L("Открыть босса в путеводителе"))
        if source:IsTruncated() or source:GetUnboundedStringWidth() > source:GetWidth() then
            ui.tooltipLine(atlas.displayName(view.boss, "target"), 1, 1, 1, true)
        end
    else
        ui.tooltipTitle(atlas.displayName(view.boss, "target"))
        ui.tooltipLine(atlas.displayName(view.place), 1, 1, 1, true)
    end
    local stages = not vendor and view.trackingCompatible ~= false and atlas.attemptStages[selected.id]
    local condition = stages and atlas.sourcePointCondition(stages.reward)
    if condition then
        ui.tooltipLine(" ")
        ui.tooltipSourceText(atlas.sourceInlineLinks(L(condition)), ui.gold)
    end
    ui.tooltipSourceAlternatives(selected)
    GameTooltip:Show()
end)
local function leaveSource(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    source:SetTextColor(unpack(bossCheck:IsShown() and ui.muted or ui.gold))
    source:SetShadowColor(0, 0, 0, 1)
end
sourceButton:SetScript("OnLeave", leaveSource)
sourceButton:SetScript("OnHide", leaveSource)
do
    local target = CreateFrame("Button", nil, sourceButton)
    local portrait, border = ui.squareIcon(sourceButton, 0, 0, 42)
    border:ClearAllPoints()
    border:SetPoint("LEFT", sourceButton, "LEFT")
    local glyphIcon = sourceButton:CreateTexture(nil, "ARTWORK")
    glyphIcon:SetSize(23, 23)
    glyphIcon:SetPoint("LEFT", sourceButton, "LEFT", 4, 0)
    border:Hide()
    portrait:Hide()
    glyphIcon:Hide()
    target.atlasTradingPostSource = true
    for _, script in ipairs({ "OnClick", "OnEnter", "OnLeave", "OnHide" }) do
        target:SetScript(script, sourceButton:GetScript(script))
        sourceButton:SetScript(script, nil)
    end
    sourceButton:EnableMouse(false)
    sourceButton.hitbox = target
    local model, requestedNPC
    local modelDisplays = {}
    local watchingPortrait = false
    local function watchPortrait(watch)
        if watchingPortrait == watch then return end
        watchingPortrait = watch
        if watch then
            sourceButton:RegisterEvent("UNIT_PORTRAIT_UPDATE")
            sourceButton:RegisterEvent("PORTRAITS_UPDATED")
        else
            sourceButton:UnregisterEvent("UNIT_PORTRAIT_UPDATE")
            sourceButton:UnregisterEvent("PORTRAITS_UPDATED")
        end
    end
    sourceButton:SetScript("OnEvent", function(self, _, changedUnit)
        if not self:IsVisible() or (issecretvalue and issecretvalue(changedUnit)) then return end
        local unit = portrait.unit
        if changedUnit and changedUnit ~= unit then return end
        if unit then
            local guid = UnitGUID(unit)
            if (issecretvalue and issecretvalue(guid)) or guid ~= portrait.guid then
                atlas.refreshDetails(true)
            else
                SetPortraitTexture(portrait, unit)
            end
        elseif portrait.displayID and not portrait.file then
            SetPortraitTextureFromCreatureDisplayID(portrait, portrait.displayID)
        end
    end)
    local function clearModel()
        if not requestedNPC then return end
        requestedNPC = nil
        model:SetScript("OnModelLoaded", nil)
        model:ClearModel()
        model:Hide()
    end
    sourceButton:HookScript("OnHide", function()
        watchPortrait(false)
        clearModel()
    end)
    local function lookupModel(npc)
        if requestedNPC ~= npc then clearModel() end
        if not npc or modelDisplays[npc] or npc == requestedNPC then return modelDisplays[npc] end
        if not model then
            model = CreateFrame("PlayerModel", nil, sourceButton)
            model:SetSize(1, 1)
            model:SetPoint("CENTER")
            model:SetAlpha(0)
            model:EnableMouse(false)
        end
        requestedNPC = npc
        local loading = true
        local function readDisplay()
            if npc ~= requestedNPC or model:GetScript("OnModelLoaded") ~= readDisplay or not sourceButton:IsVisible() then return end
            local display = model:GetDisplayInfo()
            if (issecretvalue and issecretvalue(display)) or type(display) ~= "number" or display <= 0 then return end
            modelDisplays[npc] = display
            clearModel()
            if not loading then atlas.refreshDetails(true) end
        end
        model:Show()
        model:SetScript("OnModelLoaded", readDisplay)
        model:SetCreature(npc)
        readDisplay()
        loading = false
        return modelDisplays[npc]
    end
    function sourceButton:updatePortrait(visible, mount, view, point, glyph)
        local file, displayID, aspect, unit, guid, npc
        if visible and atlas.sourcePortrait then
            file, displayID, aspect, unit, guid, npc = atlas.sourcePortrait(mount, view, point)
        end
        local modelDisplay = lookupModel(SetPortraitTextureFromCreatureDisplayID and npc)
        displayID = displayID or modelDisplay
        local hasPortrait = file ~= nil or unit ~= nil or displayID ~= nil and SetPortraitTextureFromCreatureDisplayID ~= nil
        local fallback = visible and not hasPortrait and glyph or nil
        portrait.unit = unit
        if portrait.file ~= file or portrait.displayID ~= displayID or portrait.guid ~= guid then
            portrait.file, portrait.displayID, portrait.guid = file, displayID, guid
            portrait:SetTexture(nil)
            portrait:SetTexCoord(0, 1, 0, 1)
            if unit then
                SetPortraitTexture(portrait, unit)
                portrait:SetTexCoord(.16, .84, .16, .84)
            elseif file then
                portrait:SetTexture(file)
                if type(aspect) == "number" and aspect > 1 then
                    local edge = (1 - 1 / aspect) / 2
                    portrait:SetTexCoord(edge, 1 - edge, 0, 1)
                end
            elseif displayID and SetPortraitTextureFromCreatureDisplayID then
                SetPortraitTextureFromCreatureDisplayID(portrait, displayID)
                -- Sample the square inside the circular creature portrait.
                portrait:SetTexCoord(.16, .84, .16, .84)
            end
        end
        self.portraitInset = hasPortrait and 52 or fallback and 39 or 0
        if fallback and glyphIcon.glyph ~= fallback then
            ui.setIcon(glyphIcon, fallback)
            glyphIcon.glyph = fallback
        end
        border:SetShown(hasPortrait)
        portrait:SetShown(hasPortrait)
        glyphIcon:SetShown(fallback ~= nil)
        watchPortrait(self:IsVisible() and not file and (unit ~= nil or displayID ~= nil))
    end
    function sourceButton:updateHitbox(visible)
        local measured = source.GetWrappedWidth and source:GetWrappedWidth() or source:GetStringWidth()
        local leading = self.portraitInset or 0
        local width = leading + math.min(source:GetWidth(), measured + 6)
        local height = leading > 0 and self:GetHeight() or math.min(source:GetHeight(), source:GetStringHeight() + 4)
        target:ClearAllPoints()
        ui.place(target, self, 0, (self:GetHeight() - height) / 2, math.max(1, width), math.max(1, height))
        target:SetShown(visible and width > 6 and height > 4)
        if GameTooltip:IsOwned(target) and not target:IsMouseOver() then leaveSource(target) end
    end
end
local placeArea = {}
local function placeLink()
    local view = currentSource()
    return not currentVendor() and view and view.journalInstance and view or nil
end
local function hidePlaceTooltip(self)
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
end
local function setFieldIcon(texture, name, x, y)
    -- Native map icons include transparent margins. Keep their aspect ratio
    -- while giving the visible glyph the same height as the other headings.
    local size = ({ Boss = 23, Rare = 28, Vendor = 22, Shop = 32, Raid = 32, Dungeon = 32,
        Place = 32, Chance = 23, Quest = 22, Bookmark = 16 })[name] or 20
    local width = name == "Shop" and size * 64 / 82 or size
    texture:ClearAllPoints()
    ui.place(texture, card, x + 11 - width / 2, y + 9.5 - size / 2, width, size)
    ui.setIcon(texture, name)
end
local function fieldLabel(x, y, icon, label)
    local tex = card:CreateTexture(nil, "ARTWORK")
    setFieldIcon(tex, icon, x, y)
    return ui.text(card, x + 29, y, 220, 19, 13, label, ui.muted), tex
end
sourceProgress = ui.place(CreateFrame("Frame", nil, card), card, 205, 158, 62, 22)
sourceProgress:EnableMouse(true)
ui.icon(sourceProgress, 0, 3, 16, "Calendar")
sourceProgress.label = ui.text(sourceProgress, 20, 0, 42, 22, 12, "", ui.mint)
sourceProgress.label:SetJustifyH("RIGHT")
sourceProgress:SetScript("OnEnter", function(self)
    local progress = self.progress
    if not progress then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    ui.tooltipTitle(L("Попытки этого персонажа"))
    ui.tooltipLine(L(progress.frequency == "weekly" and "Еженедельно" or "Ежедневно"), unpack(ui.muted))
    ui.tooltipLine(L("Персонаж") .. ": " .. (UnitName("player") or ""), 1, 1, 1)
    ui.tooltipLine(L("Выполнено: %d / %d", progress.completedAttempts, progress.totalAttempts), 1, 1, 1)
    ui.tooltipLine(L("Можно идти: %d · Нужно обновить: %d", progress.availableAttempts, progress.unknownAttempts), unpack(ui.muted))
    GameTooltip:Show()
end)
sourceProgress:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
sourceProgress:SetScript("OnHide", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
local detailArea = ui.place(CreateFrame("Frame", nil, card), card, 16, 328, 632, 58)
local detail = ui.text(detailArea, 0, 0, 632, 58, 13, "", ui.muted)
detail:SetJustifyV("TOP")
detailArea:Hide()
local sourcePager = ui.place(CreateFrame("Frame", nil, card), card, 560, 160, 92, 21)
sourcePager:SetFrameLevel(card:GetFrameLevel() + 5)
local counter = ui.text(sourcePager, 23, 0, 46, 21, 12, "", ui.muted)
counter:SetJustifyH("CENTER")
local navigationReserve = 118
local function cycle(delta, pointOnly)
    if not pointOnly and #sourceChoices > 1 then
        vendorIndex = (vendorIndex - 1 + delta) % #sourceChoices + 1
        locationIndex = 1
    else
        local count = placeArea.navigationCount or 0
        if count < 2 then return end
        locationIndex = (locationIndex - 1 + delta) % count + 1
    end
    ui.hideTooltipIn(card)
    setFooter()
    atlas.refreshDetails()
end
local function pagerArrow(pager, x, width, height, direction, onMove)
    local arrow = ui.place(CreateFrame("Button", nil, pager), pager, x, 0, width, height)
    -- These larger chevrons sit below the digits when their font boxes are centered.
    local label = ui.text(arrow, 0, -2, width, height, 20, direction < 0 and "‹" or "›", ui.gold)
    label:SetJustifyH("CENTER")
    arrow:SetScript("OnClick", function() onMove(direction) end)
    arrow:SetScript("OnEnter", function(self)
        if self:IsEnabled() then label:SetTextColor(1, .91, .65) end
    end)
    local function reset(self) label:SetTextColor(unpack(self:IsEnabled() and ui.gold or ui.muted)) end
    arrow:SetScript("OnDisable", reset)
    arrow:SetScript("OnEnable", reset)
    arrow:SetScript("OnLeave", reset)
    arrow:SetScript("OnHide", reset)
    return arrow
end
pagerArrow(sourcePager, 0, 23, 21, -1, cycle)
pagerArrow(sourcePager, 69, 23, 21, 1, cycle)

do
    local navigationLevel = card:GetFrameLevel() + 3
    local pager = ui.place(CreateFrame("Frame", nil, card), card, 548, 158, 108, 21)
    pager:SetFrameLevel(navigationLevel)
    local pointCounter = ui.text(pager, 22, 0, 64, 22, 12, "", ui.muted)
    pointCounter:SetJustifyH("CENTER")
    local pointHelp = ui.place(CreateFrame("Frame", nil, pager), pager, 22, 0, 64, 22)
    pointHelp:SetFrameLevel(navigationLevel + 1)
    pointHelp:EnableMouse(true)
    pointHelp:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Точки на карте"))
        ui.tooltipLine(pointCounter:GetText())
        GameTooltip:Show()
    end)
    pointHelp:SetScript("OnLeave", hidePlaceTooltip)
    pointHelp:SetScript("OnHide", hidePlaceTooltip)
    local arrows = {}
    for _, direction in ipairs({ -1, 1 }) do
        local arrow = pagerArrow(pager, direction < 0 and 0 or 86, 22, 22, direction,
            function(step) cycle(step, true) end)
        arrow:SetFrameLevel(navigationLevel + 1)
        arrows[#arrows + 1] = arrow
    end
    local coords = ui.waypointButton(card, function(self, button)
        if not self.point then return end
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        local message = ui.waypointAction({ id = selected.id }, self.point, self.points, button)
        if button ~= "RightButton" or message then setFooter(message) end
    end, function(point)
        if point.entrance and point.place then ui.tooltipLine(point.place) end
        local condition = atlas.sourcePointCondition(point)
        if condition then ui.tooltipSourceText(atlas.displaySourceText(condition)) end
        ui.tooltipRareLocation(point)
    end)
    coords:SetFrameLevel(navigationLevel + 1)
    placeArea.waypoint = coords
    function placeArea:updateNavigation(point, count, points, x, y)
        self.navigationCount = count
        local exact = point and point.navigation ~= false and atlas.hasSourceCoordinates(point)
        local multiple = count > 1
        local pointKey = point and table.concat({ tostring(selected and selected.id), tostring(point.map), tostring(point.npc),
            tostring(point.x), tostring(point.y), point.boss or point.name or "", point.place or "",
            point.kind or "", atlas.sourcePointCondition(point) or "" }, ":")
        local changed = self.navigationKey ~= pointKey
        self.navigationKey = pointKey
        if changed then coords:clearTooltip() end
        pager:ClearAllPoints()
        local hasCoordinateLine = exact or multiple and ui.waypointGroupSize(points) > 0
        pager:SetPoint("TOPLEFT", card, "TOPLEFT", x + navigationReserve - pager:GetWidth(), -(y + (hasCoordinateLine and 0 or 13)))
        pager:SetShown(exact or multiple)
        pointCounter:SetText((exact or multiple) and locationIndex .. " / " .. count or "")
        for _, arrow in ipairs(arrows) do arrow:SetEnabled(multiple) end
        coords:ClearAllPoints()
        coords:SetPoint("TOP", pager, "BOTTOM")
        coords.point = exact and point or nil
        coords.points = exact and points or nil
        coords:SetShown(exact == true)
        coords:SetEnabled(exact == true)
        coords:setCoordinates(exact and ("%.1f, %.1f"):format(point.x * 100, point.y * 100) or "")
        if GameTooltip:IsShown() and GameTooltip:IsOwned(coords) then coords:refreshTooltip() end
    end
end

local summary = {}
do
    local labelY, valueY, valueHeight = 114, 130, 20
    local iconY = (labelY + valueY + valueHeight) / 2 - 9.5
    function summary:setIcon(key, name)
        local slot = self[key]
        if slot.iconName == name then return end
        slot.iconName = name
        setFieldIcon(slot.icon, name, slot.x, iconY)
    end
    local chancePadding, chanceTextOffset = 10, 27
    local fields = {
        { "kind", 13, "Boss", "Источник", 25, 6 },
        { "place", 14, "Place", "Место" },
        { "chance", chancePadding, "Chance", "Шанс", chanceTextOffset, chancePadding },
        { "status", 8, "Bookmark", "Статус", 24, 2 },
    }
    local dividers = {}
    for i = 1, #fields do
        dividers[i] = ui.fill(card, 0, 120, 1, 23, { .30, .38, .42, .66 })
        dividers[i]:SetDrawLayer("BORDER")
    end
    local function positionDivider(index, x)
        local divider = dividers[index]
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", card, "TOPLEFT", x, -120)
        divider:Show()
    end
    local function hideValueTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    local function showValueTooltip(self)
        local text = self.atlasSummaryValue
        if not text:IsTruncated() and text:GetUnboundedStringWidth() <= text:GetWidth() then
            hideValueTooltip(self)
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(text:GetText(), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end
    for _, field in ipairs(fields) do
        local iconX, x, width = field[2], field[2] + 29, 120
        local label = ui.text(card, x, labelY, width, 19, 11, field[4], ui.muted)
        label:SetMaxLines(1)
        local valueArea = ui.place(CreateFrame("Frame", nil, card), card, x, valueY, width, valueHeight)
        valueArea:SetClipsChildren(true)
        local value = ui.text(valueArea, 0, 0, width, valueHeight, 14, "")
        value:SetWordWrap(false)
        value:SetMaxLines(1)
        value.atlasGameText = field[1] == "place"
        summary[field[1]] = { x = iconX, icon = card:CreateTexture(nil, "ARTWORK"), value = value,
            label = label, valueArea = valueArea }
        summary:setIcon(field[1], field[3])
        if field[1] == "place" then
            summary.place.hitbox = ui.locationLink(value)
            local hitbox = summary.place.hitbox
            hitbox.atlasSummaryValue = value
            local openMap = hitbox:GetScript("OnClick")
            hitbox:SetScript("OnClick", function(self, button)
                if button == "LeftButton" and IsShiftKeyDown() then
                    local loc, vendor = sourceLocation, currentVendor()
                    atlas.linkSourceName(not vendor and not loc and currentSource() or nil, self.locationText, true)
                elseif self.mapID then openMap(self, button)
                elseif placeLink() then setFooter(atlas.openPlace(placeLink())) end
            end)
        elseif field[1] ~= "chance" then
            local hitbox = ui.textTarget(value)
            summary[field[1]].hitbox = hitbox
            hitbox.atlasSummaryValue = value
            hitbox:SetScript("OnEnter", showValueTooltip)
            hitbox:SetScript("OnLeave", hideValueTooltip)
            hitbox:SetScript("OnHide", hideValueTooltip)
        end
    end
    local marketSize = 22
    local market = CreateFrame("Frame", nil, card)
    market:EnableMouse(true)
    market:Hide()
    ui.icon(market, 3, 3, 16, "Vendor")
    market:SetScript("OnEnter", function(self)
        if not self.source then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Другие способы получения"))
        ui.tooltipSourceText(self.source.journalSourceRaw)
        GameTooltip:Show()
    end)
    market:SetScript("OnLeave", hideValueTooltip)
    market:SetScript("OnHide", hideValueTooltip)
    summary.kind.blackMarket = market
    local respawnTextX = chancePadding + chanceTextOffset
    local respawn = CreateFrame("Frame", nil, card)
    summary.respawn = respawn
    respawn:EnableMouse(true)
    respawn:Hide()
    local clock = respawn:CreateTexture(nil, "ARTWORK")
    ui.place(clock, respawn, chancePadding + 2, 11, 18, 18)
    clock:SetTexture("Interface\\Icons\\Spell_Holy_BorrowedTime")
    respawn.label = ui.text(respawn, respawnTextX, labelY - 112, 80, 19, 11, "Респавн", ui.muted)
    respawn.label:SetMaxLines(1)
    respawn.value = ui.text(respawn, respawnTextX, valueY - 112, 80, valueHeight, 14, "")
    respawn.value:SetWordWrap(false)
    respawn.value:SetMaxLines(1)
    respawn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Примерное время возрождения"), unpack(ui.gold))
        if self.condition then ui.tooltipSourceText(self.condition) end
        ui.tooltipLine(L("На основе данных игроков"), unpack(ui.muted))
        GameTooltip:Show()
    end)
    respawn:SetScript("OnLeave", hideValueTooltip)
    respawn:SetScript("OnHide", hideValueTooltip)
    function summary:updateRespawn(choice, view, point, navigationKind, paged)
        local route = choice.classification
        local placeKind = view.sourcePlaceKind or view.kind
        local instanced = view.sourcePlaceKind ~= "Открытый мир"
            and (view.journalInstance or view.isRaid or placeKind == "Рейд" or placeKind == "Подземелье")
        local interval, condition
        if route.state == "current" and not route.requirement and not choice.contextOnly
            and not (choice.islandExpedition or choice.islandSalvage or choice.grant or choice.covenantVariant)
            and not (navigationKind or paged)
            and not instanced
            and (route.key == "loot" or route.key == "quest" or route.subtype == "Сбор предметов" and point and point.npc) then
            interval, condition = atlas.sourceRespawnText(selected, view, point)
        end
        respawn.value:SetText(interval or "")
        respawn.condition = interval and condition or nil
        respawn:SetShown(interval ~= nil)
    end
    local measure = card:CreateFontString(nil, "ARTWORK")
    measure:Hide()
    local function compactFieldWidth(slot)
        measure:SetFont(slot.value:GetFont())
        measure:SetText(slot.value:GetText())
        local valueWidth = measure:GetUnboundedStringWidth()
        measure:SetFont(slot.label:GetFont())
        measure:SetText(slot.label:GetText())
        return 2 * chancePadding + chanceTextOffset + math.ceil(math.max(valueWidth, measure:GetUnboundedStringWidth()))
    end
    local statusChoices = { "Не получен", "Недоступно", "В коллекции" }
    function summary:layout(hasPlace, hasChance)
        local font, size, flags = self.status.value:GetFont()
        local locale = atlas.getLocale()
        market.source = cardTabs.marketSource
        local hasMarket = market.source ~= nil
        local pagerField = sourcePager:IsShown() and (hasPlace and "place" or "kind")
        local chanceLabel = hasChance and self.chance.label:GetText() or ""
        local chanceValue = hasChance and self.chance.value:GetText() or ""
        local respawnValue = respawn.value:GetText() or ""
        local key = table.concat({ font, size, flags or "", locale, tostring(hasPlace), tostring(hasChance),
            tostring(hasMarket), chanceLabel, chanceValue, respawnValue, tostring(pagerField) }, "\001")
        if self.layoutKey == key then return end
        self.layoutKey = key
        measure:SetFont(font, size, flags)
        local statusWidth = 0
        for _, name in ipairs(statusChoices) do
            measure:SetText(L(name))
            statusWidth = math.max(statusWidth, measure:GetUnboundedStringWidth())
        end
        statusWidth = math.max(124, math.min(177, math.ceil(statusWidth) + 52))
        if not hasPlace and not hasChance and respawnValue == "" then statusWidth = math.floor(card:GetWidth() * .41) end
        local chanceWidth = hasChance and compactFieldWidth(self.chance) or 0
        local respawnWidth = respawnValue ~= "" and compactFieldWidth(respawn) or 0
        local remaining = card:GetWidth() - statusWidth - chanceWidth - respawnWidth
        local pagerWidth = sourcePager:GetWidth() + 4
        local kindWidth = hasPlace and math.floor((remaining - (pagerField == "place" and pagerWidth or 0)) * .40) or remaining
        local widths = { kindWidth, hasPlace and (remaining - kindWidth) or 0, chanceWidth, statusWidth }
        local x, dividerIndex = 0, 0
        for i, field in ipairs(fields) do
            if field[1] == "chance" and respawnWidth > 0 then
                dividerIndex = dividerIndex + 1
                positionDivider(dividerIndex, x)
                respawn:ClearAllPoints()
                ui.place(respawn, card, x, 112, respawnWidth, 40)
                local width = respawnWidth - respawnTextX - chancePadding
                respawn.label:SetWidth(width)
                respawn.value:SetWidth(width)
                x = x + respawnWidth
            end
            local slot = self[field[1]]
            local width = widths[i]
            local visible = width > 0
            slot.icon:SetShown(visible)
            slot.label:SetShown(visible)
            slot.valueArea:SetShown(visible)
            if visible then
                if x > 0 then
                    dividerIndex = dividerIndex + 1
                    positionDivider(dividerIndex, x)
                end
                local iconX = x + field[2]
                local valueX = iconX + (field[5] or 29)
                local valueWidth = x + width - valueX - (field[6] or 8)
                if field[1] == "kind" and hasMarket then
                    market:ClearAllPoints()
                    ui.place(market, card, x + width - marketSize - 4, iconY - 1.5, marketSize, marketSize)
                    valueWidth = valueWidth - marketSize - 2
                end
                if field[1] == pagerField then
                    valueWidth = valueWidth - pagerWidth
                    sourcePager:ClearAllPoints()
                    sourcePager:SetPoint("LEFT", card, "TOPLEFT", valueX + valueWidth + 4, -(iconY + 9.5))
                end
                slot.x = iconX
                setFieldIcon(slot.icon, slot.iconName, iconX, iconY)
                slot.label:ClearAllPoints()
                ui.place(slot.label, card, valueX, labelY, valueWidth, 19)
                slot.valueArea:ClearAllPoints()
                ui.place(slot.valueArea, card, valueX, valueY, valueWidth, valueHeight)
                slot.value:SetWidth(valueWidth)
                if field[1] == "chance" then
                    self.oddsArea:ClearAllPoints()
                    ui.place(self.oddsArea, card, x + 8, 112, width - 16, 40)
                elseif field[1] ~= "place" then
                    slot.hitbox:updateBounds(true)
                end
                x = x + width
            end
        end
        for i = dividerIndex + 1, #dividers do dividers[i]:Hide() end
        market:SetShown(hasMarket)
    end
end
local displayedAttempts, displayedReward, displayedProbability, displayedPerAttempt, displayedInteraction
local probabilityText = ui.probabilityText
local function displayedRewardCondition()
    local english = atlas.getLocale() == "enUS" and displayedReward.englishCondition
    return atlas.sourceInlineLinks(english or L(displayedReward.condition))
end
local attemptsLabel, attemptsIcon = fieldLabel(12, 414, "Kills", "")
attemptsLabel:SetWidth(102)
attemptsLabel:SetMaxLines(2)
ui.setFont(attemptsLabel, 11)
local oddsArea = ui.place(CreateFrame("Frame", nil, card), card, 400, 112, 110, 40)
summary.oddsArea = oddsArea
oddsArea:EnableMouse(true)
oddsArea:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if summary.openingChance then
        ui.tooltipTitle(L("Шанс при открытии"), unpack(ui.gold))
        ui.tooltipSourceText(ui.rewardText(ui.coloredMountName(selected)) .. " · " .. probabilityText(summary.openingChance))
        ui.tooltipLine(containerOutcome:GetText(), 1, 1, 1, true)
        ui.tooltipLine(L("Предположительный шанс"))
        GameTooltip:Show()
        return
    end
    if summary.starterChance then
        ui.tooltipTitle(L("Предмет для начала цепочки"), unpack(ui.gold))
        ui.tooltipLine(L("За одну попытку: %s", probabilityText(summary.starterChance)), 1, 1, 1, true)
        if summary.starterRateEstimated then ui.tooltipLine(L("Предположительный шанс")) end
        GameTooltip:Show()
        return
    end
    ui.tooltipTitle(displayedInteraction and L("Шанс") .. " · " .. probabilityText(1, true)
        or L("Шанс выпадения"), unpack(ui.gold))
    if displayedReward then
        ui.tooltipSourceText(displayedRewardCondition(), ui.paper)
        local progress = not displayedInteraction and selected and atlas.itemAttemptProgress and atlas.itemAttemptProgress(selected)
        if progress and progress.perAttempt ~= nil then
            local item = atlas.lootItems[selected.id]
            local name = atlas.dataName(progress) or (item and item.item == progress.item and atlas.dataName(item))
            local caption = atlas.sourceItemReference(progress.item, name) or RETRIEVING_ITEM_INFO
            ui.tooltipSourceText(caption .. ": " .. probabilityText(progress.perAttempt, progress.perAttempt == 1), ui.paper)
            if progress.rateEstimated then ui.tooltipLine(L("Предположительный шанс")) end
        end
    elseif displayedAttempts ~= nil then
        ui.tooltipLine(L("Попыток: %s", displayedAttempts), 1, 1, 1, true)
        ui.tooltipLine(L("За одну попытку: %s", probabilityText(displayedPerAttempt, displayedPerAttempt == 1)), 1, 1, 1, true)
        if displayedProbability then
            ui.tooltipLine(L("Вероятность за все попытки") .. ": " .. probabilityText(displayedProbability, displayedPerAttempt == 1), 1, 1, 1, true)
        end
        ui.tooltipLine(" ")
        ui.tooltipLine(L("Вероятность хотя бы одного выпадения за все учтённые попытки при постоянном шансе и независимых попытках."), ui.muted[1], ui.muted[2], ui.muted[3], true)
        if not summary.rewardRateEstimated then
            ui.tooltipLine(L("Шанс следующей попытки не увеличивается."), ui.muted[1], ui.muted[2], ui.muted[3], true)
        end
    else
        ui.tooltipLine(L("За одну попытку: %s", probabilityText(displayedPerAttempt, displayedPerAttempt == 1)), 1, 1, 1, true)
    end
    if summary.rewardRateEstimated then ui.tooltipLine(L("Предположительный шанс")) end
    local progress = not displayedInteraction and selected and atlas.itemAttemptProgress and atlas.itemAttemptProgress(selected)
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
summary.showOdds = oddsArea:GetScript("OnEnter")
local kills = ui.text(card, 144, 409, 57, 28, 20, "")
kills:SetJustifyH("RIGHT")
local killsHelp = ui.place(CreateFrame("Frame", nil, card), card, 8, 406, 195, 36)
local chanceTrack = ui.place(CreateFrame("Frame", nil, card), card, 217, 409, 291, 31)
killsHelp:EnableMouse(true)
function killsHelp:shareHint()
    if self.count ~= nil or chanceTrack.islandCount ~= nil then
        ui.attemptShareHint()
    end
end
function killsHelp.shareAttempts(_, button)
    if button == "LeftButton" and IsShiftKeyDown() then
        atlas.shareMountAttempts(selected, chanceTrack.islandCount or killsHelp.count)
    end
end
killsHelp:SetScript("OnMouseUp", killsHelp.shareAttempts)
chanceTrack:SetScript("OnMouseUp", killsHelp.shareAttempts)
function killsHelp:showRiftTooltip(owner)
    local progress = self.riftProgress
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    ui.tooltipTitle(L("Попыток: %s", progress.attempts), unpack(ui.gold))
    GameTooltip:AddDoubleLine(L("Завершено подходящих разломов"), tostring(progress.finals), 1, 1, 1, unpack(ui.paper))
    GameTooltip:AddDoubleLine(L("Открыто ящиков"), tostring(progress.boxes), 1, 1, 1, unpack(ui.paper))
    if progress.referencePerAttempt then
        local rate = probabilityText(progress.referencePerAttempt):gsub("^≈ ", "")
        ui.tooltipLine(L("Расчёт по %s за попытку. Фактический шанс может отличаться.", rate), ui.muted[1], ui.muted[2], ui.muted[3], true)
    end
    self:shareHint()
    GameTooltip:Show()
end
killsHelp:SetScript("OnEnter", function(self)
    if not selected then return end
    if chanceTrack.islandMode then return chanceTrack:GetScript("OnEnter")(self) end
    if self.riftProgress then return self:showRiftTooltip(self) end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    ui.attemptTooltip(self.count)
    if self.encounterEstimate then
        ui.tooltipLine("Rarity: " .. L(self.encounterEstimate), 1, 1, 1, true)
    end
    self:shareHint()
    GameTooltip:Show()
end)
local function hideKillsTooltip(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
killsHelp:SetScript("OnLeave", hideKillsTooltip)
killsHelp:SetScript("OnHide", hideKillsTooltip)
local cardDetails
chanceTrack:EnableMouse(true)
chanceTrack:SetScript("OnEnter", function(self)
    if killsHelp.riftProgress then return killsHelp:showRiftTooltip(self) end
    if chanceTrack.islandMode then
        if chanceTrack.islandCount == nil then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Попыток: %s", chanceTrack.islandCount), unpack(ui.gold))
        ui.tooltipLine(L("Попытка засчитывается за завершение островной экспедиции или открытие одной из перечисленных для этого маунта сумок."),
            1, 1, 1, true)
        if chanceTrack.islandRate then
            local rate = probabilityText(chanceTrack.islandRate):gsub("^≈ ", "")
            ui.tooltipLine(L("Расчёт по %s за попытку. Фактический шанс может отличаться.",
                rate), ui.muted[1], ui.muted[2], ui.muted[3], true)
        end
        killsHelp:shareHint()
        GameTooltip:Show()
        return
    end
    if displayedProbability == nil then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    local reward = ui.coloredMountName(selected)
    if summary.raidGuarantee then
        local loot = summary.raidGuarantee
        ui.tooltipTitle(L("Добыча рейда") .. " · " .. probabilityText(1, true), unpack(ui.gold))
        ui.tooltipSourceText(atlas.getLocale() == "enUS" and loot.englishCondition or loot.condition)
    elseif summary.chainReward then
        ui.tooltipTitle(L("При выполнении условий") .. " · " .. probabilityText(1, true), unpack(ui.gold))
        ui.tooltipSourceText(ui.questChainTooltip(summary.chainReward, currentChoice().chainGrant, nil, cardDetails.note, reward))
        GameTooltip:Show()
        return
    elseif summary.directQuestReward then
        ui.tooltipTitle(L("При выполнении условий") .. " · " .. probabilityText(1, true), unpack(ui.gold))
        for _, quest in ipairs(summary.directQuestReward.quests) do
            local caption = quest.mode == "choice" and "Выбери эту награду при сдаче задания: %s"
                or quest.mode == "during" and "Получи маунта во время задания: %s" or "Выполни задание: %s"
            ui.tooltipLine(L(caption, "|cffffd200" .. atlas.dataName(quest) .. "|r"), 1, 1, 1, true)
        end
        if atlas.questRewardHasExclusiveColours(selected, summary.directQuestReward) then
            ui.tooltipLine(L("За эту цепочку можно бесплатно получить только один цвет."), 1, 1, 1, true)
        end
    elseif summary.sourceGuarantee then
        ui.tooltipTitle(L("При выполнении условий") .. " · " .. probabilityText(1, true), unpack(ui.gold))
        local condition = summary.sourceGuarantee.condition or cardDetails.sourceText
        if condition and condition ~= "" then ui.tooltipSourceText(atlas.sourceInlineLinks(L(condition))) end
    elseif displayedPerAttempt == 1 then
        ui.tooltipTitle(L(displayedReward and "При выполнении условий" or "Шанс выпадения") .. " · " .. probabilityText(1, true), unpack(ui.gold))
        ui.tooltipSourceText(displayedReward and displayedRewardCondition()
            or L("За одну попытку: %s", probabilityText(1, true)), ui.paper)
    else
        local step = math.max(1, math.min(#ui.chanceFlavors, math.ceil(displayedProbability * 10)))
        ui.tooltipTitle(L("Прогресс (шанс)") .. " · " .. probabilityText(displayedProbability), unpack(ui.gold))
        if summary.openingChance then
            ui.tooltipLine(L("Попыток с добычей") .. ": " .. tostring(displayedAttempts), 1, 1, 1)
            ui.tooltipLine(L("За одну попытку: %s", probabilityText(displayedPerAttempt)), 1, 1, 1)
            ui.tooltipLine(L("Шанс при открытии") .. ": " .. probabilityText(summary.openingChance), 1, 1, 1)
        end
        if summary.rewardRateEstimated then ui.tooltipLine(L("Предположительный шанс")) end
        ui.tooltipLine(L(ui.chanceFlavors[step]), unpack(ui.muted))
    end
    ui.tooltipSourceText(ui.rewardText(reward))
    GameTooltip:Show()
end)
chanceTrack:SetScript("OnLeave", hideOdds)
chanceTrack:SetScript("OnHide", hideOdds)
chanceTrack.icon = ui.icon(chanceTrack, 0, 2, 21, "Chance")
local chanceRail = ui.fill(chanceTrack, 28, 7, 260, 7, ui.rule)
chanceRail:SetGradient("HORIZONTAL", CreateColor(.25, .30, .35), CreateColor(.22, .47, .35))
local chanceFill = ui.fill(chanceTrack, 28, 7, 1, 7, ui.mint)
chanceTrack.scaleMarkers = {}
do
    for _, fraction in ipairs({ .25, .75 }) do
        local markers = chanceTrack.scaleMarkers
        markers[#markers + 1] = ui.fill(chanceTrack, 28 + chanceRail:GetWidth() * fraction, 15, 1, 2, ui.muted)
    end
    local chanceGlow = {}
    for i, y in ipairs({ 2, 14 }) do
        local glow = ui.fill(chanceTrack, 28, y, chanceRail:GetWidth(), 5, { 1, .72, .24 })
        glow:SetDrawLayer("ARTWORK")
        glow:SetBlendMode("ADD")
        local clearGold, brightGold = CreateColor(1, .72, .24, 0), CreateColor(1, .72, .24, .38)
        glow:SetGradient("VERTICAL", i == 1 and brightGold or clearGold, i == 1 and clearGold or brightGold)
        glow:Hide()
        chanceGlow[#chanceGlow + 1] = glow
    end
    local function pulse(self, elapsed)
        self.pulseTime = (self.pulseTime + elapsed) % 3
        local brightness = .675 - .125 * math.cos(self.pulseTime * 2 * math.pi / 3)
        for _, glow in ipairs(chanceGlow) do glow:SetAlpha(brightness) end
    end
    function chanceTrack:setGlow(enabled)
        if self.glowing == enabled then return end
        self.glowing, self.pulseTime = enabled, 0
        for _, glow in ipairs(chanceGlow) do glow:SetShown(enabled) end
        self:SetScript("OnUpdate", enabled and pulse or nil)
        if enabled then pulse(self, 0) end
    end
    local halo = ui.fill(chanceTrack, 28, 2, 1, 5, { 1, 1, 1 })
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
                ray.texture:SetPoint("BOTTOM", chanceRail, "TOPLEFT", width * ray.position, -1)
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
chanceTrack.scaleMarkers[3] = ui.text(chanceTrack, 28, 16, 45, 13, 10, "0 %", ui.muted)
chanceTrack.scaleMarkers[4] = ui.text(chanceTrack, 241, 16, 47, 13, 10, "100 %", ui.muted)
chanceTrack.scaleMarkers[4]:SetJustifyH("RIGHT")
chanceTrack.value = ui.text(chanceTrack, 68, 15, 180, 15, 11, "", ui.paper)
chanceTrack.value:SetJustifyH("CENTER")
chanceTrack.condition = ui.place(CreateFrame("Frame", nil, card), card, 12, 405, 196, 35)
chanceTrack.condition:EnableMouse(true)
chanceTrack.condition:SetScript("OnEnter", chanceTrack:GetScript("OnEnter"))
chanceTrack.condition:SetScript("OnLeave", hideOdds)
chanceTrack.condition:SetScript("OnHide", hideOdds)
local conditionWreath = chanceTrack.condition:CreateTexture(nil, "BORDER")
ui.place(conditionWreath, chanceTrack.condition, 0, -4, 43, 43)
conditionWreath:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\CollectionWreath.tga")
chanceTrack.condition.icon = ui.icon(chanceTrack.condition, 12, 8, 19, "Loot")
chanceTrack.condition.title = ui.text(chanceTrack.condition, 50, 0, 147, 18, 14, "Добыча", ui.gold)
ui.text(chanceTrack.condition, 50, 18, 147, 16, 11, "При выполнении условий", ui.muted)
chanceTrack.condition:Hide()
chanceTrack.background = ui.surface(card, 0, 400, card:GetWidth(), 46, false, "SourceCard")
for _, texture in ipairs(chanceTrack.background) do texture:Hide() end
chanceTrack.islandLabel = ui.text(card, 16, 407, 196, 31, 13, "", ui.paper)
chanceTrack.islandLabel:SetMaxLines(2)
chanceTrack.islandLabel:Hide()
chanceFill:SetDrawLayer("ARTWORK", 1)
chanceTrack:Hide()

function chanceTrack:setIslandMode(enabled)
    if self.islandMode == enabled then return end
    self.islandMode = enabled
    self.islandCount, self.islandRate = nil, nil
    self.islandLabel:SetShown(enabled)
    ui.setIcon(self.icon, enabled and "Loot" or "Chance")
end

function chanceTrack:setFill(probability, guaranteed)
    local fraction = probability and math.max(0, math.min(1, probability)) or 0
    local width = chanceRail:GetWidth()
    local fillWidth = math.min(guaranteed and width or width - 1, width * fraction)
    for _, tier in ipairs(ui.chances) do
        if fraction * 100 <= tier.limit then
            chanceFill:SetColorTexture(unpack(tier.color))
            self:setRays(fraction > .60 and fillWidth, not guaranteed, unpack(tier.color))
            break
        end
    end
    self:setGlow(guaranteed == true)
    chanceFill:SetWidth(math.max(.01, fillWidth))
    chanceFill:SetShown(fraction > 0)
end

function chanceTrack:setScaleShown(shown)
    for _, marker in ipairs(self.scaleMarkers) do marker:SetShown(shown) end
end

function atlas.refreshIslandExpeditionDetails()
    if not chanceTrack.islandMode or not chanceTrack:IsVisible() then return end
    local count, cumulative, perAttempt = atlas.islandExpeditionProgress(selected)
    chanceTrack.islandCount, chanceTrack.islandRate = count, perAttempt
    chanceTrack.islandLabel:SetText(count ~= nil and L("Попыток: %s", count) or "")
    local percent = cumulative ~= nil and probabilityText(cumulative):gsub("^≈ ", "") or ""
    chanceTrack.value:SetText(percent)
    chanceTrack:setScaleShown(cumulative ~= nil)
    chanceTrack:setFill(cumulative, false)
    if GameTooltip:IsOwned(chanceTrack) and chanceTrack:IsMouseOver() then
        chanceTrack:GetScript("OnEnter")(chanceTrack)
    end
end

local planButton = ui.action(card, 526, 408, 134, 31, "В план", nil, function(self)
    local mount = selected
    local planID = atlas.activePlanID()
    local added = atlas.togglePlan(mount, planID)
    atlas.refreshDetails()
    if added and selected == mount and planID == atlas.activePlanID() and self:IsVisible() then
        self:flashAdded(mount.id, planID)
    else self:clearFlash() end
end, nil, true)
do
    local glint = ui.place(CreateFrame("Frame", nil, planButton), planButton, 5, 0, 32, 2)
    glint:EnableMouse(false)
    local clear = CreateColor(1, .74, .30, 0)
    local bright = CreateColor(1, .88, .55, 1)
    local left = ui.fill(glint, 0, 0, 16, 2, { 1, 1, 1 })
    local right = ui.fill(glint, 16, 0, 16, 2, { 1, 1, 1 })
    left:SetGradient("HORIZONTAL", clear, bright)
    right:SetGradient("HORIZONTAL", bright, clear)
    function planButton:clearFlash()
        ui.stopTransition(glint)
        glint:Hide()
        self.flashMountID, self.flashPlanID = nil, nil
    end
    function planButton:flashAdded(id, planID)
        self.flashMountID, self.flashPlanID = id, planID
        glint:Show()
        ui.transition(glint, .32, function(t)
            if t >= 1 then self:clearFlash(); return end
            local x = 5 + (self:GetWidth() - glint:GetWidth() - 10) * t
            glint:ClearAllPoints()
            glint:SetPoint("TOPLEFT", self, "TOPLEFT", x, 0)
            glint:SetAlpha(math.min(1, t * 7, (1 - t) * 5))
        end)
    end
    planButton:HookScript("OnHide", planButton.clearFlash)
    planButton:clearFlash()
end
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

cardDetails = atlas.cardDetails(card, pagerArrow)
cardDetails:bindSourceLinks(detailArea)
function cardDetails.setSummaryPlace(value)
    local text = summary.place.value
    text:SetText(value or "—")
    local mapID = value and (cardDetails.navigationMap or atlas.sourceMapID(value, cardDetails.summaryPoint, cardDetails.sourceMapView))
    local clipped = text:IsTruncated() or text:GetUnboundedStringWidth() > text:GetWidth()
    summary.place.hitbox:setLocation(mapID, value, clipped, true)
    text:SetTextColor(unpack(mapID and ui.gold or ui.paper))
end
detailArea.skin = ui.sourceCardSurface(detailArea, 0, 0, card:GetWidth(), 86)
detailArea.skin:setRoute({ key = "quest" })
detailArea.rule = ui.fill(detailArea, 14, 28, card:GetWidth() - 28, 1, { .58, .53, .39, .45 })
detailArea.rule:SetDrawLayer("BORDER")
detailArea.icon = ui.icon(detailArea, 13, 4, 20, "Quest")
detailArea.heading = ui.text(detailArea, 40, 3, 285, 23, 15, "Квест", ui.paper)
detailArea.quest = ui.text(detailArea, 18, 32, card:GetWidth() - 36, 20, 15, "", ui.gold)
detailArea.quest:SetMaxLines(1)
detailArea.questCheck = ui.check(detailArea, card:GetWidth() - 40, 32)
detailArea.progress = ui.criteriaProgressBar(detailArea, card:GetWidth() - 203, 34)
function detailArea:cancelWeeklyTimer()
    if self.weeklyTimer then
        self.weeklyTimer:Cancel()
        self.weeklyTimer = nil
    end
end
detailArea:HookScript("OnHide", detailArea.cancelWeeklyTimer)
function detailArea:updateQuest(statusOnly)
    local quest = self.questSource
    local id = quest and (quest.finalQuest or quest.id)
    local complete = id and atlas.characterQuestCompleted(quest.weeklyFlag or id) == true
    if not (complete and quest.weeklyFlag) then
        self:cancelWeeklyTimer()
    elseif not self.weeklyTimer and C_Timer and C_Timer.NewTimer and C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local seconds = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if not (issecretvalue and issecretvalue(seconds)) and type(seconds) == "number" and seconds >= 0 then
            self.weeklyTimer = C_Timer.NewTimer(seconds + 1, function()
                self.weeklyTimer = nil
                if self:IsVisible() then self:updateQuest(true) end
            end)
        end
    end
    self.questCheck:SetShown(complete == true)
    if statusOnly or not quest then return end
    self.quest:SetWidth(card:GetWidth() - (self.progress:IsShown() and 241 or 66))
    local name = atlas.dataName(quest)
    self.quest:SetText(ui.questChainLink(id, name) or name)
end
function cardDetails:layoutNote(note)
    local questSource = self.finalQuest or self.sourceQuest
    if detailArea.sourceText ~= note or detailArea.questSource ~= questSource then detailArea:Hide() end
    detailArea.sourceText, detailArea.questSource = note, questSource
    local quest = questSource ~= nil
    local hasProgress = detailArea.progress:update(self.finalQuest and self.periodicDone, self.periodicTotal, self.finalQuest, self.chainGrant)
    detailArea:updateQuest()
    detail:SetText(atlas.cardItemIcons(atlas.sourceInlineLinks(note or "")))
    local hasNote = note ~= "" or quest
    local sourceBottom = self.endsAt + 5
    local top = sourceBottom + (quest and 10 or 2)
    local height = 0
    if hasNote then
        local inset = quest and 18 or 0
        local textY = hasProgress and 73 or quest and 53 or 2
        local width = quest and card:GetWidth() or 632
        detail:ClearAllPoints()
        ui.place(detail, detailArea, inset, textY, width - 2 * inset, 0)
        local textHeight = note ~= "" and math.min(58, math.ceil(detail:GetStringHeight())) or 0
        height = textY + textHeight + (quest and 10 or 4)
        detail:SetHeight(math.max(1, textHeight))
        detailArea:ClearAllPoints()
        ui.place(detailArea, card, quest and 0 or 16, top, width, height)
        if quest then detailArea.skin:setHeight(height) end
    end
    detailArea.skin:setShown(quest)
    detailArea.heading:SetShown(quest)
    detailArea.icon:SetShown(quest)
    detailArea.rule:SetShown(quest)
    detailArea.quest:SetShown(quest)
    detailArea:SetShown(hasNote)
    card:layoutSourcePanel(self.sourceClassification, hasNote and not quest and top + height + 7 or sourceBottom)
end
do
    local area = summary.kind.hitbox
    local defaultHover = area:GetScript("OnEnter")
    local defaultClick = area:GetScript("OnClick")
    local function formerQuestLink()
        local vendor = currentVendor()
        local quest = vendor and vendor.formerQuest
        if quest then
            return ui.questChainLink(quest.id, atlas.getLocale() == "enUS" and quest.englishName or quest.name)
        end
    end
    area:SetScript("OnEnter", function(self)
        local choice = currentChoice()
        local availability = selected and selected.availability
        local history = selected and choice and (choice.classification.state ~= "historical"
            or availability and availability.unique) and ui.sourceHistory(selected)
        local link = formerQuestLink()
        if link then
            history = ui.addRouteText(history or "", L("Раньше выдавался за задание %s", link))
        end
        if not history or history == "" then return defaultHover(self) end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(self.atlasSummaryValue:GetText())
        ui.tooltipLine(L("История"), unpack(ui.gold))
        ui.tooltipSourceText(history)
        if link then ui.tooltipLine(L("Нажми, чтобы открыть прежнее задание"), unpack(ui.muted)) end
        GameTooltip:Show()
    end)
    area:SetScript("OnClick", function(self, button)
        local richLink = button == "LeftButton" and formerQuestLink()
        local link = richLink and richLink:match("|H(quest:[^|]+)|h")
        if link then
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            if IsShiftKeyDown() then atlas.linkSource(richLink, self)
            else atlas.openSourceReference(richLink, self) end
        elseif defaultClick then defaultClick(self, button) end
    end)
end
function cardDetails:refreshLayout()
    local note = self:deduplicatePlace(self.note)
    if not self.finalQuest and self.item and self.item.name and not self.isQuestStep then note = "" end
    self:layoutNote(note)
end
local collectedFooterY = 390
local collectedState = atlas.collectedState(card, collectedFooterY)
local difficultyBadge = atlas.difficultyBadge(card)

function sourceRow:layout(offset)
    self.heading = 154 + (offset == 0 and 38 or 0)
    self.targetY = self.heading + 4
    self.bottom = self.heading
    self.hasLine = false
end
function sourceRow:fitTarget(text, width, showRow)
    source:SetText(text)
    self.hasLine = showRow
    self.bottom = self.heading + (showRow and 54 or 0)
    sourceButton:ClearAllPoints()
    ui.place(sourceButton, card, 16, self.targetY, math.max(54, width), 46)
end
do
    local guide = ui.button(card, 500, 210, 26, 26, function(self)
        if self.view then
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
            setFooter(atlas.openPlace(self.view))
        end
    end)
    ui.icon(guide, 4, 4, 18, "Book")
    guide:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L("Открыть в путеводителе"))
        GameTooltip:Show()
    end)
    guide:SetScript("OnLeave", hidePlaceTooltip)
    guide:SetScript("OnHide", hidePlaceTooltip)
    guide:Hide()
    function sourceRow:setGuideFallback(view, x)
        if guide.view ~= view then hidePlaceTooltip(guide) end
        guide.view = view
        if view then
            guide:ClearAllPoints()
            ui.place(guide, card, x, self.heading + 10, 26, 26)
        end
        guide:SetShown(view ~= nil)
    end
end

-- Keep each renderer below the client's Lua 5.1 upvalue limit. The browser
-- runtime accepts larger closures, so it cannot enforce this client constraint.
local function refreshHeader(collected, choices)
    collectedState:SetShown(collected)
    if collected then collectedState:update(selected) end
    local expansion = selected.expansion ~= "Classic" and selected.expansion or nil
    local event = expansionFilter and (expansionFilter.id == "LegionRemix" or expansionFilter.id == "PandariaRemix")
        and atlas.collectionCategory(selected) == expansionFilter.id and expansionFilter or nil
    local art, logo = event and event.art or expansion or "Azeroth", event and event.logo or expansion
    headerArt:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Headers\\" .. art .. ".tga")
    local textWidth, logoBottom = expansionLogo:layout(logo, event)
    card:revealArtwork(selected.id)
    local planID = not shared and atlas.activePlanID() or nil
    if planButton.flashMountID and (planButton.flashMountID ~= selected.id or planButton.flashPlanID ~= planID) then
        planButton:clearFlash()
    end
    local className = atlas.mountClassName(selected)
    local _, description = C_MountJournal.GetMountInfoExtraByID(selected.id)
    titleArea:layout(textWidth, logoBottom, atlas.displayMountName(selected), className, description)
    titleArea:updateQuality(selected)
    titleArea.refreshModelPreview()
    local included = planID and atlas.isPlanned(selected, planID)
    local canPlan = not shared and not collected and (included or atlas.canAddMountToPlan(selected, choices))
    planButton:SetShown(canPlan)
    planButton.caption:SetText(included and "Убрать из плана" or "+ В план")
    planButton:setActive(canPlan and not included)
end

local function refreshSources(collected, choices)
    local official = selected.journalOnly == true
    local differentMount = vendorMount ~= selected
    if differentMount then vendorIndex, vendorMount = 1, selected end
    sourceChoices = cardTabs:select(choices, differentMount)
    sourceRow:layout(cardTabs.bodyOffset)
    vendorIndex = math.max(1, math.min(vendorIndex, #sourceChoices))
    local choice, vendor, view = currentChoice(), currentVendor(), currentSource()
    local interaction = not vendor and isInteractionRoute(view)
    if not vendor and not interaction and not choice.contextOnly then
        if atlas.resolveSourceInstance then atlas.resolveSourceInstance(view) end
        if atlas.resolveSourceEncounter then atlas.resolveSourceEncounter(view) end
    end

    local navigationPoints, navigationKind = locations()
    locationIndex = math.max(1, math.min(locationIndex, #navigationPoints))
    local navigationPoint = navigationPoints[locationIndex]
    local point = pointLocation(navigationPoint, choice, view, vendor, navigationKind)
    sourceLocation = point
    local vendorPoint = vendor and navigationPoint
    local directQuestReward = atlas.directQuestReward(selected, choice)
    local questTarget = atlas.questRewardTarget(atlas.questNavigationReward(selected, choice),
        navigationKind == "quest" and navigationPoint or nil)
    sourceButton.questTarget = questTarget
    local target = questTarget and questTarget.boss or navigationKind ~= "quest" and (pointName(point, "boss") or (interaction and atlas.dataName(view.sourceRequirements))
        or (not interaction or view.boss ~= view.place) and pointName(view, "boss"))
    local navigationPlace = navigationPoint and atlas.sourcePlaceValue(pointName(navigationPoint, "place"), view.kind)
    local navigationMap = navigationPoint and atlas.mapName(navigationPoint.map)
    local placeName
    local directMap = navigationMap and navigationPoint.map or nil
    if vendorPoint then
        placeName = atlas.sourcePlaceValue(vendorPoint.place, "Торговец") or navigationMap
    elseif navigationKind == "entrance" then
        -- The outdoor waypoint leads to the instance. The header names the source inside it.
        placeName = atlas.sourcePlaceValue(view.place, view.kind) or navigationPoint.boss or navigationPlace
        directMap = nil
    elseif navigationKind then
        placeName = navigationPlace or navigationMap
    else
        placeName = navigationPlace or navigationMap or atlas.sourcePlaceValue(view.place, view.kind)
    end
    local summaryPlace = placeName and atlas.summaryLocationName(view, placeName)
    local address, addressSource, addressMapID
    if not navigationKind and not vendor then
        address, addressSource, addressMapID = ui.sourceAddress(view.journalSourceOverride or view.journalSourceRaw, summaryPlace)
        if directMap and addressMapID and addressMapID ~= directMap then address, addressSource, addressMapID = nil, nil, nil end
    end
    summaryPlace = address or summaryPlace
    local route = choice.classification
    if point and not vendor and not choice.contextOnly then
        choice.point = point
        local pointRoute = atlas.classifyMountSource(selected, choice)
        if pointRoute.key == route.key then route, choice.classification = pointRoute, pointRoute end
    end
    local historical = route.state == "historical"
    local item = atlas.lootItems[selected.id]
    local namedTarget = target and target ~= "" and target ~= view.kind and target ~= view.sourceKind
        and not ui.sameSourceAddress(target, summaryPlace)
        and not (item and (item.basis == "open" or item.basis == "cage") and ui.sourceItemMatches(target, item))
    local raidReagent = route.subtype == "Сбор предметов" and view.sourceKind == "Босс" and view.sourcePlaceKind == "Рейд"
        and atlas.accountLootSources and atlas.accountLootSources[selected.id]
    local reagentSource = raidReagent or route.subtype == "Сбор предметов" and point and point.npc
    local structured = not historical and (vendor ~= nil or namedTarget and (questTarget or interaction or route.key == "loot" or reagentSource))
    local showTarget = structured and (vendor ~= nil or namedTarget)
    local targetText = vendor and groupName(vendorPoint or vendor) or showTarget and atlas.displayName(target, "target") or ""
    local encounterLink = not vendor and not questTarget and showTarget and view.journalEncounter
    local showNavigation = not historical and (navigationPoint and navigationPoint.navigation ~= false
        and atlas.hasSourceCoordinates(navigationPoint) or #navigationPoints > 1)
    local showPager = #sourceChoices > 1 and not cardTabs.hasRouteTabs

    local progress = not vendor and not interaction and view.trackingCompatible ~= false
        and atlas.planOpportunityProgress and atlas.planOpportunityProgress(selected, UnitGUID("player"))
    local multipleSources = progress and progress.totalAttempts > 1
    if progress and not multipleSources then
        for _, entry in ipairs(progress.entries or {}) do
            if #entry.npcs > 1 then multipleSources = true; break end
        end
    end
    local showProgress = showTarget and not collected and multipleSources == true and progress.totalAttempts > 0
    sourceProgress.progress = showProgress and progress or nil
    sourceProgress:SetShown(showProgress == true)
    if showProgress then
        sourceProgress.label:SetText(progress.completedAttempts .. " / " .. progress.totalAttempts)
        sourceProgress.label:SetTextColor(unpack(progress.completedAttempts > 0 and ui.mint or ui.muted))
    end

    local targetY, right = sourceRow.targetY, card:GetWidth() - 16
    difficultyBadge:update(view, card, "TOPLEFT", right, -targetY - 9, selected)
    if historical or vendor or interaction or selected.availability then
        difficultyBadge:Hide()
        view.difficultyBadgeVisible, view.difficultyBadgeWidth = false, 0
    end
    selected.difficultyBadgeVisible, selected.difficultyBadgeWidth = view.difficultyBadgeVisible, view.difficultyBadgeWidth
    if view.difficultyBadgeVisible then right = right - view.difficultyBadgeWidth - 10 end
    if showNavigation then right = right - navigationReserve end
    placeArea:updateNavigation(showNavigation and navigationPoint or nil, showNavigation and #navigationPoints or 0,
        navigationPoints, right, targetY)
    if showProgress then
        right = right - 68
        sourceProgress:ClearAllPoints()
        ui.place(sourceProgress, card, right, targetY + 13, 62, 22)
    end
    sourcePager:SetShown(showPager)
    counter:SetText(showPager and (vendorIndex .. " / " .. #sourceChoices) or "")
    local showGuide = not encounterLink and placeLink() and not (directMap or atlas.sourceMapID(summaryPlace, navigationPoint, view))
    if showGuide then right = right - 32 end
    sourceRow:setGuideFallback(showGuide and view or nil, right)
    local showRow = showTarget or showNavigation or showGuide or view.difficultyBadgeVisible
    sourceRow.sourceRight = right
    sourceRow:fitTarget(targetText .. (encounterLink and "  ›" or ""), right - 26, showRow)
    local container = route.key == "loot" and not (historical or vendor or choice.blackMarket or choice.contextOnly or choice.islandExpedition)
        and atlas.mountRewardContainerRewards and atlas.mountRewardContainerRewards[selected.id]
    summary.openingChance = container and 1 / container.contentsRate or nil
    local outcomeText = container and (atlas.getLocale() == "enUS" and container.englishText or container.text)
    containerOutcome:SetText(outcomeText or "")
    containerOutcome:SetShown(outcomeText ~= nil and outcomeText ~= "")
    if outcomeText and outcomeText ~= "" then
        ui.place(containerOutcome, card, 16, sourceRow.bottom + 5, right - 32, 20)
        sourceRow.bottom = sourceRow.bottom + 29
    end

    cardDetails.questChain, cardDetails.chainGrant = choice.questChain, choice.chainGrant
    cardDetails.progressChoice = choice
    cardDetails.directQuestReward = directQuestReward
    cardDetails.collected = collected
    cardDetails.structured = structured
    cardDetails.sourcePresentation = showTarget and { target = targetText, place = placeName, points = point and navigationPoints or nil }
    cardDetails.summaryPlace = summaryPlace
    cardDetails.navigationMap = directMap
    cardDetails.summaryPoint = addressMapID and { map = addressMapID, place = summaryPlace } or navigationPoint
    cardDetails.sourceMapView, cardDetails.addressSource, cardDetails.sourceRow = view, addressSource, sourceRow
    cardDetails.sourceClassification, cardDetails.routeRequirement = route, choice.requirementText
    cardDetails.interaction, cardDetails.sourceRequirements = interaction, interaction and view.sourceRequirements or nil
    cardDetails.factionPoint = not vendor and point or nil
    cardDetails.note = not interaction and (choice.questStep or not vendor and not choice.verifiedDrop and not choice.compact)
        and L(selected.note) or ""
    cardDetails.isQuestStep = choice.questStep
    local chain = choice.questChain
    cardDetails.finalQuest = chain and choice.chainGrant and chain.finalQuest and not chain.stageTitle and chain or nil
    cardDetails.sourceQuest = atlas.sourceCardQuest(selected, choice)
    cardDetails.bodyEnd = collected and collectedFooterY - 6 or 395
    if cardDetails.finalQuest then cardDetails.bodyEnd = cardDetails.bodyEnd - 108
    elseif cardDetails.sourceQuest then cardDetails.bodyEnd = cardDetails.bodyEnd - 78
    elseif cardDetails.note ~= "" then cardDetails.bodyEnd = cardDetails.bodyEnd - 76 end
    local activeOffer = vendor and vendor.groupedLocations and vendorPoint or vendor
    cardDetails:update(selected, not interaction and selected.locations and point, activeOffer, choice.view)
    summary:updateRespawn(choice, view, point, navigationKind, cardDetails.sourcePageCount > 1)

    sourceButton:SetWidth(math.max(54, sourceButton:GetWidth() - cardDetails.sourceInset))
    sourceButton:SetShown(showTarget)
    local sourceText, glyph = ui.sourceAppearance(route)
    local unique = historical and selected.availability and selected.availability.unique
    if unique then sourceText, glyph = "Уникальный", "Book" end
    sourceButton:updatePortrait(showTarget, selected, vendorPoint or vendor or questTarget or view, not vendor and not questTarget and point or nil,
        questTarget and "QuestGiver" or raidReagent and "Boss" or choice.islandSalvage and "Vendor" or glyph)
    refreshBossCheck(view, showTarget and not vendor and not interaction,
        not interaction and selected.locations and point, progress)
    sourceButton:updateHitbox(showTarget)
    summary.kind.value:SetText(sourceText)
    summary.kind.value:SetTextColor(unpack(unique and ui.gold or ui.paper))
    local sellerFaction = vendorPoint and vendorPoint.faction or vendor and vendor.faction
    local factionLabel = sellerFaction == "Alliance" and L("Альянс") or sellerFaction == "Horde" and L("Орда")
    summary.place.label:SetText(factionLabel and L("Место") .. " · " .. factionLabel or "Место")
    summary:setIcon("kind", glyph)
    summary.kind.hitbox:updateBounds(true)
    local status = summary.status
    local unavailable = historical or route.stock == "outOfRotation"
    summary:setIcon("status", collected and "ObjectiveComplete" or unavailable and "Lock" or "Bookmark")
    status.icon:SetDesaturated(not collected and not unavailable)
    if collected or unavailable then
        status.icon:SetVertexColor(unpack(collected and ui.mint or ui.muted))
    else
        status.icon:SetVertexColor(.85, .85, .85)
    end
    status.value:SetText(collected and "В коллекции" or unavailable and "Недоступно" or "Не получен")
    status.value:SetTextColor(unpack(collected and ui.mint or ui.muted))
    status.hitbox:updateBounds(true)

    cardDetails:refreshLayout()
    return vendor, view, official
end

local function refreshChance(collected, vendor, view, official)
    local interaction = not vendor and isInteractionRoute(view)
    local conditionalReward = interaction and view.sourceRequirements and view.sourceRequirements.guarantee
    local chain = atlas.questAcquisitionChain(selected)
    local choice = currentChoice()
    local raidGuarantee = atlas.raidLootGuaranteeForSource(selected, choice)
    local directQuestReward = cardDetails.directQuestReward
    summary.raidGuarantee = raidGuarantee
    local chainReward = not collected and not vendor and not selected.availability and atlas.questChainGuaranteedReward(choice)
    summary.chainReward = chainReward
    summary.directQuestReward = not collected and not selected.availability and directQuestReward or nil
    summary.sourceGuarantee = not collected and not (chainReward or directQuestReward or conditionalReward)
        and atlas.sourceGuaranteedReward(selected, choice) or nil
    local routeGuarantee = summary.chainReward or summary.directQuestReward or summary.sourceGuarantee
    local starterChance = cardDetails.starterChance
    summary.starterChance, summary.starterRateEstimated = starterChance, cardDetails.starterRateEstimated
    local perAttempt, cumulative, attempts
    local rollForMount = not (interaction or vendor or chain or directQuestReward or summary.sourceGuarantee
        or choice.blackMarket or choice.islandExpedition or choice.factionGift)
    local trackingCompatible = not interaction and view.trackingCompatible ~= false
    local rewardProgress = trackingCompatible and rollForMount
        and atlas.rewardAttemptProgress and atlas.rewardAttemptProgress(selected, choice.attemptStage)
    if choice.attemptStage then
        if rewardProgress then
            perAttempt, cumulative, attempts = rewardProgress.perAttempt, rewardProgress.cumulative, rewardProgress.attempts
        end
    elseif rollForMount then
        perAttempt, cumulative, attempts = atlas.dropProbability(selected)
    end
    displayedInteraction = conditionalReward ~= nil and conditionalReward ~= false
    displayedReward = conditionalReward or rollForMount and atlas.guaranteedRewards and atlas.guaranteedRewards[selected.id]
    if displayedReward then perAttempt, cumulative, attempts = 1, nil, nil end
    displayedAttempts = attempts
    displayedPerAttempt = perAttempt
    local guaranteed = raidGuarantee ~= nil or routeGuarantee ~= nil or perAttempt == 1
    displayedProbability = guaranteed and 1 or cumulative

    local chanceEligible = not atlas.rewardChanceEligible or atlas.rewardChanceEligible(selected, vendor ~= nil)
    local sharedRaidLoot = atlas.raidLootReward and atlas.raidLootReward(selected)
    local definitions = atlas.attemptStages and atlas.attemptStages[selected.id]
    local reward = not choice.attemptStage and definitions and definitions.reward
    local estimate = reward and reward.rarityEncounterEstimate and atlas.kills(selected)
    local showChance = (displayedInteraction or trackingCompatible) and not selected.availability and not vendor and not sharedRaidLoot
        and perAttempt ~= nil and (displayedReward ~= nil or chanceEligible)
    summary.rewardRateEstimated = showChance and rollForMount and not guaranteed
        and (rewardProgress and rewardProgress.rateEstimated or reward and reward.rateEstimated)
    local sourceKey = cardDetails.sourceClassification.key
    local hasRewardAttempts = type(attempts) == "number" or rewardProgress and type(rewardProgress.attempts) == "number"
    local trackedRoute = sourceKey == "loot" or sourceKey == "fishing" or hasRewardAttempts
    local showKills = not raidGuarantee and trackedRoute and rollForMount and trackingCompatible
        and (rewardProgress and rewardProgress.event == "MOUSEOVER" or not guaranteed and chanceEligible)
        and not collected and not selected.availability
        and (hasRewardAttempts or type(estimate) == "number" or rewardProgress ~= nil
            or not official or atlas.killStatistics[selected.id] ~= nil)
    local showProgress = not collected and displayedProbability ~= nil and (raidGuarantee ~= nil or routeGuarantee ~= nil or showChance)
    local showIslandAttempts = not collected and (choice.islandExpedition == true or choice.islandSalvage ~= nil)
        and atlas.islandExpeditionProgress ~= nil
    local directGuarantee = summary.directQuestReward ~= nil or summary.sourceGuarantee and summary.sourceGuarantee.method == "barter"
    local hasChance = raidGuarantee ~= nil or showChance or directGuarantee or starterChance ~= nil or summary.openingChance ~= nil
    oddsArea:SetShown(hasChance)
    oddsArea:SetScript("OnEnter", (raidGuarantee or directGuarantee) and chanceTrack:GetScript("OnEnter") or summary.showOdds)
    local finalRewardChance = directGuarantee or displayedReward and displayedReward.reagent and not starterChance
    summary.chance.label:SetText(summary.openingChance and "Шанс при открытии" or raidGuarantee and "Добыча рейда" or finalRewardChance and "Награда" or "Шанс")
    summary.chance.value:SetText(summary.openingChance and probabilityText(summary.openingChance) or starterChance and probabilityText(starterChance) or (raidGuarantee or directGuarantee) and probabilityText(1, true)
        or showChance and probabilityText(perAttempt, perAttempt == 1) or "")
    summary:layout(cardDetails.activeSummaryPlace ~= nil and cardDetails.activeSummaryPlace ~= "", hasChance)
    cardDetails.setSummaryPlace(cardDetails.activeSummaryPlace)
    chanceTrack:setIslandMode(showIslandAttempts)
    killsHelp.riftProgress = showKills and rewardProgress and rewardProgress.finals ~= nil and rewardProgress or nil
    local barProbability = killsHelp.riftProgress and killsHelp.riftProgress.referenceCumulative or showProgress and displayedProbability or nil
    for _, texture in ipairs(chanceTrack.background) do texture:SetShown(showProgress or showKills or showIslandAttempts) end
    chanceTrack:SetShown(barProbability ~= nil or showIslandAttempts)
    local showCondition = showProgress and guaranteed and not showKills
    local conditionTitle, conditionIcon = "Добыча", "Loot"
    if raidGuarantee then
        conditionTitle = "Добыча рейда"
    elseif summary.sourceGuarantee or directGuarantee or chainReward and cardDetails.sourceClassification.key == "quest" then
        conditionTitle, conditionIcon = ui.sourceAppearance(cardDetails.sourceClassification)
    end
    chanceTrack.condition.title:SetText(conditionTitle)
    ui.setIcon(chanceTrack.condition.icon, conditionIcon)
    chanceTrack.condition:SetShown(showCondition)
    if showIslandAttempts then
        atlas.refreshIslandExpeditionDetails()
    else
        chanceTrack.value:SetText(barProbability ~= nil and probabilityText(barProbability, guaranteed) or "")
        chanceTrack:setScaleShown(true)
        chanceTrack:setFill(barProbability, showProgress and guaranteed)
    end
    kills:SetShown(showKills)
    killsHelp:SetShown(showKills or showIslandAttempts)
    attemptsLabel:SetShown(showKills)
    attemptsIcon:SetShown(showKills)
    killsHelp.encounterEstimate = estimate and reward.condition or nil
    local localBossCounter = not rewardProgress and not selected.npcs and not atlas.usesKillAPI(selected)
    attemptsLabel:SetText(summary.openingChance and "Попыток с добычей" or estimate and "Rarity" or rewardProgress and "Попытки:" or selected.npcs and "Попыток с добычей"
        or localBossCounter and "Учтено убийств" or "Убийств босса")
    killsHelp.count = showKills and (estimate or attempts or rewardProgress and rewardProgress.attempts
        or atlas.kills(selected)) or nil
    kills:SetText(showKills and tostring(killsHelp.count or "—") or "")
end

function cardDetails:refreshReward()
    refreshChance(self.collected, currentVendor(), currentSource(), selected.journalOnly == true)
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
    local showingWaypoint = ui.tooltipOwnerIn(waypoint) == waypoint
    catalog:redraw()
    if not selected or catalog.loading and catalog.wantsPlan then sourceLocation = nil; card:Hide(); return end
    local collected = atlas.collection and atlas.collection.byID[selected.id]
    if type(collected) ~= "boolean" then
        local owned = select(11, C_MountJournal.GetMountInfoByID(selected.id))
        if (issecretvalue and issecretvalue(owned)) or type(owned) ~= "boolean" then card:Hide(); return end
        collected = owned
    end
    card:Show()
    local choices = buildSourceChoices(selected)
    refreshHeader(collected, choices)
    refreshChance(collected, refreshSources(collected, choices))
    if showingWaypoint and waypoint:IsVisible() and waypoint:IsMouseOver() then waypoint:refreshTooltip() end
    local owner = ui.tooltipOwnerIn(card)
    if owner and (owner == sourceButton.hitbox or owner == sourceProgress or owner == summary.respawn
        or owner == oddsArea or owner == chanceTrack or owner == chanceTrack.condition or owner == killsHelp
        or owner == loreArea or owner == summary.kind.blackMarket or owner.atlasSummaryValue)
        and owner:IsVisible() then
        if owner:IsMouseOver() then owner:GetScript("OnEnter")(owner)
        else GameTooltip:Hide() end
    end
end

local function selectMount(mount, queryChanged)
    if selected ~= mount or queryChanged then
        ui.hideTooltipIn(card, summary.kind.blackMarket)
        locationIndex = 1
        if searchQuery.key ~= "" and mount and mount.locations then
            for i, loc in ipairs(atlas.mountLocations(mount, UnitGUID("player"), true)) do
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
    if not atlas.mountModifiedClick(mount) then selectMount(mount) end
end
function catalog:updateFavorite(row)
    row.favorite:SetShown(not shared and row.item ~= nil and ui.mountFavorite(row.item.id) == true)
end
catalog:RegisterEvent("MOUNT_JOURNAL_SEARCH_UPDATED")
catalog:SetScript("OnEvent", function(self)
    if shared or not self:IsVisible() then return end
    for _, row in ipairs(self.rows) do
        if row.item then self:updateFavorite(row) end
    end
end)
function atlas.refreshMountQualities()
    if not frame:IsShown() or not page:IsShown() then return end
    catalog:redraw()
    if selected then titleArea:updateQuality(selected) end
    if collectedState:IsShown() then collectedState:updateQuality() end
end
local function colorCatalogRow(row)
    local r, g, b = .129, .133, .243
    if row.selected then r, g, b = .145, .12, .24 end
    if row.hovered then
        r, g, b = r * .94 + .06, g * .94 + .06, b * .94 + .06
    end
    for _, texture in ipairs(row.bg) do texture:SetVertexColor(r, g, b) end
end
function catalog:refreshRowHistory(row)
    local mount = row.item
    local history = mount and mount.availability and mount.availability.unique and ui.sourceHistory(mount)
    if not history or history == "" or not row:IsMouseOver() then
        if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    ui.tooltipTitle(atlas.displayMountName(mount))
    ui.tooltipLine(L("История"), unpack(ui.gold))
    ui.tooltipSourceText(history)
    GameTooltip:Show()
end
function catalog:makePlanMarker(row)
    local holder = ui.place(CreateFrame("Frame", nil, row), row, 240, 11, 19, 19)
    holder:EnableMouse(false)
    local icon = ui.icon(holder, 0, 0, 19, "Route")
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", holder, "CENTER")
    icon:SetVertexColor(unpack(ui.gold))
    icon:Hide()

    local mountID, planID, owned
    local amount, target = 0, 0
    local function draw(value)
        amount = value
        local size = 13 + 6 * value
        icon:SetSize(size, size)
        icon:SetAlpha(value)
        icon:SetShown(value > 0)
    end
    local function finish()
        ui.stopTransition(holder)
        draw(target)
        row.name:SetWidth((owned or target == 1) and 187 or 209)
    end
    row:HookScript("OnHide", finish)
    function row:updatePlanMarker(id, plan, planned, collected)
        owned = collected
        local nextTarget = planned and 1 or 0
        if mountID ~= id or planID ~= plan or not self:IsVisible() then
            mountID, planID, target = id, plan, nextTarget
            finish()
        elseif target ~= nextTarget then
            target = nextTarget
            local start = amount
            if start == target then
                finish()
                return
            end
            self.name:SetWidth(187)
            local duration = (planned and .18 or .15) * math.abs(target - start)
            ui.transition(holder, duration, function(t)
                draw(start + (target - start) * t)
                if t == 1 then self.name:SetWidth((owned or planned) and 187 or 209) end
            end)
        else
            self.name:SetWidth((owned or planned or amount > 0) and 187 or 209)
        end
    end
end

function catalog:render(row, mount)
    local active = mount == selected
    local r, g, b = atlas.qualityColor(atlas.mountDisplayQuality(mount.id))
    row.icon:SetTexture(mount.icon or 134400)
    if r then
        row.iconBorder:SetColorTexture(r, g, b)
        row.name:SetTextColor(r, g, b)
    else
        row.iconBorder:SetColorTexture(unpack(ui.rule))
        row.name:SetTextColor(unpack(ui.paper))
    end
    row.selected = active
    colorCatalogRow(row)
    local owned = atlas.collection and atlas.collection.byID[mount.id] == true
    local planID = not shared and not owned and atlas.activePlanID() or nil
    local planned = planID and atlas.isPlanned(mount, planID)
    row.bookmark:SetShown(owned)
    self:updateFavorite(row)
    row:updatePlanMarker(mount.id, planID, planned, owned)
    local killed = atlas.isKilled(mount)
    local status = owned and (killed and "В коллекции  ·  Босс убит" or "В коллекции") or (killed and "Босс убит" or "")
    local unique = mount.availability and mount.availability.unique
    if unique then
        status = status ~= "" and (L(status) .. "  ·  " .. L("Уникальный")) or "Уникальный"
    end
    row.status:SetText(status)
    row.status:SetTextColor(unpack(owned and ui.mint or unique and ui.gold or ui.muted))
    row.name:SetHeight(status == "" and 40 or 22)
    row.name:SetMaxLines(status == "" and 2 or 1)
    row.line:SetShown(active)
    for _, texture in ipairs(row.selection) do texture:SetShown(active) end
    row.name:SetText(atlas.displayMountName(mount))
    if row.refreshModelPreview then row.refreshModelPreview() end
    if GameTooltip:IsOwned(row) then self:refreshRowHistory(row) end
end
for _, row in ipairs(catalog.rows) do
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
        if button == "RightButton" then ui.openMountMenu(self)
        else catalog:onClick(self.item) end
    end)
    row.bg = ui.surface(row, 0, 0, 264, 42, false, "RoundedFill")
    row:GetHighlightTexture():SetAlpha(0)
    row:HookScript("OnEnter", function()
        row.hovered = true
        colorCatalogRow(row)
        catalog:refreshRowHistory(row)
    end)
    local function clearRowHover()
        row.hovered = false
        colorCatalogRow(row)
        if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
    end
    row:HookScript("OnLeave", clearRowHover)
    row:HookScript("OnHide", clearRowHover)
    row.selection = ui.surface(row, 0, 0, 264, 42, false, "OrnateOutline")
    for _, texture in ipairs(row.selection) do
        texture:SetDrawLayer("BACKGROUND", 2)
    end
    row.line = ui.fill(row, 1, 5, 2, 32, ui.gold)
    row.line:SetDrawLayer("BORDER")
    row.icon, row.iconBorder = ui.squareIcon(row, 5, 3, 36, ui.rule)
    row.icon:SetTexCoord(.07, .93, .07, .93)
    row.favorite = row:CreateTexture(nil, "OVERLAY")
    row.favorite:SetAtlas("PetJournal-FavoritesIcon", true)
    row.favorite:SetPoint("CENTER", row.iconBorder, "TOPLEFT")
    row.favorite:Hide()
    row.name = ui.text(row, 48, 1, 209, 40, 15, "")
    row.name.atlasGameText = true
    row.bookmark = row:CreateTexture(nil, "ARTWORK")
    ui.place(row.bookmark, row, 240, 0, 18, 22)
    row.bookmark:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\Bookmark.tga")
    catalog:makePlanMarker(row)
    row.status = ui.text(row, 48, 22, 187, 16, 11, "", ui.muted)
    bindHover(row, function() return row.item end)
end

local lastKey, lastFilter, lastSourceFilter, lastSourceSubtype, lastFrequency, lastExpansion
local lastCollection
function catalog:matchesCollection(id)
    if shared and shared.byID[id] ~= true then return false end
    if activeFilter == 1 then return true end
    local owned = atlas.collection and atlas.collection.byID[id]
    return owned == (activeFilter == 2 or activeFilter == 4)
end

refresh = function(preferredMount)
    searchQuery = atlas.searchQuery(search:GetText())
    local key = searchQuery.key .. "\n" .. (searchQuery.layout or "")
    hint:SetShown(search:GetText() == "" and not search:HasFocus())
    clear:SetShown(search:GetText() ~= "" or expansionFilter ~= nil)
    hint:SetText(expansionFilter and expansionFilter.name or "Имя, босс или место")
    catalog.loadingLabel:SetShown(catalog.loading)
    if catalog.loading then
        found:SetText("")
        collectionStatus:Hide()
        collectionBadge.count:SetText("—")
        collectionBadge.fill:Hide()
        showEmpty(false)
        if not preferredMount and not selected and not shared and not catalog.wantsPlan and activeFilter == 1
            and searchQuery.key == "" and not (sourceFilter or sourceSubtype or frequency or expansionFilter) and atlas.mounts[1] then
            preferredMount = atlas.resolveJournalMount(atlas.mounts[1].id)
            catalog.loadingPreview = preferredMount
        end
        selectMount(preferredMount or selected)
        return
    end
    local collection = atlas.collection
    if sourceMenu.journalRevision ~= atlas.journalSourceRevision then
        sourceMenu.journalRevision, sourceMenu.categories = atlas.journalSourceRevision, nil
        catalog.needsRefresh = true
    end
    local queryChanged = lastKey ~= key
    local sortMode = catalog:sortMode()
    local ordered = atlas.sortedCatalogMounts(sortMode)
    local filtersChanged = queryChanged or catalog.lastSortMode ~= sortMode or lastFilter ~= activeFilter or lastSourceFilter ~= sourceFilter
        or lastSourceSubtype ~= sourceSubtype or lastFrequency ~= frequency or lastExpansion ~= expansionFilter
    if not filtersChanged and not catalog.needsRefresh and collection == lastCollection and catalog.lastOrder == ordered then
        selectMount(preferredMount or selected)
        return
    end
    if catalog.needsRefresh or collection ~= lastCollection then
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
    local allSources = not sourceSubtype and not frequency and not sourceFilter and not expansionFilter
    sourceMenu.all:SetShown(allSources)
    for _, category in ipairs(sourceCategories) do
        sourceMenu[category.key]:SetShown(sourceFilter == category.key)
    end
    sourceMenu.rare:SetShown(sourceSubtype == "rare")
    sourceMenu.raid:SetShown(sourceSubtype == "raid")
    sourceMenu.daily:SetShown(frequency == "daily")
    sourceMenu.weekly:SetShown(frequency == "weekly")
    sourceMenu:setFiltered(not allSources)
    catalog.lastOrder = ordered
    local matches, wanted, keep = ordered, preferredMount or selected, false
    if wanted == catalog.loadingPreview and not preferredMount and not catalog.revealAfterLoading then wanted = nil end
    catalog.loadingPreview = nil
    if not shared and activeFilter == 1 and allSources and searchQuery.key == "" then
        keep = wanted and atlas.mountByID(wanted.id) == wanted
    else
        matches = {}
        for _, mount in ipairs(ordered) do
            if catalog:matchesCollection(mount.id)
                and (not sourceSubtype or (sourceSubtype == "rare" and mount.locations and mount.kind ~= "Исследование")
                or (sourceSubtype == "raid" and (mount.isRaid or mount.kind == "Рейд")))
                and atlas.matchesSearch(mount.key, searchQuery)
                and (not expansionFilter or atlas.collectionCategory(mount) == expansionFilter.id)
                and (not frequency or mount.questFrequency == frequency or atlas.lootFrequency(mount) == frequency)
                and sourceMenu:matches(mount, sourceFilter) then
                matches[#matches + 1] = mount
                if wanted == mount then keep = true end
            end
        end
    end
    catalog.needsRefresh = nil
    catalog.lastSortMode = sortMode
    if filtersChanged then catalog:resetScroll() end
    lastExpansion = expansionFilter
    lastKey, lastFilter, lastSourceFilter, lastSourceSubtype, lastFrequency = key, activeFilter, sourceFilter, sourceSubtype, frequency
    catalog.items = matches
    local n = #matches
    showEmpty(n == 0 and not collectionStatus:IsShown())
    found:SetText(collectionStatus:IsShown() and "" or tostring(n))
    selectMount(keep and wanted or matches[1], queryChanged)
    if catalog.revealAfterLoading then
        if selected == catalog.revealAfterLoading then catalog:reveal(selected) end
        catalog.revealAfterLoading = nil
    end
end

local function searchChanged() refresh() end
local function setCatalogSearch(value)
    search:SetScript("OnTextChanged", nil)
    search:SetText(value)
    search:SetScript("OnTextChanged", searchChanged)
end

local function openCatalogMount(mount)
    if shared then returnToCollection() end
    activeFilter = 1
    sourceSubtype, frequency = nil, nil
    sourceFilter = nil
    expansionFilter = nil
    setCatalogSearch("")
    showPage(false, mount)
    if mount then
        if catalog.loading then catalog.revealAfterLoading = mount else catalog:reveal(mount) end
    else search:SetFocus() end
end

function atlas.openMountCard(mountID)
    if type(mountID) ~= "number" then return false end
    local mount = atlas.resolveJournalMount(mountID)
    if not mount then return false end
    openCatalogMount(mount)
    return true
end

local function openExpansion(expansion)
    expansionFilter = expansion
    activeFilter, sourceSubtype, frequency, sourceFilter = expansion.event and 1 or 3, nil, nil, nil
    setCatalogSearch("")
    showPage(false)
end
local function refreshJournal(mount)
    if not frame:IsShown() or (settings and settings:IsShown()) then return end
    catalog.loading = not atlas.prepareJournal()
    local plan = catalog.wantsPlan and not catalog.loading
    if plan and not planner then planner = atlas.makePlanner(frame, openCatalogMount, openExpansion) end
    if plan and not planner:IsShown() then RequestRaidInfo() end
    local pageChanged = page:IsShown() == plan
    page:SetShown(not plan)
    if planner then planner:SetShown(plan) end
    if pageChanged then setFooter() end
    if plan then
        atlas.refreshPlanSnapshot()
        planner:update()
    else refresh(mount) end
end
showPage = function(plan, mount)
    catalog.wantsPlan = plan == true and not shared
    if settings then settings:Hide() end
    settingsTab:setActive(false)
    search:ClearFocus()
    setFooter()
    planTab:setActive(catalog.wantsPlan)
    catalogTab:setActive(not catalog.wantsPlan)
    if mount and not frame:IsShown() then
        selectMount(mount)
        frame:Show()
    else refreshJournal(mount) end
end
search:SetScript("OnTextChanged", searchChanged)
local function fitWindow()
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    local previous = frame:GetScale()
    if width <= 24 or height <= 24 then return previous end
    local scale = math.min(atlas.windowScale() / 100, (width - 24) / w, (height - 24) / h)
    if scale ~= previous then
        local x, y = frame:GetCenter()
        local parentX, parentY = UIParent:GetCenter()
        if x and y and parentX and parentY then
            local roomX, roomY = (width - w * scale) / 2, (height - h * scale) / 2
            local offsetX = math.max(-roomX, math.min(roomX, x * previous - parentX))
            local offsetY = math.max(-roomY, math.min(roomY, y * previous - parentY))
            frame:ClearAllPoints()
            frame:SetScale(scale)
            frame:SetPoint("CENTER", UIParent, "CENTER", offsetX / scale, offsetY / scale)
        else
            frame:SetScale(scale)
        end
    end
    local effectiveScale = frame:GetEffectiveScale()
    local ruleHeight = PixelUtil and PixelUtil.GetNearestPixelSize
        and PixelUtil.GetNearestPixelSize(1, effectiveScale, 1) or math.max(1, 1 / effectiveScale)
    for _, line in ipairs(footerRules) do line:SetHeight(ruleHeight) end
    if atlas.refreshWindowScaleSetting then atlas.refreshWindowScaleSetting(scale) end
    return scale
end
local function normalizeWindowScale(value)
    if type(value) ~= "number" or value ~= value then return 100 end
    return math.max(minimumWindowScale, math.min(maximumWindowScale, math.floor(value / 5 + .5) * 5))
end
function atlas.windowScale()
    local account = MountAtlasAccountDB
    local saved = type(account) == "table" and account.settings
    return normalizeWindowScale(type(saved) == "table" and saved.windowScale)
end
function atlas.setWindowScale(value)
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    local account = MountAtlasAccountDB
    if type(account.settings) ~= "table" then account.settings = {} end
    account.settings.windowScale = normalizeWindowScale(value)
    return fitWindow()
end
function atlas.effectiveWindowScale()
    return frame:GetScale()
end
function atlas.onJournalChanged() refreshJournal() end
function atlas.onCatalogAttemptsChanged()
    if catalog.attemptSortPending or not page:IsVisible() or catalog:sortMode() ~= "attemptChance" then return end
    catalog.attemptSortPending = true
    C_Timer.After(.1, function()
        catalog.attemptSortPending = nil
        if page:IsVisible() and catalog:sortMode() == "attemptChance" then refresh() end
    end)
end
function atlas.refreshSourceRoutes()
    sourceMenu.categories = nil
    catalog.needsRefresh = true
    if page:IsVisible() then refresh() end
end
frame:RegisterEvent("DISPLAY_SIZE_CHANGED")
frame:RegisterEvent("UI_SCALE_CHANGED")
frame:RegisterEvent("QUEST_LOG_UPDATE")
frame:RegisterEvent("QUEST_TURNED_IN")
frame:RegisterEvent("BANKFRAME_OPENED")
frame:SetScript("OnEvent", function(_, event)
    if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then fitWindow()
    elseif event == "BANKFRAME_OPENED" then
        local chain = selected and atlas.periodicQuestChains[selected.id]
        if card:IsVisible() and chain and chain.item then atlas.refreshSourceDetails() end
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_TURNED_IN" then
        if not card:IsVisible() or not selected then return end
        if cardDetails.directQuestSteps then
            local done, total = atlas.questRewardChainProgress(cardDetails.directQuestReward, cardDetails.directQuestSteps)
            if done ~= cardDetails.periodicDone or total ~= cardDetails.periodicTotal then atlas.refreshDetails(true) end
        elseif cardDetails.questChain and cardDetails.questChain.quests or atlas.periodicQuestChains[selected.id] then
            atlas.refreshDetails(true)
        elseif detailArea:IsVisible() and detailArea.questSource then detailArea:updateQuest(true) end
    end
end)
search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
frame:SetScript("OnShow", function()
    fitWindow()
    refreshJournal()
end)
showPage(false)
function atlas.toggleSettings()
    if shared then return end
    if not settings then settings = atlas.makeSettings(frame) end
    if frame:IsShown() and settings:IsShown() then showPage(catalog.wantsPlan); return end
    search:ClearFocus()
    page:Hide()
    if planner then planner:Hide() end
    catalogTab:setActive(false)
    planTab:setActive(false)
    settingsTab:setActive(true)
    settings:Show()
    frame:Show()
    setFooter()
end
local ownCatalog

local function setSharedControls(show)
    planTab.caption:SetText(show and "Вернуться" or "Планнер")
    ui.setIcon(planTab.glyph, show and "Reset" or "Route")
    settingsTab:SetShown(not show)
    settingsTab.divider:SetShown(not show)
    for id, button in ipairs(filters) do button:SetShown(show == (id > 3)) end
    collectionBadge:EnableMouse(not show)
    guide:SetText(show and L("Коллекция: %s", shared.owner:match("^[^-]+") or shared.owner)
        or "ПОЛЕВОЙ СПРАВОЧНИК   /   АЗЕРОТ")
end

returnToCollection = function()
    if not shared then return end
    ui.hideTooltipIn(page)
    shared = nil
    catalog.needsRefresh = true
    setSharedControls(false)
    activeFilter, sourceSubtype, frequency = ownCatalog.activeFilter, ownCatalog.sourceSubtype, ownCatalog.frequency
    sourceFilter, expansionFilter, selected = ownCatalog.sourceFilter, ownCatalog.expansionFilter, ownCatalog.selected
    setCatalogSearch(ownCatalog.search)
    local previous = ownCatalog
    ownCatalog = nil
    showPage(false)
    if not frame:IsShown() then refresh() end
    if selected == previous.selected then
        cardTabs.active = previous.tab
        locationIndex, vendorIndex, vendorMount = previous.locationIndex, previous.vendorIndex, selected
    end
    if previous.sortMode == catalog:sortMode() then catalog.offset = previous.offset else catalog:resetScroll() end
    atlas.refreshDetails(true)
end

function atlas.showSharedCatalog(owner)
    if not shared then
        ownCatalog = {
            activeFilter = activeFilter, sourceSubtype = sourceSubtype, frequency = frequency,
            sourceFilter = sourceFilter, expansionFilter = expansionFilter,
            search = search:GetText(), selected = selected, offset = catalog.offset, sortMode = catalog:sortMode(),
            locationIndex = locationIndex, vendorIndex = vendorIndex, tab = cardTabs.active,
        }
    end
    ui.hideTooltipIn(page)
    shared = { owner = owner, byID = {}, status = "Загрузка коллекции…" }
    catalog.needsRefresh = true
    activeFilter, sourceSubtype, frequency, sourceFilter, expansionFilter = 1, nil, nil, nil, nil
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
    catalog.needsRefresh = true
    refresh()
end

frame:HookScript("OnHide", returnToCollection)
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
