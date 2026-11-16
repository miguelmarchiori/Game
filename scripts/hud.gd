extends CanvasLayer
## Interface do playground: vida, FOCO (câmera lenta), arma e munição, contador de combo,
## barra de spawn (teclas 1-0), ajuda, avisos, mira e telas de pausa/nocaute.
## Tudo desenhado por código em um único Control.

const Weapons := preload("res://scripts/weapons.gd")

## Nome exibido (provisório — troque quando o jogo tiver nome).
const GAME_TITLE := "PROTÓTIPO 03"

const C_TEXT := Color("#ece8e1")
const C_DIM := Color(0.85, 0.83, 0.8, 0.6)
const C_ACCENT := Color("#ff8a2b")
const C_FOCUS := Color("#3fd6c6")
const C_BAD := Color("#ff4a3d")
const C_PANEL := Color(0.06, 0.07, 0.08, 0.72)

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
	col = mix(col, vec3(g) * vec3(0.85, 1.05, 1.1), amount * 0.55);
	float vig = smoothstep(0.3, 0.85, distance(uv, vec2(0.5)));
	col *= 1.0 - vig * amount * 0.6;
	COLOR = vec4(col, 1.0);
}
"""

var main: Node
var paused := false

var _canvas: Control
var _overlay: ColorRect
var _overlay_mat: ShaderMaterial
var _t := 0.0
var _msg := ""
var _msg_t := 0.0
var _hp_trail := 100.0


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


func message(text: String, duration := 1.6) -> void:
	_msg = text
	_msg_t = duration


func _process(delta: float) -> void:
	var real_dt := delta if paused else delta / maxf(Engine.time_scale, 0.01)
	_t += real_dt
	_msg_t = maxf(0.0, _msg_t - real_dt)
	_overlay.visible = Game.slowmo_amount > 0.01
	_overlay_mat.set_shader_parameter("amount", Game.slowmo_amount)
	if main and is_instance_valid(main.player):
		_hp_trail = move_toward(_hp_trail, main.player.health, 60.0 * real_dt)
		_hp_trail = maxf(_hp_trail, main.player.health)
	_canvas.queue_redraw()


# ------------------------------------------------------------- desenho ---

func _text(pos: Vector2, s: String, font_size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var font := ThemeDB.fallback_font
	_canvas.draw_string_outline(font, pos, s, align, width, font_size, maxi(4, font_size / 5), Color(0.02, 0.02, 0.03, 0.9 * color.a))
	_canvas.draw_string(font, pos, s, align, width, font_size, color)


func _center_text(y: float, s: String, font_size: int, color: Color) -> void:
	_text(Vector2(0, y), s, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, _canvas.size.x)


func _text_width(s: String, font_size: int) -> float:
	return ThemeDB.fallback_font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


func _on_draw() -> void:
	var size := _canvas.size
	if main == null or not is_instance_valid(main.player):
		return
	var p: Node = main.player
	_draw_hurt(size, p)
	_draw_vitals(p)
	_draw_weapon(size, p)
	_draw_combo(size)
	_draw_prompts(size, p)
	if main.show_spawn:
		_draw_spawn_bar(size)
	if main.show_help:
		_draw_help(size)
	if _msg_t > 0.0:
		_center_text(96, _msg, 20, Color(C_TEXT, clampf(_msg_t / 0.3, 0.0, 1.0)))
	if not p.is_alive():
		_center_text(size.y * 0.4, "NOCAUTE", 58, C_BAD)
		_center_text(size.y * 0.4 + 40, "renascendo...  (R para voltar já)", 18, C_TEXT)
	if paused:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.72))
		_center_text(size.y * 0.38, "PAUSA", 56, C_TEXT)
		_center_text(size.y * 0.38 + 46, "ESC  continuar        BACKSPACE  resetar o playground", 18, C_DIM)
		_draw_help(size, size.y * 0.5)
	_draw_crosshair(p)


func _draw_hurt(size: Vector2, p: Node) -> void:
	var hurt: float = main.hurt_flash
	var low := 0.0
	if p.is_alive() and p.health < 35.0:
		low = (0.5 + 0.5 * sin(_t * 6.0)) * 0.35
	var a := maxf(hurt * 0.5, low)
	if a <= 0.01:
		return
	var w := 70.0
	var c := Color(0.9, 0.08, 0.05, a)
	var clear := Color(0.9, 0.08, 0.05, 0.0)
	var r := Rect2(Vector2.ZERO, size)
	_canvas.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, 0), Vector2(r.end.x, w), Vector2(0, w)]), PackedColorArray([c, c, clear, clear]))
	_canvas.draw_polygon(PackedVector2Array([Vector2(0, r.end.y - w), Vector2(r.end.x, r.end.y - w), r.end, Vector2(0, r.end.y)]), PackedColorArray([clear, clear, c, c]))
	_canvas.draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(w, 0), Vector2(w, r.end.y), Vector2(0, r.end.y)]), PackedColorArray([c, clear, clear, c]))
	_canvas.draw_polygon(PackedVector2Array([Vector2(r.end.x - w, 0), Vector2(r.end.x, 0), r.end, Vector2(r.end.x - w, r.end.y)]), PackedColorArray([clear, c, c, clear]))


func _draw_vitals(p: Node) -> void:
	_canvas.draw_rect(Rect2(14, 12, 300, 62), C_PANEL)
	_text(Vector2(24, 33), "VIDA", 15, C_DIM)
	var frac := clampf(p.health / p.max_health, 0.0, 1.0)
	var trail := clampf(_hp_trail / p.max_health, 0.0, 1.0)
	var bar := Rect2(76, 20, 224, 14)
	_canvas.draw_rect(bar, Color(1, 1, 1, 0.08))
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * trail, bar.size.y)), Color(1, 1, 1, 0.5))
	var col := C_BAD.lerp(C_ACCENT, clampf(frac * 2.0, 0.0, 1.0)).lerp(Color("#9be15d"), clampf(frac * 2.0 - 1.0, 0.0, 1.0))
	_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), col)
	if Game.god_mode:
		_text(Vector2(bar.position.x + 4, 32), "MODO DEUS", 12, Color.BLACK)
	_text(Vector2(24, 61), "FOCO", 15, C_DIM)
	var cells := 12
	var filled := int(ceil(Game.battery * cells - 0.001))
	var fc := C_ACCENT if Game.slowmo_active else C_FOCUS
	for i in cells:
		var r := Rect2(76 + i * 16, 48, 12, 14)
		_canvas.draw_rect(r, Color(fc, 0.15))
		if i < filled:
			_canvas.draw_rect(r, fc)
	_text(Vector2(272, 61), "[Q]", 13, C_DIM)


func _draw_weapon(size: Vector2, p: Node) -> void:
	var box := Rect2(size.x - 274, 12, 260, 62)
	_canvas.draw_rect(box, C_PANEL)
	var w: String = p.weapon
	if w == "":
		_text(Vector2(box.position.x + 14, 38), "MÃOS LIVRES", 20, C_TEXT)
		_text(Vector2(box.position.x + 14, 60), "soco · chute · voadora", 13, C_DIM)
		return
	var d: Dictionary = Weapons.DATA[w]
	Weapons.draw(_canvas, w, Vector2(box.end.x - 70 - float(d["len"]), 44), 0.0, 1.0, 1.6)
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_text(Vector2(box.position.x + 14, 38), String(d["nome"]), 18, C_TEXT)
	if Weapons.is_gun(w):
		var ammo_col := C_BAD if p.ammo == 0 else C_ACCENT
		_text(Vector2(box.position.x + 14, 62), "%02d / %02d" % [p.ammo, int(d["municao"])], 18, ammo_col)
	else:
		_text(Vector2(box.position.x + 14, 60), "corpo a corpo" + ("  · rebate balas" if d.get("rebate", false) else ""), 13, C_DIM)


func _draw_combo(size: Vector2) -> void:
	var combo: int = main.combo
	if combo < 2:
		return
	var a := clampf(main.combo_t / 0.4, 0.0, 1.0)
	var pop: float = main.combo_pop
	var font_size := int(46 + pop * 16)
	var x := size.x - 30.0
	_text(Vector2(x - 300, 150), "x%d" % combo, font_size, Color(C_ACCENT, a), HORIZONTAL_ALIGNMENT_RIGHT, 300)
	_text(Vector2(x - 300, 176), "COMBO  ·  %d de dano" % main.combo_damage, 14, Color(C_TEXT, a), HORIZONTAL_ALIGNMENT_RIGHT, 300)


func _draw_prompts(size: Vector2, p: Node) -> void:
	var y := size.y - (96.0 if main.show_spawn else 40.0)
	if p.is_alive() and is_instance_valid(p.near_item):
		var nome := String(Weapons.DATA[p.near_item.kind]["nome"])
		var verb := "trocar por" if p.weapon != "" else "pegar"
		_center_text(y, "[E] %s %s" % [verb, nome], 18, C_ACCENT)
		y -= 26
	if p.empty_warning > 0.0:
		_center_text(y, "SEM MUNIÇÃO — botão direito para arremessar a arma", 16, C_BAD)


func _draw_spawn_bar(size: Vector2) -> void:
	var h := 62.0
	var top := size.y - h
	_canvas.draw_rect(Rect2(0, top, size.x, h), C_PANEL)
	var spawns: Array = main.SPAWNS
	var x := 14.0
	for s: Dictionary in spawns:
		var label := String(s["nome"])
		var key := String(s["tecla"])
		var w := _text_width(label, 13) + 34.0
		var is_enemy := s.has("inimigo")
		var col := Color("#e0574a") if is_enemy else C_ACCENT
		_canvas.draw_rect(Rect2(x, top + 8, w, 22), Color(col, 0.16))
		_canvas.draw_rect(Rect2(x, top + 8, 20, 22), Color(col, 0.85))
		_text(Vector2(x + 5, top + 24), key, 13, Color.BLACK)
		_text(Vector2(x + 26, top + 24), label, 13, C_TEXT)
		x += w + 6.0
	var ai := "LIGADA" if Game.ai_enabled else "DESLIGADA"
	var god := "LIGADO" if Game.god_mode else "DESL."
	var line := "teclas 1-0 e -: criar na mira    I  IA: %s    G  modo deus: %s    X  limpar inimigos    C  limpar armas    BACKSPACE  resetar    TAB  esconder    H  ajuda" % [ai, god]
	_text(Vector2(14, top + 50), line, 12, C_DIM)


func _draw_help(size: Vector2, y0 := -1.0) -> void:
	var cols := [
		["MOVIMENTO", [
			"A / D  correr (segure para acelerar)",
			"ESPAÇO / W  pular · na parede: pula de novo",
			"SHIFT  dash (8 direções, 1 no ar)",
			"S correndo  deslizar (passa em vão baixo)",
			"S parado  agachar · no ar: mergulho",
			"corra contra degraus / bordas: sobe sozinho",
		]],
		["COMBATE", [
			"CLIQUE  soco, soco, chute (combo)",
			"mira para cima  gancho (lança pro alto)",
			"no ar  voadora na direção do mouse",
			"deslizando + clique  rasteira",
			"logo após o dash + clique  soco investida",
			"F  chute frontal (empurra longe)   Q  câmera lenta",
		]],
		["ARMAS", [
			"E  pegar / trocar arma do chão",
			"CLIQUE  atirar / golpear",
			"BOTÃO DIREITO  arremessar a arma",
			"taco e espada rebatem balas",
			"escopeta no ar empurra você (pulo extra)",
			"R  renascer    ESC  pausa    F11  tela cheia",
		]],
	]
	var w := 330.0
	var total := w * cols.size() + 20.0 * (cols.size() - 1) + 40.0
	var x0 := (size.x - total) * 0.5
	var top := y0 if y0 > 0.0 else 96.0
	if y0 < 0.0:
		_canvas.draw_rect(Rect2(x0, top - 8, total, 190), C_PANEL)
		_text(Vector2(x0 + 20, top + 18), GAME_TITLE + "  ·  PLAYGROUND", 16, C_ACCENT)
		_text(Vector2(x0 + total - 220, top + 18), "H  fechar ajuda", 13, C_DIM, HORIZONTAL_ALIGNMENT_RIGHT, 200)
		top += 34
	for i in cols.size():
		var cx := x0 + 20.0 + i * (w + 20.0)
		_text(Vector2(cx, top + 10), String(cols[i][0]), 14, C_FOCUS)
		var lines: Array = cols[i][1]
		for j in lines.size():
			_text(Vector2(cx, top + 32 + j * 22), String(lines[j]), 13, C_TEXT)


func _draw_crosshair(p: Node) -> void:
	var m := _canvas.get_local_mouse_position()
	var r := 9.0
	if p.weapon != "" and Weapons.is_gun(p.weapon):
		r = 8.0 + float(Weapons.DATA[p.weapon]["dispersao"]) * 40.0
	var c := C_FOCUS if Game.slowmo_active else C_TEXT
	_canvas.draw_arc(m, r, 0.0, TAU, 28, Color(0, 0, 0, 0.6), 4.0)
	_canvas.draw_arc(m, r, 0.0, TAU, 28, c, 2.0)
	_canvas.draw_circle(m, 2.0, C_ACCENT)
