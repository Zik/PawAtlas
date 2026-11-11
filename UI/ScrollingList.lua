local _, atlas = ...
local ui = atlas.ui

-- Reuse the visible rows. Both catalog and planner scroll without constructing
-- frames for entries outside their window.
function ui.scrollingList(parent, x, y, width, step, capacity, smooth)
    local height = step * capacity
    local list = ui.place(CreateFrame("Frame", nil, parent), parent, x, y, width, height)
    list.rows, list.items, list.offset = {}, {}, 0
    local viewport, content = nil, list
    local rowCount = capacity
    if smooth then
        rowCount = capacity + 1
        viewport = ui.place(CreateFrame("ScrollFrame", nil, list), list, 0, 0, width - 8, height)
        content = CreateFrame("Frame", nil, viewport)
        content:SetSize(width - 8, rowCount * step)
        viewport:SetScrollChild(content)
    end
    local rail = ui.fill(list, width - 3, 0, 2, height - 4, ui.rule)
    local slider = ui.place(CreateFrame("Slider", nil, list), list, width - 7, 0, 10, height - 4)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(unpack(ui.gold))
    thumb:SetSize(4, 24)
    slider:SetThumbTexture(thumb)
    slider:SetFrameLevel(list:GetFrameLevel() + 5)
    rail:SetParent(slider)
    rail:SetDrawLayer("ARTWORK")
    thumb:SetDrawLayer("OVERLAY")
    slider:SetOrientation("VERTICAL")
    if not smooth then
        slider:SetValueStep(1)
        slider:SetObeyStepOnDrag(true)
    end
    slider:EnableMouse(true)
    local syncing = false
    local position, first, limit = 0, 0, 0
    local start, target, elapsed
    local duration = .18

    local function stopScroll()
        if target then
            target = nil
            list:SetScript("OnUpdate", nil)
        end
    end

    local function bindRows(force)
        for slot = 1, rowCount do
            local index = list.offset + slot
            local row = list.rows[smooth and ((index - 1) % rowCount + 1) or slot]
            local item = list.items[index]
            local changed = row.item ~= item
            if smooth and changed and row.item then
                if GameTooltip:IsOwned(row) then GameTooltip:Hide() end
                row:Hide() -- Reset hover state before binding this button to a new entry.
            end
            if smooth and row.listSlot ~= slot then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(slot - 1) * step)
                row.listSlot = slot
            end
            if force or changed then
                row.item = item
                row:SetShown(item ~= nil)
                if item then list:render(row, item, index) end
                if row.refreshModelPreview then row.refreshModelPreview() end
            end
        end
    end

    local function setPosition(value, redraw)
        position = math.max(0, math.min(value, limit))
        local offset = math.floor(position)
        list.offset = offset
        if redraw or offset ~= first then bindRows(redraw) end
        first = offset
        viewport:SetVerticalScroll((position - offset) * step)
        syncing = true
        slider:SetValue(position)
        syncing = false
    end

    function list:redraw()
        local total = #self.items
        limit = math.max(0, total - capacity)
        if smooth then
            if self.offset ~= first or (target and target > limit) then stopScroll() end
        else
            self.offset = math.max(0, math.min(self.offset, limit))
            bindRows(true)
        end
        rail:SetShown(limit > 0)
        thumb:SetShown(limit > 0)
        slider:SetShown(limit > 0)
        if limit > 0 then
            local size = math.max(15, (height - 4) * capacity / total)
            -- The native slider owns the thumb position and drag hit region.
            thumb:SetSize(4, size)
            syncing = true
            slider:SetMinMaxValues(0, limit)
            if not smooth then slider:SetValue(self.offset) end
            syncing = false
        end
        if smooth then setPosition(self.offset ~= first and self.offset or position, true) end
    end

    slider:SetScript("OnValueChanged", function(_, value)
        if syncing then return end
        if smooth then
            stopScroll()
            setPosition(value)
        else
            list.offset = math.floor(value + .5)
            list:redraw()
        end
    end)

    if smooth then
        slider:SetScript("OnMouseDown", stopScroll)
        list:SetScript("OnHide", stopScroll)
        function list:resetScroll()
            stopScroll()
            self.offset, position = 0, 0
        end
    end

    local function updateScroll(_, dt)
        elapsed = elapsed + dt
        local progress = math.min(1, elapsed / duration)
        local remaining = 1 - progress
        setPosition(target + (start - target) * remaining * remaining * remaining)
        if progress == 1 then stopScroll() end
    end

    function list:scroll(delta)
        if smooth then
            local goal = math.max(0, math.min((target or math.floor(position + .5)) + delta, limit))
            if goal == (target or position) then return end
            start, target, elapsed = position, goal, 0
            self:SetScript("OnUpdate", updateScroll)
        else
            self.offset = self.offset + delta
            self:redraw()
        end
    end
    function list:reveal(item)
        if smooth then stopScroll() end
        for i, value in ipairs(self.items) do
            if value == item then
                local offset = smooth and math.floor(position + .5) or self.offset
                local outside = i <= offset or i > offset + capacity
                if smooth then
                    setPosition(outside and i - 1 or offset)
                elseif outside then
                    self.offset = i - 1
                    self:redraw()
                end
                break
            end
        end
    end
    local function wheel(_, delta) list:scroll(-delta) end
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", wheel)
    slider:EnableMouseWheel(true)
    slider:SetScript("OnMouseWheel", wheel)
    for i = 1, rowCount do
        local row = ui.button(content, 0, (i - 1) * step, width - 8, step - 4, function(self) list:onClick(self.item) end)
        row.listSlot = i
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", wheel)
        list.rows[i] = row
    end
    return list
end
