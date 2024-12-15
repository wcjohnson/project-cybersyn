--By Mami
require("scripts.types")
require("scripts.constants")
require("scripts.events")
require("scripts.commands")
require("scripts.global")
require("scripts.lib")
require("scripts.combinator.base")
require("scripts.combinator.settings")
require("scripts.combinator.state")
require("scripts.combinator.lifecycle")
require("scripts.stop.base")
require("scripts.stop.lifecycle")
require("scripts.stop.layout")
require("scripts.factorio-api")
require("scripts.layout")
require("scripts.central-planning")
require("scripts.train-events")
require("scripts.gui")
require("scripts.debug-overlay")
require("scripts.migrations")
require("scripts.main")
require("scripts.remote-interface")

-- Enable support for the Global Variable Viewer debugging mod, if it is
-- installed.
if script.active_mods["gvv"] then require("__gvv__.gvv")() end
