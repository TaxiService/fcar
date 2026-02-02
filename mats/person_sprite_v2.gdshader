shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D texture_albedo : source_color;
uniform int sprite_columns = 11;

instance uniform vec3 person_color = vec3(0.0);
instance uniform float sprite_index = 0.0;
instance uniform float pixel_lod = 0.0;

void vertex() {
	// Billboard: make sprite always face camera
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	if (pixel_lod > 0.5) {
		ALBEDO = person_color;
		ALPHA = 1.0;
	} else {
		// Offset UV.x to select the correct sprite slice from the horizontal strip
		float col_f = float(sprite_columns);
		vec2 uv = UV;
		uv.x = (uv.x + sprite_index) / col_f;

		vec4 tex_color = texture(texture_albedo, uv);

		if (tex_color.a < 0.01) {
			discard;
		}

		ALBEDO = clamp(tex_color.rgb + person_color, 0.0, 1.0);
		ALPHA = tex_color.a;
	}
}
