-- flib_gui typing causes a lot of extraneous missing fields errors
---@diagnostic disable: missing-fields

local flib_gui = require("__flib__.gui")

combinator_api.register_combinator_mode({
	name = "station",
	localized_string = "cybersyn-gui.comb1",
	create_gui = function(parent)
		flib_gui.add(parent, {
			{
				type = "label",
				style = "heading_2_label",
				caption = "Settings", -- LORD: i18n
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
						style = "slot_button_in_shallow_frame",
						style_mods = { right_margin = 8 },
						tooltip = { "cybersyn-gui.network-tooltip" },
						elem_type = "signal",
					},
				},
			},
			{
				type = "checkbox",
				name = "allow_list",
				state = false,
				tooltip = { "cybersyn-gui.allow-list-tooltip" },
				caption = { "cybersyn-gui.allow-list-description" },
			},
			{
				type = "checkbox",
				name = "is_stack",
				state = false,
				tooltip = { "cybersyn-gui.is-stack-tooltip" },
				caption = { "cybersyn-gui.is-stack-description" },
			},
			{
				type = "checkbox",
				name = "enable_inactive",
				state = false,
				tooltip = { "cybersyn-gui.enable-inactive-tooltip" },
				caption = { "cybersyn-gui.enable-inactive-description" },
			},
			{
				type = "flow",
				name = "circuit_go_flow",
				direction = "horizontal",
				style_mods = { vertical_align = "center", horizontally_stretchable = true },
				children = {
					{
						type = "label",
						caption = "Circuit condition: allow departure",
					},
					{
						type = "flow",
						style_mods = { horizontally_stretchable = true },
					},
					{
						type = "choose-elem-button",
						name = "circuit_go_button",
						style = "slot_button_in_shallow_frame",
						style_mods = { right_margin = 8 },
						tooltip = { "cybersyn-gui.network-tooltip" },
						elem_type = "signal",
					},
				},
			},
			{
				type = "flow",
				name = "circuit_force_flow",
				direction = "horizontal",
				style_mods = { vertical_align = "center", horizontally_stretchable = true },
				children = {
					{
						type = "label",
						caption = "Circuit condition: force departure",
					},
					{
						type = "flow",
						style_mods = { horizontally_stretchable = true },
					},
					{
						type = "choose-elem-button",
						name = "circuit_force_button",
						style = "slot_button_in_shallow_frame",
						style_mods = { right_margin = 8 },
						tooltip = { "cybersyn-gui.network-tooltip" },
						elem_type = "signal",
					},
				},
			},
		})
	end,
	update_gui = function(parent, settings, changed_setting)
	end,
})
