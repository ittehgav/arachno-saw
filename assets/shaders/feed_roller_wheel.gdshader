shader_type spatial;

render_mode cull_back;

uniform vec4 rubber_color : source_color = vec4(0.07, 0.07, 0.07, 1.0);
uniform vec4 worn_color   : source_color = vec4(0.14, 0.14, 0.14, 1.0);

uniform float roughness : hint_range(0.0,1.0) = 0.88;
uniform float metallic = 0.0;

uniform float streak_scale = 120.0;
uniform float wear_scale = 18.0;
uniform float noise_scale = 300.0;

float hash(vec2 p)
{
    return fract(sin(dot(p, vec2(127.1,311.7))) * 43758.5453);
}

float noise(vec2 p)
{
    vec2 i = floor(p);
    vec2 f = fract(p);

    float a = hash(i);
    float b = hash(i + vec2(1.0,0.0));
    float c = hash(i + vec2(0.0,1.0));
    float d = hash(i + vec2(1.0,1.0));

    vec2 u = f*f*(3.0-2.0*f);

    return mix(a,b,u.x)
         + (c-a)*u.y*(1.0-u.x)
         + (d-b)*u.x*u.y;
}

void fragment()
{
    vec2 uv = UV;

    // Long scratches along roller axis
    float streak =
        noise(vec2(uv.x * 2.0, uv.y * streak_scale));

    streak = smoothstep(0.35,0.65,streak);

    // Circumferential wear bands
    float wear =
        noise(vec2(uv.x * wear_scale, 3.0));

    // Fine grain
    float grain =
        noise(uv * noise_scale);

    vec3 color = rubber_color.rgb;

    color = mix(color, worn_color.rgb, streak * 0.18);

    color += (grain - 0.5) * 0.035;

    color += (wear - 0.5) * 0.025;

    ALBEDO = color;
    ROUGHNESS = roughness;
    METALLIC = metallic;
}