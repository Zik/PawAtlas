local addonName, atlas = ...
local ui = atlas.ui
local folder = "Interface\\AddOns\\PawAtlas\\Media\\Fonts\\"
local bundled = {
    { id = "ptsans", name = "PT Sans", path = folder .. "PTSans-Regular.ttf" },
    { id = "roboto", name = "Roboto", path = folder .. "Roboto-Regular.ttf" },
    { id = "wow", name = "Стандартный WoW", path = STANDARD_TEXT_FONT, native = true },
    { id = "wowtitle", name = "Заголовки WoW", path = (QuestTitleFont:GetFont()), native = true },
}
local media = LibStub("LibSharedMedia-3.0")
local supported = media.LOCALE_BIT_western + media.LOCALE_BIT_ruRU
media:Register("font", "PT Sans", bundled[1].path, supported)
media:Register("font", "Roboto", bundled[2].path, supported)
local function refreshFonts()
    ui.fonts = {}
    local paths = {}
    for _, font in ipairs(bundled) do
        ui.fonts[#ui.fonts + 1] = font
        paths[font.path:lower()] = true
    end
    for _, name in ipairs(media:List("font")) do
        local path = media:HashTable("font")[name]
        if not paths[path:lower()] then
            ui.fonts[#ui.fonts + 1] = { id = "lsm:" .. name, name = name, path = path, native = path:lower():match("^fonts[\\/]") ~= nil }
            paths[path:lower()] = true
        end
    end
end
refreshFonts()
local registered = {}
-- The catalog uses fixed-height rows; keep font-only scaling deliberately small.
ui.fontScales = { 90, 95, 100, 105, 110 }
local function fontScale(value)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return 100 end
    return math.max(ui.fontScales[1], math.min(ui.fontScales[#ui.fontScales], math.floor(value / 5 + .5) * 5))
end
function ui.selectedFontScale()
    return fontScale(type(MountAtlasDB) == "table" and MountAtlasDB.fontScale)
end
function ui.selectedFont()
    local id = type(MountAtlasDB) == "table" and MountAtlasDB.font
    for _, font in ipairs(ui.fonts) do if font.id == id then return font end end
    return ui.fonts[1]
end
function ui.setFont(object, size, fixed)
    registered[object] = { size = size, fixed = fixed }
    local path = fixed or ui.selectedFont().path
    size = size * ui.selectedFontScale() / 100
    local currentPath, currentSize, flags = object:GetFont()
    if currentPath ~= path or currentSize ~= size or (flags and flags ~= "") then object:SetFont(path, size, "") end
end
-- Some localized Blizzard fonts lack these punctuation glyphs. Keep the
-- original text so choosing a bundled font restores the intended typography.
function ui.bindText(object)
    local setText = object.SetText
    object.SetText = function(self, value)
        self.atlasRawText = value
        if type(value) == "string" and not self.atlasGameText then value = atlas.L(value) end
        if type(value) == "string" and ui.selectedFont().native then
            value = ui.safeText(value)
        end
        setText(self, value)
    end
end
function ui.applyFont(id)
    if id then
        local valid = false
        for _, font in ipairs(ui.fonts) do if font.id == id then valid = true end end
        if not valid then return end
        if type(MountAtlasDB) ~= "table" then MountAtlasDB = {} end
        MountAtlasDB.font = id
    end
    for object, entry in pairs(registered) do
        ui.setFont(object, entry.size, entry.fixed)
        if object.atlasRawText ~= nil then object:SetText(object.atlasRawText) end
    end
    if atlas.refreshDetails then atlas.refreshDetails() end
end
function ui.applyFontScale(value)
    local previous = ui.selectedFontScale()
    if type(MountAtlasDB) ~= "table" then MountAtlasDB = {} end
    MountAtlasDB.fontScale = fontScale(value)
    if MountAtlasDB.fontScale ~= previous then ui.applyFont() end
end
local loader = CreateFrame("Frame")
media.RegisterCallback(ui, "LibSharedMedia_Registered", function(_, kind)
    if kind ~= "font" then return end
    refreshFonts()
    ui.applyFont()
    if atlas.refreshFontSettings then atlas.refreshFontSettings() end
end)
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name == addonName then ui.applyFont(); self:UnregisterEvent("ADDON_LOADED") end
end)
