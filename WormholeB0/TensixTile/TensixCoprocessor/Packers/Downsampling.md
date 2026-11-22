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

The datums are counted from the first datum of the `PACR`'s input (channel 0's X), whatever its position within its 16-byte word, and the count starts over at each `PACR`. Discarded datums are still read from `Dst`, so the tile position generator and the [edge masks](EdgeMasking.md) go on as without downsampling. Only the processed datums are the packer's input when the tile ends: its last 16-byte word is completed with zero datums as usual (see [`OutputAddressGenerator`](OutputAddressGenerator.md)).

A `PACR` with `Last` whose final 16-byte word of input from `Dst` contributes no processed datum, when the packer's input for the tile so far is a whole number of 16-byte words (or none), adds one more 16-byte word of input, every datum zero (4, 8 or 16 zero datums by the size of an `In_data_format` datum, each converted to `Out_data_format`). This is `NonContractualBehavior`: software should end a downsampled tile with a `PACR` whose last word keeps a datum.

`Downsample_rate` does not change which datums are processed. When it is not `0`, each datum's edge mask bit is replaced by the `Downsample_mask` bit of its column in `Dst`, so with a `Downsample_mask` of `0` every datum is packed as a zero. A nonzero `Downsample_rate` also changes how the tile position generator steps; that is not described here, so it should only be used where every `PCK_EDGE_OFFSET_SEC` mask that the row-set tables can select is all ones.

Downsampling with a BFP `Out_data_format` or with `ZeroWrite`, and a nonzero `Downsample_rate` with edge masks, are not yet characterized.
