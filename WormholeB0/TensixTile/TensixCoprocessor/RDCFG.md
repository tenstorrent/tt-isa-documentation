# `RDCFG` (Move from thread-agnostic backend configuration to GPRs)

**Summary:** Move 32 bits from thread-agnostic backend configuration to a Tensix GPR. The current thread's `CFG_STATE_ID_StateID` determines which configuration bank is read from. This instruction cannot be used to read from `ThreadConfig`.

**Backend execution unit:** [Configuration Unit](ConfigurationUnit.md)

## Syntax

```c
TT_RDCFG(/* u6 */ ResultReg, /* u11 */ CfgIndex)
```

## Encoding

![](../../../Diagrams/Out/Bits32_RDCFG.svg)

## Functional model

```c
if (CfgIndex >= (CFG_STATE_SIZE*4)) UndefinedBehavior(); // Cannot index out of bounds.

uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
GPRs[CurrentThread][ResultReg] = Config[StateID][CfgIndex];
```

Note that `CfgIndex` values line up exactly with the `Name_ADDR32` constants in `cfg_defines.h`, though be aware that the `// Registers for THREAD` section of `cfg_defines.h` is for indexing into `ThreadConfig` rather than `Config`.

## Performance

This instruction requires at least two cycles to execute, and then additional cycles if there is contention for GPR writes. The issuing thread is blocked for the entire duration, though there is pipelining within the Configuration Unit allowing _other_ threads to start other Configuration Unit instructions during `RDCFG`'s subsequent cycles.

## Instruction scheduling

Due to a hardware bug, if multiple threads issue `RDCFG` instructions on the same cycle, then one of those instructions will execute but the others will be silently dropped. Accordingly, if software uses `RDCFG`, it must ensure that it does not do so from multiple threads simultaneously.
