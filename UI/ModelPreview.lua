local _, atlas = ...
local ui = atlas.ui

function atlas.bindModelPreview(parent)
    -- Match MountJournal.MountDisplay.ModelScene's 407 x 514 viewport. Its
    -- per-mount camera and normalized actor scale are authored for this aspect.
    local modelWidth, modelHeight = 407, 514
    local popupWidth, popupHeight = modelWidth + 16, modelHeight + 58
    local popup = ui.place(CreateFrame("Frame", nil, parent), parent, 322, 78, popupWidth, popupHeight)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetClampedToScreen(true)
    ui.surface(popup, 0, 0, popupWidth, popupHeight)
    for _, anchor in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local left, top = anchor:find("LEFT"), anchor:find("TOP")
        local corner = popup:CreateTexture(nil, "BORDER")
        corner:SetPoint(anchor, popup, anchor, left and 2 or -2, top and -2 or 2)
        corner:SetSize(24, 24)
        corner:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\OrnateCorner.tga")
        corner:SetTexCoord(left and 0 or 1, left and 1 or 0, top and 0 or 1, top and 1 or 0)
        corner:SetAlpha(.42)
    end
    local rule = ui.fill(popup, 20, 47, popupWidth - 40, 1, ui.rule)
    rule:SetAlpha(.55)
    local heading = ui.text(popup, 20, 2, popupWidth - 40, 44, 18, "")
    heading:SetMaxLines(2)
    local note = ui.text(popup, 16, 289, popupWidth - 32, 70, 15, "3D-модель доступна в клиенте WoW.", ui.muted)
    local image = popup:CreateTexture(nil, "ARTWORK")
    ui.place(image, popup, 16, 55, popupWidth - 32, 230)
    popup:Hide()
    local hovered, model
    local activeMount, activeDisplay, activeScene, activeActor
    local request = 0
    local function clearScene()
        request = request + 1
        activeMount, activeDisplay, activeScene, activeActor = nil, nil, nil, nil
        if model then
            model:Hide()
            -- Releasing pooled actors clears their callbacks and cancels the
            -- old model load; the next mount also gets a fresh native camera.
            model:ClearScene()
        end
    end
    popup:HookScript("OnHide", clearScene)
    local function update(forceScene)
        local mount = hovered and hovered()
        if not mount or not IsShiftKeyDown() or not parent:IsVisible() then popup:Hide(); return end
        local display, _, _, isSelfMount, _, sceneID = C_MountJournal.GetMountInfoExtraByID(mount.id)
        -- Some mounts expose only their display variants, as in MountJournal.
        if not display and C_MountJournal.GetMountAllCreatureDisplayInfoByID then
            local displays = C_MountJournal.GetMountAllCreatureDisplayInfoByID(mount.id)
            display = displays and displays[1] and displays[1].creatureDisplayID
        end
        heading:SetText(atlas.displayName(mount.name))
        -- Keep the journal's camera, origin and normalized actor scale intact.
        -- Re-centering bounding boxes or overriding its zoom breaks the native
        -- framing of mounts with model-specific pivots and camera offsets.
        local native = display and sceneID and C_ModelInfo and C_ModelInfo.GetModelSceneInfoByID
            and WrappedAndUnwrappedModelSceneMixin and ModelSceneMixin
        if native then
            if not model then
                model = ui.place(CreateFrame("ModelScene", nil, popup, "NonInteractableWrappedAndUnwrappedModelScene"), popup, 8, 48, modelWidth, modelHeight)
                model:EnableMouse(false)
                model:EnableMouseWheel(false)
            end
            if forceScene or activeMount ~= mount.id or activeDisplay ~= display or activeScene ~= sceneID then
                clearScene()
                local currentRequest = request
                model:TransitionToModelSceneID(sceneID, CAMERA_TRANSITION_TYPE_IMMEDIATE, CAMERA_MODIFICATION_TYPE_DISCARD, true)
                local actor = model:GetModelSceneID() == sceneID and model:GetActorByTag("unwrapped")
                if actor then
                    model:PrepareForFanfare(false)
                    -- A hover preview shows the mount itself, without a gift
                    -- wrapper or a rider left over from another scene.
                    for other in model:EnumerateActiveActors() do other:Hide() end
                    activeMount, activeDisplay, activeScene, activeActor = mount.id, display, sceneID, actor
                    local function current(self)
                        local target = hovered and hovered()
                        return request == currentRequest and self == activeActor and target and target.id == activeMount
                            and IsShiftKeyDown() and parent:IsVisible()
                    end
                    local function loaded(self)
                        if not current(self) then return end
                        self:UpdateScale()
                        self:Show()
                    end
                    actor:SetOnModelLoadedCallback(loaded)
                    actor:SetModelByCreatureDisplayID(display, true)
                    actor:SetAnimationBlendOperation(isSelfMount and Enum.ModelBlendOperation.None or Enum.ModelBlendOperation.Anim)
                    actor:SetAnimation(isSelfMount and 618 or 0)
                    -- Cached models may already be loaded without another event.
                    if actor:IsLoaded() then loaded(actor) end
                end
            end
            native = activeMount == mount.id and activeScene == sceneID
        elseif activeMount then
            clearScene()
        end
        if model then model:SetShown(native == true) end
        note:SetShown(not native)
        image:SetShown(not native and mount.expansion ~= nil)
        if not native and mount.expansion then
            local path = mount.art and ("Plates\\" .. mount.art) or (mount.expansion == "Classic" and "Headers\\Azeroth" or "Expansions\\" .. mount.expansion)
            image:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\" .. path .. ".tga")
        end
        popup:Show()
    end
    local listener = CreateFrame("Frame", nil, parent)
    listener:RegisterEvent("MODIFIER_STATE_CHANGED")
    listener:RegisterEvent("UI_MODEL_SCENE_INFO_UPDATED")
    listener:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    listener:RegisterUnitEvent("UNIT_FORM_CHANGED", "player")
    listener:SetScript("OnEvent", function(_, event) update(event ~= "MODIFIER_STATE_CHANGED") end)
    parent:HookScript("OnHide", function() hovered = nil; popup:Hide() end)
    return function(widget, getMount)
        widget.refreshModelPreview = function()
            if hovered == getMount then update() end
        end
        widget:SetScript("OnEnter", function() hovered = getMount; update() end)
        local function leave()
            if hovered == getMount then hovered = nil; popup:Hide() end
        end
        widget:SetScript("OnLeave", leave)
        widget:HookScript("OnHide", leave)
    end
end
