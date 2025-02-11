-- Sumneko gives lots of false errors in this file due to no partial typing in
-- flib_gui's `elem_mods`. I'm disabling the missing-fields diagnostic for the entire file.
---@diagnostic disable: missing-fields

local flib_gui = require("__flib__.gui")

local WINDOW_NAME = "cybersyn-combinator-gui"

---@param window LuaGuiElement
---@param settings Cybersyn.Combinator.Settings
local function rebuild_mode_section(window, settings)
	if (not window) or (window.name ~= WINDOW_NAME) then return end
	local mode_section = window["frame"]["vflow"]["mode_settings"]
	local mode_dropdown = window["frame"]["vflow"]["mode_flow"]["mode_dropdown"]

	-- Impose desired mode from combinator settiongs
	local desired_mode_name = combinator_api.read_setting(settings, combinator_api.settings.mode)
	local desired_mode = combinator_api.get_combinator_mode(desired_mode_name)
	internal_update_combinator_gui_status_section(window, settings)
	if not desired_mode then
		-- Invalid mode
		mode_section.clear()
		mode_dropdown.selected_index = 0
		return
	end

	-- Impose mode on dropdown
	local desired_mode_index = find(
		combinator_api.get_combinator_mode_list(),
		function(x) return x == desired_mode_name end
	)
	if desired_mode_index then mode_dropdown.selected_index = desired_mode_index end

	-- Impose mode on lower GUI section
	if mode_section.tags.current_mode == desired_mode then
		-- GUI for mode is already built, update it.
		desired_mode.update_gui(mode_section, settings)
		return
	end
	-- Teardown the old mode section and rebuild/update
	mode_section.clear()
	desired_mode.create_gui(mode_section)
	mode_section.tags.current_mode = desired_mode
	desired_mode.update_gui(mode_section, settings)
end

---@param window LuaGuiElement
---@param settings Cybersyn.Combinator.Settings
---@param updated_setting string?
local function update_mode_section(window, settings, updated_setting)
	if (not window) or (window.name ~= WINDOW_NAME) then return end
	local mode_section = window["frame"]["vflow"]["mode_settings"]
	local desired_mode_name = combinator_api.read_setting(settings, combinator_api.settings.mode)
	local desired_mode = combinator_api.get_combinator_mode(desired_mode_name)
	if (not desired_mode) or (mode_section.tags.current_mode ~= desired_mode_name) then
		return rebuild_mode_section(window, settings)
	end
	desired_mode.update_gui(mode_section, settings, updated_setting)
end

---@param settings Cybersyn.Combinator.Settings
local function rebuild_mode_sections(settings)
	local map_data = storage --[[@as MapData]]
	for _, ui_state in pairs(map_data.combinator_uis) do
		if ui_state.open_combinator_unit_number == settings.entity.unit_number then
			local player = game.get_player(ui_state.player_index)
			if player then
				local comb_gui = player.gui.screen[WINDOW_NAME]
				if comb_gui then rebuild_mode_section(comb_gui, settings) end
			end
		end
	end
end

---@param settings Cybersyn.Combinator.Settings
local function update_mode_sections(settings, updated_setting)
	local map_data = storage --[[@as MapData]]
	for _, ui_state in pairs(map_data.combinator_uis) do
		if ui_state.open_combinator_unit_number == settings.entity.unit_number then
			local player = game.get_player(ui_state.player_index)
			if player then
				local comb_gui = player.gui.screen[WINDOW_NAME]
				if comb_gui then update_mode_section(comb_gui, settings, updated_setting) end
			end
		end
	end
end

---@param e EventData.on_gui_click
local function handle_close(e)
	combinator_api.close_gui(e.player_index)
end

---@param e EventData.on_gui_selection_state_changed
local function handle_mode_dropdown(e)
	local state = combinator_api.get_gui_state(e.player_index)
	if state and state.open_combinator and combinator_api.is_valid(state.open_combinator) then
		local new_mode = combinator_api.get_combinator_mode_list()[e.element.selected_index]
		if not new_mode then return end
		local settings = combinator_api.get_combinator_settings(state.open_combinator)
		combinator_api.write_setting(settings, combinator_api.settings.mode, new_mode)
	end
end

---Get the GUI state for a player if that player's GUI is open.
---@param player_index PlayerIndex
---@return Cybersyn.Combinator.PlayerUiState? #The GUI state for the player, or `nil` if the player's GUI is not open.
function combinator_api.get_gui_state(player_index)
	local map_data = storage --[[@as MapData]]
	return map_data.combinator_uis[player_index]
end

---@param player_index PlayerIndex
local function destroy_gui_state(player_index)
	local map_data = storage --[[@as MapData]]
	map_data.combinator_uis[player_index] = nil
end

---@param player_index PlayerIndex
---@param combinator Cybersyn.Combinator.Ephemeral
local function create_gui_state(player_index, combinator)
	local map_data = storage --[[@as MapData]]
	map_data.combinator_uis[player_index] = {
		player_index = player_index,
		open_combinator = combinator,
		open_combinator_unit_number = combinator.entity.unit_number,
	}
end

---Determine if the given name is the name of the combinator gui window.
---@param name string
function internal_is_combinator_gui_window_name(name)
	-- TODO: This function is only needed because of manager cruft; remove it
	-- when the manager is factored out to a separate mod as it should be.
	return (name == WINDOW_NAME)
end

---Determine if a player has the combinator GUI open.
---@param player_index PlayerIndex
---@return boolean
function combinator_api.is_gui_open(player_index)
	local player = game.get_player(player_index)
	if not player then return false end
	local gui_root = player.gui.screen
	local combinator_ui = combinator_api.get_gui_state(player_index)
	if combinator_ui or gui_root[WINDOW_NAME] then return true else return false end
end

---Close the combinator gui for the given player.
---@param player_index PlayerIndex
---@param silent boolean?
function combinator_api.close_gui(player_index, silent)
	local player = game.get_player(player_index)
	if not player then return end
	local gui_root = player.gui.screen
	if gui_root[WINDOW_NAME] then
		game.print("combinator_api.close_gui " .. tostring(silent),
			{
				skip = defines.print_skip.never,
				sound = defines.print_sound.never,
				game_state = false,
			})
		gui_root[WINDOW_NAME].destroy()
		if not silent then player.play_sound({ path = COMBINATOR_CLOSE_SOUND }) end
	end
	destroy_gui_state(player_index)
end

---@param player_index PlayerIndex
---@param combinator Cybersyn.Combinator.Ephemeral
function combinator_api.open_gui(player_index, combinator)
	if not combinator_api.is_valid(combinator) then return end
	local player = game.get_player(player_index)
	if not player then return end
	game.print("combinator_api.open_gui",
		{
			skip = defines.print_skip.never,
			sound = defines.print_sound.never,
			game_state = false,
		})
	-- Close any existing gui
	combinator_api.close_gui(player_index, true)
	-- Create new gui state
	create_gui_state(player_index, combinator)

	-- Generate main gui window
	local gui_root = player.gui.screen
	local mode_dropdown_items = map(
		combinator_api.get_combinator_mode_list(),
		function(mode_name)
			local mode = combinator_api.get_combinator_mode(mode_name)
			return { mode.localized_string }
		end
	)
	local _, main_window = flib_gui.add(gui_root, {
		{
			type = "frame",
			direction = "vertical",
			name = WINDOW_NAME,
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
									name = "status",
									style = "flib_titlebar_flow",
									direction = "horizontal",
									style_mods = {
										vertical_align = "center",
										horizontally_stretchable = true,
										bottom_padding = 4,
									},
									children = {
										-- LORD: update function to apply status to these elts.
										{
											type = "sprite",
											name = "status_sprite",
											sprite = "utility/status_not_working",
											style = "status_image",
											style_mods = { stretch_image_to_widget_size = true },
										},
										{
											type = "label",
											name = "status_label",
											caption = { "entity-status.disabled" },
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
										-- LORD: update function
										{ type = "entity-preview", name = "preview", style = "wide_entity_button" },
									},
								},
								--mode picker
								{
									type = "label",
									style = "heading_2_label",
									caption = { "cybersyn-gui.operation" },
									style_mods = { top_padding = 8 },
								},
								{
									type = "flow",
									name = "mode_flow",
									direction = "horizontal",
									style_mods = { vertical_align = "center" },
									children = {
										{
											type = "drop-down",
											name = "mode_dropdown",
											style_mods = { top_padding = 3, right_margin = 8 },
											handler = handle_mode_dropdown,
											selected_index = 1,
											items = mode_dropdown_items,
										},
									},
								},
								---Settings section for modal settings
								{
									type = "flow",
									name = "mode_settings",
									direction = "vertical",
									tags = { current_mode = "" },
									style_mods = { horizontal_align = "left" },
									children = {

									}, -- children
								}, -- mode_settings
							}, -- children
						}, -- vflow
					}, -- children
				},  -- frame
			},    -- children
		},      -- window
	})

	main_window.titlebar.drag_target = main_window
	main_window.force_auto_center()

	rebuild_mode_section(main_window, combinator_api.get_combinator_settings(combinator))

	player.opened = main_window
end

---@param event EventData.on_gui_opened
local function on_gui_opened(event)
	local comb = combinator_api.entity_to_ephemeral(event.entity)
	if not comb then return end
	combinator_api.open_gui(event.player_index, comb)
end

---@param event EventData.on_gui_closed
local function on_gui_closed(event)
	local element = event.element
	if not element or element.name ~= WINDOW_NAME then return end
	game.print("on_gui_closed", { skip = defines.print_skip.never, sound = defines.print_sound.never, game_state = false })
	combinator_api.close_gui(event.player_index)
end

-- TODO: This function only exists due to cruft in the manager. When manager is
-- separated, can be removed.
function internal_forward_on_gui_closed(event)
	on_gui_closed(event)
end

function internal_bind_gui_events()
	flib_gui.add_handlers({
		["comb_close"] = handle_close,
		["comb_mode"] = handle_mode_dropdown,
		-- ["comb_refresh_allow"] = handle_refresh_allow,
		-- ["comb_drop_down"] = handle_drop_down,
		-- ["comb_pr_switch"] = handle_pr_switch,
		-- ["comb_network"] = handle_network,
		-- ["comb_setting"] = handle_setting,
		-- ["comb_setting_flip"] = handle_setting_flip,
	})
	flib_gui.handle_events()
	script.on_event(defines.events.on_gui_opened, on_gui_opened)
	script.on_event(defines.events.on_gui_closed, on_gui_closed)
end

-- When a combinator ghost revives, seamlessly transition the GUI to the
-- revived combinator for any players that had the ghost open.
on_combinator_ghost_revived(function(ghost_id, new_combinator)
	local eph = combinator_api.entity_to_ephemeral(new_combinator)
	if not eph then return end
	local map_data = storage --[[@as MapData]]
	for player_index, ui_state in pairs(map_data.combinator_uis) do
		if ui_state.open_combinator_unit_number == ghost_id then
			ui_state.open_combinator = eph
			ui_state.open_combinator_unit_number = new_combinator.unit_number
		end
	end
	rebuild_mode_sections(combinator_api.get_combinator_settings(eph))
end)

on_combinator_setting_changed(function(combinator, setting_name, new_value, old_value)
	local settings = combinator_api.get_combinator_settings(combinator)
	if not settings then return end
	if setting_name == nil or setting_name == "mode" then
		rebuild_mode_sections(settings)
	else
		update_mode_sections(settings, setting_name)
	end
end)
