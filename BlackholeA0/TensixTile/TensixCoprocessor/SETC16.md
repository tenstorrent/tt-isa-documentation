# `SETC16` (Write 16 bits to thread-specific backend configuration)

**Summary:** Write 16 bits to thread-specific backend configuration. Writes are always performed against the configuration bank specific to the thread issuing the instruction.

**Backend execution unit:** [Configuration Unit](ConfigurationUnit.md)

## Syntax

```c
TT_SETC16(/* u8 */ CfgIndex, /* u16 */ NewValue)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SETC16.svg)

## Functional model

```c
if (CfgIndex >= THD_STATE_SIZE) {
  if (CfgIndex == 128) {
    // Writes CFG_STATE_ID_StateID, but Auto TTSync does not see the change.
    UndefinedBehavior();
  }
  NonContractualBehavior {
    // Current silicon behavior (not architecturally guaranteed): CfgIndex 129 through 128 + THD_STATE_SIZE - 1
    // write ThreadConfig[CurrentThread][CfgIndex - 128], but without the immediate effects that a write of that
    // index has (see "Special cases" in BackendConfiguration.md); other values write nothing.
    if (CfgIndex > 128 && CfgIndex < 128 + THD_STATE_SIZE) {
      ThreadConfig[CurrentThread][CfgIndex - 128].Value = NewValue;
    }
    return;
  }
}

ThreadConfig[CurrentThread][CfgIndex].Value = NewValue;
```

Note that `CfgIndex` values line up exactly with the `Name_ADDR32` constants in `cfg_defines.h`, but only for the `// Registers for THREAD` section of `cfg_defines.h` (use [`WRCFG`](WRCFG.md) for all other sections of `cfg_defines.h`).

## Instruction scheduling

When `CfgIndex == CFG_STATE_ID_StateID_ADDR32`, some scheduling restrictions apply to work around hardware bugs in Auto TTSync:
1. After coming out of reset, `TT_SETC16(CFG_STATE_ID_StateID_ADDR32, x)` needs to be executed for _some_ `x`.
2. The RISCV frontend can fuse together up to four adjacent `.ttinsn` instructions. If any instruction within a fused bundle is `TT_SETC16(CFG_STATE_ID_StateID_ADDR32, x)`, software must ensure that any instructions after it in the bundle do not depend upon the value `x`.
