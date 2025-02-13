-- flib_gui typing causes a lot of extraneous missing fields errors
---@diagnostic disable: missing-fields

local flib_gui = require("__flib__.gui")

-- TODO: this is copypasta from station.lua, refactor

---@param event EventData.on_gui_elem_changed
---@param settings Cybersyn.Combinator.Settings
local function handle_network(event, settings)
	local signal = event.element.elem_value
	if not signal then return end
	if signal.name == "signal-everything" or signal.name == "signal-anything" or signal.name == "signal-each" then
		signal.name = NETWORK_EACH
	end
	combinator_api.write_setting(settings, combinator_api.settings.network_signal, signal)
end

flib_gui.add_handlers(
	{
		handle_network = handle_network,
	},
	combinator_api.flib_settings_handler_wrapper,
	"depot_settings"
)

combinator_api.register_combinator_mode({
	name = "depot",
	localized_string = "cybersyn-gui.depot",
	create_gui = function(parent)
		flib_gui.add(parent, {
			{
				type = "label",
				style = "heading_2_label",
				caption = { "cybersyn-gui.settings" },
				style_mods = { top_padding = 8 },
			},
			{
				type = "flow",
				name = "network_flow",
				direction = "horizontal",
				style_mods = { vertical_align = "center", horizontally_stretchable = true },
				children = {
					{
						type = "label",
						caption = { "cybersyn-gui.network" },
					},
					{
						type = "flow",
						style_mods = { horizontally_stretchable = true },
					},
					{
						type = "choose-elem-button",
						name = "network_button",
						handler = handle_network,
						style = "slot_button_in_shallow_frame",
						tooltip = { "cybersyn-gui.network-tooltip" },
						elem_type = "signal",
					},
				},
			},
			{
				type = "checkbox",
				name = "use_same_depot",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "use_any_depot", inverted = true },
				tooltip = { "cybersyn-gui.use-same-depot-tooltip" },
				caption = { "cybersyn-gui.use-same-depot-description" },
			},
			{
				type = "checkbox",
				name = "depot_bypass",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "disable_depot_bypass", inverted = true },
				tooltip = { "cybersyn-gui.depot-bypass-tooltip" },
				caption = { "cybersyn-gui.depot-bypass-description" },
			},
		})
	end,
	update_gui = function(parent, settings, changed_setting)
		parent["network_flow"]["network_button"].elem_value = combinator_api.read_setting(settings,
			combinator_api.settings.network_signal)
		parent["use_same_depot"].state = not combinator_api.read_setting(settings, combinator_api.settings.use_any_depot)
		parent["depot_bypass"].state = not combinator_api.read_setting(settings, combinator_api.settings
		.disable_depot_bypass)
	end,
})
