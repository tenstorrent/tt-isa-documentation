# Format Conversion

Two data format conversions happen during the pipeline of each packer: an early conversion just after reading datums from `Dst`, and a late conversion just before writing datums to `L1`. To avoid double rounding, software should ensure that at least one conversion is an identity conversion, or ensure that both conversions are truncating. In general, the early format conversion should be used to make types narrower using rounding, and the late format conversion should be used to make types wider. To make types narrower using truncation, it is sometimes the case that either conversion could be used, in which case the early conversion should be preferred.

## Early format conversion

If fetching datums from `Dst` (as is usually the case), the early format conversion will take datums in one of the five formats supported by `Dst` and convert them to one of the supported intermediate floating-point or integer formats:

||From FP32 (e8m23)|From BF16 (e8m7)|From FP16 (e5m10)|From INT32 (e0m31)|From INT16 (e0m15)|
|:-:|---|---|---|---|---|
|**To FP32 (e8m23)**|Identity|No (keep as BF16 then use late conversion, or go via TF32; on Blackhole, an FP32 intermediate is `UnsupportedFunctionality`)|No (keep as FP16 then use late conversion)|Bitcast|No|
|**To TF32 (e8m10)**|Rounding|Rounding (though more efficient to keep as BF16 then use late conversion)|No (keep as FP16 then use late conversion)|Bitcast to FP32 then rounding|No|
|**To BF16 (e8m7)**|Rounding or truncation|Rounding or identity|No (keep as FP16 then use late conversion)|Bitcast of top 16 bits|No|
|**To E8M6**|Rounding|Rounding|No|No|No|
|**To FP16 (e5m10)**|Rounding or truncation to TF32 then exponent narrowing on Blackhole; on Wormhole, no (keep as FP32 then use late conversion, or round to TF32 then use late conversion)|Exponent narrowing on Blackhole; on Wormhole, no (keep as BF16 then use late conversion)|Rounding or identity|No|No|
|**To E5M7**|No|No|Truncation|No|No|
|**To E5M6**|No|No|Rounding|No|No|
|**To FP8 (e5m2)**|No (keep as FP32 then use late conversion)|No (keep as BF16 then use late conversion)|Truncation|No|No|
|**To INT32 (e0m31)**|Bitcast|No|No|Identity|No|
|**To INT16 (e0m15)**|Top 16 bits|No|No|Top 16 bits|Identity|
|**To INT8 (e0m7)**|Sign bit and low 7 bits of mantissa|Sign bit only, other bits zero|Sign bit only, other bits zero|Shift then round then saturate (-127 to +127), or sign bit and low 7 bits of magnitude|No|
|**To UINT8**|Low 8 bits of mantissa|No|No|Shift then round then saturate (0 to 255), or low 8 bits of magnitude|No|

Where rounding is supported, it can either be deterministic round-to-nearest with ties away from zero, or stochastic (though due to a hardware bug, stochastic rounding has a slight bias towards increasing the magnitude rather than being 50:50, and can even sometimes increase the magnitude of values which do not require rounding). Stochastic rounding (any of the `ALU_ROUNDING_MODE_*_srnd_en` fields set) is `UnsupportedFunctionality`.

Handling of denormals and NaNs in the early format conversion depends on the nature of the early format conversion:
* **Identity / bitcast:** Denormals preserved. NaN preserved.
* **Rounding:** Denormals flushed to zero. Minus zero converted to positive zero. If the exponent is 8 bits wide, NaN becomes infinity (this is a potentially surprising behavior). When rounding from FP32 or BF16 to BF16 or E8M6, the flush happens _after_ rounding: the bit pattern is rounded (which can carry from the mantissa into the exponent), and then the result is flushed to positive zero if its exponent is zero. With deterministic rounding, this is:

  ```c
  uint32_t RoundExp8(uint32_t x, unsigned ManBits) { // x is FP32, or BF16 in the high 16 bits; ManBits is 7 (BF16) or 6 (E8M6)
    uint32_t Sign = x & 0x80000000;
    unsigned Drop = 23 - ManBits;
    uint32_t Mag = (x & 0x7fffffff) + (1u << (Drop - 1)); // Round to nearest, ties away from zero; can carry into the exponent
    Mag &= ~((1u << Drop) - 1);
    if (Mag >= 0x7f800000) return Sign | 0x7f800000;      // Exponent 255: infinity, including from NaN
    if (Mag < 0x00800000) return 0;                       // Exponent 0: positive zero, including from denormals and minus zero
    return Sign | Mag;                                    // The result is in the high 1 + 8 + ManBits bits
  }
  ```

  Consequently, FP32 denormals with a mantissa of at least `0x7F8000` become the smallest BF16 normal of the same sign (`0x0080` or `0x8080`), whereas all other FP32 denormals become positive zero; and to E8M6, FP32 denormals with a mantissa of at least `0x7F0000` and BF16 denormals with a mantissa of `0x7F` become the smallest E8M6 normal of the same sign, whereas all other denormals become positive zero.
* **Truncation:** Denormals can become zero, if that is the outcome of truncating mantissa bits. NaN can become infinity, if that is the outcome of truncating mantissa bits.
* **Exponent narrowing (Blackhole only):** The datum has an 8-bit exponent and a 10-bit mantissa: from FP32, the TF32 result of the rounding (which flushes denormals and minus zero to positive zero and turns NaN into infinity) or of the truncation (which keeps them); from BF16, the BF16 datum with three zero bits appended to its mantissa. Its exponent is then narrowed to 5 bits without rounding:

```c
uint16_t NarrowToFP16(uint19_t x) { // Sign, 8-bit exponent, 10-bit mantissa
  uint1_t Sign = x >> 18;
  int32_t Exp = ((x >> 10) & 0xff) - 112;
  uint10_t Man = x & 0x3ff;
  if (Exp < 0) return Sign << 15;              // Zero, keeping the sign
  if (Exp > 31) return (Sign << 15) | 0x7fff;  // Saturate, including infinity and NaN
  return (Sign << 15) | (Exp << 10) | Man;
}
```

  An input in range <code>2<sup>-15</sup> ≤ |x| &lt; 2<sup>-14</sup></code> thus keeps its mantissa bits under an exponent field of zero, losing its implicit leading one, as the late conversion from FP32 to FP16 does.

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

Where rounding happens in BFP conversions, it can either be deterministic round-to-nearest with ties away from zero, or stochastic (though due to a hardware bug, stochastic rounding has a slight bias towards increasing the magnitude rather than being 50:50, and can even sometimes increase the magnitude of values which do not require rounding). Stochastic rounding (any of the `ALU_ROUNDING_MODE_*_srnd_en` fields set) is `UnsupportedFunctionality`.

With deterministic rounding, each group of 16 datums is converted from BF16 to BFP8, and then possibly truncated to BFP4 or BFP2, using the following logic:

```c
void BF16ToBFP8(const uint16_t Datums[16], uint8_t* SharedExp, uint8_t BFP8[16]) {
  uint8_t MaxExp = 0;
  for (unsigned i = 0; i < 16; ++i) {
    uint8_t Exp = (Datums[i] >> 7) & 0xff;
    if (Exp > MaxExp) MaxExp = Exp; // NB: Exp == 255 is not special
  }
  *SharedExp = MaxExp;
  for (unsigned i = 0; i < 16; ++i) {
    uint8_t Sign = Datums[i] >> 15;
    uint8_t Exp = (Datums[i] >> 7) & 0xff;
    uint8_t Man = (Datums[i] & 0x7f) | (Exp ? 0x80 : 0);
    unsigned Shift = MaxExp - Exp;
    uint8_t Mag = 0;
    if (Shift < 8) {
      Mag = (Man + (1u << Shift)) >> (Shift + 1); // Round to nearest, ties away from zero
      if (Mag == 128) Mag = 127; // Clamp rather than renormalize
    }
    BFP8[i] = Mag ? ((Sign << 7) | Mag) : 0; // Never 0x80
  }
}

uint4_t BFP8ToBFP4(uint8_t BFP8) {
  uint8_t Mag = (BFP8 & 0x7f) >> 4;
  return Mag ? (((BFP8 >> 7) << 3) | Mag) : 0;
}

uint2_t BFP8ToBFP2(uint8_t BFP8) {
  uint8_t Mag = (BFP8 & 0x7f) >> 6;
  return Mag ? (((BFP8 >> 7) << 1) | Mag) : 0;
}
```

The shared exponent is the largest exponent in the group, with infinity and NaN treated as normal values with exponent 255, so +∞ and -∞ become `0x40` and `0xC0` with a shared exponent of 255 (which [convert back](../FloatBitPatterns.md#conversion-routines) to +∞ and -∞). A negative datum whose magnitude rounds or truncates to zero becomes +0. The above assumes that the only datum with an exponent of zero is +0, as is the case after any rounding early format conversion; other datums with an exponent of zero are not yet documented here.

The late format conversion sometimes preserves denormals, and sometimes flushes them, depending on the nature of the late format conversion:

<table><thead><tr><th/><th>Mantissa widens</th><th>Mantissa stays same width</th><th>Mantissa narrows</th></tr></thead>
<tr><th align="left">Exponent widens</th><td colspan="2">Denormals mishandled; software should either ensure inputs are not denormal, or ensure that the subsequent consumer of FP32 data treats FP32 denormals as zero. An FP16 denormal converted to FP32 keeps its mantissa bits (as the top ten bits of the FP32 mantissa) under an exponent field of zero, without rebiasing, so <code>m × 2<sup>-24</sup></code> becomes <code>m × 2<sup>-136</sup></code></td><td>Denormals flushed to zero</td></tr>
<tr><th align="left">Exponent&nbsp;stays&nbsp;same&nbsp;width</th><td colspan="2">Denormals preserved</td><td>Denormals flushed to zero</td></tr>
<tr><th align="left">Exponent narrows</th><td colspan="3">Denormal inputs flushed to zero, as are inputs in range <code>|x| &lt; 2<sup>-15</sup></code>, but inputs in range <code>2<sup>-15</sup> ≤ |x| &lt; 2<sup>-14</sup></code> are mishandled; software should either ensure inputs are not in this range, or ensure that the subsequent consumer of FP16 data treats FP16 denormals as zero. Converting FP32 to FP16, the flushed inputs become zero with the sign kept, and an input <code>(1 + f) × 2<sup>-15</sup></code> in the mishandled range keeps the top ten bits of <code>f</code> under an exponent field of zero, losing its implicit leading one, i.e. it becomes <code>f × 2<sup>-14</sup></code> truncated</td></tr>
</table>

On Blackhole, setting `Pac_LF8_4b_exp = true` makes FP8 in `LateToFormat` mean e4m3 (1 sign bit, 4 bit exponent with a bias of 7, 3 bit mantissa) rather than e5m2. The late conversion from FP16 to e4m3 is then:

```c
uint8_t FP16ToE4M3(uint16_t x) {
  uint1_t Sign = x >> 15;
  uint5_t Exp = (x >> 10) & 0x1f;
  uint10_t Man = x & 0x3ff;
  if (Exp < 8) return Sign << 7;                         // Zero, keeping the sign
  if (Exp >= 24) return (Sign << 7) | 0x7f;              // Saturate
  return (Sign << 7) | ((Exp - 8) << 3) | (Man >> 7);    // Truncate
}
```

An input in range <code>2<sup>-7</sup> ≤ |x| &lt; 2<sup>-6</sup></code> keeps the top three bits of its mantissa under an exponent field of zero, losing its implicit leading one. An exponent field of 15 is an ordinary exponent: e4m3 as packed has no infinity or NaN.

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
* **FP8:** For normal values, like IEEE754 FP16, but with mantissa reduced to just 2 bits (i.e. e5m2). Different bit pattern for infinity, and no bit patterns meaning NaN. Encoding follows the [FP16 bit patterns](../FloatBitPatterns.md#fp16), but with mantissa reduced to just 2 bits. 8 bits per datum. On Blackhole with `Pac_LF8_4b_exp = true`, e4m3 instead, as described above.
* **BFP8 / BFP4 / BFP2:** Either 8 or 4 or 2 bits per datum, of which the high bit is a sign bit and the remaining bits are magnitude (not mantissa, because there's no implicit `1` bit). Each group of 16 datums then shares a single 8-bit exponent, which is interpreted similar to FP32.
* **BFP8a / BFP4a / BFP2a:** Either 8 or 4 or 2 bits per datum, of which the high bit is a sign bit and the remaining bits are magnitude (not mantissa, because there's no implicit `1` bit). Each group of 16 datums then shares a single 5-bit exponent, which is interpreted similar to FP16, and is zero-extended to 8 bits for storage in memory.
* **INT32:** This is a sign-magnitude format (not a two's complement format) with one sign bit and 31 magnitude bits.
* **INT16:** This is a sign-magnitude format (not a two's complement format) with one sign bit and 15 magnitude bits, though it is often used to transport opaque 16-bit data, in which case software is free to decide on any interpretation of the 16 bits.
* **INT8:** This is a sign-magnitude format (not a two's complement format) with one sign bit and 7 magnitude bits.
* **UINT8:** Regular `uint8_t` for integers in the range 0 through 255. 8 bits per datum.

For all BFP formats, there is a separate output stream in L1 for the exponents, consisting of one byte per 16 datums.

For all BFP4 formats, two datums are packed into each byte of L1. For all BFP2 formats, four datums are packed into each byte of L1.

## Configuring the conversions

The early format conversion is configured by these variables, which map to concrete configuration fields as:

```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
auto& ConfigState = Config[StateID];

Read_32b_data  is ConfigState.PCK_DEST_RD_CTRL_Read_32b_data;
Round_10b_mant is ConfigState.PCK_DEST_RD_CTRL_Round_10b_mant;
Read_raw       is ConfigState.PCK_DEST_RD_CTRL_Read_int8;
Read_unsigned  is ConfigState.PCK_DEST_RD_CTRL_Read_unsigned;

if (ConfigState.ALU_FORMAT_SPEC_REG_Dstacc_override) {
  UnsupportedFunctionality(); // No known usage
  IntermediateFormat is ConfigState.ALU_FORMAT_SPEC_REG_Dstacc_val;
} else if (TTArchitecture == Blackhole) {
  IntermediateFormat is CurrentPacker.Config[StateID].In_data_format; // ALU_FORMAT_SPEC_REG2_Dstacc has no effect on Blackhole
} else {
  IntermediateFormat is ConfigState.ALU_FORMAT_SPEC_REG2_Dstacc;
}

if (ConfigState.INT_DESCALE_Enable) {
  if (ConfigState.INT_DESCALE_Mode) {
    ShiftAmount is Config.INT_DESCALE_VALUES_SEC[(z & 63) >> 2].Value >> ((z & 3) * 8); // z is the packer's Z position (see below)
  } else {
    ShiftAmount is Config.INT_DESCALE_VALUES_SEC0_Value;
  }
} else {
  ShiftAmount is 0;
}
```

In `INT_DESCALE_Mode`, `z` is the Z position of the packer's tile position generator (see [edge masking](EdgeMasking.md)) plus the packer's `DEST_TARGET_REG_CFG_PACK_SEC[i].ZOffset`, so each XY plane of `pack_reads_per_xy_plane` rows can have its own shift amount. Only the low five bits of the selected byte are used, in either mode. It does not affect conversions to INT32.

The conversion these variables select is a cell of the tables above: a row (the format converted to) and how. `Read_32b_data` decides whether `Dst` is read as 32-bit or 16-bit datums, but no variable says which format the datums in `Dst` are, so each 16-bit case below names the `Dst` format it is described for. Combinations for which `SelectEarlyConversion` gives `NotDescribed` are not described here:

```c
EarlyConversion SelectEarlyConversion() {
  if (Read_32b_data) { // Dst holds FP32 or INT32 datums
    switch (IntermediateFormat) {
    case INT32: return {FP32 or INT32, Identity or Bitcast};
    case FP32:
      if (Read_raw || !Round_10b_mant) return {FP32 or INT32, Identity or Bitcast};
      else return {TF32, Rounding};
    case TF32:
      if (Read_raw) return {FP32 or INT32, Identity or Bitcast};
      else return {TF32, Rounding};
    case BF16:
      if (Read_raw) return {BF16, Truncation};
      else if (Round_10b_mant) return {TF32, Rounding}; // Can only be used if the late conversion is from TF32 to FP16
      else return {BF16, Rounding};
    case BFP8:
      if (Read_raw) return {BF16, Truncation};
      else return {E8M6, Rounding};
    case FP16:
      if (TTArchitecture == Blackhole && Round_10b_mant) {
        if (Read_raw) return {FP16, Truncation to TF32 then exponent narrowing};
        else return {FP16, Rounding to TF32 then exponent narrowing};
      }
      return NotDescribed;
    case INT16: return {INT16, Top 16 bits}; // Opaque data: no conversion, rounding or saturation
    case INT8: return {Read_unsigned ? UINT8 : INT8, PackInt8}; // PackInt8 is below
    default: return NotDescribed;
    }
  } else { // Dst holds BF16, FP16 or INT16 datums
    switch (IntermediateFormat) {
    case TF32: // From BF16
      if (!Read_raw) return {TF32, Rounding};
      return NotDescribed;
    case FP32: // From BF16
      if (!Read_raw && Round_10b_mant) return {TF32, Rounding};
      if (TTArchitecture == Blackhole) {
        // Each BF16 datum lands in the high 16 bits, but the low 16 bits are not zero; they come from other data in Dst.
        // To get FP32, keep the datum as BF16 instead, and let the late conversion widen it.
        UnsupportedFunctionality();
      }
      return NotDescribed;
    case BF16: // From BF16
      if (Read_raw) return {BF16, Identity};
      else if (Round_10b_mant) return {TF32, Rounding}; // Can only be used if the late conversion is from TF32 to FP16, and if available, is the preferred choice for efficiency reasons
      else return {BF16, Rounding};
    case BFP8: // From BF16
      if (Read_raw) return {BF16, Identity}; // Except that it turns -0 into -infinity, so not actually an identity
      else return {E8M6, Rounding};
    case FP16:
      if (TTArchitecture == Blackhole && Round_10b_mant) return {FP16, Exponent narrowing}; // From BF16, with no rounding
      else if (Read_raw) return {FP16, Identity}; // From FP16
      else return {FP16, Rounding}; // From FP16
    case BFP8a: // From FP16
      if (Read_raw) return {E5M7, Truncation};
      else return {E5M6, Rounding};
    case FP8: // From FP16
      if (Read_raw) return {FP8, Truncation};
      return NotDescribed;
    case INT8: // From BF16 or FP16
      if (Read_raw && !Read_unsigned) return {INT8, Sign bit only};
      return NotDescribed;
    case INT16: return {INT16, Identity}; // From INT16
    default: return NotDescribed;
    }
  }
}
```

If the late conversion is from BF16 to FP16, `Round_10b_mant` should be `false` wherever `IntermediateFormat = BF16`.

For `IntermediateFormat = INT8` with `Read_32b_data = true`, each 32-bit datum `x` becomes:

```c
uint8_t PackInt8(uint32_t x) { // x is a sign-magnitude INT32 datum, or the bits of an FP32 datum
  if (Read_raw) {
    if (Read_unsigned) return x & 0xff;         // Low 8 bits (of the magnitude, or of the mantissa)
    else return ((x >> 31) << 7) | (x & 0x7f);  // Sign bit and low 7 bits
  }
  // From INT32 only:
  uint1_t Sign = x >> 31;
  uint32_t Mag = x & 0x7fffffff;
  uint5_t Shift = ShiftAmount & 0x1f;
  if (Shift) Mag = (Mag + (1u << (Shift - 1))) >> Shift; // Round to nearest, ties away from zero
  if (Read_unsigned) return min(Mag, 255u);   // The sign is dropped: e.g. -5 becomes 5
  Mag = min(Mag, 127u);
  return Mag ? ((Sign << 7) | Mag) : 0;       // A zero magnitude is +0, even if the input was negative
}
```

The late format conversion is configured using the `LateFromFormat` and `LateToFormat` variables, which map to concrete configuration fields as:
```c
uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;

LateFromFormat is CurrentPacker.Config[StateID].In_data_format;
LateToFormat   is CurrentPacker.Config[StateID].Out_data_format;
Pac_LF8_4b_exp is CurrentPacker.Config[StateID].Pac_LF8_4b_exp; // Blackhole only
```

It is usually the case that `IntermediateFormat` and `LateFromFormat` should be set to the same value (on Blackhole, both come from `In_data_format`). All three of `IntermediateFormat` and `LateFromFormat` and `LateToFormat` are 4-bit fields with the same encoding, but some values mean different things in different fields:

|Value|Name|In `IntermediateFormat` or `LateFromFormat`|In `LateToFormat` (the format written to L1)|
|---|---|---|---|
|`0b0000`|`FP32`|FP32|FP32|
|`0b0001`|`FP16`|FP16|FP16|
|`0b0010`|`BFP8a`|A per-datum format with a 5-bit exponent: E5M7 (early conversion with `Read_raw = true`) or E5M6 (with `Read_raw = false`)|BFP8a|
|`0b0011`|`BFP4a`|Not valid|BFP4a|
|`0b0100`|`TF32`|TF32|TF32|
|`0b0101`|`BF16`|BF16|BF16|
|`0b0110`|`BFP8`|A per-datum format with an 8-bit exponent: BF16 (early conversion with `Read_raw = true`) or E8M6 (with `Read_raw = false`)|BFP8|
|`0b0111`|`BFP4`|Not valid|BFP4|
|`0b1000`|`INT32`|INT32|INT32|
|`0b1001`|`INT16`|INT16|INT16|
|`0b1010`|`FP8`|FP8 (e5m2)|FP8 (e5m2; e4m3 on Blackhole with `Pac_LF8_4b_exp = true`)|
|`0b1011`|`BFP2a`|Not valid|BFP2a|
|`0b1110`|`INT8`|INT8, or UINT8 with `Read_unsigned = true`|INT8 or UINT8 (the late conversion passes the 8 bits through)|
|`0b1111`|`BFP2`|Not valid|BFP2|

`0b1100` and `0b1101` have no name. The BFP formats are only actually BFP in `LateToFormat`, where each group of 16 datums gets one shared exponent; in the other two fields, `BFP8a` and `BFP8` name a type with the exponent width of the BFP format but one exponent per datum, which in the case of `BFP8` gives a type almost identical to BF16.
