#include <metal_stdlib>
using namespace metal;

// MARK: - Shared Types

struct Uniforms {
    float4x4 modelMatrix;
    float4x4 viewMatrix;
    float4x4 projectionMatrix;
    float4x4 normalMatrix;
    float3 sunDirection;
    float3 cameraPosition;
    float time;
    float cloudTime;
    float atmosphereRadius;
    float planetRadius;
};

struct VertexIn {
    float3 position  [[attribute(0)]];
    float3 normal    [[attribute(1)]];
    float2 texCoord  [[attribute(2)]];
    float3 tangent   [[attribute(3)]];
    float3 bitangent [[attribute(4)]];
};

struct VertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 worldNormal;
    float2 texCoord;
    float3 worldTangent;
    float3 worldBitangent;
};

struct AtmosphereVertexOut {
    float4 position [[position]];
    float3 worldPosition;
    float3 localPosition;
};

// MARK: - Constants (half where possible)

constant half PI_H = 3.14159265h;
constant float PI = 3.14159265359;
constant float INV_4PI = 1.0 / (4.0 * PI);

constant half3 C_RAYLEIGH_H = half3(5.802e-3h, 13.558e-3h, 33.1e-3h);
constant float3 C_RAYLEIGH = float3(5.802e-3, 13.558e-3, 33.1e-3);
constant float3 C_OZONE = float3(0.650e-3, 1.881e-3, 0.085e-3);
constant float C_MIE_SCAT = 3.996e-3;
constant float C_MIE_ABS  = 0.440e-3;
constant float C_MIE_EXT  = C_MIE_SCAT + C_MIE_ABS;

constant float H_R = 8.5 / 60.0;
constant float H_M = 1.2 / 60.0;
constant float MIE_G = 0.76;

constant int LUT_TRANS_W = 256;
constant int LUT_TRANS_H = 64;
constant int LUT_MS_SIZE = 32;

// MARK: - Phase Functions (half precision)

half phaseRayleigh_h(half costh) {
    return (3.0h / (16.0h * PI_H)) * (1.0h + costh * costh);
}

half phaseMie_h(half costh) {
    half g = half(MIE_G);
    half k = 1.55h * g - 0.55h * g * g * g;
    half kcosth = k * costh;
    return (1.0h - k * k) / ((4.0h * PI_H) * (1.0h - kcosth) * (1.0h - kcosth));
}

// Full precision versions for compute shaders
float phaseRayleigh(float costh) {
    return (3.0 / (16.0 * PI)) * (1.0 + costh * costh);
}

float phaseMie(float costh, float g) {
    float k = 1.55 * g - 0.55 * g * g * g;
    float kcosth = k * costh;
    return (1.0 - k * k) / ((4.0 * PI) * (1.0 - kcosth) * (1.0 - kcosth));
}

// MARK: - Density (inlined for perf)

inline float densityR(float h, float planetR, float atmR) {
    return exp(-max(0.0, (h - planetR) / (atmR - planetR)) / H_R);
}

inline float densityM(float h, float planetR, float atmR) {
    return exp(-max(0.0, (h - planetR) / (atmR - planetR)) / H_M);
}

inline float densityO(float h, float planetR, float atmR) {
    float normalized = (h - planetR) / (atmR - planetR);
    return max(0.0, 1.0 - abs(normalized - 0.4167) * 4.8) * 0.3; // ozone peak at 25/60
}

// MARK: - Ray-Sphere Intersection (branchless)

float2 raySphereIntersect(float3 ro, float3 rd, float3 center, float radius) {
    float3 oc = ro - center;
    float b = dot(oc, rd);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - c;
    float sqrtD = sqrt(max(0.0, disc));
    float valid = step(0.0, disc);
    return float2(-b - sqrtD, -b + sqrtD) * valid + float2(-1.0) * (1.0 - valid);
}

// MARK: - Transmittance

float3 absorb(float3 opticalDepth) {
    return exp(-(opticalDepth.x * C_RAYLEIGH
               + opticalDepth.y * C_MIE_EXT
               + opticalDepth.z * C_OZONE));
}

float3 integrateOpticalDepth(float3 start, float3 dir, float dist,
                              float planetR, float atmR, int steps) {
    float stepSize = dist / float(steps);
    float3 od = float3(0.0);
    for (int i = 0; i < steps; i++) {
        float h = length(start + dir * (float(i) + 0.5) * stepSize);
        od += float3(densityR(h, planetR, atmR),
                     densityM(h, planetR, atmR),
                     densityO(h, planetR, atmR));
    }
    return od * stepSize;
}

// MARK: - Transmittance LUT (reduced to 20 samples)

kernel void computeTransmittanceLUT(
    texture2d<float, access::write> lut [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uint(LUT_TRANS_W) || gid.y >= uint(LUT_TRANS_H)) return;

    float planetR = 1.0;
    float atmR = 1.025;

    float u = float(gid.x) / float(LUT_TRANS_W - 1);
    float v = float(gid.y) / float(LUT_TRANS_H - 1);

    float height = mix(planetR, atmR, v);
    float cosZenith = u * 2.0 - 1.0;
    float sinZenith = sqrt(max(0.0, 1.0 - cosZenith * cosZenith));

    float3 ro = float3(0.0, height, 0.0);
    float3 rd = float3(sinZenith, cosZenith, 0.0);

    float2 atmHit = raySphereIntersect(ro, rd, float3(0.0), atmR);
    float rayLen = max(0.0, atmHit.y);
    float2 planetHit = raySphereIntersect(ro, rd, float3(0.0), planetR);
    rayLen = mix(rayLen, min(rayLen, max(0.0, planetHit.x)), step(0.0, planetHit.x));

    float3 od = integrateOpticalDepth(ro, rd, rayLen, planetR, atmR, 20); // Was 40
    float3 T = absorb(od);
    T = mix(float3(1.0), T, step(0.0, atmHit.y));

    lut.write(float4(T, 1.0), gid);
}

// MARK: - Multiple Scattering LUT (reduced to 4x4x4 = 64 iterations from 8x8x8 = 512)

kernel void computeMultipleScatteringLUT(
    texture2d<float, access::write> lut [[texture(0)]],
    texture2d<float, access::read> transmittanceLUT [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uint(LUT_MS_SIZE) || gid.y >= uint(LUT_MS_SIZE)) return;

    float planetR = 1.0;
    float atmR = 1.025;

    float u = float(gid.x) / float(LUT_MS_SIZE - 1);
    float v = float(gid.y) / float(LUT_MS_SIZE - 1);

    float height = mix(planetR, atmR, v);
    float cosSunZ = u * 2.0 - 1.0;
    float sinSunZ = sqrt(max(0.0, 1.0 - cosSunZ * cosSunZ));
    float3 sunDir = float3(sinSunZ, cosSunZ, 0.0);

    float3 totalScatter = float3(0.0);
    float3 totalTransfer = float3(0.0);
    int N = 4; // Was 8 — 8x reduction in iterations

    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            float theta = PI * (float(i) + 0.5) / float(N);
            float phi = 2.0 * PI * (float(j) + 0.5) / float(N);
            float sinT = sin(theta);
            float3 dir = float3(sinT * cos(phi), cos(theta), sinT * sin(phi));

            float3 pos = float3(0, height, 0);
            float2 atmHit = raySphereIntersect(pos, dir, float3(0), atmR);
            float rayLen = max(0.0, atmHit.y);
            float2 pH = raySphereIntersect(pos, dir, float3(0), planetR);
            rayLen = mix(rayLen, min(rayLen, max(0.0, pH.x)), step(0.0, pH.x));

            float stepSz = rayLen / 4.0; // Was 8
            for (int s = 0; s < 4; s++) { // Was 8
                float3 sp = pos + dir * (float(s) + 0.5) * stepSz;
                float h = length(sp);
                float3 scatter = C_RAYLEIGH * densityR(h, planetR, atmR)
                               + C_MIE_SCAT * densityM(h, planetR, atmR);

                float cosSun = dot(normalize(sp), sunDir);
                uint2 lc = uint2(uint((cosSun + 1.0) * 0.5 * float(LUT_TRANS_W - 1)),
                                 uint(saturate((h - planetR) / (atmR - planetR)) * float(LUT_TRANS_H - 1)));
                float3 sunT = transmittanceLUT.read(lc).rgb;

                totalScatter += scatter * sunT * stepSz;
                totalTransfer += scatter * stepSz;
            }
            totalScatter *= sinT;
            totalTransfer *= sinT;
        }
    }

    float norm = (4.0 * PI) / float(N * N);
    totalScatter *= norm;
    totalTransfer *= norm;

    float3 f_ms = totalTransfer * INV_4PI;
    float3 F_ms = 1.0 / max(float3(0.001), 1.0 - f_ms);

    lut.write(float4(totalScatter * INV_4PI * F_ms, 1.0), gid);
}

// MARK: - Earth Vertex Shader

vertex VertexOut earthVertexShader(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    VertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;

    float3x3 normalMat = float3x3(uniforms.normalMatrix[0].xyz,
                                    uniforms.normalMatrix[1].xyz,
                                    uniforms.normalMatrix[2].xyz);
    out.worldNormal = normalize(normalMat * in.normal);
    out.worldTangent = normalize(normalMat * in.tangent);
    out.worldBitangent = normalize(normalMat * in.bitangent);
    out.texCoord = in.texCoord;
    return out;
}

// MARK: - Earth Fragment Shader (optimized)

fragment half4 earthFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    texture2d<half> dayTexture [[texture(0)]],
    texture2d<half> nightTexture [[texture(1)]],
    texture2d<half> normalMap [[texture(2)]],
    texture2d<half> specularMap [[texture(3)]],
    texture2d<half> cloudTexture [[texture(4)]],
    texture2d<float> transmittanceLUT [[texture(5)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear,
                                  mip_filter::linear, address::repeat);

    half3 N = half3(normalize(in.worldNormal));
    half3 T = half3(normalize(in.worldTangent));
    half3 B = half3(normalize(in.worldBitangent));
    half3 V = half3(normalize(uniforms.cameraPosition - in.worldPosition));
    half3 L = half3(normalize(uniforms.sunDirection));
    float2 uv = in.texCoord;

    // Normal mapping
    half3 localN = normalize(normalMap.sample(texSampler, uv).rgb * 2.0h - 1.0h);
    half3x3 TBN = half3x3(T, B, N);
    half3 worldN = normalize(TBN * localN);

    // Diffuse
    half NdotL = dot(worldN, L);
    half diffuse = max(NdotL, 0.0h);

    // Day/night — use smoothstep instead of pow (cheaper)
    half dayWeight = saturate(NdotL * 3.0h + 0.3h);
    dayWeight = smoothstep(0.0h, 1.0h, dayWeight);

    half4 dayColor = dayTexture.sample(texSampler, uv);
    half4 nightColor = nightTexture.sample(texSampler, uv);
    half3 surfaceColor = mix(nightColor.rgb, dayColor.rgb * (diffuse + 0.12h), dayWeight);

    // Specular — reduced exponent 64→32
    half specMask = specularMap.sample(texSampler, uv).r;
    half3 R = reflect(-L, worldN);
    half spec = pow(max(dot(R, V), 0.0h), 32.0h) * specMask * diffuse;
    surfaceColor += half3(1.0h, 0.95h, 0.8h) * spec * 1.5h;

    // Clouds — single sample, derive shadow from offset
    float2 cloudUV = uv + float2(uniforms.cloudTime * 0.001, 0.0);
    half4 cSample = cloudTexture.sample(texSampler, cloudUV);
    half cloudA = max(cSample.a, dot(cSample.rgb, half3(0.299h, 0.587h, 0.114h)));
    half cDiff = max(dot(N, L), 0.0h);
    half3 cColor = cSample.rgb * (cDiff * 0.9h + 0.1h);

    // Cloud shadow — precompute offset in half precision
    half3 shadowOff = dot(N, L) * N - L;
    half3x3 invTBN = transpose(TBN);
    float2 sUV = uv + float2((invTBN * shadowOff).xy) * 0.005;
    half4 sSample = cloudTexture.sample(texSampler, sUV + float2(uniforms.cloudTime * 0.001, 0.0));
    half sCloud = max(sSample.a, dot(sSample.rgb, half3(0.299h, 0.587h, 0.114h)));
    surfaceColor *= 1.0h - sCloud * 0.35h * saturate(NdotL);
    surfaceColor = mix(surfaceColor, cColor, cloudA * 0.85h);

    // Surface transmittance from LUT (keep float for LUT precision)
    float planetR = uniforms.planetRadius;
    float atmR = uniforms.atmosphereRadius;
    float3 sNorm = normalize(in.worldPosition);
    float cosVZ = dot(sNorm, float3(V));
    float lutU = (cosVZ + 1.0) * 0.5;
    float lutV = saturate((length(in.worldPosition) - planetR) / (atmR - planetR));
    half3 viewT = half3(transmittanceLUT.sample(texSampler, float2(lutU, lutV)).rgb);
    surfaceColor *= viewT;

    return half4(surfaceColor, 1.0h);
}

// MARK: - Atmosphere Vertex Shader

vertex AtmosphereVertexOut atmosphereVertexShader(
    VertexIn in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    AtmosphereVertexOut out;
    float4 worldPos = uniforms.modelMatrix * float4(in.position, 1.0);
    out.worldPosition = worldPos.xyz;
    out.localPosition = in.position;
    out.position = uniforms.projectionMatrix * uniforms.viewMatrix * worldPos;
    return out;
}

// MARK: - Atmosphere Fragment Shader (16 steps, half precision accumulation)

fragment half4 atmosphereFragmentShader(
    AtmosphereVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    texture2d<float> transmittanceLUT [[texture(0)]],
    texture2d<float> multiScatterLUT [[texture(1)]]
) {
    constexpr sampler lutSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float planetR = uniforms.planetRadius;
    float atmR = uniforms.atmosphereRadius;
    float3 sunDir = normalize(uniforms.sunDirection);
    float3 camPos = uniforms.cameraPosition;
    float3 rayDir = normalize(in.worldPosition - camPos);

    float2 atmHit = raySphereIntersect(camPos, rayDir, float3(0.0), atmR);
    if (atmHit.y < 0.0) discard_fragment();

    float tStart = max(atmHit.x, 0.0);
    float tEnd = atmHit.y;

    float2 planetHit = raySphereIntersect(camPos, rayDir, float3(0.0), planetR);
    float hitsPlanet = step(0.0, planetHit.x);
    tEnd = mix(tEnd, min(tEnd, planetHit.x), hitsPlanet);

    float rayLength = tEnd - tStart;
    if (rayLength <= 0.0) discard_fragment();

    // Phase functions
    half cosTheta = half(dot(rayDir, sunDir));
    half phR = phaseRayleigh_h(cosTheta);
    half phM = phaseMie_h(cosTheta);

    // Ray march — 16 steps (was 32), quadratic distribution
    half3 rayleighSum = half3(0.0h);
    half3 mieSum = half3(0.0h);
    float3 opticalDepth = float3(0.0); // Keep float for accumulation precision

    float prevT = 0.0;
    for (int i = 0; i < 16; i++) {
        float t_frac = float(i + 1) / 16.0;
        float t_cur = t_frac * t_frac * rayLength;
        float stepSize = t_cur - prevT;
        prevT = t_cur;

        float3 samplePos = camPos + rayDir * (tStart + t_cur - stepSize * 0.5);
        float sampleHeight = length(samplePos);

        float dR = densityR(sampleHeight, planetR, atmR);
        float dM = densityM(sampleHeight, planetR, atmR);
        float dO = densityO(sampleHeight, planetR, atmR);

        opticalDepth += float3(dR, dM, dO) * stepSize;
        half3 viewTrans = half3(absorb(opticalDepth));

        float3 sNorm = normalize(samplePos);
        float cosSunZ = dot(sNorm, sunDir);
        float hFrac = saturate((sampleHeight - planetR) / (atmR - planetR));
        float2 lutUV = float2((cosSunZ + 1.0) * 0.5, hFrac);
        half3 sunTrans = half3(transmittanceLUT.sample(lutSampler, lutUV).rgb);
        half3 ms = half3(multiScatterLUT.sample(lutSampler, lutUV).rgb);

        half3 scatR = C_RAYLEIGH_H * half(dR);
        half scatM = half(C_MIE_SCAT * dM);
        half hStep = half(stepSize);

        rayleighSum += viewTrans * scatR * (sunTrans * phR + ms) * hStep;
        mieSum += viewTrans * half3(scatM) * (sunTrans * phM + ms * 0.5h) * hStep;
    }

    half3 atmosphere = (rayleighSum + mieSum) * 20.0h;

    // Soft Schlick limb — smoothstep instead of exp for sigmoid
    float3 entryPoint = camPos + rayDir * tStart;
    float3 entryNorm = normalize(entryPoint);
    half NdotV = half(abs(dot(entryNorm, -rayDir)));
    half oneMinusNdV = 1.0h - NdotV;
    half schlick = 0.01h + 0.99h * oneMinusNdV * oneMinusNdV * oneMinusNdV * oneMinusNdV * oneMinusNdV;

    half sunAngle = half(dot(entryNorm, sunDir));
    half dayMask = smoothstep(-0.3h, 0.4h, sunAngle); // Cheaper than sigmoid
    half rimMod = mix(0.3h, 1.0h, dayMask);
    atmosphere += half3(0.08h, 0.22h, 0.6h) * schlick * rimMod * 0.5h;

    // ACES tone map
    half3 x = atmosphere;
    atmosphere = saturate((x * (2.51h * x + 0.03h)) / (x * (2.43h * x + 0.59h) + 0.14h));

    half lum = dot(atmosphere, half3(0.299h, 0.587h, 0.114h));
    half alpha = saturate(lum * 2.5h + schlick * 0.3h);
    alpha = mix(alpha, alpha * 0.4h, half(hitsPlanet));

    return half4(atmosphere, alpha);
}

// MARK: - Fresnel Glow (half precision, smoothstep)

fragment half4 fresnelGlowFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    half3 N = half3(normalize(in.worldNormal));
    half3 L = half3(normalize(uniforms.sunDirection));
    half3 V = half3(normalize(uniforms.cameraPosition - in.worldPosition));

    half cosAngle = dot(N, L);
    half mixAmount = saturate(cosAngle * 2.0h + 0.5h);
    mixAmount = smoothstep(0.0h, 1.0h, mixAmount); // Cheaper than pow(x, 1.5)

    half3 u_color = half3(0.3h, 0.6h, 1.0h);

    half fresnelTerm = 1.0h - max(dot(V, N), 0.0h);
    fresnelTerm = fresnelTerm * fresnelTerm; // x^2, cheaper than pow

    half3 glowColor = u_color * fresnelTerm * mixAmount;
    half3 finalColor = u_color * mixAmount * fresnelTerm * 0.5h + glowColor * 0.8h;
    half alpha = fresnelTerm * mixAmount * 0.9h;

    return half4(finalColor, alpha);
}

// MARK: - Preview Fragment Shader

fragment half4 previewFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    constant float &transitionMix [[buffer(2)]],
    texture2d<half> currentTexture [[texture(0)]],
    texture2d<half> previousTexture [[texture(1)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear,
                                  mip_filter::linear, address::repeat);

    half3 N = half3(normalize(in.worldNormal));
    half3 L = half3(normalize(uniforms.sunDirection));
    float2 uv = in.texCoord;

    half4 curColor = currentTexture.sample(texSampler, uv);
    half4 prevColor = previousTexture.sample(texSampler, uv);
    half4 texColor = mix(prevColor, curColor, half(transitionMix));

    half lighting = max(dot(N, L), 0.0h) * 0.7h + 0.3h;

    return half4(texColor.rgb * lighting, 1.0h);
}
