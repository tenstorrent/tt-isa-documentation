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
<tr><th>Y</th><td rowspan="3">Decompressor (for seeking to a particular compression row within L1)</td><td rowspan="3">Output address generator (for forming <code>Dst</code> or <code>SrcA</code> address in unpacker 0, and <code>SrcB</code> address in unpacker 1)</td>
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
