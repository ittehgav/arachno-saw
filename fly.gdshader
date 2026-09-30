shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
 
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 emission : source_color;
uniform float emission_energy : hint_range(0.0, 100.0, 0.01);
 
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
 
void vertex() {
    UV = UV * uv1_scale.xy + uv1_offset.xy;
 
    vec3 billboard = vec3(0.0, 1.0, 1.0);
    vec3 cam_bullet_dir = NODE_POSITION_WORLD -CAMERA_POSITION_WORLD;
    vec3 local_y = MODEL_MATRIX[1].xyz;
    vec4 mmx = vec4(normalize(cross(local_y, cam_bullet_dir)), 0.0);
    vec4 mmy = -vec4(local_y, 0);
    vec4 mmz = vec4(normalize(cross(mmx.xyz, mmy.xyz)), 0.0);
    MODELVIEW_MATRIX = VIEW_MATRIX * mat4(mmx, mmy, mmz, MODEL_MATRIX[3]);
    MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
 
void fragment() {
    vec2 base_uv = UV;
    vec4 albedo_tex = texture(texture_albedo, base_uv);
    ALBEDO = albedo_tex.rgb;
    EMISSION = emission.rgb * emission_energy;
    ALPHA *= albedo_tex.a;
}