# Configuration Unit

The Configuration Unit can read or write [backend configuration](BackendConfiguration.md). Its `WRCFG` and `RDCFG` instructions access the same GPRs as the [Scalar Unit (ThCon)](ScalarUnit.md). The instructions executed by the Configuration Unit are:

<table><thead><tr><th>Instruction</th><th>Latency</th><th>IPC</th><th>IPC group</th><th>Purpose</th></tr></thead>
<tr><td><code><a href="SETC16.md">SETC16</a></code></td><td align="right">1 cycle</td><td>3</td><td><code>ThreadConfig</code></td><td>Write to <code>ThreadConfig</code> using value from immediate</td></tr>
<tr><td><code><a href="STREAMWRCFG.md">STREAMWRCFG</a></code></td><td align="right">≥&nbsp;5 cycles</td><td>1</td><td rowspan="8"><code>Config</code></td><td>Write to <code>Config</code> using value from NoC Overlay</td></tr>
<tr><td><code><a href="WRCFG.md">WRCFG</a></code></td><td align="right">2 cycles</td><td>1</td><td>Write to <code>Config</code> using value from Tensix GPR</td></tr>
<tr><td><code><a href="CFGSHIFTMASK.md">CFGSHIFTMASK</a></code></td><td align="right">2 cycles</td><td>½</td><td>Mutate <code>Config</code> using value from <code>Config</code></td></tr>
<tr><td><code><a href="RMWCIB.md">RMWCIB</a></code></td><td align="right">1 cycle</td><td>1</td><td>Mutate <code>Config</code> using immediate</td></tr>
<tr><td><code><a href="RDCFG.md">RDCFG</a></code></td><td align="right">≥&nbsp;2&nbsp;cycles</td><td>1</td><td>Read from <code>Config</code> to Tensix GPR</td></tr>
<tr><td>RISCV&nbsp;read&nbsp;request</td><td align="right">1 cycle</td><td>1</td><td>Read from <code>Config</code> or <code>ThreadConfig</code> to RISCV GPR/FPR</td></tr>
<tr><td>RISCV&nbsp;write&nbsp;request</td><td align="right">1 cycle</td><td>1</td><td>Write to <code>Config</code> using value from RISCV GPR/FPR</td></tr>
<tr><td>Mover&nbsp;write&nbsp;request</td><td align="right">1 cycle</td><td>1</td><td>Write to <code>Config</code> using value from L1 (or zero)</td></tr>
</table>

RISCV read-requests and write-requests against `TENSIX_CFG_BASE` also end up at the Configuration Unit, and it processes these requests as if they were single-cycle instructions. Note however that it can take multiple cycles for the requests to travel from RISCV to the Configuration Unit, and multiple cycles for read-responses to return back to RISCV. They are part of the `Config` IPC group even if they are read-requests for `ThreadConfig`.

At most three instructions can be accepted per cycle (one from each thread), plus one external read/write request, although everything other than `SETC16` is part of the same IPC group, and sustained throughput across the entire group is limited to one instruction per cycle (or half an instruction per cycle if `CFGSHIFTMASK` is used). This IPC group makes use of an internal pipeline within the Configuration Unit, whose pipeline stages are numbered as -4 through +1 (numbered such that stage 0 is where the main configuration access happens). Instructions enter the pipeline at the earliest stage which applies to them, and then progress through the pipeline at a rate of one stage per cycle (except for `RDCFG`, which can potentially occupy stage 1 for multiple cycles if there is GPR write contention). Three instructions can enter this pipeline at the same time if they enter at different stages (e.g. at -4, -1, and 0), but sustained throughput is limited by every instruction requiring one cycle in stage 0 (and `CFGSHIFTMASK` requiring two cycles in stage 0):

|Instruction|Stage -4|Stage -3|Stage -2|Stage -1|Stage 0|Stage +1|
|---|---|---|---|---|---|---|
|`STREAMWRCFG`|Prepare|Issue memory read|Wait|Wait|Config write||
|`WRCFG`||||GPR read|Config write||
|`CFGSHIFTMASK` (1<sup>st</sup>)||||Blocks stage|Config read||
|`CFGSHIFTMASK` (2<sup>nd</sup>)|||||Config write||
|`RMWCIB`|||||Config read+write||
|`RDCFG`|||||Config read|GPR write|
|RISCV read request|||||Config read||
|RISCV write request|||||Config write||
|Mover write request|||||Config write||

To prevent two instructions from occupying a stage at the same time, an instruction cannot enter the pipeline if the stage it would enter at is already occupied. Furthermore, to maintain relative ordering between instructions, an instruction cannot enter the pipeline if _any_ lower-numbered stage is occupied. However, due to a hardware bug, this only applies at stages -3 and above: a `STREAMWRCFG` instruction in stage -4 does _not_ prevent an instruction entering at stage -1 or stage 0. Due to another hardware bug, this ordering is enforced regardless of issuing thread, so for example a `STREAMWRCFG` instruction occupying stage -3 or -2 prevents _any_ thread from having an instruction enter at stage -1 or stage 0. These behaviours combine to allow instructions which enter at earlier stages to starve instructions which enter at later stages. Notably, excessive use of `WRCFG` by one thread can starve processing of RISCV read/write requests from other threads, causing high latency for read-requests and delayed processing of write-requests.

If a Tensix instruction cannot enter the pipeline (for one of the reasons outlined in the prior paragraph), it'll wait at its thread's Wait Gate until it is able to enter the pipeline. If an external read/write request cannot enter, it'll wait within the memory subsystem of the external issuer.
