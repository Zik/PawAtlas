local _, atlas = ...

-- Rarity CE: Core/Detection.lua, Options_Defaults.lua and DB/SharedConstants.lua.
-- Read only the active profile. Different profiles can contain the same history.
-- "attempts" is lifetime history; "lastAttempts" is not an additional counter.
local function number(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if type(value) == "number" and value >= 0 and value < math.huge then return math.floor(value) end
end

local function identifier(value)
    local id = number(value)
    if id and id > 0 and id == value then return id end
end

local function idList(values)
    if type(values) ~= "table" then values = { values } end
    local ids = {}
    for _, value in pairs(values) do
        local id = identifier(tonumber(value))
        if not id then return end
        ids[#ids + 1] = id
    end
    if #ids == 0 then return end
    table.sort(ids)
    return table.concat(ids, ",")
end

local function activeProfile()
    local name = UnitName and UnitName("player")
    local realm = GetRealmName and GetRealmName()
    local key = type(RarityDB) == "table" and type(RarityDB.profileKeys) == "table"
        and name and realm and RarityDB.profileKeys[name .. " - " .. realm]
    local runtime = type(Rarity) == "table" and Rarity.db
    local profile = type(runtime) == "table" and rawget(runtime, "profile")
    if type(profile) == "table" then
        if type(runtime.GetCurrentProfile) == "function" then key = runtime:GetCurrentProfile() end
        return profile, type(key) == "string" and key or nil
    end
    -- Saved data may be visible without the runtime's default tables. Only use
    -- the exact active character profile, never combine every saved profile.
    if type(key) == "string" and type(RarityDB.profiles) == "table" then return RarityDB.profiles[key], key end
end

local function importData()
    local db = type(MountAtlasAccountDB) == "table" and MountAtlasAccountDB.rarityImport
    return type(db) == "table" and db or nil
end

local function importedEntries()
    local db = importData()
    return db and type(db.entries) == "table" and db.entries or nil
end

local function collectionID(definition)
    if not definition or not identifier(definition.required) then return end
    return idList(definition.collectedItems or definition.item)
end

function atlas.rarityImportedCollection(mount)
    local db = importData()
    local entry = db and type(db.collections) == "table" and db.collections[mount.id]
    if type(entry) ~= "table" then return end
    local definitions = atlas.attemptStages and atlas.attemptStages[mount.id]
    local items = definitions and collectionID(definitions.item)
    if items and entry.items == items then return number(entry.quantity), entry.baseline end
end

local function incompatibleCounter(key)
    local id = type(key) == "number" and key or type(key) == "string" and tonumber(key:match("^mount:(%d+)$"))
    local definitions = id and atlas.attemptStages and atlas.attemptStages[id]
    local reward = definitions and definitions.reward
    return reward and (reward.rarityIncompatible or reward.unverifiedEligibility), id, reward
end

local function reviewedEncounter(reward)
    return reward and reward.unverifiedEligibility and reward.rarityEncounterEstimate
        and not reward.historical and not reward.rarityIncompatible
end

function atlas.withImportedAttempts(mount, raw)
    local entries = importedEntries()
    local entry = entries and entries[mount.id]
    local imported = type(entry) == "table" and number(entry.total)
    if not imported then return raw end
    local incompatible, _, reward = incompatibleCounter(mount.id)
    if entry.encounterEstimate then return reviewedEncounter(reward) and imported or raw end
    if incompatible then return raw end
    raw = number(raw)
    -- Keep old history as a floor, then add only newly observed attempts.
    -- First-login API history must never become an incremental attempt.
    local delta = 0
    for _, value in pairs(type(entry.deltaByGUID) == "table" and entry.deltaByGUID or {}) do
        delta = delta + (number(value) or 0)
    end
    return math.max(raw or 0, imported + delta)
end

function atlas.recordImportedStatistic(id, guid, increase)
    if type(guid) ~= "string" or not number(increase) or increase <= 0 or atlas.isCharacterSuppressed(guid) then return end
    local entries = importedEntries()
    local entry = entries and entries[id]
    if type(entry) ~= "table" or not number(entry.total) or incompatibleCounter(id) then return end
    if type(entry.deltaByGUID) ~= "table" then entry.deltaByGUID = {} end
    entry.deltaByGUID[guid] = (number(entry.deltaByGUID[guid]) or 0) + increase
end

function atlas.recordImportedAttempt(mount, guid)
    if atlas.usesKillAPI(mount) then return end
    atlas.recordImportedStatistic(mount.id, guid, 1)
end

function atlas.removeImportedCharacterDelta(guid)
    for _, entry in pairs(importedEntries() or {}) do
        if type(entry) == "table" and type(entry.deltaByGUID) == "table" then entry.deltaByGUID[guid] = nil end
    end
    local db = importData()
    local collections = db and type(db.collections) == "table" and db.collections or {}
    for _, entry in pairs(collections) do
        if type(entry) == "table" and type(entry.baseline) == "table" then entry.baseline[guid] = nil end
    end
end

function atlas.rarityImportSummary()
    local db = importData()
    if not db then return { count = 0, skipped = 0, unattributed = 0 } end
    local count, seen = 0, {}
    for key, entry in pairs(importedEntries() or {}) do
        local incompatible, _, reward = incompatibleCounter(key)
        local estimate = type(entry) == "table" and entry.encounterEstimate
        if (estimate and reviewedEncounter(reward)) or (not estimate and not incompatible) then
            local ids = type(entry) == "table" and entry.mountIDs or nil
            for _, id in ipairs(ids or (tonumber(key) and { tonumber(key) } or {})) do
                if not seen[id] then seen[id] = true; count = count + 1 end
            end
        end
    end
    for id in pairs(type(db.collections) == "table" and db.collections or {}) do
        if not seen[id] and atlas.rarityImportedCollection({ id = id }) then count = count + 1 end
    end
    return { status = db.status, count = db.count or count, skipped = db.skipped or 0,
        unattributed = db.unattributed or 0, time = db.time,
        profile = db.profile, updated = db.updated, unchanged = db.unchanged, skipReasons = db.skipReasons,
        skipEntries = db.skipEntries }
end

local function collectStatistics(snapshots)
    local characters = {}
    for guid, source in pairs(type(snapshots) == "table" and snapshots or {}) do
        if type(guid) == "string" and guid:match("^Player%-") and type(source) == "table"
            and type(source.statistics) == "table" and not atlas.isCharacterSuppressed(guid) then
            local values, samples = {}, {}
            for id, statistics in pairs(atlas.killStatistics) do
                local sum, complete = 0, true
                for _, statID in ipairs(statistics) do
                    local value = number(source.statistics[statID])
                    if value == nil then complete = false
                    else sum = sum + value; samples[statID] = value end
                end
                if complete then values[id] = sum end
            end
            if next(values) then
                characters[guid] = { values = values, statistics = samples,
                    name = source.playerName, realm = source.server, level = number(source.level) }
            end
        end
    end
    return characters
end

local function mergeStatistics(projected, known, stageOwners, imported)
    local characters = MountAtlasAccountDB.characters
    for guid, source in pairs(projected) do
        local record = characters[guid]
        if type(record) ~= "table" then record = {}; characters[guid] = record end
        if type(record.statistics) ~= "table" then record.statistics = {} end
        if type(record.kills) ~= "table" then record.kills = {} end
        for id, value in pairs(source.values) do
            local previous = number(record.statistics[id])
            record.statistics[id] = math.max(previous or 0, value)
            local changed = record.statistics[id] ~= previous
            if known[id] then imported[id] = imported[id] or changed end
            for owner in pairs(stageOwners[id] or {}) do imported[owner] = imported[owner] or changed end
        end
        if not record.name and type(source.name) == "string" then record.name = source.name end
        if not record.realm and type(source.realm) == "string" then record.realm = source.realm end
        if not record.level and source.level and source.level > 0 then record.level = source.level end
        if atlas.seedImportedStatistics then atlas.seedImportedStatistics(guid, source.statistics) end
    end
end

local methods = { NPC = true, BOSS = true, ENCOUNTER = true, ZONE = true }
local function successAttempts(source)
    if source.found ~= true or source.repeatable == true then return end
    local count = number(source.realAttempts)
    return count and count > 0 and count or nil
end

local function needsMultiple(definition)
    local required = type(definition) == "table" and number(definition.required)
    return required and required > 1 or false
end

local function matchesRewardCounter(source, definition)
    if type(definition) ~= "table" or definition.historical or definition.rarityIncompatible
        or definition.unverifiedEligibility or not number(source.itemId)
        or definition.item ~= source.itemId then return false end
    for _, variant in ipairs(definition.variants or { definition }) do
        if not variant.historical and (variant.method or definition.method) == source.method then return true end
    end
    return false
end

local function buildIndex(step)
    if atlas.syncJournal then atlas.syncJournal() end
    local processed, total = 0, #atlas.mounts
    for _ in pairs(atlas.attemptStages or {}) do total = total + 1 end
    local function nextEntry()
        processed = processed + 1
        if step then step(processed, total) end
    end
    if step then step(0, total, true) end
    local bySpell, byItem, known = {}, {}, {}
    for _, mount in ipairs(atlas.mounts) do
        known[mount.id] = mount
        local _, spell = C_MountJournal.GetMountInfoByID(mount.id)
        if number(spell) then bySpell[spell] = mount end
        local loot = atlas.lootItems[mount.id]
        if loot and loot.basis == "drop" and number(loot.item) then byItem[loot.item] = mount end
        nextEntry()
    end
    local stagesByItem, stageOwners, relatedItems = {}, {}, {}
    for id, definitions in pairs(atlas.attemptStages or {}) do
        if known[id] then
            for _, role in ipairs({ "reward", "item" }) do
                local definition = definitions[role]
                if definition and number(definition.item) then relatedItems[definition.item] = true end
                local stage = definition and atlas.stageAttemptDefinition and atlas.stageAttemptDefinition(definition.key)
                if stage and number(stage.item) and stage.method ~= "COLLECTION" then
                    local entries = stagesByItem[stage.item] or {}
                    stagesByItem[stage.item] = entries
                    local entry = entries[stage.key] or { definition = stage, role = role }
                    -- A shared stage uses its first definition. Preserve the
                    -- strictest requirement from every raw owning definition.
                    entry.multiple = entry.multiple or needsMultiple(stage) or needsMultiple(definition)
                    entries[stage.key] = entry
                    local owners = stageOwners[stage.key] or {}
                    stageOwners[stage.key] = owners; owners[id] = true
                end
            end
        end
        nextEntry()
    end
    return known, bySpell, byItem, stagesByItem, stageOwners, relatedItems
end

local function sortedIDs(owners)
    local ids = {}
    for id in pairs(owners) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

local function collectCandidates(sources, known, bySpell, byItem, stagesByItem, stageOwners, relatedItems)
    local candidates, stageCandidates, foundAttempts, collections = {}, {}, {}, {}
    local skipped, skipReasons, skipEntries = 0, {}, {}
    for _, source in ipairs(sources) do
        local incoming = type(source) == "table" and number(source.attempts)
        incoming = incoming and incoming > 0 and incoming or nil
        local success = type(source) == "table" and successAttempts(source)
        if incoming or success then
            local itemID = identifier(source.itemId)
            local mount = bySpell[identifier(source.spellId)] or byItem[itemID]
            if not mount and itemID and C_MountJournal.GetMountFromItem then
                local ok, id = pcall(C_MountJournal.GetMountFromItem, itemID)
                if ok then mount = known[identifier(id)] end
            end
            local loot = mount and atlas.lootItems[mount.id]
            local definitions = mount and atlas.attemptStages and atlas.attemptStages[mount.id]
            -- A cage/egg can use the mount's existing NPC counter. Its displayed
            -- loot basis is not the unit of the verified reward attempt.
            local reward = definitions and definitions.reward
            local award = success and not needsMultiple(reward) and not (reward and reward.unverifiedEligibility)
            local collection = source.type == "MOUNT" and source.method == "COLLECTION"
            local itemSet = collection and definitions and collectionID(definitions.item)
            local encounters = reviewedEncounter(reward) and idList(reward.encounters)
            local estimate = incoming and encounters and source.type == "MOUNT"
                and source.method == "ENCOUNTER" and itemID == reward.item
                and idList(source.encounters) == encounters
            local reason
            if not mount then reason = relatedItems[itemID] and "unit_mismatch" or "unmapped"
            elseif reward and reward.unverifiedEligibility then
                if not estimate then reason = "unverified" end
            elseif incompatibleCounter(mount.id) then reason = "incompatible"
            elseif collection then
                if not incoming or not itemSet or itemSet ~= idList(source.collectedItemId) then reason = "unit_mismatch" end
            elseif mount.journalOnly and not atlas.usesKillAPI(mount) then reason = "untracked"
            elseif source.type ~= "MOUNT" or not methods[source.method] then reason = "unsupported"
            elseif loot and loot.basis ~= "drop" and not matchesRewardCounter(source, reward) then reason = "unit_mismatch"
            elseif not incoming and not award then reason = "multiple_items" end
            local accepted = not reason
            if accepted then
                if collection then
                    -- These counts measure items held, including a historical maximum
                    -- for aggregate collections. A collection completion is not a drop.
                    local previous = collections[mount.id]
                    if not previous or incoming > previous.quantity then
                        collections[mount.id] = { items = itemSet, quantity = incoming }
                    end
                else
                    if incoming then candidates[mount.id] = math.max(candidates[mount.id] or 0, incoming) end
                    if award then
                        foundAttempts["mount:" .. mount.id] = { attempts = success,
                            counterKey = mount.id, owners = { [mount.id] = true } }
                    end
                end
            end
            for key, entry in pairs(stagesByItem[itemID] or {}) do
                if not incompatibleCounter(key) and (source.type == "MOUNT" or (entry.role == "item" and source.type == "ITEM")) then
                    for _, variant in ipairs(entry.definition.variants or { entry.definition }) do
                        if (variant.method or entry.definition.method) == source.method then
                            if incoming then stageCandidates[key] = math.max(stageCandidates[key] or 0, incoming) end
                            if success and not entry.multiple then
                                foundAttempts[key] = { attempts = success, item = itemID,
                                    counterKey = key, owners = stageOwners[key] }
                            end
                            accepted = accepted or incoming ~= nil or (success ~= nil and not entry.multiple)
                            if not accepted then reason = "multiple_items" end
                            break
                        end
                    end
                end
            end
            -- Rarity's items group also contains toys, pets and unrelated loot.
            -- Only report incompatible mount counters or known prerequisites.
            if not accepted and (source.type == "MOUNT" or mount or relatedItems[itemID]) then
                skipped = skipped + 1
                skipReasons[reason] = (skipReasons[reason] or 0) + 1
                if #skipEntries < 50 then
                    skipEntries[#skipEntries + 1] = { name = mount and mount.name
                        or (type(source.name) == "string" and source.name or nil), reason = reason }
                end
            end
        end
    end
    return candidates, stageCandidates, foundAttempts, collections, skipped, skipReasons, skipEntries
end

local function collectSources(groups)
    local sources = {}
    for _, group in ipairs({ "mounts", "items" }) do
        local items = rawget(groups, group)
        for _, value in pairs(type(items) == "table" and items or {}) do sources[#sources + 1] = value end
    end
    return sources
end

local function prepareImport(checkpoint)
    if not activeProfile() then return end
    local known, bySpell, byItem, stagesByItem, stageOwners, relatedItems = buildIndex(checkpoint)
    -- Capture the current profile after the last yield. Neither a profile
    -- switch nor an attempt during indexing can commit a stale snapshot.
    local profile, name = activeProfile()
    local groups = type(profile) == "table" and rawget(profile, "groups")
    if type(groups) ~= "table"
        or (type(rawget(groups, "mounts")) ~= "table" and type(rawget(groups, "items")) ~= "table") then return end
    local candidates, stages, awards, collections, skipped, reasons, details =
        collectCandidates(collectSources(groups), known, bySpell, byItem, stagesByItem, stageOwners, relatedItems)
    return { profile = name, snapshots = collectStatistics(rawget(profile, "accountWideStatistics")),
        known = known, candidates = candidates, stages = stages, stageOwners = stageOwners, awards = awards,
        collections = collections,
        skipped = skipped, skipReasons = reasons, skipEntries = details }
end

local function emptyResult(status)
    return { status = status, count = 0, updated = 0, unchanged = 0, skipped = 0,
        unattributed = 0, skipReasons = {}, skipEntries = {} }
end

local function commitImport(plan)
    if not plan then return emptyResult("unavailable") end
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    if type(MountAtlasAccountDB.characters) ~= "table" then MountAtlasAccountDB.characters = {} end
    local db = MountAtlasAccountDB.rarityImport
    if type(db) ~= "table" then db = {} end
    local entries = type(db.entries) == "table" and db.entries or {}
    local collections = type(db.collections) == "table" and db.collections or {}
    local imported, replacements, unattributed = {}, {}, 0

    -- Apply without yielding. The imported floor must include genuine attempts
    -- recorded since the previous import, including during index preparation.
    mergeStatistics(plan.snapshots, plan.known, plan.stageOwners, imported)
    for id, incoming in pairs(plan.candidates) do
        local mount = plan.known[id]
        local _, _, reward = incompatibleCounter(id)
        local estimate = reviewedEncounter(reward)
        local raw = not estimate and atlas.rawKills(mount) or nil
        local previous = atlas.withImportedAttempts(mount, raw)
        local total = math.max(incoming, previous or 0)
        replacements[id] = { total = total, deltaByGUID = {}, source = incoming, encounterEstimate = estimate or nil }
        if atlas.usesKillAPI(mount) and total > (raw or 0) then unattributed = unattributed + 1 end
        imported[id] = imported[id] or previous ~= total
    end
    for id, incoming in pairs(plan.collections) do
        local mount = plan.known[id]
        local previous, baseline = atlas.rarityImportedCollection(mount)
        local _, delta, current = atlas.rawItemCollection(mount, baseline, true)
        -- Rarity's latest bag snapshot may already contain our new receipts.
        -- Rebase only when it raises the existing imported floor plus receipts.
        local changed = not previous or incoming.quantity > previous + delta
        if changed then
            collections[id] = { items = incoming.items, quantity = incoming.quantity, baseline = current }
        end
        imported[id] = imported[id] or changed
    end
    for key, incoming in pairs(plan.stages) do
        local raw = atlas.rawStageAttempts(key)
        local previous = atlas.withImportedAttempts({ id = key }, raw)
        local total = math.max(incoming, previous or 0)
        local ids = sortedIDs(plan.stageOwners[key])
        replacements[key] = { total = total, deltaByGUID = {}, source = incoming, mountIDs = ids }
        for _, id in ipairs(ids) do imported[id] = imported[id] or previous ~= total end
    end
    for key, found in pairs(plan.awards) do
        local previous = atlas.acquisitionAttempts and atlas.acquisitionAttempts(key)
        local saved = atlas.rememberAcquisition and atlas.rememberAcquisition(key, found.attempts, found.item)
        local added = type(saved) == "table" and not previous
        if added then saved.source = "rarity" end
        local ids = sortedIDs(found.owners)
        for _, id in ipairs(ids) do imported[id] = imported[id] or added end
        -- A confirmed award can survive a reset of Rarity's lifetime counter.
        -- Retain it in the summary without inventing a lifetime attempt total.
        if not entries[found.counterKey] and not replacements[found.counterKey] then
            replacements[found.counterKey] = { acquisitionOnly = true, mountIDs = ids }
        end
    end

    local result = emptyResult("empty")
    for _, changed in pairs(imported) do
        if changed then result.updated = result.updated + 1
        else result.unchanged = result.unchanged + 1 end
    end
    result.count = result.updated + result.unchanged
    if result.count > 0 then result.status = "imported" end
    result.profile, result.time = plan.profile, GetServerTime()
    result.skipped, result.unattributed = plan.skipped, unattributed
    result.skipReasons, result.skipEntries = plan.skipReasons, plan.skipEntries
    for key, entry in pairs(replacements) do entries[key] = entry end
    db.entries, db.collections = entries, collections
    db.time, db.profile, db.skipped, db.unattributed = result.time, result.profile, result.skipped, unattributed
    db.updated, db.unchanged = result.updated, result.unchanged
    db.status, db.count = result.status, result.count
    db.skipReasons, db.skipEntries = result.skipReasons, result.skipEntries
    MountAtlasAccountDB.rarityImport = db
    return result
end

local function refreshImportViews()
    if atlas.refreshDetails then atlas.refreshDetails() end
    if atlas.refreshAccountSettings then atlas.refreshAccountSettings() end
end

local function importRarity(checkpoint)
    return commitImport(prepareImport(checkpoint))
end

-- Keep the synchronous entry point for callers that need the result directly.
function atlas.importRarity()
    local result = importRarity()
    if result.status ~= "unavailable" then refreshImportViews() end
    return result
end

local importState
function atlas.rarityImportProgress() return importState end

function atlas.cancelRarityImport()
    if importState then importState.running = false end
    importState = nil
end

function atlas.clearRarityImport()
    atlas.cancelRarityImport()
    if type(MountAtlasAccountDB) == "table" then
        local entries = importedEntries()
        local acquisitions = MountAtlasAccountDB.acquisitionAttempts
        for key, record in pairs(type(acquisitions) == "table" and acquisitions or {}) do
            if type(record) == "table" then
                if record.source == "rarity" then acquisitions[key] = nil
                elseif not record.source and entries then
                    local incompatible, id = incompatibleCounter(key)
                    -- Keep the original record without resurfacing a potentially mixed count.
                    if incompatible and (entries[key] or entries[id]) then record.source = "unverified" end
                end
            end
        end
        MountAtlasAccountDB.rarityImport = nil
    end
    -- Import deltas also live in the normal character counters. Keep those,
    -- and API snapshots whose history cannot be separated from native kills.
    refreshImportViews()
    return true
end

function atlas.startRarityImport(onProgress)
    if importState and importState.running then return false end
    local state = { running = true, processed = 0, total = 0 }
    importState = state
    local operations = 0
    local worker = coroutine.create(function()
        return importRarity(function(processed, total, force)
            state.processed, state.total = processed, total
            operations = operations + 1
            if force or operations >= 64 then
                operations = 0
                coroutine.yield()
            end
        end)
    end)
    local function notify()
        if onProgress then
            local ok, err = pcall(onProgress, state)
            if not ok then state.callbackError = err end
        end
    end
    local function resume()
        if importState ~= state or not state.running then return end
        local ok, result = coroutine.resume(worker)
        if not ok then
            state.running = false
            state.error = result
            state.result = emptyResult("error")
        elseif coroutine.status(worker) == "dead" then
            state.running, state.result = false, result
        end
        notify()
        if importState ~= state then return end
        if state.running then C_Timer.After(0, resume)
        elseif ok and state.result.status ~= "unavailable" then refreshImportViews() end
    end
    resume()
    return true
end
