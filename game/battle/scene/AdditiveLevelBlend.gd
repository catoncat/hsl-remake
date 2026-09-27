extends RefCounted
## The original's saturating-add draw with a level (display-list modes with bit 0x4000000, e.g.
## engADDCOLOR 0x4000000, engADDCOLOR_MIX 0x24000000, 0x2c000000 = add＋zoom＋level): kind 8
## (0x462154) or its zoomed twin kind 9 (0x462e8b) of the pixel-kind table 0x46211c, picked by
## 0x46b733 from table 0x46b6b1[(mode >> 25) & 7]. Per RGB565 pixel:
##   s = mode & 0x20000000 ? T[level][src] : src   (0x462240／0x4623e1; 0x462fd7 in kind 9)
##   dst = s + dst with each channel's carry-out OR-ing that channel to full (0x4bbbec, 0x461025)
## where T[level] (0x460e9c, 17 tables at 0x4bfbf0, 0x461247) scales each channel with an integer
## floor: r5·level／16, g6·level／16, b5·level／16. The kernel's carries leak one step into the
## next channel before the OR; that and the 16-bit destination are not reproduced (sub-1/32 steps).
## A draw's level is its modulate alpha × 16 (1.0 = level 16 = plain add); modulate rgb tints src.
## provenance:
##   layout: static-derived docs/evidence_packets/runtime_observations/map_pose_floaters/README.md

const LEVELS := 16

const SHADER_CODE := """
shader_type canvas_item;
render_mode blend_add;

varying vec4 draw_modulate;

void vertex() {
	draw_modulate = COLOR;
}

void fragment() {
	vec4 src = texture(TEXTURE, UV);
	vec3 steps = vec3(31.0, 63.0, 31.0);
	float level = clamp(round(draw_modulate.a * 16.0), 0.0, 16.0);
	vec3 scaled = floor(round(src.rgb * steps) * level / 16.0) / steps;
	COLOR = vec4(scaled * draw_modulate.rgb, src.a);
}
"""

static var _material: ShaderMaterial


## One shared material for every additive level draw (sprites keep batching together).
static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = SHADER_CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
	return _material


## The level a draw modulate alpha stands for (the same rounding the shader uses).
static func alpha(level: int) -> float:
	return clampf(float(level), 0.0, float(LEVELS)) / float(LEVELS)
