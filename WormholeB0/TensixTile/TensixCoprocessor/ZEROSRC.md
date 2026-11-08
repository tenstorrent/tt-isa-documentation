# `ZEROSRC` (Set `SrcA` and/or `SrcB` to zero)

**Summary:** Set either all or half of `SrcA` or `SrcB` (or both) to `0` or floating-point negative infinity (`SrcA` only, and Wormhole only).

Only two forms are supported: clearing both banks of both `SrcA` and `SrcB` (`BothBanks` alone), and clearing the Matrix Unit's current bank of `SrcA` and/or `SrcB` (`SingleBankMatrixUnit` alone). Every other form, including `NegativeInfSrcA`, is `UnsupportedFunctionality`.

**Backend execution unit:** [Matrix Unit (FPU)](MatrixUnit.md)

## Syntax

```c
TT_ZEROSRC(/* bool */ NegativeInfSrcA,
           /* bool */ SingleBankMatrixUnit,
           /* bool */ BothBanks,
         ((/* bool */ ClearSrcB) << 1) +
           /* bool */ ClearSrcA)
```

## Encoding

![](../../../Diagrams/Out/Bits32_ZEROSRC.svg)

## Functional model

```c
if (NegativeInfSrcA) UnsupportedFunctionality(); // No known usage
if (!ClearSrcA && !ClearSrcB) UnsupportedFunctionality(); // Clears nothing: most likely a software bug
if (BothBanks && (SingleBankMatrixUnit || !ClearSrcA || !ClearSrcB)) UnsupportedFunctionality(); // No known usage
if (!BothBanks && !SingleBankMatrixUnit) UnsupportedFunctionality(); // No known usage

// Determine what to clear.
bool ClearSrcABank[2] = {false, false};
bool ClearSrcBBank[2] = {false, false};
if (ClearSrcA) {
  if (BothBanks) {
    ClearSrcABank[0] = true;
    ClearSrcABank[1] = true;
  } else if (SingleBankMatrixUnit) {
    ClearSrcABank[MatrixUnit.SrcABank] = true;
  } else {
    ClearSrcABank[Unpackers[0].SrcBank] = true;
  }
}
if (ClearSrcB) {
  if (BothBanks) {
    ClearSrcBBank[0] = true;
    ClearSrcBBank[1] = true;
  } else if (SingleBankMatrixUnit) {
    ClearSrcBBank[MatrixUnit.SrcBBank] = true;
  } else {
    ClearSrcBBank[Unpackers[1].SrcBank] = true;
  }
}

// Do the clearing.
for (unsigned Bank = 0; Bank < 2; ++Bank) {
  for (unsigned i = 0; i < 64; ++i) {
    for (unsigned j = 0; j < 16; ++j) {
      if (ClearSrcABank[Bank]) SrcA[Bank][i][j] = (NegativeInfSrcA && TTArchitecture != Blackhole) ? ~0u : 0u;
      if (ClearSrcBBank[Bank]) SrcB[Bank][i][j] = 0u;
    }
  }
}

// Note: Blackhole implied format behavior not characterized
```

## Instruction scheduling

If clearing just a single bank, software may wish to use [`STALLWAIT`](STALLWAIT.md) (with block bit B6 and some of condition codes C8 through C11) prior to using `ZEROSRC`.

`ZEROSRC` does not wait for unpack instructions that are still writing to `SrcA` or `SrcB`. If an [`UNPACR`](UNPACR.md) that writes a bank this `ZEROSRC` clears may still be in progress, some of its datums can land after the clear, leaving that data in the bank instead of zeros; on Wormhole this happens whether `ZEROSRC` clears one bank or both. Use `STALLWAIT` with block bit B6 and condition codes C1 and/or C2 (the Unpackers that may still be writing) before such a `ZEROSRC`.

If an Unpacker's [`UNPACR_NOP`](UNPACR_NOP_ZEROSRC.md) clears a bank in the same cycle as a `ZEROSRC` with `SingleBankMatrixUnit` or `BothBanks` set, the `UNPACR_NOP` clears the Matrix Unit's current bank of its register (or both banks, for `BothBanks`) rather than the Unpacker's own bank, even if this `ZEROSRC` does not clear that register. The two also share the `SrcA` clear value whenever they coincide; see [`UNPACR_NOP`'s instruction scheduling](UNPACR_NOP_ZEROSRC.md#instruction-scheduling).
