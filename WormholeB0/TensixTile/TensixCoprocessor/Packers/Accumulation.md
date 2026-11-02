# Accumulation

If a packer's `Pack_L1_Acc` configuration field is set, then rather than overwriting L1, the packer performs `L1 += Datum` for each datum it writes, using the [near-memory accumulate](../../L1.md) functionality of L1. The addition happens in L1's access port, after all of the packer's [format conversions](FormatConversion.md), and so it operates on datums in the final L1 output format.

When a packer [pads](OutputAddressGenerator.md#output-alignment) its final 16 bytes with zeroes, the padding is accumulated as well: every L1 datum covered by the padding has +0 added to it. This leaves most values as they were, but the rules below still apply to them (for example, -0 becomes +0, and denormals become zero). The zeros a `PACR` with `ZeroWrite` packs are accumulated the same way.

The output format (`Out_data_format`) selects the addition: FP32 datums are added as FP32, FP16 datums as FP16, BF16 datums as BF16, and INT32 datums as sign-magnitude INT32. On Blackhole, INT8 datums are added as sign-magnitude INT8, or as UINT8 when `Read_unsigned` is set. Every other output format is added as though each aligned group of 4 bytes of the packer's output were one FP32 value, which does not sum the datums: this includes FP8, INT16, INT8 on Wormhole, and the BFP formats. On Blackhole, `Pack_L1_Acc` must not be used with a BFP output format. The exponent section of a BFP output is not accumulated; it is written as usual.

On Blackhole, each configuration context has its own `Pack_L1_Acc` (word 3 of `THCON_SEC0_REG1`, `THCON_SEC0_REG8`, `THCON_SEC1_REG1` or `THCON_SEC1_REG8`), and a `PACR` uses the one of the context it reads; on Wormhole, each packer has its own.

## Functional model

For the floating-point output formats, the addition is:

```c
uint32_t FlushDenormal(uint32_t x) {
  // Denormals become zero, keeping their sign
  return (x & 0x7f800000) ? x : (x & 0x80000000);
}

uint32_t L1AccumulateFP32(uint32_t L1, uint32_t Datum) {
  float Sum = std::bit_cast<float>(FlushDenormal(L1)) + std::bit_cast<float>(FlushDenormal(Datum)); // IEEE754 addition, rounding to nearest with ties to even
  if (isnan(Sum)) return 0x7fc00000;
  return FlushDenormal(std::bit_cast<uint32_t>(Sum));
}

double BF16ToReal(uint16_t x) {
  bool Sign = x >> 15;
  unsigned Exp = (x >> 7) & 0xff;
  unsigned Man = x & 0x7f;
  double Mag;
  if (Exp == 0) Mag = 0; // Denormals are treated as zero
  else if (Exp == 255 && Man == 0) Mag = INFINITY;
  else Mag = ldexp(128 + Man, Exp - 134); // NB: NaN is treated as a finite value with exponent 255
  return Sign ? -Mag : Mag;
}

uint16_t L1AccumulateBF16(uint16_t L1, uint16_t Datum) {
  if ((L1 == 0x7f80 && Datum == 0xff80) || (L1 == 0xff80 && Datum == 0x7f80)) {
    return 0x7fc0; // +Infinity plus -Infinity gives NaN
  }
  bool L1IsNaN = (L1 & 0x7fff) > 0x7f80;
  if (L1IsNaN) {
    // NaN in L1 behaves as a value larger in magnitude than any Datum other than Infinity
    bool DatumIsInf = (Datum & 0x7fff) == 0x7f80;
    return DatumIsInf ? Datum : ((L1 & 0x8000) | 0x7f80);
  }
  double Sum = BF16ToReal(L1) + BF16ToReal(Datum); // Precise enough that only the rounding below matters
  uint16_t Sign = signbit(Sum) << 15;
  if (fabs(Sum) < 0x1p-126) return Sign; // Flushed to zero before rounding, not after
  if (isinf(Sum)) return Sign | 0x7f80;
  int Exp;
  double Frac = frexp(fabs(Sum), &Exp); // fabs(Sum) == Frac * 2^Exp, 0.5 <= Frac < 1
  uint32_t Man = nearbyint(ldexp(Frac, 8)); // 128 through 256, ties to even
  uint32_t Bits = ((Exp + 126) << 7) + (Man - 128);
  return Sign | (Bits < 0x7f80 ? Bits : 0x7f80);
}

double FP16ToReal(uint16_t x) {
  bool Sign = x >> 15;
  unsigned Exp = (x >> 10) & 0x1f;
  unsigned Man = x & 0x3ff;
  double Mag = Exp ? ldexp(1024 + Man, Exp - 25) : 0; // Denormals are treated as zero
  return Sign ? -Mag : Mag;
}

uint16_t L1AccumulateFP16(uint16_t L1, uint16_t Datum) {
  double Sum = FP16ToReal(L1) + FP16ToReal(Datum); // Exact
  uint16_t Sign = signbit(Sum) << 15;
  if (Sum == 0) return (((L1 >> 10) & 0x1f) >= 30) ? 0x7fff : Sign;
  if (fabs(Sum) < 0x1p-15) return Sign | 0x7fff;
  if (fabs(Sum) < 0x1p-14) return Sign;
  int Exp;
  double Frac = frexp(fabs(Sum), &Exp); // fabs(Sum) == Frac * 2^Exp, 0.5 <= Frac < 1
  uint32_t Man = nearbyint(ldexp(Frac, 11)); // 1024 through 2048, ties to even
  uint32_t Bits = ((Exp + 14) << 10) + (Man - 1024);
  return Sign | (Bits < 0x8000 ? Bits : 0x7fff); // Saturate rather than overflow
}
```

Each datum is accumulated independently of its neighbors. For FP16, every bit pattern with a non-zero exponent is a normal value (there are no bit patterns meaning infinity or NaN; see [FP16 bit patterns](../FloatBitPatterns.md#fp16)), and there are some potentially surprising behaviors:
* If `L1` and `Datum` cancel exactly and the exponent of `L1` is 30 or 31, the result is `0x7FFF` (the largest positive value) rather than +0.
* Results smaller in magnitude than 2<sup>-15</sup> saturate to the largest value of the same sign (`0x7FFF` or `0xFFFF`), whereas results of magnitude at least 2<sup>-15</sup> but less than 2<sup>-14</sup> become zero of the same sign.

For the integer output formats, the addition is:

```c
int64_t SignMagnitudeToInt(uint32_t x, unsigned MagnitudeBits) {
  int64_t Mag = x & ((1u << MagnitudeBits) - 1);
  return (x >> MagnitudeBits) & 1 ? -Mag : Mag; // -0 is 0
}

uint32_t L1AccumulateINT32(uint32_t L1, uint32_t Datum) {
  if (IsBlackhole) {
    // A term at the largest magnitude saturates the result, with its sign (the datum's when both are)
    if ((Datum & 0x7fffffff) == 0x7fffffff) return Datum;
    if ((L1 & 0x7fffffff) == 0x7fffffff) return L1;
  } else if (SignMagnitudeToInt(L1, 31) + SignMagnitudeToInt(Datum, 31) == -0x80000000LL) {
    return 0; // Wormhole: the magnitude 2^31 wraps to zero
  }
  int64_t Sum = SignMagnitudeToInt(L1, 31) + SignMagnitudeToInt(Datum, 31);
  if (Sum > 0x7fffffff) return 0x7fffffff; // Saturate to the largest magnitude
  if (Sum < -0x7fffffff) return 0xffffffff;
  return Sum < 0 ? 0x80000000 | (uint32_t)-Sum : (uint32_t)Sum; // A zero result is +0
}

// Blackhole only; each byte is accumulated independently of its neighbors
uint8_t L1AccumulateINT8(uint8_t L1, uint8_t Datum) {
  if ((Datum & 0x7f) == 0x7f) return Datum; // As for INT32 on Blackhole
  if ((L1 & 0x7f) == 0x7f) return L1;
  int64_t Sum = SignMagnitudeToInt(L1, 7) + SignMagnitudeToInt(Datum, 7);
  if (Sum > 0x7f) return 0x7f;
  if (Sum < -0x7f) return 0xff;
  return Sum < 0 ? 0x80 | (uint8_t)-Sum : (uint8_t)Sum;
}

uint8_t L1AccumulateUINT8(uint8_t L1, uint8_t Datum) {
  unsigned Sum = L1 + Datum;
  return Sum > 0xff ? 0xff : Sum;
}
```

On Blackhole, a value at the largest magnitude therefore acts like an infinity: once an INT32 or INT8 datum in L1 has saturated, later accumulations into it leave it saturated, whatever they add.
