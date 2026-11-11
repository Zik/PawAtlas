local _, atlas = ...

-- Live Trading Post offers supplement sources; they never change availability,
-- attempt accounting, or the historical acquisition route.
local perksCache, perksGeneration
perksGeneration = 0
local function perksNumber(value)
    return not (issecretvalue and issecretvalue(value)) and type(value) == "number"
        and value == value and value >= 0 and value < math.huge
end
local function perksMount(item)
    return perksNumber(item) and item > 0 and C_MountJournal and C_MountJournal.GetMountFromItem
        and C_MountJournal.GetMountFromItem(item) or nil
end
local function refreshPerksTooltip()
    local owner = GameTooltip and GameTooltip.GetOwner and GameTooltip:GetOwner()
    if owner and owner.atlasTradingPostSource and owner:IsVisible() then
        local enter = owner:GetScript("OnEnter")
        if enter then enter(owner) end
    end
end
local function invalidatePerks()
    perksGeneration = perksGeneration + 1
    perksCache = nil
    refreshPerksTooltip()
end
local function perksSnapshot()
    local now = GetTime()
    if perksCache and (not perksCache.expires or now < perksCache.expires) then return perksCache end
    local cache = { offers = {}, bonuses = {}, loaded = false }
    local api = C_PerksProgram
    local function offer(info, frozen)
        if type(info) ~= "table" or info.purchased then return end
        local id = perksNumber(info.mountID) and info.mountID > 0 and info.mountID or perksMount(info.itemID)
        if not perksNumber(id) or id <= 0 then return end
        local expires
        if not frozen and not info.doesNotExpire then
            if not perksNumber(info.timeRemaining) then return end
            -- Blizzard treats zero as non-expiring for a current vendor row.
            if info.timeRemaining > 0 then
                expires = now + info.timeRemaining
                cache.expires = math.min(cache.expires or expires, expires)
            end
        end
        cache.offers[id] = { frozen = frozen, price = perksNumber(info.price) and info.price or nil }
    end
    if api and api.GetAvailableVendorItemIDs and api.GetVendorItemInfo then
        local ids = api.GetAvailableVendorItemIDs()
        if type(ids) == "table" and #ids > 0 then
            cache.loaded = true
            for _, id in ipairs(ids) do
                local info = api.GetVendorItemInfo(id)
                if type(info) ~= "table" then cache.loaded = false else offer(info, false) end
            end
        end
    end
    if api and api.GetFrozenPerksVendorItemInfo then offer(api.GetFrozenPerksVendorItemInfo(), true) end
    local activities = C_PerksActivities and C_PerksActivities.GetPerksActivitiesInfo
        and C_PerksActivities.GetPerksActivitiesInfo()
    if type(activities) == "table" and perksNumber(activities.secondsRemaining)
        and activities.secondsRemaining > 0 and type(activities.thresholds) == "table" then
        cache.activitiesLoaded = true
        local expires = now + activities.secondsRemaining
        cache.expires = math.min(cache.expires or expires, expires)
        for _, threshold in ipairs(activities.thresholds or {}) do
            local id = perksMount(threshold.itemReward)
            if perksNumber(id) and id > 0 then cache.bonuses[id] = true end
        end
    end
    perksCache = cache
    if cache.expires and C_Timer and C_Timer.After then
        local generation = perksGeneration
        C_Timer.After(math.max(.1, cache.expires - now), function()
            if generation == perksGeneration and perksCache == cache then invalidatePerks() end
        end)
    end
    return cache
end

function atlas.tradingPostOffer(mount)
    if type(mount) ~= "table" or not perksNumber(mount.id) then return end
    local cache = perksSnapshot()
    local offer = cache.offers[mount.id]
    if offer then return offer end
    if cache.bonuses[mount.id] then return { bonus = true } end
    local legacy = atlas.legacySourceDetails and atlas.legacySourceDetails(mount)
    if (not cache.loaded or not cache.activitiesLoaded)
        and (mount.kind == "Торговая лавка" or (legacy and legacy.tradingPost)) then
        return { unknown = true }
    end
end

do
    local events = CreateFrame("Frame")
    for _, event in ipairs({ "PERKS_PROGRAM_OPEN", "PERKS_PROGRAM_DATA_REFRESH",
        "PERKS_PROGRAM_DATA_SPECIFIC_ITEM_REFRESH", "PERKS_PROGRAM_SET_FROZEN_ITEM",
        "PERKS_PROGRAM_PURCHASE_SUCCESS", "PERKS_PROGRAM_REFUND_SUCCESS", "PERKS_ACTIVITIES_UPDATED" }) do
        events:RegisterEvent(event)
    end
    events:SetScript("OnEvent", invalidatePerks)
end

-- Navigation enriches known sources without changing drop/quest classification
-- or supplying NPCs to the attempt tracker.
function atlas.mountLocations(mount)
    if mount.unavailable or mount.availability then return {} end
    local points = {}
    local extra = atlas.navigationPoints and atlas.navigationPoints[mount.id] or {}
    local identities, allowed = {}, {}
    for _, npc in ipairs(mount.npcs or {}) do allowed[npc] = true end
    local function identity(point)
        return tostring(point.map or "") .. ":" .. (atlas.searchKey and atlas.searchKey(point.boss or "") or point.boss or "")
    end
    for _, known in ipairs(extra) do
        if known.map and known.boss and allowed[known.npc] then
            local key = identity(known)
            if identities[key] == nil then identities[key] = known.npc
            elseif identities[key] ~= known.npc then identities[key] = false end
        end
    end
    local function resolve(point)
        if type(point) ~= "table" then return end
        -- Resolve an omitted ID only from one verified NPC with the exact
        -- source name and map. Nearby coordinates never establish identity.
        if not point.npc and identities[identity(point)] then
            local copy = {}
            for key, value in pairs(point) do copy[key] = value end
            copy.npc = identities[identity(point)]
            point = copy
        end
        return point
    end
    local function equal(a, b)
        if type(a) ~= "table" or type(b) ~= "table" then return a == b end
        for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
        for key in pairs(b) do if a[key] == nil then return false end end
        return true
    end
    local function contextField(key, value)
        if key == "x" or key == "y" or key == "npc" or key == "map"
            or key == "boss" or key == "place" or key == "englishBoss" or key == "englishPlace" then return false end
        -- A citation identifies the data provider, not a separate game source.
        return key ~= "source" or type(value) ~= "string" or not value:match("^https?://")
    end
    local function sameSource(a, b)
        if a.map ~= b.map or a.npc ~= b.npc then return false end
        if not a.npc and identity(a) ~= identity(b) then return false end
        for key, value in pairs(a) do
            if contextField(key, value) and not equal(value, b[key]) then return false end
        end
        for key, value in pairs(b) do
            if contextField(key, value) and not equal(value, a[key]) then return false end
        end
        return true
    end
    local function roundedCoordinate(a, b)
        if a == b then return true end
        if type(a) ~= "number" or type(b) ~= "number" then return false end
        return a == tonumber(string.format("%.3f", b)) or b == tonumber(string.format("%.3f", a))
    end
    local function add(point, reconcile)
        point = resolve(point)
        if not point then return end
        local rounded, ambiguous
        for index, known in ipairs(points) do
            if sameSource(point, known) then
                if point.x == known.x and point.y == known.y then return end
                -- Rarity and navigation providers can encode the same verified
                -- NPC at different precision. Reconcile only a unique match
                -- across feeds, never two spawn points within either feed.
                if reconcile and index <= reconcile and point.npc and point.x and point.y
                    and roundedCoordinate(point.x, known.x) and roundedCoordinate(point.y, known.y) then
                    if rounded then ambiguous = true else rounded = index end
                end
            end
        end
        if rounded and not ambiguous then
            local known = points[rounded]
            for _, candidate in ipairs(extra) do
                candidate = resolve(candidate)
                if sameSource(point, candidate) and (point.x ~= candidate.x or point.y ~= candidate.y)
                    and roundedCoordinate(candidate.x, known.x) and roundedCoordinate(candidate.y, known.y) then
                    ambiguous = true; break
                end
            end
            if not ambiguous then return end
        end
        points[#points + 1] = point
    end
    -- Replace zone-only entries only when that same NPC/map now has a point.
    for _, point in ipairs(mount.locations or {}) do
        local replaced = false
        if not point.x then
            for _, known in ipairs(extra) do
                if known.x and known.y and sameSource(resolve(point), resolve(known)) then replaced = true; break end
            end
        end
        if not replaced then add(point) end
    end
    local originalCount = #points
    for _, point in ipairs(extra) do add(point, originalCount) end
    return points
end

-- Resolve only on verified maps and their floor groups. Never change the
-- journal's selected tier or instance to discover a destination.
local function sourceMaps(mount)
    local info = atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id]
    local sourceMap = mount.sourceMap or (not mount.difficultyLocalOnly and info and info.map)
    local maps, seenMaps = {}, {}
    local function add(map)
        if type(map) == "number" and not seenMaps[map] then seenMaps[map] = true; maps[#maps + 1] = map end
    end
    add(sourceMap)
    for _, map in ipairs(mount.sourceMaps or (not mount.difficultyLocalOnly and info and info.maps) or {}) do add(map) end
    local initial = #maps
    for i = 1, initial do
        local group = C_Map and C_Map.GetMapGroupID and C_Map.GetMapGroupID(maps[i])
        if group and C_Map.GetMapGroupMembersInfo then
            for _, member in ipairs(C_Map.GetMapGroupMembersInfo(group) or {}) do
                add(member.mapID)
            end
        end
    end
    return maps
end

local function sourceDifficulty(mount)
    local info = atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id]
    local difficulties = mount.difficulties or (not mount.difficultyLocalOnly and info and info.difficulties) or {}
    for id, enabled in pairs(difficulties) do
        if enabled and (not mount.journalDifficulty or id < mount.journalDifficulty) then mount.journalDifficulty = id end
    end
end

function atlas.resolveSourceInstance(mount)
    if mount.journalInstance or (mount.sourcePlaceKind ~= "Рейд" and mount.sourcePlaceKind ~= "Подземелье")
        or not C_EncounterJournal or not C_EncounterJournal.GetEncountersOnMap
        or not EJ_GetEncounterInfo or not EJ_GetInstanceInfo then return end
    local instance
    for _, map in ipairs(sourceMaps(mount)) do
        for _, entry in ipairs(C_EncounterJournal.GetEncountersOnMap(map) or {}) do
            local _, _, _, _, _, id = EJ_GetEncounterInfo(entry.encounterID)
            if id then
                local name, _, _, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(id)
                if name and (isRaid == true) == (mount.sourcePlaceKind == "Рейд") then
                    if instance and instance ~= id then return end
                    instance = id
                end
            end
        end
    end
    if instance then mount.journalInstance = instance; sourceDifficulty(mount) end
end

function atlas.resolveSourceEncounter(mount)
    if mount.journalEncounter or not mount.hasSourcePanels or mount.sourceKind ~= "Босс"
        or not C_EncounterJournal or not C_EncounterJournal.GetEncountersOnMap or not EJ_GetEncounterInfo then return end
    local wanted = { [atlas.searchKey(mount.boss)] = true }
    local info = atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id]
    local english = mount.englishBoss or (info and info.englishBoss)
    if english then wanted[atlas.searchKey(english)] = true end
    if atlas.sourceName then wanted[atlas.searchKey(atlas.sourceName(mount.boss, "enUS"))] = true end
    local encounter, instance
    for _, map in ipairs(sourceMaps(mount)) do
        for _, entry in ipairs(C_EncounterJournal.GetEncountersOnMap(map) or {}) do
            local name, _, _, _, _, instanceID = EJ_GetEncounterInfo(entry.encounterID)
            local matches = name and wanted[atlas.searchKey(name)]
            -- A mount can name one creature in a council encounter (Shatug),
            -- while the journal and raid save name the whole encounter.
            -- Use the journal's own creature list on this verified map only.
            if not matches and instanceID and EJ_GetCreatureInfo then
                for index = 1, 9 do -- Blizzard EncounterJournal's creature limit.
                    local creature, creatureName = EJ_GetCreatureInfo(index, entry.encounterID)
                    if not creature then break end
                    if creatureName and wanted[atlas.searchKey(creatureName)] then matches = true; break end
                end
            end
            if name and instanceID and matches then
                if encounter and encounter ~= entry.encounterID then return end
                encounter, instance = entry.encounterID, instanceID
            end
        end
    end
    if not encounter then return end -- Retry later if client data was not ready.
    mount.journalEncounter, mount.journalInstance = encounter, instance
    sourceDifficulty(mount)
end

function atlas.openPlace(mount)
    if mount.unavailable then return atlas.L("Недоступно для получения") end
    if not mount.journalInstance then return end
    if InCombatLockdown() then return atlas.L("Открой путеводитель после боя.") end
    if not EncounterJournal_OpenJournal then C_AddOns.LoadAddOn("Blizzard_EncounterJournal") end
    if not EncounterJournal_OpenJournal then return atlas.L("Путеводитель недоступен.") end
    EncounterJournal_OpenJournal(mount.journalDifficulty or next(mount.difficulties or {}), mount.journalInstance)
    MountAtlasWindow:Hide()
end

function atlas.hasSourceCoordinates(point)
    return point and type(point.map) == "number" and point.map > 0 and point.map % 1 == 0
        and type(point.x) == "number" and point.x >= 0 and point.x <= 1
        and type(point.y) == "number" and point.y >= 0 and point.y <= 1
end

function atlas.hasTomTomWaypoints()
    return TomTom and type(TomTom.AddWaypoint) == "function"
end

function atlas.addSourceWaypoints(points)
    if not atlas.hasTomTomWaypoints() then return 0 end
    local count, seen = 0, {}
    for _, point in ipairs(points) do
        if atlas.hasSourceCoordinates(point) then
            local key = ("%d:%.17g:%.17g"):format(point.map, point.x, point.y)
            if not seen[key] then
                seen[key] = true
                local title = atlas.displayName(point.boss)
                local exists = TomTom.WaypointExists and TomTom:WaypointExists(point.map, point.x, point.y, title)
                if not exists and TomTom:AddWaypoint(point.map, point.x, point.y,
                    { title = title, persistent = false, crazy = false, silent = true }) then
                    count = count + 1
                end
            end
        end
    end
    return count
end

function atlas.openSource(mount, point)
    if mount.unavailable then return atlas.L("Недоступно для получения") end
    if mount.journalEncounter then
        if InCombatLockdown() then return atlas.L("Открой путеводитель после боя.") end
        if not EncounterJournal_OpenJournal then C_AddOns.LoadAddOn("Blizzard_EncounterJournal") end
        if not EncounterJournal_OpenJournal then return atlas.L("Путеводитель недоступен.") end
        EncounterJournal_OpenJournal(mount.journalDifficulty or next(mount.difficulties or {}), mount.journalInstance, mount.journalEncounter)
        MountAtlasWindow:Hide()
        return
    end

    if not atlas.hasSourceCoordinates(point) then return atlas.L("Точная точка неизвестна.") end
    local boss = atlas.displayName(point.boss)
    local destination = ("%s · %.1f, %.1f"):format(boss, point.x * 100, point.y * 100)
    if atlas.hasTomTomWaypoints() then
        local uid = TomTom:AddWaypoint(point.map, point.x, point.y,
            { title = boss, persistent = false, crazy = true })
        if uid then
            -- AddWaypoint reuses an existing waypoint without retargeting its arrow.
            if TomTom.SetCrazyArrow then TomTom:SetCrazyArrow(uid, uid.arrivaldistance, boss) end
            return "TomTom · " .. destination
        end
    end
    if C_Map.CanSetUserWaypointOnMap(point.map)
        and C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(point.map, point.x, point.y)) then
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        return atlas.L("Метка карты · %s", destination)
    end
    return atlas.L("Ориентир · %s · %s", atlas.displayName(point.place), destination)
end
