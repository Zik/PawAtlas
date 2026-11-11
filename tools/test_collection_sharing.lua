-- Run from the repository root: lua5.1 tools/test_collection_sharing.lua
assert(_VERSION == "Lua 5.1", "This test requires Lua 5.1")

local now, timers, packets = 0, {}, {}
local secret = {}

local function advance(seconds)
    local deadline = now + seconds
    while true do
        table.sort(timers, function(a, b) return a.time < b.time end)
        if not timers[1] or timers[1].time > deadline then break end
        local timer = table.remove(timers, 1)
        now = timer.time
        timer.callback()
    end
    now = deadline
end

local function client(name, collection)
    local state = { name = name .. "-Realm", chatType = "WHISPER", enabled = true, draft = "",
        group = {}, guild = {}, bnFriends = {}, filters = {}, handlers = {}, events = {}, owned = collection }
    local atlas = { collection = { byID = collection }, attempts = {}, plans = {} }
    local frame = {
        RegisterEvent = function(_, event) state.events[event] = true end,
        SetScript = function(_, _, callback) state.onEvent = callback end,
    }
    local chat = {
        GetChatType = function() return state.chatType end,
        GetTellTarget = function() return state.target end,
        GetText = function() return state.draft end,
        Insert = function(_, text) state.draft = state.draft .. text end,
    }
    local env = setmetatable({
        CreateFrame = function() return frame end,
        GetTime = function() return now end,
        GetServerTime = function() return math.floor(1000000000 + now) end,
        GetNormalizedRealmName = function() return "Realm" end,
        BNET_CLIENT_WOW = "WoW",
        WOW_PROJECT_ID = 1,
        BNGetNumFriends = function() return #state.bnFriends end,
        BNet_GetBNetIDAccount = function(target) return state.bnTargets and state.bnTargets[target] end,
        C_BattleNet = {
            GetFriendAccountInfo = function(index) return state.bnFriends[index] end,
            GetFriendNumGameAccounts = function(index) return #state.bnFriends[index].games end,
            GetFriendGameAccountInfo = function(index, slot) return state.bnFriends[index].games[slot] end,
            SendGameData = function(target, prefix, text)
                assert(prefix == state.prefix and type(target) == "number" and #text <= 255)
                if state.sendResult then return state.sendResult end
                packets[#packets + 1] = { sender = state.gameID, target = target, text = text, battleNet = true }
                return 0
            end,
        },
        UnitFullName = function(unit)
            if unit == "player" then return name, "Realm" end
            local owner = state.group[tonumber(unit:match("%d+$"))]
            if owner then return owner:match("^([^-]+)%-(.+)$") end
        end,
        IsInRaid = function() return state.raid or state.chatType == "RAID" end,
        GetNumGroupMembers = function() return #state.group + 1 end,
        GetRaidRosterInfo = function(index) return nil, nil, state.subgroups and state.subgroups[index] end,
        IsInGuild = function() return true end,
        GetNumGuildMembers = function() return #state.guild end,
        GetGuildRosterInfo = function(index)
            local entry = state.guild[index]
            return entry[1], nil, nil, nil, nil, nil, nil, nil, entry[2]
        end,
        issecretvalue = function(value) return value == secret end,
        strcmputf8i = function(first, second)
            if first:lower() == second:lower() then return 0 end
            return first:lower() < second:lower() and -1 or 1
        end,
        C_Timer = { After = function(delay, callback)
            timers[#timers + 1] = { time = now + delay, callback = callback }
        end },
        ChatFrameUtil = {
            GetActiveWindow = function() if state.enabled then return chat end end,
            AddMessageEventFilter = function(event, callback) state.filters[event] = callback end,
        },
        LinkUtil = {
            FormatLink = function(kind, label, owner) return ("|H%s:%s|h%s|h"):format(kind, owner, label) end,
            IsLinkHandlerRegistered = function(kind) return state.handlers[kind] ~= nil end,
            RegisterLinkHandler = function(kind, callback) state.handlers[kind] = callback end,
        },
        LinkProcessorResponse = { Handled = 2 },
        Enum = { RegisterAddonMessagePrefixResult = { Success = 0 }, SendAddonMessageResult = { Success = 0 } },
        C_ChatInfo = {
            RegisterAddonMessagePrefix = function(prefix) state.prefix = prefix; return 0 end,
            InChatMessagingLockdown = function() return state.lockdown or false end,
            AreOutgoingAddonChatMessagesRestricted = function() return state.restricted or false end,
            SendAddonMessage = function(prefix, text, channel, target)
                assert(prefix == state.prefix and channel == "WHISPER")
                if state.sendResult then return state.sendResult end
                assert(#text <= 255)
                packets[#packets + 1] = { sender = state.name, target = target, text = text }
                return 0
            end,
        },
    }, { __index = _G })
    setfenv(assert(loadfile("Core/CollectionSharing.lua")), env)("PawAtlas", atlas)
    state.env = env
    state.atlas = atlas
    state.emit = function(event, ...)
        if state.events[event] then state.onEvent(frame, event, ...) end
    end
    state.addon = function(text, sender)
        state.emit("CHAT_MSG_ADDON", state.prefix, text, "WHISPER", sender)
    end
    return state
end

local alice = client("Alice", { [1] = true, [7] = true, [8] = false, [9] = "unknown", [3142] = true })
local bob = client("Bob", { [1] = false })
local eve = client("Eve", { [9] = true })

local ownHidden, ownLink = alice.filters.CHAT_MSG_SAY(nil, "CHAT_MSG_SAY", "[PawAtlas-Alice]", alice.name)
assert(ownHidden == false and ownLink:find("|Hpawatlascollection:Alice-Realm|h", 1, true),
    "the sender's own public marker becomes clickable")
local _, outgoingLink = alice.filters.CHAT_MSG_WHISPER_INFORM(nil, "CHAT_MSG_WHISPER_INFORM",
    "[PawAtlas-Alice]", bob.name)
assert(outgoingLink:find("|Hpawatlascollection:Alice-Realm|h", 1, true),
    "outgoing whispers link the sender's collection, not the recipient's")
local ownSnapshot
alice.lockdown = true
assert(alice.atlas.requestSharedCollection("alice-realm", function(value) ownSnapshot = value end))
assert(ownSnapshot.owner == alice.name and ownSnapshot.count == 3 and ownSnapshot.collected[3142]
    and not ownSnapshot.collected[8] and #packets == 0, "own collection opens locally without chat transport")
ownSnapshot.collected[1] = nil
assert(alice.owned[1] == true, "local viewer receives a separate snapshot")
alice.lockdown = false

assert(alice.atlas.collectionShareChannelSupported("WHISPER"))
assert(alice.atlas.collectionShareChannelSupported("PARTY"))
assert(alice.atlas.collectionShareChannelSupported("CHANNEL"))
assert(not alice.atlas.shareCollectionLink(), "whisper without a target must leave the draft alone")
assert(alice.draft == "")
alice.target = "bob-realm"
alice.enabled = false
assert(not alice.atlas.shareCollectionLink())
alice.enabled = true
alice.lockdown = true
assert(not alice.atlas.shareCollectionLink() and alice.draft == "", "chat lockdown still blocks insertion")
alice.lockdown = false
alice.restricted = true
assert(alice.atlas.shareCollectionLink(), "outgoing chat restrictions must not block a manual chat draft")
alice.draft = ""
-- Leave this true throughout the transfer: the transport result is authoritative.
alice.chatType = "BN_WHISPER"
assert(not alice.atlas.shareCollectionLink())
alice.chatType = "GUILD"
assert(not alice.atlas.shareCollectionLink(), "a guild roster that has not loaded cannot authorize recipients")
alice.chatType = "WHISPER"
assert(alice.atlas.shareCollectionLink() and alice.draft == "[PawAtlas-Alice]" and #packets == 0)

alice.addon("Q:111", bob.name)
assert(#packets == 0, "a draft must not grant access")
alice.emit("CHAT_MSG_WHISPER_INFORM", alice.draft, eve.name)
alice.addon("Q:112", eve.name)
assert(#packets == 0, "publishing to a different target must not reuse the draft")
alice.emit("CHAT_MSG_WHISPER_INFORM", alice.draft, "Bob-OtherRealm")
alice.addon("Q:112", "Bob-OtherRealm")
assert(#packets == 0, "an identically named character on another realm must not reuse the draft")
alice.emit("CHAT_MSG_WHISPER_INFORM", alice.draft, bob.name)
alice.addon("Q:113", eve.name)
alice.addon("Q:113", "Bob-OtherRealm")
assert(#packets == 0, "whisper publication grants access to its recipient only")

local filter = bob.filters.CHAT_MSG_WHISPER
assert(filter(nil, "CHAT_MSG_WHISPER", "[PawAtlas-Alice]", eve.name) == nil)
assert(filter(nil, "CHAT_MSG_WHISPER", secret, alice.name) == nil)
assert(filter(nil, "CHAT_MSG_WHISPER", alice.draft, secret) == nil)
assert(filter(nil, "CHAT_MSG_WHISPER", "|Hitem:3|h[PawAtlas-Alice]|h", alice.name) == nil)
bob.lockdown = true
assert(filter(nil, "CHAT_MSG_WHISPER", alice.draft, alice.name) == nil)
bob.lockdown = false
local hidden, message, sender, otherArg =
    filter(nil, "CHAT_MSG_WHISPER", "Here: " .. alice.draft .. " |Hitem:3|h[Item]|h", alice.name, 17)
assert(hidden == false and sender == alice.name and otherArg == 17)
assert(message:find("|Hpawatlascollection:Alice-Realm|h[PawAtlas-Alice]|h", 1, true))
local attempts, plans = bob.atlas.attempts, bob.atlas.plans
local calls, result = 0, nil
local function callback(snapshot) calls, result = calls + 1, snapshot end
local opened
function bob.atlas.showSharedCatalog(owner)
    opened = { owner = owner }
    return opened
end
function bob.atlas.finishSharedCatalog(request, snapshot)
    assert(request == opened, "the response belongs to the catalog request that opened the view")
    callback(snapshot)
end
setfenv(assert(loadfile("UI/CollectionSharing.lua")), bob.env)("PawAtlas", bob.atlas)
assert(bob.handlers.pawatlascollection(nil, nil, { options = alice.name }, { button = "LeftButton" }) == 2)
assert(opened and opened.owner == alice.name and calls == 0)
assert(#packets == 1 and packets[1].sender == bob.name and packets[1].target == alice.name)
local question = packets[1].text
local nonce = assert(question:match("^Q:(%d+)$"))
bob.addon("D:" .. nonce .. ":1:1:A", eve.name)
bob.addon("D:123:1:1:A", alice.name)
assert(calls == 0, "a wrong sender or nonce must not complete the request")
alice.addon(question, bob.name)
assert(#packets == 2, "only the first chunk should send immediately")
advance(1)
assert(#packets == 4)
for index = 4, 2, -1 do
    assert(packets[index].target == bob.name)
    bob.addon(packets[index].text, alice.name)
    bob.addon(packets[index].text, alice.name)
end
assert(calls == 1 and result.owner == alice.name and result.count == 3)
assert(result.collected[1] and result.collected[7] and result.collected[3142])
assert(not result.collected[8] and not result.collected[9])
assert(bob.atlas.collection.byID == bob.owned and bob.owned[1] == false)
assert(bob.atlas.attempts == attempts and bob.atlas.plans == plans)
alice.addon(question, bob.name)
advance(12)
assert(#packets == 4 and calls == 1, "a repeated nonce and timer cannot resend or reopen")

assert(bob.atlas.requestSharedCollection(alice.name, callback))
nonce = assert(packets[#packets].text:match("^Q:(%d+)$"))
bob.addon("D:" .. nonce .. ":1:99:A", alice.name)
assert(calls == 2 and result == nil)
assert(bob.atlas.requestSharedCollection(alice.name, callback))
advance(12)
assert(calls == 3 and result == nil)
bob.lockdown = true
assert(not bob.atlas.requestSharedCollection(alice.name, callback))
bob.lockdown = false
bob.sendResult = 11
assert(not bob.atlas.requestSharedCollection(alice.name, callback))
bob.sendResult = nil
assert(calls == 5 and result == nil)

alice.draft, alice.chatType, alice.group = "", "PARTY", { bob.name }
assert(alice.atlas.shareCollectionLink())
alice.emit("CHAT_MSG_PARTY", alice.draft, eve.name)
local before = #packets
alice.addon("Q:114", eve.name)
assert(#packets == before, "another player's message cannot authorize publication")
alice.emit("CHAT_MSG_PARTY", alice.draft, alice.name)
alice.group = { eve.name }
alice.addon("Q:115", eve.name)
assert(#packets == before, "new group members cannot reuse an old publication")
alice.addon("Q:116", bob.name)
assert(#packets == before + 1)
advance(601)
before = #packets
alice.addon("Q:117", bob.name)
assert(#packets == before, "publication expires")

alice.draft, alice.chatType, alice.guild = "", "GUILD", { { bob.name, false }, { eve.name, true } }
assert(alice.atlas.shareCollectionLink())
alice.emit("CHAT_MSG_GUILD", alice.draft, alice.name)
alice.addon("Q:118", bob.name)
assert(#packets == before, "offline guild members cannot request the publication")
alice.addon("Q:119", eve.name)
assert(#packets == before + 1)
alice.lockdown = true
advance(1)
assert(#packets == before + 1, "a lockdown aborts a transfer already in progress")

local wim = client("Wim", { [1] = true })
wim.enabled = false
local window = { type = "whisper", theUser = bob.name }
local editor = {
    HasFocus = function() return true end,
    IsVisible = function() return true end,
    GetParent = function() return window end,
    GetText = function() return wim.draft end,
    Insert = function(_, text) wim.draft = wim.draft .. text end,
}
wim.env.WIM = { EditBoxInFocus = editor }
assert(wim.atlas.shareCollectionLink() and wim.draft == "[PawAtlas-Wim]", "WIM whisper works without a group")
before = #packets
wim.addon("Q:501", bob.name)
assert(#packets == before, "WIM insertion does not grant access before sending")
wim.emit("CHAT_MSG_WHISPER_INFORM", wim.draft, eve.name)
wim.addon("Q:502", eve.name)
assert(#packets == before, "another WIM recipient cannot claim the draft")
wim.emit("CHAT_MSG_WHISPER_INFORM", wim.draft, bob.name)
wim.addon("Q:503", bob.name)
assert(#packets == before + 1, "actual WIM recipient can request the collection")
advance(1)
wim.env.WIM = { _EditBoxInFocus = editor }
assert(not wim.atlas.shareCollectionLink(), "stale WIM focus is not an insertion target")
wim.env.WIM.EditBoxInFocus = editor
window.type = "chat"
assert(not wim.atlas.shareCollectionLink(), "non-whisper WIM windows are not mistaken for recipients")
window.type, window.theUser = "whisper", secret
assert(not wim.atlas.shareCollectionLink(), "unreadable WIM recipients are rejected")
window.theUser, wim.draft = "Bob-OtherRealm", ""
assert(wim.atlas.shareCollectionLink(), "WIM accepts a fully qualified cross-realm recipient")
wim.emit("CHAT_MSG_WHISPER_INFORM", wim.draft, "Bob-OtherRealm")
before = #packets
wim.addon("Q:504", bob.name)
assert(#packets == before, "the same name on a different realm does not receive private access")
wim.addon("Q:505", "Bob-OtherRealm")
assert(#packets == before + 1 and packets[#packets].target == "Bob-OtherRealm")
advance(1)

for _, kind in ipairs({ "SAY", "YELL", "CHANNEL" }) do
    local public = client("Public", { [1] = true })
    public.chatType = kind
    assert(public.atlas.shareCollectionLink())
    before = #packets
    public.emit("CHAT_MSG_" .. kind, public.draft, eve.name)
    public.addon("Q:601", eve.name)
    assert(#packets == before, "another player's public marker cannot publish my collection")
    public.emit("CHAT_MSG_" .. kind, public.draft, public.name)
    public.addon("Q:602", eve.name)
    assert(#packets == before + 1, "public publication accepts readers outside groups")
    advance(601)
    before = #packets
    public.addon("Q:603", bob.name)
    assert(#packets == before, "public access expires too")
end

local raid = client("Raider", { [1] = true })
raid.chatType, raid.raid = "PARTY", true
raid.group = { raid.name, bob.name, eve.name }
raid.subgroups = { 2, 2, 3 }
assert(raid.atlas.shareCollectionLink(), "party chat is usable within a raid")
raid.emit("CHAT_MSG_PARTY", raid.draft, raid.name)
before = #packets
raid.addon("Q:701", eve.name)
assert(#packets == before, "party sharing stays inside the raid subgroup")
raid.addon("Q:702", bob.name)
assert(#packets == before + 1, "a raid subgroup member can request the collection")

local bnAlice = client("Bnalice", { [1] = true, [7] = true, [3142] = true })
local bnBob = client("Bnbob", { [8] = true })
bnAlice.gameID, bnBob.gameID = 401, 402
local function friend(accountID, gameID, name, realm)
    return { bnetAccountID = accountID, games = { { gameAccountID = gameID, characterName = name,
        realmName = realm or "Realm", clientProgram = "WoW", wowProjectID = 1, isOnline = true } } }
end
bnAlice.bnFriends, bnBob.bnFriends = { friend(42, 402, "Bnbob") }, { friend(41, 401, "Bnalice") }
local function bnArgs(text, accountID)
    return text, "|KfRecipient|k", "", "", "", "", 0, 0, "", 0, 1, "", accountID
end
local function bnAddon(state, text, gameID)
    state.emit("BN_CHAT_MSG_ADDON", state.prefix, text, "WHISPER", gameID)
end
local bnWindow = { type = "whisper", isBN = true, theUser = "|KfRecipient|k", bn = { id = 42 } }
local bnEditor = {
    HasFocus = function() return true end, IsVisible = function() return true end,
    GetParent = function() return bnWindow end,
    GetText = function() return bnAlice.draft end,
    Insert = function(_, text) bnAlice.draft = bnAlice.draft .. text end,
}
bnAlice.env.WIM, bnAlice.enabled = { EditBoxInFocus = bnEditor }, false
assert(bnAlice.atlas.collectionShareChannelSupported("BN_WHISPER"))
bnWindow.bn.id = nil
assert(not bnAlice.atlas.shareCollectionLink(), "missing BN account ID cannot fall back to a display name")
bnWindow.bn.id = secret
assert(not bnAlice.atlas.shareCollectionLink(), "secret BN account IDs are rejected")
bnWindow.bn.id = 42
bnAlice.bnFriends[1].games[1].wowProjectID = 2
assert(not bnAlice.atlas.shareCollectionLink(), "Classic sessions cannot authorize Retail sharing")
bnAlice.bnFriends[1].games[1].wowProjectID = 1
assert(bnAlice.atlas.shareCollectionLink() and bnAlice.draft == "[PawAtlas-Bnalice]",
    "the focused WIM Battle.net editor accepts the marker")
before = #packets
bnAddon(bnAlice, "Q:801", 402)
assert(#packets == before, "a BN draft cannot expose a collection")
bnAlice.emit("CHAT_MSG_WHISPER_INFORM", bnAlice.draft, bnBob.name)
bnAlice.emit("CHAT_MSG_BN_WHISPER_INFORM", bnArgs(bnAlice.draft, 99))
bnAddon(bnAlice, "Q:802", 402)
assert(#packets == before, "regular whisper and another BN recipient cannot publish the draft")
bnAlice.emit("CHAT_MSG_BN_WHISPER_INFORM", bnArgs(bnAlice.draft, 42))
bnAddon(bnAlice, "Q:803", 499)
bnAlice.addon("Q:803", bnBob.name)
assert(#packets == before, "BN publication authorizes game IDs only from the selected account")

local bnFilter = bnBob.filters.CHAT_MSG_BN_WHISPER
assert(bnFilter(nil, "CHAT_MSG_BN_WHISPER", bnArgs(bnAlice.draft, 99)) == nil)
assert(bnFilter(nil, "CHAT_MSG_BN_WHISPER", bnArgs("[PawAtlas-Eve]", 41)) == nil,
    "a marker must match a character of the sending BN account")
local duplicate = friend(41, 403, "Bnalice", "Other Realm").games[1]
bnBob.bnFriends[1].games[2] = duplicate
assert(bnFilter(nil, "CHAT_MSG_BN_WHISPER", bnArgs(bnAlice.draft, 41)) == nil,
    "identically named characters on multiple sessions are ambiguous")
local bnResult, bnCalls = nil, 0
local function bnCallback(value) bnResult, bnCalls = value, bnCalls + 1 end
assert(not bnBob.atlas.requestSharedCollection("Bnalice-Realm~BN401", bnCallback)
    and #packets == before, "ambiguous or forged links cannot create a BN route")
bnBob.bnFriends[1].games[2] = nil
local _, bnLink, bnSender = bnFilter(nil, "CHAT_MSG_BN_WHISPER", bnArgs(bnAlice.draft, 41))
assert(bnLink:find("|Hpawatlascollection:Bnalice-Realm~BN401|h", 1, true)
    and bnSender == "|KfRecipient|k", "incoming BN links bind the actual game account without changing the chat sender")
local _, bnOwnLink = bnAlice.filters.CHAT_MSG_BN_WHISPER_INFORM(nil, "CHAT_MSG_BN_WHISPER_INFORM",
    bnArgs(bnAlice.draft, 42))
assert(bnOwnLink:find("|Hpawatlascollection:Bnalice-Realm|h", 1, true))
assert(bnAlice.atlas.requestSharedCollection(bnAlice.name, bnCallback) and bnResult.count == 3
    and #packets == before, "own BN link opens locally")
assert(not bnBob.atlas.requestSharedCollection("Bnalice-Realm~BN999", bnCallback) and #packets == before,
    "a manual game ID does not select a recipient")

local bnOpened
function bnBob.atlas.showSharedCatalog(owner) bnOpened = owner; return owner end
function bnBob.atlas.finishSharedCatalog(request, snapshot)
    assert(request == bnOpened)
    bnCallback(snapshot)
end
setfenv(assert(loadfile("UI/CollectionSharing.lua")), bnBob.env)("PawAtlas", bnBob.atlas)
bnBob.handlers.pawatlascollection(nil, nil, { options = "Bnalice-Realm~BN401" }, { button = "LeftButton" })
assert(bnOpened == "Bnalice-Realm~BN401" and packets[#packets].battleNet and packets[#packets].target == 401,
    "clicking a BN link requests the exact game account through the BN transport")
nonce = assert(packets[#packets].text:match("^Q:(%d+)$"))
bnResult, bnCalls = nil, 0
bnBob.addon("D:" .. nonce .. ":1:1:B", bnAlice.name)
bnAddon(bnBob, "D:" .. nonce .. ":1:1:B", 499)
assert(bnCalls == 0, "a character whisper or another game account cannot complete a BN request")
bnAddon(bnAlice, packets[#packets].text, 402)
advance(1)
assert(#packets == before + 4)
for index = #packets, before + 2, -1 do
    assert(packets[index].battleNet and packets[index].target == 402)
    bnAddon(bnBob, packets[index].text, 401)
    bnAddon(bnBob, packets[index].text, 401)
end
assert(bnCalls == 1 and bnResult.owner == bnAlice.name and bnResult.count == 3
    and bnResult.collected[3142] and not bnResult.collected[8], "BN transfer returns a separate complete character-labelled snapshot")
advance(12)
assert(bnCalls == 1, "the BN request timeout cannot complete twice")
before = #packets
bnBob.bnFriends[1].games[1].characterName = "Changed"
assert(not bnBob.atlas.requestSharedCollection("Bnalice-Realm~BN401", bnCallback) and #packets == before,
    "a changed game session invalidates a previously displayed BN route")
bnBob.bnFriends[1].games[1].characterName = "Bnalice"
bnBob.sendResult = 11
assert(not bnBob.atlas.requestSharedCollection("Bnalice-Realm~BN401", bnCallback) and #packets == before,
    "BN transport rejection completes the request without sending data")
bnBob.sendResult = nil

bnAlice.env.WIM, bnAlice.enabled, bnAlice.chatType, bnAlice.draft = nil, true, "BN_WHISPER", ""
bnAlice.target, bnAlice.bnTargets = "|KfRecipient|k", { ["|KfRecipient|k"] = 42 }
assert(bnAlice.atlas.shareCollectionLink(), "Blizzard BN drafts resolve the same account ID as its native chat sender")
advance(601)
before = #packets
bnAddon(bnAlice, "Q:804", 402)
assert(#packets == before and not bnBob.atlas.requestSharedCollection("Bnalice-Realm~BN401", bnCallback),
    "BN publication and displayed routes expire")

print("PASS: collection chat consent, WIM and Battle.net, public channels, raid subgroups, transfer, validation, and expiry")
