shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D texture_albedo : source_color;

instance uniform vec3 person_color = vec3(0.0);
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
		vec4 tex_color = texture(texture_albedo, UV);

		if (tex_color.a < 0.01) {
			discard;
		}

		ALBEDO = clamp(tex_color.rgb + person_color, 0.0, 1.0);
		ALPHA = tex_color.a;
	}
}
