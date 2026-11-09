# `ADDDMAREG` (Perform addition on GPRs)

**Summary:** Performs addition between two Tensix GPRs, or between a Tensix GPR and an unsigned 6-bit immediate.

The `RightImm6` variant is `UnsupportedFunctionality`, and its use is strongly discouraged; use the `RightReg` variant, with the constant in a GPR, instead.

**Backend execution unit:** [Scalar Unit (ThCon)](ScalarUnit.md)

## Syntax

```c
TT_ADDDMAREG(0, /* u6 */ ResultReg, /* u6 */ RightReg , /* u6 */ LeftReg)
TT_ADDDMAREG(1, /* u6 */ ResultReg, /* u6 */ RightImm6, /* u6 */ LeftReg)
```

## Encoding

![](../../../Diagrams/Out/Bits32_ADDDMAREG.svg)
![](../../../Diagrams/Out/Bits32_ADDDMAREGi.svg)

## Functional model

```c
uint32_t LeftVal = GPRs[CurrentThread][LeftReg];
uint32_t RightVal = GPRs[CurrentThread][RightReg]; // RightReg  variant
UnsupportedFunctionality();                        // RightImm6 variant
uint32_t RightVal = RightImm6;                     // RightImm6 variant
uint32_t ResultVal = LeftVal + RightVal;
GPRs[CurrentThread][ResultReg] = ResultVal;
```

## Performance

The `RightImm6` variant takes three cycles. The `RightReg` variant takes three cycles if `LeftReg` and `RightReg` come from the same aligned group of four GPRs, or four cycles otherwise.
