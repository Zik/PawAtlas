-- Run from PawAtlas: lua5.1 tools/test_event_reminders.lua
assert(_VERSION == "Lua 5.1")
local atlas={addTranslations=function() end,getLocale=function() return "ruRU" end,
    L=function(value,...) return value:format(...) end}
assert(loadfile("Data/JournalData.lua"))("PawAtlas",atlas)
-- One reward can be available in independent events as well as calendar aliases.
local separateHoliday = 900001
atlas.eventReminderHolidays[separateHoliday] = { name = "A separate event", englishName = "A separate event" }
table.insert(atlas.eventReminderSources[352].holidays, separateHoliday)
local callback,timers,messages,requests,loaded,collected={},{},{},{},{},{}
local entryTimers, retryTimers = {}, {}
local opens,offset,readyRows=0,nil,true
local function date(day,hour) return {year=2026,month=11,monthDay=day,hour=hour or 0,minute=0} end
local start,finish=date(1),date(2)
local today, calendarRows = date(1,12), { { id=372, name="Test holiday" } }
local function calendarInfo(index)
    local row = calendarRows[index]
    return { eventID=row.id, calendarType="HOLIDAY", title=row.name, name=row.name,
        startTime=row.start or start, endTime=row.finish or finish }
end
local function flush()
    local limit=50
    while #timers>0 and limit>0 do table.remove(timers,1)();limit=limit-1 end
    assert(limit>0,"reminders cannot schedule an endless retry loop")
end
function CreateFrame() return {RegisterEvent=function() end,SetScript=function(_,_,fn) callback=fn end} end
C_Timer={After=function(delay,fn)
    if delay == 0 then timers[#timers+1] = fn
    elseif delay == 15 then
        entryTimers[#entryTimers+1] = fn
    else
        retryTimers[#retryTimers+1] = { delay = delay, run = fn }
    end
end}
local function finishEntryDelay()
    local pending = entryTimers
    entryTimers = {}
    for _, timer in ipairs(pending) do timer() end
    flush()
end
C_DateAndTime={GetCurrentCalendarTime=function() return today end}
C_Calendar={OpenCalendar=function() opens=opens+1 end,
    GetMonthInfo=function() return {year=2026,month=10} end,
    GetNumDayEvents=function(month,day) offset=month;assert(day==today.monthDay);return #calendarRows end,
    GetDayEvent=function(_,_,index) if readyRows then return calendarInfo(index) end end,
    GetHolidayInfo=function(_,_,index) return calendarInfo(index) end,
    SetMonth=function() error("must not change visible calendar month") end,
    SetAbsMonth=function() error("must not change visible calendar month") end}
local byItem={}
for id,rule in pairs(atlas.eventReminderSources) do byItem[rule.item]=id;collected[id]=true end
collected[202]=false
C_MountJournal={GetMountInfoByID=function(id)
    local rule=atlas.eventReminderSources[id]
    return rule.name,rule.spell,123,nil,nil,nil,nil,nil,nil,nil,collected[id]
end,GetMountFromItem=function(item)
    if item==33977 and not loaded[item] then return end
    return byItem[item]
end}
C_Item={GetItemInfo=function(item) if loaded[item] then return "Reward","|Hitem:"..item..":0|h[Reward]|h" end end,
    RequestLoadItemDataByID=function(item) requests[item]=(requests[item] or 0)+1 end}
DEFAULT_CHAT_FRAME={AddMessage=function(_,text) messages[#messages+1]=text end}
MountAtlasAccountDB={settings={}}
assert(loadfile("Core/EventReminders.lua"))("PawAtlas",atlas)
local holidays, bosses = 0, 0
local configuredHolidays=0
for _, rule in pairs(atlas.eventReminderSources) do if rule.holidays then configuredHolidays=configuredHolidays+1 end end
for _, reward in ipairs(atlas.eventReminderRewards()) do
    if reward.worldQuest then
        assert(reward.mount == 1250 and reward.worldQuest == 52196, "Mollie uses Kraulok's active world quest")
        bosses = bosses + 1
    else holidays = holidays + 1 end
end
assert(not atlas.eventRemindersEnabled() and holidays==configuredHolidays and bosses==1,"event settings expose all configured rewards")
local function group(key)
    for _, event in ipairs(atlas.eventReminderEvents()) do
        if event.key == key then return event end
    end
    error("missing group " .. key)
end
assert(#group("holiday:1808").rewards==7 and group("worldQuest:52196").icon==2176723,
    "anniversary rewards and Kraulok artwork are exposed in settings")
atlas.setEventReminderMuted("mount:202",true)
assert(group("holiday:372").mixed and not group("holiday:335").mixed,
    "saved per-mount mute settings appear as a mixed state only in their own groups")
atlas.setEventReminderGroupMuted("holiday:372",true)
assert(group("holiday:372").muted and not group("holiday:335").muted,
    "muting one holiday leaves other holidays enabled")
atlas.setEventReminderGroupMuted("holiday:372",false)
assert(not group("holiday:372").muted and not group("holiday:372").mixed,
    "explicit group enable overrides the saved legacy mute")
MountAtlasAccountDB.settings.eventReminderMuted = nil
callback(nil,"PLAYER_ENTERING_WORLD");finishEntryDelay()
assert(opens==0 and #messages==0,"disabled reminders do not request the calendar or send chat")
atlas.setEventRemindersEnabled(true);flush()
assert(opens==1 and #messages==0,"pending calendar does not produce a fake active event")
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(offset==1 and requests[33977]==1 and #messages==0,"current date uses offset from selected month and queues exact item")
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(requests[33977]==1,"duplicate calendar updates coalesce pending item requests")
atlas.setEventRemindersEnabled(false)
loaded[33977]=true
callback(nil,"ITEM_DATA_LOAD_RESULT",33977,true);flush()
assert(#messages==0,"late item response cannot deliver after disabling reminders")
atlas.setEventRemindersEnabled(true)
callback(nil,"PLAYER_ENTERING_WORLD")
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==0,"calendar readiness cannot bypass the entry delay")
callback(nil,"LOADING_SCREEN_ENABLED");finishEntryDelay()
assert(#messages==0,"a timer from before the next loading screen cannot deliver")
callback(nil,"LOADING_SCREEN_DISABLED")
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==0,"the new delay begins after the loading screen closes")
finishEntryDelay()
assert(#messages==1 and messages[1]:find("PawAtlas:",1,true) and messages[1]:find("Test holiday",1,true),"re-enable sends once after real data and link are loaded")
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
atlas.setEventRemindersEnabled(false);atlas.setEventRemindersEnabled(true)
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==1,"same occurrence is not repeated on refresh or disable/re-enable")
collected[226]=false
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(requests[37828]==1,"second exact reward waits for its item link")
byItem[37828],loaded[37828]=202,true
callback(nil,"ITEM_DATA_LOAD_RESULT",37828,true);flush()
assert(#messages==1 and requests[37828]==1,"a different positive mount ID blocks the loaded item with no retry")
byItem[37828],collected[226]=226,true
callback(nil,"MOUNT_JOURNAL_SEARCH_UPDATED");flush()
assert(#messages==1,"late item response rechecks the collected state")
collected[226]=false
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==2,"suppressed delivery does not prematurely consume occurrence deduplication")
atlas.setEventReminderMuted("mount:202",true)
start,finish,today=date(8),date(9),date(8,12)
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==3,"muted reward stays silent for a new occurrence while another reward can remind")
atlas.setEventReminderMuted("mount:202",false);flush()
assert(#messages==4,"unmuting can deliver an occurrence that was never shown")
readyRows=false;start,finish,today=date(15),date(16),date(15,12)
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==4,"partially loaded calendar cannot manufacture an event")
local worldQuestActive
C_TaskQuest = { IsActive = function(id)
    assert(id == 52196, "the weekly loot lockout is not the active world quest")
    return worldQuestActive
end }
collected[1250], loaded[174842] = false, true
atlas.setEventRemindersEnabled(false)
atlas.setEventRemindersEnabled(true)
callback(nil,"QUEST_LOG_UPDATE");flush()
assert(#messages==4,"unknown world quest activity does not send a reminder")
worldQuestActive = true
atlas.setEventReminderMuted("mount:1250",true);flush()
assert(#messages==4,"muted world boss reward stays silent")
atlas.setEventReminderMuted("mount:1250",false);flush()
assert(#messages==5 and messages[5]:find("Краулок",1,true),"active boss can remind before the calendar loads")
callback(nil,"QUEST_LOG_UPDATE");flush()
assert(#messages==5,"world quest updates do not repeat the announcement")

readyRows=true
calendarRows = {
    { id=335, name="Love is in the Air" },
    { id=423, name="Love is in the Air", start=date(15,1) },
    { id=separateHoliday, name="A separate event" },
}
collected[352],loaded[50250]=false,true
atlas.setEventReminderGroupMuted("holiday:335",true)
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==6 and messages[6]:find("A separate event",1,true),
    "muting one event does not mute another event that shares its reward and dates")
atlas.setEventReminderGroupMuted("holiday:335",false);flush()
assert(#messages==7 and messages[7]:find("Love is in the Air",1,true),
    "alias rows are one occurrence even when their start times differ")
table.remove(calendarRows,1)
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==7,"an overlapping alias alone cannot repeat the announcement")

calendarRows = { { id=1808, name="WoW's 22nd Anniversary" } }
local faction="Alliance"
function UnitFactionGroup() return faction end
collected[286],collected[287],loaded[43959],loaded[44083]=false,false,true,true
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==8 and messages[8]:find("|Hitem:43959:",1,true),
    "an Alliance character only receives the Alliance version of the mount")
faction="Horde"
callback(nil,"CALENDAR_UPDATE_EVENT_LIST");flush()
assert(#messages==9 and messages[9]:find("|Hitem:44083:",1,true),
    "the Horde version is eventually announced to an eligible character")
print("PawAtlas event reminders passed: opt-in, async cancellation, group settings, holiday aliases and faction gates")

local function coldReward(id)
    for mountID in pairs(collected) do collected[mountID] = mountID ~= id end
    local item = atlas.eventReminderSources[id].item
    loaded[item], requests[item] = nil, 0
    start, finish, today = date(1), date(2), date(1,12)
    calendarRows, worldQuestActive = { { id=372, name="Test holiday" } }, id == 1250
    timers, entryTimers, retryTimers, messages = {}, {}, {}, {}
    MountAtlasAccountDB = { settings = { eventRemindersEnabled = true } }
    assert(loadfile("Core/EventReminders.lua"))("PawAtlas", atlas)
    callback(nil, "PLAYER_ENTERING_WORLD")
    callback(nil, "CALENDAR_UPDATE_EVENT_LIST")
    finishEntryDelay()
    assert(requests[item] == 1 and #messages == 0, "one initial request for the eligible reward")
    return item
end
local function result(item, success)
    callback(nil, "ITEM_DATA_LOAD_RESULT", item, success)
    flush()
end
local function retryAfter(delay)
    assert(#retryTimers == 1 and retryTimers[1].delay == delay, "one retry timer at " .. delay .. " seconds")
    table.remove(retryTimers, 1).run()
    flush()
end
local item = coldReward(202)
result(item, false)
result(item, false)
callback(nil, "CALENDAR_UPDATE_EVENT_LIST")
callback(nil, "QUEST_LOG_UPDATE")
flush()
assert(requests[item] == 1, "duplicate failures and refreshes cannot bypass backoff")
retryAfter(2)
assert(requests[item] == 2)
loaded[item] = true
result(item, true)
result(item, true)
assert(#messages == 1 and #retryTimers == 0, "recovered item sends once")

item = coldReward(202)
result(item, true) -- The mount mapping is still cold.
result(item, true)
retryAfter(2)
assert(requests[item] == 2 and #retryTimers == 0, "an early success waits for backoff without duplicate timers")
loaded[item] = true
result(item, true)
assert(#messages == 1, "the notification uses the resolved mount mapping")

item = coldReward(226)
C_Item.IsItemDataCachedByID = function(id) return loaded[id] == true end
for attempt, delay in ipairs({2, 5, 10}) do
    result(item, false)
    retryAfter(delay)
    assert(requests[item] == attempt + 1)
end
result(item, false)
callback(nil, "CALENDAR_UPDATE_EVENT_LIST"); flush()
assert(requests[item] == 4 and #retryTimers == 0 and #messages == 0, "limited to three retries per active reward")
calendarRows = {}; callback(nil, "CALENDAR_UPDATE_EVENT_LIST"); flush()
calendarRows = { { id=372, name="Next holiday" } }
start, finish, today = date(8), date(9), date(8,12)
callback(nil, "CALENDAR_UPDATE_EVENT_LIST"); flush()
assert(requests[item] == 5, "a later holiday has a fresh retry budget")
result(item, false)
loaded[item] = true
result(item, true)
retryAfter(2)
assert(requests[item] == 5 and #messages == 1, "another load during backoff resolves without an extra request")

for _, cancel in ipairs({
    function() today = finish end,
    function() collected[202] = true end,
    function() atlas.setEventRemindersEnabled(false) end,
    function() atlas.setEventReminderGroupMuted("holiday:372", true) end,
    function() atlas.setEventReminderMuted("mount:202", true) end,
}) do
    item = coldReward(202)
    result(item, false)
    cancel()
    retryAfter(2)
    loaded[item] = true
    result(item, true)
    assert(requests[item] == 1 and #messages == 0, "ineligible rewards cancel retries and ignore late results")
end
item = coldReward(1250)
result(item, false)
worldQuestActive = false
retryAfter(2)
assert(requests[item] == 1 and #messages == 0, "a finished world quest cannot retry")
print("PawAtlas reminder retries passed: recovery, backoff, limit, late responses, cancellation and new events")
