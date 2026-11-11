-- Run from PawAtlas: lua5.1 tools/test_trading_post.lua
assert(_VERSION == "Lua 5.1")
local now, events, timers, calls = 100, {}, {}, 0
local ids, offers, frozen, activities = {}, {}, nil, nil
function GetTime() return now end
function CreateFrame()
    return { RegisterEvent = function() end,
        SetScript = function(_, _, callback) events.callback = callback end }
end
C_Timer = { After = function(delay, callback) timers[#timers + 1] = { now + delay, callback } end }
C_PerksProgram = {
    GetAvailableVendorItemIDs = function() calls = calls + 1; return ids end,
    GetVendorItemInfo = function(id) return offers[id] end,
    GetFrozenPerksVendorItemInfo = function() return frozen end,
}
C_PerksActivities = { GetPerksActivitiesInfo = function() return activities end }
C_MountJournal = { GetMountFromItem = function(id) if id == 777 then return 3142 end end }
local atlas = { legacySourceDetails = function(mount) if mount.id == 371 then return { tradingPost = true } end end }
assert(loadfile("Core/Sources.lua"))("PawAtlas", atlas)
local function refresh() events.callback(nil, "PERKS_PROGRAM_DATA_REFRESH") end
local function equal(actual, expected, label)
    assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
equal(atlas.tradingPostOffer({ id = 371 }).unknown, true, "Unloaded known alternate")
equal(atlas.tradingPostOffer({ id = 232 }), nil, "Unrelated mount has no loading notice")
equal(calls, 1, "Repeated hover reuses cache")

ids = { 1 }
offers[1] = { mountID = 2696, price = 500, timeRemaining = 60, purchased = false }
frozen = { mountID = 371, price = 650, timeRemaining = 0, purchased = false }
activities = { secondsRemaining = 90, thresholds = { { itemReward = 777 }, { itemReward = 888 } } }
refresh()
equal(atlas.tradingPostOffer({ id = 2696 }).price, 500, "Live price")
equal(atlas.tradingPostOffer({ id = 2696 }).frozen, false, "Current rotation")
equal(atlas.tradingPostOffer({ id = 371 }).frozen, true, "Frozen outside rotation")
equal(atlas.tradingPostOffer({ id = 371 }).price, 650, "Frozen price")
equal(atlas.tradingPostOffer({ id = 3142 }).bonus, true, "Reward linked by item ID")
equal(atlas.tradingPostOffer({ id = 888 }), nil, "Non-mount reward ignored")
equal(atlas.tradingPostOffer({ id = 532, kind = "Торговая лавка" }), nil, "No invented negative availability")

frozen = { mountID = 125, price = 600, purchased = false }
refresh()
equal(atlas.tradingPostOffer({ id = 371 }), nil, "Old frozen slot removed")
equal(atlas.tradingPostOffer({ id = 125 }).frozen, true, "New frozen slot")
offers[1].purchased = true
refresh()
equal(atlas.tradingPostOffer({ id = 2696 }), nil, "Purchased offer not advertised")

offers[1].purchased = false
offers[1].timeRemaining = 1
refresh()
assert(atlas.tradingPostOffer({ id = 2696 }))
now = now + 2
ids = {}
equal(atlas.tradingPostOffer({ id = 2696 }), nil, "Expired offer disappears without an event")
equal(atlas.tradingPostOffer({ id = 125 }).frozen, true, "Frozen survives rotation expiry")

ids = { 1 }
offers[1].timeRemaining = 0
refresh()
equal(atlas.tradingPostOffer({ id = 2696 }).price, 500, "Fresh zero lifetime means non-expiring, like Blizzard")
offers[1].purchased = true
refresh()
equal(atlas.tradingPostOffer({ id = 2696 }), nil, "Purchase invalidation")
offers[1].purchased = false
events.callback(nil, "PERKS_PROGRAM_REFUND_SUCCESS")
equal(atlas.tradingPostOffer({ id = 2696 }).price, 500, "Refund restores offer")

activities.secondsRemaining = 0
offers[1] = nil
refresh()
equal(atlas.tradingPostOffer({ id = 3142, kind = "Торговая лавка" }).unknown, true, "Incomplete data remains unknown")
C_PerksProgram, C_PerksActivities = nil, nil
refresh()
equal(atlas.tradingPostOffer({ id = 371 }).unknown, true, "Unavailable API does not invent stock")
print("passed: Trading Post stock, freeze, rewards, cache and expiry")
