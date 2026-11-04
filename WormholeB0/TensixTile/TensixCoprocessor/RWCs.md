# RWCs

Matrix Unit (FPU) and Vector Unit (SFPU) instructions assume the presence of the following global variable:

```c
struct {
  uint10_t Dst, Dst_Cr;
  uint6_t SrcA, SrcA_Cr;
  uint6_t SrcB, SrcB_Cr;
  uint2_t FidelityPhase;
  uint1_t ExtraAddrModBit;
  uint10_t Sp; // Blackhole only: the SFPLOAD / SFPSTORE stack pointer
} RWCs[3];
```

The `[3]` is always indexed as `[CurrentThread]`, i.e. each Tensix thread has its own set of RWCs, and each thread has exclusive access to its own RWCs (there is no cross-thread access).

Matrix Unit (FPU) and Vector Unit (SFPU) instructions use RWCs as auto-incrementing addressing counters: the initial values of `RWCs[CurrentThread].Dst` and `RWCs[CurrentThread].SrcA` and `RWCs[CurrentThread].SrcB` help to specify which row(s) of [`Dst`](Dst.md) and [`SrcA`](SrcASrcB.md) and [`SrcB`](SrcASrcB.md) the instruction accesses, and then the instruction can specify how to increment these counters in preparation for the next instruction. The same is true of `RWCs[CurrentThread].FidelityPhase`, albeit instead of specifying a row, it specifies which one of four possible fidelity phases are in use for multiplications performed by the Matrix Unit (FPU).

There are not enough instruction bits to specify all of the required counter increments directly within an instruction, so a layer of indirection is used: an instruction uses two bits (three on Blackhole) to specify an index into an array of pre-configured increments. These bits are called the `AddrMod` bits, and the `ApplyAddrMod` function describes how these bits are used:

```c
void ApplyAddrMod(uint3_t AddrMod, bool UpdateFidelityPhase = true) {
  auto& RWC = RWCs[CurrentThread];
  uint3_t Index = AddrMod;
  if (TTArchitecture == Wormhole && (RWC.ExtraAddrModBit || ThreadConfig[CurrentThread].ADDR_MOD_SET_Base)) {
    Index += 4;
  }
  auto& AB = ThreadConfig[CurrentThread].ADDR_MOD_AB_SEC[Index];
  auto& Dst = ThreadConfig[CurrentThread].ADDR_MOD_DST_SEC[Index];
  auto& Bias = ThreadConfig[CurrentThread].ADDR_MOD_BIAS_SEC[Index];

  if (AB.SrcAClear) RWC.SrcA = 0, RWC.SrcA_Cr = 0;
  else if (AB.SrcACR) RWC.SrcA_Cr += AB.SrcAIncr, RWC.SrcA = RWC.SrcA_Cr;
  else RWC.SrcA += AB.SrcAIncr;

  if (AB.SrcBClear) RWC.SrcB = 0, RWC.SrcB_Cr = 0;
  else if (AB.SrcBCR) RWC.SrcB_Cr += AB.SrcBIncr, RWC.SrcB = RWC.SrcB_Cr;
  else RWC.SrcB += AB.SrcBIncr;

  if (Dst.DestClear) RWC.Dst = 0, RWC.Dst_Cr = 0;
  else if (Dst.DestCToCR) RWC.Dst += Dst.DestIncr, RWC.Dst_Cr = RWC.Dst;
  else if (Dst.DestCR) RWC.Dst_Cr += Dst.DestIncr, RWC.Dst = RWC.Dst_Cr;
  else RWC.Dst += Dst.DestIncr;

  if (UpdateFidelityPhase) {
    // SFPLOAD / SFPSTORE / SFPLOADMACRO do not update FidelityPhase, all other instructions do.
    if (Dst.FidelityClear) RWC.FidelityPhase = 0;
    else RWC.FidelityPhase += Dst.FidelityIncr;
  }

  if (Bias.BiasIncr & 3) RWC.ExtraAddrModBit += 1;
  else if (Bias.BiasClear) RWC.ExtraAddrModBit = 0;
}

void ApplyPartialAddrMod(uint3_t AddrMod) {
  ApplyAddrMod(AddrMod, /* UpdateFidelityPhase = */ false);
}
```

## Instructions

The [`SETRWC`](SETRWC.md) and [`INCRWC`](INCRWC.md) instructions exist purely to manipulate RWCs. Other instructions consume RWCs and use two `AddrMod` bits to specify the desired manipulation to RWCs:
* Matrix multiplication: [`MVMUL`](MVMUL.md), [`DOTPV`](DOTPV.md), [`GAPOOL`](GAPOOL.md)
* Element-wise operations: [`ELWMUL`](ELWMUL.md), [`ELWADD`](ELWADD.md), [`ELWSUB`](ELWSUB.md)
* Columnar reduction: [`GMPOOL`](GMPOOL.md)
* Data movement: [`SHIFTXB`](SHIFTXB.md), [`MOVA2D`](MOVA2D.md), [`MOVDBGA2D`](MOVDBGA2D.md), [`MOVB2A`](MOVB2A.md), [`MOVB2D`](MOVB2D.md), [`MOVD2A`](MOVD2A.md), [`MOVD2B`](MOVD2B.md)
* Clearing: [`ZEROACC`](ZEROACC.md) (some modes only)
* Legacy: `MFCONV3S1`, `CONV3S1`, `CONV3S2`, `MPOOL3S1`, `MPOOL3S2`, `APOOL3S1`, `APOOL3S2`
* Vector: [`SFPLOAD`](SFPLOAD.md), [`SFPLOADMACRO`](SFPLOADMACRO.md), [`SFPSTORE`](SFPSTORE.md) (though they neither consume nor increment `FidelityPhase`)

The [`SETC16`](SETC16.md) instruction is used to set the various bits of `ThreadConfig` which are used to apply the two `AddrMod` bits.

In a few cases, the `AddrMod` bits are able to perform a manipulation which the [`SETRWC`](SETRWC.md) and [`INCRWC`](INCRWC.md) instructions are incapable of. In these cases, it can sometimes be useful to have an instruction which doesn't _consume_ RWCs, but still has `AddrMod` bits and applies them to RWCs. It is possible to use [`SFPLOAD`](SFPLOAD.md) for this purpose: if `VD` is 8 or more and `Mod0` is not `MOD0_FMT_INT32_ALL`, then the instruction will do nothing other than `ApplyPartialAddrMod(AddrMod)`, which leaves `FidelityPhase` unchanged. [`ZEROACC`](ZEROACC.md) with `Mode = ZEROACC_MODE_16_ROWS` and `Imm10 = 0xff` is not suitable: on Wormhole it applies `AddrMod` and clears nothing only as `NonContractualBehavior`, and on Blackhole it clears 16 rows of `Dst`. Nor are the `...3S1` and `...3S2` instructions, as they compute `Dst += 0` (see [Matrix Unit](MatrixUnit.md)).

## See also

Packers and unpackers instead use [ADCs](ADCs.md) as their auto-incrementing addressing counters.
