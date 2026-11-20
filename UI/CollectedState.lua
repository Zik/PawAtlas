local _, atlas = ...
local ui = atlas.ui
local controls = "Interface\\AddOns\\PawAtlas\\Media\\Controls\\"

-- Collected mounts use a quiet celebratory footer in place of farming controls.
function atlas.collectedState(card, footerTop)
    local state = CreateFrame("Frame", nil, card)
    state:SetPoint("TOPLEFT", card, "TOPLEFT", -28, -footerTop)
    state:SetPoint("BOTTOMRIGHT", card:GetParent(), "BOTTOMRIGHT", -16, 0)
    state:SetClipsChildren(true)
    local footerHeight = state:GetHeight()
    local ribbon = state:CreateTexture(nil, "BACKGROUND")
    ribbon:SetAllPoints(state)
    ribbon:SetTexture(controls .. "CollectionRibbon.tga")
    -- The art is composed for a 712 × 126 band. Crop its height at the same scale.
    local visibleArt = math.min(1, footerHeight / 126)
    local cropTop = (1 - visibleArt) * .47
    ribbon:SetTexCoord(0, 1, cropTop, cropTop + visibleArt)

    local width, fade, height = card:GetWidth(), 58, 1.25
    local clear = CreateColor(.83, .69, .46, 0)
    local bronze = CreateColor(.83, .69, .46, .42)
    local rule = ui.place(CreateFrame("Frame", nil, state), state, 28, 0, width, height)
    local left = ui.fill(rule, 0, 0, fade, height, { 1, 1, 1 })
    ui.fill(rule, fade, 0, width - 2 * fade, height, { .83, .69, .46, .42 })
    local right = ui.fill(rule, width - fade, 0, fade, height, { 1, 1, 1 })
    left:SetGradient("HORIZONTAL", clear, bronze)
    right:SetGradient("HORIZONTAL", bronze, clear)

    local summon = CreateFrame("Button", nil, state)
    local summonWidth, iconSize, summonGap = 84, 54, 4
    summon:SetPoint("RIGHT", state, "RIGHT", -38, -height / 2)
    summon:SetSize(summonWidth, iconSize)
    summon:RegisterForClicks("LeftButtonUp")
    if summon.SetMotionScriptsWhileDisabled then summon:SetMotionScriptsWhileDisabled(true) end
    local glow = summon:CreateTexture(nil, "BACKGROUND")
    glow:SetPoint("CENTER", summon, "CENTER", 0, -5)
    glow:SetSize(100, 92)
    glow:SetTexture(controls .. "SoftGlow.tga")
    glow:SetVertexColor(.80, .53, .18)
    local mountIcon, border = ui.itemIcon(summon, (summonWidth - iconSize) / 2, 0, iconSize)

    local emblemSize = 80
    local emblemTop = (footerHeight - emblemSize) / 2
    local emblem = state:CreateTexture(nil, "ARTWORK")
    ui.place(emblem, state, 35, emblemTop, emblemSize, emblemSize)
    emblem:SetTexture(controls .. "CollectionEmblem.tga")

    local labelX, labelWidth = 139, 295
    local caption = ui.text(state, labelX, 0, labelWidth, 32, 23, "В коллекции", ui.gold)
    caption:SetMaxLines(1)
    local mountName = ui.text(state, labelX, 0, labelWidth, 42, 15, "", { .74, .75, .76 })
    mountName.atlasGameText = true
    mountName:SetJustifyV("TOP")
    mountName:SetMaxLines(2)
    local function layoutLabels()
        local _, captionSize = caption:GetFont()
        local _, nameSize = mountName:GetFont()
        local captionHeight = math.ceil(math.max(caption:GetStringHeight(), captionSize * 1.2))
        local lineHeight = math.ceil(nameSize * 1.2)
        local twoLines = mountName:GetUnboundedStringWidth() > labelWidth
        local nameHeight = (twoLines and 2 or 1) * lineHeight
        local gap = 5
        local top = emblemTop + (emblemSize - captionHeight - gap - nameHeight) / 2
        caption:ClearAllPoints()
        mountName:ClearAllPoints()
        ui.place(caption, state, labelX, top, labelWidth, captionHeight)
        ui.place(mountName, state, labelX, top + captionHeight + gap, labelWidth, nameHeight)
    end
    local summonLabel = ui.text(summon, 0, iconSize + summonGap, summonWidth, 18, 12, "Призвать", ui.gold)
    summonLabel:SetJustifyH("CENTER")
    summonLabel:SetMaxLines(1)

    local function layoutSummon(shared)
        local _, fontSize = summonLabel:GetFont()
        local labelHeight = math.ceil(math.max(summonLabel:GetStringHeight(), fontSize * 1.2))
        summonLabel:SetHeight(labelHeight)
        summonLabel:SetShown(not shared)
        summon:SetHeight(shared and iconSize or iconSize + summonGap + labelHeight)
    end

    local function readable(value) return not (issecretvalue and issecretvalue(value)) end
    local function canSummon()
        if state.shared or not state.mount then return false end
        if InCombatLockdown and InCombatLockdown() then return false, ERR_NOT_IN_COMBAT end
        local _, _, _, _, usable, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(state.mount.id)
        if not readable(collected) or collected ~= true then return false end
        if C_MountJournal.GetMountUsabilityByID then
            local allowed, reason = C_MountJournal.GetMountUsabilityByID(state.mount.id, true)
            return readable(usable) and usable == true and readable(allowed) and allowed == true,
                readable(reason) and reason or nil
        end
        return readable(usable) and usable == true
    end
    local function updateButton(hovered)
        local enabled = canSummon()
        summon:SetEnabled(enabled)
        summon:EnableMouse(not state.shared)
        mountIcon:SetAlpha((enabled or state.shared) and 1 or .5)
        glow:SetAlpha(enabled and (hovered and .46 or .20) or 0)
        summonLabel:SetAlpha(enabled and 1 or .5)
        local rimAlpha = state.shared and .65 or enabled and (hovered and 1 or .65) or .35
        for _, texture in ipairs(border) do texture:SetAlpha(rimAlpha) end
    end
    local function hideTooltip()
        if GameTooltip:IsOwned(summon) then GameTooltip:Hide() end
    end
    local function showTooltip()
        if state.shared or not state.mount then return end
        GameTooltip:SetOwner(summon, "ANCHOR_TOP")
        ui.tooltipTitle(ui.coloredMountName(state.mount))
        if MOUNT_SUMMON_TOOLTIP then ui.tooltipLine(MOUNT_SUMMON_TOOLTIP, 1, 1, 1, true) end
        local _, reason = canSummon()
        if reason and reason ~= "" then ui.tooltipLine(reason, 1, .3, .3, true) end
        GameTooltip:Show()
    end
    summon:SetScript("OnEnter", function() updateButton(true); showTooltip() end)
    summon:SetScript("OnLeave", function() updateButton(false); hideTooltip() end)
    summon:SetScript("OnHide", hideTooltip)
    summon:SetScript("OnClick", function(_, button)
        if button ~= "LeftButton" then return end
        -- Match the native journal: summon only from a real button click.
        -- Recheck immediately, since combat/usability can change after hover.
        if canSummon() then C_MountJournal.SummonByID(state.mount.id) end
        updateButton(false)
    end)
    for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "MOUNT_JOURNAL_USABILITY_CHANGED", "COMPANION_UPDATE" }) do
        state:RegisterEvent(event)
    end
    state:SetScript("OnEvent", function()
        if not state:IsShown() then return end
        updateButton(summon:IsMouseOver())
        if GameTooltip:IsOwned(summon) then showTooltip() end
    end)
    state:SetScript("OnShow", function() updateButton(false) end)

    function state:updateQuality()
        mountName:SetText(ui.coloredMountName(self.mount))
        if GameTooltip:IsOwned(summon) then showTooltip() end
    end

    function state:update(mount, shared)
        self.mount, self.shared = mount, shared
        layoutSummon(shared)
        local _, _, icon = C_MountJournal.GetMountInfoByID(mount.id)
        mountIcon:SetTexture(icon or mount.icon or "Interface\\PetBattles\\MountJournalEmptyIcon")
        self:updateQuality()
        layoutLabels()
        updateButton(not shared and summon:IsMouseOver())
    end
    state:Hide()
    return state
end
