local addonName, atlas = ...
local aceLocale = LibStub("AceLocale-3.0")

-- Lookups also accept already-localized game text and catalog strings.
aceLocale:NewLocale(addonName, "enUS", true, "raw")
local strings = aceLocale:GetLocale(addonName)
local activeLocale = aceLocale:NewLocale(addonName, "ruRU") and "ruRU" or "enUS"

function atlas.getLocale()
    return activeLocale
end

function atlas.addTranslations(locale, values)
    local entries = aceLocale:NewLocale(addonName, locale, locale == "enUS")
    if not entries then return end
    for key, value in pairs(values) do entries[key] = value end

    -- The existing translation keys are the Russian strings.
    if locale == "enUS" then
        local russian = aceLocale:NewLocale(addonName, "ruRU")
        if russian then
            for key in pairs(values) do russian[key] = true end
        end
    end
end

function atlas.L(key, ...)
    if key == nil then return "" end
    if type(key) ~= "string" then return tostring(key) end
    local text = strings[key] or key
    if select("#", ...) == 0 then return text end
    local ok, formatted = pcall(string.format, text, ...)
    return ok and formatted or text
end
