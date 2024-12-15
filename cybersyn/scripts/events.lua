-- Don't allow this file to be required multiple times, as it may create
-- phantom isolated copies of the event system.
if _G._require_guard_events then
	return
else
	_G._require_guard_events = true
end

local ipairs = ipairs
local filter_in_place = filter_in_place

---@enum Cybersyn.EventMetaOperation
EventMetaOperation = {
	REMOVE_HANDLER = 1,
	COUNT_HANDLERS = 2,
}

---Create an event.
---@generic T1, T2, T3, T4, T5
---@param name string The name of the event
---@param p1 `T1` Unused, but required for type inference
---@param p2 `T2` Unused, but required for type inference
---@param p3 `T3` Unused, but required for type inference
---@param p4 `T4` Unused, but required for type inference
---@param p5 `T5` Unused, but required for type inference
---@return fun(handler: fun(p1: T1, p2: T2, p3: T3, p4: T4, p5: T5)) on Register a handler for the event
---@return fun(p1: T1, p2: T2, p3: T3, p4: T4, p5: T5) raise Raise the event
---@return fun(operation: Cybersyn.EventMetaOperation, ...): any meta Execute a meta operation on the event.
local function event(name, p1, p2, p3, p4, p5)
	local bindings = {}
	local function on(f)
		bindings[#bindings + 1] = f
		raise_event_meta(name, #bindings)
	end
	local function raise(...)
		-- LORD: remove this
		if (game) then
			local arg1 = select(1, ...)
			if type(arg1) == "nil" or type(arg1) == "number" or type(arg1) == "string" or type(arg) == "boolean" then
				arg1 = tostring(arg1)
			else
				arg1 = serpent.line(arg1)
			end

			game.print(
				"DEBUG: Event raised: " ..
				name .. " " .. arg1,
				{ skip = defines.print_skip.never }
			)
		end
		for _, f in ipairs(bindings) do
			f(...)
		end
	end
	local function meta(op, f)
		if op == EventMetaOperation.REMOVE_HANDLER then
			local n = #bindings
			filter_in_place(bindings, function(g) return g ~= f end)
			if #bindings ~= n then
				raise_event_meta(name, #bindings)
				return true
			else
				return false
			end
		elseif op == EventMetaOperation.COUNT_HANDLERS then
			return #bindings
		end
	end
	return on, raise, meta
end

-- Event raised when the bindings of another event change.
-- - Arg 1 - `string` - name of the event whose bindings changed
-- - Arg 2 - `integer` - current number of bindings to the event
on_event_meta, raise_event_meta, meta_event_meta = event("event_meta",
	"string", "integer", "nil", "nil", "nil")

-- Event raised when a setting is changed on either an ephemeral or real
-- combinator.
-- - Arg 1 - `Cybersyn.Combinator.Settings` - reference to the combinator or ghost whose setting changed
-- - Arg 2 - `string` - the name of the setting that changed
-- - Arg 3 - `any` - the new value of the setting
-- - Arg 4 - `any` - the old value of the setting
on_combinator_setting_changed, raise_combinator_setting_changed, meta_combinator_setting_changed = event(
	"combinator_setting_changed",
	"Cybersyn.Combinator.Settings", "string", "any", "any", "nil")

-- Event raised when combinator or ghost settings are changed en masse. For performance
-- reasons, no attempt is made to diff against prior settings. Consumers of
-- this event should be aware that any or no settings may have changed.
on_combinator_settings_written, raise_combinator_settings_written, meta_combinator_settings_written = event(
	"combinator_settings_written",
	"Cybersyn.Combinator.Ephemeral", "nil", "nil", "nil", "nil")

-- Event raised when a state is updated on a live combinator.
-- For performance reasons, states are not compared to old states. Consumers of
-- this event should be aware that any or no states may have changed.
-- - Arg 1 - `Cybersyn.Combinator` - reference to the combinator whose state changed
-- - Arg 2 - `string` - the name of the state value that changed
-- - Arg 3 - `any` - the raw value passed to the state writer
on_combinator_state_written, raise_combinator_state_written, meta_combinator_state_written = event(
	"combinator_state_written",
	"Cybersyn.Combinator", "string", "any", "nil", "nil")

-- Event raised when runtime mod settings change. The `mod_settings` global
-- is updated before this event is raised.
on_mod_settings_changed, raise_mod_settings_changed, meta_mod_settings_changed = event(
	"mod_settings_changed",
	"nil", "nil", "nil", "nil", "nil")

-- Event raised when a train stop is being removed from Cybersyn state. At
-- this point, the stop state still exists, but it will be destroyed
-- synchronously after this event is handled.
on_train_stop_destroyed, raise_train_stop_destroyed, meta_train_stop_destroyed = event(
	"train_stop_destroyed",
	"Cybersyn.TrainStop", "nil", "nil", "nil", "nil")

-- Event raised when a train stop is created in Cybersyn state.
on_train_stop_created, raise_train_stop_created, meta_train_stop_created = event(
	"train_stop_created",
	"Cybersyn.TrainStop", "nil", "nil", "nil", "nil")

-- Event raised after a train stop is created and all nearby combinators are associated.
on_train_stop_post_created, raise_train_stop_post_created, meta_train_stop_post_created = event(
	"train_stop_post_created",
	"Cybersyn.TrainStop", "nil", "nil", "nil", "nil")

-- Event raised when a combinator becomes associated with a train stop.
on_combinator_associated, raise_combinator_associated, meta_combinator_associated = event(
	"combinator_associated",
	"Cybersyn.Combinator", "Cybersyn.TrainStop", "nil", "nil", "nil")

-- Event raised after a combinator is disassociated from a train stop. Note
-- that the stop OR combinator may be in the process of being destroyed.
on_combinator_disassociated, raise_combinator_disassociated, meta_combinator_disassociated = event(
	"combinator_disassociated",
	"Cybersyn.Combinator", "Cybersyn.TrainStop", "nil", "nil", "nil")

-- Event raised when the set of combinators associated to a train stop changes.
-- Note that the train stop may be in the process of being destroyed.
on_train_stop_combinator_set_changed, raise_train_stop_combinator_set_changed, meta_train_stop_combinator_set_changed =
		event(
			"train_stop_combinator_set_changed",
			"Cybersyn.TrainStop", "nil", "nil", "nil", "nil")

-- Event raised when a combinator is being removed from state. At this point, the combinator
-- state still exists, but it will be destroyed synchronously after this event.
on_combinator_destroyed, raise_combinator_destroyed, meta_combinator_destroyed = event(
	"combinator_destroyed",
	"Cybersyn.Combinator", "nil", "nil", "nil", "nil")

-- Event raised when a combinator is created in Cybersyn state.
on_combinator_created, raise_combinator_created, meta_combinator_created = event(
	"combinator_created",
	"Cybersyn.Combinator", "nil", "nil", "nil", "nil")

-- Event raised when a combinator ghost is destroyed.
on_combinator_ghost_destroyed, raise_combinator_ghost_destroyed, meta_combinator_ghost_destroyed = event(
	"combinator_ghost_destroyed",
	"Cybersyn.Combinator.Ephemeral", "nil", "nil", "nil", "nil")

-- Event raised when a combinator ghost is created.
on_combinator_ghost_created, raise_combinator_ghost_created, meta_combinator_ghost_created = event(
	"combinator_ghost_created",
	"Cybersyn.Combinator.Ephemeral", "nil", "nil", "nil", "nil")

-- Event raised when a combinator ghost is revived. Note that the ghost does not have a valid entity at this time; the passed unit number is the ID of the former ghost.
-- - Arg 1 - `UnitNumber` - the unit number of the ghost that was revived
-- - Arg 2 - `LuaEntity` - the entity that was built in place of the ghost
on_combinator_ghost_revived, raise_combinator_ghost_revived, meta_combinator_ghost_revived = event(
	"combinator_ghost_revived",
	"UnitNumber", "LuaEntity", "nil", "nil", "nil")

-- Event raised before a train stop's layout is scanned for equipment.
-- - Arg 1 - `Cybersyn.TrainStop` - the train stop whose layout is about to be scanned
-- - Arg 2 - `BoundingBox` - the area that will be scanned for equipment
on_train_stop_layout_pre_scan, raise_train_stop_layout_pre_scan, meta_train_stop_layout_pre_scan = event(
	"train_stop_layout_pre_scan",
	"Cybersyn.TrainStop.LayoutScanState", "nil", "nil", "nil", "nil")

-- Echoes the game's `on_init` event.
on_game_on_init, raise_game_on_init, meta_game_on_init = event(
	"game_on_init",
	"nil", "nil", "nil", "nil", "nil")
