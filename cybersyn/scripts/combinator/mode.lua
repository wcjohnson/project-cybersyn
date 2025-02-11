---@class Cybersyn.Combinator.ModeRegistration
---@field name string The name of the mode, which must be unique. Used as the internal storage key for the mode.
---@field localized_string string The Factorio localized string for the mode.
---@field create_gui fun(parent: LuaGuiElement): nil Create gui elements representing the mode.
---@field update_gui fun(parent: LuaGuiElement, settings: Cybersyn.Combinator.Settings, changed_setting: string?): nil Update the combinator's gui elements. If `changed_setting` is given, can be used as a hint to update only the changed setting. If nil, the whole GUI should be updated.

---@type {[string]: Cybersyn.Combinator.ModeRegistration}
local modes = {}

---@type string[]
local mode_list = {}

---Register a new combinator mode.
---@param mode_registration Cybersyn.Combinator.ModeRegistration
function combinator_api.register_combinator_mode(mode_registration)
	local name = mode_registration.name
	if (not name) or modes[name] then
		return false
	end
	modes[name] = mode_registration
	table.insert(mode_list, name)
	return true
end

---Get a list of name keys of all combinator modes.
function combinator_api.get_combinator_mode_list()
	return mode_list
end

---Get a combinator mode by name.
---@param name string
function combinator_api.get_combinator_mode(name)
	return modes[name or ""]
end

combinator_api.register_combinator_mode({
	name = "station_control",
	localized_string = "cybersyn-gui.comb2",
	create_gui = function(parent)
	end,
	update_gui = function(parent, settings, changed_setting)
	end,
})

combinator_api.register_combinator_mode({
	name = "depot",
	localized_string = "cybersyn-gui.depot",
	create_gui = function(parent)
	end,
	update_gui = function(parent, settings, changed_setting)
	end,
})

combinator_api.register_combinator_mode({
	name = "refueler",
	localized_string = "cybersyn-gui.refueler",
	create_gui = function(parent)
	end,
	update_gui = function(parent, settings, changed_setting)
	end,
})

combinator_api.register_combinator_mode({
	name = "wagon_control",
	localized_string = "cybersyn-gui.wagon-manifest",
	create_gui = function(parent)
	end,
	update_gui = function(parent, settings, changed_setting)
	end,
})
