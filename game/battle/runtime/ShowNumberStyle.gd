extends RefCounted
## Colours of the result numbers that float over the map and the cut-in result line.
## The original's defProcShowNumber (0x408580) draws every number from its kind's digit set
## and no sign glyph: kind 0 damage NUM1xx (red), kind 2 heal NUM2xx (green), kind 3 MP
## NUM3xx (blue), kind 5 MISS NUM513 (red on white). The remake keeps Label text, so each
## kind takes one representative palette entry of its digit set; captions the original has
## no glyph for (status names, cure results) stay white.
## provenance:
##   rules: n/a
##   layout: resource-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   strings: static-derived docs/evidence_packets/static_reverse/original_skill_function_bits.md
##   timing: n/a
##   audio: n/a

## NUM1xx: (255,182,180) light, (255,125,123) shade — the shade reads as red on the map.
const DAMAGE := Color8(255, 125, 123)
## NUM2xx: (189,230,164) light, (148,218,115) mid, (115,206,74) shade.
const HEAL := Color8(148, 218, 115)
## NUM3xx: (189,226,246) light, (131,206,238) shade.
const MP := Color8(131, 206, 238)
## NUM513 MISS: (255,97,98) red strokes on white.
const MISS := Color8(255, 97, 98)
## Status and cure captions have no original glyph.
const CAPTION := Color.WHITE
const KIND_COLORS := {"damage": DAMAGE, "heal": HEAL, "mp": MP, "miss": MISS, "caption": CAPTION}


## Colour of a result part by its kind (`BattleCombatCutin.feedback_parts` kinds).
static func color(kind: String) -> Color:
	if not KIND_COLORS.has(kind):
		push_error("unknown result number kind: %s" % kind)
		return CAPTION
	return KIND_COLORS[kind]
