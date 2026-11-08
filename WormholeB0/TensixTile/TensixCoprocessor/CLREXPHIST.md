# `CLREXPHIST` (Reset packer exponent histograms)

**Summary:** Resets the [exponent histogram](Packers/ExponentHistogram.md) of all four packers.

This instruction is `UnsupportedFunctionality` and its use is strongly discouraged: it has no known usage.

**Backend execution unit:** [Matrix Unit (FPU)](MatrixUnit.md)

## Syntax

```c
TTI_CLREXPHIST
```

## Encoding

![](../../../Diagrams/Out/Bits32_CLREXPHIST.svg)

## Functional model

Use of this instruction is `UnsupportedFunctionality`.

Invokes [the `Reset` function](Packers/ExponentHistogram.md#functional-model) on the exponent histogram of all four packers.
