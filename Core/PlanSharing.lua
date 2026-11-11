local _, atlas = ...
local serializer = LibStub("AceSerializer-3.0")
local formatTag, formatVersion = "PawAtlasPlan", 1
local maxBytes, maxTargets, maxName = 32768, 500, 48

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function cleanName(value)
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

local function parse(text)
    if not readable(text) or type(text) ~= "string" then return nil, "format" end
    if #text > maxBytes then return nil, "size" end
    local first = text:find("%S")
    if not first then return nil, "format" end
    local last = #text - text:reverse():find("%S") + 1
    text = text:sub(first, last)
    -- Exactly four scalar fields. AceSerializer's general decoder recurses
    -- into tables and accepts trailing data, neither of which this format uses.
    local tag, version = text:match("^%^1%^S([^%^]*)%^N([^%^]*)%^S[^%^]*%^S[^%^]*%^%^$")
    if tag ~= formatTag or text:find("[%c ]") then return nil, "format" end
    if version ~= tostring(formatVersion) then return nil, "version" end
    local ok, _, _, name, csv = serializer:Deserialize(text)
    if not ok or serializer:Serialize(formatTag, formatVersion, name, csv) ~= text then
        return nil, "format"
    end
    name = cleanName(name)
    if not name then return nil, "name" end
    local ids = {}
    if csv ~= "" then
        for token in (csv .. ","):gmatch("([^,]*),") do
            if #ids >= maxTargets then return nil, "targets_limit" end
            if #token > 10 or not token:match("^[1-9]%d*$") then return nil, "id" end
            local id = tonumber(token)
            if id > 2147483647 then return nil, "id" end
            ids[#ids + 1] = id
        end
    end
    return { ids = ids, name = name }
end

function atlas.exportPlan(profileID)
    local ids, name = atlas.planShareData(profileID)
    if not ids then return nil, name end
    if #ids > maxTargets then return nil, "targets_limit" end
    name = (not profileID or profileID == "personal") and "" or cleanName(name)
    if not name then return nil, "name" end
    return serializer:Serialize(formatTag, formatVersion, name, table.concat(ids, ","))
end

function atlas.previewPlanImport(text)
    local payload, err = parse(text)
    if not payload then return nil, err end
    local result = { ids = {}, names = {}, collected = 0, skipped = 0, name = payload.name }
    if #payload.ids == 0 then return result end

    local journal = C_MountJournal
    if not journal or not journal.GetMountIDs or not journal.GetMountInfoByID then return nil, "journal" end
    local ok, mountIDs = pcall(journal.GetMountIDs)
    if not ok or not readable(mountIDs) or type(mountIDs) ~= "table"
        or (canaccesstable and not canaccesstable(mountIDs)) or #mountIDs == 0 then return nil, "journal" end
    local known, seen = {}, {}
    for _, id in ipairs(mountIDs) do if readable(id) and type(id) == "number" then known[id] = true end end
    if not next(known) then return nil, "journal" end
    for _, id in ipairs(payload.ids) do
        if not known[id] or seen[id] then
            result.skipped = result.skipped + 1
        else
            local loaded, name, spell, _, _, _, _, _, _, _, _, collected = pcall(journal.GetMountInfoByID, id)
            if not loaded or not readable(name) or type(name) ~= "string" or name == ""
                or not readable(spell) or type(spell) ~= "number"
                or not readable(collected) or type(collected) ~= "boolean" then return nil, "journal" end
            local legacy = not collected and atlas.legacySourceDetails and atlas.legacySourceDetails({ id = id, spell = spell })
            if atlas.isExcludedJournalMount(id, name, spell, collected) or (legacy and legacy.state == "unavailable") then
                result.skipped = result.skipped + 1
            elseif collected then
                result.collected = result.collected + 1
            else
                local index = #result.ids + 1
                result.ids[index], result.names[index] = id, name
            end
        end
        seen[id] = true
    end
    return result
end

function atlas.createPlan(name)
    name = cleanName(name)
    if not name or name == "" then return nil, "name" end
    return atlas.addImportedPlan(name, {})
end

function atlas.importPlan(text, name)
    local preview, err = atlas.previewPlanImport(text)
    if not preview then return nil, err end
    if #preview.ids == 0 then return nil, "empty" end
    if name == nil then name = "" end
    name = cleanName(name)
    if not name then return nil, "name" end
    if name == "" then name = preview.name end
    if name == "" then return nil, "name" end
    local id, saveError = atlas.addImportedPlan(name, preview.ids)
    if not id then return nil, saveError end
    return id, #preview.ids
end
