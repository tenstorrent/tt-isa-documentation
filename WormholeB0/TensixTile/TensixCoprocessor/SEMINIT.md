# `SEMINIT` (Set the `Value` and `Max` of some semaphores)

**Summary:** Various semaphores are selected using a bitmask, and the selected semaphores have their `Value` and `Max` set to the provided values. `Max` is subsequently used by [`SEMWAIT`](SEMWAIT.md), and software should not [`SEMPOST`](SEMPOST.md) a semaphore whose `Value` is at or above its `Max` (current hardware ignores `Max` in `SEMPOST`; this is a `NonContractualBehavior`). Software should also not set a `Value` above the `Max` (current hardware stores both as given; this is a `NonContractualBehavior`).

**Backend execution unit:** [Sync Unit](SyncUnit.md)

## Syntax

```c
TT_SEMINIT(/* u4 */ NewMax, /* u4 */ NewValue, /* u8 */ SemaphoreMask)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SEMINIT.svg)

## Functional model

```c
atomic {
  for (unsigned i = 0; i < 8; ++i) {
    if (SemaphoreMask.Bit[i]) {
      if (NewValue > NewMax) {
        NonContractualBehavior {
          // Current silicon stores both as given, as below (not architecturally guaranteed)
        }
      }
      Semaphores[i].Value = NewValue;
      Semaphores[i].Max = NewMax;
    }
  }
}
```

## Instruction scheduling

If the programmer intent is for the semaphore manipulation to happen after some earlier Tensix instruction has _finished_ execution, it may be necessary to insert a [`STALLWAIT`](STALLWAIT.md) instruction (with block bit B1) somewhere between that earlier instruction and the `SEMINIT` instruction.

If the issuing thread's most recent [`SEMWAIT`](SEMWAIT.md) selects a semaphore that this instruction changes, its block mask does not include B1, and no instruction blocked by that mask has been issued by the thread since, then the `SEMWAIT` might still be latched when this instruction executes, and whether it is depends on timing. As this instruction can change the condition the `SEMWAIT` is waiting on, this is UndefinedBehavior: include B1 in the `SEMWAIT`'s block mask.
