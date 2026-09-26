// InkContour
// A tiny real-time "vectorizer" for ink outlines.
//
// The stair-steps in old comic scans are the outline's true (smooth) path
// quantized to the scan's pixel grid. Blurring the brightness recovers that
// smooth path: the half-way level of a blurred step follows the averaged
// line, not the individual steps (the same idea as a level-set / contour
// trace in a vectorizer). This effect finds that half-way contour and
// redraws the edge on it as a fresh, narrow transition between the nearby
// ink colour and the nearby fill colour.
//
// Detail protection (scale selection): strong smoothing merges shapes that
// sit close together - fine hatching, rocky texture, hair strands. Where
// that would happen, the strong blur flattens the local contrast, so each
// pixel checks how much contrast survives each blur and falls back to the
// gentle blur, or to the original pixels, wherever it doesn't. Long clean
// outlines keep the full smoothing.
//
// Output is always a blend of two colours already present right next to
// the pixel, so it cannot overshoot into halos. It only acts where there is
// dark ink next to a clearly brighter area; flat colour, colour-to-colour
// boundaries and soft shading pass through untouched.
//
// Intended to run after the first NNEDI3 2x (at 2x resolution), where
// source stair-steps are ~2px tall.


//!MAGPIE EFFECT
//!VERSION 4


//!PARAMETER
//!LABEL Contour Smoothing (px)
//!DEFAULT 3.0
//!MIN 0.5
//!MAX 4
//!STEP 0.1
// Gaussian sigma of the strong blur used on clean outlines. Larger =
// rounder, smoother lines.
float sigma;

//!PARAMETER
//!LABEL Fine Detail Smoothing (px)
//!DEFAULT 1.2
//!MIN 0.5
//!MAX 4
//!STEP 0.1
// Gaussian sigma of the gentle blur used where the strong one would merge
// nearby shapes.
float sigmaFine;

//!PARAMETER
//!LABEL Detail Protection
//!DEFAULT 0.8
//!MIN 0
//!MAX 1
//!STEP 0.01
// Share of an edge's contrast that must survive a blur for that blur to be
// used there. Higher = protects more detail (less smoothing in busy areas).
// 0 = no protection (always the strong blur).
float keepContrast;

//!PARAMETER
//!LABEL Edge Width (px)
//!DEFAULT 3.0
//!MIN 0.5
//!MAX 12
//!STEP 0.1
// Width of the redrawn ink-to-colour transition. Smaller = crisper, but
// below ~3px (at 2x) the final 1080p image can't place edges smoothly.
float edgeWidth;

//!PARAMETER
//!LABEL Ink Darken
//!DEFAULT 0.8
//!MIN 0
//!MAX 1
//!STEP 0.01
// 0 = keep the ink colour found nearby, 1 = pure black ink.
float inkDarken;

//!PARAMETER
//!LABEL Ink Darken Reach
//!DEFAULT 0.2
//!MIN 0.01
//!MAX 1
//!STEP 0.01
// How far from pure ink towards the fill colour the darkening still
// applies (0-1 of the ink-to-fill step). Small = only solid ink gets
// darker, so shading and thin gaps between lines keep their tone.
float inkOnly;

//!PARAMETER
//!LABEL Ink Max Luma
//!DEFAULT 0.22
//!MIN 0.02
//!MAX 0.6
//!STEP 0.01
// Only edges whose darkest nearby pixel is at most this bright count as ink.
float inkMaxLuma;

//!PARAMETER
//!LABEL Min Edge Contrast
//!DEFAULT 0.3
//!MIN 0.05
//!MAX 0.9
//!STEP 0.01
// Only edges with at least this much brightness difference are redrawn.
float minContrast;

//!PARAMETER
//!LABEL Line Weight
//!DEFAULT 1.0
//!MIN 0.5
//!MAX 1.0
//!STEP 0.01
// Scales every ink line's width by this factor, each in proportion to its
// own width, so fine lines and outlines keep the same ratio to each other
// (0.8 = every line 20% thinner). Solid black areas only lose a thin rim.
// 1 = off.
float lineWeight;

//!PARAMETER
//!LABEL Round-7 Look
//!DEFAULT 0
//!MIN 0
//!MAX 1
//!STEP 1
// 1 = redraw edges the way the round-7 test versions did: ink and fill
// colours picked from the most extreme nearby pixels, and darkening
// reaching halfway into the ink-to-fill transition. Kept so those
// captures can be seen live exactly as tested.
int legacyLook;

//!PARAMETER
//!LABEL Max Edge Shift (px)
//!DEFAULT 12
//!MIN 0
//!MAX 12
//!STEP 0.05
// How far the strong smoothing may move an edge away from where the
// gently smoothed (nearly original) edge is. Straightening stair-steps
// needs well under a pixel; small curved features (mouth and eyelid lines,
// hair tips) move further, so a small limit keeps them where the artist
// drew them. 12 = no limit.
float maxShift;

//!PARAMETER
//!LABEL Redraw Fine Features
//!DEFAULT 1
//!MIN 0
//!MAX 1
//!STEP 0.01
// Where the strong smoothing would merge or reshape things (faces, small
// strokes, lettering, dense texture): 1 = redraw them with the gentle
// smoothing, 0 = leave those pixels exactly as they came in, so small
// features keep the shape the artist drew. Long clean outlines are
// redrawn either way.
float fineRedraw;

//!PARAMETER
//!LABEL Curve Protection Radius (px)
//!DEFAULT 0
//!MIN 0
//!MAX 20
//!STEP 0.5
// Where the smoothed outline bends tighter than this radius - mouth and
// eyelid lines, stroke ends, hair tips, lettering - the original pixels
// are kept, so small features keep their exact shape. Stair-steps sit on
// long, gently curving outlines, which are still smoothed. 0 = off.
float curveRadius;

//!TEXTURE
Texture2D INPUT;

//!TEXTURE
//!WIDTH INPUT_WIDTH
//!HEIGHT INPUT_HEIGHT
Texture2D OUTPUT;

//!TEXTURE
//!WIDTH INPUT_WIDTH
//!HEIGHT INPUT_HEIGHT
//!FORMAT R16G16B16A16_FLOAT
Texture2D TMP;

//!TEXTURE
//!WIDTH INPUT_WIDTH
//!HEIGHT INPUT_HEIGHT
//!FORMAT R16G16B16A16_FLOAT
Texture2D STATS;

//!TEXTURE
//!WIDTH INPUT_WIDTH
//!HEIGHT INPUT_HEIGHT
//!FORMAT R16G16B16A16_FLOAT
Texture2D RANGE;

//!SAMPLER
//!FILTER POINT
SamplerState sam;

//!SAMPLER
//!FILTER LINEAR
SamplerState samL;


//!COMMON

// Blur reach is capped so the loops have a fixed upper bound.
#define MAX_R 10
// Min/max window radius: must reach both the ink core and the fill beside
// an edge pixel.
#define MM_R 4
// Colour-picking window radius (finds the ink and fill colours to redraw with).
#define COL_R 3

float Luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

// Radius over which a blurred step settles to (nearly) its full height,
// used when measuring how much contrast each blur keeps.
int RangeR(float s) { return min(MAX_R, (int)ceil(s * 2.0)); }


//!PASS 1
//!DESC Horizontal: both blurs + min/max
//!STYLE PS
//!IN INPUT
//!OUT TMP

float4 Pass1(float2 pos) {
	const float2 pt = GetInputPt();
	const int r = min(MAX_R, (int)ceil(max(sigma, sigmaFine) * 2.5));
	const float k = -0.5 / (sigma * sigma), kf = -0.5 / (sigmaFine * sigmaFine);
	float sum = 0, wsum = 0, sumF = 0, wsumF = 0, mn = 1e6, mx = -1e6;
	[loop]
	for (int i = -r; i <= r; ++i) {
		float l = Luma(INPUT.SampleLevel(sam, pos + float2(i * pt.x, 0), 0).rgb);
		float w = exp(k * i * i), wf = exp(kf * i * i);
		sum += w * l; wsum += w;
		sumF += wf * l; wsumF += wf;
		if (abs(i) <= MM_R) { mn = min(mn, l); mx = max(mx, l); }
	}
	return float4(sum / wsum, sumF / wsumF, mn, mx);
}


//!PASS 2
//!DESC Vertical: both blurs + min/max
//!STYLE PS
//!IN TMP
//!OUT STATS

float4 Pass2(float2 pos) {
	const float2 pt = GetInputPt();
	const int r = min(MAX_R, (int)ceil(max(sigma, sigmaFine) * 2.5));
	const float k = -0.5 / (sigma * sigma), kf = -0.5 / (sigmaFine * sigmaFine);
	float sum = 0, wsum = 0, sumF = 0, wsumF = 0, mn = 1e6, mx = -1e6;
	[loop]
	for (int i = -r; i <= r; ++i) {
		float4 s = TMP.SampleLevel(sam, pos + float2(0, i * pt.y), 0);
		float w = exp(k * i * i), wf = exp(kf * i * i);
		sum += w * s.x; wsum += w;
		sumF += wf * s.y; wsumF += wf;
		if (abs(i) <= MM_R) { mn = min(mn, s.z); mx = max(mx, s.w); }
	}
	return float4(sum / wsum, sumF / wsumF, mn, mx);
}


//!PASS 3
//!DESC Horizontal: blurred min/max
//!STYLE PS
//!IN STATS
//!OUT TMP

float4 Pass3(float2 pos) {
	const float2 pt = GetInputPt();
	const int r = RangeR(sigma), rf = RangeR(sigmaFine);
	float mnB = 1e6, mxB = -1e6, mnF = 1e6, mxF = -1e6;
	[loop]
	for (int i = -r; i <= r; ++i) {
		float2 s = STATS.SampleLevel(sam, pos + float2(i * pt.x, 0), 0).xy;
		mnB = min(mnB, s.x); mxB = max(mxB, s.x);
		if (abs(i) <= rf) { mnF = min(mnF, s.y); mxF = max(mxF, s.y); }
	}
	return float4(mnB, mxB, mnF, mxF);
}


//!PASS 4
//!DESC Vertical: blurred min/max
//!STYLE PS
//!IN TMP
//!OUT RANGE

float4 Pass4(float2 pos) {
	const float2 pt = GetInputPt();
	const int r = RangeR(sigma), rf = RangeR(sigmaFine);
	float mnB = 1e6, mxB = -1e6, mnF = 1e6, mxF = -1e6;
	[loop]
	for (int i = -r; i <= r; ++i) {
		float4 s = TMP.SampleLevel(sam, pos + float2(0, i * pt.y), 0);
		mnB = min(mnB, s.x); mxB = max(mxB, s.y);
		if (abs(i) <= rf) { mnF = min(mnF, s.z); mxF = max(mxF, s.w); }
	}
	return float4(mnB, mxB, mnF, mxF);
}


//!PASS 5
//!DESC Redraw ink edges on the smoothed contour
//!STYLE PS
//!IN INPUT, STATS, RANGE
//!OUT OUTPUT

// How far the ink continues from p in direction d (d = half a pixel per
// step), in pixels, up to 16px.
float InkRun(float2 p, float2 d, float mid) {
	[loop]
	for (int i = 1; i <= 32; ++i) {
		if (Luma(INPUT.SampleLevel(samL, p + d * i, 0).rgb) > mid) {
			return i * 0.5 - 0.25;
		}
	}
	return 16;
}

// Width of the ink stroke through p: the narrowest of four directions,
// which is within 8% of the width straight across the stroke.
float StrokeWidth(float2 p, float2 pt, float mid) {
	const float2 dirs[4] = { float2(1, 0), float2(0, 1), float2(0.7071, 0.7071), float2(0.7071, -0.7071) };
	float w = 32;
	[unroll]
	for (int k = 0; k < 4; ++k) {
		float2 d = dirs[k] * pt * 0.5;
		w = min(w, InkRun(p, d, mid) + InkRun(p, -d, mid));
	}
	return w;
}

float4 Pass5(float2 pos) {
	const float2 pt = GetInputPt();
	const float3 c = INPUT.SampleLevel(sam, pos, 0).rgb;
	const float2 blur = STATS.SampleLevel(sam, pos, 0).xy;

	// Smooth the local ink/fill levels too: a raw min/max jumps whenever a
	// single noisy pixel enters or leaves the window, which would wiggle the
	// half-way level - and with it the redrawn outline - back into steps.
	float mn = 0, mx = 0, lw = 0;
	[unroll]
	for (int sy = -2; sy <= 2; ++sy) {
		[unroll]
		for (int sx = -2; sx <= 2; ++sx) {
			float w = exp(-0.25 * (sx * sx + sy * sy));
			float2 mm = STATS.SampleLevel(sam, pos + float2(sx, sy) * pt, 0).zw;
			mn += w * mm.x; mx += w * mm.y; lw += w;
		}
	}
	mn /= lw; mx /= lw;
	const float contrast = mx - mn;

	// Is this pixel near an ink outline? (dark ink AND a clearly brighter side)
	float e = smoothstep(minContrast, minContrast + 0.12, contrast)
	        * (1 - smoothstep(inkMaxLuma, inkMaxLuma + 0.08, mn));
	[branch]
	if (e <= 0) {
		return float4(c, 1);
	}

	const float mid = 0.5 * (mn + mx);

	// How much of the edge's contrast survives each blur here. An isolated
	// outline keeps nearly all of it; shapes packed closer than the blur
	// lose it, which is exactly where that blur would merge them.
	const float4 rg = RANGE.SampleLevel(sam, pos, 0);
	const float keepS = (rg.y - rg.x) / contrast;
	const float keepF = (rg.w - rg.z) / contrast;
	const float useStrong = smoothstep(keepContrast - 0.15, keepContrast, keepS);
	const float useFine = smoothstep(keepContrast - 0.15, keepContrast, keepF);

	// Where along the edge this pixel falls on each smoothed contour.
	// A step of height `contrast` blurred by s has slope
	// contrast / (s * sqrt(2*pi)) at its middle, so this maps the blurred
	// brightness to a transition that is edgeWidth pixels wide.
	// Line weight: move each edge into its stroke by the same fraction of
	// that stroke's own width, so every line thins in proportion and fine
	// lines keep their ratio to outlines. Measured on the stroke itself (a
	// pixel outside the ink first steps across the edge into it). Strokes
	// wider than 16px are solid black areas: capped, so they lose only a rim.
	float thin = 0;
	[branch]
	if (lineWeight < 0.999) {
		float2 p = pos;
		bool found = Luma(c) <= mid;
		[branch]
		if (!found) {
			float2 g = float2(STATS.SampleLevel(sam, pos + float2(pt.x, 0), 0).x - STATS.SampleLevel(sam, pos - float2(pt.x, 0), 0).x,
			                  STATS.SampleLevel(sam, pos + float2(0, pt.y), 0).x - STATS.SampleLevel(sam, pos - float2(0, pt.y), 0).x);
			float2 d = -normalize(g + 1e-6) * pt * 0.5;
			[loop]
			for (int i = 1; i <= 10 && !found; ++i) {
				if (Luma(INPUT.SampleLevel(samL, pos + d * i, 0).rgb) <= mid) {
					p = pos + d * (i + 1);
					found = true;
				}
			}
		}
		if (found) {
			thin = (1 - lineWeight) * 0.5 * min(StrokeWidth(p, pt, mid), 16);
		}
	}

	// Distance of this pixel from each smoothed edge, in pixels (positive =
	// fill side), turned into how far across the edgeWidth-wide transition
	// it sits.
	float sS = (blur.x - mid) * (2.5066 * sigma) / contrast;
	float sF = (blur.y - mid) * (2.5066 * sigmaFine) / contrast;
	sS = clamp(sS, sF - maxShift, sF + maxShift);
	float aS = saturate(0.5 + (sS + thin) / edgeWidth);
	float aF = saturate(0.5 + (sF + thin) / edgeWidth);
	float a = smoothstep(0, 1, lerp(aF, aS, useStrong));

	// Pick the ink colour and the fill colour from the neighbourhood.
	float3 darkSum = 0, lightSum = 0;
	float darkW = 0, lightW = 0;
	[unroll]
	for (int y = -COL_R; y <= COL_R; ++y) {
		[unroll]
		for (int x = -COL_R; x <= COL_R; ++x) {
			float3 s = INPUT.SampleLevel(sam, pos + float2(x, y) * pt, 0).rgb;
			float t = saturate((Luma(s) - mn) / max(contrast, 1e-4));
			// Average the typical ink and typical fill, not the extremes:
			// the brightest pixels beside an ink edge are usually the
			// source JPEG's light ringing, and repainting with them would
			// draw a halo along every redrawn edge.
			float wd = legacyLook ? pow(1 - t, 8) : 1 - smoothstep(0.2, 0.4, t);
			float wl = legacyLook ? pow(t, 8) : smoothstep(0.6, 0.8, t);
			darkSum += wd * s; darkW += wd;
			lightSum += wl * s; lightW += wl;
		}
	}
	float3 inkC = darkW > 1e-4 ? darkSum / darkW : c;
	float3 fillC = lightW > 1e-4 ? lightSum / lightW : c;

	// Where even the gentle blur would merge shapes, leave the pixels as
	// they were - but still deepen the ink, so dense areas match the rest.
	// Only pixels that already are ink get darker. Half-dark pixels (shading,
	// the thin light gaps between close lines) are left alone, otherwise
	// neighbouring shapes merge into solid black.
	float t0 = saturate((Luma(c) - mn) / max(contrast, 1e-4));
	float3 original = c * lerp(1 - inkDarken, 1, smoothstep(0.0, inkOnly, t0));
	float3 inkDeep = inkC * (1 - inkDarken);

	// In the redrawn edge, darken only the ink end of the transition too.
	float3 redrawn = lerp(lerp(inkDeep, inkC, smoothstep(0.0, inkOnly, a)), fillC, a);
	if (legacyLook) {
		original = c * lerp(1 - inkDarken, 1, smoothstep(0.0, 0.5, t0));
		redrawn = lerp(inkDeep, fillC, a);
	}
	// Curve protection: radius of curvature of the smoothed outline through
	// this pixel (from the strongly blurred brightness, whose level lines
	// follow the outlines without the stair-steps). Tight bends = small
	// features and stroke ends: keep the original pixels there.
	float curveOK = 1;
	[branch]
	if (curveRadius > 0) {
		float b00 = STATS.SampleLevel(sam, pos + float2(-pt.x, -pt.y), 0).x, b10 = STATS.SampleLevel(sam, pos + float2(0, -pt.y), 0).x;
		float b20 = STATS.SampleLevel(sam, pos + float2(pt.x, -pt.y), 0).x, b01 = STATS.SampleLevel(sam, pos + float2(-pt.x, 0), 0).x;
		float b21 = STATS.SampleLevel(sam, pos + float2(pt.x, 0), 0).x, b02 = STATS.SampleLevel(sam, pos + float2(-pt.x, pt.y), 0).x;
		float b12 = STATS.SampleLevel(sam, pos + float2(0, pt.y), 0).x, b22 = STATS.SampleLevel(sam, pos + float2(pt.x, pt.y), 0).x;
		float bx = 0.5 * (b21 - b01), by = 0.5 * (b12 - b10);
		float bxx = b21 - 2 * blur.x + b01, byy = b12 - 2 * blur.x + b10;
		float bxy = 0.25 * (b22 - b20 - b02 + b00);
		float g2 = bx * bx + by * by;
		float k = abs(bxx * by * by - 2 * bxy * bx * by + byy * bx * bx) / max(g2 * sqrt(g2), 1e-9);
		float r = 1 / max(k, 1e-4);
		curveOK = smoothstep(0.6 * curveRadius, 1.2 * curveRadius, r);
	}

	float3 result = lerp(original, redrawn, lerp(useStrong, max(useStrong, useFine), fineRedraw) * curveOK);
	return float4(lerp(c, result, e), 1);
}
