// Ghostty Cursor Blaze Shader

float getSdfRectangle(in vec2 p, in vec2 xy, in vec2 b) {
    vec2 d = abs(p - xy) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// Distance function for a line segment, optimized for branchless execution
float seg(in vec2 p, in vec2 a, in vec2 b, inout float s, float d) {
    vec2 e = b - a;
    vec2 w = p - a;
    vec2 proj = a + e * clamp(dot(w, e) / dot(e, e), 0.0, 1.0);
    float segd = dot(p - proj, p - proj);
    d = min(d, segd);

    float c0 = step(0.0, p.y - a.y);
    float c1 = 1.0 - step(0.0, p.y - b.y);
    float c2 = 1.0 - step(0.0, e.x * w.y - e.y * w.x);

    float allCond = c0 * c1 * c2;
    float noneCond = (1.0 - c0) * (1.0 - c1) * (1.0 - c2);

    float flip = mix(1.0, -1.0, step(0.5, allCond + noneCond));
    s *= flip;

    return d;
}

float getSdfParallelogram(in vec2 p, in vec2 v0, in vec2 v1, in vec2 v2, in vec2 v3) {
    float s = 1.0;
    float d = dot(p - v0, p - v0);

    d = seg(p, v0, v3, s, d);
    d = seg(p, v1, v0, s, d);
    d = seg(p, v2, v1, s, d);
    d = seg(p, v3, v2, s, d);

    return s * sqrt(d);
}

// Normalizes coordinates to a -1 to 1 space
vec2 norm(vec2 value, float isPosition) {
    return (value * 2.0 - (iResolution.xy * isPosition)) / iResolution.y;
}

float antialiasing(float distance) {
    return 1.0 - smoothstep(0.0, norm(vec2(2.0, 2.0), 0.0).x, distance);
}

float determineStartVertexFactor(vec2 c, vec2 p) {
    float condition1 = step(p.x, c.x) * step(c.y, p.y); // c.x <= p.x && c.y >= p.y
    float condition2 = step(c.x, p.x) * step(p.y, c.y); // c.x >= p.x && c.y <= p.y
    return 1.0 - max(condition1, condition2);
}

float isLess(float c, float p) {
    return 1.0 - step(p, c);
}

vec2 getRectangleCenter(vec4 rectangle) {
    return vec2(rectangle.x + (rectangle.z / 2.0), rectangle.y - (rectangle.w / 2.0));
}

float ease(float x) {
    return pow(1.0 - x, 3.0);
}

// Colors and timing
const vec4 TRAIL_COLOR = vec4(0.20, 0.90, 0.65, 1.0);        // Minty green-blue
const vec4 TRAIL_COLOR_ACCENT = vec4(0.40, 1.0, 0.80, 1.0);  // Bright mint accent
const float DURATION = 0.45;

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // 1. Render the base terminal texture
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);

    // 2. Focus Check: Exit early if the window is unfocused.
    // This stops the stuck glow on unfocused terminals or during resize.
    if (iFocus == 0) {
        return;
    }

    // Normalization for fragCoord to a space of -1 to 1
    vec2 vu = norm(fragCoord, 1.0);
    vec2 offsetFactor = vec2(-0.5, 0.5);

    // Normalization for cursor position (xy) and size (zw)
    vec4 currentCursor = vec4(norm(iCurrentCursor.xy, 1.0), norm(iCurrentCursor.zw, 0.0));
    vec4 previousCursor = vec4(norm(iPreviousCursor.xy, 1.0), norm(iPreviousCursor.zw, 0.0));

    vec2 centerCC = getRectangleCenter(currentCursor);
    vec2 centerCP = getRectangleCenter(previousCursor);

    // Determine parallelogram vertices for the trail
    float vertexFactor = determineStartVertexFactor(currentCursor.xy, previousCursor.xy);
    float invertedVertexFactor = 1.0 - vertexFactor;

    float xFactor = isLess(previousCursor.x, currentCursor.x);
    float yFactor = isLess(currentCursor.y, previousCursor.y);

    vec2 v0 = vec2(currentCursor.x + currentCursor.z * vertexFactor, currentCursor.y - currentCursor.w);
    vec2 v1 = vec2(currentCursor.x + currentCursor.z * xFactor, currentCursor.y - currentCursor.w * yFactor);
    vec2 v2 = vec2(currentCursor.x + currentCursor.z * invertedVertexFactor, currentCursor.y);
    vec2 v3 = centerCP;

    // Calculate Signed Distance Fields
    float sdfCurrentCursor = getSdfRectangle(vu, currentCursor.xy - (currentCursor.zw * offsetFactor), currentCursor.zw * 0.5);
    float sdfTrail = getSdfParallelogram(vu, v0, v1, v2, v3);

    // Calculate animations
    float progress = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    float easedProgress = ease(progress);
    float lineLength = distance(centerCC, centerCP);

    // Compositing the trail and cursor blaze
    float modTrail = 0.007;

    // Trail blaze
    vec4 trail = mix(TRAIL_COLOR_ACCENT, fragColor, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 0.007));
    trail = mix(TRAIL_COLOR, trail, 1.0 - smoothstep(0.0, sdfTrail + modTrail, 0.006));
    trail = mix(trail, TRAIL_COLOR, step(sdfTrail + modTrail, 0.0));

    // Cursor blaze
    trail = mix(TRAIL_COLOR_ACCENT, trail, 1.0 - smoothstep(0.0, sdfCurrentCursor + 0.002, 0.004));
    trail = mix(TRAIL_COLOR, trail, 1.0 - smoothstep(0.0, sdfCurrentCursor + 0.002, 0.004));

    // Final composite onto base terminal texture
    fragColor = mix(trail, fragColor, 1.0 - smoothstep(0.0, sdfCurrentCursor, easedProgress * lineLength));
}
