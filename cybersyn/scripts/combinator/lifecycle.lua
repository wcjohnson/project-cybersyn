-- Lifecycle management for combinators.
-- Combinator state is only created/destroyed in this module.

---Create a stored combinator state.
---@param combinator_entity LuaEntity A *valid* reference to a non-ghost combinator.
---@return Cybersyn.Combinator #The new combinator state.
function combinator_api.create_combinator_state(combinator_entity)
	local map_data = (storage --[[@as MapData]])
	local combinator_id = combinator_entity.unit_number
	if not combinator_id then
		-- Should be impossible.
		error("Combinator entity has no unit number.")
	end
	map_data.combinators[combinator_id] = {
		id = combinator_id,
		entity = combinator_entity,
	} --[[@as Cybersyn.Combinator]]

	return map_data.combinators[combinator_id]
end

---Destroy a stored combinator state.
---@param combinator_id UnitNumber
---@return boolean `true` if the combinator was removed, `false` if it was not found.
function combinator_api.destroy_combinator_state(combinator_id)
	local map_data = (storage --[[@as MapData]])
	if map_data.combinators[combinator_id] then
		map_data.combinators[combinator_id] = nil
		return true
	end
	return false
end

---@param comb_id UnitNumber
function combinator_api.destroy_combinator(comb_id)
	local comb = combinator_api.get_combinator_state(comb_id, true)
	if not comb then return end
	comb.is_being_destroyed = true

	local stop = stop_api.get_stop_state(comb.stop_id, true)
	comb.stop_id = nil
	local should_destroy_stop = false
	if stop then
		stop.combinator_set[comb_id] = nil
		raise_combinator_disassociated(comb, stop)
		raise_train_stop_combinator_set_changed(stop)
		if not next(stop.combinator_set) then
			-- Destroy the stop if there are no combinators left.
			should_destroy_stop = true
		end
	end

	raise_combinator_destroyed(comb)
	combinator_api.destroy_combinator_state(comb.id)
	if should_destroy_stop then
		---@diagnostic disable-next-line: need-check-nil
		stop_api.destroy_stop(stop.id)
	end
end

---@param comb_entity LuaEntity A *valid* combinator entity
function combinator_api.create_combinator(comb_entity)
	local comb_id = comb_entity.unit_number --[[@as UnitNumber]]
	local comb = combinator_api.get_combinator_state(comb_id, true)
	if comb then
		-- Should be impossible
		return
	end
	comb = combinator_api.create_combinator_state(comb_entity)
	raise_combinator_created(comb)
	stop_api.reassociate_combinators({ comb })
end

on_combinator_created(function(combinator)
	-- LORD: create hidden output entity
end)

on_combinator_destroyed(function(combinator)
	-- LORD: destroy hidden output entity
end)
