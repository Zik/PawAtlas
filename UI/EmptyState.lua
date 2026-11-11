local _, atlas = ...
local ui = atlas.ui

function atlas.emptyCatalog(page, reset)
    local index = ui.place(CreateFrame("Frame", nil, page), page, 26, 212, 272, 240)
    local emblem = ui.icon(index, 104, 35, 64, "MinimapButton")
    emblem:SetAlpha(.45)
    local search = ui.icon(index, 117, 48, 38, "Search")
    search:SetAlpha(.65)
    local caption = ui.text(index, 16, 114, 240, 46, 16, "След пока не найден", ui.muted)
    caption:SetJustifyH("CENTER")
    local line = ui.fill(index, 76, 173, 120, 1, ui.rule)
    line:SetGradient("HORIZONTAL", CreateColor(.24, .31, .32, 0), CreateColor(.24, .31, .32, 1))

    local detail = ui.place(CreateFrame("Frame", nil, page), page, 340, 8, 668, 454)
    local mascot = detail:CreateTexture(nil, "BACKGROUND")
    ui.place(mascot, detail, 295, 51, 370, 370)
    mascot:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Illustrations\\Gryphon.tga")
    mascot:SetAlpha(.68)
    local thought = detail:CreateTexture(nil, "ARTWORK")
    ui.place(thought, detail, 180, -2, 240, 120)
    thought:SetTexture("Interface\\AddOns\\PawAtlas\\Media\\Controls\\ThoughtCloud.tga")
    local thoughtText = ui.text(detail, 212, 12, 176, 49, 17,
        "Так… а с этой\nстороны пусто!", { .94, .85, .65 })
    ui.setFont(thoughtText, 17, "Interface\\AddOns\\PawAtlas\\Media\\Fonts\\PTSans-Regular.ttf")
    thoughtText:SetJustifyH("CENTER")
    thoughtText:SetMaxLines(2)
    thoughtText:SetShadowOffset(0, 0)
    ui.text(detail, 30, 137, 285, 76, 26, "След пока не найден", ui.gold)
    ui.text(detail, 30, 214, 260, 64, 15, "Попробуй другое имя или сбрось фильтры", ui.muted)
    ui.action(detail, 30, 294, 226, 37, "Сбросить фильтры", nil, reset)
    index:Hide()
    detail:Hide()
    return function(shown) index:SetShown(shown); detail:SetShown(shown) end
end
