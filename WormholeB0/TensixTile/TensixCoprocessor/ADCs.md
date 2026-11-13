# ADCs

Packer and unpacker instructions assume the presence of the following global variable:

```c
struct {
  struct {
    struct {
      uint18_t X, X_Cr;
      uint13_t Y, Y_Cr;
      uint8_t Z, Z_Cr;
      uint8_t W, W_Cr;
    } Channel[2];
  } Unpacker[2], Packers;
} ADCs[3];
```

On Blackhole (`TTArchitecture == Blackhole`), the `Z`, `Z_Cr`, `W` and `W_Cr` fields are `uint13_t` rather than `uint8_t`. The extra bits are not visible everywhere: the unpackers' input address generator receives only the low eight bits of channel 0's `Z` and `W`, and the [debug daisychain](../DebugDaisychain.md#adcs) presents only the low eight bits of any of them. They do however take full effect when an unpacker forms its output address from channel 1, and when a packer forms its `Dst` input address from channel 0.

The `[3]` is _usually_ indexed as `[CurrentThread]`, meaning that each Tensix thread _can_ have its own set of ADCs, but software can instead use arbitrary indexing if it so wishes.

Each unpacker gets its own set of X/Y/Z/W values, which are used in various ways to form input and output addresses:

<table><tr><th/><th>Channel 0 Usage</th><th>Channel 1 Usage</th></tr>
<tr><th>X</th><td>Input address generator (for forming L1 address, and part of datum count)</td><td>Input address generator (part of datum count)</td></tr>
<tr><th>Y</th><td rowspan="3">Input address generator (for forming L1 address), and decompressor (for seeking to a particular compression row within L1)</td><td rowspan="3">Output address generator (for forming <code>Dst</code> or <code>SrcA</code> address in unpacker 0, and <code>SrcB</code> address in unpacker 1)</td>
<tr><th>Z</th></tr>
<tr><th>W</th></tr></table>

The `Y` and `Z` counters for unpackers can be incremented as part of an `UNPACR` instruction.

All four packers share a set of X/Y/Z/W values, which they use in various ways to form input and output addresses:

<table><tr><th/><th>Channel 0 Usage</th><th>Channel 1 Usage</th></tr>
<tr><th>X</th><td>Input address generator (for forming <code>Dst</code> address, and part of datum count)</td><td>Input address generator (part of datum count)</td></tr>
<tr><th>Y</th><td rowspan="3">Input address generator (for forming <code>Dst</code> address)</td><td rowspan="3">Output address generator (for forming L1 address)</td>
<tr><th>Z</th></tr>
<tr><th>W</th></tr></table>

The `Y` and `Z` counters for packers can be incremented as part of a `PACR` instruction, though a layer of indirection is used: two bits from the `PACR` instruction specify an index into an array of pre-configured increments.

## Overriding another thread's ADCs

On both Wormhole and Blackhole, an ADC instruction with a non-zero `ThreadOverride` ([`SETADC`](SETADC.md), [`SETADCXY`](SETADCXY.md), [`SETADCZW`](SETADCZW.md), [`INCADCXY`](INCADCXY.md), [`INCADCZW`](INCADCZW.md), [`ADDRCRXY`](ADDRCRXY.md) or [`ADDRCRZW`](ADDRCRZW.md); `ThreadOverride` itself is `UnsupportedFunctionality`) isn't kept apart from the instructions of the thread whose ADCs it names. Every instruction with an opcode from 0x40 to 0x68 inclusive (the unpacker, packer, Scalar Unit (ThCon), mover and ADC instructions, among others), not only the ADC instructions, is offered to its own thread's ADCs as a possible update, and an override is offered to the named thread's; in any one cycle, a thread's ADCs take a single update built from everything offered to them. So if, in the same cycle, an override names thread X's ADCs and thread X offers any instruction from that range, X's ADCs see one instruction whose operand bits are the bitwise OR of both instructions' operand bits: other counters, another channel or another dimension can be selected, the values written are ORed together, and a set and an increment can both happen. The same happens when two threads' overrides name thread X in the same cycle. Apart from the ADCs, both instructions do what they would have done anyway. As the unpackers and packers form their addresses from the ADCs, thread X's later [`UNPACR`](UNPACR.md)s and [`PACR`](PACR.md)s can then read and write the wrong places; this is `UndefinedBehavior`.

An instruction, an override included, is offered on every cycle from when it passes its thread's [Wait Gate](WaitGate.md) until its backend execution unit accepts it, not just on the cycle it's issued. A thread offers its instructions one at a time, in order, so an override meets whichever of the named thread's instructions is waiting to be accepted in that cycle; which one that is, and for how many cycles it waits, depends on how busy the execution units are, and differs between Wormhole and Blackhole.

So software which overrides thread X's ADCs must make sure that, whenever an override naming X might be offered (on any cycle from when it passes its own thread's Wait Gate until it is accepted), thread X has no instruction from 0x40 to 0x68 between its Wait Gate and its execution unit (X's own ADC instructions and `SETDMAREG` included), and that no two threads can override X's ADCs in the same cycle. Thread X's Matrix Unit (FPU), Vector Unit (SFPU), sync and configuration instructions (opcodes outside that range) don't interfere.
