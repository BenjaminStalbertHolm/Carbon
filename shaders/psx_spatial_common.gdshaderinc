// Shared PS1 spatial code for psx_spatial.gdshader (opaque) and psx_spatial_glass.gdshader
// (frosted glass, alpha blend). Spec 4.2 and 4.4, decision QUESTION-45.
//
// This file is included as text, so vertex() below becomes the vertex stage of each including
// shader. Each including shader declares its own shader_type and render_mode, and its own
// fragment(), which calls the helpers here. Helpers take and return values and never write
// built-ins. Godot only lets varyings be assigned in vertex(), so the affine varying is set
// here, not in a helper.

// The snap grid is half the internal resolution (160x120 at 320x240, 320x240 at 640x480).
// PsxPipeline sets it globally.
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

// Affine texture mapping (spec 4.2): UV times w, and w. Divided per pixel in psx_texel().
varying vec3 psx_affine_uvw;

// Vertex snapping (spec 4.2): transform to clip space, snap screen-space x and y to the grid,
// keep w, and record the affine varying.
void vertex() {
	vec4 clip = PROJECTION_MATRIX * (MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	vec2 ndc = clip.xy / clip.w;
	ndc = floor(ndc * psx_snap_grid) / psx_snap_grid;
	clip.xy = ndc * clip.w;
	POSITION = clip;
	psx_affine_uvw = vec3(UV * uv_scale * clip.w, clip.w);
}

// Texture times albedo_color (spec 4.2). The alpha is the texture alpha times albedo_color's
// alpha, which the glass variant uses as its ALPHA. Call it from fragment().
vec4 psx_texel() {
	vec4 t = texture(albedo_tex, psx_affine_uvw.xy / psx_affine_uvw.z);
	return vec4(t.rgb * albedo_color.rgb, t.a * albedo_color.a);
}

// Fog for one fragment (spec 4.4), from its view-space depth view_z (negative in front of the
// camera). The lit colour is scaled down by the fog, and the fog colour is added as emission.
void psx_fog(vec3 base, float view_z, out vec3 albedo, out vec3 emission) {
	float fog = clamp((-view_z - FOG_START) / (FOG_END - FOG_START), 0.0, 1.0) * FOG_MAX_DENSITY;
	albedo = base * (1.0 - fog);
	emission = base * emission_strength * (1.0 - fog) + FOG_COLOR * fog;
}
