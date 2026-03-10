# Format Conversion

Two data format conversions happen during the pipeline of each packer: an early conversion just after reading datums from `Dst`, and a late conversion just before writing datums to `L1`. To avoid double rounding, software should ensure that at least one conversion is an identity conversion, or ensure that both conversions are truncating. In general, the early format conversion should be used to make types narrower using rounding, and the late format conversion should be used to make types wider. To make types narrower using truncation, it is sometimes the case that either conversion could be used, in which case the early conversion should be preferred.

## Early format conversion

If fetching datums from `Dst` (as is usually the case), the early format conversion will take datums in one of the five formats supported by `Dst` and convert them to one of the supported intermediate floating-point or integer formats:

||From FP32 (e8m23)|From BF16 (e8m7)|From FP16 (e5m10)|From INT32 (e0m31)|From INT16 (e0m15)|
|:-:|---|---|---|---|---|
|**To FP32 (e8m23)**|Identity|No (keep as BF16 then use late conversion, or go via TF32)|No (keep as FP16 then use late conversion)|Bitcast|No|
|**To TF32 (e8m10)**|Rounding|Rounding (though more efficient to keep as BF16 then use late conversion)|No (keep as FP16 then use late conversion)|Bitcast to FP32 then rounding|No|
|**To BF16 (e8m7)**|Rounding or truncation|Rounding or identity|No (keep as FP16 then use late conversion)|Bitcast of top 16 bits|No|
|**To E8M6**|Rounding|Rounding|No|No|No|
|**To FP16 (e5m10)**|No (keep as FP32 then use late conversion, or round to TF32 then use late conversion)|No (keep as BF16 then use late conversion)|Rounding or identity|No|No|
|**To E5M7**|No|No|Truncation|No|No|
|**To E5M6**|No|No|Rounding|No|No|
|**To FP8 (e5m2)**|No (keep as FP32 then use late conversion)|No (keep as BF16 then use late conversion)|Truncation|No|No|
|**To INT32 (e0m31)**|Bitcast|No|No|Identity|No|
|**To INT16 (e0m15)**|No|No|No|No|Identity|
|**To INT8 (e0m7)**|Sign bit and low 7 bits of mantissa|Sign bit only, other bits zero|Sign bit only, other bits zero|Shift then round then saturate (-127 to +127), or sign bit and low 7 bits of magnitude|No|
|**To UINT8**|Low 8 bits of mantissa|No|No|Shift then round then saturate (0 to 255), or low 8 bits of magnitude|No|

Where rounding is supported, it can either be deterministic round-to-nearest with ties away from zero, or stochastic (though due to a hardware bug, stochastic rounding has a slight bias towards increasing the magnitude rather than being 50:50, and can even sometimes increase the magnitude of values which do not require rounding).

Handling of denormals and NaNs in the early format conversion depends on the nature of the early format conversion:
* **Identity / bitcast:** Denormals preserved. NaN preserved.
* **Rounding:** Denormals flushed to zero. Minus zero converted to positive zero. If the exponent is 8 bits wide, NaN becomes infinity (this is a potentially surprising behaviour).
* **Truncation:** Denormals can become zero, if that is the outcome of truncating mantissa bits. NaN can become infinity, if that is the outcome of truncating mantissa bits.

-----

If Packer 0 is fetching datums from L1 rather than from `Dst`, then the early format conversion does not happen, and the datums from L1 need to occupy a whole number of bytes:
||From 32b in L1|From 16b in L1|From 8b in L1|
|:-:|---|---|---|
|**To FP32 (e8m23)**|Identity|No|No|
|**To TF32 (e8m10)**|No|No|No|
|**To BF16 (e8m7)**|No|Identity|Sign and mantissa from 8b, exponent zero|
|**To E8M6**|No|No|No|
|**To FP16 (e5m10)**|No|Identity|No|
|**To E5M7**|No|No|Sign and mantissa from 8b, exponent zero|
|**To E5M6**|No|No|No|
|**To FP8 (e5m2)**|No|No|Identity|
|**To INT32**|Identity|Shifted left by 16 bits; bottom bits filled with zero|Shifted left by 24 bits; bottom bits filled with zero|
|**To INT16**|Uses top 16 bits; bottom 16 discarded|Identity|Shifted left by 8 bits; bottom bits filled with zero|
|**To INT8<br/>or UINT8**|No|Uses top 8 bits; bottom 8 discarded|Identity|

## Late format conversion

The late format conversion takes one of the supported intermediate formats, and converts it to a format supported by L1:

<table><tr><th/><th>From FP32</th><th>From TF32 or BF16 or E8M6 or FP16 or E5M7 or E5M6 or FP8</th><th>From INT32</th><th>From INT16</th><th>From INT8 or UINT8</th></tr>
<tr><th>To FP32 or BF16</th><td colspan="2">Truncate if there is narrowing of mantissa</td><td colspan="3">No</td></tr>
<tr><th>To TF32</th><td>No (use early conversion)</td><td>Yes (all bits preserved; no rounding or truncation or saturation ever required)</td><td colspan="3">No</td></tr>
<tr><th>To FP16<br/>or FP8</th><td colspan="2">Saturate if there is narrowing of exponent, then truncate if there is narrowing of mantissa</td><td colspan="3">No</td></tr>
<tr><th>To BFP8</th><td colspan="2">Converted to BF16 (as per first row), then round to BFP8 with one shared 8b exponent per 16 datums</td><td colspan="3">No</td></tr>
<tr><th>To BFP4<br/>or BFP2</th><td colspan="2">Converted to BFP8 (as per the above row), then truncate to BFP4 or BFP2</td><td colspan="3">No</td></tr>
<tr><th>To BFP8a</th><td colspan="2">Converted to E5M7 (saturate if there is narrowing of exponent, then truncate if there is narrowing of mantissa), then round to BFP8a with one shared 5b exponent per 16 datums</td><td colspan="3">No</td></tr>
<tr><th>To BFP4a<br/>or BFP2a</th><td colspan="2">Converted to BFP8a (as per the above row), then truncate to BFP4a or BFP2a</td><td colspan="3">No</td></tr>
<tr><th>To INT32</th><td colspan="2">No</td><td>Identity</td><td>No</td><td>No</td></tr>
<tr><th>To INT16</th><td colspan="2">No</td><td>No</td><td>Identity</td><td>No</td></tr>
<tr><th>To INT8<br/>or UINT8</th><td colspan="2">No</td><td>No</td><td>No</td><td>Identity or bitcast</td></tr>
</table>

Where rounding happens in BFP conversions, it can either be deterministic round-to-nearest with ties away from zero, or stochastic (though due to a hardware bug, stochastic rounding has a slight bias towards increasing the magnitude rather than being 50:50, and can even sometimes increase the magnitude of values which do not require rounding).

The late format conversion sometimes preserves denormals, and sometimes flushes them, depending on the nature of the late format conversion:

<table><thead><tr><th/><th>Mantissa widens</th><th>Mantissa stays same width</th><th>Mantissa narrows</th></tr></thead>
<tr><th align="left">Exponent widens</th><td colspan="2">Denormals mishandled; software should either ensure inputs are not denormal, or ensure that the subsequent consumer of FP32 data treats FP32 denormals as zero</td><td>Denormals flushed to zero</td></tr>
<tr><th align="left">Exponent&nbsp;stays&nbsp;same&nbsp;width</th><td colspan="2">Denormals preserved</td><td>Denormals flushed to zero</td></tr>
<tr><th align="left">Exponent narrows</th><td colspan="3">Denormal inputs flushed to zero, as are inputs in range <code>|x| ≤ 2<sup>-15</sup></code>, but some inputs in range <code>2<sup>-15</sup> &lt; |x| &lt; 2<sup>-14</sup></code> are mishandled; software should either ensure inputs are not in this range, or ensure that the subsequent consumer of FP16 data treats FP16 denormals as zero</td></tr>
</table>

In some cases, the early format conversion will already have flushed the problematic ranges to zero. To cover the remaining cases, the [exponent thresholding](ExponentThresholding.md) feature of the packer can be used to ensure that problematic ranges have been flushed to zero long before reaching the late format conversion.

The late format conversion sometimes preserves NaNs, and sometimes replaces them with infinity, depending on the nature of the late format conversion:

<table><thead><tr><th/><th>Mantissa widens</th><th>Mantissa stays same width</th><th>Mantissa narrows</th></tr></thead>
<tr><th align="left">Input exponent is 5 bits</th><td colspan="3">Input is never NaN, as types with a 5-bit exponent are treated as not having NaN; see <a href="../FloatBitPatterns.md#fp16">FP16 bit patterns</a> for details</td></tr>
<tr><th align="left">Input&nbsp;and&nbsp;output&nbsp;exponent&nbsp;both&nbsp;8&nbsp;bits</th><td colspan="2">NaN preserved</td><td>NaN can become infinity, if that is the outcome of truncating mantissa bits</td></tr>
<tr><th align="left">Exponent&nbsp;narrows&nbsp;from&nbsp;8&nbsp;bits&nbsp;to&nbsp;5&nbsp;bits</th><td colspan="3">NaN becomes infinity, as types with a 5-bit exponent are treated as not having NaN; see <a href="../FloatBitPatterns.md#fp16">FP16 bit patterns</a> for details</td></tr>
</table>

## Final L1 output format

The final L1 output format will be one of:
* **FP32:** Regular IEEE754 FP32. 32 bits per datum.
* **TF32:** Like regular IEEE754 FP32, but with mantissa reduced to just 10 bits. 32 bits per datum, of which the top 19 bits are meaningful, and the low 13 bits are always zero.
* **BF16:** Like regular IEEE754 FP32, but with mantissa reduced to just 7 bits. 16 bits per datum.
* **FP16:** Like IEEE754 FP16 for normal values, but different bit pattern for infinity, and no bit patterns meaning NaN. See [FP16 bit patterns](../FloatBitPatterns.md#fp16) for details. 16 bits per datum.
* **FP8:** For normal values, like IEEE754 FP16, but with mantissa reduced to just 2 bits (i.e. e5m2). Different bit pattern for infinity, and no bit patterns meaning NaN. Encoding follows the [FP16 bit patterns](../FloatBitPatterns.md#fp16), but with mantissa reduced to just 2 bits. 8 bits per datum.
* **BFP8 / BFP4 / BFP2:** Either 8 or 4 or 2 bits per datum, of which the high bit is a sign bit and the remaining bits are magnitude (not mantissa, because there's no implicit `1` bit). Each group of 16 datums then shares a single 8-bit exponent, which is interpreted similar to FP32.
* **BFP8a / BFP4a / BFP2a:** Either 8 or 4 or 2 bits per datum, of which the high bit is a sign bit and the remaining bits are magnitude (not mantissa, because there's no implicit `1` bit). Each group of 16 datums then shares a single 5-bit exponent, which is interpreted similar to FP16, and is zero-extended to 8 bits for storage in memory.
* **INT32:** This is a sign-magnitude format (not a two's complement format) with one sign bit and 31 magnitude bits.
* **INT16:** This is a sign-magnitude format (not a two's complement format) with one sign bit and 15 magnitude bits, though it is often used to transport opaque 16-bit data, in which case software is free to decide on any interpretation of the 16 bits.
* **INT8:** This is a sign-magnitude format (not a two's complement format) with one sign bit and 7 magnitude bits.
* **UINT8:** Regular `uint8_t` for integers in the range 0 through 255. 8 bits per datum.

For all BFP formats, there is a separate output stream in L1 for the exponents, consisting of one byte per 16 datums.

For all BFP4 formats, two datums are packed into each byte of L1. For all BFP2 formats, four datums are packed into each byte of L1.

## Configuring the conversions

The early format conversion is configured using a variety of configuration fields, taking different values based on the desired conversion:

* **From FP32 or INT32:** Set `Read_32b_data = true`, then:
  * **To FP32 or INT32:** Choose any of:
    * Set `IntermediateFormat = INT32`.
    * Set `IntermediateFormat = FP32` and either `Round_10b_mant = false` or `Read_raw = true`.
    * Set `IntermediateFormat = TF32` and `Read_raw = true`.
  * **To TF32:** Set `Read_raw = false`, then choose any of:
    * Set `IntermediateFormat = TF32`.
    * Set `IntermediateFormat = FP32` and `Round_10b_mant = true`.
    * Set `IntermediateFormat = BF16` and `Round_10b_mant = true` (this choice can only be used if the late conversion is from TF32 to FP16).
  * **To BF16:**
    * **Rounding:** Set `IntermediateFormat = BF16` and `Read_raw = false`. If the late conversion is from BF16 to FP16, also set `Round_10b_mant = false`.
    * **Truncating:** Set `Read_raw = true`, then choose either of:
      * Set `IntermediateFormat = BFP8`.
      * Set `IntermediateFormat = BF16`. If the late conversion is from BF16 to FP16, also set `Round_10b_mant = false`.
  * **To E8M6:** Set `IntermediateFormat = BFP8` and `Read_raw = false`.
  * **To INT8:** Set `IntermediateFormat = INT8` and `Read_unsigned = false`. Then:
    * **Sign bit and low seven bits:** Set `Read_raw = true`.
    * **Shifting, rounding, and saturating:** Set `Read_raw = false`. Set the low five bits of `ShiftAmount` to the desired right-shift amount; note that this shifts the magnitude right, leaves the sign bit as-is, and fills the gap with zeros. The shifted-out bits (if any) are used for rounding.
  * **To UINT8:** Set `IntermediateFormat = INT8` and `Read_unsigned = true`. Then:
    * **Low eight bits:** Set `Read_raw = true`.
    * **Shifting, rounding, and saturating:** Set `Read_raw = false`. Set the low five bits of `ShiftAmount` to the desired right-shift amount; note that this shifts the magnitude right, leaves the sign bit as-is, and fills the gap with zeros. The shifted-out bits (if any) are used for rounding.
* **From BF16:** Set `Read_32b_data = false`, then:
  * **To TF32:** Set `Read_raw = false`, then choose any of:
    * Set `IntermediateFormat = TF32`.
    * Set `IntermediateFormat = FP32` and `Round_10b_mant = true`.
    * Set `IntermediateFormat = BF16` and `Round_10b_mant = true` (this choice can only be used if the late conversion is from TF32 to FP16, and if available, is the preferred choice for efficiency reasons).
  * **To BF16:**
    * **Rounding (i.e. flush denormals to zero and NaN to infinity):** Set `IntermediateFormat = BF16` and `Read_raw = false`. If the late conversion is from BF16 to FP16, also set `Round_10b_mant = false`.
    * **Identity (i.e. preserve denormals and NaN):** Set `Read_raw = true`, then choose either of:
      * Set `IntermediateFormat = BFP8`.
      * Set `IntermediateFormat = BF16`. If the late conversion is from BF16 to FP16, also set `Round_10b_mant = false`.
  * **To E8M6:** Set `IntermediateFormat = BFP8` and `Read_raw = false`.
  * **To INT8 (sign bit only):** Set `IntermediateFormat = INT8` and `Read_unsigned = false` and `Read_raw = true`.
* **From FP16:** Set `Read_32b_data = false`, then:
  * **To FP16:** Set `IntermediateFormat = FP16`.
    * **Rounding (i.e. flush denormals to zero):** Set `Read_raw = false`.
    * **Identity (i.e. preserve denormals):** Set `Read_raw = true`.
  * **To E5M7:** Set `IntermediateFormat = BFP8a` and `Read_raw = true`.
  * **To E5M6:** Set `IntermediateFormat = BFP8a` and `Read_raw = false`.
  * **To FP8:** Set `IntermediateFormat = FP8` and `Read_raw = true`.
  * **To INT8 (sign bit only):** Set `IntermediateFormat = INT8` and `Read_unsigned = false` and `Read_raw = true`.
* **From INT16:** Set `Read_32b_data = false`, then:
  * **To INT16:** Set `IntermediateFormat = INT16`.

The mapping of variables in the above to concrete configuration fields is:

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

Read_32b_data  is ConfigState.PCK_DEST_RD_CTRL_Read_32b_data;
Round_10b_mant is ConfigState.PCK_DEST_RD_CTRL_Round_10b_mant;
Read_raw       is ConfigState.PCK_DEST_RD_CTRL_Read_int8;
Read_unsigned  is ConfigState.PCK_DEST_RD_CTRL_Read_unsigned;

if (ConfigState.ALU_FORMAT_SPEC_REG_Dstacc_override) {
  IntermediateFormat is ConfigState.ALU_FORMAT_SPEC_REG_Dstacc_val;
} else {
  IntermediateFormat is ConfigState.ALU_FORMAT_SPEC_REG2_Dstacc;
}

if (ConfigState.INT_DESCALE_Enable) {
  if (ConfigState.INT_DESCALE_Mode) {
    ShiftAmount is Config.INT_DESCALE_VALUES_SEC[(z & 63) >> 2].Value >> ((z & 3) * 8); // For some value z
  } else {
    ShiftAmount is Config.INT_DESCALE_VALUES_SEC0_Value;
  }
} else {
  ShiftAmount is 0;
}
```

The late format conversion is configured using the `LateFromFormat` and `LateToFormat` variables, which map to concrete configuration fields as:
```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;

LateFromFormat is CurrentPacker.Config[StateID].In_data_format;
LateToFormat   is CurrentPacker.Config[StateID].Out_data_format;
```

It is usually the case that `IntermediateFormat` and `LateFromFormat` should be set to the same value. All three of `IntermediateFormat` and `LateFromFormat` and `LateToFormat` are 4-bit fields, with the encoding of data type names being:

||`0b??11`|`0b??10`|`0b??01`|`0b??00`|
|---|---|---|---|---|
|**`0b00??`**|`BFP4a` (‡)|`BFP8a` (†)|`FP16`|`FP32`|
|**`0b01??`**|`BFP4` (‡)|`BFP8` (†)|`BF16`|`TF32`|
|**`0b10??`**|`BFP2a` (‡)|`FP8`|`INT16`|`INT32`|
|**`0b11??`**|`BFP2` (‡)|`INT8`|||

(†) Only actually _means_ BFP in `LateToFormat`. Elsewhere it usually represents a type with the same exponent and mantissa width as the BFP format, but with the exponent being per-datum rather than one common exponent per 16 datums. In the case of BFP8, this gives a type almost identical to BF16.

(‡) Only valid in `LateToFormat`, not valid in `IntermediateFormat` or `LateFromFormat`.
