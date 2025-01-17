local Dock = require("Dock")

local PluginImpl = {}
local Plugin = gdclass(nil, EditorPlugin)
    :Tool(true)
    :RegisterImpl(PluginImpl)

export type Plugin = EditorPlugin & typeof(PluginImpl) & {
    dock: Dock.Dock,
}

function PluginImpl._EnterTree(self: Plugin)
    self.dock = (assert(load("dock.tscn")) :: PackedScene):Instantiate() :: Dock.Dock
    self.dock.plugin = self
    self:AddControlToDock(EditorPlugin.DockSlot.RIGHT_UL, self.dock)
end

Plugin:RegisterMethod("_EnterTree")

function PluginImpl._ExitTree(self: Plugin)
    self:RemoveControlFromDocks(self.dock)
    self.dock:Free()
end

Plugin:RegisterMethod("_ExitTree")

return Plugin
