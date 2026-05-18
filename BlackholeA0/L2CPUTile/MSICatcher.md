# MSI Catcher

The MSI catcher is a small memory-mapped FIFO attached to the platform-level interrupt controller (PLIC). Some care is required due to its relatively small size (16x 32-bit entries), but this notwithstanding, it is a convenient way to atomically raise an interrupt via the NoC (†).

> (†) The other way to raise an interrupt via the NoC is the 128-bit vector in the address space starting at `0x0000_2001_0404`, where bit #`i` maps to PLIC source ID #`5+i`. The x280 cores within the L2CPU tile can perform atomic "Zaamo" operations on this vector, but the NoC cannot, which makes said vector difficult to use robustly. Furthermore, each of sources #5 through #10 (inclusive) are driven by the _union_ of a bit from the vector and some hardware-defined source (for example, for #6 and #7, that source is the MSI Catcher), so the first six bits of the vector should not be used.

## Memory map

<table><thead><tr><th>Address (x280 physical)</th><th>Write Behavior</th><th>Read Behavior</th></tr></thead>
<tr><td><code>0x0000_2006_0000</code></td><td><pre><code>if (queue.size() &lt; 16) {
  queue.push(write_value);
} else {
  /* No effect */
}</code></pre></td><td><pre><code>if (queue.size() == 0) {
  return 0;
} else {
  return queue.pop();
}</code></pre></td></tr>
<tr><td><code>0x0000_2006_0004</code></td><td>No effect</td><td><pre><code>queue.clear();
return 0;</code></pre></td></tr>
<tr><td><code>0x0000_2006_0008</code></td><td>No effect</td><td><pre><code>return (queue.size() &lt; 16)
    | ((queue.size() != 0) &lt;&lt; 8)
    | ((queue.size() &gt;= (16 - hwm)) &lt;&lt; 9);</code></pre></td></tr>
<tr><td><code>0x0000_2006_000C</code></td><td><code>hwm = write_value;</code></td><td><code>return hwm;</code></td></tr>
</table>

When coming out of reset, `queue` is initially empty and `hwm` is initially `1`.

## Interrupts

PLIC source ID #6 will be asserted while `queue.size() != 0`, and PLIC source ID #7 will be asserted while `queue.size() >= (16 - hwm)`. These are level-sensitive interrupt sources, but as per the RISC-V Platform-Level Interrupt
Controller Specification, the PLIC will ignore the interrupt source once the PLIC has noticed the high level and set its corresponding interrupt pending bit, and will continue ignoring the source until a hart claims the interrupt and furthermore indicates that it has completed handling the interrupt.
