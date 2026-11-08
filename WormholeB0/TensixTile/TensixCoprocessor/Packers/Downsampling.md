# Downsampling

Downsampling functionality can be used to pack a non-contiguous range of input datums. Setting `Downsample_mask` to anything other than `0` is `UnsupportedFunctionality`. The functionality is enabled by setting `Downsample_mask` to a value _other_ than `0` or `0xffff`, at which point a vector-compress operation (in the style of RISC-V Vector `vcompress.vm` or AVX512 `vpcompressd`) is performed on each group of 16 input datums. To downsample more aggressively than 16:1, or to downsample with a repeating pattern length other than 2/4/8/16 datums, then multiple consecutive pack instructions need to be used (and the output not flushed between packs).

## Functional model

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
uint16_t mask = CurrentPacker.Config[StateID].Downsample_mask;
if (mask != 0) UnsupportedFunctionality(); // No known usage
if (mask == 0) mask = 0xffff;
for (unsigned i = 0; i < CurrentPacker.InputNumDatums; ++i) {
  auto Datum = CurrentPacker.FetchInputDatum(CurrentPacker.InputSourceAddr + i * CurrentPacker.InputSourceStride);
  if (mask & 1) {
    CurrentPacker.ProcessInputDatum(Datum);
  } else {
    // Datum is discarded
  }
  mask = (mask << 15) | (mask >> 1); // Rotate mask right by one position
}
```
