shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// ---- Tweakable parameters ----
uniform vec3 body_color : source_color = vec3(0.01, 0.01, 0.012); // glossy black
uniform vec3 marking_color : source_color = vec3(0.62, 0.02, 0.03); // hourglass red
uniform float gloss : hint_range(0.0, 1.0) = 0.92;      // how shiny the carapace is
uniform float roughness_base : hint_range(0.0, 1.0) = 0.15;

// Hourglass placement & shape (in UV space of the abdomen)
uniform vec2 hourglass_center = vec2(0.5, 0.5); // UV center on the underside
uniform float hourglass_height : hint_range(0.05, 1.0) = 0.42; // vertical extent
uniform float hourglass_width : hint_range(0.05, 1.0) = 0.30;  // max half-width at top/bottom
uniform float waist_pinch : hint_range(0.0, 1.0) = 0.85;       // how tight the middle pinch is
uniform float edge_softness : hint_range(0.0, 0.1) = 0.015;

// Underside mask: only show marking where the surface faces "down"
uniform float underside_bias : hint_range(-1.0, 1.0) = -0.35; // threshold on N.y
uniform float underside_softness : hint_range(0.0, 1.0) = 0.25;

// Subtle sheen / iridescence like real black widow cuticle
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.15;

varying vec3 world_normal;

uniform vec3 marking_direction = vec3(0.0, 1.0, 0.0);

varying vec3 local_normal;

void vertex() {
	// Object-space normal — independent of the node's rotation in the world.
	local_normal = normalize(NORMAL);
}

// Signed distance-ish field for a symmetric hourglass shape in local UV space
float hourglass_sdf(vec2 uv, vec2 center, float h, float w, float pinch) {
	vec2 p = uv - center;
	// normalize vertical extent to [-1, 1] across the hourglass height
	float t = clamp(p.y / (h * 0.5), -1.0, 1.0);
	// half-width tapers from full width at top/bottom to a pinched waist at center
	float taper = mix(1.0, pinch, 1.0 - abs(t));
	float half_width_here = w * 0.5 * (1.0 - taper * 0.85);
	// distance outside the shape (negative = inside)
	float dx = abs(p.x) - max(half_width_here, 0.01);
	float dy = abs(p.y) - h * 0.5;
	return max(dx, dy);
}

void fragment() {
	// --- Hourglass mask ---
	float d = hourglass_sdf(UV, hourglass_center, hourglass_height, hourglass_width, waist_pinch);
	float hourglass_mask = 1.0 - smoothstep(0.0, edge_softness, d);

	// --- Restrict marking to one side via LOCAL-space normal ---
	float facing_target = dot(normalize(local_normal), normalize(marking_direction));
	float underside_mask = smoothstep(underside_bias - underside_softness,
	                                   underside_bias + underside_softness,
	                                   facing_target);

	float marking = hourglass_mask * underside_mask;

	// --- Base glossy black cuticle with a faint sheen highlight ---
	vec3 albedo = mix(body_color, marking_color, marking);

	// cheap sheen: brighten albedo slightly based on view-facing normal to fake iridescent cuticle
	float sheen = pow(clamp(dot(normalize(world_normal), vec3(0.0, 1.0, 0.0)), 0.0, 1.0), 3.0);
	albedo += sheen * sheen_strength * vec3(0.05, 0.05, 0.08) * (1.0 - marking);

	ALBEDO = albedo;
	METALLIC = 0.0;
	SPECULAR = gloss;
	ROUGHNESS = mix(roughness_base, 0.35, marking); // marking slightly less glossy than cuticle
}