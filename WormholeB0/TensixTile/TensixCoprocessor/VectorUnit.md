# Vector Unit (SFPU)

The Vector Unit (SFPU) performs arithmetic and manipulation on 32-bit floating-point values or 32-bit integers in [`LReg`](LReg.md). It can be considered as a general-purpose SIMD engine, consisting of 32 lanes of 32 bits.

## Instructions

<table>
<thead><tr><th colspan="4" align="left">FP32 arithmetic instructions, operating lanewise</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPADDI.md"><code>SFPADDI</code></a></td><td>1</td><td>2 cycles</td><td><code>VD += BF16ToFP32(Imm16)</code></td></tr>
<tr><td><a href="SFPADD.md"><code>SFPADD</code></a></td><td>1</td><td>2 cycles</td><td><code>VD =      VB + VC</code></td></tr>
<tr><td><a href="SFPMAD.md"><code>SFPMAD</code></a></td><td>1</td><td>2 cycles</td><td><code>VD = VA * VB + VC</code></td></tr>
<tr><td><a href="SFPMUL.md"><code>SFPMUL</code></a></td><td>1</td><td>2 cycles</td><td><code>VD = VA * VB</code></td></tr>
<tr><td><a href="SFPMULI.md"><code>SFPMULI</code></a></td><td>1</td><td>2 cycles</td><td><code>VD *= BF16ToFP32(Imm16)</code></td></tr>
<tr><td><a href="SFPLUT.md"><code>SFPLUT</code></a></td><td>1</td><td>2 cycles</td><td><code>VD = Lut8ToFp32(LReg[i] &gt;&gt; 8) * Abs(LReg[3]) + Lut8ToFp32(LReg[i])</code><br/>Where <code>i</code> is <code>0</code> or <code>1</code> or <code>2</code>, depending on the magnitude of <code>LReg[3]</code></td></tr>
<tr><td><a href="SFPLUTFP32.md"><code>SFPLUTFP32</code></a>&nbsp;(†)</td><td>1</td><td>2 cycles</td><td><code>VD = LReg[i] * Abs(LReg[3]) + LReg[4+i]</code><br/>Where <code>i</code> is <code>0</code> or <code>1</code> or <code>2</code>, depending on the magnitude of <code>LReg[3]</code></td></tr>
<tr><td><a href="SFPLUTFP32.md"><code>SFPLUTFP32</code></a>&nbsp;(†)</td><td>1</td><td>2 cycles</td><td><code>VD = Lut16ToFp32(LReg[i] &gt;&gt; 16) * Abs(LReg[3]) + Lut16ToFp32(LReg[i])</code><br/>Where <code>i</code> is <code>0</code> or <code>1</code> or <code>2</code>, depending on the magnitude of <code>LReg[3]</code></td></tr>
<tr><td><a href="SFPLUTFP32.md"><code>SFPLUTFP32</code></a>&nbsp;(†)</td><td>1</td><td>2 cycles</td><td><code>VD = Lut16ToFp32(LReg[i] &gt;&gt; j) * Abs(LReg[3]) + Lut16ToFp32(LReg[4+i] &gt;&gt; j)</code><br/>Where, depending on the magnitude of <code>LReg[3]</code>, <code>i</code> is <code>0</code> or <code>1</code> or <code>2</code>, and <code>j</code> is <code>0</code> or <code>16</code></td></tr>
<tr><td><a href="SFPSWAP.md"><code>SFPSWAP</code></a>&nbsp;(†)</td><td>≤ 1</td><td>2 cycles</td><td><code>VD = Min(VC, VD)</code> and<br/><code>VC = Max(VC, VD)</code> (simultaneous assignments)</td></tr>
<tr><td><a href="SFPMOV.md"><code>SFPMOV</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = -VC</code></td></tr>
<tr><td><a href="SFPSETSGN.md"><code>SFPSETSGN</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Abs(VC)</code> or <code>VD = -Abs(VC)</code></td></tr>
<tr><td><a href="SFPABS.md"><code>SFPABS</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Abs(VC)</code>, or <code>VD = VC</code> when <code>VC</code> is NaN</td></tr>
<tr><td><a href="SFPLZ.md"><code>SFPLZ</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td>Set per-lane flags based on <code>VC != 0</code> or <code>VC == 0</code></td></tr>
<tr><td><a href="SFPSETCC.md"><code>SFPSETCC</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td>Provided that <code>VC</code> is neither negative zero nor any kind of NaN:<br/>Set per-lane flags based on <code>VC &lt; 0</code> or <code>VC != 0</code> or <code>VC &gt;= 0</code> or <code>VC == 0</code></td></tr>
<thead><tr><th colspan="4" align="left">FP32 field manipulation instructions (sign, exponent, mantissa), operating lanewise</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPDIVP2.md"><code>SFPDIVP2</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = {VC.Sign, VC.Exp + Imm8, VC.Mant}</code>, or <code>VD = VC</code> when <code>VC</code> is NaN/Inf</td></tr>
<tr><td><a href="SFPDIVP2.md"><code>SFPDIVP2</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = {VC.Sign,          Imm8, VC.Mant}</code></td></tr>
<tr><td><a href="SFPSETEXP.md"><code>SFPSETEXP</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = {VC.Sign, VD.Mant &amp; 255, VC.Mant}</code> or<br/><code>VD = {VC.Sign, VD.Exp       , VC.Mant}</code> or<br/><code>VD = {VC.Sign,          Imm8, VC.Mant}</code></td></tr>
<tr><td><a href="SFPSETMAN.md"><code>SFPSETMAN</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = {VC.Sign, VC.Exp       , VD.Mant}</code> or<br/><code>VD = {VC.Sign, VC.Exp       , Imm12 &lt;&lt; 11}</code></td></tr>
<tr><td><a href="SFPSETSGN.md"><code>SFPSETSGN</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = {VD.Sign, VC.Exp       , VC.Mant}</code> or<br/><code>VD = {   Imm1, VC.Exp       , VC.Mant}</code></td></tr>
<tr><td><a href="SFPEXMAN.md"><code>SFPEXMAN</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = {      0,         !Imm1, VC.Mant}</code></td></tr>
<tr><td><a href="SFPEXEXP.md"><code>SFPEXEXP</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = VC.Exp</code> or <code>VD = VC.Exp - 127</code> (‡)</td></tr>
<tr><td><a href="SFPSETCC.md"><code>SFPSETCC</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td>Set flags based on <code>VC.Sign</code></td></tr>
<thead><tr><th colspan="4" align="left">Two's complement integer arithmetic instructions, operating lanewise</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPIADD.md"><code>SFPIADD</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = VC ± VD</code> or <code>VD = VC ± Imm11</code> (‡)</td></tr>
<tr><td><a href="SFPABS.md"><code>SFPABS</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Abs(VC)</code>, or <code>VD = VC</code> when <code>VC</code> is -2<sup>31</sup></td></tr>
<tr><td><a href="SFPSETCC.md"><code>SFPSETCC</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td>Set per-lane flags based on <code>VC &lt; 0</code> or <code>VC != 0</code> or <code>VC &gt;= 0</code> or <code>VC == 0</code></td></tr>
<thead><tr><th colspan="4" align="left">Sign-magnitude integer arithmetic instructions, operating lanewise</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPMOV.md"><code>SFPMOV</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = -VC</code></td></tr>
<tr><td><a href="SFPSETSGN.md"><code>SFPSETSGN</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Abs(VC)</code> or <code>VD = -Abs(VC)</code></td></tr>
<tr><td><a href="SFPSTOCHRND_IntInt.md"><code>SFPSTOCHRND</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Min(Round(Abs(VC) &gt;&gt; (VB % 32)), 255)</code> or<br/><code>VD = Min(Round(Abs(VC) &gt;&gt; Imm5), 255)</code></td></tr>
<tr><td><a href="SFPSTOCHRND_IntInt.md"><code>SFPSTOCHRND</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Clamp(Round(VC &gt;&gt; (VB % 32)), ±127)</code> or<br/><code>VD = Clamp(Round(VC &gt;&gt; Imm5), ±127)</code></td></tr>
<tr><td><a href="SFPLZ.md"><code>SFPLZ</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td>Set per-lane flags based on <code>VC != 0</code> or <code>VC == 0</code></td></tr>
<tr><td><a href="SFPSETCC.md"><code>SFPSETCC</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td>Provided that <code>VC</code> is not negative zero:<br/>Set per-lane flags based on <code>VC &lt; 0</code> or <code>VC != 0</code> or <code>VC &gt;= 0</code> or <code>VC == 0</code></td></tr>
<tr><td><a href="SFPSWAP.md"><code>SFPSWAP</code></a>&nbsp;(†)</td><td>≤ 1</td><td>2 cycles</td><td><code>VD = Min(VC, VD)</code> and<br/><code>VC = Max(VC, VD)</code> (simultaneous assignments)</td></tr>
<thead><tr><th colspan="4" align="left">Bit manipulation instructions (32 bits, unsigned), operating lanewise</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPAND.md"><code>SFPAND</code></a></td><td>1</td><td>1 cycle</td><td><code>VD &amp;= VC</code></td></tr>
<tr><td><a href="SFPOR.md"><code>SFPOR</code></a></td><td>1</td><td>1 cycle</td><td><code>VD |= VC</code></td></tr>
<tr><td><a href="SFPXOR.md"><code>SFPXOR</code></a></td><td>1</td><td>1 cycle</td><td><code>VD ^= VC</code></td></tr>
<tr><td><a href="SFPNOT.md"><code>SFPNOT</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = ~VC</code></td></tr>
<tr><td><a href="SFPLZ.md"><code>SFPLZ</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = CountLeadingZeros(VC)</code> (‡)</td></tr>
<tr><td><a href="SFPSHFT.md"><code>SFPSHFT</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = VD &lt;&lt; ( VC % 32)</code> or <code>VD = VD &lt;&lt;  Imm5</code> or<br/><code>VD = VD &gt;&gt; (-VC % 32)</code> or <code>VD = VD &gt;&gt; -Imm5</code></td></tr>
<tr><td><a href="SFPSHFT2.md"><code>SFPSHFT2</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = VB &lt;&lt; ( VC % 32)</code> or<br/><code>VD = VB &gt;&gt; (-VC % 32)</code></td></tr>
<thead><tr><th colspan="4" align="left">Data type conversion instructions, operating lanewise</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPCAST.md"><code>SFPCAST</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = SignMag32ToFp32(VC)</code></td></tr>
<tr><td><a href="SFPSTOCHRND_FloatFloat.md"><code>SFPSTOCHRND</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Fp32ToBf16(VC) &lt;&lt 16</code> or<br/><code>VD = Fp32ToTf32(VC)</code></td></tr>
<tr><td><a href="SFPSTOCHRND_FloatInt.md"><code>SFPSTOCHRND</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Fp32ToInt32(Min(Abs(VC), 255))</code> or<br/><code>VD = Fp32ToInt32(Min(Abs(VC), 65535))</code></td></tr>
<tr><td><a href="SFPSTOCHRND_FloatInt.md"><code>SFPSTOCHRND</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Fp32ToSignMag32(Clamp(VC, ±127))</code> or<br/><code>VD = Fp32ToSignMag32(Clamp(VC, ±32767))</code></td></tr>
<tr><td><a href="SFPLOADI.md"><code>SFPLOADI</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = Bf16ToFp32(Imm16)</code> or<br/><code>VD = Fp16ToFp32(Imm16)</code> or<br/><code>VD = Imm16</code> or<br/><code>VD = ±Imm15</code> or<br/><code>VD.High16 = Imm16</code> or<br/><code>VD.Low16 = Imm16</code></td></tr>
<thead><tr><th colspan="4" align="left">Data movement instructions</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPLOAD.md"><code>SFPLOAD</code></a></td><td>1</td><td>1 cycle</td><td><code>VD = Dst[R:R+4, 0:15:2]</code> or <code>VD = Dst[R:R+4, 1:16:2]</code></td></tr>
<tr><td><a href="SFPSTORE.md"><code>SFPSTORE</code></a></td><td>1</td><td>1 cycle</td><td><code>Dst[R:R+4, 0:15:2] = VD</code> or <code>Dst[R:R+4, 1:16:2] = VD</code></td></tr>
<tr><td><a href="SFPLOADMACRO.md"><code>SFPLOADMACRO</code></a></td><td>1</td><td>Complex</td><td>Like <code>SFPLOAD</code>, then schedule up to four additional vector instructions</td></tr>
<tr><td><a href="SFPMOV.md"><code>SFPMOV</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = VC</code></td></tr>
<tr><td><a href="SFPCONFIG.md"><code>SFPCONFIG</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Broadcast(LReg[0][0:8])</code> (when 11 ≤ <code>VD</code> ≤ 14)</td></tr>
<tr><td><a href="SFPSWAP.md"><code>SFPSWAP</code></a>&nbsp;(†)</td><td>≤ 1</td><td>2 cycles</td><td><code>VD = VC</code> and<br/><code>VC = VD</code> (simultaneous assignments)</td></tr>
<tr><td><a href="SFPTRANSP.md"><code>SFPTRANSP</code></a></td><td>1</td><td>1 cycle</td><td>Within each column, transpose rows of <code>LReg[0:4]</code> and of <code>LReg[4:8]</code></td></tr>
<tr><td><a href="SFPSHFT2.md"><code>SFPSHFT2</code></a>&nbsp;(†)</td><td>≤ 1</td><td>2 cycles</td><td><code>VD = RotateLanesRight(VC)</code> or<br/><code>VD = ShiftLanesRight(VC)</code></td></tr>
<tr><td><a href="SFPSHFT2.md"><code>SFPSHFT2</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>LReg[0] = LReg[1]</code> and<br/><code>LReg[1] = LReg[2]</code> and<br/><code>LReg[2] = LReg[3]</code> and<br/><code>LReg[3] = Zeroes</code> (simultaneous assignments)</td></tr>
<tr><td><a href="SFPSHFT2.md"><code>SFPSHFT2</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>LReg[0] = LReg[1]</code> and<br/><code>LReg[1] = LReg[2]</code> and<br/><code>LReg[2] = LReg[3]</code> and<br/><code>LReg[3] = {LReg[0][8:32], Zeroes[0:8]}</code> (simultaneous assignments)</td></tr>
<tr><td><a href="SFPSHFT2.md"><code>SFPSHFT2</code></a>&nbsp;(†)</td><td>≤ 1</td><td>2 cycles</td><td><code>LReg[0] = LReg[1]</code> and<br/><code>LReg[1] = LReg[2]</code> and<br/><code>LReg[2] = LReg[3]</code> and<br/><code>LReg[3] = RotateLanesRight(VC)</code> (simultaneous assignments)</td></tr>
<thead><tr><th colspan="4" align="left">Conditional execution instructions</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPENCC.md"><code>SFPENCC</code></a></td><td>1</td><td>1 cycle</td><td>Enable or disable conditional execution</td></tr>
<tr><td><a href="SFPSETCC.md"><code>SFPSETCC</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td>Set per-lane flags based on <code>VC &lt; 0</code> or <code>VC != 0</code> or <code>VC &gt;= 0</code> or <code>VC == 0</code></td></tr>
<tr><td><a href="SFPPUSHC.md"><code>SFPPUSHC</code></a></td><td>1</td><td>1 cycle</td><td>Push flags onto flag stack</td></tr>
<tr><td><a href="SFPCOMPC.md"><code>SFPCOMPC</code></a></td><td>1</td><td>1 cycle</td><td>SIMT mapping of <code>else</code> in context of <code>if</code> / <code>else</code></td></tr>
<tr><td><a href="SFPPOPC.md"><code>SFPPOPC</code></a></td><td>1</td><td>1 cycle</td><td>Pop or peek flag stack</td></tr>
<thead><tr><th colspan="4" align="left">Other instructions</th></tr></thead>
<thead><tr><th>Instruction</th><th>IPC</th><th>Latency</th><th>Approximate semantics (see instruction page for full details)</th></tr></thead>
<tr><td><a href="SFPCONFIG.md"><code>SFPCONFIG</code></a>&nbsp;(†)</td><td>1</td><td>≤&nbsp;2&nbsp;cycles</td><td><code>Configuration = Broadcast(LReg[0][0:8])</code> or <code>Configuration = Imm16</code></td></tr>
<tr><td><a href="SFPMOV.md"><code>SFPMOV</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = Configuration</code></td></tr>
<tr><td><a href="SFPMOV.md"><code>SFPMOV</code></a>&nbsp;(†)</td><td>1</td><td>1 cycle</td><td><code>VD = AdvancePRNG()</code></td></tr>
<tr><td><a href="SFPNOP.md"><code>SFPNOP</code></a></td><td>1</td><td>1 cycle</td><td>Causes no effects</td></tr>
</table>

(†) This row is describing one possible mode or interpretation of the instruction; other rows describe its other modes or interpretations.

(‡) Can also set per-lane flags.

## Sub-units

The Vector Unit (SFPU) is composed of five sub-units: load, simple, MAD, round, and store. The Vector Unit (SFPU) can only accept one instruction per cycle from the outside world, so by default four fifths of the Vector Unit (SFPU) is always idle. To have more than one sub-unit active at a time, [`SFPLOADMACRO`](SFPLOADMACRO.md) needs to be used.

## `lanewise`

In instruction descriptions, `lanewise` itself is shorthand for `for (unsigned Lane = 0; Lane < 32; ++Lane)`, and then various shorthands apply _within_ a `lanewise` block:

|Syntax|Shorthand for|
|---|---|
|`LReg[i]`|`LReg[i][Lane]`|
|`LaneEnabled`|`LaneEnabled[Lane]`|
|`LaneFlags`|`LaneFlags[Lane]`|
|`UseLaneFlagsForLaneEnable`|`UseLaneFlagsForLaneEnable[Lane]`|
|`FlagStack`|`FlagStack[Lane]`|
|`LaneConfig`|`LaneConfig[Lane]`|
|`LoadMacroConfig`|`LoadMacroConfig[Lane]`|
|`AdvancePRNG()`|`AdvancePRNG(Lane)`|

## Lane Predication Masks

```c
bool LaneFlags[32] = {false};
bool UseLaneFlagsForLaneEnable[32] = {false};
struct FlagStackEntry {
  bool LaneFlags;
  bool UseLaneFlagsForLaneEnable;
};
Stack<FlagStackEntry> FlagStack[32];
```

Software is encouraged to set `UseLaneFlagsForLaneEnable` to `true` and then always leave it as `true`, though it doesn't have to.

In instruction descriptions, `LaneEnabled[Lane]` is shorthand for `IsLaneEnabled(Lane)`, whose definition is:

```c
bool IsLaneEnabled(unsigned Lane) {
  if (LaneConfig[Lane & 7].ROW_MASK.Bit[Lane / 8]) {
    return false;
  } else if (UseLaneFlagsForLaneEnable[Lane]) {
    return LaneFlags[Lane];
  } else {
    return true;
  }
}
```

`UseLaneFlagsForLaneEnable` is initially `false`, but once changed to `true` using [`SFPENCC`](SFPENCC.md), `LaneFlags` is used to drive `LaneEnabled` (per the definition of `IsLaneEnabled` above). In turn, `LaneFlags` can be set by the [`SFPENCC`](SFPENCC.md), [`SFPSETCC`](SFPSETCC.md), [`SFPIADD`](SFPIADD.md), [`SFPLZ`](SFPLZ.md), and [`SFPEXEXP`](SFPEXEXP.md) instructions.

The `FlagStack` is used by the [`SFPPUSHC`](SFPPUSHC.md), [`SFPPOPC`](SFPPOPC.md), and [`SFPCOMPC`](SFPCOMPC.md) instructions. Compilers are encouraged to map SIMT `if` / `else` onto this stack. Some kinds of non-uniform control flow can also be accommodated using the `SFPMAD_MOD1_INDIRECT_VA` and/or `SFPMAD_MOD1_INDIRECT_VD` mode flags of the [`SFPMAD`](SFPMAD.md), [`SFPMULI`](SFPMULI.md), and [`SFPADDI`](SFPADDI.md) instructions.

## PRNG

Some modes of the [`SFPMOV`](SFPMOV.md), [`SFPCAST`](SFPCAST.md), and [`SFPSTOCHRND`](SFPSTOCHRND.md) instructions make use of a hardware PRNG, the behavior of which is:

```c
uint32_t AdvancePRNG(unsigned Lane) {
  static uint32_t State[32];
  uint32_t Result = State[Lane];
  uint32_t Taps = __builtin_popcount(Result & 0x80200003);
  State[Lane] = (~Taps << 31) | (Result >> 1);
  return Result;
}
```

The statistical properties of this PRNG are poor, so software is encouraged to build its own PRNG if high quality randomness is required.
