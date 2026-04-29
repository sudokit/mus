package mus

import "core:slice"
import "core:unicode/utf8"
import mu "vendor:microui"

import sapp "shared:sokol-odin/sokol/app"
import sg "shared:sokol-odin/sokol/gfx"
import sgl "shared:sokol-odin/sokol/gl"

@(private)
CLIPBOARD_SIZE :: 1 << 12

_ctx: struct {
	mu_ctx:     mu.Context,
	atlas:      struct {
		img:     sg.Image,
		view:    sg.View,
		sampler: sg.Sampler,
	},
	pipeline:   sgl.Pipeline,
	_clipboard: [CLIPBOARD_SIZE]u8,
}

ctx :: proc "contextless" () -> ^mu.Context {
	return &_ctx.mu_ctx
}

init :: proc() {
	pixels := make([][4]u8, mu.DEFAULT_ATLAS_WIDTH * mu.DEFAULT_ATLAS_HEIGHT); defer delete(pixels)

	for alpha, i in mu.default_atlas_alpha {
		pixels[i] = {0xff, 0xff, 0xff, alpha}
	}

	_ctx.atlas.img = sg.make_image(
		{
			width = mu.DEFAULT_ATLAS_WIDTH,
			height = mu.DEFAULT_ATLAS_HEIGHT,
			data = {mip_levels = {0 = {ptr = raw_data(pixels), size = uint(slice.size(pixels))}}},
			label = "microui-atlas-image",
		},
	)

	_ctx.atlas.view = sg.make_view(
		{texture = {image = _ctx.atlas.img}, label = "microui-atlas-view"},
	)

	_ctx.atlas.sampler = sg.make_sampler(
		{min_filter = .NEAREST, mag_filter = .NEAREST, label = "microui-atlas-sampler"},
	)

	_ctx.pipeline = sgl.make_pipeline(
		{
			colors = {
				0 = {
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					},
				},
			},
			label = "microui-pipeline",
		},
	)

	mu.init(&_ctx.mu_ctx, proc(udata: rawptr, text: string) -> bool {
			if len(text) >= CLIPBOARD_SIZE {return false}
			clipboard := (^[CLIPBOARD_SIZE]u8)(udata)
			copy(clipboard[:], text)
			if len(text) < CLIPBOARD_SIZE {
				clipboard[len(text)] = 0
			}
			return true
		}, proc(udata: rawptr) -> (string, bool) {
			clipboard := (^[CLIPBOARD_SIZE]u8)(udata)
			str := string(cstring(raw_data(clipboard)))
			return str, true
		}, &_ctx._clipboard)
	_ctx.mu_ctx.text_width = text_width
	_ctx.mu_ctx.text_height = proc(_: mu.Font) -> i32 {return 18}
}

@(private)
key_map := #partial #sparse[sapp.Keycode]mu.Key {
	.LEFT_SHIFT    = .SHIFT,
	.RIGHT_SHIFT   = .SHIFT,
	.LEFT_CONTROL  = .CTRL,
	.RIGHT_CONTROL = .CTRL,
	.LEFT_ALT      = .ALT,
	.RIGHT_ALT     = .ALT,
	.BACKSPACE     = .BACKSPACE,
	.DELETE        = .DELETE,
	.ENTER         = .RETURN,
	.KP_ENTER      = .RETURN,
	.LEFT          = .LEFT,
	.RIGHT         = .RIGHT,
	.HOME          = .HOME,
	.END           = .END,
	.A             = .A,
	.X             = .X,
	.C             = .C,
	.V             = .V,
}

event :: proc(ev: ^sapp.Event) {
	#partial switch ev.type {
	case .MOUSE_DOWN:
		mu.input_mouse_down(
			&_ctx.mu_ctx,
			i32(ev.mouse_x),
			i32(ev.mouse_y),
			mu.Mouse(ev.mouse_button),
		)
	case .MOUSE_UP:
		mu.input_mouse_up(
			&_ctx.mu_ctx,
			i32(ev.mouse_x),
			i32(ev.mouse_y),
			mu.Mouse(ev.mouse_button),
		)
	case .MOUSE_MOVE:
		mu.input_mouse_move(&_ctx.mu_ctx, i32(ev.mouse_x), i32(ev.mouse_y))
	case .MOUSE_SCROLL:
		mu.input_scroll(&_ctx.mu_ctx, 0, i32(ev.scroll_y))
	case .KEY_DOWN:
		mu.input_key_down(&_ctx.mu_ctx, key_map[ev.key_code])
	case .KEY_UP:
		mu.input_key_up(&_ctx.mu_ctx, key_map[ev.key_code])
	case .CHAR:
		if ev.char_code == 127 || ev.char_code < 32 {break}
		if bool(ev.modifiers & sapp.MODIFIER_ALT) ||
		   bool(ev.modifiers & sapp.MODIFIER_CTRL) {break}
		ch := rune(ev.char_code)
		buf: [4]u8
		str, width := utf8.encode_rune(ch)
		mu.input_text(&_ctx.mu_ctx, string(str[:width]))
	}
}

begin :: proc() {
	mu.begin(&_ctx.mu_ctx)
}

end :: proc(disp_w, disp_h: i32) {
	mu.end(&_ctx.mu_ctx)

	render_begin(disp_w, disp_h)
	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(&_ctx.mu_ctx, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Rect:
			draw_rect(cmd.rect, cmd.color)
		case ^mu.Command_Text:
			draw_text(cmd.str, cmd.pos, cmd.color)
		case ^mu.Command_Icon:
			draw_icon(cmd.id, cmd.rect, cmd.color)
		case ^mu.Command_Clip:
			set_clip_rect(cmd.rect)
		case ^mu.Command_Jump:
			unreachable()
		}
	}
	render_end()
}

@(private)
render_begin :: proc(disp_w, disp_h: i32) {
	sgl.defaults()
	sgl.push_pipeline()
	sgl.load_pipeline(_ctx.pipeline)
	sgl.enable_texture()
	sgl.texture(_ctx.atlas.view, _ctx.atlas.sampler)
	sgl.matrix_mode_projection()
	sgl.push_matrix()
	sgl.ortho(0, f32(disp_w), f32(disp_h), 0, -1, 1)
	sgl.begin_quads()
}

@(private)
render_end :: proc() {
	sgl.end()
	sgl.pop_matrix()
	sgl.pop_pipeline()
}

draw :: proc() {
	sgl.draw()
}

@(private)
push_quad :: proc(dst, src: mu.Rect, color: mu.Color) {
	u0 := f32(src.x) / f32(mu.DEFAULT_ATLAS_WIDTH)
	v0 := f32(src.y) / f32(mu.DEFAULT_ATLAS_HEIGHT)
	u1 := f32(src.x + src.w) / f32(mu.DEFAULT_ATLAS_WIDTH)
	v1 := f32(src.y + src.h) / f32(mu.DEFAULT_ATLAS_HEIGHT)

	x0 := f32(dst.x)
	y0 := f32(dst.y)
	x1 := f32(dst.x + dst.w)
	y1 := f32(dst.y + dst.h)

	sgl.c4b(color.r, color.g, color.b, color.a)
	sgl.v2f_t2f(x0, y0, u0, v0)
	sgl.v2f_t2f(x1, y0, u1, v0)
	sgl.v2f_t2f(x1, y1, u1, v1)
	sgl.v2f_t2f(x0, y1, u0, v1)
}

@(private)
draw_rect :: proc(rect: mu.Rect, color: mu.Color) {
	push_quad(rect, mu.default_atlas[mu.DEFAULT_ATLAS_WHITE], color)
}

@(private)
draw_text :: proc(text: string, pos: mu.Vec2, color: mu.Color) {
	dst := mu.Rect{pos.x, pos.y, 0, 0}
	for char in text {
		idx := mu.DEFAULT_ATLAS_FONT + int(char)
		if idx >= len(mu.default_atlas) {continue}
		src := mu.default_atlas[idx]
		dst.w = src.w
		dst.h = src.h
		push_quad(dst, src, color)
		dst.x += dst.w
	}
}

@(private)
draw_icon :: proc(id: mu.Icon, rect: mu.Rect, color: mu.Color) {
	src := mu.default_atlas[id]
	x := rect.x + (rect.w - src.w) / 2
	y := rect.y + (rect.h - src.h) / 2
	push_quad({x, y, src.w, src.h}, src, color)
}


@(private)
set_clip_rect :: proc(rect: mu.Rect) {
	sgl.end()
	sgl.scissor_rect(rect.x, rect.y, rect.w, rect.h, true)
	sgl.begin_quads()
}

@(private)
text_width :: proc(font: mu.Font, str: string) -> (w: i32) {
	for char in str {
		idx := mu.DEFAULT_ATLAS_FONT + int(char)
		if idx >= len(mu.default_atlas) {continue}
		w += mu.default_atlas[idx].w
	}
	return
}

