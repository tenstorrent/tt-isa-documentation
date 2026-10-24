# `SEMGET` (Decrement the `Value` of some semaphores)

**Summary:** Various semaphores are selected using a bitmask, and the selected semaphores have their `Value` decremented. Software should not decrement a semaphore whose `Value` is already zero; what current hardware then does (the `Value` remains at zero) is a `NonContractualBehavior`.

**Backend execution unit:** [Sync Unit](SyncUnit.md)

## Syntax

```c
TT_SEMGET(/* u8 */ SemaphoreMask)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SEMGET.svg)

## Functional model

```c
atomic {
  for (unsigned i = 0; i < 8; ++i) {
    if (SemaphoreMask.Bit[i]) {
      if (Semaphores[i].Value == 0) {
        NonContractualBehavior {
          // Current silicon leaves the Value at zero (not architecturally guaranteed)
        }
      } else {
        Semaphores[i].Value -= 1;
      }
    }
  }
}
```

## Instruction scheduling

If the programmer intent is for the semaphore decrement to happen after some earlier Tensix instruction has _finished_ execution, it may be necessary to insert a [`STALLWAIT`](STALLWAIT.md) instruction (with block bit B1) somewhere between that earlier instruction and the `SEMGET` instruction.

If the issuing thread's most recent [`SEMWAIT`](SEMWAIT.md) selects a semaphore that this instruction changes, its block mask does not include B1, and no instruction blocked by that mask has been issued by the thread since, then the `SEMWAIT` might still be latched when this instruction executes, and whether it is depends on timing, but the outcome does not, and is NonContractualBehavior: the `SEMWAIT` is evaluated against the semaphores as they were before this instruction, and is forgotten if that evaluation finds its conditions met, else stays latched and sees this instruction's change, as executing the two in program order would (what other threads and RISCV cores do to the semaphores in between still matters, as for any `SEMWAIT`). Software should not rely on this: include B1 in the `SEMWAIT`'s block mask.
