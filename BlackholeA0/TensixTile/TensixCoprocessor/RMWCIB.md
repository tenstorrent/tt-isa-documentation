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

Note that `CfgAddress` values line up exactly with the `Name_ADDR32` constants in `cfg_defines.h`, though be aware that the `// Registers for THREAD` section of `cfg_defines.h` is for indexing into `ThreadConfig` rather than `Config` (see [`SETC16`](SETC16.md) for that).

## Instruction scheduling

Matrix Unit (FPU) instructions take `ALU_ACC_CTRL_Zero_Flag_disabled_src` from the configuration as they are issued, so changing it with `RMWCIB` needs no `STALLWAIT` before or after: Matrix Unit instructions ahead of the `RMWCIB` in the thread's instruction stream use the old value, even while they wait behind earlier Matrix Unit work or for their `SrcA` / `SrcB` bank, and the instruction right after it uses the new value.

The same holds for `ALU_FORMAT_SPEC_REG0_SrcA` (used when `DISABLE_IMPLIED_SRCA_FMT` is set) and `ALU_ACC_CTRL_Fp32_enabled`, which software changes with `RMWCIB` between `MOVD2B` / `MOVB2D` / `MOVA2D` instructions to move the high and low halves of 32-bit `Dst` datums separately: each instruction uses the values written before it in the thread's instruction stream.

## Performance

This instruction executes in a single cycle, though if the Configuration Unit is busy with other instructions, it might have to wait at the Wait Gate until the Configuration Unit can accept it.
