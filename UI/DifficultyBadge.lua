local _, atlas = ...
local prefix = "ui-hud-minimap-guildbanner-"
-- Blizzard_FrameXML/InstanceDifficulty.xml uses these native minimap marks.
local parse = atlas.parseSourceDifficulty
local suffix = atlas.sourceDifficultySuffix
local function plain(value)
    return (value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$"))
end

local function modeKey(name)
    local key = atlas.searchKey(name):gsub(" режим$", ""):gsub(" mode$", "")
    return key
end

function atlas.sourceDifficulty(mount, includeSizes)
    local entries, seen = {}, {}
    local function add(name, kind)
        local key = modeKey(name)
        if not seen[key] then
            seen[key] = { name = name, kind = kind }
            entries[#entries + 1] = seen[key]
        end
        return seen[key]
    end
    local function addText(value)
        for _, entry in ipairs(parse(value) or {}) do add(entry.name, entry.kind) end
    end
    for line in (atlas.normalizeSource(mount.journalSourceRaw or mount.journalSource or "") .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
        if atlas.isDifficultySourceLabel(label) then addText(value)
        elseif label == "Место" or label == "Зона" or label == "Zone" or label == "Location" or atlas.isDropSourceLabel(label) then
            local _, mode = suffix(plain(value))
            if mode then addText(mode) end
        end
    end
    local _, mode = suffix(mount.place or "")
    if mode then addText(mode) end
    -- Source text gives the precise restriction. Structured IDs fill cards
    -- whose journal omits it, with Blizzard's localized difficulty names.
    local fromText = #entries > 0
    if (not fromText or includeSizes) and GetDifficultyInfo then
        local ids = {}
        local info = not mount.difficultyLocalOnly and atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id]
        for id, enabled in pairs(mount.difficulties or (info and info.difficulties) or {}) do if enabled then ids[#ids + 1] = id end end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local name, _, heroic, challenge, displayHeroic, mythic, _, _, minimum, maximum = GetDifficultyInfo(id)
            if type(name) == "string" and name ~= "" then
                local kind = (mythic or challenge) and "mythic" or (heroic or displayHeroic) and "heroic" or "normal"
                local entry
                if fromText then entry = seen[modeKey(name)]
                else entry = add(name, kind) end
                if includeSizes and entry and entry.kind == kind
                    and type(minimum) == "number" and type(maximum) == "number" and minimum > 0 and maximum >= minimum then
                    local size = minimum == maximum and tostring(maximum) or (minimum .. "–" .. maximum)
                    entry.sizes = entry.sizes or {}
                    local duplicate
                    for _, value in ipairs(entry.sizes) do if value == size then duplicate = true; break end end
                    if not duplicate then entry.sizes[#entry.sizes + 1] = size end
                end
            end
        end
    end
    return entries
end

function atlas.sourceWithoutDifficulty(mount, source)
    if not mount.difficultyBadgeVisible then return source end
    local lines = {}
    for line in (source .. "\n"):gmatch("(.-)\n") do
        local label, value = line:match("^%s*([^:]+):%s*(.-)%s*$")
        if not (atlas.isDifficultySourceLabel(label) and parse(value)) then
            if label == "Место" or label == "Зона" or label == "Zone" or label == "Location" or atlas.isDropSourceLabel(label) then
                local place = suffix(value)
                if place then line = label .. ": " .. place end
            end
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, "\n")
end

function atlas.placeWithoutDifficulty(mount, value)
    if not mount.difficultyBadgeVisible then return value end
    return suffix(value) or value
end

function atlas.difficultyBadge(parent)
    local ui = atlas.ui
    local frame = ui.place(CreateFrame("Frame", nil, parent), parent, 0, 0, 44, 48)
    frame:SetFrameLevel(parent:GetFrameLevel() + 5)
    frame:EnableMouse(true)
    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAtlas(prefix .. "background-top", true)
    background:SetSize(36, 44)
    background:SetPoint("TOP", frame, "TOP")
    local border = frame:CreateTexture(nil, "BORDER")
    border:SetAtlas(prefix .. "border-top", true)
    border:SetAllPoints(background)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOP", frame, "TOP", 0, -5)
    local count = ui.text(frame, 0, 25, 44, 15, 11, "", ui.gold)
    count:SetJustifyH("CENTER")
    count:SetMaxLines(1)
    local tooltipLines, tooltipText = {}, ""
    local function showTooltip(self)
        if not tooltipLines[1] then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(tooltipLines[1], 1, .82, 0)
        for i = 2, #tooltipLines do ui.tooltipLine(tooltipLines[i], 1, 1, 1) end
        GameTooltip:Show()
    end
    frame:SetScript("OnEnter", showTooltip)
    local function leave(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end
    frame:SetScript("OnLeave", leave)
    frame:SetScript("OnHide", leave)
    function frame:update(mount, anchor, relativePoint, x, y)
        local key = tostring(mount.id) .. ":" .. (mount.boss or "") .. ":" .. (mount.place or "")
        if self.sourceKey ~= key then leave(self) end
        self.sourceKey = key
        local entries = atlas.sourceDifficulty(mount, true)
        local kind = entries[1] and entries[1].kind
        for _, entry in ipairs(entries) do if entry.kind ~= kind then kind = "normal"; break end end
        local name = kind and (prefix .. kind .. "-large")
        local available = name and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(name))
        local shown = available and pcall(icon.SetAtlas, icon, name, true) or false
        local info = type(available) == "table" and available
        local width, height = icon:GetSize()
        if info then width, height = info.width, info.height end
        -- Match Blizzard's useAtlasSize: enlarging the minimap glyph blurs its
        -- edges. Keep its native size and only shrink oversized client assets.
        local scale = math.min(1, 20 / math.max(1, width), 20 / math.max(1, height))
        icon:SetSize(width * scale, height * scale)
        local sizes, used, allKnown = {}, {}, true
        tooltipLines = {}
        for i, entry in ipairs(entries) do
            tooltipLines[i] = entry.name
            if entry.sizes then
                tooltipLines[i] = entry.name .. " (" .. table.concat(entry.sizes, "/") .. ")"
                for _, size in ipairs(entry.sizes) do
                    if not used[size] then sizes[#sizes + 1] = size; used[size] = true end
                end
            else
                allKnown = false
            end
        end
        count:SetText(allKnown and table.concat(sizes, "/") or "")
        if count:GetUnboundedStringWidth() > count:GetWidth() then count:SetText("…") end
        mount.difficultyBadgeVisible = shown == true
        self:SetShown(mount.difficultyBadgeVisible)
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", anchor or parent, relativePoint or "TOPRIGHT", x or -10, (y or -5) + 8)
        local text = table.concat(tooltipLines, "\n")
        if text ~= tooltipText and shown and GameTooltip:IsOwned(self) then showTooltip(self) end
        tooltipText = text
        return mount.difficultyBadgeVisible
    end
    frame:Hide()
    return frame
end
