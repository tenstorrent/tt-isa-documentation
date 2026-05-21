# `SFPADD` (Vectorized floating-point addition)

**Summary:** Identical to [`SFPMAD`](SFPMAD.md), but is the preferred opcode when `VA == 10`, as this causes the computation to be lanewise FP32 `VD = 1.0 * VB + VC` (see the definition of [`LReg[10]`](LReg.md)). Do not use this instruction unless `VA == 10`; use `SFPMAD` instead for other cases.

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), MAD sub-unit

## Syntax

```c
TT_SFPADD(/* u4 */ VA, /* u4 */ VB, /* u4 */ VC, /* u4 */ VD, /* u4 */ Mod1)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPADD.svg)

## Functional model

As per [`SFPMAD`](SFPMAD.md#functional-model).

## IEEE754 conformance / divergence

As per [`SFPMAD`](SFPMAD.md#ieee754-conformance--divergence).

## Instruction scheduling

If `SFPADD` is used, software must ensure that on the next cycle, the Vector Unit (SFPU) does not execute an instruction which reads from any location written to by the `SFPADD`. An [`SFPNOP`](SFPNOP.md) instruction can be inserted to ensure this.
