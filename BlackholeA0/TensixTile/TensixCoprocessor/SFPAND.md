# `SFPAND` (Vectorized bitwise-and)

**Summary:** Performs lanewise bitwise-and between two vectors of 32-bit unsigned integers.

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), simple sub-unit

> [!TIP]
> Compared to Wormhole, the major upgrade to `SFPAND` in Blackhole is the `SFPAND_MOD1_USE_VB` modifier.

## Syntax

```c
TT_SFPAND(/* u4 */ VB, /* u4 */ VC, /* u4 */ VD, /* u4 */ Mod1)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPAND_BH.svg)

## Functional model

```c
unsigned vb = (Mod1 & SFPAND_MOD1_USE_VB) ? VB : VD;
if (VD < 8 || VD == 16) {
  lanewise {
    if (LaneEnabled) {
      LReg[VD].u32 = LReg[vb].u32 & LReg[VC].u32;
    }
  }
}
```

Supporting definitions:

```c
#define SFPAND_MOD1_USE_VB 1
```
