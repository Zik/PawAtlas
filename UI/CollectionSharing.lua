local _, atlas = ...

function atlas.openSharedCollection(owner)
    if type(owner) ~= "string" or owner == "" then return end
    local request = atlas.showSharedCatalog(owner)
    atlas.requestSharedCollection(owner, function(snapshot)
        atlas.finishSharedCatalog(request, snapshot)
    end)
end
