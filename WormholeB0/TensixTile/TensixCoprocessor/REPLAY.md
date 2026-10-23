# `REPLAY` (Record or replay sequence of instructions)

**Summary:** Causes the next several Tensix instructions to be stored to the replay buffer instead of (or as well as) being executed, or expands to several Tensix instructions previously stored in the replay buffer.

**Frontend execution unit:** Replay Expander

## Syntax

```c
TT_REPLAY(/* u5 */ Index, /* u6 */ Count, /* u1 */ Exec, /* u1 */ Load)
```

## Encoding

![](../../../Diagrams/Out/Bits32_REPLAY.svg)

## Functional model

The Replay Expander sits in the frontend of the Tensix coprocessor, after the MOP Expander and before the Wait Gate. It is the sole place where `REPLAY` instructions are handled, and the only thing it handles is `REPLAY` instructions. The behavior of the Replay Expander can be described as an asynchronous generator acting on the instruction stream:

```py
async def ReplayExpander():
  ReplayBuffer = [0] * 32 # This is per-thread state, as there's an expander per thread
  while True:
    Instruction = await GetNextIncomingInstruction()
    if Instruction.Opcode != REPLAY:
      yield Instruction # Just pass through everything other than REPLAY
      continue
    Index = Instruction.Index
    Count = Instruction.Count
    if Count == 0:
      # Current silicon treats a Count of 0 as 32 on Wormhole and as 64 on Blackhole (not architecturally guaranteed)
      NonContractualBehavior()
      Count = 32 if TTArchitecture == Wormhole else 64
    if TTArchitecture == Wormhole and Count > 32:
      if Count == 33 and not Instruction.Load:
        UndefinedBehavior() # Current silicon emits either 33 instructions or 1, depending on timing
      NonContractualBehavior() # Current silicon uses only the low 5 bits of Count (not architecturally guaranteed)
      Count -= 32
    if Index + Count > 32:
      NonContractualBehavior() # Current silicon wraps Index + i around modulo 32 (not architecturally guaranteed)
    if Instruction.Load:
      Exec = Instruction.Exec
      for i in range(Count):
        Instruction = await GetNextIncomingInstruction()
        if Instruction.Opcode == REPLAY:
          UndefinedBehavior() # A REPLAY cannot be one of the instructions loaded
        ReplayBuffer[(Index + i) % 32] = Instruction
        if Exec:
          yield Instruction
    else:
      for i in range(Count):
        yield ReplayBuffer[(Index + i) % 32]
```

Bits 2-3, 10-13 and 19-23 of a `REPLAY` instruction are ignored, and so is `Exec` when `Load` is clear; setting any of these is `NonContractualBehavior`.

On Blackhole, a `REPLAY` with `Load` set and `Exec` clear is further restricted by the tracking of in-flight instructions pushed by RISCV T0 / T1 / T2; see [Push Tensix Instruction](../../../BlackholeA0/TensixTile/BabyRISCV/PushTensixInstruction.md).

## Performance

While not processing `REPLAY` instructions, or processing a `REPLAY` instruction with both `Load` and `Exec` set, each Replay Expander can ingest one instruction per cycle and emit one instruction per cycle.

Upon receiving a `REPLAY` instruction with `Load = false`, a Replay Expander will ingest the `REPLAY` instruction and emit a different instruction from its `ReplayBuffer`. For the next `Count - 1` cycles (or longer, if backpressured from downstream), it will not ingest anything (any incoming instructions will instead accumulate in the FIFO sitting before the expander), but it will emit one instruction per cycle from its `ReplayBuffer`.

Upon receiving a `REPLAY` instruction with `Load = true` and `Exec = false`, a Replay Expander will ingest the `REPLAY` instruction and emit nothing. For the next `Count` cycles (or longer, if there are gaps in the incoming instruction stream), it will ingest one instruction per cycle and emit nothing.

There are no transition penalties when switching between the various modes.
