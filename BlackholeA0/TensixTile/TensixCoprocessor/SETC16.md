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
if (CfgIndex >= THD_STATE_SIZE) UndefinedBehavior(); // Cannot index out of bounds.

ThreadConfig[CurrentThread][CfgIndex].Value = NewValue;
```

Note that `CfgIndex` values line up exactly with the `Name_ADDR32` constants in `cfg_defines.h`, but only for the `// Registers for THREAD` section of `cfg_defines.h` (use [`WRCFG`](WRCFG.md) for all other sections of `cfg_defines.h`).

## Instruction scheduling

When `CfgIndex == CFG_STATE_ID_StateID_ADDR32`, some scheduling restrictions apply to work around hardware bugs in Auto TTSync:
1. After coming out of reset, `TT_SETC16(CFG_STATE_ID_StateID_ADDR32, x)` needs to be executed for _some_ `x`.
2. The RISCV frontend can fuse together up to four adjacent `.ttinsn` instructions. If any instruction within a fused bundle is `TT_SETC16(CFG_STATE_ID_StateID_ADDR32, x)`, software must ensure that any instructions after it in the bundle do not depend upon the value `x`.
