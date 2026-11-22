# `SHIFTXA` (Shift 16 rows of `SrcA` left or right by one lane)

**Summary:** An aligned block of 16 rows of `SrcA` is shifted left or right by one lane, with the vacant lane filled with zero, and written to the first 16 rows of `SrcA`. On Wormhole, a hardware bug makes it difficult to choose the block; on Blackhole, the block is always the first 16 rows. This instruction is `UnsupportedFunctionality` and its use is strongly discouraged.

**Backend execution unit:** [Matrix Unit (FPU)](MatrixUnit.md)

## Syntax

```c
TT_SHIFTXA(0, /* u2 */ Direction)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SHIFTXA.svg)

## Cross-lane data movement pattern

When `Direction==DIRECTION_RIGHT`:

![](../../../Diagrams/Out/CrossLane_SHIFTXA2.svg)

When `Direction==DIRECTION_LEFT`:

![](../../../Diagrams/Out/CrossLane_SHIFTXA3.svg)

## Functional model

This instruction will, if necessary, spend time waiting at the Wait Gate before being dispatched to the Matrix Unit (FPU):

```c
while (SrcA[MatrixUnit.SrcABank].AllowedClient != MatrixUnit) {
  wait;
}
```

Once dispatched to the Matrix Unit (FPU):
```c
UnsupportedFunctionality(); // No known usage
if (Direction != DIRECTION_RIGHT && Direction != DIRECTION_LEFT) {
  return; // SrcA is not changed
}
uint4_t SrcAFmt = ConfigState.ALU_FORMAT_SPEC_REG_SrcA_override ? ConfigState.ALU_FORMAT_SPEC_REG_SrcA_val : ConfigState.ALU_FORMAT_SPEC_REG0_SrcA;
uint6_t InRow = (TTArchitecture == Wormhole) ? (HardwareBug() & 0x30) : 0;

for (unsigned i = 0; i < 16; ++i) {
  uint19_t In[16];
  for (unsigned Column = 0; Column < 16; ++Column) {
    In[Column] = TruncateSrc(SrcA[MatrixUnit.SrcABank][InRow + i][Column], SrcAFmt);
  }
  switch (Direction) {
  case DIRECTION_RIGHT:
    for (unsigned Column = 15; Column > 0; --Column) {
      SrcA[MatrixUnit.SrcABank][i][Column] = In[Column - 1];
    }
    SrcA[MatrixUnit.SrcABank][i][0] = 0;
    break;
  case DIRECTION_LEFT:
    for (unsigned Column = 0; Column < 15; ++Column) {
      SrcA[MatrixUnit.SrcABank][i][Column] = In[Column + 1];
    }
    SrcA[MatrixUnit.SrcABank][i][15] = 0;
    break;
  }
}
```

Due to a hardware bug, `SHIFTXA` on Wormhole cannot specify which aligned block of 16 rows to use as input. The call to `HardwareBug()` in the above description evaluates to whatever the most recent `MFCONV3S1`, `CONV3S1`, `MPOOL3S1`, `APOOL3S1`, `CONV3S2`, `MPOOL3S2`, `APOOL3S2`, `MVMUL`, `ELWSUB`, `ELWADD`, `ELWMUL`, `DOTPV`, `GMPOOL`, `GAPOOL`, `MOVA2D`, `MOVB2D`, `MOVD2A`, `MOVD2B`, or `MOVB2A` instruction computed as its (starting) `SrcA` row address: its `SrcA` row field (if it has one) plus the `SrcA` RWC, before `AddrMod` is applied. Other instructions, `SHIFTXA` included, leave it unchanged. This is a `NonContractualBehavior`. On Blackhole, the input is always the first 16 rows of `SrcA`, shifted in place.

The truncation by `TruncateSrc` happens on Wormhole only (see [`MatrixUnit.md`](MatrixUnit.md#pseudocode-helpers)); on Blackhole, all 19 bits of each datum move unchanged. `SHIFTXA` leaves the RWCs unchanged.

Supporting definitions:
```c
#define DIRECTION_RIGHT 2
#define DIRECTION_LEFT  3
```
