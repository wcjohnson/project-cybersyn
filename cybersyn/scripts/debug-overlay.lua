---@class Cybersyn.Internal.DebugOverlayState
---@field public comb_overlays {[UnitNumber]: LuaRenderObject}
---@field public stop_overlays {[UnitNumber]: LuaRenderObject}
---@field public bbox_overlay LuaRenderObject?

---Clear all debug overlays.
local function clear_overlays()
	local ovl_data = (storage --[[@as MapData]]).debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	for _, ovl in pairs(ovl_data.comb_overlays or {}) do ovl.destroy() end
	for _, ovl in pairs(ovl_data.stop_overlays or {}) do ovl.destroy() end
	if ovl_data.bbox_overlay then ovl_data.bbox_overlay.destroy() end
	(storage --[[@as MapData]]).debug_overlay = nil
end

---@param combinator Cybersyn.Combinator
---@return LuaRenderObject?
local function get_or_create_combinator_overlay(combinator)
	local ovl_data = (storage --[[@as MapData]]).debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	local overlay = ovl_data.comb_overlays[combinator.id]
	if not overlay then
		if not combinator_api.is_valid(combinator) then return end
		overlay = rendering.draw_text({
			text = "",
			surface = combinator.entity.surface,
			target = { entity = combinator.entity, offset = { 0, 0 } },
			color = { r = 1, g = 1, b = 1 },
			use_rich_text = true,
			alignment = "center",
		})
		ovl_data.comb_overlays[combinator.id] = overlay
	end
	return overlay
end

---@param combinator Cybersyn.Combinator
local function destroy_combinator_overlay(combinator)
	local ovl_data = (storage --[[@as MapData]]).debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	local overlay = ovl_data.comb_overlays[combinator.id]
	if overlay then
		overlay.destroy()
		ovl_data.comb_overlays[combinator.id] = nil
	end
end

---@param stop Cybersyn.TrainStop
---@return LuaRenderObject?
local function get_or_create_stop_overlay(stop)
	local ovl_data = (storage --[[@as MapData]]).debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	local overlay = ovl_data.stop_overlays[stop.id]
	if not overlay then
		if not stop_api.is_valid(stop) then return end
		overlay = rendering.draw_text({
			text = "",
			surface = stop.entity.surface,
			target = { entity = stop.entity, offset = { 0, -2 } },
			color = { r = 1, g = 1, b = 1 },
			use_rich_text = true,
			alignment = "center",
		})
		ovl_data.stop_overlays[stop.id] = overlay
	end
	return overlay
end

---@param stop Cybersyn.TrainStop
local function destroy_stop_overlay(stop)
	local ovl_data = (storage --[[@as MapData]]).debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	local overlay = ovl_data.stop_overlays[stop.id]
	if overlay then
		overlay.destroy()
		ovl_data.stop_overlays[stop.id] = nil
	end
end

---@param dir defines.direction
local function dir_to_string(dir)
	if dir == defines.direction.north then
		return "N"
	elseif dir == defines.direction.east then
		return "E"
	elseif dir == defines.direction.south then
		return "S"
	elseif dir == defines.direction.west then
		return "W"
	end
	return "?"
end

---@param combinator Cybersyn.Combinator
local function update_combinator_overlay(combinator)
	local overlay = get_or_create_combinator_overlay(combinator)
	if overlay then
		local items = { "[item=cybersyn-combinator]", combinator.id, " " }
		if combinator.stop_id then
			table.insert(items, "[item=train-stop]")
			table.insert(items, combinator.stop_id)
			table.insert(items, " ")
			table.insert(items, tostring(combinator.distance))
			table.insert(items, " ")
		end
		if combinator_api.is_valid(combinator) then
			table.insert(items, dir_to_string(combinator.entity.direction))
		end
		overlay.text = table.concat(items)
	end
end

---@param stop Cybersyn.TrainStop
local function update_stop_overlay(stop)
	local overlay = get_or_create_stop_overlay(stop)
	if overlay then
		local items = { "[item=train-stop]", stop.id, " " }
		for comb_id in pairs(stop.combinator_set) do
			table.insert(items, "[item=cybersyn-combinator]")
			table.insert(items, comb_id)
			table.insert(items, " ")
		end
		if stop_api.is_valid(stop) then
			table.insert(items, dir_to_string(stop.entity.direction))
		end
		overlay.text = table.concat(items)
	end
end

local function create_combinator_overlays()
	local map_data = (storage --[[@as MapData]])
	local ovl_data = map_data.debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	for _, combinator in pairs(map_data.combinators) do
		update_combinator_overlay(combinator)
	end
end

local function create_stop_overlays()
	local map_data = (storage --[[@as MapData]])
	local ovl_data = map_data.debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	for _, stop in pairs(map_data.train_stops) do
		update_stop_overlay(stop)
	end
end

local function create_all_overlays()
	create_combinator_overlays()
	create_stop_overlays()
end

local function enable_overlays()
	local ovl_data = (storage --[[@as MapData]]).debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then
		storage.debug_overlay = {
			comb_overlays = {},
			stop_overlays = {},
		}
		ovl_data = storage.debug_overlay
		create_all_overlays()
	end
end

local function enable_or_disable_overlays()
	if mod_settings.enable_debug_overlay then
		enable_overlays()
	else
		clear_overlays()
	end
end

on_mod_settings_changed(enable_or_disable_overlays)
on_game_on_init(enable_or_disable_overlays)
on_train_stop_layout_pre_scan(function(state)
	local ovl_data = (storage --[[@as MapData]]).debug_overlay --[[@as Cybersyn.Internal.DebugOverlayState]]
	if not ovl_data then return end
	if ovl_data.bbox_overlay then ovl_data.bbox_overlay.destroy() end
	local l, t, r, b = bbox_get(state.bbox)
	ovl_data.bbox_overlay = rendering.draw_rectangle({
		surface = state.stop.entity.surface,
		left_top = { l, t },
		right_bottom = { r, b },
		color = { r = 100, g = 149, b = 237 },
		width = 2,
	})
end)
on_combinator_destroyed(destroy_combinator_overlay)
on_combinator_created(update_combinator_overlay)
on_combinator_associated(function(combinator)
	update_combinator_overlay(combinator)
	local l, t, r, b = bbox_get(combinator.entity.bounding_box)
	rendering.draw_rectangle({
		color = { r = 0, g = 1, b = 1, a = 0.5 },
		left_top = { l, t },
		right_bottom = { r, b },
		surface = combinator.entity.surface,
		time_to_live = 300,
	})
end)
on_combinator_disassociated(update_combinator_overlay)
on_train_stop_destroyed(destroy_stop_overlay)
on_train_stop_created(update_stop_overlay)
on_train_stop_combinator_set_changed(update_stop_overlay)
