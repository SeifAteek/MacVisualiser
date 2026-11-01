#include <metal_stdlib>
using namespace metal;

// Must match `Uniforms` in Renderer.swift field for field (all floats, so layouts agree).
struct U {
    float width, height, time, rtime;
    float bass, mid, treble, level;
    float beat, beatCount, mode, prevMode;
    float mixT, hue, trails, fbZoom;
    float fbRotate, fbHue, symmetry, bloom;
    float chroma, grain, vignette, flash;
    float shake, pad0, pad1, pad2;
};

struct VOut { float4 pos [[position]]; float2 uv; };

#define ARGS constant U& u, constant float* sp, constant float* wv, constant float4* pl
#define PASS u, sp, wv, pl
#define SPEC(x) lookup(sp, x)
#define WAVE(x) lookup(wv, x)
#define PAL(t) pal(pl, t)
#define TAU 6.2831853

vertex VOut vsQuad(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    VOut o;
    o.pos = float4(p * 2 - 1, 0, 1);
    o.uv = p; // y up
    return o;
}

// uv (y up) -> texture coordinate (y down)
float2 tc(float2 uv) { return float2(uv.x, 1 - uv.y); }

float lookup(constant float* a, float x) {
    float f = saturate(x) * 255;
    int i = int(f);
    return mix(a[i], a[min(i + 1, 255)], f - i);
}

// Inigo Quilez cosine palette; a,b,c,d come from the CPU so palettes are swappable/blendable.
float3 pal(constant float4* pl, float t) {
    return pl[0].rgb + pl[1].rgb * cos(TAU * (pl[2].rgb * t + pl[3].rgb));
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3 - 2 * f);
    return mix(mix(hash21(i), hash21(i + float2(1, 0)), f.x),
               mix(hash21(i + float2(0, 1)), hash21(i + float2(1, 1)), f.x), f.y);
}

float fbm(float2 p) {
    float v = 0, a = 0.5;
    for (int i = 0; i < 5; i++) { v += a * noise(p); p = float2x2(1.6, 1.2, -1.2, 1.6) * p; a *= 0.5; }
    return v;
}

float2x2 rot(float a) { float c = cos(a), s = sin(a); return float2x2(c, s, -s, c); }

float3 hueRotate(float3 c, float a) {
    const float3 k = float3(0.57735);
    float ca = cos(a);
    return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1 - ca);
}

float3 stars(float2 p, float density, float bright) {
    float2 g = p * density;
    float h = hash21(floor(g));
    return step(0.985, h) * smoothstep(0.25, 0.0, length(fract(g) - 0.5)) * bright;
}

// ───────────────────────────── scenes ─────────────────────────────

float3 sNebula(float2 p, ARGS) {
    float t = u.time * 0.08;
    float2 q = p * 1.4;
    float2 w = float2(fbm(q + float2(0, t)), fbm(q + float2(5.2, 1.3) - t));
    float2 r = float2(fbm(q + 3.5 * w + float2(1.7, 9.2) + t * 1.5 + u.bass * 0.4),
                      fbm(q + 3.5 * w + float2(8.3, 2.8) - t * 1.2));
    float f = fbm(q + 3.5 * r);
    float3 col = PAL(f * 1.4 + length(r) * 0.6 + t * 0.5) * (f * f * 2.2 + 0.05);
    col *= 0.5 + u.level * 1.6;
    col += PAL(r.y + 0.3) * pow(saturate(f * 1.25), 8.0) * (0.5 + u.treble * 5);
    col += stars(p, 40, (0.4 + u.treble * 2) * (0.5 + 0.5 * sin(u.rtime * 3 + p.x * 50)));
    return col;
}

float3 sTunnel(float2 p, ARGS) {
    p = rot(u.time * 0.1) * p;
    float r = length(p), a = atan2(p.y, p.x);
    float z = 0.35 / max(r, 0.001) + u.time * 1.2;
    float ang = a / TAU + 0.5;
    float s = SPEC(abs(fract(ang * 2) * 2 - 1));
    float2 g = float2(ang * 24, z * 2);
    float2 gf = abs(fract(g) - 0.5);
    float grid = smoothstep(0.42, 0.5, max(gf.x, gf.y));
    float3 col = PAL(z * 0.04 + ang) * grid * (0.3 + u.bass * 2.0);
    col += PAL(ang * 2 + 0.25) * s * s * 2.0 * (1 - grid) * (0.6 + 0.4 * sin(z * 3.0));
    col *= smoothstep(0.0, 0.6, r);
    col += PAL(0.6 + u.time * 0.02) * (0.04 / (r + 0.04)) * (0.2 + u.bass * 1.5 + u.beat);
    return col;
}

float3 sRadial(float2 p, ARGS) {
    float r = length(p), a = atan2(p.x, p.y);
    float ang = a / TAU + 0.5;
    float x = abs(ang * 2 - 1);
    float nb = 72;
    float id = floor(x * nb) / nb, cell = fract(x * nb);
    float s = SPEC(id);
    float base = 0.32 + u.bass * 0.06 + u.beat * 0.03;
    float top = base + 0.03 + s * 0.55;
    float gap = smoothstep(0.08, 0.2, cell) * smoothstep(0.92, 0.8, cell);
    float bar = smoothstep(base, base + 0.005, r) * smoothstep(top + 0.005, top, r) * gap;
    float3 col = PAL(id * 0.8 + r * 0.6 + u.time * 0.02) * bar * (0.6 + s * 1.5);
    col += PAL(id + 0.2) * 0.006 / (abs(r - top) + 0.002) * s * gap;
    float wr = base - 0.06 + WAVE(x) * 0.05;
    col += PAL(ang + u.time * 0.05) * 0.003 / (abs(r - wr) + 0.001) * (0.4 + u.level);
    col += PAL(0.1 + u.time * 0.03) * smoothstep(base - 0.1, base - 0.25, r) * (0.1 + u.beat * 0.6 + u.bass * 0.3);
    float2 gp = float2(ang * 60, r * 6 - u.time * 1.5);
    float h = hash21(floor(gp));
    col += step(0.93, h) * smoothstep(0.3, 0.0, length(fract(gp) - 0.5)) * PAL(h) * (0.3 + u.treble * 2) * smoothstep(0.3, 0.6, r);
    return col;
}

float3 sJulia(float2 p, ARGS) {
    float t = u.time * 0.15;
    float2 c = float2(-0.745 + 0.1 * sin(t * 0.7) + u.bass * 0.04, 0.12 + 0.1 * cos(t * 0.5) + u.mid * 0.03);
    float2 z = rot(t * 0.3) * p * (1.1 - u.beat * 0.08);
    float trap = 1e9;
    const int MAXI = 100;
    int i;
    for (i = 0; i < MAXI; i++) {
        z = float2(z.x * z.x - z.y * z.y, 2 * z.x * z.y) + c;
        trap = min(trap, abs(length(z) - 0.5));
        if (dot(z, z) > 256) break;
    }
    float3 col;
    if (i == MAXI) {
        col = PAL(trap * 2 + t) * (0.2 + u.bass);
    } else {
        float n = float(i) - log2(log2(dot(z, z))) + 4;
        col = PAL(n * 0.035 + t * 0.5) * (0.4 + 0.6 * sqrt(max(n, 0.0) / MAXI)) * (0.6 + u.level * 1.4);
    }
    col += PAL(0.9) * exp(-trap * 30) * u.treble * 2;
    return col;
}

float3 sScope(float2 p, float2 uv, ARGS) {
    float3 col = 0;
    for (int k = 0; k < 5; k++) {
        float fk = k;
        float y = WAVE(uv.x) * (0.55 - fk * 0.08) * (k % 2 == 0 ? 1 : -1);
        y += sin(uv.x * TAU * 2 + u.time + fk) * 0.03 * fk * u.mid;
        float d = abs(p.y - y);
        col += PAL(fk * 0.12 + uv.x * 0.4 + u.time * 0.03) * (0.004 + 0.002 * u.level) / (d + 0.004) * (1 - fk * 0.17);
    }
    float2 g = abs(fract(p * 4) - 0.5);
    col += PAL(0.6) * 0.05 * smoothstep(0.48, 0.5, max(g.x, g.y));
    float s = SPEC(abs(uv.x * 2 - 1));
    col += PAL(uv.x + 0.5) * smoothstep(s * 0.6 + 0.001, 0.0, 1 - abs(p.y)) * s * 0.6;
    return col;
}

float3 sStars(float2 p, ARGS) {
    float3 col = 0;
    float t = u.time * 0.4;
    for (int i = 0; i < 6; i++) {
        float depth = fract(float(i) / 6 + t);
        float scale = mix(18.0, 0.6, depth);
        float fade = depth * smoothstep(1.0, 0.85, depth);
        float2 q = rot(i * 1.7) * p * scale + i * 31.7;
        float2 id = floor(q), gv = fract(q) - 0.5;
        float h = hash21(id);
        float2 off = float2(h, fract(h * 34.1)) - 0.5;
        float d = length(gv - off * 0.7);
        float star = (0.015 + u.treble * 0.02) / d * smoothstep(0.5, 0.2, d);
        col += PAL(h + u.time * 0.02) * star * fade * (0.6 + u.bass * 1.5);
    }
    float r = length(p), a = atan2(p.y, p.x);
    float streak = pow(noise(float2(a * 30, r * 2 - u.time * 4)), 6.0) * smoothstep(0.1, 1.2, r);
    col += PAL(0.5 + a * 0.1) * streak * (u.bass * 3 + u.beat * 2);
    col += PAL(0.2) * 0.03 / (r + 0.03) * (0.3 + u.bass);
    return col;
}

float3 sPlasma(float2 p, ARGS) {
    float t = u.time * 0.6;
    float r = length(p);
    float v = sin(p.x * 3 + t) + sin(p.y * 3.3 - t * 1.3) + sin((p.x + p.y) * 2.5 + t * 0.7) + sin(r * 8 - t * 2 - u.bass * 3);
    float2 q = p + float2(sin(t * 0.3), cos(t * 0.4));
    v += sin(length(q) * 5 + t);
    v += SPEC(fract(r * 0.5)) * 3;
    float3 col = PAL(v * 0.15 + t * 0.05) * (0.3 + 0.5 * u.level + 0.15 * sin(v * 3.14159) + 0.15);
    col += PAL(v * 0.15 + 0.5) * smoothstep(0.9, 1.0, sin(v * TAU)) * (0.3 + u.treble * 2);
    return col;
}

float3 sBars(float2 p, float2 uv, ARGS) {
    float nb = 48;
    float x = abs(uv.x * 2 - 1);
    float id = floor(x * nb), cell = fract(x * nb);
    float s = SPEC(id / nb);
    float h = s * 0.62;
    float y = uv.y - 0.32;
    float gap = smoothstep(0.1, 0.2, cell) * smoothstep(0.9, 0.8, cell);
    float seg = smoothstep(0.15, 0.3, fract(y * 60));
    float3 c = PAL(id / nb * 0.7 + y * 0.8 + u.time * 0.02);
    float3 col = y > 0 ? c * step(y, h) * gap * seg * (0.6 + s)
                       : c * step(-y, h * 0.5) * gap * 0.25 * smoothstep(h * 0.5, 0.0, -y);
    col += c * 0.004 / (abs(y - h) + 0.004) * gap * s;
    col += PAL(0.5) * 0.002 / (abs(y) + 0.002) * (0.3 + u.bass);
    col += PAL(0.8) * 0.1 * (1 - uv.y) * u.bass;
    return col;
}

float orbMap(float3 q, ARGS) {
    float3 n = normalize(q);
    float s = SPEC(abs(n.y));
    float d = sin(n.x * 7 + u.time) * sin(n.y * 7 + u.time * 1.3) * sin(n.z * 7 - u.time * 0.7);
    return length(q) - (0.75 + u.bass * 0.25 + s * 0.35 + d * (0.06 + u.mid * 0.25));
}

float3 sOrb(float2 p, ARGS) {
    float t = u.time * 0.3;
    float3 ro = float3(0, 0, 3);
    float3 rd = normalize(float3(p, -1.8));
    float2x2 R = rot(t), R2 = rot(t * 0.6);
    ro.xz = R * ro.xz; rd.xz = R * rd.xz;
    ro.yz = R2 * ro.yz; rd.yz = R2 * rd.yz;
    float dist = 0;
    bool hit = false;
    for (int i = 0; i < 80; i++) {
        float d = orbMap(ro + rd * dist, PASS);
        if (d < 0.001) { hit = true; break; }
        dist += d * 0.6;
        if (dist > 8) break;
    }
    float r = length(p);
    float3 col = PAL(0.6 + r * 0.3) * 0.08 / (r * r + 0.1) * (0.3 + u.bass);
    if (hit) {
        float3 pos = ro + rd * dist;
        float2 e = float2(0.002, 0);
        float3 nor = normalize(float3(orbMap(pos + e.xyy, PASS) - orbMap(pos - e.xyy, PASS),
                                      orbMap(pos + e.yxy, PASS) - orbMap(pos - e.yxy, PASS),
                                      orbMap(pos + e.yyx, PASS) - orbMap(pos - e.yyx, PASS)));
        float3 l = normalize(float3(0.6, 0.8, 0.5));
        float diff = max(dot(nor, l), 0.0);
        float fres = pow(1 - max(dot(nor, -rd), 0.0), 3.0);
        float spec = pow(max(dot(reflect(rd, nor), l), 0.0), 32.0);
        float3 base = PAL(length(pos) * 1.5 + nor.y * 0.3 + u.time * 0.05);
        col = base * (0.15 + diff * 0.8) + PAL(0.5) * fres * (1.5 + u.treble * 3) + spec;
    }
    return col;
}

float3 sAurora(float2 p, float2 uv, ARGS) {
    float3 col = PAL(0.7) * 0.03 * (1 - uv.y);
    for (int i = 0; i < 5; i++) {
        float fi = i;
        float yc = 0.15 + fi * 0.12 + (fbm(float2(p.x * 0.8 + u.time * 0.05 * (1 + fi * 0.3), fi * 3.1)) - 0.5) * 0.8 - 0.3;
        float s = SPEC(saturate(abs(p.x) * 0.5 + fi * 0.05));
        float dy = p.y - yc;
        float rays = 0.4 + 0.6 * noise(float2(p.x * 30 + fi * 10, u.time * 0.4 + fi));
        float band = smoothstep(-0.04, 0.0, dy) * exp(-max(dy, 0.0) * (3.5 - u.bass));
        col += PAL(fi * 0.12 + p.x * 0.1 + u.time * 0.02) * band * rays * (0.15 + s * 1.2) * 0.6;
    }
    col += stars(p, 60, 0.6);
    return col;
}

float3 sSynth(float2 p, ARGS) {
    float hz = -0.15;
    float dz = max(hz - p.y, 0.001);
    float z = 0.25 / dz;
    float2 gp = float2(p.x * z, z + u.time * 1.5);
    float2 fw = fwidth(gp); // outside the branch: derivatives need uniform control flow
    float3 col;
    if (p.y > hz) {
        col = mix(PAL(0.75) * 0.25, PAL(0.6) * 0.02, saturate((p.y - hz) * 1.2));
        float2 sc = float2(0, 0.28);
        float sr = 0.48 + u.bass * 0.05 + u.beat * 0.03;
        float d = length(p - sc);
        float sy = (p.y - sc.y) / sr;
        float visible = sy > 0 ? 1.0 : step(saturate(-sy) * 0.6, fract(sy * 10 + u.time * 0.4));
        float3 sun = mix(PAL(0.05), PAL(0.35), sy * 0.5 + 0.5) * 1.6;
        col = mix(col, sun, smoothstep(sr, sr - 0.005, d) * visible);
        col += PAL(0.1) * 0.03 / (abs(d - sr) + 0.03) * (0.3 + u.bass * 0.8);
        float m = hz + 0.05 + SPEC(saturate(abs(p.x) * 0.5)) * 0.35 * smoothstep(0.0, 0.6, abs(p.x)) + noise(float2(p.x * 6, 0)) * 0.05;
        if (p.y < m) col = PAL(0.7) * 0.03;
        col += PAL(0.85) * 0.002 / (abs(p.y - m) + 0.002) * 0.6;
    } else {
        float2 dl = 0.5 - abs(fract(gp) - 0.5);
        float lx = 1 - smoothstep(0.0, fw.x * 1.5, dl.x);
        float lz = 1 - smoothstep(0.0, fw.y * 1.5, dl.y);
        col = PAL(0.85) * max(lx, lz) * exp(-z * 0.08) * (0.6 + u.bass * 1.5) + PAL(0.75) * 0.15 * exp(-dz * 6);
    }
    return col;
}

float3 scene(int m, float2 p, float2 uv, ARGS) {
    switch (m) {
        case 0: return sNebula(p, PASS);
        case 1: return sTunnel(p, PASS);
        case 2: return sRadial(p, PASS);
        case 3: return sJulia(p, PASS);
        case 4: return sScope(p, uv, PASS);
        case 5: return sStars(p, PASS);
        case 6: return sPlasma(p, PASS);
        case 7: return sBars(p, uv, PASS);
        case 8: return sOrb(p, PASS);
        case 9: return sAurora(p, uv, PASS);
        default: return sSynth(p, PASS);
    }
}

// ───────────────────────────── passes ─────────────────────────────

fragment float4 fsScene(VOut in [[stage_in]], constant U& u [[buffer(0)]], constant float* sp [[buffer(1)]],
                        constant float* wv [[buffer(2)]], constant float4* pl [[buffer(3)]]) {
    float2 p = (in.uv - 0.5) * 2 * float2(u.width / u.height, 1);
    float3 c = scene(int(u.mode), p, in.uv, PASS);
    if (u.mixT < 1) c = mix(scene(int(u.prevMode), p, in.uv, PASS), c, smoothstep(0.0, 1.0, u.mixT));
    return float4(max(c, 0.0), 1);
}

// Kaleidoscope fold of the scene + Milkdrop-style feedback (zoom / rotate / hue-drift of last frame).
fragment float4 fsFeedback(VOut in [[stage_in]], constant U& u [[buffer(0)]],
                           texture2d<float> scn [[texture(0)]], texture2d<float> prev [[texture(1)]]) {
    constexpr sampler s(filter::linear, address::mirrored_repeat);
    float2 asp = float2(u.width / u.height, 1);
    float2 p = (in.uv - 0.5) * asp;
    if (u.symmetry >= 2) {
        float seg = TAU / u.symmetry;
        float a = fmod(atan2(p.y, p.x) + u.time * 0.05 + 100 * seg, seg);
        a = abs(a - seg * 0.5);
        p = length(p) * float2(cos(a), sin(a));
    }
    float3 col = scn.sample(s, tc(p / asp + 0.5)).rgb;
    if (u.trails > 0) {
        float2 q = rot(u.fbRotate * 0.03) * ((in.uv - 0.5) * asp);
        q /= 1 + u.fbZoom * 0.04 * (1 + u.bass);
        float3 pc = hueRotate(prev.sample(s, tc(q / asp + 0.5)).rgb, u.fbHue * 0.1);
        col = max(col, pc * u.trails);
    }
    return float4(col, 1);
}

fragment float4 fsPost(VOut in [[stage_in]], constant U& u [[buffer(0)]], constant float4* pl [[buffer(3)]],
                       texture2d<float> img [[texture(0)]]) {
    constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
    float2 uv = in.uv + (float2(hash21(float2(u.rtime, 1)), hash21(float2(u.rtime, 2))) - 0.5) * u.beat * u.shake * 0.03;
    float2 d = uv - 0.5;
    float ca = u.chroma * 0.012 * (0.5 + u.bass);
    float3 col = float3(img.sample(s, tc(uv + d * ca), level(0)).r,
                        img.sample(s, tc(uv), level(0)).g,
                        img.sample(s, tc(uv - d * ca), level(0)).b);
    // Wide, cheap bloom from the mip chain.
    float3 b = img.sample(s, tc(uv), level(3)).rgb * 0.5 + img.sample(s, tc(uv), level(5)).rgb * 0.8 + img.sample(s, tc(uv), level(7)).rgb;
    col += max(b - 0.15, 0.0) * u.bloom * 0.5;
    col = hueRotate(col, u.hue);
    col += (PAL(u.beatCount * 0.37) + 0.4) * u.beat * u.flash * 0.25;
    col = (col * (2.51 * col + 0.03)) / (col * (2.43 * col + 0.59) + 0.14); // ACES fit
    col *= mix(1.0, smoothstep(0.95, 0.25, length(d * float2(u.width / u.height, 1) * 0.9)), u.vignette);
    col += (hash21(in.uv * u.width + fract(u.rtime) * 100) - 0.5) * u.grain * 0.15;
    return float4(saturate(col), 1);
}
