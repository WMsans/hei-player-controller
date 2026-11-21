shader_type spatial;
// World-space checker, so speed is readable on every surface.

uniform vec3 color_a : source_color = vec3(0.32, 0.40, 0.36);
uniform vec3 color_b : source_color = vec3(0.26, 0.33, 0.30);
uniform float cell_size = 2.0;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 cell = floor((world_position - world_normal * 0.01) / cell_size);
	ALBEDO = mix(color_a, color_b, mod(cell.x + cell.y + cell.z, 2.0));
	ROUGHNESS = 0.9;
}
