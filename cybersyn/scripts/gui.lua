--By Mami
local flib_gui = require("__flib__.gui")

local combinator_api = require("scripts.combinator")
local is_combinator_ghost = combinator_api.is_ghost
local to_stateful_ref = combinator_api.to_stateful_ref
local get_open_combinator_for_player = combinator_api.get_open_combinator_for_player
local combinator_settings = combinator_api.settings
local get_settings = combinator_api.get_settings
local get_associated_train_stop = combinator_api.get_associated_train_stop
local Mode = combinator_api.Mode
local legacy_combinator_to_ghost_ref = combinator_api.legacy_combinator_to_ghost_ref

local RED = "utility/status_not_working"
local GREEN = "utility/status_working"
local YELLOW = "utility/status_yellow"

local STATUS_SPRITES = {}
STATUS_SPRITES[defines.entity_status.working] = GREEN
STATUS_SPRITES[defines.entity_status.normal] = GREEN
STATUS_SPRITES[defines.entity_status.no_power] = RED
STATUS_SPRITES[defines.entity_status.low_power] = YELLOW
STATUS_SPRITES[defines.entity_status.disabled_by_control_behavior] = RED
STATUS_SPRITES[defines.entity_status.disabled_by_script] = RED
STATUS_SPRITES[defines.entity_status.marked_for_deconstruction] = RED
local STATUS_SPRITES_DEFAULT = RED
local STATUS_SPRITES_GHOST = YELLOW

local STATUS_NAMES = {}
STATUS_NAMES[defines.entity_status.working] = "entity-status.working"
STATUS_NAMES[defines.entity_status.normal] = "entity-status.normal"
STATUS_NAMES[defines.entity_status.ghost] = "entity-status.ghost"
STATUS_NAMES[defines.entity_status.no_power] = "entity-status.no-power"
STATUS_NAMES[defines.entity_status.low_power] = "entity-status.low-power"
STATUS_NAMES[defines.entity_status.disabled_by_control_behavior] = "entity-status.disabled"
STATUS_NAMES[defines.entity_status.disabled_by_script] = "entity-status.disabled-by-script"
STATUS_NAMES[defines.entity_status.marked_for_deconstruction] = "entity-status.marked-for-deconstruction"
STATUS_NAMES_DEFAULT = "entity-status.disabled"
STATUS_NAMES_GHOST = "entity-status.ghost"

local bit_extract = bit32.extract
local function setting(bits, n)
	return bit_extract(bits, n) > 0
end
local function setting_flip(bits, n)
	return bit_extract(bits, n) == 0
end


--- Update the visibility of elements of the combinator GUI based on the
--- selected item in the mode dropdown.
---@param main_window LuaGuiElement
---@param selected_index int
local function set_visibility(main_window, selected_index)
	local is_station = selected_index == 1
	local is_depot = selected_index == 2
	local is_wagon = selected_index == 5
	local uses_network = is_station or is_depot or selected_index == 3
	local uses_allow_list = is_station or selected_index == 3

	local vflow = main_window.frame.vflow --[[@as LuaGuiElement]]
	local top_flow = vflow.top --[[@as LuaGuiElement]]
	local mode_settings_flow = vflow.mode_settings --[[@as LuaGuiElement]]
	local bottom_flow = vflow.bottom --[[@as LuaGuiElement]]
	local first_settings = bottom_flow.first --[[@as LuaGuiElement]]
	local second_settings = bottom_flow.second --[[@as LuaGuiElement]]
	local depot_settings = bottom_flow.depot --[[@as LuaGuiElement]]

	top_flow.is_pr_switch.visible = is_station
	vflow.network_label.visible = uses_network
	bottom_flow.network.visible = uses_network
	first_settings.allow_list.visible = uses_allow_list
	first_settings.is_stack.visible = is_station
	second_settings.enable_inactive.visible = is_station
	second_settings.enable_circuit_condition.visible = is_station
	mode_settings_flow.enable_slot_barring.visible = is_wagon
	mode_settings_flow.enable_train_count.visible = (selected_index == 4)
	mode_settings_flow.enable_manual_inventory.visible = (selected_index == 4)

	depot_settings.visible = is_depot
end

--- Close and destroy any open combinator GUI for the given player.
---@param player LuaPlayer
---@param silent boolean?
local function close_gui_for_player(player, silent)
	storage.open_combinators[player.index] = nil
	local rootgui = player.gui.screen
	if rootgui[COMBINATOR_NAME] then
		rootgui[COMBINATOR_NAME].destroy()
		if not silent then
			-- TODO: old code didn't play sound if ghost, why?
			player.play_sound({ path = COMBINATOR_CLOSE_SOUND })
		end
	end
end

---@param e EventData.on_gui_click
local function handle_close(e)
	local element = e.element
	if not element then return end
	local comb, player = get_open_combinator_for_player(storage, e.player_index)
	if not player then return end
	close_gui_for_player(player, not comb)
end

---@param e EventData.on_gui_switch_state_changed
local function handle_pr_switch(e)
	local element = e.element
	if not element then return end
	local comb = get_open_combinator_for_player(storage, e.player_index)
	if not comb then return end

	local is_pr_state = (element.switch_state == "none" and 0) or (element.switch_state == "left" and 1) or 2

	combinator_settings.provide_or_request.write(get_settings(comb), is_pr_state)
end

---@param e EventData.on_gui_elem_changed
local function handle_network(e)
	local element = e.element
	if not element then return end
	local comb = get_open_combinator_for_player(storage, e.player_index)
	if not comb then return end

	local signal = element.elem_value --[[@as SignalID]]
	if signal and (signal.name == "signal-everything" or signal.name == "signal-anything" or signal.name == "signal-each") then
		signal.name = NETWORK_EACH
		element.elem_value = signal
	end

	combinator_settings.network_signal.write(get_settings(comb), signal)
end

---@param e EventData.on_gui_checked_state_changed
local function handle_flag_setting(e)
	local element = e.element
	if not element then return end
	local comb = get_open_combinator_for_player(storage, e.player_index)
	if not comb then return end
	local s = combinator_settings[element.tags.setting]
	if not s then return end
	local value = element.state
	if element.tags.invert then value = not value end
	s.write(get_settings(comb), value)
	-- TODO: update_allow_list_section?
end

---@param combinator Cybersyn.Combinator.GhostRef
---@return string
local function generate_stop_layout_text(combinator)
	local is_ghost, is_valid = is_combinator_ghost(combinator)
	if not is_valid then return "(invalid)" end
	if is_ghost then return "(ghost)" end
	local train_stop = get_associated_train_stop(to_stateful_ref(combinator, storage))
	if (not train_stop) then return "(detached)" end

	local stopLayout = nil
	local station = storage.stations[train_stop.unit_number]
	local refueler = storage.refuelers[train_stop.unit_number]
	if station ~= nil then
		stopLayout = station.layout_pattern
	elseif refueler ~= nil then
		stopLayout = refueler.layout_pattern
	end

	return serpent.line(stopLayout)
end

local LAYOUT_ITEM_MAP = {
	[0] = "item/locomotive",
	[1] = "item/cargo-wagon",
	[2] = "item/fluid-wagon",
	[3] = "cybersyn-both-wagon",
	unknown = "utility/questionmark",
}

---@param combinator Cybersyn.Combinator.GhostRef
---@return table[]
local function generate_stop_layout_items(combinator)
	local is_ghost, is_valid = is_combinator_ghost(combinator)

	if is_ghost or (not is_valid) then
		return {
			{
				type = "sprite",
				sprite = "entity/entity-ghost",
				style_mods = { size = 32 },
				resize_to_sprite = false,
				ignored_by_interaction = true,
			},
		}
	end

	local train_stop = get_associated_train_stop(to_stateful_ref(combinator, storage))

	local stopLayout = nil
	if train_stop ~= nil then
		local station = storage.stations[train_stop.unit_number]
		local refueler = storage.refuelers[train_stop.unit_number]
		if station ~= nil then
			stopLayout = station.layout_pattern
		elseif refueler ~= nil then
			stopLayout = refueler.layout_pattern
		end
	end

	if not stopLayout then
		return {
			{
				type = "sprite",
				sprite = "utility/rail_path_not_possible",
				style_mods = { size = 32 },
				resize_to_sprite = false,
				ignored_by_interaction = true,
			},
		}
	end

	local items = {}

	local last_i = 1
	for i, type in pairs(stopLayout) do
		if type ~= 0 and type ~= 1 and type ~= 2 and type ~= 3 then
			type = "unknown"
		end
		if i - last_i > 1 then
			for _ = 1, i - last_i - 1 do
				table.insert(items, {
					type = "sprite",
					sprite = LAYOUT_ITEM_MAP[0],
					style_mods = { size = 32 },
					resize_to_sprite = false,
					ignored_by_interaction = true,
				})
			end
		end
		table.insert(items, {
			type = "sprite",
			sprite = LAYOUT_ITEM_MAP[type],
			style_mods = { size = 32 },
			resize_to_sprite = false,
			ignored_by_interaction = true,
		})
		last_i = i
	end

	return items
end

---@param player LuaPlayer
local function get_allow_list_section(player)
	if (player.opened.name == COMBINATOR_NAME) then
		return player.opened.frame.vflow.bottom_allowlist
	end
end

local function update_allow_list_section(player_index)
	local combinator, player = get_open_combinator_for_player(storage, player_index)
	if not player or not combinator then return end
	local layoutSection = get_allow_list_section(player)
	if not layoutSection then return end
	local cs = get_settings(combinator)
	local mode = combinator_settings.mode.read(cs) --[[@as Cybersyn.Combinator.Mode]]
	local disable_allow_list = combinator_settings.disable_allow_list.read(cs) --[[@as boolean]]

	--only for Station and Refueler
	if ((mode == Mode.LEGACY_STATION or mode == Mode.LEGACY_REFUELER) and (not disable_allow_list)) then
		layoutSection.visible = true
		-- layoutSection.allow_list_label.caption = generate_stop_layout(comb_unit_number)
		local flow = layoutSection.allow_list_items
		flow.clear()
		local items = generate_stop_layout_items(combinator)
		for _, item in pairs(items) do
			flib_gui.add(flow, item)
		end
		flow.tooltip = generate_stop_layout_text(combinator)
	else
		layoutSection.visible = false
	end
end

---@param e EventData.on_gui_selection_state_changed
local function handle_drop_down(e)
	local element = e.element
	if not element then return end
	local combinator = get_open_combinator_for_player(storage, e.player_index)
	if not combinator then return end
	local cs = get_settings(combinator)

	-- TODO: refer absolutely to the correct element.
	set_visibility(element.parent.parent.parent.parent, element.selected_index)

	if element.selected_index == 1 then
		combinator_settings.mode.write(cs, Mode.LEGACY_STATION)
	elseif element.selected_index == 2 then
		combinator_settings.mode.write(cs, Mode.LEGACY_DEPOT)
	elseif element.selected_index == 3 then
		combinator_settings.mode.write(cs, Mode.LEGACY_REFUELER)
	elseif element.selected_index == 4 then
		combinator_settings.mode.write(cs, Mode.LEGACY_STATION_CONTROL)
	elseif element.selected_index == 5 then
		combinator_settings.mode.write(cs, Mode.LEGACY_WAGON)
	else
		return
	end

	-- TODO: bind setting change to combinator_update for non-ghosts
	-- combinator_update(storage, comb)

	-- TODO: consider driving update_allow_list_section via setting change event
	update_allow_list_section(e.player_index)
end

---@param e EventData.on_gui_click
local function handle_refresh_allow(e)
	local combinator = get_open_combinator_for_player(storage, e.player_index)
	if not combinator then return end
	local stop = get_associated_train_stop(to_stateful_ref(combinator, storage))
	if stop == nil then return end
	local stopId = stop.unit_number
	if not stopId then return end
	remote.call("cybersyn", "reset_stop_layout", stopId, nil, true)
	update_allow_list_section(e.player_index)
end

---@param event EventData.on_gui_opened
local function on_gui_opened(event)
	local entity = event.entity
	if not entity or not entity.valid then return end
	local name = entity.name == "entity-ghost" and entity.ghost_name or entity.name
	if name ~= COMBINATOR_NAME then return end
	local player = game.get_player(event.player_index)
	if not player then return end

	gui_opened(entity, player)
end

---@param event EventData.on_gui_closed
local function on_gui_closed(event)
	local element = event.element
	if not element or element.name ~= COMBINATOR_NAME then return end
	local combinator, player = get_open_combinator_for_player(storage, event.player_index)
	if not player then return end
	close_gui_for_player(player, not combinator)
end

function register_gui_actions()
	flib_gui.add_handlers({
		["comb_close"] = handle_close,
		["comb_refresh_allow"] = handle_refresh_allow,
		["comb_drop_down"] = handle_drop_down,
		["comb_pr_switch"] = handle_pr_switch,
		["comb_network"] = handle_network,
		["comb_set_flag"] = handle_flag_setting,
	})
	flib_gui.handle_events()
	script.on_event(defines.events.on_gui_opened, on_gui_opened)
	script.on_event(defines.events.on_gui_closed, on_gui_closed)
end

---@param cs Cybersyn.Combinator.Settings
---@return int dropdown_index Index of the dropdown item to be shown
---@return SignalID? signal The network signal to be shown
---@return string switch_state The state of the provide/request switch
local function get_gui_state_from_combinator_settings(cs)
	local dropdown_index = 1
	local mode = combinator_settings.mode.read(cs)
	if mode == Mode.LEGACY_STATION then
		dropdown_index = 1
	elseif mode == Mode.LEGACY_DEPOT then
		dropdown_index = 2
	elseif mode == Mode.LEGACY_REFUELER then
		dropdown_index = 3
	elseif mode == Mode.LEGACY_STATION_CONTROL then
		dropdown_index = 4
	elseif mode == Mode.LEGACY_WAGON then
		dropdown_index = 5
	end

	local signal = combinator_settings.network_signal.read(cs) --[[@as SignalID?]]
	local pr = combinator_settings.provide_or_request.read(cs)
	local switch_state = "none"
	if pr == 1 then
		switch_state = "left"
	elseif pr == 2 then
		switch_state = "right"
	end
	return dropdown_index, signal, switch_state
end

---@param comb_entity LuaEntity Entity of combinator opened by player. Must be valid.
---@param player LuaPlayer Player opening the combinator. Must be valid.
function gui_opened(comb_entity, player)
	local comb = legacy_combinator_to_ghost_ref(comb_entity)

	-- Destroy existing combinator gui for the player
	close_gui_for_player(player, true)
	-- Mark new combinator gui state
	storage.open_combinators[player.index] = comb

	-- TODO: XXX: why are we calling combinator_update here
	combinator_update(storage, comb, true)

	-- Obtain combinator data for populating the ui
	local is_ghost, is_valid = is_combinator_ghost(comb)
	local status = combinator_api.get_factorio_status(comb)
	local cs = get_settings(comb)
	local selected_index, signal, switch_state = get_gui_state_from_combinator_settings(cs)
	local disable_allow_list = combinator_settings.disable_allow_list.read(cs)
	local use_stack_thresholds = combinator_settings.use_stack_threholds.read(cs)
	local enable_inactivity_condition = combinator_settings.enable_inactivity_condition.read(cs)
	local use_any_depot = combinator_settings.use_any_depot.read(cs)
	local disable_depot_bypass = combinator_settings.disable_depot_bypass.read(cs)
	local enable_slot_barring = combinator_settings.enable_slot_barring.read(cs)
	local enable_circuit_condition = combinator_settings.enable_circuit_condition.read(cs)
	local enable_train_count = combinator_settings.enable_train_count.read(cs)
	local enable_manual_inventory = combinator_settings.enable_manual_inventory.read(cs)

	local rootgui = player.gui.screen

	-- TODO: this is copypasta, factor out?
	local showLayout = false
	local layoutItems = {}
	local layoutTooltip = nil
	--only for Station (1) and Refueler (3)
	if ((selected_index == 1 or selected_index == 3) and not disable_allow_list) then
		showLayout = true
		layoutItems = generate_stop_layout_items(comb)
		layoutTooltip = generate_stop_layout_text(comb)
	end

	local _, main_window = flib_gui.add(rootgui, {
		{
			type = "frame",
			direction = "vertical",
			name = COMBINATOR_NAME,
			children = {
				--title bar
				{
					type = "flow",
					name = "titlebar",
					children = {
						{
							type = "label",
							style = "frame_title",
							caption = { "cybersyn-gui.combinator-title" },
							elem_mods = { ignored_by_interaction = true },
						},
						{ type = "empty-widget", style = "flib_titlebar_drag_handle", elem_mods = { ignored_by_interaction = true } },
						{
							type = "sprite-button",
							style = "frame_action_button",
							mouse_button_filter = { "left" },
							sprite = "utility/close",
							hovered_sprite = "utility/close",
							name = COMBINATOR_NAME,
							handler = handle_close,
						},
					},
				},
				{
					type = "frame",
					name = "frame",
					style = "inside_shallow_frame_with_padding",
					style_mods = { padding = 12, bottom_padding = 9 },
					children = {
						{
							type = "flow",
							name = "vflow",
							direction = "vertical",
							style_mods = { horizontal_align = "left" },
							children = {
								--status
								{
									type = "flow",
									style = "flib_titlebar_flow",
									direction = "horizontal",
									style_mods = {
										vertical_align = "center",
										horizontally_stretchable = true,
										bottom_padding = 4,
									},
									children = {
										{
											type = "sprite",
											sprite = is_ghost and STATUS_SPRITES_GHOST or STATUS_SPRITES[status] or STATUS_SPRITES_DEFAULT,
											style = "status_image",
											style_mods = { stretch_image_to_widget_size = true },
										},
										{
											type = "label",
											caption = { is_ghost and STATUS_NAMES_GHOST or STATUS_NAMES[status] or STATUS_NAMES_DEFAULT },
										},
									},
								},
								--preview
								{
									type = "frame",
									name = "preview_frame",
									style = "deep_frame_in_shallow_frame",
									style_mods = {
										minimal_width = 0,
										horizontally_stretchable = true,
										padding = 0,
									},
									children = {
										{ type = "entity-preview", name = "preview", style = "wide_entity_button" },
									},
								},
								--drop down
								{
									type = "label",
									style = "heading_2_label",
									caption = { "cybersyn-gui.operation" },
									style_mods = { top_padding = 8 },
								},
								{
									type = "flow",
									name = "top",
									direction = "horizontal",
									style_mods = { vertical_align = "center" },
									children = {
										{
											type = "drop-down",
											style_mods = { top_padding = 3, right_margin = 8 },
											handler = handle_drop_down,
											selected_index = selected_index,
											items = {
												{ "cybersyn-gui.comb1" },
												{ "cybersyn-gui.depot" },
												{ "cybersyn-gui.refueler" },
												{ "cybersyn-gui.comb2" },
												{ "cybersyn-gui.wagon-manifest" },
											},
										},
										{
											type = "switch",
											name = "is_pr_switch",
											allow_none_state = true,
											switch_state = switch_state,
											left_label_caption = { "cybersyn-gui.switch-provide" },
											right_label_caption = { "cybersyn-gui.switch-request" },
											left_label_tooltip = { "cybersyn-gui.switch-provide-tooltip" },
											right_label_tooltip = { "cybersyn-gui.switch-request-tooltip" },
											handler = handle_pr_switch,
										},
									},
								},
								---Settings section for modal settings
								{
									type = "flow",
									name = "mode_settings",
									direction = "vertical",
									style_mods = { horizontal_align = "left" },
									children = {
										{
											type = "checkbox",
											name = "enable_slot_barring",
											state = enable_slot_barring,
											handler = handle_flag_setting,
											tags = { setting = "enable_slot_barring" },
											tooltip = { "cybersyn-gui.enable-slot-barring-tooltip" },
											caption = { "cybersyn-gui.enable-slot-barring-description" },
										},
										{
											type = "checkbox",
											name = "enable_train_count",
											state = enable_train_count,
											handler = handle_flag_setting,
											tags = { setting = "enable_train_count" },
											tooltip = { "cybersyn-gui.enable-train-count-tooltip" },
											caption = { "cybersyn-gui.enable-train-count-description" },
										},
										{
											type = "checkbox",
											name = "enable_manual_inventory",
											state = enable_manual_inventory,
											handler = handle_flag_setting,
											tags = { setting = "enable_manual_inventory" },
											tooltip = { "cybersyn-gui.enable-manual-inventory-tooltip" },
											caption = { "cybersyn-gui.enable-manual-inventory-description" },
										},
									},
								},
								---Settings section for network
								{ type = "line", style_mods = { top_padding = 10 } },
								{
									type = "label",
									name = "network_label",
									style = "heading_2_label",
									caption = { "cybersyn-gui.network" },
									style_mods = { top_padding = 8 },
								},
								{
									type = "flow",
									name = "bottom",
									direction = "horizontal",
									style_mods = { vertical_align = "top" },
									children = {
										{
											type = "choose-elem-button",
											name = "network",
											style = "slot_button_in_shallow_frame",
											elem_type = "signal",
											tooltip = { "cybersyn-gui.network-tooltip" },
											signal = signal,
											style_mods = { bottom_margin = 1, right_margin = 6, top_margin = 2 },
											handler = handle_network,
										},
										{
											type = "flow",
											name = "depot",
											direction = "vertical",
											style_mods = { horizontal_align = "left" },
											children = {
												{
													type = "checkbox",
													name = "use_same_depot",
													state = not use_any_depot,
													handler = handle_flag_setting,
													tags = { setting = "use_any_depot", invert = true },
													tooltip = { "cybersyn-gui.use-same-depot-tooltip" },
													caption = { "cybersyn-gui.use-same-depot-description" },
												},
												{
													type = "checkbox",
													name = "depot_bypass",
													state = not disable_depot_bypass,
													handler = handle_flag_setting,
													tags = { setting = "disable_depot_bypass", invert = true },
													tooltip = { "cybersyn-gui.depot-bypass-tooltip" },
													caption = { "cybersyn-gui.depot-bypass-description" },
												},
											},
										},
										{
											type = "flow",
											name = "first",
											direction = "vertical",
											style_mods = { horizontal_align = "left", right_margin = 8 },
											children = {
												{
													type = "checkbox",
													name = "allow_list",
													state = not disable_allow_list,
													handler = handle_flag_setting,
													tags = { setting = "disable_allow_list", invert = true },
													tooltip = { "cybersyn-gui.allow-list-tooltip" },
													caption = { "cybersyn-gui.allow-list-description" },
												},
												{
													type = "checkbox",
													name = "is_stack",
													state = use_stack_thresholds,
													handler = handle_flag_setting,
													tags = { setting = "use_stack_thresholds" },
													tooltip = { "cybersyn-gui.is-stack-tooltip" },
													caption = { "cybersyn-gui.is-stack-description" },
												},
											},
										},
										{
											type = "flow",
											name = "second",
											direction = "vertical",
											children = {
												{
													type = "checkbox",
													name = "enable_inactive",
													state = enable_inactivity_condition,
													handler = handle_flag_setting,
													tags = { setting = "enable_inactivity_condition" },
													tooltip = { "cybersyn-gui.enable-inactive-tooltip" },
													caption = { "cybersyn-gui.enable-inactive-description" },
												},
												{
													type = "checkbox",
													name = "enable_circuit_condition",
													state = enable_circuit_condition,
													handler = handle_flag_setting,
													tags = { setting = "enable_circuit_condition" },
													tooltip = { "cybersyn-gui.enable-circuit-condition-tooltip" },
													caption = { "cybersyn-gui.enable-circuit-condition-description" },
												},
											},
										},
									},
								},
								--preview allow list
								{
									type = "flow",
									name = "bottom_allowlist",
									direction = "vertical",
									style_mods = { vertical_align = "top" },
									visible = showLayout,
									children = {
										{
											type = "label",
											name = "allow_list_heading",
											style = "heading_2_label",
											caption = { "cybersyn-gui.allow-list-preview" },
											tooltip = { "cybersyn-gui.allow-list-preview-tooltip" },
											style_mods = { top_padding = 8 },
										},
										{
											type = "flow",
											name = "allow_list_items",
											direction = "horizontal",
											tooltip = layoutTooltip,
											children = layoutItems,
										},
										{
											type = "button",
											name = "allow_list_refresh",
											tooltip = { "cybersyn-gui.allow-list-refresh-tooltip" },
											caption = { "cybersyn-gui.allow-list-refresh-description" },
											enabled = not is_ghost,
											handler = handle_refresh_allow,
										},
									},
								},
							},
						},
					},
				},
			},
		},
	})

	main_window.frame.vflow.preview_frame.preview.entity = comb_entity
	main_window.titlebar.drag_target = main_window
	main_window.force_auto_center()

	set_visibility(main_window, selected_index)
	player.opened = main_window
end

--- Called when a combinator or ghost is destroyed; close any corresponding
--- open guis.
--- TODO: eventify this?
---@param unit_number Cybersyn.UnitNumber
---@param silent boolean?
function gui_entity_destroyed(unit_number, silent)
	for _, player in pairs(game.players) do
		if not player or not player.valid then goto continue end
		local comb = storage.open_combinators[player.index]
		if not comb then goto continue end
		if combinator_api.get_unit_number(comb) == unit_number then
			close_gui_for_player(player, silent)
		end
		::continue::
	end
end
