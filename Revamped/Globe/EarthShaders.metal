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

// MARK: - Physical Constants

constant float PI = 3.14159265359;
constant float INV_4PI = 1.0 / (4.0 * PI);

// Rayleigh scattering coefficients at sea level (per unit distance, normalized)
// Derived from beta_scat^R = (8*pi^3*(n^2-1)^2) / (3*N*lambda^4)
// The 1/lambda^4 dependence causes blue light to scatter ~5.5x more than red
constant float3 RAYLEIGH_COEFF = float3(5.802e-3, 13.558e-3, 33.1e-3);

// Ozone absorption coefficients (wavelength-dependent absorption in stratosphere)
// beta_abs = 4*pi*n_i / lambda
constant float3 OZONE_ABSORPTION = float3(0.650e-3, 1.881e-3, 0.085e-3);

// Mie scattering coefficient at sea level
// beta_scat^M = 0.434 * C(T) * pi * (2*pi/lambda)^(v-2) * K
constant float MIE_SCAT_COEFF = 3.996e-3;
// Mie absorption (extinction = scattering + absorption)
constant float MIE_ABS_COEFF = 0.440e-3;

// Scale heights (normalized to atmosphere thickness of 60km)
constant float H_RAYLEIGH = 8.5 / 60.0;   // H_R: Rayleigh scale height
constant float H_MIE      = 1.2 / 60.0;   // H_M: Mie scale height
constant float H_OZONE    = 25.0 / 60.0;  // Peak ozone layer height

// Mie asymmetry parameters for double Henyey-Greenstein
constant float MIE_G1 = 0.76;   // Forward scattering lobe
constant float MIE_G2 = -0.50;  // Backward scattering lobe
constant float MIE_ALPHA = 0.90; // Blend weight (90% forward, 10% backward)

constant int LUT_TRANSMITTANCE_W = 256;
constant int LUT_TRANSMITTANCE_H = 64;
constant int LUT_MULTISCATTER_SIZE = 32;

// MARK: - Phase Functions

// Rayleigh Phase Function:
// P_R(theta) = 0.7629 * (1 + 0.932 * cos^2(theta)) * 1/(4*pi)
float rayleighPhase(float cosTheta) {
    return 0.7629 * (1.0 + 0.932 * cosTheta * cosTheta) * INV_4PI;
}

// Single Henyey-Greenstein lobe
float henyeyGreenstein(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / (pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5)) * INV_4PI;
}

// Mie Phase Function — Double Henyey-Greenstein approximation:
// P_M(theta) = alpha * HG(theta, g1) + (1-alpha) * HG(theta, g2)
// g1 = forward lobe, g2 = backward lobe, alpha = weight
float miePhase(float cosTheta) {
    return MIE_ALPHA * henyeyGreenstein(cosTheta, MIE_G1)
       + (1.0 - MIE_ALPHA) * henyeyGreenstein(cosTheta, MIE_G2);
}

// MARK: - Atmospheric Density Functions

// Rayleigh density: exp(-h / H_R)
float densityRayleigh(float height, float planetR, float atmR) {
    float h = (height - planetR) / (atmR - planetR);
    return exp(-h / H_RAYLEIGH);
}

// Mie density: exp(-h / H_M)
float densityMie(float height, float planetR, float atmR) {
    float h = (height - planetR) / (atmR - planetR);
    return exp(-h / H_MIE);
}

// Ozone density: triangular distribution centered around 25km
float densityOzone(float height, float planetR, float atmR) {
    float h = (height - planetR) / (atmR - planetR);
    return max(0.0, 1.0 - abs(h - H_OZONE) / (H_OZONE * 0.5)) * 0.3;
}

// MARK: - Ray-Sphere Intersection (Branchless)

float2 raySphereIntersect(float3 rayOrigin, float3 rayDir, float3 center, float radius) {
    float3 oc = rayOrigin - center;
    float b = dot(oc, rayDir);
    float c = dot(oc, oc) - radius * radius;
    float discriminant = b * b - c;

    // Branchless: return -1 for both if no intersection
    float sqrtD = sqrt(max(0.0, discriminant));
    float valid = step(0.0, discriminant); // 1.0 if hit, 0.0 if miss
    return float2(-b - sqrtD, -b + sqrtD) * valid + float2(-1.0) * (1.0 - valid);
}

// MARK: - Extinction Coefficient
// beta_e = beta_scatter + beta_absorb (Rayleigh + Mie + Ozone)

float3 extinctionAtHeight(float height, float planetR, float atmR) {
    float dR = densityRayleigh(height, planetR, atmR);
    float dM = densityMie(height, planetR, atmR);
    float dO = densityOzone(height, planetR, atmR);

    // Rayleigh: extinction ≈ scattering (no absorption for air molecules)
    // Mie: extinction = scattering + absorption
    // Ozone: pure absorption
    return RAYLEIGH_COEFF * dR
         + (MIE_SCAT_COEFF + MIE_ABS_COEFF) * dM
         + OZONE_ABSORPTION * dO;
}

// Scattering coefficient at a given height (excludes absorption)
float3 scatteringRayleighAt(float height, float planetR, float atmR) {
    return RAYLEIGH_COEFF * densityRayleigh(height, planetR, atmR);
}

float scatteringMieAt(float height, float planetR, float atmR) {
    return MIE_SCAT_COEFF * densityMie(height, planetR, atmR);
}

// MARK: - Optical Depth (tau) Integration
// tau(x1, x2) = integral of beta_e(x) dx along the ray

float3 computeOpticalDepth(float3 start, float3 dir, float segmentLength,
                           float planetR, float atmR, int steps) {
    float stepSize = segmentLength / float(steps);
    float3 opticalDepth = float3(0.0);

    for (int i = 0; i < steps; i++) {
        float3 samplePoint = start + dir * (float(i) + 0.5) * stepSize;
        float height = length(samplePoint);
        opticalDepth += extinctionAtHeight(height, planetR, atmR) * stepSize;
    }

    return opticalDepth;
}

// Transmittance: T(x1, x2) = exp(-tau(x1, x2))
float3 transmittance(float3 start, float3 dir, float segmentLength,
                     float planetR, float atmR, int steps) {
    return exp(-computeOpticalDepth(start, dir, segmentLength, planetR, atmR, steps));
}

// MARK: - Transmittance LUT Compute Shader

kernel void computeTransmittanceLUT(
    texture2d<float, access::write> lut [[texture(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uint(LUT_TRANSMITTANCE_W) || gid.y >= uint(LUT_TRANSMITTANCE_H)) return;

    float planetR = 1.0;
    float atmR = 1.04;

    // Map pixel coords to (cosZenith, height)
    float u = float(gid.x) / float(LUT_TRANSMITTANCE_W - 1);
    float v = float(gid.y) / float(LUT_TRANSMITTANCE_H - 1);

    float height = mix(planetR, atmR, v);
    float cosZenith = u * 2.0 - 1.0;
    float sinZenith = sqrt(max(0.0, 1.0 - cosZenith * cosZenith));

    float3 rayOrigin = float3(0.0, height, 0.0);
    float3 rayDir = float3(sinZenith, cosZenith, 0.0);

    // Find intersection with atmosphere top
    float2 atmIntersect = raySphereIntersect(rayOrigin, rayDir, float3(0.0), atmR);

    // No atmosphere hit
    float valid = step(0.0, atmIntersect.y);
    float rayLength = atmIntersect.y * valid;

    // Clip to planet surface if ray hits ground
    float2 planetIntersect = raySphereIntersect(rayOrigin, rayDir, float3(0.0), planetR);
    float hitsPlanet = step(0.0, planetIntersect.x);
    rayLength = mix(rayLength, min(rayLength, planetIntersect.x), hitsPlanet);

    int steps = 40;
    float3 T = transmittance(rayOrigin, rayDir, rayLength, planetR, atmR, steps);

    // If no valid ray, transmittance = 1 (no attenuation)
    T = mix(float3(1.0), T, valid);

    lut.write(float4(T, 1.0), gid);
}

// MARK: - Multiple Scattering LUT Compute Shader
// Approximation: F_ms = 1 / (1 - f_ms) where f_ms is energy transfer factor

kernel void computeMultipleScatteringLUT(
    texture2d<float, access::write> lut [[texture(0)]],
    texture2d<float, access::read> transmittanceLUT [[texture(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= uint(LUT_MULTISCATTER_SIZE) || gid.y >= uint(LUT_MULTISCATTER_SIZE)) return;

    float planetR = 1.0;
    float atmR = 1.04;

    float u = float(gid.x) / float(LUT_MULTISCATTER_SIZE - 1);
    float v = float(gid.y) / float(LUT_MULTISCATTER_SIZE - 1);

    float height = mix(planetR, atmR, v);
    float cosSunZenith = u * 2.0 - 1.0;
    float sinSunZenith = sqrt(max(0.0, 1.0 - cosSunZenith * cosSunZenith));
    float3 sunDir = float3(sinSunZenith, cosSunZenith, 0.0);

    // Integrate 2nd-order scattering over the sphere of directions
    // to compute the energy transfer factor f_ms
    float3 totalScattering = float3(0.0);
    float3 totalTransferEnergy = float3(0.0);
    int dirSamples = 8;

    for (int i = 0; i < dirSamples; i++) {
        for (int j = 0; j < dirSamples; j++) {
            float theta = PI * (float(i) + 0.5) / float(dirSamples);
            float phi = 2.0 * PI * (float(j) + 0.5) / float(dirSamples);
            float sinTheta = sin(theta);

            float3 dir = float3(sinTheta * cos(phi), cos(theta), sinTheta * sin(phi));

            float3 pos = float3(0, height, 0);
            float2 atmHit = raySphereIntersect(pos, dir, float3(0), atmR);
            float rayLen = max(0.0, atmHit.y);
            float2 planetHit = raySphereIntersect(pos, dir, float3(0), planetR);
            rayLen = mix(rayLen, min(rayLen, max(0.0, planetHit.x)), step(0.0, planetHit.x));

            float stepSize = rayLen / 8.0;
            float3 pathScatter = float3(0.0);
            float3 pathTransfer = float3(0.0);

            for (int s = 0; s < 8; s++) {
                float3 samplePos = pos + dir * (float(s) + 0.5) * stepSize;
                float h = length(samplePos);
                float3 sampleUp = normalize(samplePos);

                float dR = densityRayleigh(h, planetR, atmR);
                float dM = densityMie(h, planetR, atmR);
                float3 localScatter = RAYLEIGH_COEFF * dR + MIE_SCAT_COEFF * dM;

                // Look up transmittance to sun from this sample point
                float cosSun = dot(sampleUp, sunDir);
                float lutU = (cosSun + 1.0) * 0.5;
                float lutV = saturate((h - planetR) / (atmR - planetR));
                uint2 lutCoord = uint2(uint(lutU * float(LUT_TRANSMITTANCE_W - 1)),
                                       uint(saturate(lutV) * float(LUT_TRANSMITTANCE_H - 1)));
                float3 sunTrans = transmittanceLUT.read(lutCoord).rgb;

                pathScatter += localScatter * sunTrans * stepSize;
                pathTransfer += localScatter * stepSize;
            }

            float solidAngle = sinTheta; // jacobian for spherical integration
            totalScattering += pathScatter * solidAngle;
            totalTransferEnergy += pathTransfer * solidAngle;
        }
    }

    float normFactor = (4.0 * PI) / float(dirSamples * dirSamples);
    totalScattering *= normFactor;
    totalTransferEnergy *= normFactor;

    // Infinite multiple scattering approximation:
    // F_ms = 1 / (1 - f_ms), where f_ms = totalTransferEnergy (isotropic phase = 1/4pi)
    float3 f_ms = totalTransferEnergy * INV_4PI;
    float3 F_ms = 1.0 / max(float3(0.001), 1.0 - f_ms);

    // Final multiply: 2nd-order scattered light * infinite bounce factor
    float3 multiScattered = totalScattering * INV_4PI * F_ms;

    lut.write(float4(multiScattered, 1.0), gid);
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
    // Unpack: n_x = 2*R - 1, n_y = 2*G - 1, n_z = 2*B - 1
    float3 normalSample = normalMap.sample(texSampler, uv).rgb;
    float3 localNormal = normalize(normalSample * 2.0 - 1.0);

    // TBN matrix: transform tangent-space normal to world space
    float3x3 TBN = float3x3(T, B, N);
    float3 worldNormal = normalize(TBN * localNormal);

    // --- Diffuse Lighting ---
    float NdotL = dot(worldNormal, L);
    float diffuse = max(NdotL, 0.0);

    // Day/night transition with smooth blend via exponential falloff
    float dayWeight = saturate(NdotL * 3.0 + 0.3);
    dayWeight = pow(dayWeight, 1.5);

    float4 dayColor = dayTexture.sample(texSampler, uv);
    float4 nightColor = nightTexture.sample(texSampler, uv);

    float ambient = 0.06;
    float3 surfaceColor = mix(nightColor.rgb, dayColor.rgb * (diffuse + ambient), dayWeight);

    // --- Specular / Ocean Reflections ---
    // reflect(v, w) = v - 2*(v.w)*w
    float specMask = specularMap.sample(texSampler, uv).r;
    float3 R = reflect(-L, worldNormal);
    float RdotV = max(dot(R, V), 0.0);

    float specPower = 64.0;
    float specular = pow(RdotV, specPower) * specMask * diffuse;
    surfaceColor += float3(1.0, 0.95, 0.8) * specular * 1.5;

    // --- Cloud Layer ---
    float2 cloudUV = uv + float2(uniforms.cloudTime * 0.001, 0.0);
    float4 cloudSample = cloudTexture.sample(texSampler, cloudUV);
    // JPEG clouds: derive alpha from luminance
    float cloudAlpha = max(cloudSample.a, dot(cloudSample.rgb, float3(0.299, 0.587, 0.114)));

    float cloudDiffuse = max(dot(N, L), 0.0);
    float3 cloudColor = cloudSample.rgb * (cloudDiffuse * 0.9 + 0.1);

    // --- Cloud Shadows ---
    // Project shadow along surface: dot(N, L)*N - L converted to local coords
    float3 shadowOffset3D = dot(N, L) * N - L;
    float3x3 invTBN = transpose(TBN);
    float3 shadowLocal = invTBN * shadowOffset3D;
    float2 shadowUV = uv + shadowLocal.xy * 0.005;
    float4 shadowSample = cloudTexture.sample(texSampler, shadowUV + float2(uniforms.cloudTime * 0.001, 0.0));
    float shadowCloud = max(shadowSample.a, dot(shadowSample.rgb, float3(0.299, 0.587, 0.114)));

    float shadowFactor = 1.0 - shadowCloud * 0.35 * saturate(NdotL);
    surfaceColor *= shadowFactor;

    surfaceColor = mix(surfaceColor, cloudColor, cloudAlpha * 0.85);

    // --- Surface Transmittance ---
    // T(surface, camera) from LUT — atmospheric extinction on surface radiance
    float planetR = uniforms.planetRadius;
    float atmR = uniforms.atmosphereRadius;
    float3 surfNormalized = normalize(in.worldPosition);
    float surfHeight = length(in.worldPosition);
    float cosViewZenith = dot(surfNormalized, V);

    float lutU = (cosViewZenith + 1.0) * 0.5;
    float lutV = saturate((surfHeight - planetR) / (atmR - planetR));
    float3 viewTransmittance = transmittanceLUT.sample(texSampler, float2(lutU, lutV)).rgb;

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

// MARK: - Atmosphere Fragment Shader (Physical Ray Marching)
//
// Implements the full rendering equation:
// L_tot = T(x,x0)*L_surface + integral{ beta_s(y)*T(x,y) * [P_R*L_sun*T_sun + P_M*L_sun*T_sun + F_ms] } dy
//
// With Rayleigh scattering (blue glow), Mie scattering (sun halo),
// ozone absorption, and infinite multiple scattering approximation.

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

    // Discard if no atmosphere hit (branchless not possible for discard)
    if (atmHit.y < 0.0) discard_fragment();

    float rayStart = max(atmHit.x, 0.0);
    float rayEnd = atmHit.y;

    // Planet occlusion (branchless clamp)
    float2 planetHit = raySphereIntersect(camPos, rayDir, float3(0.0), planetR);
    float hitsPlanet = step(0.0, planetHit.x);
    rayEnd = mix(rayEnd, min(rayEnd, planetHit.x), hitsPlanet);

    float rayLength = rayEnd - rayStart;
    if (rayLength <= 0.0) discard_fragment();

    // --- Phase functions (computed once, constant along ray) ---
    float cosTheta = dot(rayDir, sunDir);
    float phaseR = rayleighPhase(cosTheta);
    float phaseM = miePhase(cosTheta);

    // --- Day/night mask at atmosphere entry point ---
    // Used to modulate the glow: visible on sunlit side, fades on dark side
    float3 entryPoint = camPos + rayDir * rayStart;
    float3 entryNormal = normalize(entryPoint);
    float sunIncidence = dot(entryNormal, sunDir);
    // Smooth transition across terminator (wider than surface to show twilight glow)
    float dayMask = saturate(sunIncidence * 2.0 + 0.5);

    // --- Ray marching ---
    int numSteps = 32;
    float stepSize = rayLength / float(numSteps);
    float sunIntensity = 22.0;

    float3 inScatteredLight = float3(0.0);
    float3 totalExtinction = float3(0.0); // accumulated optical depth

    for (int i = 0; i < numSteps; i++) {
        float3 samplePos = camPos + rayDir * (rayStart + (float(i) + 0.5) * stepSize);
        float sampleHeight = length(samplePos);

        // Density at sample point
        float dR = densityRayleigh(sampleHeight, planetR, atmR);
        float dM = densityMie(sampleHeight, planetR, atmR);
        float dO = densityOzone(sampleHeight, planetR, atmR);

        // Local extinction: beta_e = beta_scatter + beta_absorb
        float3 localExtinction = RAYLEIGH_COEFF * dR
                               + (MIE_SCAT_COEFF + MIE_ABS_COEFF) * dM
                               + OZONE_ABSORPTION * dO;

        // Accumulate optical depth along view ray
        totalExtinction += localExtinction * stepSize;

        // Transmittance from camera to this sample: T(camera, sample) = exp(-tau)
        float3 viewTrans = exp(-totalExtinction);

        // Transmittance from sample to sun via LUT
        float3 sampleNorm = normalize(samplePos);
        float cosSunZenith = dot(sampleNorm, sunDir);
        float heightFrac = saturate((sampleHeight - planetR) / (atmR - planetR));
        float sLutU = (cosSunZenith + 1.0) * 0.5;
        float3 sunTrans = transmittanceLUT.sample(texSampler, float2(sLutU, heightFrac)).rgb;

        // Multiple scattering contribution (precomputed F_ms factor included)
        float3 multiScatter = multiScatterLUT.sample(texSampler, float2(sLutU, heightFrac)).rgb;

        // Scattering coefficients (only scattering, not absorption)
        float3 scatR = RAYLEIGH_COEFF * dR;
        float scatM = MIE_SCAT_COEFF * dM;

        // In-scattered radiance at this sample:
        // L_inscatter = beta_s * T_view * [T_sun * (P_R + P_M) * L_sun + F_ms * L_sun]
        float3 singleScatterR = scatR * phaseR * sunTrans;
        float3 singleScatterM = float3(scatM) * phaseM * sunTrans;
        float3 multiScatterContrib = (scatR + float3(scatM)) * multiScatter;

        inScatteredLight += viewTrans * (singleScatterR + singleScatterM + multiScatterContrib) * stepSize;
    }

    float3 atmosphere = inScatteredLight * sunIntensity;

    // --- Fresnel Edge Glow (Bright Blue Rim) ---
    // Visible ALL around the planet (day and night side)
    // Tight, concentrated glow right at the limb
    float3 surfPoint = camPos + rayDir * rayStart;
    float3 surfNorm = normalize(surfPoint);
    float fresnelAngle = 1.0 - abs(dot(surfNorm, -rayDir));

    // Tight electric blue rim — high power for sharp falloff, visible everywhere
    float rimIntensity = pow(fresnelAngle, 3.0);
    float3 rimColor = float3(0.15, 0.4, 1.0); // Deep electric/cobalt blue

    // Day side: brighter rim + physical scattering
    // Night side: still visible rim but slightly dimmer
    float rimDayBoost = mix(0.7, 1.0, dayMask); // Night=0.7x, Day=1.0x
    atmosphere += rimColor * rimIntensity * rimDayBoost * 1.2;

    // Extra-bright thin edge line (very high power Fresnel for the sharp limb)
    float thinEdge = pow(fresnelAngle, 8.0);
    atmosphere += float3(0.3, 0.6, 1.0) * thinEdge * 0.8;

    // --- Tone Mapping (ACES approximation) ---
    float3 x = atmosphere;
    atmosphere = (x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14);
    atmosphere = saturate(atmosphere);

    // Alpha: strong at the rim for the visible glow ring
    float alpha = saturate(dot(atmosphere, float3(0.299, 0.587, 0.114)) * 3.0 + rimIntensity * 0.6);

    // Reduce alpha over planet surface
    alpha = mix(alpha, alpha * 0.5, hitsPlanet);

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

    float diffuse = max(dot(N, L), 0.0);
    float lighting = diffuse * 0.7 + 0.3;

    return float4(texColor.rgb * lighting, 1.0);
}

// MARK: - Outer Glow Fragment Shader (Electric Blue Rim Halo)
//
// Creates the bright blue atmospheric rim glow visible all around the planet.
// Matches the reference: tight, vivid cobalt blue rim hugging the limb,
// visible on both day and night sides, with sharp falloff into space.

fragment float4 outerGlowFragmentShader(
    AtmosphereVertexOut in [[stage_in]],
    constant Uniforms &uniforms [[buffer(1)]]
) {
    float planetR = uniforms.planetRadius;
    float3 sunDir = normalize(uniforms.sunDirection);
    float3 camPos = uniforms.cameraPosition;
    float3 fragWorldPos = in.worldPosition;
    float3 rayDir = normalize(fragWorldPos - camPos);

    // Don't draw over the planet surface
    float2 planetHit = raySphereIntersect(camPos, rayDir, float3(0.0), planetR);
    float overPlanet = step(0.0, planetHit.x);

    // Fragment's position relative to planet center
    float3 fragNormal = normalize(fragWorldPos);
    float distFromCenter = length(fragWorldPos);

    // --- Radial distance falloff ---
    // Glow is tightest near the planet surface and drops off sharply
    float glowOuterEdge = planetR * 1.08; // Glow extends ~8% beyond surface
    float normalizedDist = (distFromCenter - planetR) / (glowOuterEdge - planetR);
    float radialFalloff = saturate(1.0 - normalizedDist);
    radialFalloff = pow(radialFalloff, 1.5); // Sharp falloff

    // --- Fresnel (limb brightening) ---
    // Glow is brightest at the very edge of the planet silhouette
    float3 viewDir = -rayDir;
    float NdotV = abs(dot(fragNormal, viewDir));
    float fresnel = 1.0 - NdotV;
    float rimGlow = pow(fresnel, 2.0);

    // --- Day/night modulation (subtle — glow is visible everywhere) ---
    float sunCosAngle = dot(fragNormal, sunDir);
    // Night side gets ~60% intensity, day side gets 100%
    float dayBoost = mix(0.6, 1.0, saturate(sunCosAngle * 1.5 + 0.5));

    // --- Electric blue rim color ---
    // Deep cobalt blue matching the reference image
    float3 rimColor = float3(0.1, 0.35, 1.0);

    // Primary glow: tight rim around the entire planet
    float glowStrength = rimGlow * radialFalloff * dayBoost;
    float3 glowColor = rimColor * glowStrength * 1.4;

    // Brighter thin edge (very concentrated at the limb)
    float thinEdge = pow(fresnel, 5.0) * radialFalloff;
    glowColor += float3(0.2, 0.5, 1.0) * thinEdge * dayBoost * 0.8;

    // Softer wide glow (subtle diffuse spread beyond the sharp rim)
    float wideGlow = pow(fresnel, 1.2) * pow(radialFalloff, 2.5);
    glowColor += float3(0.05, 0.15, 0.5) * wideGlow * dayBoost * 0.4;

    // --- Mie sun halo (warm tint near sun direction) ---
    float sunAlignment = max(0.0, dot(rayDir, sunDir));
    float mieHalo = pow(sunAlignment, 16.0) * radialFalloff;
    glowColor += float3(0.4, 0.5, 0.8) * mieHalo * 0.3;

    // Alpha: visible all around, strongest at the rim
    float alpha = saturate(glowStrength * 1.5 + thinEdge * 1.0 + wideGlow * 0.3);

    // Hide over planet surface
    alpha *= (1.0 - overPlanet);

    return float4(glowColor, alpha);
}
