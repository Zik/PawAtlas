local _, atlas = ...
local loader = CreateFrame("Frame")
local pending

local function activeChat()
    local getter = ChatFrameUtil and ChatFrameUtil.GetActiveWindow or ChatEdit_GetActiveWindow
    return getter and getter()
end

local function insertLink(link)
    if type(link) ~= "string" or link == "" then return false end
    local insert = ChatFrameUtil and ChatFrameUtil.InsertLink or ChatEdit_InsertLink
    local open = ChatFrameUtil and ChatFrameUtil.OpenChat or ChatFrame_OpenChat
    -- InsertLink also targets macros and auction searches. With no active chat,
    -- open a chat draft explicitly, as Blizzard's own LinkItem does.
    if activeChat() and insert and insert(link) then return true end
    if open then open(link); return true end
    return false
end

function atlas.cancelPendingLink(owner)
    if pending and (not owner or pending.owner == owner) then
        pending = nil
        loader:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        loader:SetScript("OnUpdate", nil)
    end
end

local function positiveID(value)
    value = tonumber(value)
    return value and value > 0 and value < math.huge and value == math.floor(value) and value or nil
end

local function itemLink(id)
    if not C_Item or not C_Item.GetItemInfo then return nil end
    return select(2, C_Item.GetItemInfo(id))
end

function atlas.linkItem(itemID, owner)
    atlas.cancelPendingLink()
    local id = positiveID(itemID)
    if not id then return false end
    local link = itemLink(id)
    if link then return insertLink(link) end
    if not C_Item.RequestLoadItemDataByID then return false end
    local chat = activeChat()
    local request = {
        id = id, owner = owner, chat = chat,
        text = chat and chat:GetText(), expires = GetTime() + 5,
    }
    pending = request
    loader:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    loader:SetScript("OnUpdate", function()
        local current = activeChat()
        if GetTime() >= request.expires or (owner and not owner:IsVisible())
            or current ~= chat or (current and current:GetText() ~= request.text)
            or (IsKeyDown and IsKeyDown("ESCAPE")) then
            atlas.cancelPendingLink()
        end
    end)
    C_Timer.After(5, function()
        if pending == request then atlas.cancelPendingLink() end
    end)
    C_Item.RequestLoadItemDataByID(id)
    return true
end

loader:SetScript("OnEvent", function(_, _, id, success)
    local request = pending
    if not request or request.id ~= id then return end
    atlas.cancelPendingLink()
    if not success or GetTime() >= request.expires then return end
    if request.owner and not request.owner:IsVisible() then return end
    local chat = activeChat()
    if chat ~= request.chat or (chat and chat:GetText() ~= request.text) then return end
    insertLink(itemLink(id))
end)

function atlas.linkMount(mount)
    atlas.cancelPendingLink()
    local id = positiveID(type(mount) == "table" and mount.id or mount)
    if not id or not C_MountJournal or not C_Spell or not C_Spell.GetSpellLink then return false end
    local _, spellID = C_MountJournal.GetMountInfoByID(id)
    return spellID and insertLink(C_Spell.GetSpellLink(spellID)) or false
end

function atlas.linkSourceName(view, name, place)
    atlas.cancelPendingLink()
    local link
    if place and view and view.journalInstance and EJ_GetInstanceInfo then
        link = select(8, EJ_GetInstanceInfo(view.journalInstance))
    elseif not place and view and view.journalEncounter and EJ_GetEncounterInfo then
        link = select(5, EJ_GetEncounterInfo(view.journalEncounter))
    end
    -- Vendors and open-world NPCs have no journal chat link. Insert their
    -- visible name rather than fabricating a unit GUID or an unsupported link.
    if type(link) ~= "string" or not link:find("|H", 1, true) then link = name end
    return insertLink(link)
end

function atlas.linkSource(link, owner)
    atlas.cancelPendingLink()
    if type(link) ~= "string" then return false end
    local payload = link:match("|H([^|]+)|h") or link
    local kind, id = payload:match("^(%a+):(%d+)")
    id = positiveID(id)
    if not id then return false end
    if kind == "item" then return atlas.linkItem(id, owner) end
    if kind == "currency" and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
        return insertLink(C_CurrencyInfo.GetCurrencyLink(id))
    end
    if kind == "achievement" and GetAchievementLink then
        return insertLink(GetAchievementLink(id))
    end
    return false
end
