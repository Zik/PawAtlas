local _, atlas = ...
local ui = atlas.ui
local L = atlas.L
local button = CreateFrame("Button", "MountAtlasMinimapButton", Minimap)
button:SetSize(34, 34)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp")
button:Hide()
local shadow = ui.place(button:CreateTexture(nil, "BACKGROUND"), button, -15, -14, 64, 64)
shadow:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Brand\\MountAtlasMinimapShadow.tga")
shadow:SetDrawLayer("BACKGROUND")
shadow:SetVertexColor(1, 1, 1, .65)
local surface = ui.brandIcon(button, 1, 1, 32)
local pressed = false
local function refreshIcon(hovered)
    if pressed then surface:SetVertexColor(.62, .48, .28)
    elseif hovered then surface:SetVertexColor(1, 1, 1)
    else surface:SetVertexColor(.88, .88, .88) end
end
button:SetScript("OnMouseDown", function(_, mouseButton)
    if mouseButton == "LeftButton" then pressed = true; refreshIcon(true) end
end)
button:SetScript("OnMouseUp", function(self)
    pressed = false
    refreshIcon(self:IsMouseOver())
end)
local settings
local function updatePosition()
    local radius = Minimap:GetWidth() / 2 + 8
    local angle = settings().angle
    if type(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = 150 end
    angle = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", radius * math.cos(angle), radius * math.sin(angle))
end
settings = function()
    if type(MountAtlasDB) ~= "table" then MountAtlasDB = {} end
    if type(MountAtlasDB.minimap) ~= "table" then MountAtlasDB.minimap = {} end
    return MountAtlasDB.minimap
end
local dragging, dragged = false, false
button:RegisterForDrag("LeftButton")
button:SetScript("OnDragStart", function(self)
    dragging, dragged = true, true
    if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    self:SetScript("OnUpdate", function()
        local x, y = GetCursorPosition()
        local cx, cy = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        x, y = x / scale - cx, y / scale - cy
        local angle
        if math.atan2 then angle = math.atan2(y, x)
        elseif x == 0 then angle = y >= 0 and math.pi / 2 or -math.pi / 2
        else angle = math.atan(y / x); if x < 0 then angle = angle + math.pi end end
        settings().angle = math.deg(angle) % 360
        updatePosition()
    end)
end)
local function stopDrag(self)
    dragging = false
    self:SetScript("OnUpdate", nil)
    C_Timer.After(0, function() dragged = false end)
end
button:SetScript("OnDragStop", stopDrag)
function atlas.showMinimapButton()
    settings().hide = false
    updatePosition()
    button:Show()
end
function atlas.hideMinimapButton()
    settings().hide = true
    button:Hide()
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end
button:SetScript("OnClick", function(_, mouseButton)
    if mouseButton ~= "LeftButton" then return end
    if dragged then return end
    if IsShiftKeyDown() then
        atlas.hideMinimapButton()
        print(L("PawAtlas: значок скрыт. Вернуть: /paw minimap"))
    else atlas.toggleWindow() end
end)
button:SetScript("OnEnter", function(self)
    if dragging then return end
    refreshIcon(true)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    ui.tooltipTitle(L("PawAtlas"))
    ui.tooltipLine(L("ЛКМ — открыть / закрыть"), 1, 1, 1)
    ui.tooltipLine(L("Shift + ЛКМ — скрыть значок"), 1, 1, 1)
    ui.tooltipLine(L("Вернуть: /paw minimap"), unpack(ui.gold))
    GameTooltip:Show()
end)
local function leave()
    pressed = false
    refreshIcon(false)
    if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
end
button:SetScript("OnLeave", leave)
button:SetScript("OnHide", leave)
button:HookScript("OnHide", stopDrag)
button:RegisterEvent("PLAYER_LOGIN")
button:SetScript("OnEvent", function(self)
    updatePosition()
    self:SetShown(not settings().hide)
    self:UnregisterEvent("PLAYER_LOGIN")
end)
Minimap:HookScript("OnSizeChanged", updatePosition)
leave()
