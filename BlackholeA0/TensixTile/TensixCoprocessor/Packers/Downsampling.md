# Downsampling

Downsampling packs a non-contiguous selection of the datums of each row a [`PACR`](../PACR.md) reads from `Dst`, in the style of a vector compress (RISC-V Vector `vcompress.vm`, AVX512 `vpcompressd`). It is configured per [configuration context](../PACR.md#configuration-contexts) by `THCON_SEC0_REG1_Downsample_mask` (16 bits) and `THCON_SEC0_REG1_Downsample_rate` (3 bits), and their copies in `THCON_SEC0_REG8`, `THCON_SEC1_REG1` and `THCON_SEC1_REG8` for contexts 1 to 3. Setting either to anything other than `0` is `UnsupportedFunctionality` (no known usage); the rest of this page describes what the hardware does.

Downsampling is enabled when `Downsample_mask` is neither `0` nor `0xffff`. Each row the `PACR` reads (one per enabled read interface) then keeps, of the datums in its ADC X range, those whose mask bit is set, the mask being counted from the X start: bit `j` of the mask selects the datum in column `XStart + j`, and mask bits that would select a column past the X end select nothing. The kept datums are packed densely, in column order, and everything else about the `PACR` is as usual: the rows follow one another, and the `PACR`s of a tile follow one another, with no gap. A `PACR` with `ZeroWrite` keeps its zero datums the same way. To downsample more aggressively than 16:1, or with a pattern that repeats other than every 2, 4, 8 or 16 datums, use several `PACR` instructions with different X ranges.

The kept datums alone are the tile's input: the completion of a tile's last 32-byte unit (or, for 8-bit datums, its last row), the 128-byte groups of the conversions that use them, and the datum count behind a converted tile's address change (all in [`PACR`](../PACR.md)) count only kept datums. A `PACR` with `Last` that keeps no datum at all ends a tile whose input so far is a multiple of 128 bytes (counting a datum of an 8-bit or BFP format as 2 bytes, and including a tile with no input at all) with 128 bytes' worth of zero datums (32 datums of 32 bits, or 64 of the others), in the output format; after any other input it adds nothing beyond the usual end of the tile. This is `NonContractualBehavior`: software should not issue a `PACR` with `Last` that keeps no datum.

[Edge masks](EdgeMasking.md) apply to the datums by their column in `Dst`, before the datums are dropped.

`Downsample_rate` does not change which datums are kept. When it is not `0`, each datum's edge mask bit is replaced by the `Downsample_mask` bit of its column in `Dst` (not counted from the X start): with a `Downsample_mask` of `0`, every datum of the X range is packed as a zero, and with a mask that is neither `0` nor `0xffff` and an X start other than `0`, a kept datum whose own column's mask bit is clear is packed as a zero. A nonzero `Downsample_rate` also changes how edge masks are selected and how the tile position generator steps; that is not described here, so a non-zero `Downsample_rate` should only be used where every `PCK_EDGE_OFFSET_SEC` mask that the row-set tables can select is all ones.

## Functional model

Where a `PACR` packs the datums of one row (see [`PACR`](../PACR.md) and [`EdgeMasking`](EdgeMasking.md)), with `Mask` and `Rate` from the `PACR`'s configuration context and every edge mask all ones when `Rate` is not `0`:

```c
uint16_t Mask = Ctx.Downsample_mask;
uint3_t Rate = Ctx.Downsample_rate;
bool Enabled = Mask != 0 && Mask != 0xffff;
uint16_t EdgeMask = RowEdgeMask(k);
for (unsigned X = XStart; X <= XEnd; ++X) {
  if (Enabled && !((Mask >> (X - XStart)) & 1)) continue; // Datum discarded
  bool Keep = Rate != 0 ? (Mask >> X) & 1 : (EdgeMask >> X) & 1;
  PackDatum(Keep ? ReadDst(Row, X) : 0);
}
```

## Not yet characterized

Downsampling with a BFP `Out_data_format`, with `RowPadZero`, with `ZeroWrite` and a `ReadIntfSel` of `0`, and a non-zero `Downsample_rate` with edge masks.
