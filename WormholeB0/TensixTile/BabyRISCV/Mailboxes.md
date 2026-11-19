# Mailboxes

There are 16 mailboxes within each Tensix tile, one _from_ each of RISCV (B, T0, T1, T2) _to_ each of RISCV (B, T0, T1, T2). Note that there are no mailboxes to or from RISCV NC. Notwithstanding RISCV NC, each RISCV can read from the four mailboxes which go to it, and write to the four mailboxes which go from it. Mailboxes cannot be accessed by the NoC or by the Tensix coprocessor; they are exclusively for the RISCV cores.

Each mailbox is a FIFO queue of 32-bit values. Writes will push a value onto the queue, whereas reads will either pop a value or query whether any values are present. It is not possible to pop from an empty FIFO; a read attempting to do so will not generate a read-response until the FIFO is subsequently written to. For the purposes of memory ordering, the read and write sides of each mailbox count as separate memory regions, even though their memory addresses are identical.

Each mailbox can hold up to four 32-bit values. Furthermore, considering all four mailboxes that any given RISCV can write to, those four mailboxes in aggregate can only hold four 32-bit values (for example, one value in each mailbox, or four values in one mailbox and the other three empty). Attempting to push more values than this will cause the writes to sit in shared buffers within the memory subsystem. If those shared buffers become full, the issuing RISCV will be stalled until space becomes available.

See also [PCBufs](PCBufs.md) for separate FIFO queues from RISCV B to each of RISCV (T0, T1, T2).

## Memory map

The mailbox referenced by a particular address depends on three things: the address, the issuing RISCV, and whether the access is a read or a write.

<table><thead><tr><th>Name and address range</th><th>RISCV&nbsp;B</th><th>RISCV&nbsp;T0</th><th>RISCV&nbsp;T1</th><th>RISCV&nbsp;T2</th></tr></thead>
<tr><td><code>TENSIX_MAILBOX0_BASE</code><br/><code>0xFFEC_0000</code> to <code>0xFFEC_0FFF</code></td><td>B to B</td><td>Write: T0 to B<br/>Read: B to T0</td><td>Write: T1 to B<br/>Read: B to T1</td><td>Write: T2 to B<br/>Read: B to T2</td></tr>
<tr><td><code>TENSIX_MAILBOX1_BASE</code><br/><code>0xFFEC_1000</code> to <code>0xFFEC_1FFF</code></td><td>Write: B to T0<br/>Read: T0 to B</td><td>T0 to T0</td><td>Write: T1 to T0<br/>Read: T0 to T1</td><td>Write: T2 to T0<br/>Read: T0 to T2</td></tr>
<tr><td><code>TENSIX_MAILBOX2_BASE</code><br/><code>0xFFEC_2000</code> to <code>0xFFEC_2FFF</code></td><td>Write: B to T1<br/>Read: T1 to B</td><td>Write: T0 to T1<br/>Read: T1 to T0</td><td>T1 to T1</td><td>Write: T2 to T1<br/>Read: T1 to T2</td></tr>
<tr><td><code>TENSIX_MAILBOX3_BASE</code><br/><code>0xFFEC_3000</code> to <code>0xFFEC_3FFF</code></td><td>Write: B to T2<br/>Read: T2 to B</td><td>Write: T0 to T2<br/>Read: T2 to T0</td><td>Write: T1 to T2<br/>Read: T2 to T1</td><td>T2 to T2</td></tr>
</table>

Once the particular mailbox has been determined, the functional model for writes is:
```python
while mailbox.full or sum(mb.size for mb in issuing_core_writable_mailboxes) >= 4:
  wait
mailbox.push(value)
```

For reads, two operations are possible: non-blocking query whether the mailbox has anything available to read, and blocking pop. The functional model is:
```python
if address & 4:
  return 0 if mailbox.empty else 1
else:
  while mailbox.empty:
    wait
  return mailbox.pop()
```

Although any address within the address range can be used, it is conventional to always use `TENSIX_MAILBOX{i}_BASE` for writes, and either `TENSIX_MAILBOX{i}_BASE + 0` or `TENSIX_MAILBOX{i}_BASE + 4` for reads.

Note that the `wait`s in the above happen within the memory subsystem; they prevent the memory region in question from processing the next request, but they do not _necessarily_ prevent the issuing RISCV from executing some more RISCV instructions.

## Soft reset

When a RISCV enters [soft reset](../SoftReset.md#riscv-soft-reset), the values in the four mailboxes it writes are discarded. A blocking pop of an empty mailbox waits within the writer's side of the mailbox, not the reader's, which has these consequences:
* If the writer enters soft reset while a pop of one of its mailboxes is waiting, the pop is forgotten, and the reader waits forever: a value the writer pushes after leaving reset stays in the mailbox for the reader's next read, but never completes the forgotten pop. A pop that is issued while the writer is held in soft reset is forgotten the same way. Only soft reset of the reader ends the wait.
* If the reader enters soft reset while its pop is waiting and the writer does not, the pop remains waiting within the writer's side: the next value pushed to that mailbox completes it and is lost, and until that push, a read of that mailbox by the reader (a query included) waits.

Software must not soft reset one side of a mailbox while a pop of that mailbox may be waiting; it should instead put the reader and the writer into soft reset together, with a single write to `RISCV_DEBUG_REG_SOFT_RESET_0`. A pop that is waiting when its writer enters soft reset, or that is issued while its writer is held in soft reset, is `UndefinedBehavior`, as the reader can hang forever. Soft reset of the reader alone while its pop is waiting is `NonContractualBehavior`.

## Memory ordering

When writing to a mailbox, it is usually the case that the programmer wants the mailbox write-request to be processed _after_ all earlier write-requests have been processed. When reading from a mailbox, it is usually the case that the programmer wants the mailbox read-response to be obtained _before_ any later read-requests are emitted. Neither of these things happen by default; see [memory ordering](MemoryOrdering.md) for details on how to avoid race conditions and ensure that they do happen.
