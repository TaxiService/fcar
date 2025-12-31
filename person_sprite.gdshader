shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D texture_albedo : source_color;
uniform vec3 color_add : source_color = vec3(0.0, 0.0, 0.0);
uniform bool invert_colors = false;

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
	vec4 tex_color = texture(texture_albedo, UV);

	// Only process non-transparent pixels
	if (tex_color.a < 0.01) {
		ALPHA = 0.0;
	} else {
		vec3 final_color = tex_color.rgb;

		// Apply color addition
		final_color = final_color + color_add;

		// Apply inversion if enabled
		if (invert_colors) {
			final_color = vec3(1.0) - final_color;
		}

		// Clamp to valid range
		final_color = clamp(final_color, 0.0, 1.0);

		ALBEDO = final_color;
		ALPHA = tex_color.a;
	}
}
