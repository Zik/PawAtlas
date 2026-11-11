local _, atlas = ...

local prefix = "PawAtlasColl1"
local linkType = "pawatlascollection"
local shareDuration, requestTimeout = 600, 12
local chunkSize, maxMountID = 200, 16384
local maxSnapshotSize = math.ceil(maxMountID / 6)
local maxChunks = math.ceil(maxSnapshotSize / chunkSize)
local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local scopes = {
    CHAT_MSG_WHISPER = "whisper",
    CHAT_MSG_BN_WHISPER = "bnwhisper",
    CHAT_MSG_PARTY = "party", CHAT_MSG_PARTY_LEADER = "party",
    CHAT_MSG_RAID = "raid", CHAT_MSG_RAID_LEADER = "raid",
    CHAT_MSG_GUILD = "guild",
    CHAT_MSG_SAY = "public", CHAT_MSG_YELL = "public", CHAT_MSG_CHANNEL = "public",
}
local draft, published, incoming, outgoing
local sequence = 0
local bnRoutes = {}

local channels = { WHISPER = "whisper", BN_WHISPER = "bnwhisper", PARTY = "party", RAID = "raid", GUILD = "guild",
    SAY = "public", YELL = "public", CHANNEL = "public" }

local function readable(value)
    return not (issecretvalue and issecretvalue(value))
end

local function identity(value, realm)
    if not readable(value) or type(value) ~= "string" or #value > 128 then return end
    local name, qualified = value:match("^([^-]+)%-(.+)$")
    name = name or value
    realm = qualified or realm
    if not readable(realm) then return end
    if not realm or realm == "" then realm = GetNormalizedRealmName and GetNormalizedRealmName() end
    if #name > 48 or not name:match("^[%a\128-\255]+$") then return end
    if not readable(realm) or type(realm) ~= "string" or #realm > 79
        or not realm:match("^[%w\128-\255'%-]+$") then return end
    return name .. "-" .. realm, name
end

local function playerIdentity()
    if UnitFullName then return identity(UnitFullName("player")) end
end

local function sameIdentity(first, second)
    if not first or not second then return false end
    if strcmputf8i then return strcmputf8i(first, second) == 0 end
    return first:lower() == second:lower()
end

local function validID(value)
    return readable(value) and type(value) == "number" and value > 0
        and value < 2 ^ 53 and value == math.floor(value)
end

local function bnGameOwner(info)
    if type(info) ~= "table" or not readable(info.isOnline) or info.isOnline ~= true
        or not readable(info.clientProgram) or info.clientProgram ~= BNET_CLIENT_WOW
        or not readable(info.wowProjectID) or info.wowProjectID ~= WOW_PROJECT_ID
        or not validID(info.gameAccountID) or not readable(info.realmName)
        or type(info.realmName) ~= "string" or info.realmName == "" then return end
    return identity(info.characterName, (info.realmName:gsub("%s", "")))
end

-- Chat whispers identify a Battle.net account; addon data addresses a game account.
-- Resolve only that friend's online Retail sessions, never a display name or BattleTag.
local function bnGames(accountID)
    if not validID(accountID) or not C_BattleNet or not C_BattleNet.SendGameData
        or not C_BattleNet.GetFriendAccountInfo or not C_BattleNet.GetFriendNumGameAccounts
        or not C_BattleNet.GetFriendGameAccountInfo or not BNGetNumFriends
        or not BNET_CLIENT_WOW or not WOW_PROJECT_ID then return end
    local count = BNGetNumFriends()
    if not readable(count) or type(count) ~= "number" then return end
    for index = 1, math.min(count, 1000) do
        local account = C_BattleNet.GetFriendAccountInfo(index)
        if account and readable(account.bnetAccountID) and account.bnetAccountID == accountID then
            local games, total = {}, C_BattleNet.GetFriendNumGameAccounts(index)
            if not readable(total) or type(total) ~= "number" then return end
            for slot = 1, math.min(total, 100) do
                local info = C_BattleNet.GetFriendGameAccountInfo(index, slot)
                local owner = bnGameOwner(info)
                if owner then games[("bn:%.0f"):format(info.gameAccountID)] = owner end
            end
            return next(games) and games or nil
        end
    end
end

local function findMarker(message, name)
    if not readable(message) or type(message) ~= "string" or #message > 1024 then return end
    local marker = "[PawAtlas-" .. name .. "]"
    local first, last = message:find(marker, 1, true)
    if not first then return end
    -- Ignore markers inside the display text of other chat hyperlinks.
    for start, after in message:gmatch("()|H[^|]-|h.-|h()") do
        if first < start then break end
        if first < after then
            first, last = message:find(marker, after, true)
            if not first then return end
        end
    end
    return first, last
end

local function chatAccessible()
    if not C_ChatInfo or not C_ChatInfo.InChatMessagingLockdown then return false end
    local locked = C_ChatInfo.InChatMessagingLockdown()
    return readable(locked) and locked == false
end

local function canSend()
    -- SendAddonMessage reports whether the addon transport accepts this send.
    -- The outgoing chat restriction is not a transport capability check.
    return chatAccessible() and type(C_ChatInfo.SendAddonMessage) == "function"
end

local function send(owner, text)
    if not canSend() then return false end
    local gameID = owner:match("^bn:(%d+)$")
    local result
    if gameID then
        if not C_BattleNet or not C_BattleNet.SendGameData then return false end
        result = C_BattleNet.SendGameData(tonumber(gameID), prefix, text)
    else
        result = C_ChatInfo.SendAddonMessage(prefix, text, "WHISPER", owner)
    end
    return readable(result) and result == Enum.SendAddonMessageResult.Success
end

local function encodeSnapshot()
    local collection = atlas.collection and atlas.collection.byID
    if not collection then return end
    -- Each character carries six consecutive mount IDs, independent of catalog order.
    local cells, last, known = {}, 0, false
    for id, owned in pairs(collection) do
        if type(owned) == "boolean" then known = true end
        if owned == true and type(id) == "number" and id >= 1 and id == math.floor(id) then
            if id > maxMountID then return end
            local index = math.floor((id - 1) / 6) + 1
            cells[index] = (cells[index] or 0) + 2 ^ ((id - 1) % 6)
            last = math.max(last, index)
        end
    end
    if not known then return end
    local encoded = {}
    for index = 1, last do
        local value = (cells[index] or 0) + 1
        encoded[index] = alphabet:sub(value, value)
    end
    return table.concat(encoded)
end

local function decodeSnapshot(owner, encoded)
    if #encoded > maxSnapshotSize then return end
    local collected, count = {}, 0
    for index = 1, #encoded do
        local position = alphabet:find(encoded:sub(index, index), 1, true)
        if not position then return end
        local value = position - 1
        for bit = 1, 6 do
            if value % 2 == 1 then
                local id = (index - 1) * 6 + bit
                if id > maxMountID then return end
                collected[id], count = true, count + 1
            end
            value = math.floor(value / 2)
        end
    end
    return { owner = owner, collected = collected, count = count }
end

local function finish(request, snapshot)
    if incoming ~= request then return end
    incoming = nil
    request.callback(snapshot)
end

local function audience(scope, target)
    if scope == "whisper" then return target and { [target] = true } end
    if scope == "bnwhisper" then return bnGames(target) end
    if scope == "public" then return {} end
    local members = {}
    if scope == "guild" then
        if not IsInGuild or not GetNumGuildMembers or not GetGuildRosterInfo then return end
        local inGuild = IsInGuild()
        if not readable(inGuild) or inGuild ~= true then return end
        local count = GetNumGuildMembers()
        if not readable(count) or type(count) ~= "number" or count < 1 then return end
        for index = 1, math.min(count, 1000) do
            local fullName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(index)
            local owner = identity(fullName)
            if owner and readable(online) and online == true then members[owner] = true end
        end
    else
        if not UnitFullName or not GetNumGroupMembers or not IsInRaid then return end
        local raid, count = IsInRaid(), GetNumGroupMembers()
        if not readable(raid) or (scope == "raid" and not raid) or not readable(count) or type(count) ~= "number"
            or count < 2 then return end
        local subgroup
        if raid and scope == "party" then
            if not GetRaidRosterInfo then return end
            for index = 1, math.min(count, 40) do
                local _, _, group = GetRaidRosterInfo(index)
                local owner = identity(UnitFullName("raid" .. index))
                if sameIdentity(owner, playerIdentity()) and readable(group) then subgroup = group; break end
            end
            if type(subgroup) ~= "number" then return end
        end
        local unit = raid and "raid" or "party"
        for index = 1, raid and 40 or 4 do
            local owner = identity(UnitFullName(unit .. index))
            if subgroup then
                local _, _, group = GetRaidRosterInfo(index)
                if not readable(group) or group ~= subgroup then owner = nil end
            end
            if owner then members[owner] = true end
        end
    end
    members[playerIdentity() or ""] = nil
    return next(members) and members or nil
end

local function reply(owner, nonce)
    local offer = published
    local now = GetTime()
    if outgoing or not offer or now >= offer.expires
        or (not offer.public and not offer.audience[owner]) or not canSend() then return end
    local previous = offer.requests[owner]
    if previous and (previous.nonce == nonce or now < previous.retryAt) then return end
    local data = encodeSnapshot()
    if not data then return end
    offer.requests[owner] = { nonce = nonce, retryAt = now + 5 }
    local transfer = { index = 1, count = math.max(1, math.ceil(#data / chunkSize)) }
    outgoing = transfer
    local function nextChunk()
        if outgoing ~= transfer then return end
        if published ~= offer or GetTime() >= offer.expires then
            outgoing = nil
            return
        end
        local index = transfer.index
        local chunk = data:sub((index - 1) * chunkSize + 1, index * chunkSize)
        local message = ("D:%s:%d:%d:%s"):format(nonce, index, transfer.count, chunk)
        if not send(owner, message) or index == transfer.count then
            outgoing = nil
            return
        end
        transfer.index = index + 1
        C_Timer.After(0.3, nextChunk)
    end
    nextChunk()
end

local function receive(message, sender, battleNet)
    if not chatAccessible() or not readable(message) or type(message) ~= "string" or #message > 255 then return end
    local owner
    if battleNet then
        if validID(sender) then owner = ("bn:%.0f"):format(sender) end
    else
        owner = identity(sender)
    end
    if not owner or owner == playerIdentity() then return end
    local nonce = message:match("^Q:(%d+)$")
    if nonce then
        if #nonce <= 22 then reply(owner, nonce) end
        return
    end
    local request = incoming
    if not request or request.peer ~= owner then return end
    local token, index, total, data = message:match("^D:(%d+):(%d%d?):(%d%d?):([%w_-]*)$")
    if token ~= request.nonce then return end
    index, total = tonumber(index), tonumber(total)
    if index < 1 or index > total or total > maxChunks or #data > chunkSize
        or (index < total and #data ~= chunkSize) or (total > 1 and #data == 0)
        or (request.total and total ~= request.total) then
        finish(request)
        return
    end
    request.total = total
    local seen = request.chunks[index]
    if seen then
        if seen ~= data then finish(request) end
        return
    end
    request.chunks[index] = data
    request.received = request.received + 1
    if request.received == total then
        finish(request, decodeSnapshot(request.owner, table.concat(request.chunks)))
    end
end

local frame = CreateFrame("Frame")
local registered = false

function atlas.collectionShareChannelSupported(chatType)
    return readable(chatType) and channels[chatType] ~= nil
end

function atlas.shareCollectionLink()
    if not registered or not canSend() then return false end
    local chat, chatType, recipient
    -- WIM keeps its focused editor separate from Blizzard's active chat window.
    -- Never use its last-focused editor: it may belong to another conversation.
    local focused = type(WIM) == "table" and WIM.EditBoxInFocus
    if focused and focused.HasFocus and focused:HasFocus() then
        local window = focused.GetParent and focused:GetParent()
        if not focused.IsVisible or not focused:IsVisible() or not window or window.type ~= "whisper" then return false end
        chat, chatType = focused, window.isBN and "BN_WHISPER" or "WHISPER"
        recipient = window.isBN and window.bn and window.bn.id or window.theUser
    else
        chat = ChatFrameUtil and ChatFrameUtil.GetActiveWindow and ChatFrameUtil.GetActiveWindow()
        if chat and chat.GetChatType then chatType = chat:GetChatType() end
        if (chatType == "WHISPER" or chatType == "BN_WHISPER") and chat.GetTellTarget then
            recipient = chat:GetTellTarget()
            if chatType == "BN_WHISPER" then
                if not readable(recipient) or type(recipient) ~= "string" or not BNet_GetBNetIDAccount then return false end
                recipient = BNet_GetBNetIDAccount(recipient)
            end
        end
    end
    local _, name = playerIdentity()
    if not chat or not name or not chat.Insert or not chat.GetText then return false end
    if not atlas.collectionShareChannelSupported(chatType) then return false end
    local scope = channels[chatType]
    local target = scope == "bnwhisper" and recipient or (scope == "whisper" and identity(recipient))
    if (scope == "whisper" and sameIdentity(target, playerIdentity())) or not audience(scope, target) then return false end
    chat:Insert("[PawAtlas-" .. name .. "]")
    if not findMarker(chat:GetText(), name) then return false end
    draft = { expires = GetTime() + shareDuration, scope = scope, target = target }
    return true
end

function atlas.requestSharedCollection(owner, callback)
    assert(type(callback) == "function", "Expected a collection callback")
    local route = readable(owner) and type(owner) == "string" and bnRoutes[owner]
    local peer
    if route then
        local games = GetTime() < route.expires and bnGames(route.accountID)
        if not games or not sameIdentity(games[route.peer], route.owner) then callback(nil); return false end
        owner, peer = route.owner, route.peer
    else
        owner = identity(owner)
        peer = owner
    end
    if sameIdentity(owner, playerIdentity()) then
        local encoded = encodeSnapshot()
        local snapshot = encoded and decodeSnapshot(playerIdentity(), encoded)
        callback(snapshot)
        return snapshot ~= nil
    end
    if not registered or not owner or not canSend() then
        callback(nil)
        return false
    end
    sequence = sequence + 1
    local nonce = ("%d%06d"):format(GetServerTime(), sequence % 1000000)
    local request = { owner = owner, peer = peer, callback = callback, nonce = nonce, chunks = {}, received = 0 }
    local previous = incoming
    incoming = request
    if previous then previous.callback(nil) end
    if incoming ~= request then return false end
    if not send(peer, "Q:" .. nonce) then
        finish(request)
        return false
    end
    C_Timer.After(requestTimeout, function() finish(request) end)
    return true
end

local function displayLink(_, event, message, sender, ...)
    if not chatAccessible() then return end
    local owner, name
    if event == "CHAT_MSG_WHISPER_INFORM" or event == "CHAT_MSG_BN_WHISPER_INFORM" then
        owner, name = playerIdentity()
    elseif event == "CHAT_MSG_BN_WHISPER" then
        if not readable(message) or type(message) ~= "string" or #message > 1024
            or not message:find("[PawAtlas-", 1, true) then return end
        local accountID = select(11, ...)
        local games = bnGames(accountID)
        local selectedPeer
        for peer, character in pairs(games or {}) do
            local _, characterName = identity(character)
            if findMarker(message, characterName) then
                -- Two sessions with the same character name cannot identify the sender.
                if owner then return end
                owner, name, selectedPeer = character, characterName, peer
            end
        end
        if owner then
            local now = GetTime()
            for token, route in pairs(bnRoutes) do
                if now >= route.expires then bnRoutes[token] = nil end
            end
            local token = owner .. "~BN" .. selectedPeer:sub(4)
            bnRoutes[token] = { owner = owner, peer = selectedPeer, accountID = accountID,
                expires = now + shareDuration }
            owner = token
        end
    else owner, name = identity(sender) end
    if not owner then return end
    local first, last = findMarker(message, name)
    if not first then return end
    local label = message:sub(first, last)
    local link = "|cffd7b46a" .. LinkUtil.FormatLink(linkType, label, owner) .. "|r"
    return false, message:sub(1, first - 1) .. link .. message:sub(last + 1), sender, ...
end

frame:SetScript("OnEvent", function(_, event, message, sender, channel, author, ...)
    if event == "CHAT_MSG_ADDON" or event == "BN_CHAT_MSG_ADDON" then
        if readable(message) and readable(channel) and message == prefix and channel == "WHISPER" then
            receive(sender, author, event == "BN_CHAT_MSG_ADDON")
        end
        return
    end
    if not draft or GetTime() >= draft.expires or not chatAccessible() then return end
    local self, name = playerIdentity()
    if not self or not findMarker(message, name) then return end
    local target = identity(sender)
    local scope = scopes[event]
    if event == "CHAT_MSG_WHISPER_INFORM" then
        scope = "whisper"
    elseif event == "CHAT_MSG_BN_WHISPER_INFORM" then
        scope, target = "bnwhisper", select(9, ...)
        if not validID(target) or target ~= draft.target then return end
    elseif scope == "whisper" or scope == "bnwhisper" or target ~= self then return end
    if scope ~= draft.scope or (scope == "whisper" and not sameIdentity(target, draft.target)) then return end
    draft = nil
    local recipients = audience(scope, target)
    if recipients then
        published = { expires = GetTime() + shareDuration, audience = recipients,
            public = scope == "public", requests = {} }
    end
end)

if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and Enum
    and Enum.RegisterAddonMessagePrefixResult and Enum.SendAddonMessageResult
    and ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter and LinkUtil and LinkUtil.FormatLink
    and LinkUtil.IsLinkHandlerRegistered and LinkUtil.RegisterLinkHandler
    and LinkProcessorResponse and LinkProcessorResponse.Handled
    and C_Timer and C_Timer.After and GetTime and GetServerTime
    and not LinkUtil.IsLinkHandlerRegistered(linkType) then
    local result = C_ChatInfo.RegisterAddonMessagePrefix(prefix)
    if result == Enum.RegisterAddonMessagePrefixResult.Success then
        registered = true
        frame:RegisterEvent("CHAT_MSG_ADDON")
        frame:RegisterEvent("BN_CHAT_MSG_ADDON")
        frame:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
        frame:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", displayLink)
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_BN_WHISPER_INFORM", displayLink)
        for event, scope in pairs(scopes) do
            if scope ~= "whisper" and scope ~= "bnwhisper" then frame:RegisterEvent(event) end
            ChatFrameUtil.AddMessageEventFilter(event, displayLink)
        end
        LinkUtil.RegisterLinkHandler(linkType, function(_, _, data, context)
            if context.button == "LeftButton" and atlas.openSharedCollection then
                local owner = readable(data.options) and type(data.options) == "string"
                    and bnRoutes[data.options] and data.options or identity(data.options)
                if owner then atlas.openSharedCollection(owner) end
            end
            return LinkProcessorResponse.Handled
        end)
    end
end
