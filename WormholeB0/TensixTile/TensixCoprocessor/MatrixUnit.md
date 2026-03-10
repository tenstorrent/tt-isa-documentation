# Matrix Unit (FPU)

The Matrix Unit (FPU) performs arithmetic on low-precision (≤ 19-bit) matrices in [`SrcA` and `SrcB`](SrcASrcB.md), usually accumulating the results onto matrices in [`Dst`](Dst.md) (in either 16-bit or 32-bit precision). AI workloads are expected to make heavy use of the [`MVMUL`](MVMUL.md) instruction for matrix multiplication, though there is also [`GMPOOL`](GMPOOL.md) for performing `max` reduction along columns, and [`ELWMUL`](ELWMUL.md) / [`ELWADD`](ELWADD.md) / [`ELWSUB`](ELWSUB.md) for performing element-wise matrix arithmetic. Various data movement instructions also exist.

The Vector Unit (SFPU) can be used instead of the Matrix Unit (FPU) when other operations are required, or when _all_ operands need 32-bit precision rather than just the accumulator, albeit the Vector Unit (SFPU) is not nearly as performant as the Matrix Unit (FPU).

Most Matrix Unit (FPU) instructions use [RWCs](RWCs.md) as part of specifying which rows of `Dst` and `SrcA` and `SrcB` to operate on, and which [fidelity phase](SrcASrcB.md#fidelity-phases-floating-point) to use. The RWCs can be incremented as part of the instruction, and software is encouraged to use this auto-increment functionality rather than spending cycles on standalone [`SETRWC`](SETRWC.md) and [`INCRWC`](INCRWC.md) instructions.

## Instructions

The majority of Matrix Unit (FPU) instructions can be organised based on where they read from and write/accumulate to:

<table><tr><th/><th>Reads <code>Dst</code></th><th>Reads <code>SrcA</code></th><th>Reads <code>SrcB</code></th><th>Reads nothing</th></tr>
<tr><th align="right">Accumulates onto <code>Dst</code></th><td colspan="3"><a href="MVMUL.md"><code>MVMUL</code></a>, <a href="DOTPV.md"><code>DOTPV</code></a>, <a href="GAPOOL.md"><code>GAPOOL</code></a>, <a href="GMPOOL.md"><code>GMPOOL</code></a>, <a href="ELWMUL.md"><code>ELWMUL</code></a>, <a href="ELWADD.md"><code>ELWADD</code></a>, <a href="ELWSUB.md"><code>ELWSUB</code></a></td><td/></tr>
<tr><th align="right">Writes to <code>Dst</code></th><td/><td><a href="MOVA2D.md"><code>MOVA2D</code></a>, <a href="MOVDBGA2D.md"><code>MOVDBGA2D</code></a></td><td><a href="MOVB2D.md"><code>MOVB2D</code></a></td><td><a href="ZEROACC.md"><code>ZEROACC</code></a></td></tr>
<tr><th align="right">Writes to <code>SrcA</code></th><td><a href="MOVD2A.md"><code>MOVD2A</code></a></td><td><a href="SHIFTXA.md"><code>SHIFTXA</code></a></td><td><a href="MOVB2A.md"><code>MOVB2A</code></a></td><td><a href="ZEROSRC.md"><code>ZEROSRC</code></a></td></tr>
<tr><th align="right">Writes to <code>SrcB</code></th><td><a href="MOVD2B.md"><code>MOVD2B</code></a></td><td/><td><a href="SHIFTXB.md"><code>SHIFTXB</code></a>, <a href="TRNSPSRCB.md"><code>TRNSPSRCB</code></a></td><td><a href="ZEROSRC.md"><code>ZEROSRC</code></a></td></tr></table>

The remaining Matrix Unit (FPU) instructions which cannot be organised in this way are [`SETRWC`](SETRWC.md) and [`INCRWC`](INCRWC.md) for manipulating [RWCs](RWCs.md), and then the three oddball instructions [`CLEARDVALID`](CLEARDVALID.md), [`CLREXPHIST`](CLREXPHIST.md), and [`GATESRCRST`](GATESRCRST.md).

Instruction latency and throughput:

|Instruction(s)|Throughput (instructions per cycle)|Latency (cycles)|
|---|---|---|
|`MVMUL`, `DOTPV`, `GAPOOL`, `ELWMUL`|1 (†)|5|
|`GMPOOL`, `ELWADD`, `ELWSUB`|1|5|
|`SETRWC`, `INCRWC`, `CLEARDVALID`, `CLREXPHIST`, `GATESRCRST`|1|1|
|`SHIFTXA`, `ZEROACC`, `ZEROSRC`, `TRNSPSRCB`|1|1|
|`SHIFTXB`|0.5|2|
|`MOVD2A`|1|2 (‡)|
|`MOVA2D`, `MOVDBGA2D`, `MOVB2D`, `MOVB2A`|1|4 (‡)|

(†) If multiple fidelity phases are in use, then one instruction is required per fidelity phase, so the effective IPC decreases as the number of fidelity phases increases.

(‡) Only certain Matrix Unit (FPU) instructions can be used to hide this latency; see the relevant instruction pages for details.

Note that instructions in _other units_ can also interact with `Dst`, `SrcA`, and `SrcB`:

<table><tr><th/><th>Reads <code>Dst</code></th><th>Reads L1</th><th>Reads Tensix GPRs</th><th>Reads <code>LReg</code></th></tr>
<tr><th align="right">Writes to <code>Dst</code></th><td>Matrix Unit (FPU)</td><td>Unpacker 0</td><td/><td><a href="SFPSTORE.md"><code>SFPSTORE</code></a></td></tr>
<tr><th align="right">Writes to <code>SrcA</code></th><td>Matrix Unit (FPU)</td><td>Unpacker 0</td><td><a href="STOREIND_Src.md"><code>STOREIND</code> (<code>SrcA</code>)</a></td><td/></tr>
<tr><th align="right">Writes to <code>SrcB</code></th><td>Matrix Unit (FPU)</td><td>Unpacker 1</td><td><a href="STOREIND_Src.md"><code>STOREIND</code> (<code>SrcB</code>)</a></td><td/></tr>
<tr><th align="right">Writes to L1</th><td>Packers 0-3</td><td>Packer 0, <a href="XMOV.md"><code>XMOV</code></a><td><a href="STOREIND_L1.md"><code>STOREIND</code> (L1)</a>, <a href="ATSWAP.md"><code>ATSWAP</code></a></td><td/></tr>
<tr><th align="right">Accumulates onto L1</th><td>Packers 0-3</td><td>Packer 0</td><td><a href="ATINCGET.md"><code>ATINCGET</code></a>, <a href="ATINCGETPTR.md"><code>ATINCGETPTR</code></a></td><td/></tr>
<tr><th align="right">Writes to <code>LReg</code></th><td><a href="SFPLOAD.md"><code>SFPLOAD</code></a>, <a href="SFPLOADMACRO.md"><code>SFPLOADMACRO</code></a></td><td/><td/><td>Vector Unit (SFPU)</td></tr>
</table>

## Legacy instructions

The `MFCONV3S1`, `CONV3S1`, `CONV3S2`, `APOOL3S1`, and `APOOL3S2` instructions theoretically exist, and count as Matrix Unit (FPU) instructions for the purpose of [`STALLWAIT`](STALLWAIT.md), but all they do is compute `Dst += 0`. They did something more interesting in earlier architectures, but were neutered for Wormhole rather than being fully removed.

A similar remark applies to `MPOOL3S1` and `MPOOL3S2`, albeit instead of computing `Dst += 0` they do something similar to what `GMPOOL` would do if `SrcA` was entirely zero. In any case, they are not useful instructions.

All of these behaviors are NonContractualBehaviors and these opcode values are likely to be repurposed in future implementations.

## Performance

Theoretical maximum performance per Matrix Unit (FPU), running at Wormhole's standard 1 GHz clock rate:

|Instruction|1 Fidelity Phase|2 Fidelity Phases|3 Fidelity Phases|4 Fidelity Phases|
|---|---|---|---|---|
|`MVMUL`, `BroadcastSrcBRow==false`|4.096 TFLOP/s|2.048 TFLOP/s|1.366 TFLOP/s|1.024 TFLOP/s|
|`DOTPV`|4.096 TFLOP/s|2.048 TFLOP/s|1.366 TFLOP/s|1.024 TFLOP/s|
|`GAPOOL`|2.048 TFLOP/s|1.024 TFLOP/s|0.683 TFLOP/s|0.512 TFLOP/s|
|`MVMUL`, `BroadcastSrcBRow==true`|0.560 TFLOP/s|0.280 TFLOP/s|0.187 TFLOP/s|0.140 TFLOP/s|
|`ELWMUL`|0.256 TFLOP/s|0.128 TFLOP/s|0.085 TFLOP/s|0.064 TFLOP/s|
|`GMPOOL`|0.256 TFLOP/s|0.256 TFLOP/s|0.256 TFLOP/s|0.256 TFLOP/s|
|`ELWADD` / `ELWSUB`, `AddDst==true`|0.256 TFLOP/s|0.256 TFLOP/s|0.256 TFLOP/s|0.256 TFLOP/s|
|`ELWADD` / `ELWSUB`, `AddDst==false`|0.128 TFLOP/s|0.128 TFLOP/s|0.128 TFLOP/s|0.128 TFLOP/s|

Note that `GMPOOL` / `ELWADD` / `ELWSUB` do not need multiple fidelity phases, so the same number is quoted for all fidelity phase columns. Other instructions require a variable number of [fidelity phases](SrcASrcB.md#fidelity-phases-floating-point), depending on the data types in use and the desired precision. As a point of comparison, the Vector Unit (SFPU) instruction `SFPMAD` has a theoretical maximum performance of 0.064 TFLOP/s (per Vector Unit) at FP32 precision.

For integer types, the performance numbers are the same (just replace "TFLOP/s" with "TOP/s"), though [fidelity phases for integer types](SrcASrcB.md#fidelity-phases-integer) relate to the maximum magnitude of the inputs, so arbitrary 8-bit inputs require 4 fidelity phases. For integer inputs in the range -127 through +127, it is also possible to massage the data into floating-point form, and then just 2 fidelity phases are required (plus an occasional step to flush FP32 accumulators to INT32).

To calculate the performance of an entire Wormhole ASIC, multiply the above numbers by the number of Tensix tiles on the Wormhole ASIC, which depending on the product will be either 64 or 72 or 80. To then calculate the performance of an entire product, multiply by the number of Wormhole ASICs in the product (an n150 board will have 1 ASIC with 72 tiles, an n300 board will have 2 ASICs with 64 tiles each, and a Galaxy server will have 32 ASICs with 80 tiles each).
