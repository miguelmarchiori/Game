extends RefCounted
## "Esqueleto" desenhado por código, usado pelo jogador e pelos inimigos.
##
## Uma POSE é um dicionário com 7 pontos (coordenadas locais, personagem olhando
## para a DIREITA, origem nos pés):
##   hip (quadril), chest (peito/ombros), head (cabeça),
##   hand_f / hand_b (mão da frente / de trás), foot_f / foot_b (pé da frente / de trás)
## Joelhos e cotovelos são calculados sozinhos (cinemática inversa de 2 ossos).
## As animações ficam suaves porque cada personagem INTERPOLA da pose atual
## para a pose alvo a cada quadro (veja blend()).

const KEYS := ["hip", "chest", "head", "hand_f", "hand_b", "foot_f", "foot_b"]
const THIGH := 12.0
const SHIN := 11.5
const UPPER_ARM := 10.0
const FOREARM := 9.5


static func pose(hip: Vector2, chest: Vector2, head: Vector2, hand_f: Vector2, hand_b: Vector2, foot_f: Vector2, foot_b: Vector2) -> Dictionary:
	return {"hip": hip, "chest": chest, "head": head, "hand_f": hand_f, "hand_b": hand_b, "foot_f": foot_f, "foot_b": foot_b}


## Aproxima `current` de `target` (rate maior = mais rápido). Altera `current`.
static func blend(current: Dictionary, target: Dictionary, rate: float, delta: float) -> void:
	var k := 1.0 - exp(-rate * delta)
	for key in KEYS:
		var a: Vector2 = current.get(key, target[key])
		current[key] = a.lerp(target[key], k)


## Junta do meio de um membro com 2 ossos (bend = +1 ou -1 escolhe o lado da dobra).
static func ik(a: Vector2, b: Vector2, l1: float, l2: float, bend: float) -> Vector2:
	var d := a.distance_to(b)
	if d < 0.001:
		return a + Vector2(0, l1)
	var dd := clampf(d, absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	var x := (l1 * l1 - l2 * l2 + dd * dd) / (2.0 * dd)
	var h := sqrt(maxf(0.0, l1 * l1 - x * x))
	var dir := (b - a) / d
	return a + dir * x + Vector2(-dir.y, dir.x) * bend * h


static func limb(ci: CanvasItem, a: Vector2, b: Vector2, l1: float, l2: float, bend: float, color: Color, w: float) -> void:
	var d := b - a
	if d.length() > l1 + l2:
		b = a + d.normalized() * (l1 + l2)
	var j := ik(a, b, l1, l2, bend)
	ci.draw_line(a, j, color, w)
	ci.draw_line(j, b, color, w * 0.92)
	ci.draw_circle(a, w * 0.5, color)
	ci.draw_circle(j, w * 0.48, color)


## Desenha o corpo inteiro. `s` = estilo (cores/medidas), veja STYLE em player.gd/enemy.gd.
static func draw_figure(ci: CanvasItem, p: Dictionary, s: Dictionary) -> void:
	var hip: Vector2 = p["hip"]
	var chest: Vector2 = p["chest"]
	var head: Vector2 = p["head"]
	var lw: float = s.get("limb_w", 6.0)
	var tw: float = s.get("torso_w", 8.0)
	var skin: Color = s["skin"]

	# membros de trás (mais escuros)
	limb(ci, hip + Vector2(-1, 0), p["foot_b"], THIGH, SHIN, -1.0, s["legs_dark"], lw + 0.5)
	_shoe(ci, p["foot_b"], Color(s["shoes"]).darkened(0.25))
	limb(ci, chest + Vector2(-2, 2), p["hand_b"], UPPER_ARM, FOREARM, 1.0, s["top_dark"], lw - 0.5)
	ci.draw_circle(p["hand_b"], 4.0, Color(s["fist"]).darkened(0.2))

	# tronco
	var spine := chest - hip
	if spine.length_squared() < 0.01:
		spine = Vector2(0, -1)
	var n := Vector2(-spine.y, spine.x).normalized()
	ci.draw_circle(hip, tw * 0.85, s["legs"])
	ci.draw_colored_polygon(PackedVector2Array([hip + n * tw * 0.85, hip - n * tw * 0.85, chest - n * tw, chest + n * tw]), s["top"])
	ci.draw_circle(chest, tw, s["top"])
	if s.get("hood", false):
		ci.draw_circle(chest.lerp(head, 0.45) + Vector2(-4, 1), 6.5, s["top_dark"])

	# cabeça
	var hr: float = s.get("head_r", 7.0)
	if s.has("mask"):
		ci.draw_circle(head, hr, s["mask"])
		ci.draw_rect(Rect2(head + Vector2(0.5, -2.5), Vector2(hr + 0.5, 3.0)), s["eye"])
	else:
		ci.draw_circle(head, hr, skin)
		var hair: Color = s["hair"]
		ci.draw_colored_polygon(PackedVector2Array([
			head + Vector2(-hr, 1), head + Vector2(-hr + 1, -5), head + Vector2(-2, -hr - 2),
			head + Vector2(5, -hr - 1), head + Vector2(hr + 1, -3), head + Vector2(3, -4), head + Vector2(-2, -1),
		]), hair)
		ci.draw_rect(Rect2(head + Vector2(3, -2), Vector2(2, 2)), Color(0.1, 0.08, 0.08))  # olho

	# membros da frente
	limb(ci, hip + Vector2(1, 0), p["foot_f"], THIGH, SHIN, -1.0, s["legs"], lw + 0.5)
	_shoe(ci, p["foot_f"], s["shoes"])
	limb(ci, chest + Vector2(1, 1), p["hand_f"], UPPER_ARM, FOREARM, 1.0, s["top"], lw - 0.5)
	ci.draw_circle(p["hand_f"], 4.2, s["fist"])


## Silhueta de uma cor só (rastro do dash, fantasmas).
static func draw_silhouette(ci: CanvasItem, p: Dictionary, c: Color, lw := 6.0) -> void:
	var hip: Vector2 = p["hip"]
	var chest: Vector2 = p["chest"]
	limb(ci, hip, p["foot_b"], THIGH, SHIN, -1.0, c, lw)
	limb(ci, hip, p["foot_f"], THIGH, SHIN, -1.0, c, lw)
	ci.draw_line(hip, chest, c, 14.0)
	limb(ci, chest, p["hand_b"], UPPER_ARM, FOREARM, 1.0, c, lw - 1.0)
	limb(ci, chest, p["hand_f"], UPPER_ARM, FOREARM, 1.0, c, lw - 1.0)
	ci.draw_circle(p["head"], 7.0, c)


static func _shoe(ci: CanvasItem, foot: Vector2, c: Color) -> void:
	ci.draw_rect(Rect2(foot + Vector2(-3, -3.5), Vector2(9, 4)), c)
