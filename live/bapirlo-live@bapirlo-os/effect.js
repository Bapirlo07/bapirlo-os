// The live layer itself: one fragment shader on the wallpaper actor (Meta.BackgroundActor).
// Clutter renders the wallpaper once into an offscreen texture; each frame only this shader runs
// on the GPU (Intel iGPU — the compositor's card — so the NVIDIA card stays asleep).
//   · embers   3 depth layers rising from the bottom, flickering, additive glow
//   · petals   3 depth layers falling diagonally, tumbling (width follows the flip)
//   · glow     the crimson parts of the art breathe ±10 % brightness
//   · parallax art zoomed 2 % and shifted up to 0.8 % against the pointer
//   · depth    3D: a depth map of the picture (layer 1, white = near; see lib/bapirlo_depth.py) moves
//              near things further than far things. Per pixel it marches the eye ray from the nearest
//              layer back (20 steps, then refined between the last two), so the first surface hit wins
//              and foreground edges occlude properly instead of ghosting
// Particles live one per grid cell (most cells empty), drawn only inside their own cell, so a
// pixel costs 6 cheap evaluations — no loops over neighbours.
import Clutter from 'gi://Clutter';
import Cogl from 'gi://Cogl';
import GdkPixbuf from 'gi://GdkPixbuf';
import GObject from 'gi://GObject';

const DECLARATIONS = `
uniform sampler2D tex;
uniform float t;
uniform float aspect;
uniform float amount;
uniform float density;
uniform float embers;
uniform float petals;
uniform float glow;
uniform float zoom;
uniform vec2 shift;
uniform vec3 ember_col;
uniform vec3 petal_col;
uniform sampler2D depth_tex;
uniform float depth_on;
uniform vec2 dscale;
uniform vec2 dshift;
uniform float focal;

float depthAt(vec2 p) {
    return texture2D(depth_tex, (p - 0.5) * dscale + 0.5).r;
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// one ember layer: returns glow intensity at uv
float emberLayer(vec2 uv, float scale, float speed, float seed) {
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y += t * speed;
    p.x += sin(p.y * 0.9 + seed) * 0.35;
    vec2 cell = floor(p);
    float r = hash12(cell + seed);
    if (r > density * 0.6)
        return 0.0;
    vec2 c = 0.3 + 0.4 * hash22(cell + seed * 1.7);
    c.x += 0.07 * sin(t * (0.6 + r) + r * 40.0);
    float d = length(fract(p) - c);
    float size = mix(0.03, 0.075, hash12(cell + 3.1 + seed));
    float flick = 0.55 + 0.45 * sin(t * (2.0 + r * 4.0) + r * 60.0);
    float core = smoothstep(size, size * 0.2, d);
    float halo = smoothstep(size * 3.2, 0.0, d) * 0.5;
    return (core + halo) * flick;
}

// one petal layer: returns alpha (x) and shading (y)
vec2 petalLayer(vec2 uv, float scale, float speed, float seed) {
    vec2 p = vec2(uv.x * aspect, uv.y) * scale;
    p.y -= t * speed;
    p.x -= t * speed * 0.55;
    p.x += sin(p.y * 0.7 + seed) * 0.25;
    vec2 cell = floor(p);
    float r = hash12(cell + seed);
    if (r > density * 0.5)
        return vec2(0.0);
    vec2 c = 0.35 + 0.3 * hash22(cell + seed * 2.3);
    vec2 q = fract(p) - c;
    float a = t * (0.4 + r) + r * 6.2832;
    float ca = cos(a), sa = sin(a);
    q = vec2(ca * q.x - sa * q.y, sa * q.x + ca * q.y);
    float flip = cos(t * (1.1 + r * 1.5) + r * 20.0);
    float w = max(0.25, abs(flip));
    float size = mix(0.09, 0.16, hash12(cell + 7.7 + seed));
    q.x /= w;
    float d = length(q * vec2(1.0, 1.9)) / size;
    d += 0.35 * smoothstep(0.0, 0.25, -q.y / size) * smoothstep(0.18, 0.0, abs(q.x) / size); // notch
    float alpha = smoothstep(1.0, 0.75, d);
    return vec2(alpha, 0.75 + 0.25 * flip);
}
`;

const SOURCE = `
vec2 uv = cogl_tex_coord_in[0].xy;
vec2 suv = (uv - 0.5) / zoom + 0.5 + shift;
if (depth_on > 0.0) {
    vec2 ds = dshift * depth_on;
    float hPrev = 1.0;
    float dPrev = depthAt(suv + ds * (1.0 - focal));
    vec2 q = suv + ds * (1.0 - focal);
    if (dPrev < 1.0) {
        q = suv - ds * focal;
        for (int i = 1; i <= 20; i++) {
            float h = 1.0 - float(i) / 20.0;
            float d = depthAt(suv + ds * (h - focal));
            if (d >= h) {
                float a = hPrev - dPrev;
                float hh = mix(hPrev, h, a / max(a + d - h, 1e-4));
                q = suv + ds * (hh - focal);
                break;
            }
            hPrev = h;
            dPrev = d;
        }
    }
    suv = q;
}
vec4 col = texture2D(tex, suv);

if (glow > 0.5) {
    float m = clamp((col.r - max(col.g, col.b)) * 2.2, 0.0, 1.0);
    col.rgb += col.rgb * m * 0.10 * sin(t * 0.9) * amount;
}

if (embers > 0.5) {
    float e = emberLayer(uv, 7.0, 0.060, 1.0)
            + emberLayer(uv, 12.0, 0.085, 11.0) * 0.75
            + emberLayer(uv, 20.0, 0.11, 23.0) * 0.5;
    e *= smoothstep(-0.1, 1.0, uv.y);           // denser near the bottom, fading as they rise
    col.rgb += ember_col * e * amount * 0.9;
}

if (petals > 0.5) {
    vec2 a1 = petalLayer(uv, 4.0, 0.035, 5.0);
    vec2 a2 = petalLayer(uv, 7.0, 0.050, 17.0);
    vec2 a3 = petalLayer(uv, 12.0, 0.065, 31.0);
    col.rgb = mix(col.rgb, petal_col * a3.y * 0.75, a3.x * 0.55 * amount);
    col.rgb = mix(col.rgb, petal_col * a2.y * 0.88, a2.x * 0.75 * amount);
    col.rgb = mix(col.rgb, petal_col * a1.y, a1.x * 0.9 * amount);
}

cogl_color_out = vec4(clamp(col.rgb, 0.0, 1.0), col.a) * cogl_color_in.a;
`;

export const LiveEffect = GObject.registerClass(
class BapirloLiveEffect extends Clutter.ShaderEffect {
    // depth map (PNG path or null): uploaded once, attached as layer 1 of whatever pipeline the
    // offscreen effect currently paints with (create_pipeline isn't reachable from JS)
    setDepth(path) {
        this._depth = null;
        this._pipeline = null;
        this.depthAspect = 0;
        if (path) {
            try {
                const pb = GdkPixbuf.Pixbuf.new_from_file(path);
                const ctx = global.stage.context.get_backend().get_cogl_context();
                this._depth = Cogl.Texture2D.new_from_data(ctx, pb.width, pb.height,
                    pb.has_alpha ? Cogl.PixelFormat.RGBA_8888 : Cogl.PixelFormat.RGB_888, pb.rowstride, pb.get_pixels());
                this.depthAspect = pb.width / pb.height;
            } catch (e) {
                console.warn(`bapirlo-live: depth map ${path}: ${e.message}`);
            }
        }
        this.queue_repaint();
        return !!this._depth;
    }

    vfunc_paint_target(node, paintContext) {
        const p = this.get_pipeline();
        if (p && this._depth && p !== this._pipeline) {
            this._pipeline = p;
            p.set_layer_texture(1, this._depth);
            p.set_layer_combine(1, 'RGBA = REPLACE(PREVIOUS)');
        }
        super.vfunc_paint_target(node, paintContext);
    }

    vfunc_get_static_snippet() {
        return Cogl.Snippet.new(Cogl.SnippetHook.FRAGMENT, DECLARATIONS, SOURCE);
    }

    // u: {t, aspect, amount, density, embers, petals, glow, zoom, shift:[x,y], emberCol:[r,g,b], petalCol:[r,g,b],
    //     depthOn, dscale:[x,y], dshift:[x,y], focal}
    update(u) {
        this.set_uniform_value('tex', 0);
        this.set_uniform_value('depth_tex', 1);
        this.set_uniform_float('depth_on', 1, [this._depth ? u.depthOn : 0]);
        this.set_uniform_float('focal', 1, [u.focal]);
        this.set_uniform_float('dscale', 2, u.dscale);
        this.set_uniform_float('dshift', 2, u.dshift);
        for (const k of ['t', 'aspect', 'amount', 'density', 'embers', 'petals', 'glow', 'zoom'])
            this.set_uniform_float(k, 1, [u[k]]);
        this.set_uniform_float('shift', 2, u.shift);
        this.set_uniform_float('ember_col', 3, u.emberCol);
        this.set_uniform_float('petal_col', 3, u.petalCol);
        this.queue_repaint();
    }
});
