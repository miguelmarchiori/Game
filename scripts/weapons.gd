extends RefCounted
## TABELA DE ARMAS — ajuste o balanceamento aqui.
##   tipo "tiro":  dmg por projétil, cadencia (s entre tiros), municao, auto (segurar),
##                 projeteis, dispersao (rad), vel, alcance (vida do projétil em s),
##                 recuo (empurra o jogador; escopeta no ar = "pulo de escopeta")
##   tipo "corpo": dmg, dur (duração do golpe), alcance (px), kb (empurrão),
##                 atordoa (s), derruba, rebate (rebate balas!), quebra (some após 1 golpe)
##   arremesso: dano ao ACERTAR o inimigo jogando a arma (botão direito)
##   len: comprimento do desenho (px)

const DATA := {
	"pistola": {
		"nome": "PISTOLA", "tipo": "tiro", "dmg": 34, "cadencia": 0.2, "municao": 12, "auto": false,
		"projeteis": 1, "dispersao": 0.03, "vel": 1500.0, "alcance": 1.0, "recuo": 60.0,
		"kb": 220.0, "som": "shot", "arremesso": 22, "len": 18,
	},
	"escopeta": {
		"nome": "ESCOPETA", "tipo": "tiro", "dmg": 16, "cadencia": 0.75, "municao": 6, "auto": false,
		"projeteis": 7, "dispersao": 0.36, "vel": 1250.0, "alcance": 0.33, "recuo": 420.0,
		"kb": 300.0, "som": "shotgun", "arremesso": 26, "len": 32,
	},
	"metralhadora": {
		"nome": "SUBMETRALHADORA", "tipo": "tiro", "dmg": 14, "cadencia": 0.075, "municao": 30, "auto": true,
		"projeteis": 1, "dispersao": 0.09, "vel": 1450.0, "alcance": 0.9, "recuo": 30.0,
		"kb": 120.0, "som": "smg", "arremesso": 22, "len": 24,
	},
	"taco": {
		"nome": "TACO", "tipo": "corpo", "dmg": 32, "dur": 0.34, "alcance": 72.0, "kb": Vector2(640, -240),
		"atordoa": 0.55, "derruba": true, "rebate": true, "som": "bat", "arremesso": 24, "len": 40,
	},
	"faca": {
		"nome": "FACA", "tipo": "corpo", "dmg": 26, "dur": 0.18, "alcance": 50.0, "kb": Vector2(160, -40),
		"atordoa": 0.3, "derruba": false, "rebate": false, "som": "slash", "arremesso": 65, "len": 20,
	},
	"espada": {
		"nome": "ESPADA", "tipo": "corpo", "dmg": 44, "dur": 0.28, "alcance": 80.0, "kb": Vector2(320, -120),
		"atordoa": 0.4, "derruba": false, "rebate": true, "som": "slash", "arremesso": 40, "len": 48,
	},
	"garrafa": {
		"nome": "GARRAFA", "tipo": "corpo", "dmg": 30, "dur": 0.3, "alcance": 52.0, "kb": Vector2(260, -140),
		"atordoa": 1.0, "derruba": false, "rebate": false, "quebra": true, "som": "glass", "arremesso": 30, "len": 22,
	},
}

const C_METAL := Color("#2b2f35")
const C_METAL_LIGHT := Color("#59616b")
const C_WOOD := Color("#c8955a")
const C_STEEL := Color("#dfe6ee")
const C_GRIP := Color("#1c1c1e")
const C_GLASS := Color(0.35, 0.75, 0.45, 0.85)


static func is_gun(kind: String) -> bool:
	return DATA.has(kind) and DATA[kind]["tipo"] == "tiro"


## Desenha a arma com o cabo em `pos`, apontando para `angle`.
## flip_y = -1 espelha (arma apontada para a esquerda não fica de cabeça para baixo).
static func draw(ci: CanvasItem, kind: String, pos: Vector2, angle: float, flip_y := 1.0, scale := 1.0) -> void:
	ci.draw_set_transform(pos, angle, Vector2(scale, flip_y * scale))
	match kind:
		"pistola":
			ci.draw_rect(Rect2(-3, -4, 20, 6), C_METAL)
			ci.draw_rect(Rect2(-3, -4, 20, 2), C_METAL_LIGHT)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-2, 2), Vector2(4, 2), Vector2(2, 10), Vector2(-4, 9)]), C_GRIP)
		"escopeta":
			ci.draw_rect(Rect2(-4, -4, 36, 5), C_METAL)
			ci.draw_rect(Rect2(8, 1, 14, 4), C_WOOD.darkened(0.2))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-4, -4), Vector2(-4, 2), Vector2(-16, 6), Vector2(-17, -1)]), C_WOOD)
		"metralhadora":
			ci.draw_rect(Rect2(-4, -5, 22, 8), C_METAL)
			ci.draw_rect(Rect2(18, -3, 8, 3), C_METAL_LIGHT)
			ci.draw_rect(Rect2(6, 3, 5, 11), C_GRIP)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-2, 3), Vector2(3, 3), Vector2(1, 10), Vector2(-4, 9)]), C_GRIP)
		"taco":
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-6, -2), Vector2(36, -4.5), Vector2(40, 0), Vector2(36, 4.5), Vector2(-6, 2)]), C_WOOD)
			ci.draw_rect(Rect2(-6, -2.5, 10, 5), C_GRIP)
		"faca":
			ci.draw_rect(Rect2(-6, -2, 8, 4.5), C_GRIP)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(2, -2.5), Vector2(18, -1), Vector2(21, 0.5), Vector2(2, 3)]), C_STEEL)
		"espada":
			ci.draw_rect(Rect2(-9, -2, 10, 4), C_GRIP)
			ci.draw_rect(Rect2(1, -5, 3, 10), Color("#b8963a"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(4, -2.5), Vector2(46, -1.5), Vector2(50, 0.5), Vector2(4, 2.5)]), C_STEEL)
		"garrafa":
			ci.draw_rect(Rect2(-6, -2, 9, 4), C_GLASS.darkened(0.2))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(3, -3), Vector2(8, -6), Vector2(20, -6), Vector2(20, 6), Vector2(8, 6), Vector2(3, 3)]), C_GLASS)
			ci.draw_line(Vector2(9, -4), Vector2(18, -4), Color(1, 1, 1, 0.5), 1.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
