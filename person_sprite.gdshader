shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

uniform sampler2D texture_albedo : source_color;

// Magenta transparency color (0xFF00FF)
const vec3 MAGENTA = vec3(1.0, 0.0, 1.0);

void fragment() {
	vec4 tex_color = texture(texture_albedo, UV);

	// Calculate how "magenta" this pixel is (0 = not magenta, 1 = pure magenta)
	float magenta_amount = 1.0 - distance(tex_color.rgb, MAGENTA) / 1.732; // max distance is sqrt(3)

	// Make magenta pixels transparent (smooth falloff for anti-aliased edges)
	float alpha = 1.0 - smoothstep(0.3, 1.0, magenta_amount);

	ALBEDO = tex_color.rgb;
	ALPHA = alpha * tex_color.a;
}
