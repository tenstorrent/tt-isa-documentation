# `SFPMAD` (Vectorized floating-point multiply then add/subtract)

**Summary:** Performs lanewise FP32 `VD = ±(VA * VB) ± VC`. In some modes, the `VA` and/or `VD` indices from the instruction bits are ignored, and instead come from the low four bits of `LReg[7]` (which allows these bits to potentially differ between lanes).

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), MAD sub-unit

> [!TIP]
> Compared to Wormhole, some of the major upgrades to `SFPMAD` in Blackhole are: `SFPMAD_MOD1_NEGATE_VA` and `SFPMAD_MOD1_NEGATE_VC` modifiers, improved edge-case handling of NaNs and of negative zero, and automatic instruction scheduling.

## Syntax

```c
TT_SFPMAD(/* u4 */ VA, /* u4 */ VB, /* u4 */ VC, /* u4 */ VD, /* u4 */ Mod1)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPMAD.svg)

## Functional model

```c
lanewise {
  if (VD < 12 || LaneConfig[Lane].DISABLE_BACKDOOR_LOAD) {
    if (LaneEnabled) {
      unsigned va = Mod1 & SFPMAD_MOD1_INDIRECT_VA ? LReg[7].u32 & 15 : VA;
      uint32_t a = LReg[va].u32;
      uint32_t b = LReg[VB].u32;
      uint32_t c = LReg[VC].u32;
      if (Mod1 & SFPMAD_MOD1_NEGATE_VA) a ^= 0x80000000;
      if (Mod1 & SFPMAD_MOD1_NEGATE_VC) c ^= 0x80000000;
      uint32_t d = fma_model(a, b, c); // compute a * b + c
      unsigned vd;
      if ((Mod1 & SFPMAD_MOD1_INDIRECT_VD) && VD != 16) {
        vd = LReg[7].u32 & 15;
      } else {
        vd = VD;
      }
      if (vd < 8 || vd == 16) {
        LReg[vd].u32 = d;
      }
    }
  }
}
```

Supporting definitions:

```c
#define SFPMAD_MOD1_NEGATE_VA 1
#define SFPMAD_MOD1_NEGATE_VC 2
#define SFPMAD_MOD1_INDIRECT_VA 4
#define SFPMAD_MOD1_INDIRECT_VD 8
```

## IEEE754 conformance / divergence

Denormal inputs are treated as if they were zero.

If any input is NaN or ±Infinity, then the result will be NaN or ±Infinity, following the usual IEEE754 rules. If a NaN is emitted, it is always the canonical NaN with bit pattern `0x7fc00000`.

The multiply and the add are _partially_ fused, but not _completely_ fused: the result of the multiplication is kept in higher precision than FP32, but is not kept in the infinite precision required to be a completely fused operation. A single rounding step is performed, with the rounding mode always round to nearest with ties to even. If multiplying by one or adding zero, then the partially fused operation is equivalent to a standalone add or standalone multiply (handling of denormals notwithstanding).

If the output (after rounding) is denormal, it'll be flushed to sign-preserved zero.

A [bit-perfect software model](../../../Miscellaneous/FMA/README.md) is provided for anyone either trying to exactly reproduce the hardware behavior or trying to understand exactly where and how it diverges from IEEE754.

## Instruction scheduling

`SFPMAD` requires two cycles to compute its result. If `SFPMAD` is used, hardware will ensure that on the next cycle, the Vector Unit (SFPU) does not execute an instruction which reads from any location written to by the `SFPMAD`. If a thread presents a Vector Unit (SFPU) instruction which wants to read from such a location, then hardware will automatically stall the thread for one cycle. If `SFPMAD_MOD1_INDIRECT_VA` is used, the stalling logic conservatively assumes that `SFPMAD` reads from every `LReg`. Similarly, if `SFPMAD_MOD1_INDIRECT_VD` is used, the stalling logic conservatively assumes that `SFPMAD` writes to every `LReg`. This can lead to decreased performance when these modifiers are used.

> [!CAUTION]
> Automatic stalling does not apply to `SFPMAD` instructions executed as part of an [`SFPLOADMACRO`](SFPLOADMACRO.md) sequence. When constructing such sequences, software must ensure a gap of at least one cycle between the `SFPMAD` instruction and any instruction consuming the output of `SFPMAD`.

> [!CAUTION]
> Due to hardware bugs, a handful of cases are not detected by the automatic stalling logic:
> * `SFPAND` when `SFPAND_MOD1_USE_VB` is used: the stalling logic ignores `SFPAND_MOD1_USE_VB`, and therefore thinks that `SFPAND` always reads from `VD` and never reads from `VB`.
> * `SFPOR` when `SFPOR_MOD1_USE_VB` is used: the stalling logic ignores `SFPOR_MOD1_USE_VB`, and therefore thinks that `SFPOR` always reads from `VD` and never reads from `VB`.
> * `SFPIADD`: the stalling logic does not realize that `SFPIADD` reads from `VD`.
> * `SFPSHFT`: the stalling logic does not realize that `SFPSHFT` reads from `VD`.
> * `SFPCONFIG`: the stalling logic does not realize that `SFPCONFIG` can read from `LReg[0]`.
> * `SFPSWAP` in all modes _except_ `SFPSWAP_MOD1_SWAP`: these modes read from `VC` and `VD` during their 1<sup>st</sup> cycle to compare them, and then read them _again_ during their 2<sup>nd</sup> cycle if they need to be swapped, but the stalling logic does not realize that any reads are performed during the 1<sup>st</sup> cycle.
> * `SFPSHFT2` when `SFPSHFT2_MOD1_SUBVEC_SHFLROR1_AND_COPY4` or `SFPSHFT2_MOD1_SUBVEC_SHFLROR1` or `SFPSHFT2_MOD1_SUBVEC_SHFLSHR1` are used: the stalling logic does not realize that these modes of `SFPSHFT2` read anything.
> * `SFPSHFT2` when `SFPSHFT2_MOD1_SHFT_LREG` or `SFPSHFT2_MOD1_SHFT_IMM` are used: the stalling logic thinks that these modes of `SFPSHFT2` read from `VD` whereas they actually read from `VB`.
>
> If `SFPMAD` is followed by one of the above cases, with `SFPMAD` writing to a location which is not detected by the automatic stalling logic, software must ensure a gap of at least one cycle between `SFPMAD` and the consuming instruction. An [`SFPNOP`](SFPNOP.md) instruction can be inserted to ensure this.

## Performance

Each `SFPMAD` instruction can perform 32 FP32 multiplications and 32 FP32 additions, for 64 FP32 operations total. Running at Blackhole's standard 1.35 GHz clock rate, this gives 0.0864 TFLOP/s (per Vector Unit). To hit this number whilst simultaneously moving data in and out of the Vector Unit (SFPU), [`SFPLOADMACRO`](SFPLOADMACRO.md) needs to be used.
