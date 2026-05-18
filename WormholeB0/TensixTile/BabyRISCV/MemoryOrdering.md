# Memory Ordering

Although the "baby" RISCV cores are typically described as being in-order cores, significant re-ordering can occur _within_ their Load/Store Units. To ensure correct race-free operation, the programmer (or compiler writer) should be aware of memory ordering.

## Mechanical description

The Load/Store Unit contains a four-entry store queue and an eight-entry retire-order queue. These queues are important for describing when instructions can enter or leave the Load/Store Unit:

<table><thead><tr><th/><th>Load instructions</th><th>Store instructions</th><th>Other instructions</th></tr></thead>
<tr><th>Requirements to enter Integer Unit</th><td colspan="3">Correct values available for all register operands (and as instructions enter in order, correct values must also have been available for the register operands of all earlier instructions)</td></tr>
<tr><th>Requirements to enter Load/Store Unit</th><td>Space available in retire-order queue, space available in store queue, no conflicting store in store queue</td><td colspan="2">Space available in retire-order queue, space available in store queue</td></tr>
<tr><th>Action upon entering Load/Store Unit</th><td>Append to retire-order queue, emit read-request into the memory subsystem</td><td>Append to retire-order queue, append to store queue (NB: does <em>not</em> immediately emit a write-request into the memory subsystem)</td><td>Append to retire-order queue</td></tr>
<tr><th>Requirements to leave Load/Store Unit</th><td>Reached front of retire-order queue, read-response obtained from memory subsystem</td><td>Reached front of retire-order queue (NB: might or might not still be in store queue; stores can retire <em>before</em> their write-request makes it into the memory subsystem)</td><td>Reached front of retire-order queue</td></tr>
</table>

The memory subsystem is shown on the pipeline diagram as the huge mux to the right of the Load/Store Unit, along with everything to the right of that mux. It can accept _either_ one read-request or one write-request every cycle, and it can also return one read-response every cycle (NB: write-requests are fire-and-forget; write-acknowledgements are _not_ returned from the memory subsystem). The mux is another source of re-ordering; the mux _itself_ can't re-order requests, but each of its outgoing branches is independent, and each of them can take a different number of cycles to process requests and return responses. One final source of re-ordering can occur for mailboxes, as another downstream mux splits out mailbox read-requests from mailbox write-requests and also splits out requests to different mailboxes.

The store queue is drained automatically; whenever possible, entries are popped from the store queue and emitted as write-requests into the memory subsystem. Incoming loads _usually_ have priority, but hardware guarantees eventual forward progress of the store queue. Note that the store queue is drained completely independently of the retire-order queue; stores enter both queues at the same time, but can leave them at different times, and can leave either queue first.

Once a request has been _emitted_ into the memory subsystem, it will work its way through the various muxes and queues within the memory subsystem before eventually reaching the correct memory region, at which point the request will be _processed_:
* For write-requests, processing means _actually_ writing the value to long-term storage. Subsequent read-requests will observe the stored value. For memory addresses that are actually FIFOs, processing means pushing onto the FIFO.
* For read-requests, processing means reading the value from long-term storage and sending a read-response back to the issuer. The response will work its way back through the memory subsystem, and the issuer will _obtain_ the read-response some time later. For memory addresses that are actually FIFOs, processing means popping from the FIFO: the request will remain unprocessed until a read-response can be sent (and therefore cause subsequent requests against the same memory region to stall before they reach the memory region). A similar remark applies to memory addresses that are a more exotic kind of synchronization device: the request will only be processed when the relevant wait condition allows a read-response to be sent.

Most memory regions can process at most one read-request or write-request per cycle, thus trivially allowing a strict total order of processing requests at the scope of a memory region. The notable exception to this is L1, which can handle 16 simultaneous requests per cycle: one per bank per cycle. Thankfully, each L1 access port ensures that no reordering happens as requests pass through that port: the request at the front of the queue will cause head-of-line blocking if the bank it wants to access is busy, even if a request behind it in that same port's queue wants to access an idle bank.

For reference, the pipeline diagram is:

![](../../../Diagrams/Out/BabyRISCV.svg)

## Instruction pairings

The consequences of the mechanical description can be worked through for various pairs of instructions:

<table><thead><tr><th>Assembly code</th><th>Behavioral guarantees</th><th>Remaining dangers</th></tr></thead>
<tr><td>Load then load:<pre><code>lw t0, 0(t1)
lw t2, 0(t3)</code></pre></td><td>The earlier load (from <code>0(t1)</code>) will emit a read-request <i>before</i> the later load (from <code>0(t3)</code>) emits a read-request.<br/><br/>If the two loads are from the same region of memory, the two requests will be processed in order.</td><td>The later load might emit a read-request <i>before</i> the earlier load's read-response has been obtained.<br/><br/>If the two loads are to different regions of memory, the later load might have its request processed <i>before</i> the earlier load has its processed.</td></tr>
<tr><td>Load then store:<pre><code>lw t0, 0(t1)
sw t2, 0(t3)</code></pre></td><td>The load will emit a read-request <i>before</i> the store emits a write-request.<br/><br/>If the load and the store are against the same region of memory, the two requests will be processed in order, and so the read-response for load will contain the old value rather than any value written by the store.</td><td>The store might emit a write-request <i>before</i> the load's read-response has been obtained.<br/><br/>If the load and the store are against different regions of memory, the store might have its request processed <i>before</i> the load has its processed.</td></tr>
<tr><td>Store then store:<pre><code>sw t0, 0(t1)
sw t2, 0(t3)</code></pre></td><td>The earlier store (to <code>0(t1)</code>) will emit a write-request <i>before</i> the later store (to <code>0(t3)</code>) emits a write-request.<br/><br/>If the two stores are to the same region of memory, the two requests will be processed in order. In particular, if the byte address ranges of the two stores overlap, and the memory region isn't a FIFO, then the later store will (partially or entirely) overwrite the earlier store.</td><td>The later store might emit a write-request <i>before</i> the earlier store's write-request has been processed.<br/><br/>If the two stores are to different regions of memory, the later store might have its request processed <i>before</i> the earlier store has its processed.</td></tr>
<tr><td>Store then load:<pre><code>sw t0, 0(t1)
lw t2, 0(t3)</code></pre></td><td>If the starting byte address of the store (<code>0 + t1</code>) <i>exactly</i> equals the starting byte address of the load (<code>0 + t3</code>), then the store will emit a write-request <i>before</i> the load emits a read-request.<br/><br/>If the store and the load are against the same region of memory, the requests will be processed in the same order as they were emitted.<br/><br/>In particular, if both of the above points are true, and furthermore the memory address refers to a regular memory location (or to a device with memory-like semantics), then the load's read-response will return the value written by the store.</td><td><b>If the starting byte addresses are not exactly equal, there is no guarantee: either of the two instructions could emit a request first.</b><br/><br/>The request which is emitted second might be emitted before the other request has been processed.<br/><br/>If the store and the load are against different regions of memory, either request might be processed first.</td></tr>
</table>

## Enforcing stronger ordering

The RISCV `fence` instruction is treated as a no-op by the baby RISCV cores, so it **cannot** be used to enforce stronger ordering. Instead, the behaviors outlined in the mechanical description need to be exploited to obtain stronger ordering.

It is always the case that a load's read-request is emitted before a subsequent memory operation's request is emitted.

To ensure that a load's read-response has been obtained before a subsequent memory operation's request is emitted, any of the following are sufficient:
* The result of the load is written to some register (other than `x0`), and the subsequent memory operation directly consumes that same register. This is exploiting the fact that the subsequent memory operation cannot enter the Integer Unit until correct values are available for its register operands.
* The result of the load is written to some register (other than `x0`), and some other instruction between the load and the subsequent memory operation consumes that same register. Note that the result (if any) of that other instruction does not need to be used in any way. This is exploiting the fact that the other instruction cannot enter the Integer Unit until correct values are available for its register operands, and that earlier instructions must enter the Integer Unit before later instructions can.
* At least seven other instructions are executed between the load and the subsequent memory operation. This is exploiting the fact that the retire-order queue has a capacity of eight instructions, and that loads exhibit head-of-line blocking until their read-response has been obtained. If there are not enough useful instructions available for this purpose, `nop` instructions can be used for this purpose.

To ensure that a store's write-request has been emitted before a subsequent memory operation's request is emitted, any of the following are sufficient:
* The subsequent memory operation is itself another store.
* The subsequent memory operation has the same starting byte address as the original store's starting byte address.
* At least three other store instructions (to any address) are executed between the original store and the subsequent memory operation. This is exploiting the fact that the store queue has a capacity of four instructions, and neither loads nor stores can enter the Load/Store Unit if the store queue is full. If there are not enough useful store instructions in the program for this purpose, various addresses exist which will discard any stores performed against them - `RISCV_TDMA_REG_STATUS` is one such address.

There is no _general_ mechanism to ensure that a store's write-request has been processed before a subsequent memory operation's request is emitted. However, it is possible (via different means) in many cases:
* If the address of the store denotes a memory location which is readable as well as writable, and reads from that location do not trigger undesirable side effects, then the store can be followed by a load from the same address, at which point the store's write-request will be processed before the load's read-request, and one of the previously-described mechanisms can be used to ensure that the load's read-response is obtained before the subsequent memory operation's request is emitted.
* As a weaker case of the above, if the store is to a memory region which has _some_ other location in that region which is readable without triggering undesirable side effects, then the store can be followed by a load from the same region, one of the previously-described mechanisms can be used to ensure that the store's write-request is emitted before the load's read-request, these two requests will be processed in order by the memory region in question, and one of the previously-described mechanisms can be used to ensure that the load's read-response is obtained before the subsequent memory operation's request is emitted.
* If the address of the store denotes an instruction FIFO or command FIFO, the effects of that instruction or command (or of a later instruction or command in the same FIFO) can be observed: once the effect has been observed, the store's write-request must have happened. For example, the effects of a Tensix instruction to modify a Tensix semaphore or Tensix GPR can be observed by issuing load instructions to poll the value of the relevant semaphore or GPR.

One very common scenario is to perform a store to Tensix GPRs or to Tensix Backend Configuration, and then perform a store to push a Tensix instruction, where execution of that instruction is intended to consume the just-written GPR or configuration. The usual rules for store-then-store apply: the write-requests will be _emitted_ in order, but as the stores are to different regions of memory, they might not be _processed_ in order: the Tensix instruction could execute _before_ the GPR write or configuration write takes effect. There are two recommended options to avoid the race condition here:
* Use the previously-described mechanisms to ensure that the earlier store's write-request has been processed before the instruction store's write-request is emitted. This involves `sw` for the earlier store, followed by `lw` of the same address to read the value back, followed by an instruction making use of the `lw` result, followed by `sw` for the instruction store.
* Push an appropriate Tensix `STALLWAIT` instruction in between the earlier store and the desired instruction store. This involves `sw` for the earlier store, followed by `sw` of an appropriate `STALLWAIT` instruction, followed by `sw` for the desired instruction. The `STALLWAIT` instruction uses special hooks into the memory subsystem to ensure that the programmer's intended ordering is achieved, but it only applies to the case of stores to Tensix GPRs or to Tensix Backend Configuration followed by a store to push a Tensix instruction.

## Other cores and clients

The memory ordering rules on this page are mostly describing the semantics of a single baby RISCV core interacting with memory. Things get more complicated when multiple RISCV cores are interacting with memory, or when other clients (for example, the NoC, the unpackers, the packers, and so forth) are interacting with memory. Things can also get more complicated when a RISCV core is _instructing_ another client to interact with memory, as the RISCV core tends to issue those instructions by performing memory stores.

### Interacting through L1, same access port

If two clients are interacting through L1, and those two clients go through the same L1 access port, then each client will be emitting its own stream of read/write requests, and those streams will be combined into a single ordered stream as they reach the L1 access port. The L1 access port will process its requests in order: the request at the front of the queue will cause head-of-line blocking if the bank it wants to access is busy, even if a request behind it in that same port's queue wants to access an idle bank.

### Interacting through L1, different access port

If two clients are interacting through L1, and those two clients go through different L1 access ports, then the point of synchronization becomes the L1 banks rather than the L1 access ports. Each bank can process at most one request per cycle, allowing a strict total order for processing of all the requests targeting any given bank.

### Interacting through other memory regions

If two clients are interacting through a memory region _other_ than L1, then each client will be emitting its own stream of read/write requests against that region, and those streams will be combined into a single ordered stream as they reach the memory region. Each memory region can process at most one request per cycle, allowing a strict total order for processing of all the requests targeting any given region.

## Examples of non-intuitive memory ordering

### Mailbox read from the future

The following example, if executed on RISCV B, with the B to B mailbox initially empty, will result in the `t2` register containing the value `123`, even though the store which pushes `123` into the mailbox appears later in the instruction stream than the load to `t2`:
```
li t0, 0xFFEC0000 # TENSIX_MAILBOX0_BASE. When running on RISCV B, this is the B to B mailbox.
li t1, 123
lw t2, 0(t0) # Pop from mailbox - will end up popping 123 even though it hasn't been pushed yet!
sw t1, 0(t0) # Push 123 to mailbox
```
This is because the read and write sides of a mailbox are considered to be different memory regions, so while the `lw`'s read-request is emitted before the `sw`'s write-request is emitted, the `sw`'s write-request can be processed before the `lw`'s read-request is processed (and indeed the `sw`'s write-request _must_ be processed first, in order to make the mailbox non-empty). Thankfully, mailboxes are the only scenario in which the same memory address can be in different memory regions depending on whether it is being read from or written to.

Variations on this example can be used to probe the capacity of the queues within the Load/Store Unit, and to probe the capabilities of the register operand forwarding network. For example, the following example still results in the `t2` register containing the value `123`:
```
li t0, 0xFFEC0000 # TENSIX_MAILBOX0_BASE. When running on RISCV B, this is the B to B mailbox.
li t1, 123
lw t2, 0(t0) # Pop from mailbox - will end up popping 123 even though it hasn't been pushed yet!
mv t3, t0
addi t3, t3, 0
addi t3, t3, 0
addi t3, t3, 0
addi t3, t3, 0
addi t3, t3, 0
sw t1, 0(t3) # Push 123 to mailbox
```
However, replacing _any_ of the `addi` instructions in the above example with a `nop` instruction will mean that the `sw` instruction never executes (i.e. the example will hang forever): the instruction _after_ the `nop` will not be able to _enter_ the Integer Unit, as the correct value for its `t3` operand will not be available, as the instruction _before_ the `nop` which writes to `t3` will be sitting _within_ the retire-order queue of the Load/Store Unit, and operand forwarding is only possible from an instruction _as_ it enters or leaves the Load/Store Unit, not when it is sitting _within_ the unit. This example seems esoteric at first, but understanding it is crucial for optimal scheduling of instructions for the purpose of hiding load latency.

### Sub-word load not observing previous store

The following example looks like it _should_ always end up setting `t1` to zero, as the byte address range accessed by the load is a strict subset of the byte address range accessed by the store, but in fact `t1` sometimes ends up containing whatever was in memory prior to the store happening:
```
li t0, 0xFFB00000 # MEM_LOCAL_BASE (could also use a random address in L1)
sw x0, 0(t0)
lhu t1, 2(t0)
```
This is because the load instruction is (arguably incorrectly) allowed to enter the Load/Store Unit even if the store instruction is still waiting in the store queue, as conflict detection is performed based on just the starting byte addresses, and `0 + t0` does _not_ equal `2 + t0`.

### Cross-core signalling using mailboxes

The following example is trying to have RISCV B write a value to L1, and have RISCV T0 read the value that was written, and use a mailbox to signal that RISCV B has finished writing and that RISCV T0 can start reading:
<table><tr><th>RISCV B</th><th>RISCV T0</th></tr>
<tr><td><pre><code>li t0, 0xFFEC1000 # B to T0 mailbox (B write side)
li t1, 123
sw t1, 0x124(x0) # Random address in L1
sw x0, 0(t0)     # Mailbox push</code></pre></td><td><pre><code>li t2, 0xFFEC0000 # B to T0 mailbox (T0 read side)<br/>
lw x0, 0(t2)     # Mailbox pop
lw t3, 0x124(x0) # Random address in L1</code></pre></td></tr>
</table>

The memory ordering rules _do_ guarantee that RISCV B's first `sw` emits a write-request before RISCV B's second `sw` emits a write-request, and that RISCV T0's first `lw` emits a read-request before RISCV T0's second `lw` emits a read-request, and the semantics of mailboxes ensure that the write-request pushing to the mailbox is processed before the read-request popping from the mailbox is processed. However, the rules do _not_ guarantee that RISCV B's write-request to L1 is processed before RISCV T0's read-request from L1 is processed. To get the desired behavior, a few extra instructions are required:

<table><tr><th>RISCV B</th><th>RISCV T0</th></tr>
<tr><td><pre><code>li t0, 0xFFEC1000 # B to T0 mailbox (B write side)
li t1, 123
sw t1, 0x124(x0) # Random address in L1
lw t4, 0x124(x0) # Read it back
addi x0, t4, 0   # Consume the read result
sw x0, 0(t0)     # Mailbox push</code></pre></td><td><pre><code>li t2, 0xFFEC0000 # B to T0 mailbox (T0 read side)<br/>
lw t5, 0(t2)     # Mailbox pop
addi x0, t5, 0   # Consume the read result
lw t3, 0x124(x0) # Random address in L1</code></pre></td></tr>
</table>
