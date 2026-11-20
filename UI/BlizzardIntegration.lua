local _, atlas = ...
local L = atlas.L
local events = CreateFrame("Frame")
local entry, category
local function settings()
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    if type(MountAtlasAccountDB.settings) ~= "table" then MountAtlasAccountDB.settings = {} end
    return MountAtlasAccountDB.settings
end
function atlas.openFullSettings()
    if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
    if not MountAtlasSettings or not MountAtlasSettings:IsVisible() then atlas.toggleSettings() end
end
function atlas.addonCompartmentEnabled()
    return settings().addonCompartment ~= false
end
local function updateCompartment()
    local compartment = AddonCompartmentFrame
    if not compartment or type(compartment.RegisterAddon) ~= "function"
        or type(compartment.UpdateDisplay) ~= "function" or type(compartment.registeredAddons) ~= "table" then return false end
    if not entry then
        entry = { text = L("PawAtlas"), icon = "Interface\\AddOns\\PawAtlas\\Media\\Brand\\MountAtlasMinimap.tga",
            func = function() atlas.toggleWindow() end }
    end
    local found
    -- Retail exposes registration but no unregister method. Remove only our
    -- exact registered object; preserve every other provider's entry and order.
    for i = #compartment.registeredAddons, 1, -1 do
        if compartment.registeredAddons[i] == entry then
            if not atlas.addonCompartmentEnabled() or found then table.remove(compartment.registeredAddons, i)
            else found = true end
        end
    end
    if atlas.addonCompartmentEnabled() and not found then compartment:RegisterAddon(entry)
    else compartment:UpdateDisplay() end
    return true
end
function atlas.setAddonCompartmentEnabled(enabled)
    settings().addonCompartment = enabled == true
    updateCompartment()
    if atlas.refreshIntegrationSettings then atlas.refreshIntegrationSettings() end
end
local function makeBlizzardSettings()
    if category or not Settings or not Settings.RegisterCanvasLayoutCategory or not Settings.RegisterAddOnCategory then return end
    local panel = CreateFrame("Frame")
    panel:Hide()
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(L("PawAtlas"))
    local checks = {}
    local function checkbox(y, label, get, set)
        local button = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        button:SetPoint("TOPLEFT", 16, -y)
        button:SetSize(32, 32)
        local text = button:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        text:SetPoint("LEFT", button, "RIGHT", 8, 0)
        text:SetText(L(label))
        button:SetHitRectInsets(0, -300, 0, 0)
        button:SetScript("OnClick", function(self) set(self:GetChecked() == true) end)
        checks[#checks + 1] = { button = button, get = get }
    end
    checkbox(54, "Значок миникарты", atlas.minimapButtonShown, atlas.setMinimapButtonShown)
    checkbox(94, "Подсказки в игре", atlas.gameTooltipsEnabled, function(value) settings().gameTooltips = value end)
    checkbox(134, "Трекер", function() return atlas.expeditionSettings() end, atlas.setExpeditionEnabled)
    checkbox(174, "Напоминания о событиях", function() return atlas.eventRemindersEnabled and atlas.eventRemindersEnabled() or false end,
        function(value) if atlas.setEventRemindersEnabled then atlas.setEventRemindersEnabled(value) end end)
    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetPoint("TOPLEFT", 16, -228)
    open:SetSize(290, 28)
    open:SetText(L("Открыть настройки PawAtlas"))
    open:SetScript("OnClick", atlas.openFullSettings)
    local function refresh()
        for _, check in ipairs(checks) do check.button:SetChecked(check.get() == true) end
    end
    panel.OnRefresh = refresh
    panel:SetScript("OnShow", refresh)
    category = Settings.RegisterCanvasLayoutCategory(panel, L("PawAtlas"))
    Settings.RegisterAddOnCategory(category)
end
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" or event == "ADDON_LOADED" then makeBlizzardSettings() end
    updateCompartment()
end)
