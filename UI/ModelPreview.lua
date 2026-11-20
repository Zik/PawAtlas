local _, atlas = ...

function atlas.bindModelPreview(parent)
    return function(widget, getMount)
        atlas.bindMountPreviewCursor(widget, getMount)
        widget.refreshModelPreview = function()
            atlas.refreshMountPreviewCursor(widget)
        end
    end
end
