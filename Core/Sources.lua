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
    if atlas.refreshSourceRoutes then atlas.refreshSourceRoutes() end
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
        cache.offers[id] = { frozen = frozen, price = perksNumber(info.price) and info.price or nil, expires = expires }
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
            if perksNumber(id) and id > 0 then cache.bonuses[id] = { bonus = true, expires = expires } end
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
    if cache.bonuses[mount.id] then return cache.bonuses[mount.id] end
    local legacy = atlas.legacySourceDetails and atlas.legacySourceDetails(mount)
    if (not cache.loaded or not cache.activitiesLoaded)
        and (mount.kind == "Торговая лавка" or (legacy and legacy.tradingPost)) then
        return { unknown = true }
    end
end

local sourceCategories = {
    loot = { "Добыча", "Loot", "loot" },
    fishing = { "Рыбалка", "Fishing", "loot" },
    profession = { "Профессия", "Profession", "other" },
    quest = { "Квест", "Quest", "quest" },
    achievement = { "Достижение", "Achievement", "achievement" },
    purchase = { "Покупка", "Vendor", "vendor" },
    pvp = { "PvP", "Kills", "other" },
    event = { "Событие", "Calendar", "other" },
    promotion = { "Акция / код", "Promotion", "other" },
    progress = { "Награда за прогресс", "Progress", "other" },
}

local sourceTypes = {
    ["Рарка"] = { "loot", "Рарка", "Rare" }, ["Босс"] = { "loot", "Босс", "Boss" },
    ["Рейд"] = { "loot", "Рейд", "Raid" }, ["Подземелье"] = { "loot", "Подземелье", "Dungeon" },
    ["Сокровище"] = { "loot", "Сокровище" }, ["Добыча"] = { "loot" },
    ["Исследование"] = { "loot" }, ["Взаимодействие"] = { "loot", "Взаимодействие", "Book" },
    ["Рыбалка"] = { "fishing" }, ["Профессия"] = { "profession" },
    ["Квест"] = { "quest" }, ["Достижение"] = { "achievement" },
    ["Великий подвиг"] = { "achievement", "Великий подвиг" },
    ["Торговец"] = { "purchase", "Торговец" }, ["Магазин"] = { "purchase", "Внутриигровой магазин" },
    ["Торговая лавка"] = { "purchase", "Торговая лавка" },
    ["Чёрный рынок"] = { "purchase", "Чёрный рынок" },
    ["PvP"] = { "pvp" }, ["Событие"] = { "event" },
    ["Акция"] = { "promotion" }, ["Карточная игра"] = { "promotion", "Код TCG" },
    ["Награда за прогресс"] = { "progress" },
}

local function fishingReward(mount)
    local stages = (atlas.attemptStages or {})[mount.id]
    local reward = stages and stages.reward
    if not reward or reward.historical or not reward.item then return false end
    if reward.method ~= "FISHING" then
        local egg = (atlas.guaranteedRewards or {})[mount.id]
        if not egg or egg.method ~= "egg" or egg.rate ~= 1 or egg.item ~= reward.item
            or not egg.reagent or not stages.item or stages.item.method ~= "FISHING"
            or stages.item.item ~= egg.reagent.item then return false end
    end
    for _, item in ipairs((atlas.mountRewardItems or {})[mount.id] or {}) do
        if item.item == reward.item then return true end
    end
    return false
end

local function eventForSource(mount)
    local reminder = (atlas.eventReminderSources or {})[mount.id]
    if reminder and reminder.spell == mount.spell and reminder.holidays then return reminder.holidays[1] end
end

local function questMountReward(mount)
    local reward = (atlas.questMountRewards or {})[mount.id]
    if reward and reward.spell == mount.spell then return reward end
end

function atlas.questAcquisitionChain(mount)
    local chain = (atlas.questAcquisitionChains or {})[mount.id]
    if not chain or chain.spell ~= mount.spell then return end
    if chain.stageTitle then
        local reward = questMountReward(mount)
        for _, quest in ipairs(reward and reward.quests or {}) do
            if quest.id == chain.finalQuest and quest.item == chain.reward then
                for _, npc in ipairs(quest.givers or {}) do
                    if npc == chain.npc then return chain, chain end
                end
            end
        end
        return
    end
    local grant = (atlas.guaranteedRewards or {})[mount.id]
    local stages = (atlas.attemptStages or {})[mount.id]
    if not stages then return end
    local starter = stages.item and stages.item.item == chain.starter and stages.item or stages.reward
    if not starter or starter.item ~= chain.starter then return end
    if grant then
        local reagent = grant.method == "quest" and grant.reagent
        if not reagent or reagent.item ~= chain.starter or reagent.completionQuest ~= chain.unlock
            or grant.item ~= chain.reward then return end
    elseif not chain.condition or not stages.reward or stages.reward.method ~= "SPECIAL" or stages.reward.item ~= chain.reward then
        return
    end
    if chain.toastItem and starter.method == "LOOT_TOAST" then
        for _, item in ipairs(starter.toastItems or {}) do if item == chain.toastItem then return chain, grant or chain end end
    elseif starter.method == "NPC" then
        for _, npc in ipairs(starter.npcs or {}) do if npc == chain.npc then return chain, grant or chain end end
    end
end

local function primaryAcquisitionSource(mount, choice, view)
    return view == mount or not (choice and choice.verifiedDrop) and mount.sourceGroups and #mount.sourceGroups == 1
        and view == mount.sourceGroups[1]
end

-- Only replace the journal's four feature-only entries, and keep the rest
-- of the catalogue (including updated journal sources) on the native path.
function atlas.covenantVariantChoices(mount)
    local entry = (atlas.covenantVariantSources or {})[mount.id]
    if not entry or entry.spell ~= mount.spell then return end
    local pages = atlas.covenantSourcePages(mount)
    if not pages or #pages ~= 4 then return end
    for _, page in ipairs(pages) do
        local feature, covenant = atlas.normalizeSource(page):match("^([^\n]+)\n([^\n]+)$")
        if not feature or not (feature:match("^Особенность ковенанта: ") or feature:match("^Covenant Feature: "))
            or not (covenant:match("^Ковенант: ") or covenant:match("^Covenant: ")) then return end
    end
    local knownItem
    for _, item in ipairs((atlas.mountRewardItems or {})[mount.id] or {}) do
        if item.item == entry.item then knownItem = true; break end
    end
    if not knownItem then return end

    local L, en = atlas.L, atlas.getLocale() == "enUS"
    local covenants = en and { "Kyrian", "Venthyr", "Night Fae", "Necrolord" }
        or { "Кирии", "Вентиры", "Ночной народец", "Некролорды" }
    local function choice(covenant, kind, map, place, lines, vendor)
        local fields = { L("Ковенант") .. ": " .. covenants[covenant] }
        for _, line in ipairs(lines) do fields[#fields + 1] = line end
        local raw = table.concat(fields, "\n")
        if vendor then vendor.conditions = raw end
        return { covenantVariant = covenant, vendor = vendor, category = vendor and "vendor" or "loot",
            compact = not vendor, view = { id = mount.id, spell = mount.spell, kind = kind,
                place = place, sourceMap = map, journalSourceRaw = raw,
                trackingCompatible = false, difficultyLocalOnly = true } }
    end
    local function offer(covenant, condition, feature)
        local data = atlas.covenantVariantVendors[covenant]
        if data.reputation then
            condition = ("%s: %s (%s)"):format(L("Репутация"), atlas.dataName(data.reputation), L("Превознесение"))
        end
        local vendor = { name = atlas.dataName(data), npc = data.npc, map = data.map, x = data.x, y = data.y,
            place = en and data.englishPlace or data.place }
        if data.alternate then
            local alt = data.alternate
            vendor.waypoints = { { npc = vendor.npc, map = vendor.map, x = vendor.x, y = vendor.y, boss = vendor.name,
                place = vendor.place }, { npc = alt.npc, map = alt.map, x = alt.x, y = alt.y, boss = vendor.name,
                place = en and alt.englishPlace or alt.place } }
        end
        local price = ("%s: %d |Hcurrency:1813|h[%s]|h"):format(L("Цена"), data.anima, en and "Reservoir Anima" or "Запасенная анима")
        return choice(covenant, "Торговец", vendor.map, vendor.place, { feature, condition, price }, vendor)
    end
    local path = en and "Path of Ascension" or "Путь Перерождения"
    local kyrian = entry.achievement and offer(1, ("%s: |Hachievement:%d|h[%s]|h"):format(
        L("Достижение"), entry.achievement, atlas.dataName(entry)), path)
        or choice(1, "Добыча", 1707, en and "Elysian Hold" or "Элизийская цитадель", {
            en and "Path of Ascension: defeat Azaruux on Wisdom difficulty."
                or "Путь Перерождения: победи Азаруукса на сложности «Мудрость».",
        })
    local venthyr
    if entry.chests then
        venthyr = choice(2, "Сокровище", 1644, en and "Ember Court" or "Пепельный двор", {
            L("Добыча") .. ": " .. entry.chests[1][en and 3 or 2] .. "; " .. entry.chests[2][en and 3 or 2],
        })
    else
        venthyr = offer(2, nil,
            en and "The Ember Court" or "Пепельный двор")
    end
    local spirit = ("{item:%d:%s}"):format(entry.spirit, en and entry.englishSpiritName or entry.spiritName)
    local grain = en and "{item:176832:Wildseed Root Grain}" or "{item:176832:Зерно дикого корня}"
    local fae = choice(3, "Сокровище", 1662, en and "Queen's Conservatory" or "Королевский зимний сад", {
        L("Добыча") .. ": " .. (en and "Queen's Conservatory Cache" or "Тайник королевского зимнего сада"),
        (en and "Tier 5: plant %s or a higher-quality spirit of the same type and use %s ×4."
            or "5-й уровень: посади %s или духа того же вида покачественнее и используй %s ×4."):format(spirit, grain),
    })
    local necrolord = offer(4, nil,
        en and "Abominable Stitching" or "Фабрика поганищ")
    return { venthyr, fae, kyrian, necrolord }
end

function atlas.questChainForSource(mount, choice)
    if choice.vendor or choice.verifiedDrop or choice.contextOnly or choice.separateSource or choice.grant
        or choice.tradingPost or (choice.category ~= "loot" and choice.category ~= "quest")
        or not primaryAcquisitionSource(mount, choice, choice.view or mount) then return end
    local chain, grant = atlas.questAcquisitionChain(mount)
    if chain and (not chain.stageTitle or choice.category == "quest") then return chain, grant end
end

function atlas.questChainGuaranteedReward(choice)
    local chain, grant = choice and choice.questChain, choice and choice.chainGrant
    if chain and grant and chain.guaranteedReward == true and chain.finalQuest and chain.reward
        and (grant == chain or grant.rate == 1) then return chain end
end

function atlas.questChainTitle(chain, id)
    if id == chain.finalQuest then return atlas.dataName(chain) end
    if chain.prerequisite and id == chain.prerequisite.id then return atlas.dataName(chain.prerequisite) end
    if chain.stageTitle then
        for _, quest in ipairs(chain.quests) do
            if id == quest then return atlas.dataName(chain.stageTitle) end
        end
    end
end

function atlas.questChainProgress(chain, showSteps)
    local quests = chain.quests or { chain.finalQuest }
    local log, complete, total = C_QuestLog, 0, #quests
    local active, nextQuest, finalCompleted
    local states = showSteps and {}
    for _, id in ipairs(quests) do
        local done = log and log.IsQuestFlaggedCompleted and log.IsQuestFlaggedCompleted(id)
        local accepted = log and log.IsOnQuest and log.IsOnQuest(id)
        if issecretvalue and issecretvalue(done) then done = nil end
        if issecretvalue and issecretvalue(accepted) then accepted = nil end
        if chain.stageTitle and id == chain.finalQuest then
            total = total - 1
            finalCompleted = done == true
        elseif done == true then
            complete = complete + 1
        end
        if accepted == true then active = active or id end
        if done == false then nextQuest = nextQuest or id end
        if states then states[id] = done == true and "complete" or accepted == true and "active"
            or done == false and "incomplete" or nil end
    end
    if finalCompleted then complete, active, nextQuest = total, nil, nil end
    return complete, total, active, nextQuest, states, finalCompleted
end

local function merchantHasQuestReward(mount, reward, vendor)
    local item = vendor.items[mount.id]
    if not item then return false end
    for _, quest in ipairs(reward.quests) do
        if quest.item == item then return true end
    end
    return false
end

local function questMerchantOffer(mount, merchant)
    local L, en = atlas.L, atlas.getLocale() == "enUS"
    local offer = merchant.offers and merchant.offers[mount.id] or merchant
    local place = en and merchant.englishPlace or merchant.place
    local name = atlas.dataName(merchant)
    local reputation = en and merchant.englishReputation or merchant.reputation
    local price = L("Цена") .. ": " .. (merchant.gold and ("%d|TInterface\\MoneyFrame\\UI-GoldIcon.blp:0|t"):format(merchant.gold)
        or en and offer.englishPrice or offer.price)
    local conditions = {}
    if offer.renown then
        conditions[#conditions + 1] = L("Фракция") .. ": " .. reputation
        conditions[#conditions + 1] = L("Известность") .. ": " .. offer.renown
    elseif reputation then
        conditions[#conditions + 1] = ("%s: %s (%s)"):format(L("Репутация"), reputation, L("Превознесение"))
    end
    conditions[#conditions + 1] = price
    if merchant.condition then conditions[#conditions + 1] = en and merchant.englishCondition or merchant.condition end
    local vendor = { name = name, place = place, faction = merchant.faction, npc = merchant.npc, map = merchant.map,
        x = merchant.x, y = merchant.y, conditions = table.concat(conditions, "\n") }
    local alt = merchant.alternate
    if alt then
        vendor.waypoints = {
            { npc = vendor.npc, map = vendor.map, x = vendor.x, y = vendor.y, boss = name, place = place },
            { npc = alt.npc, map = alt.map, x = alt.x, y = alt.y, boss = name, place = place,
                condition = alt.condition, englishCondition = alt.englishCondition },
        }
    end
    return vendor, price
end

function atlas.addQuestRewardVendors(mount, choices)
    local reward = not mount.unavailable and not mount.availability and questMountReward(mount)
    if not reward then return end
    for _, merchant in ipairs(atlas.questRewardVendors or {}) do
        if merchantHasQuestReward(mount, reward, merchant) then
            local vendor, price = questMerchantOffer(mount, merchant)
            local name, englishName = atlas.searchKey(merchant.name), atlas.searchKey(merchant.englishName)
            local existing
            for _, choice in ipairs(choices) do
                local route = choice.vendor
                if route then
                    local routeName = not route.npc and atlas.searchKey(route.name or "")
                    if route.npc == merchant.npc or routeName == name or routeName == englishName then
                        existing = route
                        break
                    end
                end
            end
            if existing then
                existing.name = vendor.name
                existing.npc = existing.npc or vendor.npc
                if not existing.map then
                    existing.place = vendor.place
                    existing.map, existing.x, existing.y = vendor.map, vendor.x, vendor.y
                    existing.waypoints = vendor.waypoints
                end
                local normalized = atlas.normalizeSource(existing.conditions)
                if not ("\n" .. normalized):find("\nЦена:", 1, true) and not ("\n" .. normalized):find("\nPrice:", 1, true)
                    and not ("\n" .. normalized):find("\nCost:", 1, true) then
                    existing.conditions = normalized == "" and price or normalized .. "\n" .. price
                end
            else
                choices[#choices + 1] = { vendor = vendor, view = mount }
            end
        end
    end
end

function atlas.questRewardHasExclusiveColours(mount, reward)
    for _, vendor in ipairs(atlas.questRewardVendors or {}) do
        if reward and vendor.exclusiveColours and merchantHasQuestReward(mount, reward, vendor) then return true end
    end
end

function atlas.sourceNavigationHidden(mount, choice)
    local spell = mount and (atlas.mountSourcesWithoutWaypoints or {})[mount.id]
    return spell ~= nil and spell == mount.spell and not (choice and choice.vendor)
end

function atlas.questRouteGuide(mount, choice)
    local guide = (atlas.questRouteGuides or {})[mount.id]
    local route = choice and choice.classification
    if guide and guide.spell == mount.spell and route and route.state == "current" and route.key == "quest"
        and not (choice.vendor or choice.contextOnly or choice.separateSource or choice.verifiedDrop or choice.grant)
        and primaryAcquisitionSource(mount, choice, choice.view or mount) then return guide end
end

function atlas.directQuestReward(mount, choice)
    if not choice or choice.vendor or choice.contextOnly or choice.separateSource or choice.questChain
        or mount.unavailable or mount.availability then return end
    local route = choice.classification or atlas.classifyMountSource(mount, choice)
    if route.key ~= "quest" or route.state ~= "current" or route.requirement then return end
    local reward = questMountReward(mount)
    if not reward or choice.questReward ~= reward and not primaryAcquisitionSource(mount, choice, choice.view or mount) then return end
    local applicable
    for index, quest in ipairs(reward.quests) do
        if atlas.questMatchesPlayerFaction(quest) then
            if applicable then applicable[#applicable + 1] = quest end
        elseif not applicable then
            applicable = {}
            for i = 1, index - 1 do applicable[i] = reward.quests[i] end
        end
    end
    -- Keep a faction-exclusive mount documented when inspecting it on the other faction.
    if not applicable or #applicable == 0 then return reward end
    return { spell = reward.spell, quests = applicable, prerequisites = reward.prerequisites, starter = reward.starter }
end

function atlas.questMatchesPlayerFaction(quest)
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    return not quest.faction or faction ~= "Alliance" and faction ~= "Horde" or quest.faction == faction
end

function atlas.periodicQuestProgress(mount, choice)
    if not mount or not choice or mount.unavailable or mount.availability or choice.vendor or choice.blackMarket
        or choice.tradingPost or choice.contextOnly or choice.separateSource or choice.verifiedDrop or choice.grant then return end
    local data = (atlas.periodicQuestChains or {})[mount.id]
    local done = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
    if not data or data.spell ~= mount.spell or not done then return end
    local view = choice.view or mount
    local route = choice.classification or atlas.classifyMountSource(mount, choice)
    if route.state ~= "current" or route.requirement or not primaryAcquisitionSource(mount, choice, view) then return end

    local faction = UnitFactionGroup and UnitFactionGroup("player")
    if data.faction and data.faction ~= faction then return end
    local steps = data.variants and data.variants[faction] or not data.variants and data
    if not steps then return end
    local frequency = atlas.questFrequencies[mount.id]
    if data.chain then
        local chain = choice.questChain
        if not chain or chain ~= atlas.questAcquisitionChain(mount) then return end
        local complete, total, _, _, states, finalCompleted = atlas.questChainProgress(chain, true)
        if not finalCompleted then
            for _, id in ipairs(chain.quests) do
                if not states[id] and (not chain.stageTitle or id ~= chain.finalQuest) then return end
            end
        end
        return complete, total, frequency
    end
    if data.npc then
        if not view.sourceRequirements or view.sourceRequirements.npc ~= data.npc then return end
    else
        local reward = atlas.directQuestReward(mount, choice)
        if not reward then return end
        local matched
        for _, quest in ipairs(reward.quests) do
            if quest.id == steps.finalQuest then matched = true break end
        end
        if not matched then return end
    end

    local function completion(id)
        local value = done(id)
        if not (issecretvalue and issecretvalue(value)) and type(value) == "boolean" then return value end
    end
    local total = data.required or #steps.quests
    if completion(steps.finalQuest) == true then return total, total, frequency end

    if data.objectiveQuest then
        if not GetQuestObjectiveInfo then return end
        local _, _, _, count, required = GetQuestObjectiveInfo(data.objectiveQuest, 0, false)
        if (issecretvalue and (issecretvalue(count) or issecretvalue(required))) then return end
        if required == total and type(count) == "number" and count >= 0 and count <= total then
            return count, total, frequency
        end
        return
    end
    if data.item then
        local active = C_QuestLog.IsOnQuest and C_QuestLog.IsOnQuest(steps.finalQuest)
        if (issecretvalue and issecretvalue(active)) or active ~= true then return end
        local count = C_Item and C_Item.GetItemCount and C_Item.GetItemCount(data.item, true, false, false, false)
        if not (issecretvalue and issecretvalue(count)) and type(count) == "number" and count >= 0 then
            return math.min(count, total), total, frequency
        end
        return
    end

    local complete = 0
    for _, stage in ipairs(steps.quests) do
        local value
        if type(stage) == "table" then
            local known = true
            for _, id in ipairs(stage) do
                local variant = completion(id)
                if variant == true then value = true break end
                if variant == nil then known = false end
            end
            if value == nil and known then value = false end
        else
            value = completion(stage)
        end
        if value == nil then return end
        if value == true then complete = complete + 1 end
    end
    return complete, total, frequency
end

function atlas.questNavigationReward(mount, choice)
    if mount.unavailable or mount.availability then return end
    local chain = choice and choice.questChain
    if not chain or not chain.stageTitle then
        local reward = atlas.directQuestReward(mount, choice)
        if reward and reward.prerequisites then return { quests = { reward.prerequisites[1] } } end
        return reward
    end
    local function stage(id)
        local title = id == chain.finalQuest and chain or chain.stageTitle
        return { id = id, name = title.name, englishName = title.englishName, givers = { chain.npc } }
    end
    local completed, count, active, nextQuest = atlas.questChainProgress(chain)
    if completed == count then return { quests = { stage(chain.finalQuest) } } end
    if active or completed > 0 and nextQuest then return { quests = { stage(active or nextQuest) } } end
    return { quests = { stage(chain.firstQuest), stage(chain.finalQuest) } }
end

-- A quest can have several starting NPCs. Pair a coordinate only with the
-- NPC recorded on that point. Without a point, list the verified starters.
function atlas.questRewardTarget(reward, point)
    if not reward then return end
    local names = atlas.questGiverNames or {}
    if point then
        if not point.questNavigation then return end
        local name = atlas.dataName(names[point.npc])
        if name then return { boss = name, npc = point.npc, quest = point.quest, questName = point.questName,
            condition = point.condition, place = point.place } end
        return
    end
    local seen, captions, first = {}, {}, nil
    for _, quest in ipairs(reward.quests) do
        if atlas.questMatchesPlayerFaction(quest) then
            for _, npc in ipairs(quest.givers or {}) do
                local name = atlas.dataName(names[npc])
                if name and not seen[npc] then
                    seen[npc], first = true, first or npc
                    captions[#captions + 1] = name
                end
            end
        end
    end
    if first then
        local quest = #reward.quests == 1 and reward.quests[1]
        local title = quest and atlas.dataName(quest)
        return { boss = table.concat(captions, " · "), npc = #captions == 1 and first or nil,
            quest = quest and quest.id, questName = title, condition = title and atlas.L("Задание") .. ": "
                .. (atlas.sourceQuestReference(quest.id, title) or title) }
    end
end

function atlas.questRewardWaypoints(mount, choice, existing)
    if mount.availability or atlas.sourceNavigationHidden(mount, choice)
        or choice and (choice.blackMarket or choice.tradingPost) then return end
    local reward = atlas.questNavigationReward(mount, choice)
    if not reward then return end
    local faction = UnitFactionGroup and UnitFactionGroup("player")
    local points = {}
    for _, quest in ipairs(reward.quests) do
        local name = atlas.dataName(quest)
        local interaction = atlas.questInteractionWaypoints and atlas.questInteractionWaypoints[quest.id]
        local verified = interaction or atlas.questGiverWaypoints and atlas.questGiverWaypoints[quest.id]
        for _, coordinate in ipairs(verified or {}) do
            local place = atlas.mapName(coordinate.map)
            if (not quest.faction or quest.faction == faction) and (not coordinate.faction or coordinate.faction == faction) then
                local x, y = coordinate.x, coordinate.y
                for _, point in ipairs(existing or {}) do
                    if point.quest == quest.id and point.npc == coordinate.npc and point.map == coordinate.map
                        and point.navigation ~= false and atlas.hasSourceCoordinates(point)
                        and math.abs(point.x - x) <= .0005 and math.abs(point.y - y) <= .0005 then
                        x, y = point.x, point.y
                        break
                    end
                end
                local target = atlas.dataName((atlas.questGiverNames or {})[coordinate.npc])
                local condition = interaction and atlas.L("Финальное взаимодействие: %s", name)
                    or atlas.L("Задание") .. ": " .. (atlas.sourceQuestReference(quest.id, name) or name)
                points[#points + 1] = { map = coordinate.map, x = x, y = y, npc = coordinate.npc,
                    place = place, boss = target or name, quest = quest.id, questName = name, questNavigation = true, condition = condition }
            end
        end
    end
    return #points > 0 and points or nil
end

function atlas.extraQuestRewardSource(mount)
    if mount.unavailable or mount.availability then return end
    local reward = questMountReward(mount)
    if not reward or not reward.alternative then return end
    local lines = {}
    for _, quest in ipairs(reward.quests) do
        lines[#lines + 1] = ("%s: {quest:%d:%s}"):format(atlas.L("Задание"), quest.id, atlas.dataName(quest))
    end
    return { category = "quest", questReward = reward, compact = true,
        view = { id = mount.id, spell = mount.spell, kind = "Квест", journalSourceRaw = table.concat(lines, "\n"),
            trackingCompatible = false } }
end

local function sourceResult(choice, key, subtype, icon)
    local category = sourceCategories[key]
    if not category then
        return { label = "Способ не указан", icon = "Book", tab = choice.category or "other", state = "unknown" }
    end
    return { key = key, label = category[1], subtype = subtype, icon = icon or category[2],
        tab = choice.category or category[3], state = "current", requirement = false }
end

local function tradingPostResult(choice, offer)
    if offer and offer.bonus then return sourceResult(choice, "progress", "Награда журнала путешественника") end
    local result = sourceResult(choice, "purchase", "Торговая лавка")
    result.state = offer and not offer.unknown and "current" or "unknown"
    result.stock = offer and (offer.unknown and "unknown" or offer.frozen and "frozen" or "current") or "outOfRotation"
    return result
end

local function hasNativeBlackMarketSource(mount)
    local listing = atlas.blackMarketMounts and atlas.blackMarketMounts[mount.id]
    if not listing or listing.spell ~= mount.spell then return false end
    local source = mount.journalSourceRaw or ""
    source = source:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
    return source == "Черный рынок" or source == "Чёрный рынок" or source == "Black Market"
end

local function directGrantForSource(mount, choice, primary)
    local grant = mount.directSourceGrant
    if not grant then return end
    if grant.alternative and choice.grant == grant.alternative then return grant.alternative end
    if choice.grant == grant or primary and not choice.verifiedDrop and not grant.alternate then return grant end
end

-- `choice` is the route being displayed. Its category, when supplied, is the
-- existing renderer group; it is never evidence for unrelated alternatives.
function atlas.classifyMountSource(mount, choice)
    choice = choice or {}
    if type(mount) ~= "table" then return sourceResult(choice) end
    local view, vendor = choice.view or mount, choice.vendor
    local availability = view.availability or mount.availability
    if choice.historical or (mount.unavailable or availability and availability.state == "unavailable")
        and not vendor and not choice.tradingPost then
        local historyKey = availability and availability.historyKey
        local method = sourceCategories[historyKey]
        local label = availability and availability.conditions and "—" or "Способ не указан"
        return { label = label, icon = method and method[2] or "Book", tab = "unavailable", state = "historical",
            historyKey = historyKey, historyLabel = method and method[1],
            seasonal = availability and availability.temporary == true or false }
    end

    if vendor then
        local result
        if vendor.redemption == "tcg" then
            result = sourceResult(choice, "promotion", "Код TCG")
        else
            result = sourceResult(choice, "purchase", "Торговец")
        end
        result.eventID = vendor.holiday or choice.holiday
        result.seasonal = result.eventID ~= nil
        return result
    end
    if choice.tradingPost then return tradingPostResult(choice, choice.tradingPost) end
    if choice.blackMarket or view == mount and hasNativeBlackMarketSource(mount) then
        return sourceResult(choice, "purchase", "Чёрный рынок")
    end

    local finalReward = (atlas.guaranteedRewards or {})[mount.id]
    local questGrant = choice.questStep and finalReward and finalReward.method == "quest"
        and finalReward.reagent and finalReward.reagent.completionQuest
    if view.purchaseRequirement or choice.contextOnly or choice.questStep then
        local key = view.purchaseRequirement and "achievement" or choice.category
        local result = sourceResult(choice, key)
        result.requirement = not questGrant
        return result
    end

    if availability and availability.state == "blackmarket" then return sourceResult(choice, "purchase", "Чёрный рынок") end
    local availabilityRoute = availability and availability.routes and availability.routes[1]
    if availability and availability.state == "conditional" and availabilityRoute and availabilityRoute.kind == "legacyTitle" then
        local result = sourceResult(choice, "progress")
        result.state = "unknown"
        return result
    end
    local primary = primaryAcquisitionSource(mount, choice, view)
    local kind = view.sourceKind or view.kind or choice.verifiedDrop and "Добыча"
    local result
    local questReward = primary and questMountReward(mount)
    local grant = directGrantForSource(mount, choice, primary)
    if grant then
        result = sourceResult(choice, grant.key, grant.subtype)
        result.state = grant.state or result.state
        result.seasonal = grant.seasonal
    elseif questReward and questReward.nativeGap then
        result = sourceResult(choice, "quest")
    elseif primary and not choice.verifiedDrop and (kind == "Профессия" or kind == "Добыча")
        and fishingReward(mount) then
        result = sourceResult(choice, "fishing")
    elseif primary and not choice.verifiedDrop and (kind == "Добыча" or kind == "Босс") and finalReward
        and finalReward.method == "collection" and finalReward.reagent and finalReward.item and finalReward.rate == 1 then
        result = sourceResult(choice, "progress", "Сбор предметов")
    elseif kind == "Торговая лавка" and primary then
        result = tradingPostResult(choice, atlas.tradingPostOffer(mount))
    elseif primary and not choice.verifiedDrop and (kind == "Добыча" or kind == "Квест" or kind == nil) and choice.category == "loot"
        and mount.locations and mount.npcs and not view.journalInstance and not view.isRaid then
        result = sourceResult(choice, "loot", "Рарка", "Rare")
    else
        local tag = sourceTypes[kind]
        result = tag and sourceResult(choice, unpack(tag)) or sourceResult(choice)
    end
    if primary and (result.key == "loot" or result.key == "event" or result.key == "quest") then
        result.eventID = eventForSource(mount)
        if result.eventID then result.seasonal = true end
    end
    if primary and result.key == "pvp" and mount.sourceReview
        and mount.sourceReview.reviewReason == "futureViciousSaddleAvailability" then
        result.state, result.seasonal, result.historyKey = "unknown", true, "pvp"
    end
    return result
end

local vendorPriceLabels = { ["Цена"] = true, ["Стоимость"] = true, Price = true, Cost = true }
local indirectRewardLabels = {
    ["Добыча"] = true, ["Сокровище"] = true, ["Контейнер"] = true,
    Drop = true, Treasure = true, Container = true,
}

local function directVendorPrice(vendor, reward)
    if type(vendor.name) ~= "string" or vendor.redemption
        or vendor.name == "" and (not reward or not atlas.sourcePlaceValue(vendor.place, "Торговец")) then return false end
    local priced, directItem
    for line in atlas.normalizeSource(vendor.conditions):gmatch("[^\n]+") do
        local label, value = line:match("^([^:{]+):%s*(.-)%s*$")
        if indirectRewardLabels[label] then return false end
        if label == "Предмет" or label == "Item" then
            local item = tonumber(value:match("|Hitem:(%d+)") or value:match("{item:(%d+):"))
            if not reward or item ~= reward.item then return false end
            directItem = item
        end
        if vendorPriceLabels[label] then
            local amount = value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(%d+)")
            if priced or not amount or tonumber(amount) <= 0 then return false end
            priced = true
        end
    end
    return priced == true, directItem
end

local function randomContainerSource(mount, view)
    local stages = (atlas.attemptStages or {})[mount.id]
    local reward = stages and stages.reward
    if not reward or reward.method ~= "USE" or reward.rate == 1 then return false end
    local source = atlas.normalizeSource(view.journalSourceOverride or view.journalSourceRaw or view.journalSource)
    for line in source:gmatch("[^\n]+") do
        local label, text = line:match("^([^:{]+):%s*(.+)$")
        if indirectRewardLabels[label] or label == "Источник" or label == "Source" or label == "Предмет" or label == "Item" then
            local id = tonumber(text:match("|Hitem:(%d+)") or text:match("{item:(%d+):"))
            for _, container in ipairs(reward.items or {}) do
                if id == container then return true end
            end
            local key = atlas.searchKey(text)
            for _, name in ipairs(reward.searchNames or {}) do
                if key:find(atlas.searchKey(name), 1, true) then return true end
            end
        end
    end
    return false
end

function atlas.craftedMountItem(mount)
    local recipes = atlas.mountCraftRecipes or {}
    local item
    for _, reward in ipairs((atlas.mountRewardItems or {})[mount.id] or {}) do
        if recipes[reward.item] then
            if item and item ~= reward.item then return end
            item = reward.item
        end
    end
    return item
end

function atlas.protoformUnlockQuest(mount, choice)
    local route = choice and choice.classification
    if not route or route.key ~= "profession" or route.state ~= "current" or route.requirement then return end
    local item = atlas.craftedMountItem(mount)
    if item and atlas.protoformMountRecipes[item] then return atlas.protoformForgeQuest end
end

-- The guarantee describes this route's final reward. A separate starter,
-- drop or alternative route keeps its own chance and attempt counters.
function atlas.sourceGuaranteedReward(mount, choice)
    if not mount or not choice then return end
    local view = choice.view or mount
    local route = choice.classification or atlas.classifyMountSource(mount, choice)
    if route.state ~= "current" or route.requirement or choice.historical or choice.blackMarket
        or route.subtype == "Чёрный рынок" or choice.verifiedDrop or view.purchaseRequirement then return end

    local offer = choice.tradingPost
    if offer then
        if not offer.unknown and (offer.bonus or perksNumber(offer.price) and offer.price >= 0) then
            return { method = "tradingPost" }
        end
        return
    end
    local availability = view.availability or mount.availability
    if mount.unavailable or view.unavailable or availability and availability.state ~= "available"
        or choice.contextOnly or view.contextOnly then return end

    local vendor = choice.vendor
    if vendor then
        if route.key == "purchase" then
            local reward = atlas.rewardItem(mount, vendor, true)
            local priced, directItem = directVendorPrice(vendor, reward)
            if priced and (directItem or not randomContainerSource(mount, view)) then
                return { method = "purchase", item = reward and reward.item }
            end
        end
        return
    end
    if route.key == "achievement" and atlas.sourceAchievementReward then
        local item = atlas.sourceAchievementReward(mount, view)
        if item then return { method = "achievement", item = item } end
    end
    if route.key == "quest" then
        local reward = atlas.directQuestReward(mount, choice)
        if reward then return { method = "quest", item = #reward.quests == 1 and reward.quests[1].item or nil } end
    end
    if route.key == "profession" and not choice.separateSource then
        local item = atlas.craftedMountItem(mount)
        if item then return { method = "profession", item = item } end
    end
    local primary = primaryAcquisitionSource(mount, choice, view)
    local grant = directGrantForSource(mount, choice, primary)
    if grant and not choice.separateSource and (route.key == "progress" or route.key == "quest" or route.key == "pvp") then
        local condition = atlas.getLocale() == "enUS" and grant.englishText or grant.text
        return { method = route.key, condition = condition and atlas.sourceInlineLinks(condition) }
    end
end

function atlas.raidLootGuaranteeForSource(mount, choice)
    if choice.vendor or choice.blackMarket or choice.tradingPost or choice.verifiedDrop or choice.contextOnly
        or choice.separateSource or mount.unavailable or mount.availability then return end
    local reward = atlas.raidLootReward(mount)
    if not reward or reward.groupRate ~= 1 or mount.spell ~= reward.spell then return end
    local view = choice.view or mount
    local route = choice.classification or atlas.classifyMountSource(mount, choice)
    if route.key ~= "loot" or route.state ~= "current" or route.requirement or not primaryAcquisitionSource(mount, choice, view)
        or view.difficulties and not view.difficulties[reward.difficultyID]
        or view.sourceMap and view.sourceMap ~= reward.map then return end
    local place = atlas.sourcePlaceValue(view.place, view.kind)
    if place then
        place = atlas.searchKey(atlas.sourceDifficultySuffix(place) or place)
        if place ~= atlas.searchKey(reward.place) and place ~= atlas.searchKey(reward.englishPlace) then return end
    end
    local boss = view.boss and atlas.searchKey(atlas.sourceDifficultySuffix(view.boss) or view.boss)
    if boss == atlas.searchKey(reward.boss) or boss == atlas.searchKey(reward.englishBoss) then return reward end
end

-- A current journal/live calendar offer is its own route, including when the
-- same item has a redemption code or another acquisition source.
function atlas.extraTradingPostSource(mount)
    if not mount or mount.kind == "Торговая лавка" then return end
    local offer = atlas.tradingPostOffer(mount)
    if offer and not offer.unknown then return offer end
end

function atlas.extraBlackMarketSource(mount)
    if not mount or mount.unavailable or mount.availability and mount.availability.state == "blackmarket" then return end
    local listing = (atlas.blackMarketMounts or {})[mount.id]
    if not listing or listing.spell ~= mount.spell or hasNativeBlackMarketSource(mount) then return end
    return { category = "vendor", compact = true, contextOnly = true, blackMarket = listing, view = {
        id = mount.id, spell = mount.spell, kind = "Чёрный рынок", contextOnly = true, trackingCompatible = false,
        journalSourceRaw = atlas.L("Чёрный рынок: лот с маунтом."),
    } }
end

function atlas.extraDirectGrantSource(mount)
    local grant = mount and mount.directSourceGrant
    grant = grant and (grant.alternative or grant.alternate and grant)
    if not grant then return end
    local text = atlas.getLocale() == "enUS" and grant.englishText or grant.text
    if grant.renown then text = atlas.covenantRenownSource(grant.covenant, grant.renown) end
    return { category = "other", compact = true, grant = grant, view = {
        id = mount.id, spell = mount.spell, kind = "Награда за прогресс", journalSourceRaw = text,
        trackingCompatible = false,
    } }
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
function atlas.sourceNavigationAllowed(mount, npc)
    if npc then
        for _, point in ipairs(mount.locations or {}) do
            if point.npc == npc and point.navigation == false then return false end
        end
    end
    return true
end

function atlas.sourcePointCondition(point)
    if not point then return end
    local english = point.englishCondition
    if atlas.getLocale() == "enUS" and type(english) == "string" and english ~= "" then return english end
    if type(point.condition) == "string" and point.condition ~= "" then return point.condition end
end

local sourceFactions = {
    Alliance = "Alliance", Horde = "Horde", ["Альянс"] = "Alliance", ["Орда"] = "Horde",
}

function atlas.sourcePointFaction(point)
    if not point then return end
    local explicit = sourceFactions[point.faction]
    if explicit then return explicit end
    local faction
    if type(point.condition) == "string" then
        for line in (point.condition .. "\n"):gmatch("(.-)\n") do
            local side = sourceFactions[line:match("^%s*(.-)%s*$")]
            if faction and side and side ~= faction then return end
            faction = side or faction
        end
    end
    return faction or (atlas.npcSourceFactions and atlas.npcSourceFactions[point.npc])
end

function atlas.mountLocations(mount, guid, navigationOnly)
    if mount.unavailable or mount.availability then return {} end
    local points, byX, locatedByMap, missing = {}, {}, {}, {}
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
    local function contextValue(key, value, zoneMatch, faction)
        if key == "x" or key == "y" or key == "npc" or key == "map"
            or key == "boss" or key == "place" or key == "englishBoss" or key == "englishPlace" then return end
        -- A citation identifies the data provider, not a separate game source.
        if key == "source" and type(value) == "string" and value:match("^https?://") then return end
        -- A sighting locates the same NPC, and a faction label can repeat its fixed eligibility.
        if zoneMatch and key == "kind" and value == "sighting" then return end
        if faction and (key == "faction" or key == "condition" or key == "englishCondition")
            and sourceFactions[value] == faction then return end
        return value
    end
    local function sameSource(a, b, zoneMatch)
        if a.map ~= b.map or a.npc ~= b.npc then return false end
        if not a.npc and identity(a) ~= identity(b) then return false end
        zoneMatch = zoneMatch and a.npc ~= nil
        local faction = zoneMatch and atlas.npcSourceFactions and atlas.npcSourceFactions[a.npc]
        for key, value in pairs(a) do
            if not equal(contextValue(key, value, zoneMatch, faction), contextValue(key, b[key], zoneMatch, faction)) then
                return false
            end
        end
        for key, value in pairs(b) do
            if a[key] == nil and contextValue(key, value, zoneMatch, faction) ~= nil then return false end
        end
        return true
    end
    local function roundedCoordinate(a, b)
        if a == b then return true end
        if type(a) ~= "number" or type(b) ~= "number" then return false end
        -- Use the same percent scale and precision as the coordinate button.
        -- Reconcile with a provider at that precision, not two precise points.
        local function atDisplayPrecision(value)
            return math.abs(value * 1000 - math.floor(value * 1000 + .5)) < 1e-7
        end
        return (atDisplayPrecision(a) or atDisplayPrecision(b))
            and string.format("%.1f", a * 100) == string.format("%.1f", b * 100)
    end
    local function sameWaypoint(original, extraPoint)
        if roundedCoordinate(extraPoint.x, original.x) and roundedCoordinate(extraPoint.y, original.y) then return true end
        local byMap = atlas.sourceWaypointAliases and atlas.sourceWaypointAliases[extraPoint.map]
        local alias = byMap and byMap[extraPoint.npc]
        return alias and original.x == alias.x and original.y == alias.y
            and extraPoint.x == alias.alternateX and extraPoint.y == alias.alternateY
    end
    local function add(point, reconcile)
        point = resolve(point)
        if not point then return end
        if navigationOnly and (point.navigation == false or not atlas.sourceNavigationAllowed(mount, point.npc)) then return end
        if guid and atlas.sourceAvailableToCharacter(point.npc, guid) ~= true then return end
        local x, y = point.x, point.y
        if x == nil then x = missing end
        if y == nil then y = missing end
        local exact
        if x == x and y == y then
            local byY = byX[x]
            if not byY then byY = {}; byX[x] = byY end
            exact = byY[y]
            if not exact then exact = {}; byY[y] = exact end
            for _, known in ipairs(exact) do
                if sameSource(point, known) then return end
            end
        end
        -- Rarity and navigation providers can encode the same verified NPC at
        -- different precision. Only compare against the original feed here.
        local rounded, ambiguous
        if reconcile and point.npc and point.x and point.y then
            for index = 1, reconcile do
                local known = points[index]
                if sameSource(point, known) and sameWaypoint(known, point) then
                    if rounded then ambiguous = true; break end
                    rounded = known
                end
            end
        end
        if rounded and not ambiguous then
            for _, candidate in ipairs(extra) do
                candidate = resolve(candidate)
                if sameSource(point, candidate) and (point.x ~= candidate.x or point.y ~= candidate.y)
                    and sameWaypoint(rounded, candidate) then
                    ambiguous = true; break
                end
            end
            if not ambiguous then return end
        end
        points[#points + 1] = point
        if exact then exact[#exact + 1] = point end
        if point.navigation ~= false and atlas.hasSourceCoordinates(point) then
            local located = locatedByMap[point.map]
            if not located then located = {}; locatedByMap[point.map] = located end
            located[#located + 1] = point
        end
    end
    for _, point in ipairs(mount.locations or {}) do add(point) end
    local originalCount = #points
    for _, point in ipairs(extra) do add(point, originalCount) end

    -- Compare both feeds after validating the waypoints for the active character and view.
    local kept, entrances = 0, 0
    for _, point in ipairs(points) do
        local replaced = false
        if not atlas.hasSourceCoordinates(point) then
            for _, known in ipairs(locatedByMap[point.map] or {}) do
                if sameSource(point, known, true) then replaced = true; break end
            end
        end
        if not replaced then
            kept = kept + 1
            local position = kept
            if point.kind == "caveEntrance" then
                entrances = entrances + 1
                position = entrances
                for index = kept, position + 1, -1 do points[index] = points[index - 1] end
            end
            points[position] = point
        end
    end
    for index = #points, kept + 1, -1 do points[index] = nil end
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
    local kind = mount.sourcePlaceKind or mount.kind
    if mount.journalInstance or (kind ~= "Рейд" and kind ~= "Подземелье")
        or not EJ_GetInstanceInfo then return end
    local encounters = C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap
    local function matches(id)
        if not id or id == 0 then return end
        local name, _, _, _, _, _, _, _, _, _, _, isRaid = EJ_GetInstanceInfo(id)
        return name and (isRaid == true) == (kind == "Рейд")
    end
    local instance
    for _, map in ipairs(sourceMaps(mount)) do
        local direct = EJ_GetInstanceForMap and EJ_GetInstanceForMap(map)
        if matches(direct) then
            if instance and instance ~= direct then return end
            instance = direct
        elseif encounters and EJ_GetEncounterInfo then
            for _, entry in ipairs(encounters(map) or {}) do
                local _, _, _, _, _, id = EJ_GetEncounterInfo(entry.encounterID)
                if matches(id) then
                    if instance and instance ~= id then return end
                    instance = id
                end
            end
        end
    end
    if instance then mount.journalInstance = instance; sourceDifficulty(mount) end
end

local encounterTargetAliases = {
    -- The curated mount routes use these Russian titles in every client locale.
    [542] = { "Анзу" },
    [1553] = { "Ловчий Аттумен" },
    [1576] = { "Кель’тас Солнечный Скиталец" },
    -- Glacial Tidestorm's mount journal source omits the title used in the raid journal.
    -- https://wago.tools/db2/JournalEncounterCreature/csv?filter[JournalEncounterID]=2343
    [2343] = { "Джайна Праудмур", "Jaina Proudmoore" },
    -- Vengeance's mount source includes Sylvanas's title.
    -- https://wago.tools/db2/JournalEncounter/csv?filter[ID]=2441
    [2441] = { "Леди Сильвана Ветрокрылая", "Lady Sylvanas Windrunner" },
    -- Anu'relos lists the abbreviated name for Fyrakk the Blazing.
    -- https://wago.tools/db2/JournalEncounter/csv?filter[ID]=2519
    [2519] = { "Фиракк", "Fyrakk" },
}

local function sourceTargetKey(name)
    if not (issecretvalue and issecretvalue(name)) and type(name) == "string" then
        local key = atlas.searchKey(name)
        if key ~= "" then return key end
    end
end

local function sourceTargetNames(view)
    local wanted = {}
    local function add(name)
        local key = sourceTargetKey(name)
        if key then wanted[key] = true end
        return key
    end
    if add(view.boss) and atlas.sourceName then add(atlas.sourceName(view.boss, "enUS", "target")) end
    add(view.englishBoss)
    return wanted
end

local function matchesEncounterTarget(id, name, wanted)
    local key = sourceTargetKey(name)
    if not key then return end
    if wanted[key] then return true end
    for _, alias in ipairs(encounterTargetAliases[id] or {}) do
        if wanted[atlas.searchKey(alias)] then return true end
    end
end

local function matchesReviewedBossRoute(view, route, wanted)
    if route.map and route.map ~= view.sourceMap or not sourceTargetKey(view.place) then return end
    local place = sourceTargetKey(atlas.sourceDifficultySuffix(view.place) or view.place)
    if place ~= sourceTargetKey(route.place) and place ~= sourceTargetKey(route.englishPlace) then return end
    return wanted[sourceTargetKey(route.boss)] or wanted[sourceTargetKey(route.englishBoss)]
end

local function positiveIntegerID(id)
    return perksNumber(id) and id > 0 and id % 1 == 0
end

local function matchesSourceEncounter(id, name, wanted)
    if matchesEncounterTarget(id, name, wanted) then return true end
    if not EJ_GetCreatureInfo then return end
    -- A mount can name an individual creature in a council encounter, such as Shatug.
    for index = 1, 9 do -- Blizzard EncounterJournal's creature limit.
        local creature, creatureName = EJ_GetCreatureInfo(index, id)
        if not positiveIntegerID(creature) then break end
        if wanted[sourceTargetKey(creatureName)] then return true end
    end
end

function atlas.resolveSourceEncounter(mount)
    if mount.journalEncounter or not mount.hasSourcePanels or mount.sourceKind ~= "Босс" then return end
    local info = not mount.difficultyLocalOnly and atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id]
    local wanted = sourceTargetNames(mount)
    if not next(wanted) then return end
    if info and info.noJournalEncounter and matchesReviewedBossRoute(mount, info, wanted) then return end
    local encounter, instance
    local seen = {}
    local function consider(id, name, instanceID)
        if not positiveIntegerID(id) or not positiveIntegerID(instanceID) or seen[id] then return end
        seen[id] = true
        if matchesSourceEncounter(id, name, wanted) then
            if encounter then return true end
            encounter, instance = id, instanceID
        end
    end
    local mapEncounters = C_EncounterJournal and C_EncounterJournal.GetEncountersOnMap
    if mapEncounters and EJ_GetEncounterInfo then
        for _, map in ipairs(sourceMaps(mount)) do
            for _, entry in ipairs(mapEncounters(map) or {}) do
                local id = entry.encounterID
                if positiveIntegerID(id) and not seen[id] then
                    local name, _, _, _, _, instanceID = EJ_GetEncounterInfo(id)
                    if consider(id, name, instanceID) then return end
                end
            end
        end
    end
    if not encounter and EJ_GetEncounterInfoByIndex then
        if not mount.journalInstance then atlas.resolveSourceInstance(mount) end
        local instanceID = mount.journalInstance
        if positiveIntegerID(instanceID) then
            -- The instance can have several independent UiMap groups with their own pins.
            local index = 1
            while true do
                local name, _, id, _, _, owner = EJ_GetEncounterInfoByIndex(index, instanceID)
                if not positiveIntegerID(id) then break end
                if positiveIntegerID(owner) and owner == instanceID and consider(id, name, owner) then return end
                index = index + 1
            end
        end
    end
    if not encounter then return end -- Retry later if client data was not ready.
    mount.journalEncounter, mount.journalInstance = encounter, instance
    sourceDifficulty(mount)
end

local encounterPortraits = {}
local portraitUnits = { "npc", "target", "focus", "mouseover" }
local function visiblePortraitUnit(npc)
    if not SetPortraitTexture or not UnitGUID then return end
    for _, unit in ipairs(portraitUnits) do
        local guid = UnitGUID(unit)
        if not (issecretvalue and issecretvalue(guid)) and type(guid) == "string" then
            local kind, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
            if (kind == "Creature" or kind == "Vehicle") and tonumber(id) == npc then return unit, guid end
        end
    end
end

local function encounterPortraitFile(icon)
    if issecretvalue and issecretvalue(icon) then return end
    if positiveIntegerID(icon) then
        -- Blizzard's default encounter icon and item question mark.
        if icon ~= 521744 and icon ~= 134400 then return icon end
    elseif type(icon) == "string" and icon ~= "" then
        local asset = icon:lower()
        if not asset:find("ui-ej-boss-default", 1, true) and not asset:find("inv_misc_questionmark", 1, true) then return icon end
    end
end

local function encounterCreatures(id)
    if not positiveIntegerID(id) or not EJ_GetCreatureInfo then return end
    if encounterPortraits[id] then return encounterPortraits[id] end
    local entries, complete = {}, true
    for index = 1, 9 do
        -- The first result identifies a JournalEncounterCreature row.
        local creature, name, _, display, icon = EJ_GetCreatureInfo(index, id)
        if not positiveIntegerID(creature) then
            if (issecretvalue and issecretvalue(creature)) or creature ~= nil then complete = false end
            break
        end
        icon = encounterPortraitFile(icon)
        name = sourceTargetKey(name)
        display = positiveIntegerID(display) and display or nil
        if not name or not (display or icon) then complete = false end
        entries[#entries + 1] = { name = name, display = display, icon = icon }
    end
    if #entries > 0 then
        if complete then encounterPortraits[id] = entries end
        return entries
    end
end

local function sourceNpc(subject)
    local npc = subject.npc
    if not positiveIntegerID(npc) and subject.npcs and #subject.npcs == 1 then npc = subject.npcs[1] end
    if positiveIntegerID(npc) then return npc end
end

local function reviewedBossNpc(mount, view)
    if not mount or mount.unavailable or view.sourceKind ~= "Босс" or not primaryAcquisitionSource(mount, nil, view) then return end
    local route = mount.sourceOverride or (atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id])
    if not route then return end
    local faction = route.npcByFaction and atlas.characterFaction and atlas.characterFaction()
    local variant = faction and route.npcByFaction[faction]
    local npc = sourceNpc(route) or variant and (not view.sourceMap or view.sourceMap == variant.map) and sourceNpc(variant)
    if npc and matchesReviewedBossRoute(view, route, sourceTargetNames(view)) then return npc end
end

local function encounterSourcePortrait(view, subject, point, npc)
    local id = view.journalEncounter
    local entries = encounterCreatures(id)
    if not entries then return end
    local wanted = sourceTargetNames(subject)
    local matchesTitle
    if not point and EJ_GetEncounterInfo then
        local title = EJ_GetEncounterInfo(id)
        matchesTitle = matchesEncounterTarget(id, title, wanted)
        if matchesTitle then wanted[sourceTargetKey(title)] = true end
    end
    local selected
    for _, entry in ipairs(entries) do
        if wanted[entry.name] then
            if selected and (selected.display ~= entry.display or selected.icon ~= entry.icon) then return end
            selected = entry
        end
    end
    if not selected and not point then
        -- Blizzard uses the first creature as the icon for an encounter heading.
        if matchesTitle or #entries == 1 and not next(wanted) and not npc then selected = entries[1] end
    end
    return selected
end

function atlas.sourcePortrait(mount, view, point)
    if not view then return end
    local subject = point or view
    local npc = sourceNpc(subject)
    if not npc and not point then npc = reviewedBossNpc(mount, view) end
    -- The Darkshore creature joins the player as this mount.
    -- https://www.wowhead.com/npc=148790/frightened-kodo
    local kodo = mount and mount.id == 1201 and mount.spell == 288499 and primaryAcquisitionSource(mount, nil, view)
        and (npc == 148790 or not point and not npc)
    local display
    if npc or kodo then
        npc = npc or 148790
        local unit, guid = visiblePortraitUnit(npc)
        if unit then return nil, nil, nil, unit, guid end
        local known = atlas.sourceNpcDisplayIDs and atlas.sourceNpcDisplayIDs[npc]
        if positiveIntegerID(known) and SetPortraitTextureFromCreatureDisplayID then display = known end
        if kodo and not display then return mount.icon end
    end
    local selected
    if not point or not npc or npc == sourceNpc(view) then
        selected = encounterSourcePortrait(view, subject, point, npc)
    end
    if selected and selected.icon then return selected.icon, selected.display, 2 end
    if display then return nil, display end
    if selected and selected.display and SetPortraitTextureFromCreatureDisplayID then return nil, selected.display end
    return nil, nil, nil, nil, nil, npc
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

local classNames = {
    [1] = { "Воин", "Warrior" }, [2] = { "Паладин", "Paladin" }, [3] = { "Охотник", "Hunter" },
    [4] = { "Разбойник", "Rogue" }, [5] = { "Жрец", "Priest" }, [6] = { "Рыцарь смерти", "Death Knight" },
    [7] = { "Шаман", "Shaman" }, [8] = { "Маг", "Mage" }, [9] = { "Чернокнижник", "Warlock" },
    [10] = { "Монах", "Monk" }, [11] = { "Друид", "Druid" }, [12] = { "Охотник на демонов", "Demon Hunter" },
    [13] = { "Пробудитель", "Evoker" },
}

function atlas.mountClassName(mount)
    local id = mount and atlas.mountClassRequirements and atlas.mountClassRequirements[mount.id]
    if not id then return end
    local locale = atlas.getLocale()
    if not GetLocale or GetLocale() == locale then
        local info = C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(id)
        local name = info and info.className or (GetClassInfo and GetClassInfo(id))
        if not (issecretvalue and issecretvalue(name)) and type(name) == "string" and name ~= "" then return name end
    end
    local names = classNames[id]
    return names and names[locale == "enUS" and 2 or 1]
end

local function validUiMapID(id)
    return perksNumber(id) and id > 0 and id % 1 == 0
end

local function nativeMapInfo(id)
    if not validUiMapID(id) or not C_Map or not C_Map.GetMapInfo then return end
    local info = C_Map.GetMapInfo(id)
    if type(info) == "table" and not (issecretvalue and issecretvalue(info)) and info.mapID == id then return info end
end

local uiMaps = atlas.sourceUiMaps or {}
-- Exact journal names and acquisition-route aliases for verified UiMaps.
local reviewedMapNames = {
    [24] = { "Обитель Света", "Sanctum of Light" }, -- ATT SANCTUM_OF_LIGHT = LIGHTS_HOPE_CHAPEL.
    [141] = { "Око Вечности", "Eye of Eternity" },
    [334] = { "Око (Крепость Бурь)", "The Eye, Tempest Keep", "Крепость Бурь · Око", "Tempest Keep · The Eye" },
    [500] = { 'Потасовочная "У Бизмо"', "Bizmo's Brawlpub" }, -- ATT DEEPRUN_TRAM_BIZMOS_BRAWLPUB.
    [794] = { "Возвращение в Каражан", "Return to Karazhan" },
    [942] = { "Stormsong" },
    [2133] = { "Заралек" },
    [2200] = { "Изумрудный Сон" },
    [2248] = { "The Isle of Dorn" },
}
local routeMapNames = {
    -- Gilnean Prowler, q78189 in the Ruins of Gilneas. Other maps share the ruRU name.
    [1949] = { spell = 430225, map = 217, names = { "Гилнеас", "Gilneas" } },
}
local mapsByName
local function mapNameKey(name)
    if not (issecretvalue and issecretvalue(name)) and type(name) == "string" then
        local key = atlas.searchKey(name)
        if key ~= "" and key ~= "—" then return key end
    end
end

local function mapCandidates(key)
    if not mapsByName then
        mapsByName = {}
        local function index(id, names, count)
            local seen = {}
            for i = 1, count or #names do
                local key = mapNameKey(names[i])
                if key and not seen[key] then
                    seen[key] = true
                    local ids = mapsByName[key] or {}
                    ids[#ids + 1] = id
                    mapsByName[key] = ids
                end
            end
        end
        for id, row in pairs(uiMaps) do
            index(id, row, 2)
        end
        -- Explicit reviewed aliases identify the playable map even when a
        -- same-name scenario is also present in UiMap.
        local aliases = {}
        for id, names in pairs(reviewedMapNames) do
            for _, name in ipairs(names) do
                local key = mapNameKey(name)
                if aliases[key] == nil then aliases[key] = id
                elseif aliases[key] ~= id then aliases[key] = false end
            end
        end
        for name, id in pairs(aliases) do
            if id then mapsByName[name] = { id } end
        end
    end
    return mapsByName[key]
end

local function mapMatchesName(id, key, info)
    local row = uiMaps[id]
    if not key then return false end
    if mapNameKey(info and info.name) == key or row and (mapNameKey(row[1]) == key or mapNameKey(row[2]) == key) then return true end
    for _, name in ipairs(reviewedMapNames[id] or {}) do
        if mapNameKey(name) == key then return true end
    end
    return false
end

local function mapChildOf(id, parent)
    while validUiMapID(id) do
        if id == parent then return true end
        local row = uiMaps[id]
        local nextID = row and row[3]
        if id == nextID then return end
        id = nextID
    end
end

local function uniqueNamedMap(key, parentKey)
    local eligible = {}
    for _, id in ipairs(mapCandidates(key) or {}) do
        if not parentKey then
            eligible[#eligible + 1] = id
        else
            for _, parent in ipairs(mapCandidates(parentKey) or {}) do
                if id ~= parent and mapChildOf(id, parent) then eligible[#eligible + 1] = id; break end
            end
        end
    end
    -- When names repeat along one parent/child chain, the parent is the
    -- territory map. A same-name orphan sharing its parent is not a second
    -- geographic zone. Other siblings need explicit source context.
    for _, id in ipairs(eligible) do
        local parent = true
        local map = uiMaps[id]
        for _, other in ipairs(eligible) do
            local replica = uiMaps[other]
            local orphan = map and map[4] == 3 and replica and replica[4] == 6 and replica[3] == map[3]
            if not orphan and not mapChildOf(other, id) then parent = false; break end
        end
        if parent then return nativeMapInfo(id) and id or nil end
    end
end

function atlas.mapName(id)
    local info = nativeMapInfo(id)
    if not info then return end
    local row = uiMaps[id]
    return row and row[atlas.getLocale() == "enUS" and 2 or 1] or info.name
end

function atlas.instanceEntrancePoints(view)
    local instance = view.journalInstance
    local kind = view.sourcePlaceKind or view.kind
    local fallback
    if kind == "Вылазка" then
        fallback = atlas.delveEntranceWaypoints and atlas.delveEntranceWaypoints[view.sourceMap]
        if not fallback then return end
    elseif instance then
        fallback = atlas.instanceEntranceWaypoints and atlas.instanceEntranceWaypoints[instance]
        if not fallback and kind ~= "Рейд" and kind ~= "Подземелье" then return end
        fallback = fallback or {}
    else return end
    local maps, seenMaps, fallbackCounts, specificMaps, eligible = {}, {}, {}, {}, {}
    local faction, factionRestricted = UnitFactionGroup and UnitFactionGroup("player"), false
    local function addMap(map)
        if not seenMaps[map] then
            seenMaps[map] = true
            maps[#maps + 1] = map
        end
    end
    for _, point in ipairs(fallback) do
        factionRestricted = factionRestricted or point.faction ~= nil
        if atlas.hasSourceCoordinates(point) and (not point.faction or point.faction == faction) then
            addMap(point.map)
            eligible[#eligible + 1] = point
            fallbackCounts[point.map] = (fallbackCounts[point.map] or 0) + 1
            if point.specific then specificMaps[point.map] = true end
        end
    end

    local points, nativeCounts, seenPoints = {}, {}, {}
    local title = instance and EJ_GetInstanceInfo and EJ_GetInstanceInfo(instance) or view.place
    local function addPoint(map, x, y)
        local point = { map = map, x = x, y = y, boss = title, place = atlas.mapName(map), entrance = true,
            condition = atlas.L("Вход") }
        if not point.place or not atlas.hasSourceCoordinates(point) then return end
        local key = ("%d:%.1f:%.1f"):format(map, x * 100, y * 100)
        if seenPoints[key] then return end
        seenPoints[key] = true
        points[#points + 1] = point
        return true
    end

    if instance and C_EncounterJournal and C_EncounterJournal.GetDungeonEntrancesForMap then
        -- Query only confirmed entrance maps and the nearest outdoor map of known instance floors.
        local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
        local visited = {}
        if not factionRestricted then
            for _, sourceMap in ipairs(sourceMaps(view)) do
                local map = sourceMap
                while map and map > 0 and not visited[map] do
                    visited[map] = true
                    local info = nativeMapInfo(map)
                    if not info then break end
                    local row = uiMaps[map]
                    if (info.mapType or row and row[4]) == zoneType then addMap(map); break end
                    map = info.parentMapID
                end
            end
        end
        for _, map in ipairs(maps) do
            if not specificMaps[map] then
                for _, entry in ipairs(C_EncounterJournal.GetDungeonEntrancesForMap(map) or {}) do
                    if entry.journalInstanceID == instance and entry.position then
                        local x, y = entry.position:GetXY()
                        if addPoint(map, x, y) then nativeCounts[map] = (nativeCounts[map] or 0) + 1 end
                    end
                end
            end
        end
    end
    for _, point in ipairs(eligible) do
        if not (fallbackCounts[point.map] == 1 and nativeCounts[point.map] == 1) then
            addPoint(point.map, point.x, point.y)
        end
    end
    return #points > 0 and points or nil
end

function atlas.sourceMapID(place, point, mount)
    if not mapNameKey(place) then return end
    place = atlas.sourceDifficultySuffix and atlas.sourceDifficultySuffix(place) or place
    local first, second = place:match("^(.-) · (.-)$")
    if first then
        local parent, child = mapNameKey(first), mapNameKey(second)
        if not parent or not child then return end
        for _, pair in ipairs(atlas.sourceAddressParts or {}) do
            if (parent == mapNameKey(pair.parent) or parent == mapNameKey(pair.englishParent))
                and (child == mapNameKey(pair.child) or child == mapNameKey(pair.englishChild)) then
                local id = pair.childMap or pair.parentMap
                if id then return nativeMapInfo(id) and id or nil end
                return uniqueNamedMap(parent) -- Reviewed subzone with no separate UiMap.
            end
        end
        return uniqueNamedMap(mapNameKey(place)) or uniqueNamedMap(child, parent)
    end
    local key = mapNameKey(place)
    local function matches(id)
        local info = nativeMapInfo(id)
        return info and mapMatchesName(id, key, info) and id or nil
    end
    local active = matches(point and point.map)
    if active then return active end
    local reviewed = mount and routeMapNames[mount.id]
    if reviewed and mount.spell == reviewed.spell and nativeMapInfo(reviewed.map) then
        for _, name in ipairs(reviewed.names) do
            if key == mapNameKey(name) then return reviewed.map end
        end
    end
    local info = mount and not mount.difficultyLocalOnly and atlas.dropSourceInfo and atlas.dropSourceInfo[mount.id]
    local map = matches(mount and mount.sourceMap) or matches(info and info.map)
        or uniqueNamedMap(key)
    if map then return map end
    local name, parent = place:match("^(.-)%s+%(([^()]+)%)$")
    if not name then name, parent = place:match("^([^,]+),%s*([^,]+)$") end
    local nameKey, parentKey = mapNameKey(name), mapNameKey(parent)
    if nameKey and parentKey then return uniqueNamedMap(nameKey, parentKey) end
end

function atlas.openMap(id)
    if type(OpenWorldMap) ~= "function" or not nativeMapInfo(id) then return false end
    local disabled = Enum and Enum.GameRule and Enum.GameRule.WorldMapDisabled
    if disabled and C_GameRules and C_GameRules.IsGameRuleActive and C_GameRules.IsGameRuleActive(disabled) then return false end
    local opened, result = pcall(OpenWorldMap, id)
    return opened and result ~= false
end

function atlas.hasSourceCoordinates(point)
    return point and type(point.map) == "number" and point.map > 0 and point.map % 1 == 0
        and type(point.x) == "number" and point.x >= 0 and point.x <= 1
        and type(point.y) == "number" and point.y >= 0 and point.y <= 1
end

function atlas.tomTomAvailable()
    return type(TomTom) == "table" and type(TomTom.AddWaypoint) == "function"
end

function atlas.waypointPreference()
    local account = MountAtlasAccountDB
    local settings = type(account) == "table" and account.settings
    local preference = type(settings) == "table" and settings.waypointProvider
    if preference == "wow" or preference == "tomtom" then return preference end
end

function atlas.waypointProvider()
    if atlas.waypointPreference() ~= "wow" and atlas.tomTomAvailable() then return "tomtom" end
    return "wow"
end

function atlas.setWaypointProvider(provider)
    if provider ~= "wow" and provider ~= "tomtom" then return false end
    if type(MountAtlasAccountDB) ~= "table" then MountAtlasAccountDB = {} end
    local account = MountAtlasAccountDB
    if type(account.settings) ~= "table" then account.settings = {} end
    account.settings.waypointProvider = provider
    return true
end

function atlas.hasTomTomWaypoints()
    return atlas.waypointProvider() == "tomtom"
end

function atlas.bulkWaypointUnavailableText()
    return atlas.L(atlas.tomTomAvailable() and "Для нескольких меток выбери TomTom" or "Для нескольких меток нужен TomTom")
end

function atlas.addSourceWaypoints(points)
    if not atlas.hasTomTomWaypoints() then return 0 end
    local count, seen = 0, {}
    for _, point in ipairs(points) do
        if point.navigation ~= false and atlas.hasSourceCoordinates(point) then
            local key = ("%d:%.17g:%.17g"):format(point.map, point.x, point.y)
            if not seen[key] then
                seen[key] = true
                local title = atlas.displayName(point.englishBoss and atlas.getLocale() == "enUS" and point.englishBoss or point.boss or point.name, "target")
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

    if point and point.navigation == false then return end
    if not atlas.hasSourceCoordinates(point) then return atlas.L("Точная точка неизвестна.") end
    local boss = atlas.displayName(point.englishBoss and atlas.getLocale() == "enUS" and point.englishBoss or point.boss or point.name, "target")
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
    if C_Map and C_Map.CanSetUserWaypointOnMap and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
        and C_Map.CanSetUserWaypointOnMap(point.map)
        and C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(point.map, point.x, point.y)) then
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
        return atlas.L("Метка карты · %s", destination)
    end
    return atlas.L("Ориентир · %s · %s", atlas.displayName(point.place), destination)
end
