# `SFPLUT` (Vectorised evaluate piecewise linear floating-point function)

**Summary:** Operating lanewise, performs one of the FP32 multiply then add variants from the following table:

|Input Range|Computation|
|---|---|
|0.0 ≤ `Abs(LReg[3])` < 1.0|`VD = Lut8ToFp32(LReg[0] >> 8) * Abs(LReg[3]) + Lut8ToFp32(LReg[0])`|
|1.0 ≤ `Abs(LReg[3])` < 2.0|`VD = Lut8ToFp32(LReg[1] >> 8) * Abs(LReg[3]) + Lut8ToFp32(LReg[1])`|
|2.0 ≤ `Abs(LReg[3])`      |`VD = Lut8ToFp32(LReg[2] >> 8) * Abs(LReg[3]) + Lut8ToFp32(LReg[2])`|

After this computation, the sign bit of the result can optionally be replaced with the original sign bit of `LReg[3]`. In another optional mode, the `VD` index from the instruction bits is ignored, and instead comes from the low four bits of `LReg[7]` (which allows these bits to potentially differ between lanes).

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), MAD sub-unit

## Syntax

```c
TT_SFPLUT(/* u4 */ VD, /* u4 */ Mod0, 0)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPLUT.svg)

## Functional model

```c
lanewise {
  if (VD < 12 || LaneConfig[Lane].DISABLE_BACKDOOR_LOAD) {
    if (LaneEnabled) {
      uint32_t l3 = LReg[3].u32;
      uint32_t b = l3 & 0x7FFFFFFF; // absolute value
      uint32_t coeffs = (b < 0x3F800000) ? LReg[0].u32 : // b < 1.0f
                        (b < 0x40000000) ? LReg[1].u32 : // b < 2.0f
                        LReg[2].u32;
      uint32_t a = Lut8ToFp32((coeffs >> 8) & 0xFF);
      uint32_t c = Lut8ToFp32( coeffs       & 0xFF);
      uint32_t d = fma_model(a, b, c); // compute a * b + c
      if (Mod0 & SFPLUT_MOD0_SGN_RETAIN) {
        d = (d & 0x7FFFFFFF) | (l3 & 0x80000000); // copy sign bit from l3
      }
      unsigned vd;
      if ((Mod0 & SFPLUT_MOD0_INDIRECT_VD) && VD != 16) {
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
#define SFPLUT_MOD0_SGN_RETAIN  4
#define SFPLUT_MOD0_INDIRECT_VD 8

uint32_t Lut8ToFp32(uint8_t x) {
  if (x == 0xff) return 0;
  uint32_t Sign = x >> 7;
  uint32_t Exp = (x >> 4) & 7;
  uint32_t Man = x & 0xf;
  return (Sign << 31) | ((127 - Exp) << 23) | (Man << 19);
}
```

Note that the 256 possible values of `Lut8ToFp32` are:

|Exp Bits|Possible values of `Lut8ToFp32`|
|---|---|
|`0b000`|±1.9375, ±1.875, ±1.8125, ±1.75, ±1.6875, ±1.625, ±1.5625, ±1.5,<br/>±1.4375, ±1.375, ±1.3125, ±1.25, ±1.1875, ±1.125, ±1.0625, ±1|
|`0b001`|±0.96875, ±0.9375, ±0.90625, ±0.875, ±0.84375, ±0.8125, ±0.78125, ±0.75,<br/>±0.71875, ±0.6875, ±0.65625, ±0.625, ±0.59375, ±0.5625, ±0.53125, ±0.5|
|`0b010`|±0.484375, ±0.46875, ±0.453125, ±0.4375, ±0.421875, ±0.40625, ±0.390625, ±0.375,<br/>±0.359375, ±0.34375, ±0.328125, ±0.3125, ±0.296875, ±0.28125, ±0.265625, ±0.25|
|`0b011`|±0.242188, ±0.234375, ±0.226563, ±0.21875, ±0.210938, ±0.203125, ±0.195313, ±0.1875,<br/>±0.179688, ±0.171875, ±0.164063, ±0.15625, ±0.148438, ±0.140625, ±0.132813, ±0.125|
|`0b100`|±0.121094, ±0.117188, ±0.113281, ±0.109375, ±0.105469, ±0.101563, ±0.0976563, ±0.09375,<br/>±0.0898438, ±0.0859375, ±0.0820313, ±0.078125, ±0.0742188, ±0.0703125, ±0.0664063, ±0.0625|
|`0b101`|±0.0605469, ±0.0585938, ±0.0566406, ±0.0546875, ±0.0527344, ±0.0507813, ±0.0488281, ±0.046875,<br/>±0.0449219, ±0.0429688, ±0.0410156, ±0.0390625, ±0.0371094, ±0.0351563, ±0.0332031, ±0.03125|
|`0b110`|±0.0302734, ±0.0292969, ±0.0283203, ±0.0273438, ±0.0263672, ±0.0253906, ±0.0244141, ±0.0234375,<br/>±0.0224609, ±0.0214844, ±0.0205078, ±0.0195313, ±0.0185547, ±0.0175781, ±0.0166016, ±0.015625|
|`0b111`|+0.0151367, ±0.0146484, ±0.0141602, ±0.0136719, ±0.0131836, ±0.0126953, ±0.012207, ±0.0117188,<br/>±0.0112305, ±0.0107422, ±0.0102539, ±0.00976563, ±0.00927734, ±0.00878906, ±0.00830078, ±0.0078125,<br/>0|

## IEEE754 conformance / divergence

The evaluation of `a * b + c` is as per [`SFPMAD`](SFPMAD.md#ieee754-conformance--divergence).

## Instruction scheduling

If `SFPLUT` is used, software must ensure that on the next cycle, the Vector Unit (SFPU) does not execute an instruction which reads from any location written to by the `SFPLUT`. An [`SFPNOP`](SFPNOP.md) instruction can be inserted to ensure this.
