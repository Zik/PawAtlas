local _, atlas = ...
local ui = atlas.ui
local L = atlas.L
local controls = "Interface\\AddOns\\PawAtlas\\Media\\Controls\\"

local function hideTooltip(owner)
    atlas.cancelPendingLink(owner)
    owner.pendingItem = nil
    owner:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

-- Keep the owner and request together: a late item response must never reopen a
-- tooltip after leaving its region or selecting a different mount.
local function showItemTooltip(owner, itemID, fallback, link, append)
    hideTooltip(owner)
    local function render()
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        if C_Item.IsItemDataCachedByID(itemID) then
            if link then GameTooltip:SetHyperlink(link) else GameTooltip:SetItemByID(itemID) end
        end
        if GameTooltip:NumLines() == 0 then
            ui.tooltipTitle(fallback and fallback ~= "" and fallback or RETRIEVING_ITEM_INFO)
            if append then append() end
        end
        GameTooltip:Show()
    end
    render()
    if not C_Item.IsItemDataCachedByID(itemID) then
        owner.pendingItem = itemID
        owner:SetScript("OnEvent", function(self, _, loadedID, success)
            if self.pendingItem ~= loadedID then return end
            self.pendingItem = nil
            self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
            if success and self:IsVisible() and GameTooltip:IsOwned(self) then render() end
        end)
        owner:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        C_Item.RequestLoadItemDataByID(itemID)
    end
end

local function achievementCriteriaColors(id)
    local colors = {}
    if not GetAchievementNumCriteria or not GetAchievementCriteriaInfo then return colors end
    for index = 1, GetAchievementNumCriteria(id) do
        -- Match AchievementUI: a child achievement can be earned while its
        -- parent criterion remains incomplete because of additional modifiers.
        local name, _, completed = GetAchievementCriteriaInfo(id, index)
        if name and name ~= "" then
            colors[name] = completed == true and (colors[name] == nil or colors[name])
        end
    end
    return colors
end

local function setAchievementTooltip(id)
    if GameTooltip.ProcessInfo and C_TooltipInfo and C_TooltipInfo.GetAchievementByID then
        local criteria = achievementCriteriaColors(id)
        GameTooltip:ProcessInfo({
            getterName = "GetAchievementByID", getterArgs = { id },
            rebuildPreCall = function() criteria = achievementCriteriaColors(id) end,
            linePreCall = function(tooltip, line)
                if tooltip:NumLines() == 0 then return end
                -- Keep Blizzard's title, description, completion status and
                -- layout. Only recolor cells that exactly name a criterion.
                for _, side in ipairs({ "left", "right" }) do
                    local text = line[side .. "Text"]
                    if type(text) == "string" then
                        local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        local completed = criteria[plain:match("^%s*(.-)%s*$")]
                        if completed ~= nil then
                            line[side .. "Text"] = plain
                            line[side .. "Color"] = completed and CreateColor(0, 1, 0) or CreateColor(.6, .6, .6)
                        end
                    end
                end
            end,
        })
    elseif GameTooltip.SetAchievementByID then
        GameTooltip:SetAchievementByID(id)
    end
end

-- Additional card areas use Blizzard's full source text in the tooltip when it
-- exceeds the available rows. Item quality comes from the mount-teaching item.
function atlas.cardDetails(card, onNavigate)
    local panel = {}
    local journal = ui.place(CreateFrame("Frame", nil, card), card, 0, 182, 668, 64)
    panel.sourceFrame = journal
    journal:EnableMouse(true)
    journal:SetHyperlinksEnabled(true)
    local journalSurface = ui.surface(journal, 0, 0, 668, 64)
    local journalAccent = journal:CreateTexture(nil, "BORDER")
    ui.place(journalAccent, journal, 0, 12, 2, 40)
    journalAccent:SetColorTexture(unpack(ui.gold))
    local journalIcon = ui.icon(journal, 18, 17, 30, "Scroll")
    local journalHeading = ui.text(journal, 65, 10, 582, 18, 12, "", ui.gold)
    local mapButton = ui.place(CreateFrame("Button", nil, journal), journal, 620, 3, 32, 32)
    local mapIcon = ui.icon(mapButton, 0, 0, 32, "Place")
    local mapArrow = ui.dropdownArrow(mapButton, 24, 12, 8)
    mapButton:Hide()
    local dismissPoints = ui.button(card, 0, 0, 668, 454, function() end)
    dismissPoints:SetFrameLevel(card:GetFrameLevel() + 10)
    dismissPoints:ClearHighlightTexture()
    dismissPoints:Hide()
    local pointMenu = ui.place(CreateFrame("Frame", nil, card), card, 338, 216, 330, 226)
    pointMenu:ClearAllPoints()
    pointMenu:SetPoint("TOPRIGHT", journal, "TOPRIGHT", 0, -36)
    pointMenu:SetFrameLevel(card:GetFrameLevel() + 12)
    pointMenu:EnableMouse(true)
    local pointSurface = ui.dropdownSurface(pointMenu)
    local pointList = ui.scrollingList(pointMenu, 8, 8, 314, 42, 5)
    local function pointTooltip(owner, point)
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        ui.tooltipTitle(L("Поставить метку · %.1f, %.1f", point.x * 100, point.y * 100))
        ui.tooltipLine(atlas.displayName(point.boss), 1, 1, 1, true)
        ui.tooltipLine(atlas.displayName(point.place), 1, 1, 1, true)
        if point.condition then ui.tooltipLine(atlas.displaySourceText(point.condition), 1, 1, 1, true) end
        GameTooltip:Show()
    end
    local function navigate(point)
        pointMenu:Hide()
        GameTooltip:Hide()
        local message = atlas.openSource({ id = panel.mount.id }, point)
        if onNavigate then onNavigate(message) end
    end
    for _, row in ipairs(pointList.rows) do
        row.name = ui.text(row, 8, 1, 290, 19, 13, "", ui.gold)
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.place = ui.text(row, 8, 21, 290, 16, 11, "", ui.muted)
        row.place:SetMaxLines(1)
        row:HookScript("OnEnter", function(self) if self.item then pointTooltip(self, self.item) end end)
        row:HookScript("OnLeave", hideTooltip)
        row:HookScript("OnHide", hideTooltip)
    end
    function pointList:render(row, point)
        row.name:SetText(atlas.displayName(point.boss))
        row.place:SetText(("%s · %.1f, %.1f"):format(atlas.displayName(point.place), point.x * 100, point.y * 100))
        -- Scrolling reuses the hovered row without another OnEnter event.
        if GameTooltip:IsOwned(row) then pointTooltip(row, point) end
    end
    function pointList:onClick(point) navigate(point) end
    pointMenu:SetScript("OnShow", function() dismissPoints:Show(); pointList:redraw() end)
    pointMenu:SetScript("OnHide", function() dismissPoints:Hide(); GameTooltip:Hide() end)
    dismissPoints:SetScript("OnClick", function() pointMenu:Hide() end)
    mapButton:SetScript("OnClick", function()
        if #pointList.items == 1 then navigate(pointList.items[1])
        elseif #pointList.items > 1 then pointMenu:SetShown(not pointMenu:IsShown()) end
    end)
    mapButton:SetScript("OnEnter", function(self)
        mapIcon:SetVertexColor(1, .91, .65)
        if #pointList.items == 1 then pointTooltip(self, pointList.items[1])
        else GameTooltip:SetOwner(self, "ANCHOR_TOP"); ui.tooltipTitle(L("Место")); GameTooltip:Show() end
    end)
    local function leaveMap(self) mapIcon:SetVertexColor(1, 1, 1); hideTooltip(self) end
    mapButton:SetScript("OnLeave", leaveMap)
    mapButton:SetScript("OnHide", function(self) leaveMap(self); pointMenu:Hide() end)
    journal:HookScript("OnHide", function() pointMenu:Hide() end)
    pointMenu:Hide()
    local journalScroll = ui.place(CreateFrame("ScrollFrame", nil, journal), journal, 65, 32, 582, 84)
    local journalContent = ui.place(CreateFrame("Frame", nil, journalScroll), journalScroll, 0, 0, 582, 84)
    journalContent:EnableMouse(true)
    journalContent:SetHyperlinksEnabled(true)
    journalScroll:SetScrollChild(journalContent)
    local journalText = ui.text(journalContent, 0, 0, 582, 84, 15, "")
    journalText.atlasGameText = true
    journalText:SetMaxLines(0)
    journalText:SetJustifyV("TOP")
    local separatorMeasure = ui.text(journalContent, 0, 0, 582, 0, 15, "")
    separatorMeasure:SetMaxLines(0)
    separatorMeasure:Hide()
    local vendorSeparators = {}
    local sourceSlider = ui.place(CreateFrame("Slider", nil, journal), journal, 651, 32, 10, 84)
    local sourceRail = sourceSlider:CreateTexture(nil, "ARTWORK")
    sourceRail:SetPoint("TOP", sourceSlider, "TOP")
    sourceRail:SetPoint("BOTTOM", sourceSlider, "BOTTOM")
    sourceRail:SetWidth(2)
    sourceRail:SetColorTexture(unpack(ui.rule))
    sourceRail:SetAlpha(.6)
    local sourceThumb = sourceSlider:CreateTexture(nil, "OVERLAY")
    sourceThumb:SetColorTexture(unpack(ui.gold))
    sourceThumb:SetAlpha(.5)
    sourceThumb:SetSize(2, 20)
    sourceSlider:SetThumbTexture(sourceThumb)
    sourceSlider:SetOrientation("VERTICAL")
    sourceSlider:SetValueStep(1)
    sourceSlider:SetObeyStepOnDrag(true)
    sourceSlider:EnableMouse(true)
    sourceSlider:SetScript("OnValueChanged", function(_, value)
        journalScroll:SetVerticalScroll(value)
    end)
    local function scrollSource(_, delta)
        hideTooltip(journal)
        hideTooltip(journalContent)
        sourceSlider:SetValue(math.max(0, math.min(panel.sourceRange or 0, journalScroll:GetVerticalScroll() - delta * 36)))
    end
    for _, owner in ipairs({ journal, journalScroll, journalContent, sourceSlider }) do
        owner:EnableMouseWheel(true)
        owner:SetScript("OnMouseWheel", scrollSource)
    end
    local function showSource(self)
        if self ~= journalContent then return end
        -- Achievement previews belong to their name links, not the surrounding
        -- source panel, including while the achievement index is loading.
        if panel.sourceHasAchievement then return end
        local mount = panel.mount
        if not mount then return end
        local legacy = mount.availability or (atlas.legacySourceDetails and atlas.legacySourceDetails(mount))
        local english = atlas.getLocale() == "enUS"
        local period = legacy and ((english and legacy.englishPeriod) or legacy.period)
        local conditions = legacy and ((english and legacy.englishConditions) or legacy.conditions)
        local event = mount.unavailable and legacy and ((english and legacy.englishEvent) or legacy.event)
        local alternatives = (legacy and (legacy.alternatives or legacy.history))
            or (atlas.tradingPostOffer and atlas.tradingPostOffer(mount))
        if panel.sourceTruncated or journalText:IsTruncated() or period or conditions or event or alternatives then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(event or L(mount.kind))
            ui.tooltipSourceText(panel.sourceText or mount.journalSource, mount.unavailable and { 1, .67, .39 })
            if period or conditions then ui.tooltipLine(" ") end
            if period then ui.tooltipSourceText(L("Был доступен: %s", period), ui.muted) end
            if conditions then ui.tooltipSourceText(L("Условия: %s", conditions), ui.gold) end
            ui.tooltipSourceAlternatives(mount)
            GameTooltip:Show()
        end
    end
    journal:SetScript("OnLeave", hideTooltip)
    journal:SetScript("OnHide", hideTooltip)
    journal:SetScript("OnHyperlinkEnter", function(self, link, text)
        local kind, id = link:match("^(%a+):(%d+)")
        id = tonumber(id)
        if not id or id <= 0 then return end
        if kind == "item" then
            showItemTooltip(self, id, text, link)
        elseif kind == "currency" then
            hideTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:SetCurrencyByID(id)
            GameTooltip:Show()
        elseif kind == "achievement" then
            hideTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            if not panel.shared then setAchievementTooltip(id) end
            if GameTooltip:NumLines() == 0 then
                local _, name, _, _, _, _, _, description = GetAchievementInfo(id)
                ui.tooltipTitle(name or text)
                if description and description ~= "" then ui.tooltipLine(description, 1, 1, 1, true) end
            end
            GameTooltip:Show()
        end
    end)
    journal:SetScript("OnHyperlinkClick", function(self, link, _, button)
        if button ~= "LeftButton" then return end
        if IsShiftKeyDown() then atlas.linkSource(link, self); return end
        local id = tonumber(link:match("^achievement:(%d+)"))
        if id then atlas.openAchievement(id) end
    end)
    journal:SetScript("OnHyperlinkLeave", function(self)
        hideTooltip(self)
        if self:IsVisible() and self:IsMouseOver() then showSource(self) end
    end)
    for _, script in ipairs({ "OnEnter", "OnLeave", "OnHide", "OnHyperlinkEnter", "OnHyperlinkClick", "OnHyperlinkLeave" }) do
        journalContent:SetScript(script, journal:GetScript(script))
    end
    journalContent.atlasTradingPostSource = true
    journalContent:SetScript("OnEnter", showSource)

    local itemBox = ui.place(CreateFrame("Frame", nil, card), card, 0, 257, 668, 60)
    itemBox:EnableMouse(true)
    local itemSurface = ui.surface(itemBox, 0, 0, 668, 60)
    local compactItemSurface = ui.surface(itemBox, 0, 0, 668, 52)
    ui.icon(itemBox, 16, 16, 28, "Loot")
    local heading = ui.text(itemBox, 58, 8, 594, 17, 11, "", ui.muted)
    heading:SetMaxLines(1)
    local itemName = ui.text(itemBox, 58, 22, 594, 22, 17, "", ui.gold)
    itemName.atlasGameText = true
    itemName:SetMaxLines(1)
    local itemCheck = ui.icon(itemBox, 628, 22, 20, "ObjectiveComplete")
    itemCheck:Hide()
    local itemAttempts = ui.text(itemBox, 350, 5, 302, 21, 14, "", ui.muted)
    itemAttempts:SetJustifyH("RIGHT")
    itemAttempts:SetMaxLines(1)
    local itemChanceHelp = ui.place(CreateFrame("Frame", nil, itemBox), itemBox, 350, 5, 302, 21)
    itemChanceHelp:EnableMouse(true)
    local function showItemChance(self)
        local progress = panel.itemProgress
        if not progress or progress.collection or progress.acquired or not progress.perAttempt or progress.perAttempt == 1 then return end
        local chance = progress.cumulative
        if chance == nil then return end
        local step = math.max(1, math.min(#ui.chanceFlavors, math.ceil(chance * 10)))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L(ui.chanceFlavors[step]), itemAttempts:GetTextColor())
        GameTooltip:Show()
    end
    itemChanceHelp:SetScript("OnEnter", showItemChance)
    itemChanceHelp:SetScript("OnLeave", hideTooltip)
    itemChanceHelp:SetScript("OnHide", hideTooltip)
    itemChanceHelp:Hide()
    local itemTrack = ui.fill(itemBox, 58, 53, 594, 3, ui.rule)
    itemTrack:SetAlpha(.65)
    local itemFill = ui.fill(itemBox, 58, 53, 1, 3, ui.mint)
    itemAttempts:Hide(); itemTrack:Hide(); itemFill:Hide()
    local nameLoader = CreateFrame("Frame", nil, card)
    local function clearNameRequest(self)
        self.pendingItem = nil
        self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    end
    nameLoader:SetScript("OnHide", clearNameRequest)
    local function updateItemName()
        local item = panel.item
        if not item then return end
        local name = item.name or RETRIEVING_ITEM_INFO
        if atlas.displayName then name = atlas.displayName(name) end
        itemName:SetText(name .. (item.required and ("  ×" .. item.required) or ""))
    end
    nameLoader:SetScript("OnEvent", function(self, _, id, success)
        if self.pendingItem ~= id then return end
        self.pendingItem = nil
        self:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        if success and panel.item and panel.item.item == id then
            local name = C_Item.GetItemInfo(id)
            if name and name ~= "" then panel.item.name = name; updateItemName() end
        end
    end)
    local function appendItemContext()
        local item = panel.item
        local progress = panel.itemProgress
        local hasStats = progress and (progress.attempts ~= nil or progress.perAttempt ~= nil or not progress.collection)
            or not progress and item.basis ~= "drop" and item.basis ~= "teaching"
        if panel.mount.quest or (panel.covenants and #panel.covenants > 0) or hasStats then ui.tooltipLine(" ") end
        if panel.mount.quest then ui.tooltipLine(L("Квест: %s", panel.mount.quest)) end
        if panel.covenants and #panel.covenants > 0 then
            local names = {}
            for _, covenant in ipairs(panel.covenants) do names[#names + 1] = atlas.displayName(covenant.name) end
            ui.tooltipLine(L("Ковенант: %s", table.concat(names, ", ")), 1, 1, 1, true)
        end
        if progress then
            local gathered = atlas.itemCollectionCount and atlas.itemCollectionCount(panel.mount)
            if gathered ~= nil then ui.tooltipLine(L("Собрано: %s", gathered), 1, 1, 1) end
            if progress.collected ~= nil and progress.required then
                ui.tooltipLine(L("В наличии: %s / %s", progress.collected, progress.required), 1, 1, 1)
                ui.tooltipLine(L("Сумки, банк персонажа и банк отряда"), ui.muted[1], ui.muted[2], ui.muted[3], true)
                if progress.attempts ~= nil or progress.perAttempt ~= nil then ui.tooltipLine(" ") end
            end
            if progress.attempts ~= nil then ui.tooltipLine(L("Попытки: %s", progress.attempts), 1, 1, 1) end
            if progress.perAttempt ~= nil then
                local chanceLabel = item.basis == "cage" and "Выпадение клетки: %s" or "За одну попытку: %s"
                ui.tooltipLine(L(chanceLabel, ui.probabilityText(progress.perAttempt, progress.perAttempt == 1)), 1, 1, 1)
                if progress.contentsPerOpening then
                    ui.tooltipLine(L("Маунт из клетки: %s", ui.probabilityText(progress.contentsPerOpening)), 1, 1, 1)
                end
                if progress.rateEstimated then ui.tooltipLine(L("Предположительный шанс")) end
                if progress.attempts and progress.attempts > 0 and progress.cumulative ~= nil then
                    ui.tooltipLine(L("Вероятность за все попытки: %s", ui.probabilityText(progress.cumulative, progress.perAttempt == 1)), 1, 1, 1)
                    ui.tooltipLine(" ")
                    ui.tooltipLine(L("Вероятность хотя бы одного выпадения за все учтённые попытки при постоянном шансе и независимых попытках."), ui.muted[1], ui.muted[2], ui.muted[3], true)
                    ui.tooltipLine(L("Шанс следующей попытки не увеличивается."), ui.muted[1], ui.muted[2], ui.muted[3], true)
                end
            elseif not progress.collection then ui.tooltipLine(L("Шанс добычи самого предмета неизвестен.")) end
        elseif item.basis ~= "drop" and item.basis ~= "teaching" then
            if item.rate then
                ui.tooltipLine(L("Шанс: %s", ui.probabilityText(1 / item.rate, item.rate == 1)), 1, 1, 1)
            else ui.tooltipLine(L("Шанс добычи самого предмета неизвестен.")) end
        end
        local reward = atlas.guaranteedRewards and atlas.guaranteedRewards[panel.mount.id]
        local raidLoot = atlas.raidLootReward and atlas.raidLootReward(panel.mount)
        local seen, separated = {}, false
        local function instruction(text)
            if not text or text == "" or seen[text] then return end
            seen[text] = true
            if not separated then ui.tooltipLine(" "); separated = true end
            ui.tooltipSourceText(text, ui.gold)
        end
        instruction(reward and reward.condition and L(reward.condition))
        instruction(panel.mount.note and L(panel.mount.note))
        instruction(panel.sourceView and panel.sourceView.conditions and atlas.displaySourceText(panel.sourceView.conditions))
        instruction(raidLoot and raidLoot.condition and L(raidLoot.condition))
    end
    -- Retail can rebuild native item lines asynchronously; append context on
    -- each rebuild, restricted to this card's tooltip rather than all items.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip and tooltip:IsOwned(itemBox) and itemBox:IsVisible() and panel.item then
            appendItemContext()
        end
    end)
    itemBox:SetScript("OnEnter", function(self)
        local item = panel.item
        if not item then return end
        if item.item then
            showItemTooltip(self, item.item, item.name, nil, appendItemContext)
        else
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(item.name)
            appendItemContext()
            GameTooltip:Show()
        end
    end)
    itemBox:SetScript("OnLeave", hideTooltip)
    itemBox:SetScript("OnHide", hideTooltip)
    itemBox:SetScript("OnMouseUp", function(self, button)
        atlas.cancelPendingLink(self)
        if button == "LeftButton" and IsShiftKeyDown() and panel.item and panel.item.item then
            atlas.linkItem(panel.item.item, self)
        end
    end)

    local owned = ui.place(CreateFrame("Frame", nil, card), card, 0, 72, 270, 24)
    local tint = ui.fill(owned, 0, 0, 270, 24, { .10, .24, .18, .55 })
    tint:SetGradient("HORIZONTAL", CreateColor(.14, .32, .22, .65), CreateColor(.04, .13, .10, 0))
    ui.icon(owned, 8, 2, 18, "Bookmark")
    ui.text(owned, 34, 0, 220, 24, 13, "В коллекции", ui.mint)

    -- Faction is part of the source panel's background, with no separate hit
    -- region. Keep the native emblem proportional and the text unobstructed.
    local factionBackgrounds = {}
    for _, owner in ipairs({ card, journal }) do
        local emblem = owner:CreateTexture(nil, "BACKGROUND", nil, 3)
        emblem:SetAlpha(1)
        emblem:SetBlendMode("BLEND")
        factionBackgrounds[#factionBackgrounds + 1] = { emblem = emblem }
    end
    local function hideFactionBackgrounds()
        for _, background in ipairs(factionBackgrounds) do
            background.emblem:Hide()
        end
    end

    local sourcePager = ui.place(CreateFrame("Frame", nil, journal), journal, 546, 7, 108, 24)
    sourcePager:SetFrameLevel(journalContent:GetFrameLevel() + 2)
    local pageNumber = ui.text(sourcePager, 29, 0, 50, 24, 12, "", ui.muted)
    pageNumber:SetJustifyH("CENTER")
    local function turnPage(delta)
        local total = panel.sourcePageCount or 0
        if total < 2 then return end
        panel.sourcePage = ((panel.sourcePage or 1) - 1 + delta) % total + 1
        panel:update(panel.mount, panel.location, panel.vendor, panel.sourceView)
    end
    ui.action(sourcePager, 0, 0, 25, 24, "‹", nil, function() turnPage(-1) end)
    ui.action(sourcePager, 83, 0, 25, 24, "›", nil, function() turnPage(1) end)
    sourcePager:Hide()

    function panel:update(mount, loc, vendor, sourceView, sourcePoints)
        if self.mount ~= mount then self.sourcePage = 1 end
        local sourceKind = sourceView and sourceView.sourceKind or mount.kind
        local vendorKey = vendor and table.concat({ vendor.name or "", vendor.place or "", vendor.conditions or "", vendor.faction or "" }, "\001")
        local sourceKey = sourceView and table.concat({ sourceView.boss or "", sourceView.place or "",
            sourceView.journalSourceRaw or "", sourceView.conditions or "", sourceView.faction or "" }, "\001")
        local locationKey = loc and table.concat({ loc.map or "", loc.npc or "", loc.boss or "", loc.place or "",
            loc.x or "", loc.y or "", loc.condition or "", loc.faction or "" }, "\001")
        if self.vendorKey ~= vendorKey or self.sourceKey ~= sourceKey then self.sourcePage = 1 end
        local changed = self.mount ~= mount or self.locationKey ~= locationKey or self.vendorKey ~= vendorKey or self.sourceKey ~= sourceKey
            or self.lastSourcePage ~= self.sourcePage
        if changed then
            hideTooltip(journal)
            hideTooltip(journalContent)
            hideTooltip(itemBox)
            -- Hide the previous source before resolving the next one. A failed
            -- data lookup must not leave an old achievement over a new vendor.
            journal:Hide()
            itemBox:Hide()
            owned:Hide()
            hideFactionBackgrounds()
            pointMenu:Hide()
            pointList.offset = 0
        end
        clearNameRequest(nameLoader)
        self.mount, self.item, self.location, self.vendor, self.vendorKey = mount, nil, loc, vendor, vendorKey
        self.sourceView = sourceView
        self.locationKey = locationKey
        self.sourceText, self.sourceHasAchievement = nil, false
        self.sourceKey = sourceKey
        self.lastSourcePage = self.sourcePage
        self.covenants = atlas.mountCovenantRequirements and atlas.mountCovenantRequirements(mount) or {}
        local rewardItem = atlas.lootItems[mount.id]
        local progress = not self.shared and not vendor and not mount.availability and not (sourceView and sourceView.trackingCompatible == false)
            and atlas.itemAttemptProgress and atlas.itemAttemptProgress(mount) or nil
        local missingRewardItem = not rewardItem or (not rewardItem.item and (not rewardItem.basis or rewardItem.basis == "drop"))
        local displayItem = missingRewardItem and not (progress and progress.item) and not vendor
            and atlas.rewardItem and atlas.rewardItem(mount, loc,
                not mount.availability and (mount.kind == "Квест" or mount.covenantSourceOnly))
        if displayItem or rewardItem then
            self.item = {}
            for key, value in pairs(displayItem or {}) do self.item[key] = value end
            for key, value in pairs(rewardItem or {}) do self.item[key] = value end
        end
        self.itemProgress = progress
        if progress and progress.item then
            -- This box describes the tracked reagent/container stage; the
            -- reward's own odds and item metadata stay separate for the main card.
            local item = {}
            for key, value in pairs(rewardItem or {}) do item[key] = value end
            item.item = progress.item
            item.required = progress.required or (rewardItem and rewardItem.item == progress.item and rewardItem.required) or nil
            local cachedName = C_Item.GetItemInfo and C_Item.GetItemInfo(progress.item)
            item.name = cachedName or progress.name or (rewardItem and rewardItem.item == progress.item
                and (atlas.dataName and atlas.dataName(rewardItem) or rewardItem.name))
            item.englishName = progress.englishName or (rewardItem and rewardItem.item == progress.item and rewardItem.englishName) or nil
            item.rate = progress.perAttempt and progress.perAttempt > 0 and 1 / progress.perAttempt or nil
            if progress.collection then item.basis = "ingredient" end
            self.item = item
        end
        if self.item and self.item.item then
            local cachedName = C_Item.GetItemInfo and C_Item.GetItemInfo(self.item.item)
            if cachedName == "" then cachedName = nil end
            self.item.name = cachedName
                or (atlas.dataName and atlas.dataName(self.item) or self.item.name)
            if not self.item.name or self.item.name == "" then
                self.item.name = RETRIEVING_ITEM_INFO
            end
            -- A static fallback is not proof that the client-localized item
            -- name is loaded. Keep listening even when that fallback is usable.
            if not cachedName then
                nameLoader.pendingItem = self.item.item
                nameLoader:RegisterEvent("ITEM_DATA_LOAD_RESULT")
                C_Item.RequestLoadItemDataByID(self.item.item)
            end
        end
        local compact = vendor ~= nil or mount.availability ~= nil or (sourceView and sourceView.factionRoute) or (mount.journalOnly == true and not mount.hasSourcePanels
            and not (sourceView and sourceView.hasSourcePanels))
        pointList.items = {}
        if compact and not vendor and not mount.availability and not (sourceView and sourceView.factionRoute) then
            for _, point in ipairs(sourcePoints or atlas.mountLocations(mount)) do
                if type(point.map) == "number" and type(point.x) == "number" and type(point.y) == "number" then
                    pointList.items[#pointList.items + 1] = point
                end
            end
        end
        local hasNavigation = #pointList.items > 0
        local paginationWidth = (self.sourceChoiceCount or 0) > 1 and 132 or 0
        local rightInset = 12 + (mount.difficultyBadgeVisible and 48 or 0) + paginationWidth
        mapButton:ClearAllPoints()
        mapButton:SetPoint("TOPRIGHT", journal, "TOPRIGHT", -rightInset, -3)
        mapButton:SetShown(hasNavigation)
        mapArrow:SetShown(#pointList.items > 1)
        local pointHeight = 16 + math.max(1, math.min(5, #pointList.items)) * 42
        pointMenu:SetHeight(pointHeight)
        pointList:SetHeight(pointHeight - 16)
        local menuX, menuY = { 0, 10, 320, 330 }, { 0, 10, pointHeight - 10, pointHeight }
        for row = 1, 3 do
            for col = 1, 3 do
                local texture = pointSurface[(row - 1) * 3 + col]
                texture:ClearAllPoints()
                ui.place(texture, pointMenu, menuX[col], menuY[row], menuX[col + 1] - menuX[col], menuY[row + 1] - menuY[row])
            end
        end
        if pointMenu:IsShown() then pointList:redraw() end
        local sourceMount = vendor and { id = mount.id, journalSourceRaw = vendor.conditions or "" } or sourceView or mount
        local sourcePages = compact and not vendor and atlas.covenantSourcePages(sourceMount)
        self.sourcePageCount = sourcePages and #sourcePages or 0
        sourcePager:SetShown(self.sourcePageCount > 1)
        sourcePager:ClearAllPoints()
        sourcePager:SetPoint("TOPRIGHT", journal, "TOPRIGHT", -rightInset - (hasNavigation and 36 or 0), -7)
        if sourcePages then
            self.sourcePage = math.max(1, math.min(self.sourcePage or 1, #sourcePages))
            sourceMount = { id = mount.id, journalSourceRaw = sourcePages[self.sourcePage] }
            self.covenants = atlas.mountCovenantRequirements({ journalSourceRaw = sourceMount.journalSourceRaw })
            pageNumber:SetText(self.sourcePage .. " / " .. #sourcePages)
        end
        self.sourceText = atlas.sourceWithoutDifficulty(mount, atlas.decorateSource(sourceMount))
        local hasFeat, hasOrdinaryAchievement = false, false
        for line in (self.sourceText .. "\n"):gmatch("(.-)\n") do
            if line:match("^%s*Великий подвиг:") or line:match("^%s*Feats of Strength:") then
                hasFeat, self.sourceHasAchievement = true, true
            elseif line:match("^%s*Достижение:") or line:match("^%s*Achievement:") then
                hasOrdinaryAchievement = true
                self.sourceHasAchievement = true
            end
        end
        local sourceY = vendor and 252 or 182
        journal:ClearAllPoints()
        journal:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -sourceY)
        local content = self.sourceText ~= "" and self.sourceText:match("^%s*(.-)%s*$") or L("Источник не указан")
        if journalText.atlasRawText ~= content then journalText:SetText(content) end
        local item = self.item
        local hasItem = not vendor and item and item.name ~= nil
        local achievement = not vendor and sourceKind == "Достижение"
        local textLeft = vendor and 14 or achievement and 96 or 65
        local headingKind = (mount.unavailable and mount.availability and mount.availability.event and "Событие")
            or (achievement and hasFeat and not hasOrdinaryAchievement and "Великий подвиг")
            or (not sourceView and mount.covenantSourceOnly and "Ковенант") or sourceKind
        journalHeading:SetText(vendor and "Условие" or L("Источник · %s", L(headingKind)))
        journalHeading:SetTextColor(unpack(vendor and ui.muted or ui.gold))
        ui.setIcon(journalIcon, vendor and "Scroll" or sourceKind == "Квест" and "Quest"
            or sourceKind == "Достижение" and "Achievement" or "Book")
        journalIcon:ClearAllPoints()
        ui.place(journalIcon, journal, vendor and 12 or 18, vendor and 8 or 17, vendor and 16 or 30, vendor and 16 or 30)
        journalHeading:ClearAllPoints()
        ui.place(journalHeading, journal, vendor and 34 or textLeft, vendor and 7 or 10, vendor and 614 or 582, 18)
        journalAccent:SetShown(not vendor)
        ui.setFont(journalText, vendor and 14 or 15)
        ui.setFont(separatorMeasure, vendor and 14 or 15)
        -- Every source shares the card width and padding. Only its height follows
        -- the actual text, measured with the currently selected font.
        local width = 668
        local textWidth = width - textLeft - 21
        local textY = vendor and 28 or 32
        journal:SetWidth(width)
        journalHeading:SetWidth((vendor and 614 or textWidth) - (not vendor and mount.difficultyBadgeVisible and 48 or 0)
            - (hasNavigation and 36 or 0) - (sourcePages and 116 or 0) - (not vendor and paginationWidth or 0))
        journalText:SetWidth(textWidth)
        journalScroll:ClearAllPoints()
        journalScroll:SetPoint("TOPLEFT", journal, "TOPLEFT", textLeft, -textY)
        journalScroll:SetWidth(textWidth)
        journalContent:SetWidth(textWidth)
        separatorMeasure:SetWidth(textWidth)
        journalText:SetHeight(0)
        local measured = math.max(18, math.ceil(journalText:GetStringHeight()))
        local collected = self.shared or select(11, C_MountJournal.GetMountInfoByID(mount.id)) == true
        local lowerPanel = collected or item ~= nil or (atlas.guaranteedRewards and atlas.guaranteedRewards[mount.id])
        -- Leave room for two objective rows, including inline coin/check art.
        -- The collected footer starts at 329; this panel ends no lower than 326.
        local maxHeight = vendor and (collected and 40 or 128) or (hasItem and 42 or (lowerPanel and 90 or 186))
        local visibleHeight = math.min(measured, maxHeight)
        journalText:SetHeight(measured)
        journalContent:SetHeight(measured)
        journalScroll:SetHeight(visibleHeight)
        panel.sourceTruncated = measured > visibleHeight
        panel.sourceRange = math.max(0, measured - visibleHeight)
        sourceSlider:ClearAllPoints()
        ui.place(sourceSlider, journal, width - 17, textY, 10, visibleHeight)
        sourceSlider:SetMinMaxValues(0, panel.sourceRange)
        sourceThumb:SetHeight(math.max(15, math.min(28, visibleHeight * visibleHeight / measured)))
        sourceSlider:SetShown(panel.sourceRange > 0)
        sourceSlider:SetValue(changed and 0 or math.min(journalScroll:GetVerticalScroll(), panel.sourceRange))
        local height = textY + visibleHeight + (vendor and 6 or 12)
        journal:SetHeight(height)
        if achievement then
            -- The native shield occupies a 62x58 cell; keep its visible edges
            -- balanced inside the gutter rather than centering transparent padding.
            local iconWidth = math.min(64, (height - 20) * 62 / 58)
            local iconHeight = iconWidth * 58 / 62
            journalIcon:ClearAllPoints()
            ui.place(journalIcon, journal, 16 + (64 - iconWidth) / 2, (height - iconHeight) / 2, iconWidth, iconHeight)
        end
        journalAccent:SetHeight(height - 24)
        local xs, ys = { 0, 10, width - 10, width }, { 0, 10, height - 10, height }
        for row = 1, 3 do
            for col = 1, 3 do
                local texture = journalSurface[(row - 1) * 3 + col]
                texture:ClearAllPoints()
                ui.place(texture, journal, xs[col], ys[row], xs[col + 1] - xs[col], ys[row + 1] - ys[row])
            end
        end
        local separatorCount = 0
        if mount.kind == "Торговец" and not vendor then
            local text = journalText:GetText()
            for at in text:gmatch("()\n%s*\n") do
                separatorMeasure:SetText(text:sub(1, at - 1))
                separatorCount = separatorCount + 1
                local texture = vendorSeparators[separatorCount]
                if not texture then
                    texture = journalContent:CreateTexture(nil, "BACKGROUND")
                    texture:SetColorTexture(unpack(ui.rule))
                    texture:SetAlpha(.5)
                    vendorSeparators[separatorCount] = texture
                end
                texture:ClearAllPoints()
                ui.place(texture, journalContent, 0, separatorMeasure:GetStringHeight() + 8, textWidth, 1)
                texture:Show()
            end
        end
        for i = separatorCount + 1, #vendorSeparators do vendorSeparators[i]:Hide() end
        itemBox:ClearAllPoints()
        itemBox:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -(compact and (sourceY + height + 8) or 257))
        itemBox:SetHeight(compact and 52 or 60)
        local acquired = hasItem and progress and progress.acquired == true
        itemCheck:SetShown(acquired == true)
        itemName:SetWidth(acquired and 564 or 594)
        local showProgress = hasItem and progress ~= nil and not collected and not acquired
        local probability = showProgress and (progress.attempts and progress.attempts > 0 and progress.cumulative or progress.perAttempt) or nil
        local collection = showProgress and progress.collected ~= nil and progress.required and progress.required > 0
        local showBar = showProgress and (probability ~= nil or collection)
        heading:SetWidth(showProgress and 286 or 594)
        itemAttempts:SetShown(showProgress and (progress.attempts ~= nil or probability ~= nil or collection))
        itemChanceHelp:SetShown(showProgress and not collection and progress.cumulative ~= nil
            and progress.perAttempt ~= nil and progress.perAttempt < 1)
        itemTrack:SetShown(showBar)
        itemFill:SetShown(showBar and (collection and progress.collected > 0 or probability ~= nil and probability > 0))
        if showProgress then
            local guaranteed = progress.perAttempt == 1
            local count = progress.attempts ~= nil and L("Попытки: %s",
                collection and ("|cffe6e9ed" .. progress.attempts .. "|r") or progress.attempts) or ""
            local value = collection and L("В наличии: %s / %s",
                "|cffa1d1ba" .. progress.collected, progress.required .. "|r")
                or probability ~= nil and ui.probabilityText(probability, guaranteed) or ""
            itemAttempts:SetText(count .. (value ~= "" and ((count ~= "" and " · " or "") .. value) or ""))
            itemAttempts:SetTextColor(unpack(ui.muted))
            if showBar then
                local fill = collection and math.min(1, progress.collected / progress.required) or probability
                local color = collection and ui.mint or ui.muted
                if not collection then
                    for _, tier in ipairs(ui.chances) do if probability * 100 <= tier.limit then color = tier.color; break end end
                end
                itemAttempts:SetTextColor(unpack(collection and ui.muted or color))
                itemFill:SetColorTexture(unpack(color))
                itemTrack:ClearAllPoints(); itemFill:ClearAllPoints()
                ui.place(itemTrack, itemBox, 58, compact and 45 or 53, 594, 3)
                itemFill:SetShown(fill > 0)
                ui.place(itemFill, itemBox, 58, compact and 45 or 53, math.max(.01, 594 * math.max(0, math.min((collection or guaranteed) and 1 or .9999, fill))), 3)
            end
        end
        if itemChanceHelp:IsShown() and GameTooltip:IsOwned(itemChanceHelp) then showItemChance(itemChanceHelp) end
        -- Keep the name on the same baseline with or without a progress bar.
        for _, texture in ipairs(itemSurface) do texture:SetShown(not compact) end
        for _, texture in ipairs(compactItemSurface) do texture:SetShown(compact) end
        if item and item.name then
            local label = L(({ ingredient="Собрать", egg="Выбить и дождаться созревания", open="Открыть", cage="Выбить и открыть",
                teaching="Предмет маунта" })[item.basis] or "Добыча")
            local raidLoot = atlas.raidLootReward and atlas.raidLootReward(mount)
            if raidLoot then label = L("Добыча · %d маунта на рейд", raidLoot.quantity) end
            if mount.quest then
                local reward = atlas.guaranteedRewards and atlas.guaranteedRewards[mount.id]
                label = reward and reward.reagent and reward.reagent.completionQuest and L("Квест")
                    or L("Начинает квест %s", mount.quest)
            end
            local sigils = {}
            for _, covenant in ipairs(self.covenants) do sigils[#sigils + 1] = "|T" .. covenant.texture .. ":16:16:0:0|t" end
            local badges = table.concat(sigils, " ")
            if loc and loc.condition and not loc.condition:find("Альянс") and not loc.condition:find("Орда") then
                label = label .. " · " .. (badges ~= "" and (badges .. " ") or "") .. atlas.displaySourceText(loc.condition)
            elseif badges ~= "" then
                label = label .. " · " .. badges
                if #self.covenants == 1 then label = label .. " " .. L(atlas.displayName(self.covenants[1].name)) end
            end
            heading:SetText(label)
            updateItemName()
        end
        local _, _, _, _, _, _, _, restricted, faction = C_MountJournal.GetMountInfoByID(mount.id)
        local sourceFaction = (vendor and vendor.faction) or (sourceView and sourceView.faction) or (loc and loc.faction)
        local localFaction = ({ Alliance = "Альянс", Horde = "Орда", ["Альянс"] = "Альянс", ["Орда"] = "Орда" })[sourceFaction]
        if not localFaction and loc and loc.condition then
            for line in (loc.condition .. "\n"):gmatch("(.-)\n") do
                local header = line:match("^%s*(.-)%s*$")
                if header == "Альянс" or header == "Орда" then localFaction = header; break end
            end
        end
        local factionName = localFaction or (restricted and ({ [0]="Орда", [1]="Альянс" })[faction])
        hideFactionBackgrounds()
        if factionName then
            local inline = compact and not vendor
            local background = factionBackgrounds[inline and 2 or 1]
            local owner = inline and journal or card
            local panelWidth, panelHeight, y = inline and width or 296, inline and height or 64, inline and 0 or 182
            local horde = factionName == "Орда"
            local atlasName = "MountJournalIcons-" .. (horde and "Horde" or "Alliance")
            local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlasName)
            background.emblem:SetAtlas(atlasName, false)
            local emblemHeight = math.min(panelHeight - 12, 100)
            local aspect = info and info.width and info.height and info.width / math.max(1, info.height) or 1
            local emblemWidth = math.min(panelWidth - 12, emblemHeight * aspect)
            background.emblem:ClearAllPoints()
            ui.place(background.emblem, owner, panelWidth - emblemWidth - 10,
                y + (panelHeight - emblemHeight) / 2, emblemWidth, emblemHeight)
            background.emblem:Show()
        end
        -- Publish visibility only after the source, geometry and item state are
        -- complete. Native lookup errors remain visible to the error handler.
        journal:SetShown(compact and (not vendor or self.sourceText ~= ""))
        itemBox:SetShown(hasItem)
        owned:SetShown(collected)
        return not vendor and rewardItem or nil
    end
    atlas.refreshSourceDetails = function()
        if panel.mount and card:IsVisible() then panel:update(panel.mount, panel.location, panel.vendor, panel.sourceView) end
    end
    return panel
end
