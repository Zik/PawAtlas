local _, atlas = ...
local ui = atlas.ui
local L = atlas.L
local controls = "Interface\\AddOns\\PawAtlas\\Media\\Controls\\"

local function collectionWithoutChance(progress)
    return progress and type(progress.required) == "number" and progress.required > 1 and progress.perAttempt == nil
end

local function hideTooltip(owner)
    atlas.cancelPendingLink(owner)
    owner.hoveredAchievement, owner.hoveredAchievementText = nil, nil
    owner.achievementNeedsData, owner.achievementTooltipRetry = nil, nil
    owner.pendingItem = nil
    owner:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

-- Keep the owner and request together: a late item response must never reopen a
-- tooltip after leaving its region or selecting a different mount.
local function showItemTooltip(owner, itemID, fallback, link, append, fallbackQuality)
    owner.pendingItem = nil
    owner:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    local function render()
        GameTooltip:SetOwner(owner, "ANCHOR_TOP")
        GameTooltip:ClearLines()
        if C_Item.IsItemDataCachedByID(itemID) then
            if link and not link:match("^item:%d+$") then GameTooltip:SetHyperlink(link)
            else GameTooltip:SetItemByID(itemID) end
        end
        if not GameTooltip:IsOwned(owner) then GameTooltip:SetOwner(owner, "ANCHOR_TOP") end
        if GameTooltip:NumLines() == 0 then
            local quality = select(3, atlas.sourceItemInfo(itemID))
            ui.tooltipTitle(atlas.qualityText(fallback and fallback ~= "" and fallback or RETRIEVING_ITEM_INFO, quality or fallbackQuality))
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

local function showAchievementTooltip(owner, id, text)
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:ClearLines()
    -- The player's Blizzard link carries the completion bits for individual criteria.
    local link = atlas.nativeAchievementLink(id)
    if link then GameTooltip:SetHyperlink(link) end
    owner.achievementNeedsData = GameTooltip:NumLines() == 0
    if GameTooltip:NumLines() == 0 then
        local actualID, name, _, _, _, _, _, description
        if GetAchievementInfo then actualID, name, _, _, _, _, _, description = GetAchievementInfo(id) end
        local exact = not (issecretvalue and (issecretvalue(actualID) or issecretvalue(name) or issecretvalue(description)))
            and actualID == id
        local title = type(text) == "string" and (text:match("|h(.-)|h") or text)
        ui.tooltipTitle(exact and name or title)
        if exact and description and description ~= "" then ui.tooltipLine(description, 1, 1, 1, true) end
    end
    owner.hoveredAchievement = id
    owner.hoveredAchievementText = text
    GameTooltip:Show()
    if owner.achievementNeedsData and not owner.achievementTooltipRetry then
        local request = {}
        owner.achievementTooltipRetry = request
        C_Timer.After(.25, function()
            if owner.achievementTooltipRetry == request and owner.hoveredAchievement == id and owner.achievementNeedsData
                and owner:IsVisible() and owner:IsMouseOver() and GameTooltip:IsShown() and GameTooltip:IsOwned(owner) then
                showAchievementTooltip(owner, id, owner.hoveredAchievementText)
            end
        end)
    end
end

function ui.criteriaProgressBar(parent, x, y)
    local bar = ui.place(CreateFrame("Frame", nil, parent), parent, x, y, 158, 39)
    ui.fill(bar, -9, 1, 1, 32, { .30, .38, .42, .55 })
    local label = ui.text(bar, 0, 0, 158, 21, 12, "", ui.paper)
    label:SetMaxLines(1)
    local track = ui.fill(bar, 0, 25, 149, 4, ui.rule)
    local fill = ui.fill(bar, 0, 25, 1, 4, ui.mint)
    fill:SetDrawLayer("ARTWORK", 1)
    local function showChain(self)
        if not self.chain then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(atlas.dataName(self.chain))
        ui.tooltipSourceText(ui.questChainTooltip(self.chain, self.grant, self.chain.finalQuest))
        GameTooltip:Show()
    end
    bar:SetScript("OnEnter", showChain)
    bar:SetScript("OnLeave", hideTooltip)
    bar:SetScript("OnHide", hideTooltip)
    function bar:update(value, total, chain, grant)
        local visible = value ~= nil and total ~= nil and total > 1
        self.chain, self.grant = chain, grant
        self:EnableMouse(visible and chain ~= nil and grant ~= nil)
        self:SetShown(visible)
        if not visible then return false end
        local fraction = math.max(0, math.min(1, value / total))
        label:SetText(L("Выполнено: %d / %d", value, total))
        fill:SetShown(fraction > 0)
        fill:SetWidth(math.max(.01, track:GetWidth() * fraction))
        fill:SetColorTexture(ui.gold[1] + (.33 - ui.gold[1]) * fraction,
            ui.gold[2] + (.78 - ui.gold[2]) * fraction, ui.gold[3])
        if GameTooltip:IsOwned(self) then
            if chain and grant then showChain(self) else hideTooltip(self) end
        end
        return true
    end
    bar:Hide()
    return bar
end

-- Additional card areas use Blizzard's full source text in the tooltip when it
-- exceeds the available rows. Item quality comes from the mount-teaching item.
function atlas.cardDetails(card, pagerArrow)
    local panel = {}
    local width = card:GetWidth()
    local journal = ui.place(CreateFrame("Frame", nil, card), card, 0, 196, width, 64)
    journal:EnableMouse(true)
    journal:SetHyperlinksEnabled(true)
    local sourceBodyRule = ui.fill(journal, 16, 0, width - 36, 1, { .30, .38, .42, .55 })
    local progressLeft = width - 178
    local progressBar = ui.criteriaProgressBar(journal, progressLeft, 8)
    local journalIcon = ui.icon(journal, 11, 10, 18, "Scroll")
    local journalHeading = ui.text(journal, 38, 8, 610, 18, 12, "", ui.gold)
    journalHeading:SetWordWrap(false)
    journalHeading:SetMaxLines(1)
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
    local function guideText(guide)
        return guide and (atlas.getLocale() == "enUS" and guide.englishText or guide.text)
    end
    local function directQuestTitle(reward, id)
        if reward then
            for _, quest in ipairs(reward.prerequisites or {}) do
                if quest.id == id then return atlas.dataName(quest) end
            end
            for _, quest in ipairs(reward.quests) do
                if quest.id == id then return atlas.dataName(quest) end
            end
        end
    end
    local function appendQuestGuide(reward)
        local guide, prerequisites = panel.routeGuide, reward.prerequisites
        local text = guideText(guide and (guide.quest or guide))
        if text then
            ui.tooltipLine(" ")
            ui.tooltipSourceText(text)
        end
        if prerequisites then
            ui.tooltipLine(" ")
            local index = 0
            for _, steps in ipairs({ prerequisites, reward.quests }) do
                for _, quest in ipairs(steps) do
                    index = index + 1
                    ui.tooltipLine(("%d. |cffffd200%s|r"):format(index, atlas.dataName(quest)), unpack(ui.paper))
                end
            end
        end
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
        local event = mount.unavailable and legacy and ((english and legacy.englishEvent) or legacy.event)
        local historical = panel.sourceClassification and panel.sourceClassification.state == "historical"
        local historicalAchievements = historical and atlas.historicalAchievementSource(mount)
        local alternatives = (legacy and (legacy.alternatives or legacy.history))
            or (atlas.tradingPostOffer and atlas.tradingPostOffer(mount))
        local guide = guideText(panel.routeGuide)
        if guide or panel.sourceTruncated or journalText:IsTruncated() or alternatives or historicalAchievements then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(L(historical and "История" or event or ui.sourceAppearance(panel.sourceClassification) or mount.kind))
            ui.tooltipSourceText(guide or panel.sourceText or mount.journalSource, mount.unavailable and { 1, .67, .39 })
            if historicalAchievements then ui.tooltipSourceText(historicalAchievements) end
            ui.tooltipSourceAlternatives(mount, panel.sourceClassification and panel.sourceClassification.stock ~= nil
                or panel.sourceView and panel.sourceView.tradingPost)
            GameTooltip:Show()
        end
    end
    journal:SetScript("OnLeave", hideTooltip)
    journal:SetScript("OnHide", hideTooltip)
    journal:SetScript("OnHyperlinkEnter", function(self, link, text)
        local instanceID = atlas.sourceJournalInstanceID(link)
        if instanceID then
            local title, description
            if EJ_GetInstanceInfo then title, description = EJ_GetInstanceInfo(instanceID) end
            title = (text and (text:match("|h(.-)|h") or text)) or title
            if title and title ~= "" then
                hideTooltip(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                ui.tooltipTitle(title)
                if description and description ~= "" then ui.tooltipSourceText(description) end
                GameTooltip:Show()
            end
            return
        end
        local kind, id = link:match("^(%a+):(%d+)")
        id = tonumber(id)
        if kind == "pawatlascost" or kind == "pawatlascoin" then
            local caption = link:match("^pawatlascost:0:(.+)$")
            if kind == "pawatlascoin" then
                local coinText = C_CurrencyInfo and C_CurrencyInfo.GetCoinText or GetCoinText
                caption = coinText and coinText(id)
            end
            hideTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(caption or RETRIEVING_ITEM_INFO)
            GameTooltip:Show()
            return
        end
        if not id or id <= 0 then return end
        if kind == "item" then
            self.hoveredAchievement, self.hoveredAchievementText = nil, nil
            local reagent = atlas.protoformReagentNames[id] or atlas.craftReagentInfo[id]
            local caption = text and (text:match("|h(.-)|h") or text):gsub("|T.-|t", ""):gsub("|A.-|a", "")
                :match("^%s*(.-)%s*$")
            local fallback = reagent and atlas.itemDisplayName(reagent) or caption ~= "" and caption or atlas.itemReferenceName(id)
            showItemTooltip(self, id, fallback, link)
        elseif kind == "currency" then
            hideTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:SetCurrencyByID(id)
            if GameTooltip:NumLines() == 0 then
                local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
                ui.tooltipTitle(info and info.name or RETRIEVING_DATA or RETRIEVING_ITEM_INFO)
            end
            GameTooltip:Show()
        elseif kind == "quest" then
            hideTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:ClearLines()
            GameTooltip:SetHyperlink(link)
            if not GameTooltip:IsOwned(self) then GameTooltip:SetOwner(self, "ANCHOR_TOP") end
            local chain, grant = panel.questChain, panel.chainGrant
            local sourceQuest = panel.sourceQuest and panel.sourceQuest.id == id and panel.sourceQuest
            local directTitle = directQuestTitle(panel.directQuestReward, id)
            local chainTitle = sourceQuest and atlas.dataName(sourceQuest) or chain and atlas.questChainTitle(chain, id) or directTitle
            local nativeTitle = chainTitle and C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
            local missingTitle = chainTitle and (issecretvalue and issecretvalue(nativeTitle)
                or type(nativeTitle) ~= "string" or nativeTitle == "")
            if missingTitle then GameTooltip:ClearLines() end
            if GameTooltip:NumLines() == 0 then
                local title = chainTitle or text and (text:match("|h(.-)|h") or text)
                if title and title ~= "" then ui.tooltipTitle(title, 1, .82, 0) end
            end
            if sourceQuest and sourceQuest.tooltip then
                ui.tooltipLine(" ")
                ui.tooltipSourceText(atlas.getLocale() == "enUS" and sourceQuest.englishTooltip or sourceQuest.tooltip)
            elseif chain and grant and (chainTitle or id == chain.firstQuest) then
                if GameTooltip:NumLines() == 0 then ui.tooltipTitle(atlas.dataName(chain)) end
                ui.tooltipLine(" ")
                ui.tooltipSourceText(ui.questChainTooltip(chain, grant, id, panel.note))
            end
            if directTitle then appendQuestGuide(panel.directQuestReward) end
            GameTooltip:Show()
        elseif kind == "pawatlasmission" then
            hideTooltip(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            local title = C_Garrison and C_Garrison.GetMissionName and C_Garrison.GetMissionName(id)
            title = title or (text and (text:match("|h(.-)|h") or text))
            if title and title ~= "" then
                ui.tooltipTitle(title)
                GameTooltip:Show()
            end
        elseif kind == "achievement" then
            hideTooltip(self)
            showAchievementTooltip(self, id, text)
        end
    end)
    journal:SetScript("OnHyperlinkClick", function(self, link, text, button)
        if button ~= "LeftButton" then return end
        local questID = tonumber(link:match("^quest:(%d+)"))
        if questID and panel.questChain then text = atlas.questChainTitle(panel.questChain, questID) or text end
        if IsShiftKeyDown() then atlas.linkSource(link, self, text); return end
        local id = tonumber(link:match("^achievement:(%d+)"))
        if id then atlas.openAchievement(id)
        else
            local _, err = atlas.openSourceReference(link, self, text)
            if err and UIErrorsFrame then UIErrorsFrame:AddMessage(err, 1, .1, .1) end
        end
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
    function panel:bindSourceLinks(owner)
        owner:EnableMouse(true)
        owner:SetHyperlinksEnabled(true)
        for _, script in ipairs({ "OnLeave", "OnHide", "OnHyperlinkEnter", "OnHyperlinkLeave", "OnHyperlinkClick" }) do
            owner:SetScript(script, journal:GetScript(script))
        end
    end


    local itemBox = ui.place(CreateFrame("Frame", nil, card), card, 0, 265, width, 60)
    itemBox:EnableMouse(true)
    itemBox.rule = ui.fill(itemBox, 16, 0, card:GetWidth() - 36, 1, { .30, .38, .42, .55 })
    local itemIcon, itemBorder = ui.squareIcon(itemBox, 16, 16, 23)
    local itemGlyph = ui.icon(itemBox, 16, 16, 23, "Loot")
    itemBorder:ClearAllPoints()
    itemBorder:SetPoint("LEFT", itemBox, "LEFT", 16, 0)
    itemGlyph:ClearAllPoints()
    itemGlyph:SetPoint("LEFT", itemBox, "LEFT", 16, 0)
    local itemHeading = ui.place(CreateFrame("Frame", nil, itemBox), itemBox, 49, 5, 594, 17)
    panel:bindSourceLinks(itemHeading)
    local heading = ui.text(itemHeading, 0, 0, 594, 17, 11, "", ui.muted)
    heading:ClearAllPoints()
    heading:SetAllPoints(itemHeading)
    heading:SetMaxLines(1)
    local itemName = ui.text(itemBox, 49, 22, 594, 22, 16, "", ui.gold)
    itemName.atlasGameText = true
    itemName:SetMaxLines(1)
    local itemCheck = ui.icon(itemBox, 628, 22, 20, "ObjectiveComplete")
    itemCheck:Hide()
    local itemAttempts = ui.text(itemBox, width - 318, 5, 302, 21, 14, "", ui.muted)
    itemAttempts:SetJustifyH("RIGHT")
    itemAttempts:SetMaxLines(1)
    local itemChanceHelp = CreateFrame("Frame", nil, itemBox)
    itemChanceHelp:SetPoint("TOPRIGHT", itemBox, "TOPRIGHT", -12, -5)
    itemChanceHelp:SetHeight(21)
    itemChanceHelp:EnableMouse(true)
    local function showItemChance(self)
        local progress = panel.itemProgress
        if not progress then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self.hasAttempts then
            ui.attemptTooltip(progress.attempts)
            ui.attemptShareHint()
        elseif self.showChance then
            local step = math.max(1, math.min(#ui.chanceFlavors, math.ceil(progress.cumulative * 10)))
            ui.tooltipTitle(L(ui.chanceFlavors[step]), itemAttempts:GetTextColor())
        end
        GameTooltip:Show()
    end
    itemChanceHelp:SetScript("OnMouseUp", function(self, button)
        if self.hasAttempts and button == "LeftButton" and IsShiftKeyDown() then
            atlas.shareItemAttempts(panel.itemProgress)
        end
    end)
    itemChanceHelp:SetScript("OnEnter", showItemChance)
    itemChanceHelp:SetScript("OnLeave", hideTooltip)
    itemChanceHelp:SetScript("OnHide", hideTooltip)
    itemChanceHelp:Hide()
    local itemTrack = ui.fill(itemBox, 58, 53, 594, 3, ui.rule)
    itemTrack:SetAlpha(.65)
    local itemFill = ui.fill(itemBox, 58, 53, 1, 3, ui.mint)
    itemAttempts:Hide(); itemTrack:Hide(); itemFill:Hide()
    local function updateItemName()
        local item = panel.item
        if not item then return end
        local name = atlas.qualityText(item.name or RETRIEVING_ITEM_INFO, item.quality)
        itemName:SetText(name .. (item.required and ("  ×" .. item.required) or ""))
        local icon = item.item and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item.item)
        local hasIcon = not (issecretvalue and issecretvalue(icon))
            and (type(icon) == "number" and icon > 0 or type(icon) == "string" and icon ~= "")
        if not hasIcon and item.icon then icon, hasIcon = item.icon, true end
        if hasIcon then
            itemIcon:SetTexture(icon)
            itemIcon:SetTexCoord(.07, .93, .07, .93)
        end
        itemIcon:SetShown(hasIcon)
        itemBorder:SetShown(hasIcon)
        itemGlyph:SetShown(not hasIcon)
    end
    local function appendItemContext()
        if panel.progressChoice and panel.progressChoice.factionGift then return end
        local item = panel.item
        local progress = panel.itemProgress
        local collectionOnly = collectionWithoutChance(progress)
        local gathered = progress and atlas.itemCollectionCount and atlas.itemCollectionCount(panel.mount)
        local hasStats = progress and (gathered ~= nil or not collectionOnly
            and (progress.attempts ~= nil or progress.perAttempt ~= nil or not progress.collection))
            or not progress and item.basis ~= "drop" and item.basis ~= "teaching"
        local chainStarter = panel.questChain and panel.chainGrant and item.item == panel.questChain.starter
        local starterID = panel.directQuestReward and panel.directQuestReward.starter
        local itemStarter = starterID and item.item == starterID
        local quest = not (chainStarter or itemStarter) and panel.mount.quest
        if quest or (panel.covenants and #panel.covenants > 0) or hasStats then ui.tooltipLine(" ") end
        if quest then ui.tooltipLine(L("Квест: %s", quest)) end
        if panel.covenants and #panel.covenants > 0 then
            local names = {}
            for _, covenant in ipairs(panel.covenants) do names[#names + 1] = atlas.displayName(covenant.name) end
            ui.tooltipLine(L("Ковенант: %s", table.concat(names, ", ")), 1, 1, 1, true)
        end
        if progress then
            if gathered ~= nil then ui.tooltipLine(L("Собрано: %s", gathered), 1, 1, 1) end
            if not collectionOnly and progress.collected ~= nil and progress.required then
                ui.tooltipLine(L("В наличии: %s / %s", progress.collected, progress.required), 1, 1, 1)
                ui.tooltipLine(L("Сумки, банк персонажа и банк отряда"), ui.muted[1], ui.muted[2], ui.muted[3], true)
                if progress.attempts ~= nil or progress.perAttempt ~= nil then ui.tooltipLine(" ") end
            end
            if not collectionOnly and progress.attempts ~= nil then ui.tooltipLine(L("Попытки: %s", progress.attempts), 1, 1, 1) end
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
            elseif not progress.collection and not collectionOnly then ui.tooltipLine(L("Шанс добычи самого предмета неизвестен.")) end
        elseif item.basis ~= "drop" and item.basis ~= "teaching" then
            if item.rate then
                ui.tooltipLine(L("Шанс: %s", ui.probabilityText(1 / item.rate, item.rate == 1)), 1, 1, 1)
            else ui.tooltipLine(L("Шанс добычи самого предмета неизвестен.")) end
        end
        local reward = atlas.guaranteedRewards and atlas.guaranteedRewards[panel.mount.id]
        local raidLoot = panel.raidLoot
        local seen, separated = {}, false
        local function instruction(text)
            if not text or text == "" or seen[text] then return end
            seen[text] = true
            if not separated then ui.tooltipLine(" "); separated = true end
            ui.tooltipSourceText(atlas.sourceInlineLinks(text), ui.gold)
        end
        if not chainStarter then
            instruction(reward and (atlas.getLocale() == "enUS" and reward.englishCondition or L(reward.condition)))
        end
        if not chainStarter or panel.mount.note ~= panel.chainGrant.condition then
            instruction(panel.mount.note and L(panel.mount.note))
        end
        instruction(panel.sourceView and panel.sourceView.conditions and atlas.displaySourceText(panel.sourceView.conditions))
        instruction(raidLoot and raidLoot.condition and (atlas.getLocale() == "enUS" and raidLoot.englishCondition or L(raidLoot.condition)))
        local guide = panel.routeGuide
        instruction(guideText(guide and (itemStarter and guide.starter or guide)))
    end
    -- Retail can rebuild native item lines asynchronously; append context on
    -- each rebuild, restricted to this card's tooltip rather than all items.
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip == GameTooltip and tooltip:IsOwned(itemBox) and itemBox:IsVisible() and panel.item then
            appendItemContext()
        end
    end)
    local function showItemBox(self)
        local item = panel.item
        if not item then return end
        if item.item then
            showItemTooltip(self, item.item, item.name, nil, appendItemContext, item.quality)
        else
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            ui.tooltipTitle(item.name)
            appendItemContext()
            GameTooltip:Show()
        end
    end
    itemBox:SetScript("OnEnter", showItemBox)
    itemBox:SetScript("OnLeave", hideTooltip)
    itemBox:SetScript("OnHide", hideTooltip)
    itemBox:SetScript("OnMouseUp", function(self, button)
        atlas.cancelPendingLink(self)
        if button ~= "LeftButton" or not panel.item or not panel.item.item then return end
        if IsModifiedClick and IsModifiedClick("DRESSUP") then
            local mount = atlas.itemPreviewMount(panel.item.item)
            if mount then atlas.previewMount(mount) end
        elseif IsShiftKeyDown() then atlas.linkItem(panel.item.item, self) end
    end)

    atlas.bindMountPreviewCursor(itemBox, function()
        return panel.item and atlas.itemPreviewMount(panel.item.item)
    end)
    local sourceEmblem = card:CreateTexture(nil, "BACKGROUND", nil, 3)
    local journalEmblem = journal:CreateTexture(nil, "BACKGROUND", nil, 3)
    local function hideFactionBackgrounds()
        sourceEmblem:Hide()
        journalEmblem:Hide()
    end
    local factionAtlasNames = {
        Alliance = "MountJournalIcons-Alliance", Horde = "MountJournalIcons-Horde",
        ["Альянс"] = "MountJournalIcons-Alliance", ["Орда"] = "MountJournalIcons-Horde",
    }
    local function resolveFactionAtlas(mount, loc, vendor, view)
        local route = view and factionAtlasNames[view.faction]
        if vendor then return factionAtlasNames[vendor.faction] or route end
        local point = factionAtlasNames[atlas.sourcePointFaction(loc)]
        if point or route or (loc and loc.npc) then return point or route end
        if factionAtlasNames[mount.faction] then return factionAtlasNames[mount.faction] end
        local _, _, _, _, _, _, _, restricted, faction = C_MountJournal.GetMountInfoByID(mount.id)
        if restricted and faction == 0 then return factionAtlasNames.Horde end
        if restricted and faction == 1 then return factionAtlasNames.Alliance end
    end
    local function placeFactionEmblem(texture, owner, name, aspect, right, top, height, widthLimit)
        local emblemHeight = math.min(height - 8, widthLimit / aspect)
        local emblemWidth = emblemHeight * aspect
        texture:SetAtlas(name, false)
        texture:ClearAllPoints()
        ui.place(texture, owner, right - emblemWidth, top + (height - emblemHeight) / 2, emblemWidth, emblemHeight)
        texture:Show()
        return emblemWidth
    end

    local sourcePager = ui.place(CreateFrame("Frame", nil, journal), journal, 546, 7, 108, 24)
    sourcePager:SetFrameLevel(journalContent:GetFrameLevel() + 2)
    local pageNumber = ui.text(sourcePager, 29, 0, 50, 24, 12, "", ui.muted)
    pageNumber:SetJustifyH("CENTER")
    local function turnPage(delta)
        if panel.sourcePageCount > 1 then
            panel.sourcePage = (panel.sourcePage - 1 + delta) % panel.sourcePageCount + 1
        else return end
        panel:update(panel.mount, panel.location, panel.vendor, panel.sourceView)
        if panel.refreshLayout then panel:refreshLayout() end
    end
    pagerArrow(sourcePager, 0, 25, 24, -1, turnPage)
    pagerArrow(sourcePager, 83, 25, 24, 1, turnPage)
    sourcePager:Hide()

    function panel:deduplicatePlace(body)
        if body == "" then return body end
        local place = self.activeSummaryPlace
        local view, point = self.sourceMapView, self.summaryPoint
        local mapID = place and atlas.sourceMapID(place, point, view)
        body = ui.deduplicateSourceFields(body, place, self.visibleCovenant, self.addressSource, mapID)
        if not mapID or body == "" then return body end
        local lines, removed = {}, false
        for line in (body .. "\n"):gmatch("(.-)\n") do
            local name = ui.singleSourcePlace(line)
            if name and atlas.sourceMapID(name, point, view) == mapID then removed = true
            else lines[#lines + 1] = line end
        end
        return removed and table.concat(lines, "\n"):match("^%s*(.-)%s*$") or body
    end

    function panel:update(mount, loc, vendor, sourceView)
        self.periodicDone, self.periodicTotal, self.directQuestSteps = nil, nil, nil
        if self.progressChoice then
            if atlas.periodicQuestChains[mount.id] then
                self.periodicDone, self.periodicTotal = atlas.periodicQuestProgress(mount, self.progressChoice)
            else
                self.directQuestSteps = atlas.questRewardProgressSteps(self.directQuestReward)
                self.periodicDone, self.periodicTotal = atlas.questRewardChainProgress(self.directQuestReward, self.directQuestSteps)
            end
        end
        if self.mount ~= mount then self.sourcePage = 1 end
        local vendorKey = vendor and table.concat({ vendor.name or "", vendor.place or "", vendor.conditions or "", vendor.faction or "" }, "\001")
        local sourceKey = sourceView and table.concat({ sourceView.boss or "", sourceView.place or "",
            sourceView.decoratedSource or sourceView.journalSourceRaw or "", sourceView.conditions or "", sourceView.faction or "" }, "\001")
        local locationCondition = atlas.sourcePointCondition(loc)
        local locationKey = loc and table.concat({ loc.map or "", loc.npc or "", loc.boss or "", loc.place or "",
            loc.x or "", loc.y or "", locationCondition or "", loc.faction or "" }, "\001")
        if self.vendorKey ~= vendorKey or self.sourceKey ~= sourceKey then self.sourcePage = 1 end
        local changed = self.mount ~= mount or self.locationKey ~= locationKey or self.vendorKey ~= vendorKey or self.sourceKey ~= sourceKey
            or self.lastSourcePage ~= self.sourcePage
        if changed then
            local owner = GameTooltip:GetOwner()
            if owner and owner.hoveredAchievement then hideTooltip(owner) end
            self.achievementRefresh = nil
            hideTooltip(journal)
            hideTooltip(journalContent)
            hideTooltip(itemBox)
            -- Hide the previous source before resolving the next one. A failed
            -- data lookup must not leave an old achievement over a new vendor.
            journal:Hide()
            itemBox:Hide()
            hideFactionBackgrounds()
        end
        self.mount, self.item, self.location, self.vendor, self.vendorKey = mount, nil, loc, vendor, vendorKey
        self.sourceView = sourceView
        self.locationKey = locationKey
        self.sourceText, self.sourceHasAchievement = nil, false
        self.routeGuide = atlas.questRouteGuide(mount, self.progressChoice)
        self.sourceKey = sourceKey
        self.lastSourcePage = self.sourcePage
        self.covenants = atlas.mountCovenantRequirements and atlas.mountCovenantRequirements(sourceView or mount) or {}
        local requirements = self.sourceRequirements
        local condition = requirements and (atlas.getLocale() == "enUS" and requirements.englishCondition or requirements.condition)
        local contextOnly = sourceView and sourceView.contextOnly
        local route = self.sourceClassification
        local raidLoot = atlas.raidLootReward and atlas.raidLootReward(mount)
        if raidLoot and raidLoot.groupRate and not atlas.raidLootGuaranteeForSource(mount,
            { view = sourceView, classification = route, vendor = vendor }) then raidLoot = nil end
        self.raidLoot = raidLoot
        local ownReward = not contextOnly and not (sourceView and (sourceView.tradingPost or sourceView.separateReward))
        local choice = self.progressChoice
        local barter = vendor and vendor.redemption == "barter" and atlas.sourceGuaranteedReward(mount, choice)
        local questView = sourceView or mount
        local questItem = not vendor and not self.interaction and ownReward and atlas.questRewardItem(mount, self.directQuestReward,
            questView.decoratedSource or questView.journalSourceOverride or questView.journalSourceRaw or questView.journalSource)
        local loot = not vendor and not self.interaction and ownReward and atlas.lootItems[mount.id]
        if self.directQuestReward and loot and (not loot.basis or loot.basis == "drop" or loot.basis == "teaching") then loot = nil end
        local rewardItem = choice and choice.factionGift or requirements and requirements.reward
            or barter and barter.reward or loot or questItem
        if choice and choice.islandExpedition and rewardItem and rewardItem.basis == "open" then
            rewardItem = atlas.rewardItem(mount, loc, true)
        end
        local progress = not self.interaction and not vendor and not mount.availability and not (sourceView and sourceView.trackingCompatible == false)
            and atlas.itemAttemptProgress and atlas.itemAttemptProgress(mount) or nil
        local missingRewardItem = not rewardItem or (not rewardItem.item and (not rewardItem.basis or rewardItem.basis == "drop"))
        local displayItem = not self.interaction and ownReward and missingRewardItem and not (progress and progress.item) and not vendor
            and not self.directQuestReward
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
            item.name = progress.name or (rewardItem and rewardItem.item == progress.item and rewardItem.name)
            item.englishName = progress.englishName or (rewardItem and rewardItem.item == progress.item and rewardItem.englishName) or nil
            item.rate = progress.perAttempt and progress.perAttempt > 0 and 1 / progress.perAttempt or nil
            if progress.collection then item.basis = "ingredient" end
            self.item = item
        end
        local starterID = self.questChain and self.questChain.starter or self.directQuestReward and self.directQuestReward.starter
        local stage = starterID and atlas.attemptStages[mount.id]
        local starter = stage and stage.item
        if starter and starter.item == starterID and (not self.item or self.item.item ~= starter.item) then
            self.item = { item = starter.item, name = starter.name, englishName = starter.englishName }
        end
        self.starterChance, self.starterRateEstimated = nil, false
        if self.finalQuest then
            local record = starter or (stage and stage.reward)
            if record and record.item == self.finalQuest.starter and type(record.rate) == "number" and record.rate >= 1 then
                self.starterChance = 1 / record.rate
                self.starterRateEstimated = record.rateEstimated == true
            end
        end
        if self.item and self.item.item then
            local item = self.item
            local cachedName, _, quality = atlas.sourceItemInfo(item.item)
            item.name = atlas.itemDisplayName(item, cachedName) or atlas.itemReferenceName(item.item)
            item.quality = quality or item.quality
        end
        self.containerItem = not vendor and not mount.availability and ownReward and self.item and self.item.name
            and (self.item.basis == "open" or self.item.basis == "cage") and self.item or nil
        local compact = not self.interaction and (not self.structured or vendor ~= nil)
        local factionAtlas = resolveFactionAtlas(mount, self.factionPoint or loc, vendor, sourceView)
        local factionInfo = factionAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(factionAtlas)
        local factionAspect = factionInfo and (factionInfo.width or 0) > 0 and (factionInfo.height or 0) > 0
            and factionInfo.width / factionInfo.height or 1
        local inlineFaction = factionAtlas and not self.structured and compact and not vendor
        self.sourceInset = 0
        hideFactionBackgrounds()
        local row = self.sourceRow
        if factionAtlas and self.structured then
            local width = placeFactionEmblem(sourceEmblem, card, factionAtlas, factionAspect,
                row.sourceRight or 307, row.heading - 2, row.bottom - row.heading, 84)
            self.sourceInset = width + 14
        end
        local sourceMount = vendor and { id = mount.id, spell = mount.spell, faction = vendor.faction,
            journalSourceRaw = vendor.conditions or "", vendorName = vendor.name,
            vendorPriceResolved = vendor.priceResolved } or sourceView or mount
        local sourcePages = compact and not vendor and atlas.covenantSourcePages(sourceMount)
        self.sourcePageCount = sourcePages and #sourcePages or 0
        local hasPager = self.sourcePageCount > 1
        local rightInset = 15
        if sourcePages then
            self.sourcePage = math.max(1, math.min(self.sourcePage or 1, #sourcePages))
            sourceMount = { id = mount.id, journalSourceRaw = sourcePages[self.sourcePage] }
            self.covenants = atlas.mountCovenantRequirements({ journalSourceRaw = sourceMount.journalSourceRaw })
            pageNumber:SetText(self.sourcePage .. " / " .. #sourcePages)
        end
        self.sourceText = condition and atlas.sourceInlineLinks(condition)
            or atlas.sourceWithoutDifficulty(mount, sourceMount.decoratedSource or atlas.decorateSource(sourceMount))
        self.activeSummaryPlace = sourcePages and ui.singleSourcePlace(self.sourceText) or self.summaryPlace
        if self.setSummaryPlace then self.setSummaryPlace(self.activeSummaryPlace) end
        local item = self.item
        local hasItem = (not vendor or barter) and item and item.name ~= nil
        local craftedItem = route and route.key == "profession" and atlas.craftedMountItem(mount)
        self.visibleCovenant = nil
        if hasItem then
            local label = L((requirements or questItem and item.item == questItem.item) and "Награда"
                or ({ ingredient="Собрать", egg="Выбить и дождаться созревания", open="Открыть", cage="Открыть",
                teaching="Предмет маунта" })[item.basis] or route and route.key ~= "loot" and "Награда" or "Добыча")
            if raidLoot then
                label = raidLoot.quantity == 1 and L("Добыча · 1 маунт на рейд") or L("Добыча · %d маунта на рейд", raidLoot.quantity)
            end
            if craftedItem then label = L(item.item == craftedItem and "Результат рецепта" or "Собрать") end
            if starterID and item.item == starterID then
                label = L("Предмет для начала цепочки")
            elseif mount.quest then
                local reward = atlas.guaranteedRewards and atlas.guaranteedRewards[mount.id]
                label = reward and reward.reagent and reward.reagent.completionQuest and L("Квест")
                    or L("Начинает квест %s", mount.quest)
            end
            local sigils = {}
            for _, covenant in ipairs(self.covenants) do sigils[#sigils + 1] = "|T" .. covenant.texture .. ":16:16:0:0|t" end
            local badges = table.concat(sigils, " ")
            local covenant
            local rawCondition = loc and type(loc.condition) == "string" and loc.condition or ""
            if locationCondition and not rawCondition:find("Альянс") and not rawCondition:find("Орда") then
                label = label .. " · " .. (badges ~= "" and (badges .. " ") or "") .. atlas.displaySourceText(locationCondition)
                if #self.covenants == 1 and atlas.displayName(locationCondition) == atlas.displayName(self.covenants[1].name) then
                    covenant = self.covenants[1]
                end
            elseif badges ~= "" then
                label = label .. " · " .. badges
                if #self.covenants == 1 then
                    covenant = self.covenants[1]
                    label = label .. " " .. L(atlas.displayName(covenant.name))
                end
            end
            local headingWidth = progress and not self.collected and not progress.acquired and 286 or width - 74
            itemHeading:SetWidth(headingWidth)
            itemHeading:EnableMouse(label:find("|H", 1, true) ~= nil)
            heading:SetText(atlas.cardItemIcons(label))
            if covenant and heading:GetUnboundedStringWidth() <= headingWidth then self.visibleCovenant = covenant end
            updateItemName()
        end
        if route and route.state == "historical" then
            if mount.availability and mount.availability.unique then
                self.sourceText = ""
            else
                self.sourceText = ui.historicalSourceBody(mount, self.sourceText)
                if self.sourceText == "" and mount.unavailable then self.sourceText = L("Недоступно для получения") end
            end
        elseif not vendor then
            self.sourceText = ui.compactSourceBody(self.sourceText, route)
        end
        if self.sourceText == "" and not self.collected and mount.unknownSourceNote then
            self.sourceText = L(mount.unknownSourceNote)
        end
        if hasItem then self.sourceText = ui.withoutDisplayedItem(self.sourceText, item) end
        if self.containerItem then
            local reward = atlas.rewardItem and atlas.rewardItem(mount, loc, true)
            if reward and reward.item ~= self.containerItem.item and not self.sourceText:find("|Hitem:" .. reward.item .. "%D") then
                local name = atlas.dataName(reward) or atlas.itemReferenceName(reward.item)
                local link = atlas.sourceItemReference(reward.item, name)
                local prefix = self.sourceText ~= "" and (self.sourceText .. "\n") or ""
                self.sourceText = prefix .. L("Награда") .. ": " .. link
            end
        end
        if self.questChain and self.chainGrant then
            self.sourceText = ui.withoutChainQuest(self.sourceText, self.questChain)
            if self.questChain.stageTitle then
                self.sourceText = ui.addRouteText(ui.questChainSummary(self.questChain), self.sourceText)
            end
        elseif self.routeRequirement then
            self.sourceText = ui.addRouteText(self.sourceText, self.routeRequirement)
        end
        self.sourceText = ui.withQuestRewards(self.sourceText, self.directQuestReward)
        if self.structured and self.sourcePresentation then
            local presentation = self.sourcePresentation
            self.sourceText = ui.structuredLootBody(self.sourceText, presentation.target, presentation.place, presentation.points,
                route and route.subtype == "Рарка")
        end
        local encounterNote = loc and route and route.key == "loot" and atlas.rareEncounterNotes[loc.npc]
        if encounterNote then
            self.sourceText = ui.addRouteText(self.sourceText, atlas.getLocale() == "enUS" and encounterNote.englishText or encounterNote.text)
        end
        if craftedItem then
            local reagents = atlas.mountCraftReagentText(craftedItem)
            if reagents then self.sourceText = ui.addRouteText(self.sourceText, reagents) end
        end
        local stockNote = route and (route.stock == "outOfRotation" and "Нет в ассортименте"
            or route.stock == "unknown" and "Открой Торговую лавку, чтобы проверить ассортимент")
        if stockNote then self.sourceText = self.sourceText ~= "" and self.sourceText .. "\n" .. L(stockNote) or L(stockNote) end
        self.sourceText = self:deduplicatePlace(self.sourceText)
        if self.sourceText == "" then condition = nil end
        for line in (self.sourceText .. "\n"):gmatch("(.-)\n") do
            if line:find("|Hachievement:", 1, true) or line:match("^%s*Великий подвиг:") or line:match("^%s*Feats of Strength:")
                or line:match("^%s*Достижение:") or line:match("^%s*Achievement:") then
                self.sourceHasAchievement = true
                break
            end
        end
        local achievementID
        if route and route.key == "achievement" then
            for id in self.sourceText:gmatch("|Hachievement:(%d+)") do
                if achievementID and achievementID ~= id then achievementID = nil; break end
                achievementID = id
            end
        end
        self.achievementID = tonumber(achievementID)
        local completed, total, achievementReady
        if self.achievementID then
            completed, total, achievementReady = atlas.achievementProgress(self.achievementID)
        elseif not self.finalQuest then
            completed, total = self.periodicDone, self.periodicTotal
        end
        local showProgress = progressBar:update(completed, total, self.questChain, self.chainGrant)
        local sourceY = row.bottom
        journal:ClearAllPoints()
        journal:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -sourceY)
        local content = self.sourceText:match("^%s*(.-)%s*$")
        content = atlas.cardItemIcons(atlas.sourceItemLinks(ui.unavailableText(content)))
        if journalText.atlasRawText ~= content then
            local owner = GameTooltip:GetOwner()
            if (owner == journal or owner == journalContent) and owner.hoveredAchievement
                and not content:find("|Hachievement:" .. owner.hoveredAchievement .. "|", 1, true) then hideTooltip(owner) end
            journalText:SetText(content)
        end
        local inlinePager = hasPager and not condition
        local textY = condition and 26 or 7
        local bottomPadding = 7
        local itemSpace = hasItem and 55 or 0
        local availableHeight = self.bodyEnd - sourceY - textY - bottomPadding - itemSpace
        local compactVendor = vendor and not (choice and choice.islandSalvage)
        local maxHeight = math.min(compactVendor and 92 or (hasItem or contextOnly) and 96 or 155, math.max(18, availableHeight))
        local textLeft = 16
        local emblemWidth, emblemRight
        ui.setFont(journalText, condition and 13 or vendor and 14 or 15)
        ui.setFont(separatorMeasure, vendor and 14 or 15)
        journalText:SetHeight(0)
        if inlineFaction then
            journalText:SetWidth(width - textLeft - 21)
            local bodyHeight = math.min(maxHeight, math.max(18, math.ceil(journalText:GetStringHeight())))
            emblemWidth = math.min(showProgress and 42 or 144, (textY + bodyHeight + bottomPadding - 8) * factionAspect)
            emblemRight = showProgress and progressLeft - 21 or width - rightInset - 8
            rightInset = rightInset + emblemWidth + 16
        end
        sourcePager:SetShown(hasPager)
        sourcePager:ClearAllPoints()
        sourcePager:SetPoint("TOPRIGHT", journal, "TOPRIGHT", -rightInset, -7)
        journalHeading:SetShown(condition ~= nil)
        journalIcon:SetShown(condition ~= nil)
        journalHeading:SetText("Требуется")
        journalHeading:SetTextColor(unpack(vendor and ui.muted or ui.gold))
        ui.setIcon(journalIcon, "Scroll")
        journalIcon:ClearAllPoints()
        ui.place(journalIcon, journal, 16, 7, 18, 18)
        journalHeading:ClearAllPoints()
        ui.place(journalHeading, journal, 42, 7, 610, 18)
        local textWidth = emblemRight and (emblemRight - emblemWidth - 8 - textLeft) or width - 2 * textLeft
        if showProgress then textWidth = math.min(textWidth, width - 220) end
        if inlinePager then textWidth = math.min(textWidth, width - rightInset - 120 - textLeft) end
        journal:SetWidth(width)
        journalHeading:SetWidth(math.max(1, textWidth - (hasPager and 116 or 0)))
        journalText:SetWidth(textWidth)
        journalScroll:ClearAllPoints()
        journalScroll:SetWidth(textWidth)
        journalContent:SetWidth(textWidth)
        separatorMeasure:SetWidth(textWidth)
        -- Allow for glyph descenders and the shadow below inline links and icons.
        local measured = math.max(18, math.ceil(journalText:GetStringHeight())) + 4
        journalText:SetHeight(measured)
        local collected = self.collected
        local visibleHeight = math.min(measured, maxHeight)
        local height = math.max(textY + visibleHeight + bottomPadding, showProgress and 43 or hasPager and 31 or 0)
        if not condition then textY = math.floor((height - visibleHeight) / 2) end
        journalScroll:SetPoint("TOPLEFT", journal, "TOPLEFT", textLeft, -textY)
        journalContent:SetHeight(measured)
        journalScroll:SetHeight(visibleHeight)
        panel.sourceTruncated = measured > visibleHeight
        panel.sourceRange = math.max(0, measured - visibleHeight)
        sourceSlider:ClearAllPoints()
        ui.place(sourceSlider, journal, (inlinePager or showProgress) and textLeft + textWidth + 2 or width - 17,
            textY, 10, visibleHeight)
        sourceSlider:SetMinMaxValues(0, panel.sourceRange)
        sourceThumb:SetHeight(math.max(15, math.min(28, visibleHeight * visibleHeight / measured)))
        sourceSlider:SetShown(panel.sourceRange > 0)
        sourceSlider:SetValue(changed and 0 or math.min(journalScroll:GetVerticalScroll(), panel.sourceRange))
        journal:SetHeight(height)
        if inlineFaction then
            placeFactionEmblem(journalEmblem, journal, factionAtlas, factionAspect, emblemRight, 0,
                showProgress and math.min(height, 47) or height, emblemWidth)
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
        local showJournal = content ~= "" or hasPager or showProgress
        local itemY = sourceY + (showJournal and height or 0)
        itemBox:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -itemY)
        local acquired = hasItem and progress and progress.acquired == true
        itemCheck:SetShown(acquired == true)
        local itemTextWidth = width - 74
        local showProgress = hasItem and progress ~= nil and not collected and not acquired
        local collectionOnly = collectionWithoutChance(progress)
        local probability
        if showProgress and not collectionOnly then
            if self.starterChance then
                -- The summary shows the starter's drop rate. Its bar tracks the attempts, including zero.
                probability = progress.cumulative
            else
                probability = progress.attempts and progress.attempts > 0 and progress.cumulative or progress.perAttempt
            end
        end
        local collection = showProgress and progress.collected ~= nil and progress.required and progress.required > 0
        local showBar = showProgress and (probability ~= nil or collection)
        local itemHeight = showBar and 52 or 46
        itemBox:SetHeight(itemHeight)
        itemName:ClearAllPoints()
        ui.place(itemName, itemBox, 49, 20, itemTextWidth - (acquired and 30 or 0), 22)
        itemCheck:ClearAllPoints()
        ui.place(itemCheck, itemBox, width - 40, (itemHeight - 20) / 2, 20, 20)
        itemAttempts:SetShown(showProgress and (not collectionOnly and progress.attempts ~= nil or probability ~= nil or collection))
        itemChanceHelp.hasAttempts = showProgress and atlas.canShareItemAttempts(progress)
        itemChanceHelp.showChance = showProgress and not collection and progress.cumulative ~= nil
            and progress.perAttempt ~= nil and progress.perAttempt < 1
        itemTrack:SetShown(showBar)
        itemFill:SetShown(showBar and (collection and progress.collected > 0 or probability ~= nil and probability > 0))
        if showProgress then
            local guaranteed = progress.perAttempt == 1
            local count = not collectionOnly and progress.attempts ~= nil and L("Попытки: %s",
                collection and ("|cffe6e9ed" .. progress.attempts .. "|r") or progress.attempts) or ""
            local value = collection and L("В наличии: %s / %s",
                "|cffa1d1ba" .. progress.collected, progress.required .. "|r")
                or probability ~= nil and ui.probabilityText(probability, guaranteed) or ""
            itemAttempts:SetText(count .. (value ~= "" and ((count ~= "" and " · " or "") .. value) or ""))
            itemChanceHelp:SetWidth(math.min(302, math.ceil(itemAttempts:GetUnboundedStringWidth()) + 8))
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
                ui.place(itemTrack, itemBox, 49, 45, itemTextWidth, 3)
                itemFill:SetShown(fill > 0)
                ui.place(itemFill, itemBox, 49, 45,
                    math.max(.01, itemTextWidth * math.max(0, math.min((collection or guaranteed) and 1 or .9999, fill))), 3)
            end
        end
        itemChanceHelp:SetShown(itemChanceHelp.hasAttempts or itemChanceHelp.showChance)
        if itemChanceHelp:IsShown() and GameTooltip:IsShown() and GameTooltip:IsOwned(itemChanceHelp) then
            if itemChanceHelp:IsMouseOver() then showItemChance(itemChanceHelp) else hideTooltip(itemChanceHelp) end
        end
        -- Publish visibility only after the source, geometry and item state are
        -- complete. Native lookup errors remain visible to the error handler.
        journal:SetShown(showJournal)
        if not showJournal or not self.achievementID or achievementReady then
            self.achievementRefresh = nil
        elseif not self.achievementRefresh or self.achievementRefresh.id ~= self.achievementID then
            local request = { id = self.achievementID }
            self.achievementRefresh = request
            local function refresh()
                if self.achievementRefresh ~= request or not journal:IsVisible() then return end
                atlas.refreshSourceDetails()
            end
            C_Timer.After(.25, refresh)
            C_Timer.After(1, refresh)
        end
        sourceBodyRule:SetShown(showJournal and row.hasLine)
        itemBox.rule:SetShown(showJournal or row.hasLine)
        self.endsAt = itemY + (hasItem and itemHeight or 0)
        atlas.refreshMountPreviewCursor(itemBox)
        itemBox:SetShown(hasItem)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(itemBox) then
            if itemBox:IsMouseOver() then showItemBox(itemBox) else hideTooltip(itemBox) end
        end
        return not vendor and rewardItem or nil
    end
    journal:HookScript("OnShow", function(self)
        self:RegisterEvent("ACHIEVEMENT_EARNED")
        self:RegisterEvent("CRITERIA_UPDATE")
    end)
    journal:HookScript("OnHide", function(self)
        panel.achievementRefresh = nil
        self:UnregisterEvent("ACHIEVEMENT_EARNED")
        self:UnregisterEvent("CRITERIA_UPDATE")
    end)
    local criteriaRefreshPending
    journal:SetScript("OnEvent", function(_, event, achievementID)
        local owner = GameTooltip:GetOwner()
        local hovered = owner and owner.hoveredAchievement
        local anyCriteria = event == "CRITERIA_UPDATE"
        if criteriaRefreshPending or not (panel.achievementID and (anyCriteria or achievementID == panel.achievementID)
            or hovered and (anyCriteria or achievementID == hovered)) then return end
        local contextID, contextOwner = panel.achievementID, owner
        criteriaRefreshPending = true
        C_Timer.After(0, function()
            criteriaRefreshPending = nil
            if not journal:IsVisible() then return end
            if contextID and contextID == panel.achievementID then
                local wasShown = progressBar:IsShown()
                local completed, total, ready = atlas.achievementProgress(contextID)
                if ready then panel.achievementRefresh = nil end
                if progressBar:update(completed, total) ~= wasShown then atlas.refreshSourceDetails() end
            end
            if hovered and contextOwner.hoveredAchievement == hovered and GameTooltip:IsOwned(contextOwner)
                and GameTooltip:IsShown() and contextOwner:IsVisible() and contextOwner:IsMouseOver() then
                showAchievementTooltip(contextOwner, hovered, contextOwner.hoveredAchievementText)
            end
        end)
    end)
    atlas.refreshSourceDetails = function()
        if panel.mount and card:IsVisible() then
            panel:update(panel.mount, panel.location, panel.vendor, panel.sourceView)
            if panel.refreshLayout then panel:refreshLayout() end
            if panel.sourceClassification and panel.sourceClassification.key == "achievement" then
                panel:refreshReward()
            end
            local owner = GameTooltip:GetOwner()
            if owner and owner.hoveredAchievement and owner.achievementNeedsData and GameTooltip:IsShown() and owner:IsMouseOver() then
                showAchievementTooltip(owner, owner.hoveredAchievement, owner.hoveredAchievementText)
            end
        end
    end
    return panel
end
