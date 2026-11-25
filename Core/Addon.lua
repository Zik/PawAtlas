local addonName, atlas = ...

LibStub("AceAddon-3.0"):NewAddon(atlas, addonName, "AceEvent-3.0", "AceConsole-3.0")

function atlas:OnInitialize()
    self.initializeTracking()
    self.initializeAttemptStages()
    if self.initializeIslandImports then self.initializeIslandImports() end
    if self.initializeGameTooltips then self.initializeGameTooltips() end
end
