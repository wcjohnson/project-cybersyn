-- Registration and manipulation of combinator settings.

local bit_extract = bit32.extract
local bit_replace = bit32.replace

---@alias Cybersyn.Combinator.SettingValue any

---@enum Cybersyn.Combinator.SettingValueType The type of value that a given setting can store.
combinator_api.SettingValueType = {
	UNKNOWN = 0,
	BOOLEAN = 1,
	INTEGER = 2,
	STRING = 3,
	-- A Factorio signal, possibly stored natively on the combinator.
	SIGNAL = 4,
	-- A Factorio `Tags` table: `table<string, string|boolean|number|Tags>`
	TAGS = 5,
}

---@alias Cybersyn.Combinator.SettingReader fun(definition: Cybersyn.Combinator.SettingDefinition, settings: Cybersyn.Combinator.Settings): Cybersyn.Combinator.SettingValue? Reads a setting from a combinator. `nil` return value indicates the setting was absent.
---@alias Cybersyn.Combinator.SettingWriter fun(definition: Cybersyn.Combinator.SettingDefinition, settings: Cybersyn.Combinator.Settings, value: Cybersyn.Combinator.SettingValue?): boolean, any, any Writes a setting to a combinator. Returns `true` if the write was successful.

---@class Cybersyn.Combinator.SettingDefinition Definition of a setting that can be stored on a Cybersyn combinator.
---@field public name string The unique name of the setting.
---@field public value_type Cybersyn.Combinator.SettingValueType The type of value that this setting can store.
---@field public reader Cybersyn.Combinator.SettingReader The function used to read this setting from a combinator.
---@field public writer Cybersyn.Combinator.SettingWriter? The function used to write this setting to a combinator.
---@field public bit_index? uint The index of this setting in a bitfield, if applicable.
---@field public bit_width? uint The width of this setting in a bitfield, if applicable.

if not combinator_api.settings then
	combinator_api.settings = {} --[[@as {[string]: Cybersyn.Combinator.SettingDefinition}]]
end

---Read the value of a combinator setting.
---@param combinator Cybersyn.Combinator.Settings
---@param setting Cybersyn.Combinator.SettingDefinition
---@return any value The value of the setting.
function combinator_api.read_setting(combinator, setting)
	return setting.reader(setting, combinator)
end

---Change the value of a combinator setting.
---@param combinator Cybersyn.Combinator.Settings
---@param setting Cybersyn.Combinator.SettingDefinition
---@param value Cybersyn.Combinator.SettingValue
---@param skip_event boolean? If `true`, the setting changed event will not be raised.
---@return boolean was_written `true` if a changed value was written.
function combinator_api.write_setting(combinator, setting, value, skip_event)
	local writer = setting.writer
	if not writer then return false end
	local written, new_value, old_value = writer(setting, combinator, value)
	if written and (not skip_event) then
		raise_combinator_setting_changed(combinator, setting.name, new_value, old_value)
	end
	return written
end

---@param definition Cybersyn.Combinator.SettingDefinition
function combinator_api.register_setting(definition)
	local name = definition.name
	if combinator_api.settings[name] then
		return false
	end
	combinator_api.settings[name] = definition
	return true
end

---@param op string?
local function op_to_mode(op)
	if op == "*" then
		return "unknown"
	elseif op == "/" or op == "^" or op == "<<" then
		return "station"
	elseif op == "%" then
		return "station_control"
	elseif op == "+" then
		return "depot"
	elseif op == "-" then
		return "wagon_control"
	elseif op == ">>" then
		return "refueler"
	else
		return "unknown"
	end
end

---@param mode string
local function mode_to_op(mode)
	if mode == "station" then
		return "/"
	elseif mode == "station_control" then
		return "%"
	elseif mode == "depot" then
		return "+"
	elseif mode == "wagon_control" then
		return "-"
	elseif mode == "refueler" then
		return ">>"
	else
		return "*"
	end
end

---@param name string
---@param legacy_bit_index uint?
---@param legacy_bit_width uint?
---@return Cybersyn.Combinator.SettingDefinition
local function packed_int_setting(name, legacy_bit_index, legacy_bit_width)
	---@type Cybersyn.Combinator.SettingDefinition
	local def = {
		name = name,
		value_type = combinator_api.SettingValueType.INTEGER,
		bit_index = legacy_bit_index,
		bit_width = legacy_bit_width,
		reader = function(definition, settings)
			if legacy_bit_index and combinator_api.is_legacy(settings) then
				local params = settings.legacy_control_behavior.parameters
				if not params then return 0 end
				local bits = params.second_constant or 0
				return bit_extract(bits, legacy_bit_index, legacy_bit_width)
			end
			return 0
		end,
		writer = function(definition, settings, new_value)
			if legacy_bit_index and combinator_api.is_legacy(settings) then
				local params = settings.legacy_control_behavior.parameters
				if not params then return false end
				local bits = params.second_constant or 0
				local old_value = bit_extract(bits, legacy_bit_index, legacy_bit_width)
				if old_value ~= new_value then
					local new_bits = bit_replace(bits, new_value, legacy_bit_index, legacy_bit_width)
					params.second_constant = new_bits
					settings.legacy_control_behavior.parameters = params
					return true, new_value, old_value
				end
			end
			return false
		end,
	}
	return def
end

---@param name string
---@param legacy_bit_index uint?
---@return Cybersyn.Combinator.SettingDefinition
local function flag_setting(name, legacy_bit_index)
	---@type Cybersyn.Combinator.SettingDefinition
	local def = {
		name = name,
		value_type = combinator_api.SettingValueType.BOOLEAN,
		bit_index = legacy_bit_index,
		reader = function(definition, settings)
			if legacy_bit_index and combinator_api.is_legacy(settings) then
				local params = settings.legacy_control_behavior.parameters
				if not params then return false end
				local bits = params.second_constant or 0
				return (bit_extract(bits, legacy_bit_index, 1) ~= 0)
			end
			return false
		end,
		writer = function(definition, settings, new_value)
			if legacy_bit_index and combinator_api.is_legacy(settings) then
				local params = settings.legacy_control_behavior.parameters
				if not params then return false end
				local stored_value = new_value and 1 or 0
				local bits = params.second_constant or 0
				local old_value = bit_extract(bits, legacy_bit_index, 1)
				if old_value ~= stored_value then
					local new_bits = bit_replace(bits, stored_value, legacy_bit_index, 1)
					params.second_constant = new_bits
					settings.legacy_control_behavior.parameters = params
					return true, new_value, (old_value ~= 0)
				end
			end
			return false
		end,
	}
	return def
end

--- Register Cybersyn's combinator settings.
combinator_api.register_setting({
	name = "mode",
	value_type = combinator_api.SettingValueType.STRING,
	reader = function(definition, settings)
		if combinator_api.is_legacy(settings) then
			local params = settings.legacy_control_behavior.parameters
			if not params then return "unknown" end
			return op_to_mode(params.operation)
		end
		return "unknown"
	end,
	writer = function(definition, settings, new_mode)
		if combinator_api.is_legacy(settings) then
			local params = settings.legacy_control_behavior.parameters
			if not params then return false end
			local old_mode = op_to_mode(params.operation)
			if new_mode ~= old_mode then
				params.operation = mode_to_op(new_mode)
				settings.legacy_control_behavior.parameters = params
				return true, new_mode, old_mode
			end
		end
		return false
	end,
})

combinator_api.register_setting({
	name = "network_signal",
	value_type = combinator_api.SettingValueType.SIGNAL,
	reader = function(definition, settings)
		if combinator_api.is_legacy(settings) then
			local params = settings.legacy_control_behavior.parameters
			if not params then return nil end
			return params.first_signal
		end
		return nil
	end,
	writer = function(definition, settings, new_signal)
		if combinator_api.is_legacy(settings) then
			local params = settings.legacy_control_behavior.parameters
			if not params then return false end
			local old_signal = params.first_signal
			if not signal_eq(new_signal, old_signal) then
				params.first_signal = new_signal
				settings.legacy_control_behavior.parameters = params
				return true, new_signal, old_signal
			end
		end
		return false
	end,
})

combinator_api.register_setting(packed_int_setting("pr", 0, 2))
combinator_api.register_setting(flag_setting("disable_allow_list", 2))
combinator_api.register_setting(flag_setting("use_stack_thresholds", 3))
combinator_api.register_setting(flag_setting("enable_inactivity_condition", 4))
combinator_api.register_setting(flag_setting("use_any_depot", 5))
combinator_api.register_setting(flag_setting("disable_depot_bypass", 6))
combinator_api.register_setting(flag_setting("enable_slot_barring", 7))
combinator_api.register_setting(flag_setting("enable_circuit_condition", 8))
combinator_api.register_setting(flag_setting("enable_train_count", 9))
combinator_api.register_setting(flag_setting("enable_manual_inventory", 10))
