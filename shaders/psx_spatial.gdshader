shader_type spatial;
render_mode vertex_lighting, cull_back, diffuse_lambert, specular_disabled;

// PS1 look, spec 4.2 and 4.4. The snap grid is half the internal resolution
// (160x120 at 320x240, 320x240 at 640x480). PsxPipeline sets it globally.
global uniform vec2 psx_snap_grid;

uniform sampler2D albedo_tex : source_color, filter_nearest, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform float emission_strength = 0.0;

// Linear depth fog: colour #2A2A26, 6.0 m to 18.0 m, max density 1.0.
const vec3 FOG_COLOR = vec3(0.164706, 0.164706, 0.149020);
const float FOG_START = 6.0;
const float FOG_END = 18.0;
const float FOG_MAX_DENSITY = 1.0;

// Affine texture mapping: UV and w are interpolated, and divided per pixel.
varying vec2 affine_uv;
varying float affine_w;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	// Vertex snapping: snap screen-space x and y to the grid, keeping w.
	vec2 ndc = clip.xy / clip.w;
	ndc = floor(ndc * psx_snap_grid) / psx_snap_grid;
	clip.xy = ndc * clip.w;
	POSITION = clip;
	affine_uv = UV * uv_scale * clip.w;
	affine_w = clip.w;
}

void fragment() {
	vec3 base = texture(albedo_tex, affine_uv / affine_w).rgb * albedo_color.rgb;
	// In fragment(), VERTEX is the view-space position, so -z is depth.
	float fog = clamp((-VERTEX.z - FOG_START) / (FOG_END - FOG_START), 0.0, 1.0) * FOG_MAX_DENSITY;
	// Fog is mixed in after lighting: the lit colour is scaled down, and the
	// fog colour is added as emission.
	ALBEDO = base * (1.0 - fog);
	EMISSION = base * emission_strength * (1.0 - fog) + FOG_COLOR * fog;
}
