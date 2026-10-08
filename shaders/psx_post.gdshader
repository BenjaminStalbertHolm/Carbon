shader_type canvas_item;

// Colour depth and dither, spec 4.3. Each channel is quantised to 5 bits
// (32 levels). An ordered 4x4 Bayer offset of amplitude 1/32 is added first,
// using the internal-resolution pixel coordinate. dither_on = false removes
// the offset and keeps the quantisation.
uniform vec2 internal_res = vec2(320.0, 240.0);
uniform bool dither_on = true;

// 2x2 Bayer ranks, [[0, 2], [3, 1]]. r is the row and c is the column.
float bayer2(float r, float c) {
	if (r < 0.5) {
		return c < 0.5 ? 0.0 : 2.0;
	}
	return c < 0.5 ? 3.0 : 1.0;
}

// 4x4 Bayer rank in 0..15, built from the 2x2 ranks.
float bayer4(vec2 p) {
	vec2 q = mod(floor(p), 4.0);
	float low = bayer2(mod(q.y, 2.0), mod(q.x, 2.0));
	float high = bayer2(mod(floor(q.y / 2.0), 2.0), mod(floor(q.x / 2.0), 2.0));
	return 4.0 * low + high;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float offset = 0.0;
	if (dither_on) {
		// Maps ranks 0..15 onto -1..1, scaled to an amplitude of 1/32.
		offset = ((bayer4(floor(UV * internal_res)) - 7.5) / 7.5) / 32.0;
	}
	vec3 v = clamp(c.rgb + vec3(offset), 0.0, 1.0);
	COLOR = vec4(floor(v * 31.0 + 0.5) / 31.0, c.a);
}
