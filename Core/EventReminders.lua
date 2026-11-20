local _, atlas = ...
atlas.addTranslations("enUS", {
    ["PawAtlas: %s — доступно событие: %s"] = "PawAtlas: %s — event available: %s",
})

local sources = atlas.eventReminderSources or {}
local groups, holidaysByID, bossesByQuest = {}, {}, {}
for id, holiday in pairs(atlas.eventReminderHolidays or {}) do
    local key = "holiday:" .. id
    groups[key] = { key = key, name = holiday.name, englishName = holiday.englishName, icon = holiday.icon, mounts = {} }
    holidaysByID[id] = groups[key]
    for _, alias in ipairs(holiday.ids or {}) do holidaysByID[alias] = groups[key] end
end
for mountID, rule in pairs(sources) do
    if rule.worldQuest then
        local key = "worldQuest:" .. rule.worldQuest
        if not groups[key] then
            groups[key] = { key = key, worldQuest = rule.worldQuest, name = rule.boss, englishName = rule.englishBoss,
                icon = rule.bossIcon, mounts = {} }
            bossesByQuest[rule.worldQuest] = groups[key]
        end
        groups[key].mounts[mountID] = true
    else
        for _, holidayID in ipairs(rule.holidays) do
            local group = holidaysByID[holidayID]
            if group then group.mounts[mountID] = true end
        end
    end
end
local sent, itemLoads, calendarReady, queued = {}, {}, false, false
local entryGeneration, loadingScreen, deliveryReady = 0, false, false
local function readable(value) return not (issecretvalue and issecretvalue(value)) end
local function number(value)
    return readable(value) and type(value) == "number" and value >= 0 and value < math.huge
end
local function settings(write)
    if type(MountAtlasAccountDB) ~= "table" then
        if not write then return end
        MountAtlasAccountDB = {}
    end
    if type(MountAtlasAccountDB.settings) ~= "table" then
        if not write then return end
        MountAtlasAccountDB.settings = {}
    end
    return MountAtlasAccountDB.settings
end
function atlas.eventRemindersEnabled()
    local saved = settings()
    return saved ~= nil and saved.eventRemindersEnabled == true
end
local function muted(key, eventKey)
    local saved = settings()
    local preferences = saved and saved.eventReminderMuted
    if type(preferences) ~= "table" then return false end
    if eventKey and preferences[eventKey] ~= nil then return preferences[eventKey] == true end
    return preferences[key] == true
end
local function rewardInfo(id, rule)
    local name, spell, icon, collected
    if C_MountJournal and C_MountJournal.GetMountInfoByID then
        local info = { C_MountJournal.GetMountInfoByID(id) }
        name, spell, icon, collected = info[1], info[2], info[3], info[11]
    end
    local english = atlas.getLocale() == "enUS"
    if not readable(name) or type(name) ~= "string" or name == "" then name = english and rule.englishName or rule.name end
    if not readable(icon) then icon = nil end
    if not readable(collected) or type(collected) ~= "boolean" then collected = nil end
    return name, icon, collected, readable(spell) and spell == rule.spell
end
function atlas.eventReminderRewards()
    local result = {}
    for id, rule in pairs(sources) do
        local name, icon = rewardInfo(id, rule)
        local key = "mount:" .. id
        result[#result + 1] = { key = key, mount = id, item = rule.item, name = name, icon = icon,
            worldQuest = rule.worldQuest, muted = muted(key) }
    end
    table.sort(result, function(a, b) return a.mount < b.mount end)
    return result
end

function atlas.eventReminderEvents()
    local result = {}
    local english = atlas.getLocale() == "enUS"
    for key, group in pairs(groups) do
        local event = { key = key, name = english and group.englishName or group.name, icon = group.icon,
            worldQuest = group.worldQuest, rewards = {} }
        local disabled = 0
        for mountID in pairs(group.mounts) do
            local name, icon, collected = rewardInfo(mountID, sources[mountID])
            local isMuted = muted("mount:" .. mountID, key)
            if isMuted then disabled = disabled + 1 end
            event.rewards[#event.rewards + 1] = { mount = mountID, name = name, icon = icon,
                collected = collected, muted = isMuted }
        end
        if #event.rewards > 0 then
            table.sort(event.rewards, function(a, b) return a.mount < b.mount end)
            event.muted = disabled == #event.rewards
            event.mixed = disabled > 0 and not event.muted
            result[#result + 1] = event
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local function calendarTime(value)
    if type(value) ~= "table" then return end
    for _, field in ipairs({ "year", "month", "monthDay", "hour", "minute" }) do
        if not number(value[field]) then return end
    end
    return ((((value.year * 12 + value.month) * 32 + value.monthDay) * 24 + value.hour) * 60 + value.minute)
end
local function activeEvents()
    local api = C_Calendar
    if not calendarReady or not api or not api.GetMonthInfo or not api.GetNumDayEvents or not api.GetDayEvent
        or not C_DateAndTime or not C_DateAndTime.GetCurrentCalendarTime then return end
    local today = C_DateAndTime.GetCurrentCalendarTime()
    local now = calendarTime(today)
    local month = api.GetMonthInfo()
    if not now or not month or not number(month.year) or not number(month.month) then return end
    -- Read relative to the selected calendar month without changing the user's
    -- month, calendar filters, open event or visible Blizzard calendar window.
    local offset = (today.year - month.year) * 12 + today.month - month.month
    local count = api.GetNumDayEvents(offset, today.monthDay)
    if not number(count) then return end
    local result = {}
    for index = 1, count do
        local event = api.GetDayEvent(offset, today.monthDay, index)
        if not event then return end
        if readable(event.calendarType) and event.calendarType == "HOLIDAY" and readable(event.eventID) then
            local group = holidaysByID[tonumber(event.eventID)]
            if group then
                local holiday = api.GetHolidayInfo and api.GetHolidayInfo(offset, today.monthDay, index)
                local start = calendarTime(holiday and holiday.startTime or event.startTime)
                local finish = calendarTime(holiday and holiday.endTime or event.endTime)
                local name = holiday and holiday.name or event.title
                if start and finish and start <= now and now < finish
                    and readable(name) and type(name) == "string" and name ~= "" then
                    local current = result[group]
                    if current then
                        current.start, current.finish = math.min(current.start, start), math.max(current.finish, finish)
                    else result[group] = { name = name, start = start, finish = finish } end
                end
            end
        end
    end
    return result
end
local function requestItem(item)
    if not itemLoads[item] and C_Item and C_Item.RequestLoadItemDataByID then
        itemLoads[item] = "pending"
        C_Item.RequestLoadItemDataByID(item)
    end
end
local function rewardLink(rule)
    local link = C_Item and C_Item.GetItemInfo and select(2, C_Item.GetItemInfo(rule.item))
    if readable(link) and type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")) == rule.item then return link end
    link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(rule.spell)
    if readable(link) and type(link) == "string" and tonumber(link:match("|Hspell:(%d+)")) == rule.spell then return link end
    requestItem(rule.item)
end
local function notifyReward(id, rule, group, eventName, occurrence)
    local key = "mount:" .. id
    local deliveryKey = group.key .. ":" .. key
    local previous = sent[deliveryKey]
    -- The same holiday may appear under several calendar IDs with slightly
    -- different times. Overlapping windows are one occurrence for this reward.
    if previous and (group.worldQuest
        or previous.start < occurrence.finish and occurrence.start < previous.finish) then
        if not group.worldQuest then
            previous.start = math.min(previous.start, occurrence.start)
            previous.finish = math.max(previous.finish, occurrence.finish)
        end
        return
    end
    if muted(key, group.key) then return end
    if rule.requiresAlliance or rule.requiresHorde then
        local faction = UnitFactionGroup and UnitFactionGroup("player")
        if not readable(faction) or (rule.requiresAlliance and faction ~= "Alliance")
            or (rule.requiresHorde and faction ~= "Horde") then return end
    end
    local _, _, collected, identity = rewardInfo(id, rule)
    local mount = atlas.mountByID and atlas.mountByID(id)
    if not identity or collected ~= false or (mount and mount.unavailable) then return end
    local itemMount = C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(rule.item)
    if readable(itemMount) and (itemMount == nil or itemMount == 0) then requestItem(rule.item) end
    if not number(itemMount) or itemMount ~= id then return end
    local link = rewardLink(rule)
    if link and DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(atlas.L("PawAtlas: %s — доступно событие: %s", link, eventName))
        sent[deliveryKey] = group.worldQuest and true
            or { start = occurrence.start, finish = occurrence.finish }
    end
end
local function evaluate(worldQuestsOnly)
    if not deliveryReady or not atlas.eventRemindersEnabled() then return end
    local events = not worldQuestsOnly and activeEvents()
    for id, rule in pairs(sources) do
        if rule.worldQuest then
            local active = C_TaskQuest and C_TaskQuest.IsActive and C_TaskQuest.IsActive(rule.worldQuest)
            if readable(active) and active == true then
                local name = atlas.getLocale() == "enUS" and rule.englishBoss or rule.boss
                notifyReward(id, rule, bossesByQuest[rule.worldQuest], name)
            end
        end
    end
    for group, event in pairs(events or {}) do
        for id in pairs(group.mounts) do
            notifyReward(id, sources[id], group, event.name, event)
        end
    end
end
local pendingCalendar = false
local function queue(worldQuestsOnly)
    if not deliveryReady or not atlas.eventRemindersEnabled() then return end
    if not worldQuestsOnly then pendingCalendar = true end
    if queued then return end
    queued = true
    C_Timer.After(0, function()
        local onlyQuests = not pendingCalendar
        queued, pendingCalendar = false, false
        evaluate(onlyQuests)
    end)
end
local function delayDelivery()
    deliveryReady = false
    entryGeneration = entryGeneration + 1
    if loadingScreen then return end
    local generation = entryGeneration
    C_Timer.After(15, function()
        if generation ~= entryGeneration then return end
        deliveryReady = true
        evaluate()
    end)
end
local function refreshSettings()
    if atlas.refreshEventReminderSettings then atlas.refreshEventReminderSettings() end
end
local function requestCalendar()
    if not atlas.eventRemindersEnabled() then return end
    calendarReady = false
    if C_Calendar and C_Calendar.OpenCalendar then C_Calendar.OpenCalendar() end
end
function atlas.setEventRemindersEnabled(enabled)
    settings(true).eventRemindersEnabled = enabled == true
    refreshSettings()
    if enabled == true then requestCalendar(); queue(true) end
end
local function saveMute(key, value)
    local saved = settings(true)
    if type(saved.eventReminderMuted) ~= "table" then saved.eventReminderMuted = {} end
    saved.eventReminderMuted[key] = value
    refreshSettings()
    queue()
    return true
end
function atlas.setEventReminderMuted(key, value)
    local id = type(key) == "string" and tonumber(key:match("^mount:(%d+)$"))
    if not id or not sources[id] then return false end
    return saveMute(key, value == true or nil)
end
function atlas.setEventReminderGroupMuted(key, value)
    if not groups[key] then return false end
    -- A deliberate group choice supersedes legacy per-mount preferences even when enabling it.
    return saveMute(key, value == true)
end

local frame = CreateFrame("Frame")
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "LOADING_SCREEN_ENABLED", "LOADING_SCREEN_DISABLED",
    "CALENDAR_UPDATE_EVENT_LIST", "QUEST_LOG_UPDATE", "NEW_MOUNT_ADDED",
    "MOUNT_JOURNAL_SEARCH_UPDATED", "ITEM_DATA_LOAD_RESULT" }) do frame:RegisterEvent(event) end
frame:SetScript("OnEvent", function(_, event, id, success)
    if event == "PLAYER_ENTERING_WORLD" then
        delayDelivery()
        requestCalendar()
    elseif event == "LOADING_SCREEN_ENABLED" or event == "LOADING_SCREEN_DISABLED" then
        loadingScreen = event == "LOADING_SCREEN_ENABLED"
        delayDelivery()
    elseif event == "CALENDAR_UPDATE_EVENT_LIST" then calendarReady = true; queue()
    elseif event == "QUEST_LOG_UPDATE" then queue(true)
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        if not number(id) or itemLoads[id] ~= "pending" then return end
        itemLoads[id] = success == true and "loaded" or "failed"
        if success == true then queue() end
    else refreshSettings(); queue() end
end)
