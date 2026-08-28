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
    float  redFlash;      // 过热红闪包络 0..1
    float  redGain;       // 过热红光相对蓝的额外增益
    float  redScale;      // 过热红光相对蓝的尺寸倍率
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

    // 过热门控提前计算：红光在呼吸暗相放行
    float pulse = 0.5 + 0.5 * sin(6.28318 * u.pulseHz * u.time);
    float darkPhase = 1.0 - pulse;
    float gate = (u.redFlash > 0.001)
        ? smoothstep(0.35, 0.95, darkPhase) : 0.0;
    float flash = u.redFlash > 0.001 ? pow(u.redFlash, 0.6) * gate : 0.0;

    // 光晕尺度：红闪时按 redScale 膨胀（flash 渐变过渡，不跳变）
    float scale = u.glowScale * mix(1.0, u.redScale, flash);

    // 不对称椭圆：刘海下方延伸长、上方短（上方被屏幕顶边自然截断）
    float dx = (frag.x - u.notchCenter.x) / scale;
    float dy = frag.y - u.notchCenter.y;
    float ry = (dy > 0.0) ? scale * 0.62 : scale * 0.30;
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
    float3 blue = float3(0.22, 0.48, 1.0) * (1.0 + (u.hdrBoost - 1.0) * (0.55 + 0.45 * pulse));
    blue *= 0.85 + 0.3 * pulse;   // 亮度呼吸

    float3 color = mix(rainbow, blue, u.modeMix);
    float alpha = falloff * mix(u.mediumAlpha, 0.95, u.modeMix) * u.intensity;

    // 过热红闪：与蓝同源 HDR 增益 ×redGain 超亮压制；
    if (flash > 0.001) {
        float3 redc = float3(1.00, 0.06, 0.04)
                    * (1.0 + (u.hdrBoost - 1.0) * (0.55 + 0.45 * pulse) * u.redGain);
        color = color * (1.0 - flash) + redc * flash;
        alpha = min(1.0, alpha * (1.0 + flash * 0.4));
    }

    return float4(color * alpha, alpha);
}
