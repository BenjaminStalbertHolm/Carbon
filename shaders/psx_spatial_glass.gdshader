shader_type spatial;
// Frosted glass (spec 5.2, decision QUESTION-45). The same PS1 vertex snap, affine mapping,
// vertex lighting and fog as psx_spatial.gdshader, drawn as a standard alpha blend. The alpha
// is albedo_color.a times the texture alpha; the frosted texture is alpha 178 (0.7).
// depth_draw_opaque: the glass does not write depth, so it never hides what is behind it.
render_mode blend_mix, depth_draw_opaque, cull_back, vertex_lighting, diffuse_lambert, specular_disabled;

#include "res://shaders/psx_spatial_common.gdshaderinc"

void fragment() {
	vec4 texel = psx_texel();
	vec3 albedo;
	vec3 emission;
	// VERTEX is the view-space position here, so its z is negative in front of the camera.
	psx_fog(texel.rgb, VERTEX.z, albedo, emission);
	ALBEDO = albedo;
	EMISSION = emission;
	ALPHA = texel.a;
}
