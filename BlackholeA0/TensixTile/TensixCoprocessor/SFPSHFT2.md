# `SFPSHFT2` (Vector shuffle or vector bitwise shift)

**Summary:** Performs some kind of bitwise shift within vector lanes, or some kind of shuffle of vector lanes. The exact behaviour is determined by the `Mod1` field; see the functional model for descriptions of each mode.

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), round sub-unit

> [!TIP]
> Compared to Wormhole, the major upgrades to `SFPSHFT2` in Blackhole are fixing the hardware bug in `SFPSHFT2_MOD1_SUBVEC_SHFLSHR1` and automatic instruction scheduling.

## Syntax

```c
TT_SFPSHFT2(/*  u4 */ VB,    /* u4 */ VC, /* u4 */ VD, /* u4 */ Mod1)
TT_SFPSHFT2(/* i12 */ (Imm12 & 0xfff), 0, /* u4 */ VD, /* u4 */ Mod1)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPSHFT2.svg)

![](../../../Diagrams/Out/Bits32_SFPSHFT2b.svg)

## Cross-lane data movement pattern

Some modes of this instruction involve cross-lane data movement. Assuming all 32 lanes active:

### `SFPSHFT2_MOD1_COPY4`

This mode does not actually involve any cross-lane data movement (merely lanewise movement between registers), but the diagram is included here for reference.

![](../../../Diagrams/Out/CrossLane_COPY4.svg)

### `SFPSHFT2_MOD1_SUBVEC_CHAINED_COPY4`

![](../../../Diagrams/Out/CrossLane_CHAINED_COPY4.svg)

### `SFPSHFT2_MOD1_SUBVEC_SHFLROR1_AND_COPY4`

![](../../../Diagrams/Out/CrossLane_SHFLROR1_AND_COPY4.svg)

### `SFPSHFT2_MOD1_SUBVEC_SHFLROR1`

![](../../../Diagrams/Out/CrossLane_SHFLROR1.svg)

### `SFPSHFT2_MOD1_SUBVEC_SHFLSHR1`

![](../../../Diagrams/Out/CrossLane_SHFLSHR1_BH.svg)

## Functional model

```c
switch (Mod1) {
case SFPSHFT2_MOD1_COPY4: // (Mod1 == 0)
  // Within each lane, shuffle L0 / L1 / L2 / L3.
  lanewise {
    if (VD < 12 || LaneConfig.DISABLE_BACKDOOR_LOAD) {
      if (LaneEnabled) {
        LReg[0] = LReg[1];
        LReg[1] = LReg[2];
        LReg[2] = LReg[3];
        LReg[3] = 0;
      }
    }
  }
  break;
case SFPSHFT2_MOD1_SUBVEC_CHAINED_COPY4: {
  // Within each lane, shuffle L0 / L1 / L2 / L3, then shift the original L0 left
  // by eight lanes and assign it to L3.
  auto v0 = LReg[0];
  for (unsigned Lane = 0; Lane < 32; ++Lane) {
    if (VD < 12 || LaneConfig[Lane].DISABLE_BACKDOOR_LOAD) {
      if (LaneEnabled[Lane]) {
        LReg[0][Lane] = LReg[1][Lane];
        LReg[1][Lane] = LReg[2][Lane];
        LReg[2][Lane] = LReg[3][Lane];
        LReg[3][Lane] = Lane < 24 ? v0[Lane + 8] : 0;
      }
    }
  }
  break; }
case SFPSHFT2_MOD1_SUBVEC_SHFLROR1_AND_COPY4:
  // Within each lane, shuffle L0 / L1 / L2 / L3, then within each group of eight
  // lanes of the original VC, rotate lanes right by one lane and assign to L3.
  if (VD < 12 || LaneConfig.DISABLE_BACKDOOR_LOAD) {
    auto vc = LReg[VC];
    for (unsigned Lane = 0; Lane < 32; ++Lane) {
      if (LaneEnabled[Lane]) {
        LReg[0][Lane] = LReg[1][Lane];
        LReg[1][Lane] = LReg[2][Lane];
        LReg[2][Lane] = LReg[3][Lane];
        LReg[3][Lane] = Lane & 7 ? vc[Lane - 1] : vc[Lane + 7];
      }
    }
  }
  break;
case SFPSHFT2_MOD1_SUBVEC_SHFLROR1:
  // Within each group of eight lanes, rotate lanes right by one lane.
  if (VD < 12 || LaneConfig.DISABLE_BACKDOOR_LOAD) {
    auto vc = LReg[VC];
    if (VD < 8 || VD == 16) {
      for (unsigned Lane = 0; Lane < 32; ++Lane) {
        if (LaneEnabled[Lane]) {
          LReg[VD][Lane] = Lane & 7 ? vc[Lane - 1] : vc[Lane + 7];
        }
      }
    }
  }
  break;
case SFPSHFT2_MOD1_SUBVEC_SHFLSHR1:
  // Within each group of eight lanes, shift lanes right by one lane.
  if (VD < 8 || VD == 16) {
    auto vc = LReg[VC];
    for (unsigned Lane = 0; Lane < 32; ++Lane) {
      if (LaneEnabled[Lane]) {
        LReg[VD][Lane] = Lane & 7 ? vc[Lane - 1] : 0;
      }
    }
  }
  break;
case SFPSHFT2_MOD1_SHFT_LREG:
  // Within each lane, shift bits left or right.
  if (VD < 8 || VD == 16) {
    lanewise {
      if (LaneEnabled) {
        int32_t vc = LReg[VC].i32;
        if (vc >= 0) {
          LReg[VD].u32 = LReg[VB].u32 << (vc & 31);
        } else {
          LReg[VD].u32 = LReg[VB].u32 >> ((-vc) & 31);
        }
      }
    }
  }
  break;
case SFPSHFT2_MOD1_SHFT_IMM:
  // This mode has limited use; see SFPSHFT for a more useful alternative.
  if (VD < 8 || VD == 16) {
    lanewise {
      if (LaneEnabled) {
        unsigned VB = Imm12 & 15;
        if (Imm12 >= 0) {
          LReg[VD].u32 = LReg[VB].u32 << (Imm12 & 31);
        } else {
          LReg[VD].u32 = LReg[VB].u32 >> ((-Imm12) & 31);
        }
      }
    }
  }
  break;
default:
  UndefinedBehavior();
}
```

Supporting definitions:
```c
#define SFPSHFT2_MOD1_COPY4 0
#define SFPSHFT2_MOD1_SUBVEC_CHAINED_COPY4 1
#define SFPSHFT2_MOD1_SUBVEC_SHFLROR1_AND_COPY4 2
#define SFPSHFT2_MOD1_SUBVEC_SHFLROR1 3
#define SFPSHFT2_MOD1_SUBVEC_SHFLSHR1 4
#define SFPSHFT2_MOD1_SHFT_LREG 5
#define SFPSHFT2_MOD1_SHFT_IMM 6
```

## Instruction scheduling

If `SFPSHFT2_MOD1_SUBVEC_SHFLROR1_AND_COPY4` or `SFPSHFT2_MOD1_SUBVEC_SHFLROR1` or `SFPSHFT2_MOD1_SUBVEC_SHFLSHR1` are used, then on the next cycle, the only instruction that the Vector Unit (SFPU) can accept is `SFPNOP`. If a thread presents any other Vector Unit (SFPU) instruction, then hardware will automatically stall the thread for one cycle. As such, software does not _need_ to insert an `SFPNOP` instruction after these modes of `SFPSHFT2`, but if it does regardless, the sequence of `SFPSHFT2` and `SFPNOP` only requires two cycles rather than three.

> [!CAUTION]
> Automatic stalling does not apply to `SFPSHFT2` instructions executed as part of an [`SFPLOADMACRO`](SFPLOADMACRO.md) sequence. When constructing such sequences, software should ensure at least one idle cycle occurs after an `SFPSHFT2` instruction with `SFPSHFT2_MOD1_SUBVEC_SHFLROR1_AND_COPY4` or `SFPSHFT2_MOD1_SUBVEC_SHFLROR1` or `SFPSHFT2_MOD1_SUBVEC_SHFLSHR1`.
