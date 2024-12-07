local bit_extract = bit32.extract
local bit_replace = bit32.replace

local events = require("scripts.events")

local raise_combinator_setting_changed = events.raise_combinator_setting_changed

-- API and abstraction layer for working with Cybernetic Combinators.
local combinator_api = {}

---@alias Cybersyn.Combinator.SettingReader fun(settings: Cybersyn.Combinator.Settings): any? Read a setting from a combinator. `nil` return value indicates the setting was absent.
---@alias Cybersyn.Combinator.SettingWriter fun(settings: Cybersyn.Combinator.Settings, value: any?): boolean Write a setting to a combinator. A `nil` value will either clear the setting or reset it to a default, depending on the setting's implementation.

---@class (exact) Cybersyn.Combinator.SettingDefinition Definition of a setting persistently stored on a Cybernetic Combinator. Settings must be fully accessible while the combinator is a ghost.
---@field public name string The name of the setting. Must correspond to the setting's table key in `combinator_api.settings`.
---@field public legacy boolean? If true, this setting is a legacy setting read from the original Cybersyn arithmetic combinator control behavior.
---@field public read Cybersyn.Combinator.SettingReader Read this setting from a combinator.
---@field public write Cybersyn.Combinator.SettingWriter? Write a new value to this setting on a combinator. If the `write` method is absent, the setting is read only.

---@enum Cybersyn.Combinator.Mode Possible modes of a Cybernetic Combinator.
local Mode = {
	UNKNOWN = 0,
	LEGACY_STATION = 1,
	LEGACY_STATION_CONTROL = 2,
	LEGACY_DEPOT = 3,
	LEGACY_WAGON = 4,
	LEGACY_REFUELER = 5,
}
combinator_api.Mode = Mode

--- Get access to combinator settings from basic combinator data. The combinator is allowed to be a ghost.
---@param combinator Cybersyn.Combinator.GhostRef
---@return Cybersyn.Combinator.Settings
function combinator_api.get_settings(combinator)
	local behavior = combinator.legacy and
			combinator.legacy.get_or_create_control_behavior() --[[@as LuaArithmeticCombinatorControlBehavior]]
	local parameters = behavior and behavior.parameters
	return {
		combinator = combinator,
		legacy_control_behavior = behavior,
		legacy_parameters = parameters,
		map_data = storage,
	}
end

---@param bit_index uint The index of the bit to read from the legacy flags.
---@return Cybersyn.Combinator.SettingReader
local function flag_reader(bit_index)
	return function(combinator)
		local params = combinator.legacy_parameters
		if not params then return false end
		local bits = params.second_constant or 0
		return bit_extract(bits, bit_index) > 0
	end
end

---@param setting_name string Name of the setting; must correspond to the key in `combinator_api.settings`.
---@param bit_index uint The index of the bit to write to the legacy flags.
---@return Cybersyn.Combinator.SettingWriter
local function flag_writer(setting_name, bit_index)
	return function(combinator, value)
		local params = combinator.legacy_parameters
		if not params then return false end
		local bits = params.second_constant or 0
		local new_bits = bit_replace(bits, value and 1 or 0, bit_index)
		if new_bits ~= bits then
			params.second_constant = new_bits
			combinator.legacy_control_behavior.parameters = params
			raise_combinator_setting_changed(combinator, setting_name, value)
		end
		return true
	end
end

---Generate data for a legacy flag setting.
---@param setting_name string Name of the setting; must correspond to the key in `combinator_api.settings`.
---@param bit_index uint The index of the bit in the legacy flags.
---@return Cybersyn.Combinator.SettingDefinition
local function legacy_flag(setting_name, bit_index)
	return {
		name = setting_name,
		legacy = true,
		read = flag_reader(bit_index),
		write = flag_writer(setting_name, bit_index),
	}
end

---@type { [string]: Cybersyn.Combinator.SettingDefinition }
combinator_api.settings = {
	mode = {
		name = "mode",
		legacy = true,
		read = function(combinator)
			local params = combinator.legacy_parameters
			if not params then return Mode.UNKNOWN end
			if params.operation == "*" then
				return Mode.UNKNOWN
			elseif params.operation == "/" or params.operation == "^" or params.operation == "<<" then
				return Mode.LEGACY_STATION
			elseif params.operation == "%" then
				return Mode.LEGACY_STATION_CONTROL
			elseif params.operation == "+" then
				return Mode.LEGACY_DEPOT
			elseif params.operation == "-" then
				return Mode.LEGACY_WAGON
			elseif params.operation == ">>" then
				return Mode.LEGACY_REFUELER
			else
				return Mode.UNKNOWN
			end
		end,
		write = function(combinator, value)
			local params = combinator.legacy_parameters
			if not params then return false end
			local new_operation = "*"
			if value == Mode.UNKNOWN then
				new_operation = "*"
			elseif value == Mode.LEGACY_STATION then
				new_operation = "/"
			elseif value == Mode.LEGACY_STATION_CONTROL then
				new_operation = "%"
			elseif value == Mode.LEGACY_DEPOT then
				new_operation = "+"
			elseif value == Mode.LEGACY_WAGON then
				new_operation = "-"
			elseif value == Mode.LEGACY_REFUELER then
				new_operation = ">>"
			else
				new_operation = "*"
			end
			if new_operation ~= params.operation then
				params.operation = new_operation
				combinator.legacy_control_behavior.parameters = params
				raise_combinator_setting_changed(combinator, "mode", value)
			end
			return true
		end,
	},
	network_signal = {
		name = "network_signal",
		legacy = true,
		read = function(combinator)
			local params = combinator.legacy_parameters
			if not params then return nil end
			return params.first_signal
		end,
		write = function(combinator, value)
			local params = combinator.legacy_parameters
			if not params then return false end
			params.first_signal = value
			combinator.legacy_control_behavior.parameters = params
			raise_combinator_setting_changed(combinator, "network_signal", value)
			return true
		end,
	},
	provide_or_request = {
		name = "provide_or_request",
		legacy = true,
		read = function(combinator)
			local params = combinator.legacy_parameters
			if not params then return false end
			local bits = params.second_constant or 0
			return bit_extract(bits, 0, 2)
		end,
		write = function(combinator, value)
			local params = combinator.legacy_parameters
			if not params then return false end
			local bits = params.second_constant or 0
			local new_bits = bit_replace(bits, value, 0, 2)
			if new_bits ~= bits then
				params.second_constant = new_bits
				combinator.legacy_control_behavior.parameters = params
				raise_combinator_setting_changed(combinator, "provide_or_request", value)
			end
			return true
		end,
	},
	disable_allow_list = legacy_flag("disable_allow_list", 2),
	use_stack_thresholds = legacy_flag("use_stack_thresholds", 3),
	enable_inactivity_condition = legacy_flag("enable_inactivity_condition", 4),
	use_any_depot = legacy_flag("use_any_depot", 5),
	disable_depot_bypass = legacy_flag("disable_depot_bypass", 6),
	enable_slot_barring = legacy_flag("enable_slot_barring", 7),
	enable_circuit_condition = legacy_flag("enable_circuit_condition", 8),
	enable_train_count = legacy_flag("enable_train_count", 9),
	enable_manual_inventory = legacy_flag("enable_manual_inventory", 10),
}

---@param combinator Cybersyn.Combinator.GhostRef?
---@return boolean? `true` if the combinator is a valid entity OR ghost, falsy value otherwise.
local function is_valid(combinator)
	return combinator and combinator.legacy and combinator.legacy.valid
end
combinator_api.is_valid = is_valid

---@param combinator Cybersyn.Combinator.GhostRef
---@return boolean is_ghost `true` if the combinator is a ghost, `false` if it is a physical entity or invalid.
---@return boolean is_valid `true` if the combinator is a valid entity OR ghost, `false` otherwise.
function combinator_api.is_ghost(combinator)
	if (not combinator) or (not combinator.legacy) or (not combinator.legacy.valid) then return false, false end
	if combinator.legacy.name == "entity-ghost" then return true, true else return false, true end
end

---Downcast a ghost reference into a stateful reference. Only works if the
---referenced combinator is alive and has internal Cybersyn state.
---@param ghost_ref Cybersyn.Combinator.GhostRef
---@param map_data MapData
---@return Cybersyn.Combinator.StatefulRef?
function combinator_api.to_stateful_ref(ghost_ref, map_data)
	if not is_valid(ghost_ref) then return end
	return map_data.combinators[ghost_ref.legacy.unit_number]
end

--- Get a `GhostRef` to the validated combinator the given player has open in the GUI, if it exists.
---@param map_data MapData
---@param player_index Cybersyn.PlayerIndex Index of player to check.
---@return Cybersyn.Combinator.GhostRef? combinator The validated combinator the player is interacting with, or `nil` if the player is not interacting with a valid combinator.
---@return LuaPlayer? player The player object, if valid.
function combinator_api.get_open_combinator_for_player(map_data, player_index)
	local player = game.get_player(player_index)
	if not player then return end
	local comb = map_data.open_combinators[player_index]
	if not is_valid(comb) then return nil, player end
	return comb, player
end

---@param stateful_ref Cybersyn.Combinator.StatefulRef? A valid stateful combinator reference, or `nil`.
---@return LuaEntity? train_stop The associated train stop if extant and valid, or `nil`.
function combinator_api.get_associated_train_stop(stateful_ref)
	if not stateful_ref then return end
	if stateful_ref.stop and stateful_ref.stop.valid then return stateful_ref.stop end
end

---@param combinator LuaEntity Valid combinator entity.
---@return Cybersyn.Combinator.GhostRef
function combinator_api.legacy_combinator_to_ghost_ref(combinator)
	return {
		legacy = combinator,
	}
end

--- Get the Factorio `entity_status` of the combinator's main entity.
---@param combinator Cybersyn.Combinator.GhostRef Valid combinator ref.
function combinator_api.get_factorio_status(combinator)
	return combinator.legacy.status
end

--- Get the Factorio `unit_number` of the combinator's main entity.
---@param combinator Cybersyn.Combinator.GhostRef Valid combinator ref.
---@return Cybersyn.UnitNumber
function combinator_api.get_unit_number(combinator)
	return combinator.legacy.unit_number
end

--- Get a `StatefulRef` given the unit number of a real combinator.
---@param unit_number Cybersyn.UnitNumber
---@param map_data MapData
---@return Cybersyn.Combinator.StatefulRef?
function combinator_api.unit_number_to_stateful_ref(unit_number, map_data)
	return map_data.combinators[unit_number]
end

return combinator_api
