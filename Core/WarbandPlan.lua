local _, atlas = ...
local accountLootSources = atlas.accountLootSources or {}
local personalPlanID = "personal"
local maxProfiles, maxName = 20, 48

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function cleanPlanName(value)
    if not readable(value) or type(value) ~= "string" or #value > maxName * 4
        or value:find("[%c|<>]") then return end
    value = value:match("^ *(.-) *$")
    local index, length = 1, 0
    while index <= #value do
        local byte = value:byte(index)
        local width, code, minimum = 1, byte, 0
        if byte >= 0xC2 and byte <= 0xDF then width, code, minimum = 2, byte - 0xC0, 0x80
        elseif byte >= 0xE0 and byte <= 0xEF then width, code, minimum = 3, byte - 0xE0, 0x800
        elseif byte >= 0xF0 and byte <= 0xF4 then width, code, minimum = 4, byte - 0xF0, 0x10000
        elseif byte >= 0x80 then return end
        for offset = 1, width - 1 do
            local continuation = value:byte(index + offset)
            if not continuation or continuation < 0x80 or continuation > 0xBF then return end
            code = code * 64 + continuation - 0x80
        end
        if code < minimum or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF)
            or (code >= 0x80 and code <= 0x9F) or code == 0x061C or code == 0xFEFF
            or (code >= 0x200B and code <= 0x200F) or (code >= 0x2028 and code <= 0x202E)
            or (code >= 0x2060 and code <= 0x206F) then return end
        index, length = index + width, length + 1
        if length > maxName then return end
    end
    return value
end
atlas.cleanPlanName = cleanPlanName

local function number(value)
    return readable(value) and type(value) == "number" and value >= 0 and value < math.huge
end

local function playerGUID()
    local guid = UnitGUID and UnitGUID("player")
    return readable(guid) and type(guid) == "string" and guid ~= "" and guid or nil
end

local function savedAccount()
    return type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB or nil
end

local function accountForWrite()
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    return MountAtlasAccountDB
end

local awaitingLoginCharacter
function atlas.selectPlanCharacter(guid)
    awaitingLoginCharacter = false
    if atlas.isWarbandCharacterHidden(guid) then guid = nil end
    local db = accountForWrite()
    if type(db.settings) ~= "table" then db.settings = {} end
    db.settings.plannerCharacterGUID = guid
    if atlas.queueExpeditionStatsRefresh then atlas.queueExpeditionStatsRefresh() end
    if atlas.queuePlanBrokerStatsRefresh then atlas.queuePlanBrokerStatsRefresh() end
end

local function database()
    local db = accountForWrite()
    for _, key in ipairs({ "plan", "planRemoved", "planMigrations" }) do
        if type(db[key]) ~= "table" then db[key] = {} end
    end
    local guid = playerGUID()
    if guid and type(MountAtlasDB) == "table" and not MountAtlasDB.planMigrated and not db.planMigrations[guid] then
        local order = type(db.planOrder) == "table" and db.planOrder
        local migrated = {}
        for id, enabled in pairs(type(MountAtlasDB.plan) == "table" and MountAtlasDB.plan or {}) do
            local key = tostring(id)
            if enabled and not db.planRemoved[key] and not db.plan[key] then
                db.plan[key] = true
                migrated[#migrated + 1] = key
            end
        end
        if order then
            table.sort(migrated)
            for _, key in ipairs(migrated) do order[#order + 1] = key end
        end
        -- Kept separately from character snapshots: removing a character or a
        -- shared target must not replay its legacy personal plan on next login.
        MountAtlasDB.planMigrated = true
        db.planMigrations[guid] = true
    end
    return db
end

local function planChanged()
    if atlas.queuePlanBrokerRefresh then atlas.queuePlanBrokerRefresh() end
    if atlas.queueExpeditionTrackerRefresh then atlas.queueExpeditionTrackerRefresh() end
end

local function profileStore(db)
    local store = db and db.planProfiles
    if type(store) == "table" and store.version == 1
        and type(store.entries) == "table" and type(store.order) == "table" then return store end
end

local function planRecord(db, profileID)
    if not profileID or profileID == personalPlanID then
        return db and type(db.plan) == "table" and db or nil
    end
    local store = profileStore(db)
    local entry = store and store.entries[profileID]
    if type(entry) == "table" and type(entry.name) == "string"
        and type(entry.plan) == "table" and type(entry.planOrder) == "table" then return entry end
end

function atlas.planProfiles()
    local result = { { id = personalPlanID, name = atlas.L("Личный план") } }
    local db = savedAccount()
    local store = profileStore(db)
    if not store then return result end
    local seen = {}
    for _, id in ipairs(store.order) do
        local entry = type(id) == "string" and id ~= personalPlanID and planRecord(db, id)
        if entry and not seen[id] then
            result[#result + 1], seen[id] = { id = id, name = entry.name }, true
        end
    end
    return result
end

function atlas.movePlanProfile(id, anchorID, after)
    if not readable(id) or not readable(anchorID) or type(id) ~= "string" or type(anchorID) ~= "string"
        or id == personalPlanID or anchorID == personalPlanID or id == anchorID then return false end
    local store = profileStore(savedAccount())
    if not store then return false end

    local profiles, order = atlas.planProfiles(), {}
    local sourceIndex, anchorIndex
    for i = 2, #profiles do
        local profileID = profiles[i].id
        order[#order + 1] = profileID
        if profileID == id then sourceIndex = #order end
        if profileID == anchorID then anchorIndex = #order end
    end
    if not sourceIndex or not anchorIndex or sourceIndex == anchorIndex + (after and 1 or -1) then return false end

    table.remove(order, sourceIndex)
    if sourceIndex < anchorIndex then anchorIndex = anchorIndex - 1 end
    table.insert(order, anchorIndex + (after and 1 or 0), id)
    store.order = order
    planChanged()
    return true
end

function atlas.activePlanID()
    local db = savedAccount()
    local settings = db and db.settings
    local id = type(settings) == "table" and settings.plannerPlanID
    return type(id) == "string" and planRecord(db, id) and id or personalPlanID
end

local function setActivePlan(db, id)
    if type(db.settings) ~= "table" then db.settings = {} end
    db.settings.plannerPlanID = id
    planChanged()
end

function atlas.selectPlan(id)
    if type(id) ~= "string" or (id ~= personalPlanID and not planRecord(savedAccount(), id)) then return false end
    if id ~= atlas.activePlanID() then setActivePlan(accountForWrite(), id) end
    return true
end

function atlas.renamePlan(id, name)
    local entry = type(id) == "string" and id ~= personalPlanID and planRecord(savedAccount(), id)
    if not entry then return false, "profile" end
    name = cleanPlanName(name)
    if not name or name == "" then return false, "name" end
    if entry.name ~= name then
        entry.name = name
        if id == atlas.activePlanID() then planChanged() end
    end
    return true
end

function atlas.deletePlanProfile(id)
    local db = savedAccount()
    if type(id) ~= "string" or id == personalPlanID or not planRecord(db, id) then
        return false, "profile"
    end
    local active = atlas.activePlanID() == id
    local store = profileStore(db)
    store.entries[id] = nil
    for index = #store.order, 1, -1 do
        if store.order[index] == id then table.remove(store.order, index) end
    end
    if active then setActivePlan(db, personalPlanID) end
    return true
end

function atlas.addImportedPlan(name, ids)
    local db = savedAccount()
    local store = profileStore(db)
    if db and db.planProfiles ~= nil and not store then return nil, "profiles_version" end
    if store then
        local count = 0
        for _ in pairs(store.entries) do count = count + 1 end
        if count >= maxProfiles then return nil, "profiles_limit" end
    end
    local entry = { name = name, plan = {}, planOrder = {} }
    for _, id in ipairs(ids) do
        local key = tostring(id)
        entry.plan[key], entry.planOrder[#entry.planOrder + 1] = true, key
    end
    db = accountForWrite()
    store = store or { version = 1, nextID = 1, order = {}, entries = {} }
    local nextID = store.nextID
    if not number(nextID) or nextID < 1 or nextID > 2147483647 or nextID % 1 ~= 0 then
        return nil, "profiles_version"
    end
    local id = "import:" .. nextID
    while store.entries[id] do
        nextID = nextID + 1
        id = "import:" .. nextID
    end
    store.nextID = nextID + 1
    store.entries[id], store.order[#store.order + 1] = entry, id
    db.planProfiles = store
    setActivePlan(db, id)
    return id
end

local function eachPlan(db, callback)
    local personal = planRecord(db)
    if personal then callback(personal, db.planRemoved) end
    local store = profileStore(db)
    if not store then return end
    for id in pairs(store.entries) do
        local record = id ~= personalPlanID and planRecord(db, id)
        if record then callback(record) end
    end
end

function atlas.isPlanned(mount, profileID)
    local record = planRecord(savedAccount(), profileID)
    return record ~= nil and record.plan[tostring(mount.id)] == true
end

local function removePlanTarget(record, key, removed)
    if not record.plan[key] then return false end
    local mountKey = tostring(key)
    record.plan[key] = nil
    if removed then removed[mountKey] = true end
    local order = record.planOrder
    if type(order) == "table" then
        for i = #order, 1, -1 do
            if tostring(order[i]) == mountKey then table.remove(order, i) end
        end
    end
    return true
end

local function notifyCompletion(changed)
    if changed then
        planChanged()
        if atlas.refreshDetails then atlas.refreshDetails() end
    end
    return changed
end

local function removeCompletedTargets(db, ids)
    local changed = false
    eachPlan(db, function(record, removed)
        for id in pairs(ids) do
            if removePlanTarget(record, tostring(id), removed) then changed = true end
            if removePlanTarget(record, id, removed) then changed = true end
        end
    end)
    return notifyCompletion(changed)
end

local pendingCollection = {}
local collectionMembershipReady = false

function atlas.completePlanTarget(mountID)
    local id = readable(mountID) and tonumber(mountID)
    if not number(id) or id <= 0 or id % 1 ~= 0 then return false end
    pendingCollection[id] = nil
    return removeCompletedTargets(database(), { [id] = true })
end

local function reconcileCollection(db)
    local journal = C_MountJournal
    if not next(pendingCollection) or not journal or not journal.GetMountInfoByID then return end
    local completed = {}
    for id in pairs(pendingCollection) do
        local collected = select(11, journal.GetMountInfoByID(id))
        if readable(collected) and type(collected) == "boolean" then
            pendingCollection[id] = nil
            if collected then completed[id] = true end
        end
    end
    -- Missing old IDs should not keep the retry event alive once the client
    -- has supplied a usable journal membership list.
    if not collectionMembershipReady and next(pendingCollection) and journal.GetMountIDs then
        local ids = journal.GetMountIDs()
        if readable(ids) and type(ids) == "table" and (not canaccesstable or canaccesstable(ids)) then
            local known = {}
            for _, id in ipairs(ids) do
                if number(id) and id > 0 then known[id] = true end
            end
            if next(known) then
                collectionMembershipReady = true
                for id in pairs(pendingCollection) do
                    if not known[id] then pendingCollection[id] = nil end
                end
            end
        end
    end
    if next(completed) then removeCompletedTargets(db, completed) end
end

local planEvents = CreateFrame("Frame")
local retryEvent = "MOUNT_JOURNAL_SEARCH_UPDATED"
local retryQueued
planEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
planEvents:RegisterEvent("COVENANT_CHOSEN")
planEvents:SetScript("OnEvent", function(self, event, isInitialLogin)
    if event == "COVENANT_CHOSEN" then
        if atlas.queueAttemptRefresh then atlas.queueAttemptRefresh(true) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        self:UnregisterEvent(event)
        local db = database()
        if isInitialLogin then
            local guid = playerGUID()
            local roster = db.characters
            if type(roster) ~= "table" or type(roster[guid]) ~= "table" then guid = nil end
            atlas.selectPlanCharacter(guid)
            awaitingLoginCharacter = not guid
        end
        eachPlan(db, function(record)
            for key, enabled in pairs(record.plan) do
                local id = tonumber(key)
                if enabled and number(id) and id > 0 and id % 1 == 0 then pendingCollection[id] = true end
            end
        end)
        reconcileCollection(db)
        if next(pendingCollection) then self:RegisterEvent(retryEvent) end
    elseif not retryQueued then
        retryQueued = true
        C_Timer.After(0, function()
            retryQueued = false
            reconcileCollection(savedAccount())
            if not next(pendingCollection) then self:UnregisterEvent(retryEvent) end
        end)
    end
end)

function atlas.togglePlan(mount, profileID)
    local personal = not profileID or profileID == personalPlanID
    local db = personal and database() or savedAccount()
    local record, key = planRecord(db, profileID), tostring(mount.id)
    if not record then return false end
    local removed = personal and db.planRemoved or nil
    local order = type(record.planOrder) == "table" and record.planOrder
    if record.plan[key] then
        removePlanTarget(record, key, removed)
    else
        local owned = C_MountJournal and select(11, C_MountJournal.GetMountInfoByID(mount.id))
        if mount.unavailable or (readable(owned) and owned) then return false end
        record.plan[key] = true
        if removed then removed[key] = nil end
        if order then order[#order + 1] = key end
    end
    planChanged()
    return record.plan[key] == true
end

local function addJournalPlanTargets(plan, targets, seen)
    local unresolved
    for key, enabled in pairs(plan) do
        if enabled and type(key) == "string" and not seen[key] then
            local id = tonumber(key)
            if number(id) and id > 0 and id % 1 == 0 and tostring(id) == key then
                unresolved = unresolved or {}
                unresolved[id] = true
            end
        end
    end
    if not unresolved then return false end

    local journal = C_MountJournal
    if not journal or not journal.GetMountIDs or not journal.GetMountInfoByID then return true end
    local ids = journal.GetMountIDs()
    if not readable(ids) or type(ids) ~= "table" or (canaccesstable and not canaccesstable(ids))
        or not next(ids) then return true end

    local pending = false
    for _, id in ipairs(ids) do
        if number(id) and unresolved[id] then
            local name, spell, _, _, _, _, _, _, _, _, collected = journal.GetMountInfoByID(id)
            if readable(name) and type(name) == "string" and name ~= "" and readable(spell) then
                if not atlas.isExcludedJournalMount(id, name, spell, readable(collected) and collected) then
                    targets[#targets + 1] = { id = id, name = name }
                end
            else
                pending = true
            end
            unresolved[id] = nil
            if not next(unresolved) then break end
        end
    end
    -- IDs absent from a loaded membership list are not pending names.
    return pending
end

function atlas.planTargets(includeJournal, profileID)
    local db, targets, ranks, seen = planRecord(savedAccount(), profileID), {}, {}, {}
    if not db or not next(db.plan) then return targets, false end
    if type(db.planOrder) == "table" then
        for i, id in ipairs(db.planOrder) do
            local key = tostring(id)
            if not ranks[key] then ranks[key] = i end
        end
    end
    for key, enabled in pairs(db.plan) do
        local id = tonumber(key)
        local mount = enabled and id and tostring(id) == key and atlas.mountByID(id)
        if mount then
            targets[#targets + 1], seen[key] = mount, true
        end
    end
    -- Supply native names before the catalog opens without inserting a partial batch.
    local pending = includeJournal and addJournalPlanTargets(db.plan, targets, seen) or false
    table.sort(targets, function(a, b)
        local ai, bi = ranks[tostring(a.id)] or math.huge, ranks[tostring(b.id)] or math.huge
        if ai ~= bi then return ai < bi end
        local ap, bp = a.place or "", b.place or ""
        if ap ~= bp then return ap < bp end
        local an, bn = a.name or "", b.name or ""
        if an ~= bn then return an < bn end
        return a.id < b.id
    end)
    return targets, pending
end

function atlas.planShareData(profileID)
    local personal = not profileID or profileID == personalPlanID
    local record = planRecord(savedAccount(), profileID)
    if not record and not personal then return nil, "profile" end
    local name = personal and atlas.L("Личный план") or record.name
    local ids, seen = {}, {}
    if not record then return ids, name end
    local function append(value)
        local id = tonumber(value)
        if number(id) and id > 0 and id <= 2147483647 and id % 1 == 0 and not seen[id]
            and (record.plan[tostring(id)] or record.plan[id]) then
            ids[#ids + 1], seen[id] = id, true
        end
    end
    for _, id in ipairs(type(record.planOrder) == "table" and record.planOrder or {}) do append(id) end
    for _, mount in ipairs(atlas.planTargets(true, profileID)) do append(mount.id) end
    local unresolved = {}
    for key, enabled in pairs(record.plan) do
        local id = tonumber(key)
        if enabled and number(id) and not seen[id] then unresolved[#unresolved + 1] = id end
    end
    table.sort(unresolved)
    for _, id in ipairs(unresolved) do append(id) end
    return ids, name
end

function atlas.movePlanTarget(mountID, anchorID, after, profileID)
    local db = planRecord(savedAccount(), profileID)
    if not db then return false end
    local source, anchor = tostring(mountID), tostring(anchorID)
    if source == anchor or not db.plan[source] or not db.plan[anchor] then return false end

    local targets, sourceIndex, anchorIndex = atlas.planTargets(false, profileID)
    for i, mount in ipairs(targets) do
        local key = tostring(mount.id)
        if key == source then sourceIndex = i end
        if key == anchor then anchorIndex = i end
    end
    if not sourceIndex or not anchorIndex or sourceIndex == anchorIndex + (after and 1 or -1) then return false end

    local order, seen = {}, {}
    local function append(key)
        if key ~= source and db.plan[key] and not seen[key] then
            order[#order + 1], seen[key] = key, true
        end
    end
    -- Keep ordered targets that are temporarily absent from the catalog.
    if type(db.planOrder) == "table" then
        for _, id in ipairs(db.planOrder) do append(tostring(id)) end
    end
    for _, mount in ipairs(targets) do append(tostring(mount.id)) end
    local unresolved = {}
    for key, enabled in pairs(db.plan) do
        if type(key) == "string" and enabled and key ~= source and not seen[key] then
            unresolved[#unresolved + 1] = key
        end
    end
    table.sort(unresolved)
    for _, key in ipairs(unresolved) do append(key) end
    for i, key in ipairs(order) do
        if key == anchor then
            table.insert(order, i + (after and 1 or 0), source)
            break
        end
    end
    db.planOrder = order
    planChanged()
    return true
end

local function resetTime(frequency, now)
    local method = frequency == "weekly" and "GetSecondsUntilWeeklyReset"
        or frequency == "daily" and "GetSecondsUntilDailyReset"
    local getter = C_DateAndTime and C_DateAndTime[method]
    local ok, seconds
    if getter then ok, seconds = pcall(getter) end
    if not ok then return nil end
    return number(seconds) and seconds > 0 and now + seconds or nil
end

function atlas.lootOpportunityKey(mount, npc, frequency)
    local shared = atlas.sharedLootLockouts and atlas.sharedLootLockouts[mount.id]
    if shared then return "npc:" .. shared .. ":" .. frequency end
    for _, group in ipairs(atlas.lootOpportunityGroups and atlas.lootOpportunityGroups[mount.id] or {}) do
        local found, first = false, nil
        for _, member in ipairs(group) do
            if number(member) and member > 0 then
                first = first and math.min(first, member) or member
                if npc == member then found = true end
            end
        end
        if found then return "npc:group:" .. first .. ":" .. frequency end
    end
    return "npc:" .. npc .. ":" .. frequency
end

local function opportunitySource(mount)
    local stages = atlas.attemptStages and atlas.attemptStages[mount.id]
    if not stages then return nil, mount.npcs end
    local reward, item = stages.reward, stages.item
    if item and item.method == "NPC" then return item, item.npcs end
    if reward and not reward.historical then
        if reward.method == "NPC" then return reward, reward.npcs end
        if reward.method == "SPECIAL" and reward.nodes then return reward end
    end
end

-- Tracking writes one mark per eligible NPC, except sources whose daily loot
-- is explicitly shared. Coordinates and duplicate spawn points are not attempts.
local function opportunityGroups(mount, guid)
    -- A raid location alone does not impose a weekly lock on trash drops or
    -- prerequisites. NPC opportunities require reviewed reset metadata.
    if accountLootSources[mount.id] then return end
    local frequency = atlas.lootFrequencies and atlas.lootFrequencies[mount.id]
    if frequency ~= "daily" and frequency ~= "weekly" then return end
    if mount.encounter then return end
    local definition, npcs = opportunitySource(mount)
    local requiredCovenant = definition and (definition.requiredCovenantID or definition.requiresCovenant)
    if definition and definition.method == "SPECIAL" and definition.key then
        return { { key = "stage:" .. definition.key .. ":" .. frequency,
            lootQuestID = definition.lootQuestID, npcs = mount.npcs or {} } }, frequency, nil, requiredCovenant
    end
    if type(npcs) ~= "table" then return end
    local groups, byKey, seenNPC = {}, {}, {}
    for _, npc in ipairs(npcs) do
        local allowed = true
        if atlas.npcSourceFactions and atlas.npcSourceFactions[npc] then
            allowed = atlas.sourceAvailableToCharacter(npc, guid)
            -- Old offline snapshots do not identify the character's faction.
            -- Do not count both alternatives or infer it from a loot flag.
            if allowed == nil then return nil, frequency, true end
        end
        if allowed and number(npc) and npc > 0 and not seenNPC[npc] then
            seenNPC[npc] = true
            local key = atlas.lootOpportunityKey(mount, npc, frequency)
            local group = byKey[key]
            if not group then
                group = { key = key, npcs = {} }
                groups[#groups + 1], byKey[key] = group, group
            end
            group.npcs[#group.npcs + 1] = npc
        end
    end
    if #groups > 0 then return groups, frequency, nil, requiredCovenant end
end

function atlas.planStageOpportunityKey(mount, definition, npc)
    if accountLootSources[mount.id] then return end
    local source = opportunitySource(mount)
    local frequency = atlas.lootFrequencies and atlas.lootFrequencies[mount.id]
    if not source or source.key ~= definition.key or (frequency ~= "daily" and frequency ~= "weekly") then return end
    if definition.method == "SPECIAL" and definition.nodes then return "stage:" .. definition.key .. ":" .. frequency, frequency end
    if definition.method == "NPC" and number(npc) then return atlas.lootOpportunityKey(mount, npc, frequency), frequency end
end

function atlas.lootOpportunityExpires(mount, npc, frequency)
    local attempts = type(MountAtlasDB) == "table" and MountAtlasDB.lastAttempts
    if type(attempts) ~= "table" then return nil end
    local key = atlas.lootOpportunityKey(mount, npc, frequency)
    local expires = attempts[key]
    local groups = opportunityGroups(mount)
    for _, group in ipairs(groups or {}) do
        if group.key == key then
            for _, member in ipairs(group.npcs) do
                local previous = attempts["npc:" .. member .. ":" .. frequency]
                if number(previous) and (not number(expires) or previous > expires) then expires = previous end
            end
        end
    end
    return number(expires) and expires or nil
end

local function savedOpportunity(status, group, frequency, single)
    if type(status) ~= "table" then return end
    if status.frequency == frequency and type(status.opportunities) == "table" then
        local opportunity = status.opportunities[group.key]
        -- The stage key can survive a change to its personal loot quest.
        if type(opportunity) == "table" and (not group.lootQuestID or opportunity.lootQuestID == group.lootQuestID) then
            return opportunity
        end
        return
    end
    -- A legacy attempt without an NPC key is conclusive only for one NPC group.
    if single and (not status.frequency or status.frequency == frequency) and not status.opportunities
        and status.state == "attempt" and not group.key:match("^stage:") then
        return status
    end
end

local function currentOpportunities(mount, now, questCache, previous)
    local groups, frequency, _, requiredCovenant = opportunityGroups(mount)
    if not groups then return end
    local expires = resetTime(frequency, now)
    local attempts = type(MountAtlasDB) == "table" and MountAtlasDB.lastAttempts
    local covenant = requiredCovenant and C_Covenants and C_Covenants.GetActiveCovenantID
        and C_Covenants.GetActiveCovenantID()
    local covenantID = number(covenant) and covenant > 0 and covenant or nil
    local eligible = not requiredCovenant or covenantID == requiredCovenant
    local result = { state = "unknown", updated = now, expires = expires,
        frequency = frequency, covenantID = covenantID, opportunities = {} }
    local completed, available = 0, 0
    local quests = atlas.npcLootQuests and atlas.npcLootQuests[mount.id]
    local questReady = IsLoggedIn and IsLoggedIn() == true and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
    for _, group in ipairs(groups) do
        local value = type(attempts) == "table" and attempts[group.key]
        -- Explicit alias/shared metadata can be added after an older character
        -- already recorded a member under its NPC key. One group still counts once.
        if not group.key:match("^stage:") then
            for _, npc in ipairs(group.npcs) do
                local previous = type(attempts) == "table" and attempts["npc:" .. npc .. ":" .. frequency]
                if number(previous) and (not number(value) or previous > value) then value = previous end
            end
        end
        -- A covenant change can hide a previously observed loot flag.
        local saved = requiredCovenant and savedOpportunity(previous, group, frequency, #groups == 1)
        if type(saved) == "table" and saved.state == "attempt" and number(saved.expires)
            and (not number(value) or saved.expires > value) then
            value = saved.expires
        end
        local used = number(value) and value > now
        local unlocked = false
        if not used and expires and questReady and (group.lootQuestID or type(quests) == "table") then
            local checks = group.lootQuestID and 1 or #group.npcs
            local allKnown, seen = checks > 0, {}
            for index = 1, checks do
                local quest = group.lootQuestID or quests[group.npcs[index]]
                if not number(quest) or quest <= 0 then allKnown = false
                elseif not seen[quest] then
                    seen[quest] = true
                    local sample = questCache and questCache[quest]
                    if not sample then
                        local ok, complete = pcall(C_QuestLog.IsQuestFlaggedCompleted, quest)
                        sample = { valid = ok and readable(complete) and type(complete) == "boolean", complete = complete }
                        if questCache then questCache[quest] = sample end
                    end
                    if not sample.valid then allKnown = false
                    elseif sample.complete then used = true end
                end
            end
            unlocked = allKnown and not used and eligible
        end
        result.opportunities[group.key] = { state = used and "attempt" or unlocked and "available" or "unknown",
            expires = used and number(value) and value > now and value or expires, lootQuestID = group.lootQuestID }
        if used then completed = completed + 1 end
        if unlocked then available = available + 1 end
    end
    result.state = completed == #groups and "attempt" or completed > 0 and "partial"
        or available > 0 and "available" or "unknown"
    return result
end

-- This is a snapshot of loot locks, not a promise that a character satisfies
-- every level, faction, quest, difficulty or summoning requirement.
local function snapshot(mount, now, questCache, planned, previous)
    if atlas.bossLockout then
        local state, expires, difficultyStates = atlas.bossLockout(mount)
        if state then return { state = state, expires = expires, updated = now, difficultyStates = difficultyStates } end
    end
    local opportunities = currentOpportunities(mount, now, questCache, previous)
    if opportunities then return opportunities end
    if planned then return { state = "unknown", updated = now } end
end

-- Source eligibility can change when previously missing journal rows arrive.
-- Character-specific NPC alternatives are still evaluated at capture time.
local snapshotSources, snapshotRevision
local lastLockoutsReady = false
function atlas.capturePlanSnapshot(ready)
    lastLockoutsReady = ready == true
    atlas.refreshBossLockouts(lastLockoutsReady)
    local db, guid = database(), playerGUID()
    local record = guid and type(db.characters) == "table" and db.characters[guid]
    if type(record) ~= "table" then return end
    if awaitingLoginCharacter then atlas.selectPlanCharacter(guid) end
    if type(record.planStatus) ~= "table" then record.planStatus = {} end
    local now, questCache = GetServerTime(), {}
    local planned = {}
    eachPlan(db, function(plan)
        for key, enabled in pairs(plan.plan) do
            if enabled == true and (type(key) == "string" or type(key) == "number") then
                planned[tostring(key)] = true
            end
        end
    end)
    if not snapshotSources or snapshotRevision ~= atlas.journalSourceRevision then
        snapshotSources, snapshotRevision = {}, atlas.journalSourceRevision
        for _, mount in ipairs(atlas.mounts) do
            local frequency = atlas.lootFrequencies and atlas.lootFrequencies[mount.id]
            if not accountLootSources[mount.id] and (frequency == "daily" or frequency == "weekly"
                or (atlas.isBossLockoutSource and atlas.isBossLockoutSource(mount))) then
                snapshotSources[tostring(mount.id)] = mount
            end
        end
    end
    local function capture(key, mount)
        if mount and not accountLootSources[mount.id] then
            local previous = record.planStatus[key]
            local nextStatus = snapshot(mount, now, questCache, planned[key], previous)
            if nextStatus and (nextStatus.opportunities or nextStatus.state ~= "unknown" or type(previous) ~= "table"
                or not number(previous.expires) or previous.expires <= now) then
                record.planStatus[key] = nextStatus
            end
        end
    end
    for key, mount in pairs(snapshotSources) do capture(key, mount) end
    for key in pairs(planned) do
        if not snapshotSources[key] then capture(key, atlas.mountByID(tonumber(key))) end
    end
end

function atlas.planOpportunityProgress(mount, guid)
    local groups, frequency, unknownFaction, requiredCovenant = opportunityGroups(mount, guid)
    if not groups then return nil, unknownFaction end
    local db, current, now = database(), playerGUID(), GetServerTime()
    guid = guid or current
    local record = guid and type(db.characters) == "table" and db.characters[guid]
    local status = type(record) == "table" and type(record.planStatus) == "table" and record.planStatus[tostring(mount.id)]
    -- The current character can be inspected in the catalog without adding a
    -- target to the plan. Offline characters only have their saved snapshots.
    if guid and guid == current and not (atlas.isCharacterSuppressed and atlas.isCharacterSuppressed(guid)) then
        status = currentOpportunities(mount, now, nil, status)
    end
    local eligible = not requiredCovenant or type(status) == "table" and status.covenantID == requiredCovenant
    local result = { frequency = frequency, entries = {}, completedAttempts = 0,
        totalAttempts = #groups, unknownAttempts = 0, availableAttempts = 0,
        stale = false, updated = type(status) == "table" and status.updated or nil }
    for _, group in ipairs(groups) do
        local value = savedOpportunity(status, group, frequency, #groups == 1)
        local state, expires = "unknown", type(value) == "table" and value.expires
        if type(value) == "table" and (value.state == "attempt" or eligible and value.state == "available") then
            if not number(expires) or expires <= now then
                state, result.stale = "stale", true
            else
                state = value.state
                result.expires = result.expires and math.min(result.expires, expires) or expires
            end
        end
        if state == "attempt" then result.completedAttempts = result.completedAttempts + 1
        elseif state == "available" then result.availableAttempts = result.availableAttempts + 1
        else result.unknownAttempts = result.unknownAttempts + 1 end
        result.entries[#result.entries + 1] = { key = group.key, npcs = group.npcs,
            npc = #group.npcs == 1 and group.npcs[1] or nil, state = state, expires = expires }
    end
    return result
end

function atlas.refreshPlanSnapshot()
    atlas.capturePlanSnapshot(lastLockoutsReady)
end

function atlas.planCharacterStatus(mount, guid)
    if accountLootSources[mount.id] then return atlas.accountLootLockout(mount) end
    local db = database()
    local record = type(db.characters) == "table" and db.characters[guid]
    if type(record) == "table" and atlas.lootFrequency(mount) == "repeatable" then return "available" end
    local progress, unknownFaction = atlas.planOpportunityProgress(mount, guid)
    if unknownFaction then return "unknown" end
    if progress then
        local state = progress.completedAttempts == progress.totalAttempts and "attempt"
            or progress.completedAttempts > 0 and "partial"
            or progress.availableAttempts > 0 and "available"
            or progress.stale and "stale" or "unknown"
        return state, progress.updated, progress.expires, progress
    end
    local status = type(record) == "table" and type(record.planStatus) == "table" and record.planStatus[tostring(mount.id)]
    if type(status) ~= "table" then return "unknown" end
    if status.state == "unknown" then return "unknown", status.updated end
    if not number(status.expires) or status.expires <= GetServerTime() then return "stale", status.updated end
    return status.state, status.updated, status.expires
end

function atlas.planSummary(mount)
    local counts = { done = 0, available = 0, unknown = 0, total = 0,
        completedAttempts = 0, totalAttempts = 0, unknownAttempts = 0, availableAttempts = 0 }
    if accountLootSources[mount.id] then
        counts.total, counts.totalAttempts = 1, 1
        if atlas.accountLootLockout(mount) == "attempt" then counts.done, counts.completedAttempts = 1, 1
        else counts.unknown, counts.unknownAttempts = 1, 1 end
        return counts
    end
    for _, character in ipairs(atlas.accountCharacters()) do
        local state, _, expires, progress = atlas.planCharacterStatus(mount, character.guid)
        if expires and (state == "boss" or state == "attempt" or state == "partial")
            and (not counts.expires or expires < counts.expires) then counts.expires = expires end
        counts.total = counts.total + 1
        if state == "boss" or state == "attempt" then counts.done = counts.done + 1
        elseif state == "available" or (progress and progress.availableAttempts > 0) then counts.available = counts.available + 1
        else counts.unknown = counts.unknown + 1 end
        if progress then
            for _, field in ipairs({ "completedAttempts", "totalAttempts", "unknownAttempts", "availableAttempts" }) do
                counts[field] = counts[field] + progress[field]
            end
        end
    end
    return counts
end
