// Screen-space ASCII post-process. Reads the finished 3D frame, splits it into
// fixed character cells, averages each cell's luminance, and stamps a glyph
// from a 10-step ramp (" .:-=+*#%@"). The lighting it quantises is the
// engine's real lighting; nothing here invents shade.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform vec2 cell = vec2(8.0, 16.0);
uniform int glyphs = 10;
uniform float gamma = 1.5;   // <1 lifts midtones so shaded walls still read
// the thing, in screen space: the grid is pulled toward it, slowly swirled, and
// coarsened inside thing_r, so the reading bends around it before its shape resolves
uniform vec2 thing_px = vec2(-4000.0, -4000.0);
uniform float thing_r = 1.0;
uniform float thing_on = 0.0;

void fragment() {
    vec2 screen_px = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 p = SCREEN_UV * screen_px;
    vec2 d = p - thing_px;
    float r = length(d);
    float w = thing_on * (1.0 - smoothstep(0.0, thing_r, r));
    float ang = w * w * 0.55 * sin(TIME * 0.35 + r * 0.012);
    mat2 rot = mat2(vec2(cos(ang), sin(ang)), vec2(-sin(ang), cos(ang)));
    vec2 pw = thing_px + rot * d * (1.0 - 0.30 * w * w);
    vec2 cl = cell * (1.0 + 0.7 * w);
    vec2 c = floor(pw / cl);
    vec2 f = fract(pw / cl);
    // four taps inside the cell instead of one, so edges do not flicker
    vec2 o = cl / screen_px;
    vec2 base = (c * cl) / screen_px;
    vec3 rgb = texture(screen_tex, base + o * vec2(0.25, 0.25)).rgb
             + texture(screen_tex, base + o * vec2(0.75, 0.25)).rgb
             + texture(screen_tex, base + o * vec2(0.25, 0.75)).rgb
             + texture(screen_tex, base + o * vec2(0.75, 0.75)).rgb;
    rgb *= 0.25;
    float lum = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
    lum = pow(clamp(lum, 0.0, 1.0), gamma);
    int idx = int(clamp(lum, 0.0, 0.999) * float(glyphs));
    vec2 auv = vec2((float(idx) + f.x) / float(glyphs), f.y);
    float g = texture(atlas, auv).r;
    // brighter cells get a brighter glyph as well as a denser one
    COLOR = vec4(vec3(g * mix(0.55, 1.0, lum)), 1.0);
}
