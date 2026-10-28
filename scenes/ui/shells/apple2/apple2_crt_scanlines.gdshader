shader_type canvas_item;

// Godot 4 screen sampler to read the rendered UI behind the ColorRect
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

uniform float scanline_density : hint_range(100.0, 800.0) = 380.0;
uniform float scanline_opacity : hint_range(0.0, 0.5) = 0.18;
uniform float phosphor_bloom : hint_range(0.0, 0.5) = 0.08;
uniform vec4 tint_color : source_color = vec4(0.2, 1.0, 0.2, 1.0);

void fragment() {
	vec2 uv = SCREEN_UV;
	
	// Subtle CRT scanline calculation
	vec4 base_color = texture(screen_texture, UV);
	
	// Darken every other line
	float scanline = sin(uv.y * scanline_density * 3.14159) * 0.5 + 0.5;
	base_color.rgb -= scanline * scanline_opacity;
	
	// Slight green phosphor tint multiplier
	base_color.rgb = mix(base_color.rgb, base_color.rgb * tint_color.rgb, phosphor_bloom);
	
	COLOR = base_color;
}