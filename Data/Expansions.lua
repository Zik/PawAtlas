local _, atlas = ...
-- Newest first; Classic uses the neutral Azeroth panorama.
atlas.expansions = {
    { id = "Midnight", name = "Midnight" },
    { id = "TheWarWithin", name = "The War Within" },
    { id = "Dragonflight", name = "Dragonflight" },
    { id = "Shadowlands", name = "Shadowlands" },
    { id = "BattleForAzeroth", name = "Battle for Azeroth" },
    { id = "Legion", name = "Legion" },
    { id = "WarlordsOfDraenor", name = "Warlords of Draenor" },
    { id = "MistsOfPandaria", name = "Mists of Pandaria" },
    { id = "Cataclysm", name = "Cataclysm" },
    { id = "WrathOfTheLichKing", name = "Wrath of the Lich King" },
    { id = "BurningCrusade", name = "The Burning Crusade" },
    { id = "Classic", name = "World of Warcraft", art = "Azeroth" },
    { id = "Other", name = "Другие источники", art = "Azeroth" },
    -- Event logos from Blizzard Entertainment press kits, resized for the planner.
    -- https://blizzard.gamespress.com/legionremix (WoW_Legion_Remix-2.png)
    { id = "LegionRemix", name = "Legion Remix", art = "Legion", logo = "LegionRemix",
        logoUV = { 82/512, 419/512, 45/256, 207/256 }, logoAspect = 337/162, event = "WoW Remix: Legion" },
    -- https://blizzard.gamespress.com/World-of-Warcraft-Remix-Mists-of-Pandaria-Launch (WOWRemix-MOP_Logo.png)
    { id = "PandariaRemix", name = "Pandaria Remix", art = "MistsOfPandaria", logo = "PandariaRemix",
        logoUV = { 20/512, 472/512, 33/256, 247/256 }, logoAspect = 452/214, event = "WoW Remix: Mists of Pandaria" },
}

local eventCategories = {}
for _, expansion in ipairs(atlas.expansions) do
    if expansion.event then eventCategories[expansion.event] = expansion.id end
end

function atlas.collectionCategory(mount)
    local event = mount.availability and mount.availability.event
    return eventCategories[event] or mount.expansion or "Other"
end
