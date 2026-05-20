# MOP Expander

The Tensix frontend contains one so-called MOP Expander per Tensix thread. Once appropriately configured, a MOP expander allows a single incoming `MOP` (macro-op) instruction to be expanded out to a sequence of up to 32639 instructions, though typical configuration might result in something more like 10 or 100 instructions.

The frontend _also_ contains a [Replay Expander](REPLAY.md) per Tensix thread, which serves a similar role to the MOP Expander, though the MOP Expander is typically used for repetitive looping instruction sequences, whereas the Replay Expander is typically used for linear non-looping sequences. The Replay Expander sits _after_ the MOP Expander in the frontend, so the MOP Expander can output [`REPLAY`](REPLAY.md) instructions as part of its looping sequence, and those `REPLAY` instructions will subsequently be expanded by the Replay Expander (the converse is not true; the expansion of a `REPLAY` instruction cannot contain `MOP` instructions). In either case, the expanders allow a RISCV core to push instructions at a rate of less than one instruction per cycle, but the Tensix backend to still receive one instruction per cycle per thread. This frees up the RISCV cores to perform other tasks, rather than having to spend every single cycle pushing a Tensix instruction.

## Instructions

The [`MOP`](MOP.md) and [`MOP_CFG`](MOP_CFG.md) instructions execute at the MOP Expander.

## Functional model

The MOP Expander sits at the start of the frontend of the Tensix coprocessor, before the Replay Expander. It is the sole place where `MOP` and `MOP_CFG` instructions are handled, and the only things it handles are `MOP` and `MOP_CFG` instructions. The behavior of the MOP Expander can be described as an asynchronous generator acting on the instruction stream:

```py
async def MOPExpander(MopCfg): # MopCfg is per-thread state
  MaskHi = 0 # This is per-thread state, as there's an expander per thread
  while True:
    Instruction = await GetNextIncomingInstruction()
    if Instruction.Opcode == MOP_CFG:
      MaskHi = Instruction.MaskHi
    elif Instruction.Opcode == MOP:
      if Instruction.Template == 0:
        async for x in ExpandTemplate0((MaskHi << 16) + Instruction.MaskLo, Instruction.Count1, MopCfg):
          yield x
      else:
        async for x in ExpandTemplate1(MopCfg):
          yield x
    else:
      yield Instruction # Just pass through everything other than MOP and MOP_CFG

async def ExpandTemplate0(Mask, Count1, MopCfg):
  Flags  = MopCfg[1]
  InsnB  = MopCfg[2]
  InsnA0 = MopCfg[3]
  InsnA1 = MopCfg[4]
  InsnA2 = MopCfg[5]
  InsnA3 = MopCfg[6]
  SkipA0 = MopCfg[7]
  SkipB  = MopCfg[8]
  HasB    = Flags & 1
  HasA123 = Flags & 2
  for i in range(Count1+1):
    if (Mask & 1) == 0:
      yield InsnA0
      if HasA123:
        yield InsnA1
        yield InsnA2
        yield InsnA3
      if HasB:
        yield InsnB
    else:
      yield SkipA0
      if HasB:
        yield SkipB
    Mask >>= 1

async def ExpandTemplate1(MopCfg):
  OuterCount = MopCfg[0] & 127
  InnerCount = MopCfg[1] & 127
  StartOp    = MopCfg[2]
  EndOp0     = MopCfg[3]
  EndOp1     = MopCfg[4]
  LoopOp     = MopCfg[5]
  LoopOp1    = MopCfg[6]
  Loop0Last  = MopCfg[7] # Overrides LoopOp or LoopOp1 on last iteration of inner loop, if also last iteration of outer loop
  Loop1Last  = MopCfg[8] # Overrides LoopOp or LoopOp1 on last iteration of inner loop, if not last iteration of outer loop
  if IsNop(LoopOp1):
    LoopOpFlip = 0
  else:
    LoopOpFlip = LoopOp ^ LoopOp1 # Inner loop will alternate between the two instructions and will
    InnerCount *= 2               # execute for twice as many iterations. It is expressed like this
                                  # because Loop0Last / Loop1Last override the last iteration.
  if OuterCount == 1 and IsNop(StartOp) and InnerCount == 0 and not IsNop(EndOp0):
    OuterCount += 128 # Hardware bug
  for j in range(OuterCount):
    if not IsNop(StartOp):
      yield StartOp
    for i in range(InnerCount):
      if i != InnerCount-1:
        yield LoopOp
      elif j != OuterCount-1:
        yield Loop1Last
      else:
        yield Loop0Last
      LoopOp ^= LoopOpFlip
    if not IsNop(EndOp0):
      yield EndOp0
      if not IsNop(EndOp1):
        yield EndOp1

def IsNop(Instruction):
  # This only recognizes plain NOP (opcode 0x02), not DMANOP nor SFPNOP.
  return Instruction.Opcode == NOP
```

## Configuration

Each instance of `MopCfg` is mapped into the address space of one RISCV core as if it were `uint32_t[9]`, starting at address `TENSIX_MOP_CFG_BASE`, though the address range is **write-only**: attempting to read it from RISCV triggers `UndefinedBehavior`. RISCV T0 gets `MopCfg` for Tensix thread T0, RISCV T1 gets `MopCfg` for Tensix thread T1, and RISCV T2 gets `MopCfg` for Tensix thread T2. As per the above functional model, the meaning of each entry in `MopCfg` varies based on which template a `MOP` instruction requests:
||Template 0 usage|Template 1 usage|
|---|---|---|
|**`MopCfg[0]`**|Not used for anything|`OuterCount` (low seven bits only)|
|**`MopCfg[1]`**|`Flags` (low two bits only; `HasB` and `HasA123`)|`InnerCount` (low seven bits only)|
|**`MopCfg[2]`**|`InsnB` (only used if `HasB`)|`StartOp` (not used if it's a `NOP`)|
|**`MopCfg[3]`**|`InsnA0`|`EndOp0` (not used if it's a `NOP`)|
|**`MopCfg[4]`**|`InsnA1` (only used if `HasA123`)|`EndOp1` (not used if it's a `NOP` nor if `EndOp0` is a `NOP`)|
|**`MopCfg[5]`**|`InsnA2` (only used if `HasA123`)|`LoopOp`|
|**`MopCfg[6]`**|`InsnA3` (only used if `HasA123`)|`LoopOp1` (not used if it's a `NOP`)|
|**`MopCfg[7]`**|`SkipA0`|`Loop0Last`|
|**`MopCfg[8]`**|`SkipB` (only used if `HasB`)|`Loop1Last`|

Though the functional model shows `MopCfg` being sampled at the start of `ExpandTemplate0` / `ExpandTemplate1`, actual hardware (mostly) samples the values as required during the expansion process. As such, software should not change `MopCfg` while an expansion is in progress. [RISCV TTSync](../BabyRISCV/TTSync.md) can be used to wait for expansions to finish, and software is strongly encouraged to use it prior to writing new MOP Expander configuration.

## Performance

While not processing `MOP` or `MOP_CFG` instructions, each MOP Expander can ingest one instruction per cycle and emit one instruction per cycle. When emitting instructions, the MOP Expander will resolve as much control flow as necessary to find the next `yield` statement, so the control flow is effectively free.

Upon receiving a `MOP` instruction, a MOP Expander will ingest the `MOP` instruction and then emit a different sequence of instructions, at a rate of one instruction per cycle, only slowing down if backpressured from downstream.

After expanding a `MOP` instruction, if the next instruction is _not_ a `MOP` instruction, there is a one cycle transition penalty during which the MOP Expander neither ingests nor emits anything. To ensure that the Tensix backend receives one instruction per cycle regardless of this penalty, at least one of the instructions emitted by the expander should be a `REPLAY` instruction which in turn needs to expand to at least two instructions.
