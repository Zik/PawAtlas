local _, atlas = ...
local ui = atlas.ui

-- Collected mounts use a quiet celebratory footer in place of farming controls.
function atlas.collectedState(card)
    local state = ui.place(CreateFrame("Frame", nil, card), card, 0, 329, 668, 131)
    local controls = "Interface\\AddOns\\PawAtlas\\Media\\Controls\\"
    -- Transparent ribbons and feathered dividers blend into the card itself.
    local ribbon = state:CreateTexture(nil, "BACKGROUND")
    ui.place(ribbon, state, 20, 14, 640, 108)
    ribbon:SetTexture(controls .. "CollectionRibbon.tga")
    for _, y in ipairs({ 13, 122 }) do
        local left = ui.fill(state, 112, y, 278, 1, ui.gold)
        local right = ui.fill(state, 390, y, 268, 1, ui.gold)
        left:SetGradient("HORIZONTAL", CreateColor(.92, .76, .44, 0), CreateColor(.92, .76, .44, .65))
        right:SetGradient("HORIZONTAL", CreateColor(.92, .76, .44, .65), CreateColor(.92, .76, .44, 0))
        local diamond = ui.fill(state, 387, y - 3, 7, 7, ui.gold)
        diamond:SetRotation(math.pi / 4)
        diamond:SetAlpha(.7)
        local inset = ui.fill(state, 389, y - 1, 3, 3, ui.panel)
        inset:SetDrawLayer("BORDER")
        inset:SetRotation(math.pi / 4)
    end

    local mascot = state:CreateTexture(nil, "ARTWORK")
    ui.place(mascot, state, 0, -5, 144, 144)
    mascot:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Illustrations\\GryphonVictorySoft.tga")
    mascot:SetVertexColor(.84, .84, .84)

    local summon = ui.place(CreateFrame("Button", nil, state), state, 568, 24, 72, 72)
    summon:RegisterForClicks("LeftButtonUp")
    if summon.SetMotionScriptsWhileDisabled then summon:SetMotionScriptsWhileDisabled(true) end
    local mountIcon, border = ui.itemIcon(summon, 0, 0, 72)

    local caption = ui.text(state, 178, 32, 360, 36, 24, "В коллекции", ui.gold)
    caption:SetMaxLines(1)
    local mountName = ui.text(state, 180, 73, 358, 37, 15, "", ui.muted)
    mountName.atlasGameText = true
    mountName:SetJustifyV("TOP")
    mountName:SetMaxLines(2)
    local summonLabel = ui.text(state, 550, 99, 108, 18, 12, "Призвать", ui.gold)
    summonLabel:SetJustifyH("CENTER")
    summonLabel:SetMaxLines(1)

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
        if state.shared then
            mountIcon:SetAlpha(1)
            for _, texture in ipairs(border) do texture:SetAlpha(.65) end
            return
        end
        mountIcon:SetAlpha(enabled and 1 or .5)
        if summonLabel then summonLabel:SetAlpha(enabled and 1 or .5) end
        for _, texture in ipairs(border) do
            texture:SetAlpha(enabled and (hovered and 1 or .65) or .35)
        end
    end
    local function hideTooltip()
        if GameTooltip:IsOwned(summon) then GameTooltip:Hide() end
    end
    local function showTooltip()
        if state.shared or not state.mount then return end
        GameTooltip:SetOwner(summon, "ANCHOR_TOP")
        ui.tooltipTitle(state.mount.name)
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
        updateButton(false)
        if GameTooltip:IsOwned(summon) then showTooltip() end
    end)
    state:SetScript("OnShow", function() updateButton(false) end)

    function state:update(mount, shared)
        self.mount, self.shared = mount, shared
        summonLabel:SetShown(not shared)
        local _, _, icon = C_MountJournal.GetMountInfoByID(mount.id)
        mountIcon:SetTexture(icon or mount.icon or "Interface\\PetBattles\\MountJournalEmptyIcon")
        mountName:SetText(mount.name)
        updateButton(false)
    end
    state:Hide()
    return state
end
