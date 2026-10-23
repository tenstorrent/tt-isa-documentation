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
  NonContractualBehavior {
    // Current silicon behavior (not architecturally guaranteed): only the low 6 bits of CfgIndex are used. Where they
    // are below THD_STATE_SIZE, ThreadConfig[CurrentThread][CfgIndex % 64] is written as by an in-range SETC16, except
    // that writing the UNPACK_MISC_CFG_CfgContextCntReset fields this way does not reset the unpacker configuration
    // context counters (see "Special cases" in BackendConfiguration.md); otherwise nothing is written.
    if ((CfgIndex % 64) < THD_STATE_SIZE) {
      ThreadConfig[CurrentThread][CfgIndex % 64].Value = NewValue;
    }
    return;
  }
}

ThreadConfig[CurrentThread][CfgIndex].Value = NewValue;
```

Note that `CfgIndex` values line up exactly with the `Name_ADDR32` constants in `cfg_defines.h`, but only for the `// Registers for THREAD` section of `cfg_defines.h` (use [`WRCFG`](WRCFG.md) for all other sections of `cfg_defines.h`).
