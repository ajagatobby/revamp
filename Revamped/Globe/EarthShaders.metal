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

struct AtmosphereParams {
    float planetRadius;       // 6371 km normalized to 1.0
    float atmosphereRadius;   // ~1.015 (60km above surface)
    float rayleighScaleHeight; // H_R
    float mieScaleHeight;     // H_M
    float3 rayleighScattering; // beta_R at sea level
    float mieScattering;      // beta_M at sea level
    float mieAsymmetry;       // g parameter
    float sunIntensity;
};

// MARK: - Constants

constant float PI = 3.14159265359;
constant float3 RAYLEIGH_COEFF = float3(5.802e-3, 13.558e-3, 33.1e-3); // per km, normalized
constant float MIE_COEFF = 3.996e-3;
constant float RAYLEIGH_SCALE_HEIGHT = 8.5 / 60.0;  // normalized to atmosphere thickness
constant float MIE_SCALE_HEIGHT = 1.2 / 60.0;
constant float MIE_G = 0.76;
constant int LUT_TRANSMITTANCE_W = 256;
constant int LUT_TRANSMITTANCE_H = 64;

// MARK: - Utility Functions

float2 sphereToUV(float3 normal) {
    float u = atan2(normal.z, normal.x) / (2.0 * PI) + 0.5;
    float v = asin(clamp(normal.y, -1.0, 1.0)) / PI + 0.5;
    return float2(u, 1.0 - v);
}

float3x3 cotangentFrame(float3 N, float3 p, float2 uv) {
    float3 dp1 = dfdx(p);
    float3 dp2 = dfdy(p);
    float2 duv1 = dfdx(uv);
    float2 duv2 = dfdy(uv);

    float3 dp2perp = cross(dp2, N);
    float3 dp1perp = cross(N, dp1);

    float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 B = dp2perp * duv1.y + dp1perp * duv2.y;

    float invmax = rsqrt(max(dot(T, T), dot(B, B)));
    return float3x3(T * invmax, B * invmax, N);
}

// MARK: - Phase Functions

float rayleighPhase(float cosTheta) {
    return (3.0 / (16.0 * PI)) * (1.0 + cosTheta * cosTheta);
}

float miePhase(float cosTheta, float g) {
    float g2 = g * g;
    float num = (1.0 - g2);
    float denom = 4.0 * PI * pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
    return num / denom;
}

// MARK: - Atmospheric Scattering Helpers

float atmosphereDensityRayleigh(float height, float planetR, float atmR) {
    float h = (height - planetR) / (atmR - planetR);
    return exp(-h / RAYLEIGH_SCALE_HEIGHT);
}

float atmosphereDensityMie(float height, float planetR, float atmR) {
    float h = (height - planetR) / (atmR - planetR);
    return exp(-h / MIE_SCALE_HEIGHT);
}

// Ray-sphere intersection: returns (near, far) distances, negative if no hit
float2 raySphereIntersect(float3 rayOrigin, float3 rayDir, float3 center, float radius) {
    float3 oc = rayOrigin - center;
    float b = dot(oc, rayDir);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - c;

    if (discriminant < 0.0) {
        return float2(-1.0, -1.0);
    }

    float sqrtD = sqrt(discriminant);
    return float2(-b - sqrtD, -b + sqrtD);
}

// Compute optical depth along a ray segment
float2 computeOpticalDepth(float3 start, float3 dir, float segmentLength,
                           float planetR, float atmR, int steps) {
    float stepSize = segmentLength / float(steps);
    float2 opticalDepth = float2(0.0); // x=rayleigh, y=mie

    for (int i = 0; i < steps; i++) {
        float3 samplePoint = start + dir * (float(i) + 0.5) * stepSize;
        float height = length(samplePoint);
        opticalDepth.x += atmosphereDensityRayleigh(height, planetR, atmR) * stepSize;
        opticalDepth.y += atmosphereDensityMie(height, planetR, atmR) * stepSize;
    }

    return opticalDepth;
}

// MARK: - Transmittance LUT Compute Shader

kernel void computeTransmittanceLUT(
    texture2d<float, access::write> lut [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uint(LUT_TRANSMITTANCE_W) || gid.y >= uint(LUT_TRANSMITTANCE_H)) return;

    float planetR = 1.0;
    float atmR = 1.015;

    // Map pixel coords to (height, cosZenith)
    float u = float(gid.x) / float(LUT_TRANSMITTANCE_W - 1);
    float v = float(gid.y) / float(LUT_TRANSMITTANCE_H - 1);

    float height = mix(planetR, atmR, v);
    float cosZenith = u * 2.0 - 1.0;
    float sinZenith = sqrt(max(0.0, 1.0 - cosZenith * cosZenith));

    float3 rayOrigin = float3(0.0, height, 0.0);
    float3 rayDir = float3(sinZenith, cosZenith, 0.0);

    // Find intersection with atmosphere top
    float2 atmIntersect = raySphereIntersect(rayOrigin, rayDir, float3(0.0), atmR);

    if (atmIntersect.y < 0.0) {
        lut.write(float4(1.0, 1.0, 1.0, 1.0), gid);
        return;
    }

    float rayLength = atmIntersect.y;

    // Check if ray hits planet
    float2 planetIntersect = raySphereIntersect(rayOrigin, rayDir, float3(0.0), planetR);
    if (planetIntersect.x > 0.0) {
        rayLength = planetIntersect.x;
    }

    int steps = 40;
    float2 optDepth = computeOpticalDepth(rayOrigin, rayDir, rayLength, planetR, atmR, steps);

    float3 transmittance = exp(-(RAYLEIGH_COEFF * optDepth.x + MIE_COEFF * optDepth.y));

    lut.write(float4(transmittance, 1.0), gid);
}

// MARK: - Multiple Scattering LUT Compute Shader

kernel void computeMultipleScatteringLUT(
    texture2d<float, access::write> lut [[texture(0)]],
    texture2d<float, access::read> transmittanceLUT [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= 32u || gid.y >= 32u) return;

    float planetR = 1.0;
    float atmR = 1.015;

    float u = float(gid.x) / 31.0;
    float v = float(gid.y) / 31.0;

    float height = mix(planetR, atmR, v);
    float cosSunZenith = u * 2.0 - 1.0;

    // Approximate 2nd order scattering by integrating over sphere directions
    float3 totalScattering = float3(0.0);
    int dirSamples = 8;

    for (int i = 0; i < dirSamples; i++) {
        for (int j = 0; j < dirSamples; j++) {
            float theta = PI * (float(i) + 0.5) / float(dirSamples);
            float phi = 2.0 * PI * (float(j) + 0.5) / float(dirSamples);

            float3 dir = float3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi));

            float2 atmHit = raySphereIntersect(float3(0, height, 0), dir, float3(0), atmR);
            if (atmHit.y <= 0.0) continue;

            float rayLen = atmHit.y;
            float2 planetHit = raySphereIntersect(float3(0, height, 0), dir, float3(0), planetR);
            if (planetHit.x > 0.0) rayLen = planetHit.x;

            float stepSize = rayLen / 8.0;
            for (int s = 0; s < 8; s++) {
                float3 pos = float3(0, height, 0) + dir * (float(s) + 0.5) * stepSize;
                float h = length(pos);
                float densR = atmosphereDensityRayleigh(h, planetR, atmR);
                float densM = atmosphereDensityMie(h, planetR, atmR);

                // Look up transmittance to sun from this point
                float3 up = normalize(pos);
                float cosSun = dot(up, float3(0, cosSunZenith, sqrt(max(0.0, 1.0 - cosSunZenith * cosSunZenith))));
                float lutU = (cosSun + 1.0) * 0.5;
                float lutV = (h - planetR) / (atmR - planetR);
                uint2 lutCoord = uint2(uint(lutU * float(LUT_TRANSMITTANCE_W - 1)),
                                       uint(lutV * float(LUT_TRANSMITTANCE_H - 1)));
                float3 sunTrans = transmittanceLUT.read(lutCoord).rgb;

                totalScattering += (RAYLEIGH_COEFF * densR + MIE_COEFF * densM) * sunTrans * stepSize;
            }

            totalScattering *= sin(theta); // solid angle weight
        }
    }

    totalScattering *= (4.0 * PI) / float(dirSamples * dirSamples);

    lut.write(float4(totalScattering, 1.0), gid);
}

// MARK: - Earth Surface Vertex Shader

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

// MARK: - Earth Surface Fragment Shader

fragment float4 earthFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    texture2d<float> dayTexture [[texture(0)]],
    texture2d<float> nightTexture [[texture(1)]],
    texture2d<float> normalMap [[texture(2)]],
    texture2d<float> specularMap [[texture(3)]],
    texture2d<float> cloudTexture [[texture(4)]],
    texture2d<float> transmittanceLUT [[texture(5)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear,
                                  mip_filter::linear, address::repeat);

    float3 N = normalize(in.worldNormal);
    float3 T = normalize(in.worldTangent);
    float3 B = normalize(in.worldBitangent);
    float3 V = normalize(uniforms.cameraPosition - in.worldPosition);
    float3 L = normalize(uniforms.sunDirection);

    float2 uv = in.texCoord;

    // --- Normal Mapping ---
    // Unpack normal map: n = 2*RGB - 1
    float3 normalSample = normalMap.sample(texSampler, uv).rgb;
    float3 localNormal = normalSample * 2.0 - 1.0;
    localNormal = normalize(localNormal);

    // TBN matrix to transform local normal to world space
    float3x3 TBN = float3x3(T, B, N);
    float3 worldNormal = normalize(TBN * localNormal);

    // --- Diffuse Lighting ---
    float NdotL = dot(worldNormal, L);
    float diffuse = max(NdotL, 0.0);

    // Day/night transition with smooth blend
    // Use exponential falloff for more realistic terminator
    float dayWeight = saturate(NdotL * 3.0 + 0.3);
    dayWeight = pow(dayWeight, 1.5);

    float4 dayColor = dayTexture.sample(texSampler, uv);
    float4 nightColor = nightTexture.sample(texSampler, uv);

    // Ambient light for the day side
    float ambient = 0.06;
    float3 surfaceColor = mix(nightColor.rgb, dayColor.rgb * (diffuse + ambient), dayWeight);

    // --- Specular / Ocean Reflections ---
    float specMask = specularMap.sample(texSampler, uv).r;

    // Reflection vector: reflect(-L, worldNormal)
    float3 R = reflect(-L, worldNormal);
    float RdotV = max(dot(R, V), 0.0);

    // Phong specular with high shininess for water
    float specPower = 64.0;
    float specular = pow(RdotV, specPower) * specMask * diffuse;

    // Add specular glare to ocean areas
    surfaceColor += float3(1.0, 0.95, 0.8) * specular * 1.5;

    // --- Cloud Layer ---
    // Offset clouds slowly over time
    float2 cloudUV = uv + float2(uniforms.cloudTime * 0.001, 0.0);
    float4 cloudSample = cloudTexture.sample(texSampler, cloudUV);
    // Cloud texture may be JPEG (no alpha) — derive opacity from brightness
    float cloudAlpha = max(cloudSample.a, dot(cloudSample.rgb, float3(0.299, 0.587, 0.114)));

    // Cloud diffuse lighting
    float cloudDiffuse = max(dot(N, L), 0.0);
    float3 cloudColor = cloudSample.rgb * (cloudDiffuse * 0.9 + 0.1);

    // --- Cloud Shadows ---
    // Project shadow offset along surface based on sun direction
    float3 shadowOffset3D = dot(N, L) * N - L;
    float3x3 invTBN = transpose(TBN); // TBN is orthonormal, so inverse = transpose
    float3 shadowLocal = invTBN * shadowOffset3D;
    float2 shadowUV = uv + shadowLocal.xy * 0.005;
    float4 shadowSample = cloudTexture.sample(texSampler, shadowUV + float2(uniforms.cloudTime * 0.001, 0.0));
    float shadowCloud = max(shadowSample.a, dot(shadowSample.rgb, float3(0.299, 0.587, 0.114)));

    // Dim surface under cloud shadows
    float shadowFactor = 1.0 - shadowCloud * 0.35 * saturate(NdotL);
    surfaceColor *= shadowFactor;

    // Blend clouds over surface
    surfaceColor = mix(surfaceColor, cloudColor, cloudAlpha * 0.85);

    // --- Surface Transmittance (atmosphere absorption on surface) ---
    float planetR = 1.0;
    float atmR = uniforms.atmosphereRadius;
    float3 surfNormalized = normalize(in.worldPosition);
    float surfHeight = length(in.worldPosition);
    float cosViewZenith = dot(surfNormalized, V);

    // Sample transmittance LUT for view ray
    float lutU = (cosViewZenith + 1.0) * 0.5;
    float lutV = saturate((surfHeight - planetR) / (atmR - planetR));
    float3 viewTransmittance = transmittanceLUT.sample(texSampler, float2(lutU, lutV)).rgb;

    // Apply atmospheric extinction to surface color
    surfaceColor *= viewTransmittance;

    return float4(surfaceColor, 1.0);
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

// MARK: - Atmosphere Fragment Shader (Ray Marching)

fragment float4 atmosphereFragmentShader(
    AtmosphereVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    texture2d<float> transmittanceLUT [[texture(0)]],
    texture2d<float> multiScatterLUT [[texture(1)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear, address::clamp_to_edge);

    float planetR = uniforms.planetRadius;
    float atmR = uniforms.atmosphereRadius;
    float3 sunDir = normalize(uniforms.sunDirection);
    float3 camPos = uniforms.cameraPosition;
    float3 rayDir = normalize(in.worldPosition - camPos);

    // Ray-atmosphere intersection
    float2 atmHit = raySphereIntersect(camPos, rayDir, float3(0.0), atmR);
    if (atmHit.y < 0.0) {
        discard_fragment();
    }

    float rayStart = max(atmHit.x, 0.0);
    float rayEnd = atmHit.y;

    // Check for planet occlusion
    float2 planetHit = raySphereIntersect(camPos, rayDir, float3(0.0), planetR);
    if (planetHit.x > 0.0) {
        rayEnd = min(rayEnd, planetHit.x);
    }

    float rayLength = rayEnd - rayStart;
    if (rayLength <= 0.0) {
        discard_fragment();
    }

    // Ray marching parameters
    int numSteps = 24;
    float stepSize = rayLength / float(numSteps);

    float3 inScatteredRayleigh = float3(0.0);
    float3 inScatteredMie = float3(0.0);
    float2 totalOpticalDepth = float2(0.0);

    float cosTheta = dot(rayDir, sunDir);
    float phaseR = rayleighPhase(cosTheta);
    float phaseM = miePhase(cosTheta, MIE_G);

    float sunIntensity = 22.0;

    for (int i = 0; i < numSteps; i++) {
        float3 samplePos = camPos + rayDir * (rayStart + (float(i) + 0.5) * stepSize);
        float sampleHeight = length(samplePos);

        if (sampleHeight < planetR) break;

        float densR = atmosphereDensityRayleigh(sampleHeight, planetR, atmR);
        float densM = atmosphereDensityMie(sampleHeight, planetR, atmR);

        float2 localOD = float2(densR, densM) * stepSize;
        totalOpticalDepth += localOD;

        // Transmittance from camera to sample point
        float3 viewTrans = exp(-(RAYLEIGH_COEFF * totalOpticalDepth.x + MIE_COEFF * totalOpticalDepth.y));

        // Transmittance from sample point to sun (LUT lookup)
        float3 sampleNorm = normalize(samplePos);
        float cosSunZenith = dot(sampleNorm, sunDir);
        float heightFrac = saturate((sampleHeight - planetR) / (atmR - planetR));
        float lutU = (cosSunZenith + 1.0) * 0.5;
        float3 sunTrans = transmittanceLUT.sample(texSampler, float2(lutU, heightFrac)).rgb;

        // Add multiple scattering contribution
        float3 multiScatter = multiScatterLUT.sample(texSampler, float2(lutU, heightFrac)).rgb;

        // In-scattered light
        float3 scatterR = RAYLEIGH_COEFF * densR;
        float3 scatterM = float3(MIE_COEFF * densM);

        inScatteredRayleigh += viewTrans * scatterR * (sunTrans * phaseR + multiScatter) * stepSize;
        inScatteredMie += viewTrans * scatterM * (sunTrans * phaseM + multiScatter * 0.5) * stepSize;
    }

    float3 atmosphere = (inScatteredRayleigh + inScatteredMie) * sunIntensity;

    // --- Fresnel Edge Effect ---
    // Atmosphere appears denser at grazing angles
    float3 surfPoint = camPos + rayDir * rayStart;
    float3 surfNorm = normalize(surfPoint);
    float fresnelAngle = 1.0 - abs(dot(surfNorm, -rayDir));
    float fresnel = pow(fresnelAngle, 3.0) * 0.5;
    atmosphere += float3(0.3, 0.5, 1.0) * fresnel;

    // Tone mapping
    atmosphere = 1.0 - exp(-atmosphere);

    // Alpha based on scattering intensity
    float alpha = saturate(length(atmosphere) * 1.5);

    // If ray hits planet, don't draw atmosphere (surface shader handles it)
    if (planetHit.x > 0.0 && planetHit.x < atmHit.y) {
        // Only show atmosphere between camera and planet surface
        alpha *= 0.6;
    }

    return float4(atmosphere, alpha);
}

// MARK: - Preview Fragment Shader (Single Texture on Globe)

fragment float4 previewFragmentShader(
    VertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]],
    texture2d<float> previewTexture [[texture(0)]]
) {
    constexpr sampler texSampler(mag_filter::linear, min_filter::linear,
                                  mip_filter::linear, address::repeat);

    float3 N = normalize(in.worldNormal);
    float3 L = normalize(uniforms.sunDirection);

    float2 uv = in.texCoord;
    float4 texColor = previewTexture.sample(texSampler, uv);

    // Simple diffuse + ambient lighting so the texture is clearly visible
    float diffuse = max(dot(N, L), 0.0);
    float lighting = diffuse * 0.7 + 0.3;

    return float4(texColor.rgb * lighting, 1.0);
}
