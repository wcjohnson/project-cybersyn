-- flib_gui typing causes a lot of extraneous missing fields errors
---@diagnostic disable: missing-fields

local flib_gui = require("__flib__.gui")

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

---@param event EventData.on_gui_switch_state_changed
---@param settings Cybersyn.Combinator.Settings
local function handle_pr_switch(event, settings)
	local element = event.element
	local is_pr_state = (element.switch_state == "none" and 0) or (element.switch_state == "left" and 1) or 2
	combinator_api.write_setting(settings, combinator_api.settings.pr, is_pr_state)
end

flib_gui.add_handlers(
	{
		handle_network = handle_network,
		handle_pr_switch = handle_pr_switch,
	},
	combinator_api.flib_settings_handler_wrapper,
	"station_settings"
)

combinator_api.register_combinator_mode({
	name = "station",
	localized_string = "cybersyn-gui.comb1",
	create_gui = function(parent)
		flib_gui.add(parent, {
			{
				type = "label",
				style = "heading_2_label",
				caption = { "cybersyn-gui.settings" },
				style_mods = { top_padding = 8 },
			},
			{
				type = "switch",
				name = "is_pr_switch",
				allow_none_state = true,
				switch_state = "none",
				handler = handle_pr_switch,
				left_label_caption = { "cybersyn-gui.switch-provide" },
				right_label_caption = { "cybersyn-gui.switch-request" },
				left_label_tooltip = { "cybersyn-gui.switch-provide-tooltip" },
				right_label_tooltip = { "cybersyn-gui.switch-request-tooltip" },
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
				name = "allow_list",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "disable_allow_list", inverted = true },
				tooltip = { "cybersyn-gui.allow-list-tooltip" },
				caption = { "cybersyn-gui.allow-list-description" },
			},
			{
				type = "checkbox",
				name = "is_stack",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "use_stack_thresholds" },
				tooltip = { "cybersyn-gui.is-stack-tooltip" },
				caption = { "cybersyn-gui.is-stack-description" },
			},
			{
				type = "checkbox",
				name = "enable_inactive",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "enable_inactivity_condition" },
				tooltip = { "cybersyn-gui.enable-inactive-tooltip" },
				caption = { "cybersyn-gui.enable-inactive-description" },
			},
			{
				type = "checkbox",
				name = "enable_circuit_condition",
				state = false,
				handler = combinator_api.generic_checkbox_handler,
				tags = { setting = "enable_circuit_condition" },
				tooltip = { "cybersyn-gui.enable-circuit-condition-tooltip" },
				caption = { "cybersyn-gui.enable-circuit-condition-description" },
			},
			-- {
			-- 	type = "flow",
			-- 	name = "circuit_go_flow",
			-- 	direction = "horizontal",
			-- 	style_mods = { vertical_align = "center", horizontally_stretchable = true },
			-- 	children = {
			-- 		{
			-- 			type = "label",
			-- 			caption = "Circuit condition: allow departure",
			-- 		},
			-- 		{
			-- 			type = "flow",
			-- 			style_mods = { horizontally_stretchable = true },
			-- 		},
			-- 		{
			-- 			type = "choose-elem-button",
			-- 			name = "circuit_go_button",
			-- 			style = "slot_button_in_shallow_frame",
			-- 			style_mods = { right_margin = 8 },
			-- 			tooltip = { "cybersyn-gui.network-tooltip" },
			-- 			elem_type = "signal",
			-- 		},
			-- 	},
			-- },
		})
	end,
	update_gui = function(parent, settings, changed_setting)
		local switch_state = "none"
		local is_pr_state = combinator_api.read_setting(settings, combinator_api.settings.pr)
		if is_pr_state == 0 then
			switch_state = "none"
		elseif is_pr_state == 1 then
			switch_state = "left"
		elseif is_pr_state == 2 then
			switch_state = "right"
		end
		parent["is_pr_switch"].switch_state = switch_state

		parent["network_flow"]["network_button"].elem_value = combinator_api.read_setting(settings,
			combinator_api.settings.network_signal)

		parent["allow_list"].state = not combinator_api.read_setting(settings, combinator_api.settings.disable_allow_list)
		parent["is_stack"].state = combinator_api.read_setting(settings, combinator_api.settings.use_stack_thresholds)
		parent["enable_inactive"].state = combinator_api.read_setting(settings,
			combinator_api.settings.enable_inactivity_condition)
		parent["enable_circuit_condition"].state = combinator_api.read_setting(settings,
			combinator_api.settings.enable_circuit_condition)
	end,
})
