extends CanvasLayer
## Interface: barra FOCO (câmera lenta), cronômetro, inimigos restantes,
## telas de título / morte / fase concluída / pausa, mira e seta da saída.
## Tudo desenhado por código em um único Control (fácil de trocar depois).

const C_TEXT := Color("#ece6d9")
const C_DIM := Color(0.8, 0.78, 0.95, 0.6)
const C_ACCENT := Color("#ff3d7f")
const C_FOCUS := Color("#5ae4ff")
const C_GOOD := Color("#5affb0")
const C_BAD := Color("#ff4060")

const SLOWMO_SHADER := """
shader_type canvas_item;
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 off = (uv - 0.5) * 0.004 * amount;
	vec3 col;
	col.r = texture(screen_tex, uv + off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - off).b;
	float g = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(g) * vec3(0.7, 0.95, 1.25), amount * 0.5);
	float vig = smoothstep(0.3, 0.85, distance(uv, vec2(0.5)));
	col *= 1.0 - vig * amount * 0.65;
	COLOR = vec4(col, 1.0);
}
"""

var main: Node   ## main.gd (fornece tempo, inimigos, porta...)
var mode := "title"   ## title | play | dead | complete | finished
var paused := false
var info := {}        ## dados das telas (tempo, recorde, etc.)

var _canvas: Control
var _overlay: ColorRect
var _overlay_mat: ShaderMaterial
var _t := 0.0
var _mode_t := 0.0
var _intro := ""
var _intro_t := 0.0
var _msg := ""
var _msg_t := 0.0
var _flash := 0.0
var _flash_color := Color.WHITE


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 5
	add_child(fx_layer)
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SLOWMO_SHADER
	_overlay_mat = ShaderMaterial.new()
	_overlay_mat.shader = sh
	_overlay.material = _overlay_mat
	_overlay.visible = false
	fx_layer.add_child(_overlay)

	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_on_draw)
	add_child(_canvas)


func set_mode(m: String, data := {}) -> void:
	mode = m
	info = data
	_mode_t = 0.0


func intro(text: String) -> void:
	_intro = text
	_intro_t = 2.0


func message(text: String, duration := 1.8) -> void:
	_msg = text
	_msg_t = duration


func flash(color: Color, strength := 0.35) -> void:
	_flash_color = color
	_flash = maxf(_flash, strength)


func _process(delta: float) -> void:
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	if paused:
		real_dt = delta
	_t += real_dt
	_mode_t += real_dt
	_intro_t = maxf(0.0, _intro_t - real_dt)
	_msg_t = maxf(0.0, _msg_t - real_dt)
	_flash = maxf(0.0, _flash - real_dt * 2.5)
	_overlay.visible = Game.slowmo_amount > 0.01
	_overlay_mat.set_shader_parameter("amount", Game.slowmo_amount)
	_canvas.queue_redraw()


# ------------------------------------------------------------- desenho ---

func _on_draw() -> void:
	var size := _canvas.size
	match mode:
		"title":
			_draw_title(size)
		"play", "dead", "complete":
			_draw_gameplay(size)
		"finished":
			_draw_finished(size)
	if _flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color, _flash))
	if paused:
		_draw_pause(size)
	_draw_crosshair()


func _text(pos: Vector2, s: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	_canvas.draw_string_outline(font, pos, s, align, width, font_size, maxi(4, font_size / 5), Color(0.03, 0.02, 0.07, 0.9 * color.a))
	_canvas.draw_string(font, pos, s, align, width, font_size, color)


func _center_text(y: float, s: String, font_size: int, color: Color) -> void:
	_text(Vector2(0, y), s, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, _canvas.size.x)


func _draw_gameplay(size: Vector2) -> void:
	# --- barra FOCO ---
	var cells := 12
	var filled := int(ceil(Game.battery * cells - 0.001))
	var col := C_ACCENT if Game.slowmo_active else C_FOCUS
	_text(Vector2(24, 34), "FOCO", 16, C_DIM)
	for i in cells:
		var r := Rect2(78 + i * 15, 20, 11, 18)
		_canvas.draw_rect(r, Color(col, 0.15))
		if i < filled:
			_canvas.draw_rect(r, col)
	_text(Vector2(78 + cells * 15 + 8, 34), "[SHIFT]", 13, C_DIM)

	# --- nome da fase / tempo / inimigos ---
	if main:
		_center_text(32, main.level_name(), 15, C_DIM)
		_text(Vector2(size.x - 224, 34), _fmt_time(main.level_time), 22, C_TEXT, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		var left: int = main.enemies_left
		var total: int = main.enemies_total
		var etxt := "ALVOS  %d / %d" % [total - left, total]
		_text(Vector2(size.x - 224, 58), etxt, 14, C_GOOD if left == 0 else C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		_draw_exit_arrow(size)
	if Game.god_mode:
		_text(Vector2(24, 62), "MODO DEUS (F1)", 13, C_GOOD)

	# --- textos centrais ---
	if _intro_t > 0.0 and mode == "play":
		var a := clampf(_intro_t / 0.5, 0.0, 1.0)
		_center_text(size.y * 0.32, _intro, 44, Color(C_TEXT, a))
	if _msg_t > 0.0 and mode == "play":
		var a2 := clampf(_msg_t / 0.4, 0.0, 1.0)
		_center_text(size.y * 0.42, _msg, 26, Color(C_GOOD, a2))

	if mode == "dead":
		var k := clampf(_mode_t / 0.25, 0.0, 1.0)
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.0, 0.03, 0.45 * k))
		_center_text(size.y * 0.45, "ELIMINADO", 64, Color(C_BAD, k))
		if _mode_t > 0.35:
			_center_text(size.y * 0.45 + 50, "clique ou R para tentar de novo", 20, C_TEXT)
	elif mode == "complete":
		var k2 := clampf(_mode_t / 0.25, 0.0, 1.0)
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.05, 0.04, 0.5 * k2))
		_center_text(size.y * 0.38, "FASE CONCLUÍDA", 56, Color(C_GOOD, k2))
		var t: float = info.get("time", 0.0)
		var best: float = info.get("best", t)
		var rec := "   NOVO RECORDE!" if info.get("record", false) else ""
		_center_text(size.y * 0.38 + 50, "tempo %s    recorde %s%s" % [_fmt_time(t), _fmt_time(best), rec], 20, C_TEXT)
		if _mode_t > 0.4:
			_center_text(size.y * 0.38 + 90, "clique para continuar", 18, C_DIM)


func _draw_exit_arrow(size: Vector2) -> void:
	var door: Node2D = main.door
	if not is_instance_valid(door) or door.locked or mode != "play":
		return
	var p := door.get_global_transform_with_canvas().origin + Vector2(0, -30)
	var margin := 40.0
	var screen := Rect2(Vector2.ZERO, size).grow(-margin)
	if screen.has_point(p):
		return
	var c := size * 0.5
	var dir := (p - c).normalized()
	# ponto na borda da tela na direção da porta
	var tx := INF if dir.x == 0.0 else ((screen.end.x if dir.x > 0.0 else screen.position.x) - c.x) / dir.x
	var ty := INF if dir.y == 0.0 else ((screen.end.y if dir.y > 0.0 else screen.position.y) - c.y) / dir.y
	var edge := c + dir * minf(tx, ty)
	var pulse := 1.0 + 0.15 * sin(_t * 8.0)
	var pts := PackedVector2Array([
		edge + dir * 16.0 * pulse,
		edge + dir.rotated(2.4) * 12.0 * pulse,
		edge + dir.rotated(-2.4) * 12.0 * pulse,
	])
	_canvas.draw_colored_polygon(pts, C_GOOD)
	_text(edge - dir * 28.0 + Vector2(-30, 5), "SAÍDA", 13, C_GOOD, HORIZONTAL_ALIGNMENT_CENTER, 60)


func _draw_title(size: Vector2) -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0818"))
	# faixas diagonais animadas
	for i in 14:
		var x := fmod(i * 140.0 + _t * 60.0, size.x + 400.0) - 200.0
		var c := Color(C_ACCENT, 0.05) if i % 3 == 0 else Color(C_FOCUS, 0.03)
		_canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(x, 0), Vector2(x + 40, 0), Vector2(x - 160, size.y), Vector2(x - 200, size.y)]), c)
	# "corte" atravessando o título
	var slash_k := clampf(_mode_t / 0.35, 0.0, 1.0)
	var y := size.y * 0.36
	_canvas.draw_line(Vector2(size.x * 0.15, y + 30), Vector2(lerpf(size.x * 0.15, size.x * 0.85, slash_k), y - 40 + 70 * (1.0 - slash_k)), Color(C_ACCENT, 0.8), 3.0)
	_center_text(y, "VANGUARD", 96, C_TEXT)
	_center_text(y + 44, "protótipo 02  ·  ação com lâmina  ·  um golpe mata", 18, C_DIM)
	if int(_t * 2.0) % 2 == 0 or _mode_t < 0.5:
		_center_text(size.y * 0.6, "CLIQUE PARA JOGAR", 26, C_ACCENT)
	var lines := [
		"A / D  mover        ESPAÇO / W  pular (também na parede)",
		"CLIQUE ESQUERDO  golpe na direção do mouse  (rebate balas!)",
		"S / CTRL  rolamento invencível        SHIFT  câmera lenta",
		"R  reiniciar fase        ESC  pausa        F11  tela cheia",
	]
	for i in lines.size():
		_center_text(size.y * 0.72 + i * 26, lines[i], 16, C_DIM)


func _draw_finished(size: Vector2) -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color("#0b0818"))
	_center_text(size.y * 0.38, "FIM DO PROTÓTIPO", 60, C_GOOD)
	var total: float = info.get("total", 0.0)
	_center_text(size.y * 0.38 + 50, "tempo total %s    mortes %d" % [_fmt_time(total), Game.deaths], 20, C_TEXT)
	_center_text(size.y * 0.38 + 84, "obrigado por testar — mande feedback para a equipe", 16, C_DIM)
	if _mode_t > 0.6:
		_center_text(size.y * 0.7, "clique para voltar ao início", 18, C_ACCENT)


func _draw_pause(size: Vector2) -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.05, 0.7))
	_center_text(size.y * 0.4, "PAUSA", 56, C_TEXT)
	_center_text(size.y * 0.4 + 48, "ESC  continuar      R  reiniciar fase      Q  menu inicial", 18, C_DIM)


func _draw_crosshair() -> void:
	var m := _canvas.get_local_mouse_position()
	var c := C_FOCUS if Game.slowmo_active else C_TEXT
	_canvas.draw_arc(m, 9.0, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 4.0)
	_canvas.draw_arc(m, 9.0, 0.0, TAU, 24, c, 2.0)
	_canvas.draw_circle(m, 2.0, C_ACCENT)


func _fmt_time(t: float) -> String:
	var m := int(t / 60.0)
	var s := fmod(t, 60.0)
	return "%02d:%05.2f" % [m, s]
