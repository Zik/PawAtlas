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

local raidOrder = { normal = 2, heroic = 3, mythic = 4 }
local function raidModeOrder(name, kind, lfr)
    local key = modeKey(name or "")
    if lfr or key == "поиск рейда" or key == "raid finder" or key == "looking for raid" then return 1 end
    if key == "путешествие во времени" or key == "timewalking" then return 5 end
    return raidOrder[kind] or 6
end

local function difficultyInfo(id)
    local name, _, heroic, challenge, displayHeroic, mythic, _, lfr, minimum, maximum = GetDifficultyInfo(id)
    local kind = (mythic or challenge) and "mythic" or (heroic or displayHeroic) and "heroic" or "normal"
    return name, kind, lfr or id == 7 or id == 17, minimum, maximum
end

local function sortRaidLockouts(rows)
    local keys = {}
    local function before(a, b)
        local left, right = keys[a], keys[b]
        if left.order ~= right.order then return left.order < right.order end
        if left.size ~= right.size then return left.size < right.size end
        return a < b
    end
    for _, row in ipairs(rows) do
        local ids = row.difficultyIDs or { row.difficultyID }
        for _, id in ipairs(ids) do
            if not keys[id] then
                local name, kind, lfr, _, maximum = difficultyInfo(id)
                keys[id] = { order = raidModeOrder(name, kind, lfr),
                    size = type(maximum) == "number" and maximum > 0 and maximum or math.huge }
            end
        end
        table.sort(ids, before)
    end
    table.sort(rows, function(a, b)
        return before(a.difficultyIDs and a.difficultyIDs[1] or a.difficultyID,
            b.difficultyIDs and b.difficultyIDs[1] or b.difficultyID)
    end)
end

function atlas.sourceDifficulty(mount, includeSizes)
    local entries, seen = {}, {}
    local raid = mount.sourcePlaceKind == "Рейд" or mount.isRaid or mount.kind == "Рейд"
    local keys = {}
    local function add(name, kind)
        local key = modeKey(name)
        if not seen[key] then
            local entry = { name = name, kind = kind }
            seen[key] = entry
            entries[#entries + 1] = entry
            if raid then
                keys[entry] = { order = raidModeOrder(name, kind), size = tonumber(name:match("^%d+")) or math.huge,
                    index = #entries }
            end
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
            local name, kind, lfr, minimum, maximum = difficultyInfo(id)
            if type(name) == "string" and name ~= "" then
                local entry
                if fromText then entry = seen[modeKey(name)]
                else entry = add(name, kind) end
                if raid and entry then
                    if lfr then keys[entry].order = 1 end
                    if type(maximum) == "number" and maximum > 0 then
                        keys[entry].size = math.min(keys[entry].size, maximum)
                    end
                end
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
    if raid then
        table.sort(entries, function(a, b)
            local left, right = keys[a], keys[b]
            if left.order ~= right.order then return left.order < right.order end
            if left.size ~= right.size then return left.size < right.size end
            return left.index < right.index
        end)
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

function atlas.summaryLocationName(mount, value)
    if not value then return end
    local name = suffix(value) or value
    local place, tag = name:match("^(.-)%s+·%s+(.+)$")
    if place then
        local key = atlas.searchKey(tag)
        if (key == "рейд" or key == "raid") and (mount.isRaid or mount.sourcePlaceKind == "Рейд" or mount.kind == "Рейд")
            or (key == "подземелье" or key == "dungeon")
                and (mount.sourcePlaceKind == "Подземелье" or mount.kind == "Подземелье") then
            name = place
        end
    end
    return atlas.displayName(name)
end

function atlas.appendBossDifficultyTooltip(mount, guid)
    local ui, L = atlas.ui, atlas.L
    local rows = atlas.bossDifficultyLockouts and atlas.bossDifficultyLockouts(mount, nil, guid) or {}
    sortRaidLockouts(rows)
    for index = 1, math.min(4, #rows) do
        local row, names = rows[index], {}
        for _, id in ipairs(row.difficultyIDs or { row.difficultyID }) do
            local name = GetDifficultyInfo(id)
            if name then names[#names + 1] = name end
        end
        local state = L(row.stale and "Нужно обновить" or row.state == "boss" and "Босс убит"
            or row.state == "available" and "Можно идти" or "Нет данных")
        local color = row.state == "boss" and ui.mint or row.state == "available" and ui.paper or ui.muted
        GameTooltip:AddDoubleLine(ui.safeText("  " .. table.concat(names, "/")), ui.safeText(state),
            ui.muted[1], ui.muted[2], ui.muted[3], color[1], color[2], color[3])
        if row.shared then ui.tooltipLine(L("Общее сохранение для этих сложностей"), ui.muted[1], ui.muted[2], ui.muted[3], true) end
    end
end

local function instanceSource(view)
    local kind = view.sourceKind or view.kind
    if view.availability or view.unavailable or kind == "Рарка" or kind == "Квест" or kind == "Торговец"
        or kind == "Достижение" or kind == "Профессия" or view.sourcePlaceKind == "Открытый мир" then return end
    if view.sourcePlaceKind == "Рейд" or kind == "Рейд" or view.isRaid == true then return "raid" end
    if view.sourcePlaceKind == "Подземелье" or kind == "Подземелье" then return "dungeon" end
end

function atlas.difficultyBadge(parent)
    local ui, L = atlas.ui, atlas.L
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
    icon:SetPoint("TOP", frame, "TOP", 0, -5)
    local count = ui.text(frame, 0, 25, 44, 15, 11, "", ui.gold)
    count:SetJustifyH("CENTER")
    count:SetMaxLines(1)
    local check = ui.icon(frame, 27, 1, 13, "ObjectiveComplete")
    check:Hide()
    local rows, lines = {}, {}
    local function leave() if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end end
    local function showTooltip()
        if #rows == 0 and #lines == 0 then return end
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
        if #rows > 0 then
            ui.tooltipTitle(L("Режим"))
            for _, row in ipairs(rows) do
                local names = {}
                for _, id in ipairs(row.difficultyIDs or { row.difficultyID }) do
                    local name = GetDifficultyInfo(id)
                    if name then names[#names + 1] = name end
                end
                local used = row.state == "boss" and not row.stale
                local color = used and ui.muted or row.state == "available" and ui.paper or ui.muted
                local mark = used and "|A:ui-questtracker-tracker-check:12:12:0:0|a " or ""
                local state = L(row.stale and "Нужно обновить" or used and "Босс убит"
                    or row.state == "available" and "Можно идти" or "Нет данных")
                GameTooltip:AddDoubleLine(mark .. ui.safeText(table.concat(names, "/")), ui.safeText(state),
                    color[1], color[2], color[3], color[1], color[2], color[3])
                if row.shared then ui.tooltipLine(L("Общее сохранение для этих сложностей"), ui.muted[1], ui.muted[2], ui.muted[3], true) end
            end
        else
            ui.tooltipTitle(lines[1])
            for i = 2, #lines do ui.tooltipLine(lines[i], 1, 1, 1, true) end
        end
        GameTooltip:Show()
    end
    frame:SetScript("OnEnter", showTooltip)
    frame:SetScript("OnLeave", leave)
    frame:SetScript("OnHide", leave)
    function frame:update(mount, anchor, relativePoint, x, y, contextMount, guid)
        local key = table.concat({ tostring(mount.id), mount.boss or "", mount.place or "", mount.sourceKind or mount.kind or "",
            mount.sourcePlaceKind or "", tostring(mount.isRaid), tostring(guid) }, ":")
        local function clear()
            leave()
            rows, lines = {}, {}
            count:SetText("")
            check:Hide()
            icon:SetTexture(nil)
            self:EnableMouse(false)
            if self.mount then self.mount.difficultyBadgeVisible, self.mount.difficultyBadgeWidth = false, 0 end
            mount.difficultyBadgeVisible, mount.difficultyBadgeWidth = false, 0
            self:SetWidth(1)
            self:Hide()
        end
        if self.sourceKey ~= key then clear() end
        self.sourceKey, self.mount = key, mount
        local source = instanceSource(mount)
        if not source then clear(); return false end
        rows = source == "raid" and atlas.bossDifficultyLockouts
            and atlas.bossDifficultyLockouts(contextMount or mount, mount, guid) or {}
        sortRaidLockouts(rows)
        -- An account-wide reagent has one limit even when several raid modes
        -- award it. Show the eligible modes without per-character save rows.
        local accountLoot = source == "raid" and atlas.accountLootSources and atlas.accountLootSources[(contextMount or mount).id]
        if source == "raid" and #rows == 0 and not accountLoot then clear(); return false end
        local kind, sizes, usedSizes, allSizes, allComplete = nil, {}, {}, true, #rows > 0
        lines = {}
        if #rows > 0 then
            for _, row in ipairs(rows) do
                local title, _, heroic, challenge, displayHeroic, mythic, _, _, _, maximum = GetDifficultyInfo(row.difficultyID)
                if not title then clear(); return false end
                local rowKind = (mythic or challenge) and "mythic" or (heroic or displayHeroic) and "heroic" or "normal"
                if not kind then kind = rowKind elseif kind ~= rowKind then kind = "normal" end
                allComplete = allComplete and row.state == "boss" and not row.stale
                if type(maximum) == "number" and maximum > 0 then
                    if not usedSizes[maximum] then sizes[#sizes + 1], usedSizes[maximum] = tostring(maximum), true end
                else allSizes = false end
            end
        else
            local entries = atlas.sourceDifficulty(mount, true)
            kind = entries[1] and entries[1].kind
            if accountLoot then lines[1] = L("Режим") end
            for _, entry in ipairs(entries) do
                if entry.kind ~= kind then kind = "normal" end
                lines[#lines + 1] = entry.name .. (entry.sizes and (" (" .. table.concat(entry.sizes, "/") .. ")") or "")
                if entry.sizes then
                    for _, size in ipairs(entry.sizes) do if not usedSizes[size] then sizes[#sizes + 1], usedSizes[size] = size, true end end
                else allSizes = false end
            end
        end
        if not kind then clear(); return false end
        local name = prefix .. kind .. "-large"
        local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
        if C_Texture and C_Texture.GetAtlasInfo and not info then clear(); return false end
        icon:SetAtlas(name, true)
        local width, height = icon:GetSize()
        if info then width, height = info.width, info.height end
        local scale = math.min(1, 20 / math.max(1, width), 20 / math.max(1, height))
        icon:SetSize(width * scale, height * scale)
        icon:SetDesaturated(allComplete)
        background:SetAlpha(allComplete and .6 or 1)
        count:SetTextColor(unpack(allComplete and ui.muted or ui.gold))
        count:SetText(accountLoot and tostring(#lines - 1) or allSizes and table.concat(sizes, "/") or "")
        if count:GetUnboundedStringWidth() > count:GetWidth() then count:SetText("…") end
        check:SetShown(allComplete)
        mount.difficultyBadgeVisible, mount.difficultyBadgeWidth = true, 44
        self:SetWidth(44)
        self:EnableMouse(true)
        self:Show()
        self:ClearAllPoints()
        self:SetPoint("TOPRIGHT", anchor or parent, relativePoint or "TOPRIGHT", x or -10, (y or -5) + 8)
        if GameTooltip:IsShown() and GameTooltip:IsOwned(self) then showTooltip() end
        return true
    end
    frame:Hide()
    return frame
end
