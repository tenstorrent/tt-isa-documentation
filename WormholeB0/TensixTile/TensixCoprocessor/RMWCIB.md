# `RMWCIB` (Write up to 8 bits to thread-agnostic backend configuration)

**Summary:** Write up to 8 bits to thread-agnostic backend configuration. The current thread's `CFG_STATE_ID_StateID` determines which configuration bank is written to. This instruction cannot be used to write to `ThreadConfig` (see [`SETC16`](SETC16.md) for that).

**Backend execution unit:** [Configuration Unit](ConfigurationUnit.md)

## Syntax

```c
TT_RMWCIB0(/* u8 */ Mask, /* u8 */ NewValue, /* u8 */ Index4)
TT_RMWCIB1(/* u8 */ Mask, /* u8 */ NewValue, /* u8 */ Index4)
TT_RMWCIB2(/* u8 */ Mask, /* u8 */ NewValue, /* u8 */ Index4)
TT_RMWCIB3(/* u8 */ Mask, /* u8 */ NewValue, /* u8 */ Index4)
```

Note that `/* u2 */ Index1` is specified as the digit at the end of the instruction name.

## Encoding

![](../../../Diagrams/Out/Bits32_RMWCIB.svg)

## Functional model

```c
if (Index4 >= (CFG_STATE_SIZE*4)) {
  NonContractualBehavior {
    return; // Current silicon writes nothing and has no other effect (not architecturally guaranteed)
  }
}

uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
uint8_t* CfgAddress = (uint8_t*)&Config[StateID][Index4] + Index1;
atomic {
  uint8_t OldValue = *CfgAddress;
  *CfgAddress = (NewValue & Mask) | (OldValue & ~Mask);
}
```

Note that `CfgIndex` values line up exactly with the `Name_ADDR32` constants in `cfg_defines.h`, though be aware that the `// Registers for THREAD` section of `cfg_defines.h` is for indexing into `ThreadConfig` rather than `Config` (see [`SETC16`](SETC16.md) for that).

## Instruction scheduling

A Matrix Unit (FPU) instruction reads `ALU_ACC_CTRL_Zero_Flag_disabled_src` when it starts executing, not when it is issued, so if it is still waiting behind earlier Matrix Unit work, an `RMWCIB` of the flag issued after it can change how it treats `SrcA` and `SrcB` datums whose exponent is zero. To change the flag without affecting instructions already issued, first use `STALLWAIT` with block B7 and conditions C7 and C14. The instruction right after the `RMWCIB` uses the new value.

The `SrcA` data format (`ALU_FORMAT_SPEC_REG0_SrcA`, or `ALU_FORMAT_SPEC_REG_SrcA_val` when `ALU_FORMAT_SPEC_REG_SrcA_override` is set) is read the same way, so the same `STALLWAIT` is needed before an `RMWCIB` of it whenever the Matrix Unit instruction just before the `RMWCIB` might still be waiting behind earlier Matrix Unit work.

## Performance

This instruction executes in a single cycle, though if the Configuration Unit is busy with other instructions, it might have to wait at the Wait Gate until the Configuration Unit can accept it.
