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
if (Index4 >= (CFG_STATE_SIZE*4)) UndefinedBehaviour(); // Cannot write to three-copy configuration

uint1_t StateID = ThreadConfig[CurrentThread].CFG_STATE_ID_StateID;
uint8_t* CfgAddress = (uint8_t*)&Config[StateID][Index4] + Index1;
atomic {
  uint8_t OldValue = *CfgAddress;
  *CfgAddress = (NewValue & Mask) | (OldValue & ~Mask);
}
```

Note that `CfgAddress` values line up exactly with the `Name_ADDR32` constants in `cfg_defines.h`, though be aware that the `// Registers for THREAD` section of `cfg_defines.h` is for indexing into `ThreadConfig` rather than `Config` (see [`SETC16`](SETC16.md) for that).

## Performance

This instruction executes in a single cycle, though if the Configuration Unit is busy with other instructions, it might have to wait at the Wait Gate until the Configuration Unit can accept it.
