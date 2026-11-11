local _, atlas = ...
local ui = {}
atlas.ui = ui
ui.ink = { .024, .059, .090 }
ui.panel = { .047, .094, .137 }
ui.active = { .11, .18, .21 }
ui.rule = { .24, .31, .32 }
ui.gold = { .92, .76, .44 }
ui.paper = { .918, .941, .957 }
ui.muted = { .635, .694, .737 }
ui.mint = { .63, .82, .73 }

-- Native tooltip fonts have narrower glyph coverage than bundled UI fonts.
-- Apply this only to our text, leaving Blizzard's item tooltip and fonts intact.
local approximateSymbol = "|TInterface\\AddOns\\PawAtlas\\Media\\Controls\\Approximate.tga:0:0|t"
function ui.safeText(value)
    if type(value) ~= "string" then return value end
    return (value:gsub("·", "/"):gsub("≈", approximateSymbol):gsub("›", ">"):gsub("‹", "<")
        :gsub("×", "x"):gsub("—", "-"):gsub("…", "..."))
end

function ui.tooltipTitle(text, ...)
    GameTooltip:SetText(ui.safeText(text), ...)
end

function ui.tooltipLine(text, ...)
    GameTooltip:AddLine(ui.safeText(text), ...)
end

local sourceTooltipLabels = {}
for _, label in ipairs({
    "Источник", "Добыча", "Босс", "Торговец", "Торговцы", "Место", "Зона", "Зоны", "Область",
    "Задание", "Квест", "Локальное задание", "Задание гарнизона", "Фракция", "Репутация",
    "Ковенант", "Известность", "Цена", "Профессия", "Навык", "Требуется", "Режим",
    "Событие", "Особое событие", "Праздник", "Drop", "Zone", "Location", "Difficulty",
}) do
    sourceTooltipLabels[atlas.L(label)] = true
end
for _, format in ipairs({ "Был доступен: %s", "Условия: %s" }) do
    local label = atlas.L(format, ""):match("^([^:]+):")
    if label then sourceTooltipLabels[label] = true end
end

function ui.tooltipSourceText(text, color)
    if not text or text == "" then return end
    local r, g, b = unpack(color or ui.paper)
    for line in (text .. "\n"):gmatch("(.-)\n") do
        local label = line:match("^([^:|]+):%s*%S")
        if label and sourceTooltipLabels[label] then
            local last = #label + 1
            line = "|cff9fddeb" .. line:sub(1, last) .. "|r" .. line:sub(last + 1)
        end
        ui.tooltipLine(line ~= "" and line or " ", r, g, b, true)
    end
end

function ui.tooltipSourceAlternatives(mount)
    local detail = atlas.legacySourceDetails and atlas.legacySourceDetails(mount)
    local offer = atlas.tradingPostOffer and atlas.tradingPostOffer(mount)
    if not detail and not offer then return end
    detail = detail or {}
    local english = atlas.getLocale() == "enUS"
    local alternatives = (english and detail.englishAlternatives) or detail.alternatives
    local history = (english and detail.englishHistory) or detail.history
    if offer or detail.tradingPost or (alternatives and alternatives ~= "") then
        ui.tooltipLine(" ")
        ui.tooltipLine(atlas.L("Другие способы получения"), unpack(ui.gold))
        if alternatives and alternatives ~= "" then ui.tooltipSourceText(alternatives, ui.paper) end
        if offer then
            local label = offer.unknown and "Открой Торговую лавку, чтобы проверить ассортимент"
                or offer.frozen and "Заморожено у тебя"
                or offer.bonus and "Награда журнала путешественника" or "В продаже сейчас"
            ui.tooltipSourceText(atlas.L("Торговая лавка") .. " — " .. atlas.L(label), offer.unknown and ui.muted or ui.paper)
            if offer.price then
                local currency = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(2032)
                local suffix = currency and currency.name or ""
                ui.tooltipLine(atlas.L("Цена") .. ": " .. offer.price .. " " .. suffix, unpack(ui.gold))
            end
        elseif detail.tradingPost then
            ui.tooltipSourceText(atlas.L("Торговая лавка — появлялся в ассортименте. Ассортимент меняется"), ui.paper)
        end
    end
    if history and history ~= "" then
        ui.tooltipLine(" ")
        ui.tooltipLine(atlas.L("Прошлые предложения"), unpack(ui.gold))
        ui.tooltipSourceText(history, ui.muted)
    end
end

ui.qualityColors = {
    [0] = { .62, .62, .62 }, [1] = { 1, 1, 1 }, [2] = { .12, 1, 0 },
    [3] = { 0, .44, .87 }, [4] = { .64, .21, .93 }, [5] = { 1, .50, 0 },
    [6] = { .90, .80, .50 }, [7] = { 0, .80, 1 },
}

-- Displayed probability; low-to-high contrast against the dark card.
ui.chances = {
    { limit = 1, color = { .73, .76, .79 }, label = "До 1% включительно" },
    { limit = 5, color = { .48, .87, .63 }, label = "Свыше 1% и до 5%" },
    { limit = 20, color = { .51, .76, .99 }, label = "Свыше 5% и до 20%" },
    { limit = 60, color = { .78, .66, .99 }, label = "Свыше 20% и до 60%" },
    { limit = 100, color = { 1, .79, .36 }, label = "Свыше 60% и до 100%" },
}

ui.chanceFlavors = {
    "Приключение начинается", "Первый круг почёта", "Тропа уже знакома", "Босс уже узнаёт тебя",
    "Ещё один заход в копилку", "Полпути к легенде о терпении", "Здесь уже можно прописаться",
    "Местные считают тебя своим", "Терпение эпического качества", "Легендарное упорство",
}

function ui.probabilityText(fraction, guaranteed)
    if fraction == nil then return atlas.L("Неизвестен") end
    local percent = fraction * 100
    if percent == 0 then return "0 %" end
    if guaranteed then return "100 %" end
    -- Rounding and floating-point saturation must never imply a guaranteed drop.
    local russian = atlas.getLocale() == "ruRU"
    if percent >= 99.995 then return russian and "> 99,99 %" or "> 99.99 %" end
    if percent < .005 then return russian and "< 0,01 %" or "< 0.01 %" end
    local formatted = string.format("%.2f", percent):gsub("0+$", ""):gsub("%.$", "")
    if russian then formatted = formatted:gsub("%.", ",") end
    return "≈ " .. formatted .. " %"
end

function ui.place(object, parent, x, y, w, h)
    object:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    object:SetSize(w, h)
    return object
end

function ui.fill(parent, x, y, w, h, color)
    local tex = parent:CreateTexture(nil, "BACKGROUND")
    ui.place(tex, parent, x, y, w, h)
    tex:SetColorTexture(unpack(color))
    return tex
end

function ui.windowBorder(frame, w, h, trimScale)
    local bronze = { .48, .40, .28 }
    local bevel = { .22, .24, .24 }
    local scale = trimScale or 1
    local function pixels(value) return math.floor(value * scale + .5) end
    local function edge(start, endPoint, x1, y1, x2, y2)
        local texture = frame:CreateTexture(nil, "BACKGROUND")
        texture:SetPoint("TOPLEFT", frame, start, x1, y1)
        texture:SetPoint("BOTTOMRIGHT", frame, endPoint, x2, y2)
        texture:SetColorTexture(unpack(bronze))
    end
    edge("TOPLEFT", "TOPRIGHT", 0, 0, 0, -1)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", 0, 1, 0, 0)
    edge("TOPLEFT", "BOTTOMLEFT", 0, -1, 1, 1)
    edge("TOPRIGHT", "BOTTOMRIGHT", -1, -1, 0, 1)
    for _, anchor in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
        local dx = anchor:find("LEFT") and 1 or -1
        local dy = anchor:find("TOP") and -1 or 1
        local function trim(x, y, width, height, color)
            local tex = frame:CreateTexture(nil, "BORDER")
            tex:SetPoint(anchor, frame, anchor, pixels(x) * dx, pixels(y) * dy)
            tex:SetSize(math.max(1, pixels(width)), math.max(1, pixels(height)))
            tex:SetColorTexture(unpack(color))
        end
        trim(0, 0, 32, 2, ui.gold)
        trim(0, 0, 2, 19, ui.gold)
        trim(4, 4, 17, 1, bronze)
        trim(4, 4, 1, 9, bronze)
        trim(7, 7, 3, 3, bevel)
        local ornament = frame:CreateTexture(nil, "BORDER")
        ornament:SetPoint(anchor, frame, anchor, 0, 0)
        ornament:SetSize(pixels(48), pixels(48))
        ornament:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\OrnateCorner.tga")
        ornament:SetTexCoord(dx == 1 and 0 or 1, dx == 1 and 1 or 0, dy == -1 and 0 or 1, dy == -1 and 1 or 0)
    end
end

function ui.text(parent, x, y, w, h, size, value, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ui.place(fs, parent, x, y, w, h)
    ui.setFont(fs, size)
    ui.bindText(fs)
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("MIDDLE")
    fs:SetTextColor(unpack(color or ui.paper))
    fs:SetText(value)
    return fs
end

function ui.button(parent, x, y, w, h, action)
    local btn = ui.place(CreateFrame("Button", nil, parent), parent, x, y, w, h)
    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, .05)
    btn:SetHighlightTexture(hover)
    btn:SetScript("OnClick", action)
    return btn
end

local controls = "Interface\\AddOns\\PawAtlas\\Media\\Controls\\"
local nativeIcons = {
    Boss = { texture = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull" },
    Rare = { atlas = "VignetteKill", texture = "Interface\\WorldMap\\Skull_64Grey" },
    Vendor = { texture = "Interface\\GossipFrame\\VendorGossipIcon" },
    Raid = { atlas = "Raid", texture = "Interface\\Minimap\\Raid" },
    Dungeon = { atlas = "Dungeon", texture = "Interface\\Minimap\\Dungeon" },
    Place = { atlas = "Waypoint-MapPin-Untracked", texture = "Interface\\Minimap\\Minimap-Waypoint-MapPin-Untracked" },
    Chance = { texture = "Interface\\Buttons\\UI-GroupLoot-Dice-Up" },
    Achievement = { texture = "Interface\\AchievementFrame\\UI-Achievement-Shields-NoPoints", crop = { 0, 62/128, 0, 58/128 } },
    Quest = { texture = "Interface\\GossipFrame\\AvailableQuestIcon" },
    ObjectiveComplete = { atlas = "ui-questtracker-tracker-check", texture = "Interface\\RaidFrame\\ReadyCheck-Ready" },
    Lock = { texture = "Interface\\Buttons\\LockButton-Locked-Up", crop = { 6/32, 25/32, 6/32, 25/32 } },
    Unlock = { texture = "Interface\\Buttons\\LockButton-Unlocked-Up", crop = { 6/32, 25/32, 6/32, 25/32 } },
}

-- MapLegendFrame, QuestUtils, AchievementUI and the native loot-roll controls
-- provide these client assets. Built-in paths also cover an unavailable atlas.
function ui.setIcon(texture, name)
    local native = nativeIcons[name]
    texture:SetTexCoord(0, 1, 0, 1)
    if native then
        local available = native.atlas and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(native.atlas))
        if available then texture:SetAtlas(native.atlas, false)
        else
            texture:SetTexture(native.texture)
            if native.crop then texture:SetTexCoord(unpack(native.crop)) end
        end
    else texture:SetTexture(controls .. name .. ".tga") end
end

-- Nine slices keep the bevel and corners crisp at any panel size.
function ui.surface(parent, x, y, w, h, gold, asset)
    local textures = {}
    local xs, ys = {0, 10, w - 10, w}, {0, 10, h - 10, h}
    local uv = {0, 12/128, 116/128, 1}
    for row = 1, 3 do
        for col = 1, 3 do
            local tex = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
            ui.place(tex, parent, x + xs[col], y + ys[row], xs[col+1]-xs[col], ys[row+1]-ys[row])
            tex:SetTexture(controls .. (asset or (gold and "OrnateGold" or "OrnatePanel")) .. ".tga")
            tex:SetTexCoord(uv[col], uv[col+1], uv[row], uv[row+1])
            textures[#textures+1] = tex
        end
    end
    return textures
end

local fieldTint = { .61, .70, .87 }

function ui.fieldSurface(parent, x, y, w, h)
    local textures = ui.surface(parent, x, y, w, h, true)
    for _, texture in ipairs(textures) do texture:SetVertexColor(unpack(fieldTint)) end
    return textures
end

-- Dropdowns sit above existing content and need an opaque, distinct surface.
function ui.dropdownSurface(parent)
    for spread = 8, 2, -2 do
        local shadow = parent:CreateTexture(nil, "BACKGROUND", nil, -2)
        shadow:SetPoint("TOPLEFT", parent, "TOPLEFT", -spread, spread - 2)
        shadow:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", spread, -spread - 2)
        shadow:SetColorTexture(0, 0, 0, .025)
    end
    return ui.fieldSurface(parent, 0, 0, parent:GetWidth(), parent:GetHeight())
end

-- The toast scales as a whole; a continuous texture avoids filtered slice seams.
function ui.rewardFrame(parent, x, y, w, h)
    local texture = parent:CreateTexture(nil, "BACKGROUND", nil, 0)
    ui.place(texture, parent, x, y, w, h)
    texture:SetTexture(controls .. "CollectionRewardFrame.tga")
    texture:SetVertexColor(.76, .76, .76)
    -- Reuse the approved three-toed emblem instead of redrawing it in the frame.
    local emblemSize = math.floor(h * .226 + .5)
    local emblem = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    ui.place(emblem, parent, x + (w - emblemSize) / 2, y + 8, emblemSize, emblemSize)
    emblem:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Brand\\RewardPaw.tga")
    emblem:SetVertexColor(.85, .85, .85)
end

function ui.icon(parent, x, y, size, name)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    ui.place(texture, parent, x, y, size, size)
    ui.setIcon(texture, name)
    return texture
end

-- Square item artwork gets a thin slot rim, not the wide bevel of a panel.
function ui.itemIcon(parent, x, y, size)
    local slot = ui.place(CreateFrame("Frame", nil, parent), parent, x, y, size, size)
    ui.fill(slot, 0, 0, size, size, { .025, .035, .04, 1 })
    local rim = {}
    for _, edge in ipairs({ { 0, 0, size, 1 }, { 0, size - 1, size, 1 },
        { 0, 1, 1, size - 2 }, { size - 1, 1, 1, size - 2 } }) do
        local line = ui.fill(slot, edge[1], edge[2], edge[3], edge[4], ui.gold)
        line:SetDrawLayer("BORDER")
        rim[#rim + 1] = line
    end
    local icon = slot:CreateTexture(nil, "ARTWORK")
    ui.place(icon, slot, 3, 3, size - 6, size - 6)
    icon:SetTexCoord(.08, .92, .08, .92)
    return icon, rim, slot
end

-- Draw the chevron independently of the selected font's glyph coverage.
function ui.dropdownArrow(parent, x, y, size)
    local arrow = ui.place(CreateFrame("Frame", nil, parent), parent, x, y, size, size)
    local thickness = size <= 12 and 1 or 2
    local left = ui.fill(arrow, size * .15, size * .45, size * .4, thickness, ui.gold)
    local right = ui.fill(arrow, size * .4, size * .45, size * .4, thickness, ui.gold)
    left:SetDrawLayer("ARTWORK")
    right:SetDrawLayer("ARTWORK")
    left:SetRotation(-math.pi / 4)
    right:SetRotation(math.pi / 4)
    function arrow:SetColor(color)
        left:SetColorTexture(unpack(color)); right:SetColorTexture(unpack(color))
    end
    return arrow
end

function ui.brandIcon(parent, x, y, size)
    local texture = parent:CreateTexture(nil, "ARTWORK")
    ui.place(texture, parent, x, y, size, size)
    texture:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Brand\\"
        .. (size <= 34 and "MountAtlasMinimap.tga" or "MountAtlasHeader.tga"))
    return texture
end

function ui.action(parent, x, y, w, h, label, icon, callback, field)
    local button = ui.place(CreateFrame("Button", nil, parent), parent, x, y, w, h)
    local surface = ui.surface(button, 0, 0, w, h)
    local glow = ui.surface(button, -2, -2, w + 4, h + 4, true, "OrnateGlow")
    for _, texture in ipairs(glow) do texture:SetDrawLayer("BORDER") end
    button:SetScript("OnClick", callback)
    local active, hovered, pressed = false, false, false
    local fieldStyle
    local function updateSurface()
        local highlight = hovered and button:IsEnabled()
        local name = ((field or active) and "OrnateGold" or "OrnatePanel") .. (highlight and "Hover" or "")
        local tint = pressed and .85 or (field and active and 1.14 or 1)
        local color = fieldStyle or (field and fieldTint)
        for _, texture in ipairs(surface) do
            texture:SetTexture(controls .. name .. ".tga")
            if color then
                texture:SetVertexColor(color[1] * tint, color[2] * tint, color[3] * tint)
            else texture:SetVertexColor(tint, tint, tint) end
        end
        local light = button:IsEnabled() and not pressed and ((active or field) and (highlight and .85 or .45) or (highlight and .35 or 0)) or 0
        if fieldStyle and light > 0 then light = highlight and .35 or .15 end
        for _, texture in ipairs(glow) do texture:SetAlpha(light) end
        if button.glyph then button.glyph:SetVertexColor(unpack((active or highlight) and ui.gold or ui.paper)) end
        if button.caption then button.caption:SetTextColor(unpack((active or highlight) and ui.paper or ui.muted)) end
    end
    local function resetHover() hovered, pressed = false, false; updateSurface() end
    button:SetScript("OnEnter", function() hovered = true; updateSurface() end)
    button:SetScript("OnLeave", resetHover)
    button:SetScript("OnHide", resetHover)
    button:SetScript("OnDisable", resetHover)
    button:SetScript("OnEnable", resetHover)
    button:SetScript("OnMouseDown", function() pressed = button:IsEnabled(); updateSurface() end)
    button:SetScript("OnMouseUp", function() pressed = false; hovered = button:IsMouseOver(); updateSurface() end)
    if icon then
        local glyph = button:CreateTexture(nil, "OVERLAY")
        button.glyph = glyph
        ui.place(glyph, button, label and 10 or (w - 19) / 2, (h - 19) / 2, 19, 19)
        ui.setIcon(glyph, icon)
    end
    if label then
        local left = icon and 30 or 3
        button.caption = ui.text(button, left, 0, w - left - 3, h, 14, label)
        button.caption:SetJustifyH("CENTER")
    end
    function button:setActive(value)
        active = value
        updateSurface()
    end
    function button:setFieldStyle(color)
        fieldStyle = color
        for _, texture in ipairs(surface) do texture:SetDesaturated(color ~= nil) end
        for _, texture in ipairs(glow) do
            texture:SetDesaturated(color ~= nil)
            texture:SetVertexColor(unpack(color or { 1, 1, 1 }))
        end
        updateSurface()
    end
    button:setActive(false)
    return button
end

function ui.check(parent, x, y)
    local badge = parent:CreateTexture(nil, "OVERLAY")
    ui.place(badge, parent, x, y, 21, 21)
    ui.setIcon(badge, "ObjectiveComplete")
    badge:Hide()
    return badge
end

function ui.resetButton(parent, x, y, callback)
    local button = ui.place(CreateFrame("Button", nil, parent), parent, x, y, 32, 32)
    local icon = ui.icon(button, 4, 4, 24, "Reset")
    icon:SetAlpha(.8)
    button:SetScript("OnClick", callback)
    button:SetScript("OnEnter", function(self)
        icon:SetAlpha(1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(atlas.L("По умолчанию"))
        GameTooltip:Show()
    end)
    local function clearHover(self)
        icon:SetAlpha(.8)
        icon:SetVertexColor(1, 1, 1)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    button:SetScript("OnLeave", clearHover)
    button:SetScript("OnHide", clearHover)
    button:SetScript("OnDisable", clearHover)
    button:SetScript("OnMouseDown", function() icon:SetVertexColor(.7, .7, .7) end)
    button:SetScript("OnMouseUp", function() icon:SetVertexColor(1, 1, 1) end)
    return button
end
