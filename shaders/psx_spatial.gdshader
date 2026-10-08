shader_type spatial;
render_mode vertex_lighting, cull_back, diffuse_lambert, specular_disabled;

// PS1 look, spec 4.2 and 4.4. The vertex stage and the shared fragment helpers (texel, fog)
// are in psx_spatial_common.gdshaderinc, which psx_spatial_glass.gdshader also includes.
#include "res://shaders/psx_spatial_common.gdshaderinc"

void fragment() {
	vec3 albedo;
	vec3 emission;
	// In fragment(), VERTEX is the view-space position, so -z is depth.
	psx_fog(psx_texel().rgb, VERTEX.z, albedo, emission);
	ALBEDO = albedo;
	EMISSION = emission;
}
