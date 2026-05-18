# Format Conversion

The available unpacker format conversions vary slightly based on whether unpacking to [`SrcA` or `SrcB`](../SrcASrcB.md) or unpacking to [`Dst`](../Dst.md):

<table><thead><tr><th>L1 data type</th><th>→</th><th><a href="../SrcASrcB.md#data-types"><code>SrcA</code> data type</a></th><th><a href="../SrcASrcB.md#data-types"><code>SrcB</code> data type</a></th><th><a href="../Dst.md#data-types"><code>Dst</code> data type</a></th></tr></thead>
<tr><td>FP32 or TF32</td><td>→</td><td colspan="2">TF32 or BF16 or FP16</td><td>FP32 or BF16 or FP16</td></tr>
<tr><td>BF16</td><td>→</td><td colspan="2">TF32 or BF16</td><td>BF16</td></tr>
<tr><td><a href="../FloatBitPatterns.md#bfp">BFP8 or BFP4 or BFP2</a> (†) or INT8 (sign-magnitude)</td><td>→</td><td colspan="2">TF32 or BF16</td><td>BF16</td></tr>
<tr><td><a href="../FloatBitPatterns.md#bfp">BFP8a or BFP4a or BFP2a</a> (†)</td><td>→</td><td colspan="3">FP16</td></tr>
<tr><td>FP16 or FP8 (e5m2) (‡)</td><td>→</td><td colspan="3">FP16</td></tr>
<tr><td>INT32 (sign-magnitude)</td><td>→</td><td colspan="2">Not possible</td><td>Integer "32"</td></tr>
<tr><td>INT16 (opaque data)</td><td>→</td><td colspan="3">Integer "16" (opaque data)</td></tr>
<tr><td>INT8 (sign-magnitude)</td><td>→</td><td colspan="3">Integer "8" (in range ±127)</td></tr>
<tr><td>UINT8 (unsigned)</td><td>→</td><td colspan="3">Integer "8" (in range 0 - 255)</td></tr>
</table>

> (†) Each datum is either 8 or 4 or 2 bits in L1. Exponents usually come from a separate array in L1 containing one exponent value per 16 datums, though the unpack instruction can instead opt to provide a fixed exponent for all datums.
>
> (‡) Like IEEE754 for normal values, but different bit pattern for infinity, and no bit patterns meaning NaN. See [FP16 bit patterns](../FloatBitPatterns.md#fp16) for details.

## Configuring the conversion

The below table shows how to configure the conversion when unpacking to [`SrcA` or `SrcB`](../SrcASrcB.md): `F`→`G` means that `InDataFormat` should be set to `F` and `OutDataFormat` should be set to `G`, whereas just `F` means that both of `InDataFormat` and `OutDataFormat` should be set to `F`:

||To TF32|To BF16|To FP16|To Integer "16"|To Integer "8"|
|:-:|:-:|:-:|:-:|:-:|:-:|
|**From FP32**|`FP32`→`TF32`|`FP32`→`BF16`|`FP32`→`FP16`|❌|❌|
|**From TF32**|`FP32`→`TF32`|`FP32`→`BF16`|`FP32`→`FP16`|❌|❌|
|**From BF16**|`BF16`|`BF16`|❌|❌|❌|
|**From BFP8**|`BFP8`|`BFP8`|❌|❌|❌|
|**From BFP4**|`BFP4`|`BFP4`|❌|❌|❌|
|**From BFP2**|`BFP2`|`BFP2`|❌|❌|❌|
|**From FP16**|❌|❌|`FP16`|❌|❌|
|**From BFP8a**|❌|❌|`BFP8a`|❌|❌|
|**From BFP4a**|❌|❌|`BFP4a`|❌|❌|
|**From BFP2a**|❌|❌|`BFP2a`|❌|❌|
|**From FP8**|❌|❌|`FP8`|❌|❌|
|**From INT16**|❌|❌|❌|`INT16`|❌|
|**From INT8**|`BFP8` (†)|`BFP8` (†)|❌|❌|`INT8` (‡)|
|**From UINT8**|❌|❌|❌|❌|`INT8` (‡)|

The below table shows the same, but for when unpacking to [`Dst`](../Dst.md):

||To FP32|To BF16|To FP16|To Integer "32"|To Integer "16"|To Integer "8"|
|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
|**From FP32**|`FP32`|`FP32`→`BF16`|`FP32`→`FP16`|❌|❌|❌|
|**From TF32**|`FP32`|`FP32`→`BF16`|`FP32`→`FP16`|❌|❌|❌|
|**From BF16**|❌|`BF16`|❌|❌|❌|❌|
|**From BFP8**|❌|`BFP8`|❌|❌|❌|❌|
|**From BFP4**|❌|`BFP4`|❌|❌|❌|❌|
|**From BFP2**|❌|`BFP2`|❌|❌|❌|❌|
|**From FP16**|❌|❌|`FP16`|❌|❌|❌|
|**From BFP8a**|❌|❌|`BFP8a`|❌|❌|❌|
|**From BFP4a**|❌|❌|`BFP4a`|❌|❌|❌|
|**From BFP2a**|❌|❌|`BFP2a`|❌|❌|❌|
|**From FP8**|❌|❌|`FP8`|❌|❌|❌|
|**From INT32**|❌|❌|❌|`INT32`|❌|❌|
|**From INT16**|❌|❌|❌|❌|`INT16`|❌|
|**From INT8**|❌|`BFP8` (†)|❌|❌|❌|`INT8` (‡)|
|**From UINT8**|❌|❌|❌|❌|❌|`INT8` (‡)|

> (†) The `REG2_Force_shared_exp` configuration field needs to be set, and then a fixed exponent is supplied via the `FORCED_SHARED_EXP_shared_exp` configuration field.
>
> (‡) Additional `ALU_FORMAT_SPEC_REG0_SrcAUnsigned` or `ALU_FORMAT_SPEC_REG0_SrcBUnsigned` configuration required to specify type. Unlike other configuration registers which influence the behavior of unpack instructions, these `Src?Unsigned` configuration registers need to be held constant for the entire duration of the unpack operation.

The exact location of `InDataFormat` and `OutDataFormat` varies based on how the [`UNPACR`](../UNPACR_Regular.md) instruction was configured and invoked. Full details can be found within [`UNPACR`'s functional model](../UNPACR_Regular.md#functional-model); the abridged summary is:

||Unpacking to `SrcA` or `Dst` (`i < 8`)|Unpacking to `SrcB` (`i < 2`)|
|---|---|---|
|**`InDataFormat`**|`THCON_SEC0.TileDescriptor.InDataFormat`&nbsp;or<br/>`THCON_SEC0.Unpack_data_format_cntx[i]`|`THCON_SEC1.TileDescriptor.InDataFormat`&nbsp;or<br/>`THCON_SEC1.Unpack_data_format_cntx[i]`|
|**`OutDataFormat`**|`THCON_SEC0.REG2_Out_data_format`&nbsp;or<br/>`THCON_SEC0.Unpack_out_data_format_cntx[i]`|`THCON_SEC1.REG2_Out_data_format`&nbsp;or<br/>`THCON_SEC1.Unpack_out_data_format_cntx[i]`|

The encoding of type names in these two fields is:

||`0b??11`|`0b??10`|`0b??01`|`0b??00`|
|---|---|---|---|---|
|**`0b00??`**|`BFP4a`|`BFP8a`|`FP16`|`FP32`|
|**`0b01??`**|`BFP4`|`BFP8`|`BF16`|`TF32`|
|**`0b10??`**|`BFP2a`|`FP8`|`INT16`|`INT32`|
|**`0b11??`**|`BFP2`|`INT8`|||
