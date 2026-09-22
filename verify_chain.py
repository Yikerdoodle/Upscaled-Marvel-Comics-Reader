import json, os
c = json.load(open(r"C:/Users/Work/AppData/Local/Magpie/config/v2/config.json", encoding='utf-8'))
i = c['profiles'][0]['scalingMode']
mode = c['scalingModes'][i]
print("active:", mode['name'])
base = r"E:\ComicUpscale\Magpie\effects"
sep = chr(92)
total_scale = 1.0
for e in mode['effects']:
    rel = e['name'].replace(sep, os.sep) + '.hlsl'
    path = os.path.join(base, rel)
    ok = os.path.isfile(path)
    is_ups = e['name'] == 'Anime4K' + sep + 'Anime4K_Upscale_UL'
    if is_ups:
        total_scale *= 2
    note = " (2x)" if is_ups else ""
    print(f"  [{'OK' if ok else 'MISSING'}] {e['name']}{note}")
print()
print(f"total upscale before Magpie fits to screen: {total_scale:.0f}x")
print(f"intermediate canvas from 1920x1080 input: {int(1920*total_scale)}x{int(1080*total_scale)}")
mb = (1920*total_scale) * (1080*total_scale) * 8 / 1e6
print(f"rough VRAM per full-res fp16 buffer: ~{mb:.0f} MB (well under 4GB; lightweight HLSL")
print("shader passes, much lighter per-buffer than the ONNX APISR network that already ran fine)")
