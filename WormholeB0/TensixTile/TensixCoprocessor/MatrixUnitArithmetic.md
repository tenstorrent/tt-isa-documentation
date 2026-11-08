# Matrix Unit (FPU) floating-point arithmetic, exactly

The functional models of [`ELWADD`](ELWADD.md), [`ELWSUB`](ELWSUB.md), [`ELWMUL`](ELWMUL.md), [`MVMUL`](MVMUL.md), [`DOTPV`](DOTPV.md) and [`GAPOOL`](GAPOOL.md) describe their floating-point arithmetic with C `float` operations, which is only a rough guide. This page gives the exact arithmetic for one output datum, bit for bit, for Blackhole, and for Wormhole with the differences listed at the end. It covers the floating-point cases only (`SrcAStyle` is `BF16`, `FP16` or `TF32`); integer arithmetic (`ALU_ACC_CTRL_INT8_math_enabled`) is as the instruction pages describe it.

The model assumes the configuration the instruction pages require: `ALU_ACC_CTRL_Zero_Flag_disabled_src` clear, `FP16A_FORCE_Enable` clear, and no fidelity phase other than 0 for `ELWADD` / `ELWSUB`. It also assumes `ALU_ROUNDING_MODE_Fpu_srnd_en` (stochastic rounding) and `ALU_ROUNDING_MODE_GS_LF` are clear, which this page does not describe; setting either is `UnsupportedFunctionality`.

## Overview

Each datum position of an 8x16 block of `Dst` is computed by a pair of lanes, `r0` and `r1`, each with eight multipliers. A lane forms the sum of its eight products in fixed point, aligned to the largest of their exponents; `r0` then aligns its own sum, `r1`'s sum and the `Dst` datum to their common exponent, adds them, and rounds the result once to the `Dst` format. In detail:

* `MVMUL`, `DOTPV` and `GAPOOL` (sums of products): output `(i, j)` is `Dst[i][j]` plus the sum over `k` of `SrcB[i][k] * SrcA[k][j]`. Lane `r0` computes the products for `k` in 0 through 7, and lane `r1` those for `k` in 8 through 15. Each instruction rounds into `Dst` once; a matrix multiply that needs several fidelity phases, or a reduction dimension longer than 16, is several instructions, each rounding into `Dst`, in the order software issues them.
* `ELWMUL`: `r0`'s first multiplier computes `SrcA * SrcB`, and its result is added to `Dst`.
* `ELWADD` and `ELWSUB`: `SrcA` and `SrcB` bypass the multipliers (they are presented as `SrcA * 1` and `1 * SrcB`, but at full precision), and their sum is added to `Dst` (or to zero, without `AddDst`). `ELWSUB` is `ELWADD` with the sign of the `SrcB` datum flipped as it is read.

Notable properties, all visible in the model below:

* Products are exact, but each product is rounded as it is aligned to its lane's largest exponent, and a lane keeps only 10 fractional bits relative to that exponent. Then each lane's sum is rounded again as it is aligned to the common exponent, as is the `Dst` datum, and the final sum is rounded once more to the output format. Two `BF16` values that differ in exponent can therefore sum to a result one unit in the last place away from the correctly rounded sum.
* Without `ALU_ACC_CTRL_Fp32_enabled`, every term is rounded to 10 fractional bits of the common exponent before the addition, whether `Dst` holds `BF16` or `FP16`; with it, to 23.
* Rounding is to nearest. Ties go away from zero, except when a lane's sum is aligned to the common exponent: there, ties go towards positive infinity.
* There are no denormals: a `Src` datum whose exponent field is 0 is zero, and a result whose exponent would be 0 or less is `+0`. A zero result is always `+0`.
* Infinities and NaNs have no special handling: an exponent field of 255 is an ordinary (large) exponent, the mantissa of a NaN takes part in the arithmetic like any other, and a result whose exponent would be 255 or more is an infinity of the result's sign. For an `FP16` result in 16-bit `Dst`, an exponent of 31 is an ordinary exponent, and a result whose exponent would be 32 or more becomes the largest `FP16` magnitude (exponent 31, mantissa all ones).

## Functional model

```c
// What the instruction tells the lanes.
struct LaneControl {
  bool SumOfProducts;    // MVMUL, DOTPV, GAPOOL
  bool Add;              // ELWADD, ELWSUB (ELWMUL is neither)
  bool AddDst;           // ELWADD, ELWSUB: the instruction's AddDst. Others: true
  bool Fp32;             // UseDst32b, i.e. ALU_ACC_CTRL_Fp32_enabled
  bool Exp8;             // SrcAStyle is BF16 or TF32 (an 8-bit exponent), not FP16
  uint2_t FidelityPhase;
};

// A Src datum, Sign(1),Man(10),Exp(8), after TruncateSrc (which only Wormhole applies).
// Every mantissa and exponent bit is used, whatever the data type; the datum is zero
// exactly when its exponent field is zero.
struct Operand {
  uint1_t Sign;
  uint8_t Exp;
  uint10_t Man;
  bool Zero;
};

Operand ReadOperand(uint19_t x) {
  return {x >> 18, x & 0xff, (x >> 8) & 0x3ff, (x & 0xff) == 0};
}

// The multiplier inputs (see "Fidelity phases" in SrcASrcB.md): 5 bits of SrcA,
// read as a fixed-point number with 4 fractional bits, and 7 bits of SrcB, with 6.
uint5_t SrcAMultiplierBits(Operand a, uint2_t FidelityPhase) {
  if (FidelityPhase & 1) return (a.Man >> 1) & 0x1f; // Mantissa bits 5 through 1.
  else return 0x10 | (a.Man >> 6); // Implicit 1, then mantissa bits 9 through 6.
}

uint7_t SrcBMultiplierBits(Operand b, uint2_t FidelityPhase) {
  if (FidelityPhase & 2) return (b.Man & 0xf) << 3; // Mantissa bits 3 through 0, then three 0s.
  else return 0x40 | (b.Man >> 4); // Implicit 1, then mantissa bits 9 through 4.
}

// One lane's sum of products: a fixed-point number with 10 fractional bits, scaled by
// 2 to the power of (Exp - Dst's exponent bias). A lane whose exponent underflows has
// Exp == 0 and Sum == 0.
struct LaneSum {
  uint9_t Exp;
  int32_t Sum;
};

LaneSum LaneSumOfProducts(LaneControl c, Operand a[8], Operand b[8]) {
  // The exponent of each product (as the sum of two biased exponents), and their maximum.
  uint9_t ExpSum[8], MaxExpSum = 0;
  for (unsigned i = 0; i < 8; ++i) {
    ExpSum[i] = (a[i].Zero || b[i].Zero) ? 0 : a[i].Exp + b[i].Exp;
    if (ExpSum[i] > MaxExpSum) MaxExpSum = ExpSum[i];
  }

  // Each product, aligned to the maximum exponent and rounded to 10 fractional bits
  // (to nearest, ties away from zero), then summed.
  int32_t Sum = 0;
  for (unsigned i = 0; i < 8; ++i) {
    uint12_t Product; // 10 fractional bits
    if (c.Add) {
      // Pair 0 is (SrcA, 1) and pair 1 is (1, SrcB): the full significands, unrounded.
      if (i == 0) Product = a[0].Zero ? 0 : 0x400 | a[0].Man;
      else if (i == 1) Product = b[1].Zero ? 0 : 0x400 | b[1].Man;
      else Product = 0;
    } else if (a[i].Zero || b[i].Zero) {
      Product = 0;
    } else {
      Product = SrcAMultiplierBits(a[i], c.FidelityPhase) * SrcBMultiplierBits(b[i], c.FidelityPhase);
    }
    unsigned Shift = MaxExpSum - ExpSum[i];
    uint32_t Aligned = Shift >= 16 ? 0 : (((Product << 1) >> Shift) + 1) >> 1;
    if (a[i].Sign != b[i].Sign) Sum -= Aligned;
    else Sum += Aligned;
  }

  // Rebias the exponent for Dst: a sum of two biased exponents carries the bias twice, so
  // subtract it once (for FP16 operands into a 32-bit Dst, convert from twice FP16's bias
  // to FP32's bias instead), and account for the fidelity phase's scaling of the multiplier
  // bits. This is computed modulo 2**10, and a result of 0 or of 512 or more underflows.
  int Bias = c.Exp8 ? -127 : c.Fp32 ? 127 - 30 : -15;
  int PhaseAdjust = ((c.FidelityPhase & 1) ? 5 : 0) + ((c.FidelityPhase & 2) ? 7 : 0);
  uint10_t Exp = (MaxExpSum + Bias - PhaseAdjust) & 0x3ff;
  if (Exp == 0 || Exp >= 512) return {0, 0};
  return {Exp, Sum};
}

// The Dst datum, in FP32 layout (Sign, Exp, Man), as read from Dst32b or widened from
// Dst16b: from BF16, Man is the 7 stored mantissa bits followed by 16 zeros; from FP16,
// Exp is the stored 5-bit exponent (not rebiased) and Man is the 10 stored mantissa bits
// followed by 13 zeros. ELWADD and ELWSUB without AddDst do not read Dst.
struct DstOperand {
  uint1_t Sign;
  uint8_t Exp;
  uint23_t Man;
};

// x / 2**n rounded to an integer, to nearest with ties towards positive infinity.
int64_t ShiftRound(int64_t x, unsigned n) {
  if (n == 0) return x;
  if (n >= 63) return 0;
  return (x + (int64_t(1) << (n - 1))) >> n; // Arithmetic shift, i.e. rounding down.
}

// The output datum, in FP32 layout: for a 16-bit Dst, the BF16 or FP16 value is the top
// 7 or 10 mantissa bits of the result (the rest are 0), with an FP16 result's 5-bit
// exponent in the exponent field, ready for the narrowing to Dst16b's layout.
// DstLow is described below the code.
uint32_t LanePairResult(LaneControl c, LaneSum r0, LaneSum r1, DstOperand d, uint13_t DstLow) {
  // The Dst term: 24 significant bits, 23 of them fractional. In a 16-bit Dst, the low
  // 13 bits are DstLow.
  bool DstIsZero = d.Exp == 0 || (c.Add && !c.AddDst);
  uint8_t DstExp = (c.Add && !c.AddDst) ? 0 : d.Exp;
  uint1_t DstSign = DstIsZero ? 0 : d.Sign;
  uint24_t DstMan = DstIsZero ? 0 : 0x800000 | d.Man;
  if (!c.Fp32) DstMan |= DstLow;

  // The common exponent.
  uint9_t Exp = r0.Exp;
  if (c.SumOfProducts && r1.Exp > Exp) Exp = r1.Exp;
  if (DstExp > Exp) Exp = DstExp;

  // Align every term to the common exponent, as a fixed-point number with 23 fractional
  // bits, rounding as it is aligned: to a multiple of 2**13 (i.e. to 10 fractional bits)
  // unless c.Fp32. Lane sums round with ties towards positive infinity; the Dst term
  // rounds its magnitude, with ties away from zero. An alignment shift is at most 31.
  unsigned Low = c.Fp32 ? 0 : 13;
  int64_t Acc = ShiftRound(int64_t(r0.Sum) << (13 - Low), min(Exp - r0.Exp, 31)) << Low;
  if (c.SumOfProducts) {
    Acc += ShiftRound(int64_t(r1.Sum) << (13 - Low), min(Exp - r1.Exp, 31)) << Low;
  }
  int64_t DstTerm = ShiftRound(DstMan, min(Exp - DstExp, 31) + Low) << Low;
  Acc += DstSign ? -DstTerm : DstTerm;

  // Normalize (|Acc| is always less than 2**29).
  uint1_t Sign = Acc < 0;
  uint32_t Mag = Sign ? -Acc : Acc;
  if (Exp == 0 || Mag == 0) return 0; // +0
  unsigned Top = 31 - clz(Mag); // The position of the most significant 1 bit of Mag.
  int ResultExp = Exp + Top - 23;
  uint29_t Normalized = Mag << (28 - Top); // Implicit 1 at bit 28.
  if (TTArchitecture == Wormhole && Acc == -1) {
    // Wormhole erratum: -1 normalizes as if it were -16, with the implicit 1 lost.
    ResultExp = Exp + 4;
    Normalized = 0;
  }

  // Round to 23 (FP32), 7 (BF16) or 10 (FP16) fractional bits, to nearest, ties away from zero.
  unsigned Dropped = c.Fp32 ? 5 : c.Exp8 ? 21 : 18;
  uint32_t Rounded = (Normalized >> Dropped) + ((Normalized >> (Dropped - 1)) & 1);
  if (Rounded >> (29 - Dropped)) { // Rounded up to the next power of two.
    Rounded >>= 1;
    ResultExp += 1;
  }
  uint23_t Man = (Rounded << (Dropped - 5)) & 0x7fffff;

  if (c.Fp32 || c.Exp8) {
    if (ResultExp <= 0) return 0; // +0
    if (ResultExp >= 255) return (Sign << 31) | (255 << 23); // Infinity
    return (Sign << 31) | (ResultExp << 23) | Man;
  } else {
    // FP16 result in a 16-bit Dst. With FP16 operands (exponent fields 0 through 31),
    // ResultExp is always less than 64.
    if (ResultExp <= 0) return 0; // +0
    if (ResultExp >= 32) return (Sign << 31) | (31 << 23) | (0x3ff << 13); // Largest magnitude
    return (Sign << 31) | (ResultExp << 23) | Man;
  }
}

// ELWMUL, ELWADD, ELWSUB: one output datum (SrcBVal's sign already flipped for ELWSUB).
uint32_t ElementwiseDatum(LaneControl c, uint19_t SrcAVal, uint19_t SrcBVal, DstOperand d, uint13_t DstLow) {
  const Operand One = {0, c.Exp8 ? 127 : 15, 0, false};
  const Operand Zero = {0, 0, 0, true};
  Operand a[8] = {Zero, Zero, Zero, Zero, Zero, Zero, Zero, Zero};
  Operand b[8] = {Zero, Zero, Zero, Zero, Zero, Zero, Zero, Zero};
  a[0] = ReadOperand(SrcAVal);
  if (c.Add) {
    b[0] = One;
    a[1] = One;
    b[1] = ReadOperand(SrcBVal);
  } else {
    b[0] = ReadOperand(SrcBVal);
  }
  LaneSum r0 = LaneSumOfProducts(c, a, b);
  return LanePairResult(c, r0, r0, d, DstLow);
}

// MVMUL, DOTPV, GAPOOL: one output datum, from row i of SrcB (SrcBRow[k] = SrcB[i][k])
// and column j of SrcA (SrcACol[k] = SrcA[k][j]).
uint32_t SumOfProductsDatum(LaneControl c, uint19_t SrcACol[16], uint19_t SrcBRow[16], DstOperand d, uint13_t DstLow) {
  Operand a[2][8], b[2][8];
  for (unsigned k = 0; k < 16; ++k) {
    a[k / 8][k % 8] = ReadOperand(SrcACol[k]);
    b[k / 8][k % 8] = ReadOperand(SrcBRow[k]);
  }
  LaneSum r0 = LaneSumOfProducts(c, a[0], b[0]);
  LaneSum r1 = LaneSumOfProducts(c, a[1], b[1]);
  return LanePairResult(c, r0, r1, d, DstLow);
}
```

`DstLow` is 0 when `Dst` is 32 bits wide (it is not used). When `Dst` is 16 bits wide, the lane uses 13 bits it holds from earlier instructions as the low 13 bits of the `Dst` term's mantissa. They are 0 until the first `ELWADD`, `ELWSUB`, `ELWMUL`, `MVMUL`, `DOTPV`, `GAPOOL` or `GMPOOL` with a 32-bit `Dst` (`ALU_ACC_CTRL_Fp32_enabled` or `ALU_ACC_CTRL_INT8_math_enabled`) after reset. After one, bit 12 of `DstLow` is an `UnpredictableValue()`, separately for every datum, and bits 11 through 0 are 0. Bit 12 matters only when the `Dst` term is not shifted (its exponent is the common exponent), where it can round the term up. Software that mixes 32-bit and 16-bit `Dst` accumulation should expect 16-bit results that occasionally differ by one unit in the last place of the 10-bit accumulator (this has been characterized on Blackhole).

## Differences on Wormhole

The same model describes Wormhole, with these differences:

* Every `Src` datum first goes through `TruncateSrc`, as the instruction pages show.
* The normalization of an accumulator value of exactly -1 (one unit in the 23rd fractional place, possible only with `ALU_ACC_CTRL_Fp32_enabled`) is wrong, as shown in the model: the result is -2<sup>4</sup> times 2 to the power of (the common exponent - 127), not -2<sup>-23</sup> times that.
* `ALU_ROUNDING_MODE_GS_LF` changes the multiplier inputs, and is not described here; the model assumes it is clear (setting it is `UnsupportedFunctionality` on both chips).
