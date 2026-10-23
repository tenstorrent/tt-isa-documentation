# `SFPPUSHC` (Push onto vector conditional execution stack)

**Summary:** Pushes a copy of the current lane predication masks (per-lane `LaneFlags` and `UseLaneFlagsForLaneEnable`) onto the vector conditional execution stack. The stack has a maximum capacity of eight elements, and this instruction must not be used if the stack is already full (what current hardware then does is a `NonContractualBehavior`; see [the flag stack](VectorUnit.md#lane-predication-masks)).

**Backend execution unit:** [Vector Unit (SFPU)](VectorUnit.md), simple sub-unit

## Syntax

```c
TT_SFPPUSHC(0, 0, /* u4 */ VD, 0)
```

## Encoding

![](../../../Diagrams/Out/Bits32_SFPPUSHC.svg)

## Functional model

```c
lanewise {
  if (VD < 12 || LaneConfig.DISABLE_BACKDOOR_LOAD) {
    if (Mod1 != 0) { // Reserved instruction modifiers
      NonContractualBehavior {
        // Current silicon behavior (not architecturally guaranteed): nothing is pushed and
        // FlagStack.Size() is unchanged, but the entry at index FlagStack.Size() % 8 is
        // overwritten (the bottom entry if the stack is full; otherwise an entry above the top,
        // which nothing reads before a push overwrites it again), and Mod1 == 13 also does
        // LaneFlags = !LaneFlags.
      }
    } else {
      if (FlagStack.Size() >= 8) {
        // Software should avoid using SFPPUSHC when the stack is full.
        NonContractualBehavior {
          // The push below overwrites entry Size() % 8 and leaves Size() above 8.
        }
      }
      FlagStack.Push({LaneFlags, UseLaneFlagsForLaneEnable});
    }
  }
}
```
