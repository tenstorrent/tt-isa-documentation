# `SFPCAST` (Vectorized two's complement integer absolute value)

**Summary:** Performs lanewise absolute value on a vector of two's complement integers. This encoding of `SFPCAST` was intended to do something else, but due to a hardware bug, it ends up computing the absolute value. It is documented merely so that all encodings of `SFPCAST` have defined behavior; software is strongly encouraged to use [`SFPABS`](SFPABS.md) rather than this encoding of `SFPCAST`.

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), simple sub-unit

## Syntax

```c
TT_SFPCAST(/* u4 */ VC, /* u4 */ VD, /* u4 */ Mod1)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPCAST.svg)

## Functional model

```c
if ((Mod1 & 3) != SFPCAST_MOD1_INT32_ABS) {
  // Is some other flavour of SFPCAST; see other pages for details.
  UndefinedBehavior();
}

if (VD < 8 || VD == 16) {
  lanewise {
    if (LaneEnabled) {
      uint32_t x = LReg[VC].u32;
      if (x >= 0x80000000u) {
        // Sign bit is set, i.e. value is negative.
        // Two's complement integer negation, unless the input is
        // -2147483648, in which case it remains as -2147483648.
        x = -x;
      } else {
        // Value is positive (or zero); leave it as-is.
      }
      LReg[VD].u32 = x;
    }
  }
}
```

Supporting definitions:
```c
#define SFPCAST_MOD1_INT32_ABS 2
```
