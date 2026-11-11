local _, atlas = ...
local ui, L = atlas.ui, atlas.L
local labels = { attempt = "Попытка использована", boss = "Босс убит", available = "Можно идти",
    unknown = "Нет данных", stale = "Нужно обновить" }
local pointFactions = { ["Альянс"] = "Alliance", ["Орда"] = "Horde" }

local function complete(state) return state == "attempt" or state == "boss" end
local located = atlas.hasSourceCoordinates

local function indexProgress(mount, guid)
    local progress, byKey = atlas.planOpportunityProgress(mount, guid), {}
    for _, entry in ipairs(progress and progress.entries or {}) do byKey[entry.key] = entry.state end
    if not progress and atlas.lootFrequency(mount) == "repeatable" then byKey.fallback = "available" end
    return byKey, progress
end

-- A row is a named source, not a coordinate or an extra loot opportunity.
-- Shared locks keep one key even when several NPCs can supply the same reward.
local function sources(mount, progress)
    local rows, bySource, byNPC, covered = {}, {}, {}, {}
    local groups = progress and progress.entries or {}
    for _, entry in ipairs(groups) do
        for _, npc in ipairs(entry.npcs) do byNPC[npc] = entry.key end
    end
    for _, point in ipairs(atlas.mountLocations(mount)) do
        local key = byNPC[point.npc] or (not point.npc and #groups == 1 and groups[1].key or nil)
        -- Verified aliases can share a lock and a source name. Keep faction
        -- alternatives with different names separate, not duplicate aliases.
        local identity = point.npc and key and point.boss
            and key .. ":" .. tostring(point.map) .. ":" .. atlas.searchKey(point.boss)
            or point.npc and "npc:" .. point.npc .. ":" .. tostring(point.map)
            or tostring(point.map) .. ":" .. atlas.searchKey(point.boss or "")
        local row = bySource[identity]
        if not row then
            row = { identity = identity, key = key, point = point, points = {},
                name = point.boss or mount.boss, place = point.place or mount.place }
            rows[#rows + 1], bySource[identity] = row, row
        elseif not located(row.point) and located(point) then row.point = point end
        row.points[#row.points + 1] = point
        if key then covered[key] = true end
    end
    for _, entry in ipairs(groups) do
        if not covered[entry.key] then
            rows[#rows + 1] = { identity = entry.key, key = entry.key,
                name = #groups == 1 and mount.boss or L("Нет данных"), place = mount.place }
        end
    end
    local counts = {}
    for _, row in ipairs(rows) do
        if row.key then counts[row.key] = (counts[row.key] or 0) + 1 end
    end
    for _, row in ipairs(rows) do row.shared = row.key and counts[row.key] > 1 or false end
    return rows
end

function atlas.makePlannerSources(parent)
    local overlay = CreateFrame("Frame", "MountAtlasPlannerSources", parent)
    overlay:SetAllPoints(parent)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetFrameLevel(parent:GetFrameLevel() + 30)
    overlay:EnableMouse(true)
    -- Cover the window's whole content area between header and footer rules,
    -- rather than drawing a dark rectangle at the planner's inset bounds.
    local dismiss = ui.button(overlay, -34, -24, 1038, 497, function() overlay:Hide() end)
    dismiss:ClearHighlightTexture()
    ui.fill(dismiss, 0, 0, 1038, 497, { 0, .02, .025, .55 })
    local panel = ui.place(CreateFrame("Frame", nil, overlay), overlay, 49, 0, 872, 450)
    panel:EnableMouse(true)
    panel:SetFrameLevel(dismiss:GetFrameLevel() + 1)
    ui.surface(panel, 0, 0, 872, 450)
    local title = ui.text(panel, 20, 12, 778, 28, 21, "", ui.gold)
    title.atlasGameText = true
    title:SetMaxLines(1)
    local summary = ui.text(panel, 20, 43, 820, 30, 12, "", ui.muted)
    ui.action(panel, 826, 12, 30, 30, nil, "Close", function() overlay:Hide() end)
    ui.fill(panel, 20, 74, 832, 1, ui.rule)
    ui.text(panel, 25, 82, 530, 20, 12, "Рарки", ui.muted)
    local rosterTitle = ui.text(panel, 594, 82, 254, 20, 12, "", ui.gold)
    rosterTitle.atlasGameText = true
    rosterTitle:SetMaxLines(1)
    local list = ui.scrollingList(panel, 18, 106, 550, 41, 7)
    local roster = ui.scrollingList(panel, 590, 106, 262, 41, 7)
    ui.fill(panel, 579, 88, 1, 301, ui.rule)
    local footer = ui.text(panel, 20, 410, 832, 23, 12, "", ui.muted)
    footer:SetMaxLines(1)
    overlay.list, overlay.roster = list, roster
    local mount, selectedGUID, current, characters, currentStates, snapshots, focused

    local function stateFor(item, character)
        local states = snapshots[character.guid]
        return states and ((item.key and states[item.key]) or states.fallback) or "unknown"
    end
    local function currentState(item)
        return (item.key and currentStates[item.key]) or currentStates.fallback or "unknown"
    end
    local function waypointPoints()
        local points = {}
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        for _, item in ipairs(list.items) do
            if item.points and not complete(currentState(item)) then
                for _, point in ipairs(item.points) do
                    local requiredFaction = pointFactions[point.condition]
                    if located(point) and (not requiredFaction or requiredFaction == faction) then
                        points[#points + 1] = point
                    end
                end
            end
        end
        return points
    end
    local bulk = ui.action(panel, 663, 405, 189, 32, "Поставить метки", "Place", function()
        overlay:refresh()
        if #list.items > 1 and atlas.hasTomTomWaypoints() then
            footer:SetText(L("Метки поставлены: %d", atlas.addSourceWaypoints(waypointPoints())))
        end
    end)
    local disabledHover = CreateFrame("Frame", nil, panel)
    disabledHover:SetAllPoints(bulk)
    disabledHover:SetFrameLevel(bulk:GetFrameLevel() + 1)
    disabledHover:EnableMouse(true)
    local function showWaypointTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        ui.tooltipTitle(L(atlas.hasTomTomWaypoints() and "Поставить метки" or "Для нескольких меток нужен TomTom"))
        GameTooltip:Show()
    end
    local function hideWaypointTooltip(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end
    for _, region in ipairs({ bulk, disabledHover }) do
        region:HookScript("OnEnter", showWaypointTooltip)
        region:HookScript("OnLeave", hideWaypointTooltip)
        region:HookScript("OnHide", hideWaypointTooltip)
    end
    local function feedback(item)
        local state = currentState(item)
        if complete(state) then
            return (UnitName("player") or "") .. " · " .. L(labels[state])
        elseif not located(item.point) then return L("Точная точка неизвестна.")
        else return L("Поставить метку · %.1f, %.1f", item.point.x * 100, item.point.y * 100) end
    end
    local function focus(item)
        focused = item
        rosterTitle:SetText(atlas.displayName(item.name or mount.boss))
        for _, row in ipairs(list.rows) do row.selected:SetShown(row.item == item) end
        roster.items = characters
        roster:redraw()
        footer:SetText(feedback(item))
    end
    for _, row in ipairs(roster.rows) do
        row.name = ui.text(row, 4, 1, 238, 20, 13, "")
        row.name.atlasGameText = true
        row.name:SetMaxLines(1)
        row.state = ui.text(row, 4, 21, 238, 18, 12, "", ui.muted)
        row.state:SetMaxLines(1)
        row:ClearHighlightTexture()
    end
    function roster:onClick() end
    function roster:render(row, character)
        row.name:SetText(character.name .. " · " .. character.realm)
        local state = stateFor(focused, character)
        row.state:SetText(labels[state] or labels.unknown)
        row.state:SetTextColor(unpack(complete(state) and ui.mint or state == "available" and ui.paper or ui.muted))
    end
    for _, row in ipairs(list.rows) do
        row.selected = ui.fill(row, 0, 5, 2, 28, ui.gold)
        row.selected:SetDrawLayer("ARTWORK")
        row.mark = ui.icon(row, 7, 10, 23, "Rare")
        row.name = ui.text(row, 39, 1, 340, 21, 14, "")
        row.place = ui.text(row, 39, 21, 340, 17, 12, "", ui.muted)
        row.name.atlasGameText, row.place.atlasGameText = true, true
        row.name:SetMaxLines(1)
        row.place:SetMaxLines(1)
        row.status = ui.text(row, 382, 4, 144, 32, 12, "", ui.muted)
        row.status:SetJustifyH("RIGHT")
        row.status:SetMaxLines(2)
        row:SetScript("OnEnter", function(self) if self.item then focus(self.item) end end)
    end
    function list:render(row, item)
        row.selected:SetShown(item == focused)
        local done = 0
        for _, character in ipairs(characters) do if complete(stateFor(item, character)) then done = done + 1 end end
        local state = selectedGUID and stateFor(item, { guid = selectedGUID }) or currentState(item)
        local used = complete(state)
        ui.setIcon(row.mark, used and (item.shared and "Lock" or "ObjectiveComplete") or "Rare")
        row.mark:SetVertexColor(1, 1, 1)
        row.name:SetText(atlas.displayName(item.name or mount.boss))
        row.place:SetText(atlas.displayName(item.place or mount.place))
        row.name:SetTextColor(unpack(used and ui.muted or ui.paper))
        row.status:SetText(not selectedGUID and item.shared and "" or (selectedGUID or not item.key) and L(labels[state] or labels.unknown)
            or L("Выполнено: %d / %d", done, #characters))
        row.status:SetTextColor(unpack(used and ui.mint or ui.muted))
    end
    function overlay:refresh()
        if not mount then return end
        current = UnitGUID("player")
        local progress
        currentStates, progress = indexProgress(mount, current)
        characters, snapshots = {}, {}
        local count, total = 0, 0
        local selectedLabel = L("Весь отряд")
        for _, character in ipairs(atlas.accountCharacters()) do
            if not selectedGUID or selectedGUID == character.guid then
                characters[#characters + 1] = character
                local states, saved = indexProgress(mount, character.guid)
                snapshots[character.guid] = states
                if saved then count = count + saved.completedAttempts; total = total + saved.totalAttempts end
                if selectedGUID then selectedLabel = character.name .. " · " .. character.realm end
            end
        end
        title:SetText(atlas.displayName(mount.name))
        summary:SetText(selectedLabel .. "   /   " .. (total > 0 and L("Выполнено: %d / %d", count, total)
            or L(currentStates.fallback and "Можно идти" or "Нет данных")))
        local previous = focused and focused.identity
        list.items = sources(mount, progress)
        local sharedKey = #list.items > 1 and list.items[1].shared and list.items[1].key
        for _, item in ipairs(list.items) do
            if item.key ~= sharedKey then sharedKey = nil; break end
        end
        if sharedKey then
            summary:SetText(summary:GetText() .. "\n" .. L("Общая попытка для этих противников — отдельно для каждого персонажа"))
        end
        local multiple = #list.items > 1
        local enabled = multiple and atlas.hasTomTomWaypoints() and #waypointPoints() > 0
        bulk:SetShown(multiple)
        bulk:SetEnabled(enabled == true)
        bulk:SetAlpha(enabled and 1 or .55)
        disabledHover:SetShown(multiple and not enabled)
        footer:SetWidth(multiple and 625 or 832)
        focused = list.items[1]
        for _, item in ipairs(list.items) do if item.identity == previous then focused = item end end
        list:redraw()
        if focused then focus(focused) else roster.items = {}; roster:redraw(); footer:SetText("Нет данных") end
    end
    function list:onClick(item)
        if not item then return end
        -- Read the current lock again at click time, including while viewing an alt.
        overlay:refresh()
        for _, updated in ipairs(self.items) do
            if updated.identity == item.identity then
                focus(updated)
                if not complete(currentState(updated)) and located(updated.point) then
                    footer:SetText(atlas.openSource({}, updated.point) or "")
                end
                break
            end
        end
    end
    function overlay:open(target, guid)
        mount, selectedGUID, focused = target, guid, nil
        list.offset, roster.offset = 0, 0
        GameTooltip:Hide()
        self:refresh()
        self:Show()
    end
    overlay:SetScript("OnHide", function() GameTooltip:Hide() end)
    if UISpecialFrames then table.insert(UISpecialFrames, "MountAtlasPlannerSources") end
    overlay:Hide()
    return overlay
end
