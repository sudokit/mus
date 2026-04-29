# Sokol & microui

Example:
```odin
package main

import "base:runtime"

import mu "vendor:microui"

import sapp "shared:sokol-odin/sokol/app"
import sg "shared:sokol-odin/sokol/gfx"
import sgl "shared:sokol-odin/sokol/gl"
import sglue "shared:sokol-odin/sokol/glue"
import slog "shared:sokol-odin/sokol/log"

import "shared:mus"

st: struct {
	pass_action: sg.Pass_Action,
}

init :: proc "c" () {
	context = runtime.default_context()
	sg.setup({environment = sglue.environment(), logger = {func = slog.func}})
	sgl.setup({logger = {func = slog.func}})
	st.pass_action.colors[0] = {
		load_action = .CLEAR,
		clear_value = {1.0, 0.0, 0.0, 1.0},
	}

	mus.init()
}

frame :: proc "c" () {
	context = runtime.default_context()

	mu_ctx := mus.ctx()
	mus.begin()
	if mu.begin_window(mu_ctx, "Miui", {40, 40, 300, 450}) {
		mu.end_window(mu_ctx)
	}
	mus.end(sapp.width(), sapp.height())

	sg.begin_pass({action = st.pass_action, swapchain = sglue.swapchain()})
	mus.draw()
	sg.end_pass()
	sg.commit()
}

cleanup :: proc "c" () {
	context = runtime.default_context()
	sgl.shutdown()
	sg.shutdown()
}

event :: proc "c" (ev: ^sapp.Event) {
	context = runtime.default_context()

	mus.event(ev)
}

main :: proc() {
	sapp.run(
		{
			init_cb = init,
			frame_cb = frame,
			cleanup_cb = cleanup,
			event_cb = event,
			width = 800,
			height = 600,
			window_title = "leijjuva",
			icon = {sokol_default = true},
			logger = {func = slog.func},
		},
	)
}
```
