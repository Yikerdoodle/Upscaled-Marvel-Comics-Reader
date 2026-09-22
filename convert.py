"""
Convert an ESRGAN-family .pth to ONNX in the exact shape Magpie requires.

Magpie's constraints (from the onnx-preview docs):
  - input/output tensors must be [-1, 3, -1, -1] NCHW (dynamic batch/H/W)
  - fp16 or fp32, and BOTH must be the same
  - output size must be a whole-number multiple of the input
"""
import sys, io, os, torch, onnx
# torch prints a U+2705 on success; the Windows console is cp1252 and dies on it.
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
from spandrel import ModelLoader
from onnxconverter_common import float16

SRC   = r"E:\ComicUpscale\models\2x_APISR_RRDB_GAN_generator.pth"
OUT32 = r"E:\ComicUpscale\out\2x_APISR_RRDB_fp32.onnx"
OUT16 = r"E:\ComicUpscale\out\2x_APISR_RRDB_fp16.onnx"

print("=== loading weights ===")
desc = ModelLoader().load_from_file(SRC)
arch = getattr(desc.architecture, "name", desc.architecture)
nparams = sum(p.numel() for p in desc.model.parameters())
print(f"  architecture   : {arch}")
print(f"  scale          : {desc.scale}x")
print(f"  input channels : {desc.input_channels}")
print(f"  parameters     : {nparams:,}")

if desc.scale != 2:
    sys.exit(f"ERROR: expected a 2x model, got {desc.scale}x")

model = desc.model.eval().float()
dummy = torch.randn(1, 3, 64, 64)

print("\n=== exporting fp32 ONNX ===")
torch.onnx.export(
    model, dummy, OUT32,
    input_names=["input"], output_names=["output"],
    dynamic_axes={"input":  {0: "batch", 2: "height", 3: "width"},
                  "output": {0: "batch", 2: "height", 3: "width"}},
    opset_version=17, do_constant_folding=True,
    dynamo=False,   # legacy TorchScript exporter: honours dynamic_axes exactly
)
m = onnx.load(OUT32)
onnx.checker.check_model(m)
print("  fp32 written and validated")

def shape_of(vi):
    return [d.dim_param if d.HasField("dim_param") else d.dim_value
            for d in vi.type.tensor_type.shape.dim]

print(f"  input  shape : {shape_of(m.graph.input[0])}")
print(f"  output shape : {shape_of(m.graph.output[0])}")

print("\n=== converting to fp16 (halves VRAM on your 4GB card) ===")
m16 = float16.convert_float_to_float16(m, keep_io_types=False)
onnx.save(m16, OUT16)
m16chk = onnx.load(OUT16)
onnx.checker.check_model(m16chk)

TYPES = {1: "float32", 10: "float16"}
it = m16chk.graph.input[0].type.tensor_type.elem_type
ot = m16chk.graph.output[0].type.tensor_type.elem_type
print(f"  input  dtype : {TYPES.get(it, it)}")
print(f"  output dtype : {TYPES.get(ot, ot)}")
if it != ot:
    sys.exit("ERROR: Magpie requires input and output dtypes to match")

import os
print(f"\n  fp32: {os.path.getsize(OUT32)/1e6:.1f} MB")
print(f"  fp16: {os.path.getsize(OUT16)/1e6:.1f} MB")
print("\nDONE")
