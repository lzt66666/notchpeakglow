#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 resolution;    // drawable 像素
    float2 notchCenter;   // drawable 像素坐标（左上原点）
    float  time;
    float  intensity;     // 总强度 0...1（淡入淡出）
    float  modeMix;       // 0 = 中档彩虹, 1 = 高档蓝
    float  hdrBoost;      // 1 + headroom * factor（高档用）
    float  pulseHz;
    float  glowScale;     // 光晕尺度
    float  mediumAlpha;   // 中档峰值透明度
};

float hash21(float2 p) {
    p = fract(p * float2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1, 0));
    float c = hash21(i + float2(0, 1));
    float d = hash21(i + float2(1, 1));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    return valueNoise(p) * 0.6 + valueNoise(p * 2.13) * 0.4;
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

struct FragmentInput {
    float4 position [[position]];
};

vertex FragmentInput vertexShader(uint vid [[vertex_id]]) {
    // 覆盖全屏的两个三角形
    float2 pos[6] = {
        float2(-1, -1), float2(1, -1), float2(1, 1),
        float2(-1, -1), float2(1, 1), float2(-1, 1)
    };
    FragmentInput out;
    out.position = float4(pos[vid], 0, 1);
    return out;
}

fragment float4 fragmentShader(FragmentInput in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]]) {
    float2 frag = in.position.xy;  // 已是像素坐标（左上原点）

    // 不对称椭圆：刘海下方延伸长、上方短（上方被屏幕顶边自然截断）
    float dx = (frag.x - u.notchCenter.x) / u.glowScale;
    float dy = frag.y - u.notchCenter.y;
    float ry = (dy > 0.0) ? u.glowScale * 0.62 : u.glowScale * 0.30;
    float2 d = float2(dx, dy / ry);
    float dist = length(d);

    // 流动噪声：极坐标扭曲
    float ang = atan2(d.y, d.x);
    float n = fbm(float2(ang * 1.6, dist * 2.2 - u.time * 0.22));
    float ripple = 1.0 + n * 0.45;

    float falloff = 1.0 - smoothstep(0.0, ripple, dist);
    falloff = pow(falloff, 1.3);

    // ---- 中档：彩虹 + HDR 提升（较蓝色温和：约一半增益）----
    float hue = fract(u.time * 0.045 + ang / 6.2832 + n * 0.22);
    float3 rainbow = hsv2rgb(float3(hue, 0.85, 1.0));
    rainbow *= 1.0 + (u.hdrBoost - 1.0) * 0.5;

    // ---- 高档：鲜艳蓝 + HDR 呼吸 ----
    float pulse = 0.5 + 0.5 * sin(6.28318 * u.pulseHz * u.time);
    float3 blue = float3(0.22, 0.48, 1.0) * (1.0 + (u.hdrBoost - 1.0) * (0.55 + 0.45 * pulse));
    blue *= 0.85 + 0.3 * pulse;   // 亮度呼吸

    float3 color = mix(rainbow, blue, u.modeMix);
    float alpha = falloff * mix(u.mediumAlpha, 0.95, u.modeMix) * u.intensity;

    return float4(color * alpha, alpha);
}
