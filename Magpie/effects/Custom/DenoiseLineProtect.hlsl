// DenoiseLineProtect
// Derived from Anime4K_Denoise_Bilateral_Mean (bloc97/Anime4K), modified to
// leave dark (ink) pixels completely untouched instead of denoising them.
//
// The original algorithm already computes `vc`, the pixel's ORIGINAL color,
// before averaging - this just blends between that original and the
// denoised result based on how dark the original pixel was, instead of
// always using the denoised value. Everything else is unchanged.


//!MAGPIE EFFECT
//!VERSION 4


//!PARAMETER
//!LABEL Strength
//!DEFAULT 0.22
//!MIN 0.01
//!MAX 5
//!STEP 0.01
float intensitySigma;

//!PARAMETER
//!LABEL Ink Luma Threshold
//!DEFAULT 0.12
//!MIN 0
//!MAX 1
//!STEP 0.01
// Original pixels with luma below this are treated as ink/line and left
// completely untouched (0% denoise). Above it, normal denoise applies.
float inkThreshold;

//!PARAMETER
//!LABEL Ink Transition Softness
//!DEFAULT 0.06
//!MIN 0.001
//!MAX 0.5
//!STEP 0.01
// Width of the smooth ramp between "fully protected" and "fully denoised",
// centered on Ink Luma Threshold. Prevents a hard seam at the cutoff.
float inkSoftness;

//!PARAMETER
//!LABEL Edge Protection Threshold
//!DEFAULT 0.18
//!MIN 0
//!MAX 1
//!STEP 0.01
// Protects BOTH sides of any strong boundary, not just dark pixels - a
// white pixel sitting right next to a black line is bright, so the ink
// check alone doesn't protect it, and the wide averaging window can pull
// some of that black line into it (visible as bleed into the white area).
// Measured as the luma range (max-min) in this pixel's immediate 3x3
// neighborhood; above this threshold, treat it as "near an edge" and
// protect it regardless of the pixel's own brightness.
float edgeThreshold;

//!PARAMETER
//!LABEL Edge Transition Softness
//!DEFAULT 0.05
//!MIN 0.001
//!MAX 0.5
//!STEP 0.01
float edgeSoftness;

//!TEXTURE
Texture2D INPUT;

//!TEXTURE
//!WIDTH INPUT_WIDTH
//!HEIGHT INPUT_HEIGHT
Texture2D OUTPUT;

//!SAMPLER
//!FILTER POINT
SamplerState sam;


//!PASS 1
//!IN INPUT
//!OUT OUTPUT
//!BLOCK_SIZE 16
//!NUM_THREADS 64

#define INTENSITY_SIGMA intensitySigma
// Widened from the original 1.0 (5x5 = 25px window). "Strength" only
// controls how TOLERANT the filter is of intensity differences within
// this window - it never controlled how FAR the window reaches. At 1.0,
// pushing Strength stopped helping once all 25 nearby pixels already
// qualified, well before Strength reached the ~0.2-0.35 range tested.
// 2.0 -> 9x9 = 81px window, a real increase in how much area gets
// averaged, independent of the Strength parameter.
#define SPATIAL_SIGMA 2.0

#define INTENSITY_POWER_CURVE 1.0

#define KERNELSIZE (max(uint(ceil(SPATIAL_SIGMA * 2.0)), 1) * 2 + 1)
#define KERNELHALFSIZE (uint(KERNELSIZE/2))
#define KERNELLEN (KERNELSIZE * KERNELSIZE)


float3 gaussian_vec(float3 x, float3 rcpS, float3 m) {
	float3 scaled = (x - m) * rcpS;
	return exp(-0.5 * scaled * scaled);
}

float gaussian(float x, float rcpS, float m) {
	float scaled = (x - m) * rcpS;
	return exp(-0.5 * scaled * scaled);
}


void Pass1(uint2 blockStart, uint3 threadId) {
	uint2 gxy = (Rmp8x8(threadId.x) << 1) + blockStart;

	const uint2 outputSize = GetOutputSize();
	if (gxy.x >= outputSize.x || gxy.y >= outputSize.y) {
		return;
	}

	float2 inputPt = GetInputPt();
	uint i, j;

	float3 src[KERNELSIZE + 1][KERNELSIZE + 1];
	[unroll]
	for (i = 0; i <= KERNELSIZE - 1; i += 2) {
		[unroll]
		for (j = 0; j <= KERNELSIZE - 1; j += 2) {
			float2 tpos = (gxy + int2(i, j) - KERNELHALFSIZE + 1) * inputPt;
			const float4 sr = INPUT.GatherRed(sam, tpos);
			const float4 sg = INPUT.GatherGreen(sam, tpos);
			const float4 sb = INPUT.GatherBlue(sam, tpos);

			src[i][j] = float3(sr.w, sg.w, sb.w);
			src[i][j + 1] = float3(sr.x, sg.x, sb.x);
			src[i + 1][j] = float3(sr.z, sg.z, sb.z);
			src[i + 1][j + 1] = float3(sr.y, sg.y, sb.y);
		}
	}

	float len[KERNELSIZE][KERNELSIZE];
	[unroll]
	for (i = 0; i < KERNELSIZE; ++i) {
		[unroll]
		for (j = 0; j < KERNELSIZE; ++j) {
			len[i][j] = length(float2((int)i - KERNELHALFSIZE, (int)j - KERNELHALFSIZE));
		}
	}

	[unroll]
	for (i = 0; i <= 1; ++i) {
		[unroll]
		for (j = 0; j <= 1; ++j) {
			uint2 destPos = gxy + uint2(i, j);

			float3 sum = 0;
			float3 n = 0;

			float3 vc = src[KERNELHALFSIZE + i][KERNELHALFSIZE + j].rgb;

			float3 rcpIs = rcp(pow(vc + 0.0001, INTENSITY_POWER_CURVE) * INTENSITY_SIGMA);
			float rcpSs = rcp(SPATIAL_SIGMA);

			[unroll]
			for (uint k = 0; k < KERNELSIZE; ++k) {
				[unroll]
				for (uint m = 0; m < KERNELSIZE; ++m) {
					float3 v = src[k + i][m + j];
					float3 d = gaussian_vec(v, rcpIs, vc) * gaussian(len[k][m], rcpSs, 0);
					sum += d * v;
					n += d;
				}
			}

			float3 denoised = sum / n;

			// Ink protection: blend back toward the ORIGINAL pixel (vc) the
			// darker it is. smoothstep gives a soft ramp instead of a hard
			// cutoff, so there's no visible seam at the threshold.
			float luma = dot(vc, float3(0.299, 0.587, 0.114));
			float darkWeight = smoothstep(inkThreshold - inkSoftness, inkThreshold + inkSoftness, luma);

			// Edge protection: look at the immediate 3x3 neighborhood (from
			// the already-gathered src[][] array, no extra texture reads)
			// and measure its luma range. A pixel sitting right next to a
			// strong boundary - light OR dark side - gets protected too,
			// so the wide averaging window can't bleed one side into the
			// other near any edge.
			float minL = 1e6, maxL = -1e6;
			[unroll]
			for (int di = -1; di <= 1; ++di) {
				[unroll]
				for (int dj = -1; dj <= 1; ++dj) {
					float3 s = src[KERNELHALFSIZE + i + di][KERNELHALFSIZE + j + dj];
					float l = dot(s, float3(0.299, 0.587, 0.114));
					minL = min(minL, l);
					maxL = max(maxL, l);
				}
			}
			float edgeStrength = maxL - minL;
			// inverted: HIGH edgeStrength (near a boundary) -> LOW weight (protect)
			float edgeWeight = 1.0 - smoothstep(edgeThreshold - edgeSoftness, edgeThreshold + edgeSoftness, edgeStrength);

			// Protect if EITHER signal says to: this pixel is dark ink, OR
			// this pixel (any brightness) sits near a strong local edge.
			float denoiseWeight = min(darkWeight, edgeWeight);
			float3 result = lerp(vc, denoised, denoiseWeight);

			OUTPUT[destPos] = float4(result, 1);
		}
	}
}
