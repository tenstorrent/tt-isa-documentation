# Debug Timestamper

The debug timestamper provides two services:
* A 64-bit counter which increments by one every clock cycle, the value of which can be sampled.
* The ability to write a stream of timestamp events out to a buffer in [L1](L1.md), where each event contains a 29-bit user-specified token along with the value of the 64-bit counter at the time of the event.

These services are mapped into the address space of the Tensix tile, and are available to any RISCV core. The address space is also available over the NoC and available to ThCon.

## The 64-bit counter

The low and high halves of the 64-bit counter are accessed separately. The low 32 bits can be obtained by reading from `RISCV_DEBUG_REG_WALL_CLOCK_L`.

If the full 64 bits are required, then there are two ways of obtaining it. If there is only one agent simultaneously reading from `RISCV_DEBUG_REG_WALL_CLOCK_L`, then the full 64 bits can be obtained by reading from `RISCV_DEBUG_REG_WALL_CLOCK_L` and then reading from `RISCV_DEBUG_REG_WALL_CLOCK_H`:
```
li t0, 0xFFB12000
lw t1, 0x1F0(t0) # RISCV_DEBUG_REG_WALL_CLOCK_L
lw t2, 0x1F8(t0) # RISCV_DEBUG_REG_WALL_CLOCK_H
# t2:t1 now contains the 64-bit value
```

If there are multiple agents simultaneously reading from `RISCV_DEBUG_REG_WALL_CLOCK_L`, then a more complex sequence is required to safely obtain the full 64 bits:
```
li t0, 0xFFB12000
retry:
lw t2, 0x1F4(t0)
lw t1, 0x1F0(t0) # RISCV_DEBUG_REG_WALL_CLOCK_L
lw t3, 0x1F4(t0)
bne t2, t3, retry
# t2:t1 now contains the 64-bit value
```

## Timestamp event streams

Writing a 32-bit value to `RISCV_DEBUG_REG_TIMESTAMP` will append an event to the configured timestamp event stream in L1. The low three bits of the written value control the size of the appended event, and the remaining 29 bits can be anything - they'll be passed through and included in the appended event. The four possible event sizes are:

|Event size|Low three bits of `header`|Event contents (as consecutive 32-bit values)|
|---:|---|---|
|128 bits|`0`|`header, counter_lo, counter_hi, 0`|
|96 bits|`4`|`header, counter_lo, counter_hi`|
|64 bits|`1`|`header, counter_lo`|
|32 bits|`2`|`(header & 0x0000ffff) + ((counter_lo & 0x001fffe0) << 11)`|

The event stream is written out to L1 in units of 128 bits; if using one of the smaller event sizes, then the event is appended to an internal write-accumulation buffer instead of going straight out to L1, and this buffer is automatically flushed once it contains 128 bits of event data. If using 64-bit or 96-bit events, the write-accumulation buffer can be flushed by writing a special value to `RISCV_DEBUG_REG_TIMESTAMP`. For any size of event, the status of the write-accumulation buffer can be queried by reading from `RISCV_DEBUG_REG_TIMESTAMP_STATUS`, from which it is possible to infer how many more events need to be appended to trigger an automatic flush. Different event sizes cannot be mixed; the write-accumulation buffer must be flushed (either automatically or manually) when changing event size.

Additional memory-mapped registers are used to configure the location of the buffer in L1; see the memory map.

## Memory map

See the functional specification (below) for state and functions referenced herein.

|Address|Write Behaviour|Read Behaviour|
|---|---|---|
|`RISCV_DEBUG_REG_WALL_CLOCK_L`<br/>`0xFFB1_21F0`|`counter_high_at = counter >> 32`<br/>(No other effect)|`counter_high_at = counter >> 32`<br/>`return counter & 0xffffffff`|
|`RISCV_DEBUG_REG_WALL_CLOCK_L+4`<br/>`0xFFB1_21F4`|No effect|`return counter >> 32`|
|`RISCV_DEBUG_REG_WALL_CLOCK_H`<br/>`0xFFB1_21F8`|No effect|`return counter_high_at`|
|`RISCV_DEBUG_REG_TIMESTAMP`<br/>`0xFFB1_21FC`|`CmdWrite(new_val)`|`return 0`|
|`RISCV_DEBUG_REG_TIMESTAMP+4`<br/>`0xFFB1_2200`|`cntl_raw = new_val`<br/>`CntlWrite(new_val)`|`return cntl_raw`|
|`RISCV_DEBUG_REG_TIMESTAMP_STATUS`<br/>`0xFFB1_2204`|`StatusWrite(new_val)`|`return StatusRead()`|
|`RISCV_DEBUG_REG_TIMESTAMP+12`<br/>`0xFFB1_2208`|`bufs[0].start = new_val`|`return bufs[0].start`|
|`RISCV_DEBUG_REG_TIMESTAMP+16`<br/>`0xFFB1_220C`|`bufs[0].end = new_val`|`return bufs[0].end`|
|`RISCV_DEBUG_REG_TIMESTAMP+20`<br/>`0xFFB1_2210`|`bufs[1].start = new_val`|`return bufs[1].start`|
|`RISCV_DEBUG_REG_TIMESTAMP+24`<br/>`0xFFB1_2214`|`bufs[1].end = new_val`|`return bufs[1].end`|

## Functional specification

Relevant state:

```c
struct {                 // To specify where to append to in L1
  bool valid = true;
  bool full = false;     // Sticky bit
  bool overflow = false; // Sticky bit
  uint32_t start;        // Multiply by 16 to get an L1 address
  uint32_t end;          // Multiply by 16 to get an L1 address
  uint32_t position = 0; // Incremented on every L1 write
} bufs[2];
struct {                 // For accumulating data to write out in units of 16 bytes
  uint32_t data[4];
  uint32_t position = 0;
  uint32_t event_size = 0;
} accum;
bool reset_streams = false;
uint32_t cntl_raw = 3;
uint64_t counter = 0;
uint32_t counter_high_at = 0;
```

This function executes every cycle:

```c
void EveryCycle() {
  counter += 1;
  if (reset_streams) {
    for (auto& buf : bufs) {
      buf.full = false;
      buf.overflow = false;
    }
    accum.position = 0;
    accum.event_size = 0;
  }
}
```

These functions are referenced by the memory map:

```c
#define APPEND_32b 2
#define APPEND_64b 1
#define APPEND_96b 4
#define APPEND_128b 0
#define FLUSH_64b 3
#define FLUSH_96b 7

void CmdWrite(uint32_t new_val) {
  switch (new_val & 7) {
  case APPEND_32b:
    SetEventSize(32);
    AppendU32((new_val & 0xffff) | ((counter & 0x001fffe0) << 11));
    break;
  case APPEND_64b:
    SetEventSize(64);
    AppendU32(new_val);
    AppendU32(counter & 0xffffffff);
    break;
  case APPEND_96b:
    SetEventSize(96);
    AppendU32(new_val);
    AppendU32(counter & 0xffffffff);
    AppendU32(counter >> 32);
    break;
  case APPEND_128b:
    SetEventSize(128);
    AppendU32(new_val);
    AppendU32(counter & 0xffffffff);
    AppendU32(counter >> 32);
    AppendU32(0);
    break;
  case FLUSH_64b:
    SetEventSize(64);
    FlushAccum();
    break;
  case FLUSH_96b:
    SetEventSize(96);
    FlushAccum();
    break;
  default:
    UndefinedBehaviour();
    break;
  }
}

void CntlWrite(uint32_t new_val) {
  bufs[0].valid = !!(new_val & 1);
  bufs[1].valid = !!(new_val & 2);
  reset_streams = !!(new_val >> 31); // Note this state is sticky; writers should pulse it high then set it back low
}

struct StatusBits {
  bool bufs0_full : 1;
  bool bufs1_full : 1;
  unsigned reserved : 2;
  bool bufs0_overflow : 1;
  bool bufs1_overflow : 1;
  unsigned reserved : 2;
  unsigned accum_pos_64b : 1;
  unsigned accum_pos_32b : 2;
  unsigned accum_pos_96b : 2;
  unsigned reserved : 1;
  unsigned bufs0_position : 18;
}

StatusBits StatusRead() {
  StatusBits result;
  result.bufs0_full = bufs[0].full;
  result.bufs1_full = bufs[1].full;
  result.bufs0_overflow = bufs[0].overflow;
  result.bufs1_overflow = bufs[1].overflow;
  result.accum_pos_64b = accum.event_size == 64 ? accum.position / 2 : 0;
  result.accum_pos_32b = accum.event_size == 32 ? accum.position : 0;
  result.accum_pos_96b = accum.event_size == 96 ? (4 - accum.position) & 3 : 0;
  result.bufs0_position = bufs[0].position;
  // NB: No way to query bufs[1].position
  return result;
}

void StatusWrite(StatusBits new_val) {
  // Clear indicated sticky bits
  if (new_val.bufs0_full) bufs[0].full = false, bufs[0].position = 0;
  if (new_val.bufs1_full) bufs[1].full = false, bufs[1].position = 0;
  if (new_val.bufs0_overflow) bufs[0].overflow = false;
  if (new_val.bufs1_overflow) bufs[1].overflow = false;
}

void SetEventSize(uint32_t new_event_size) {
  if (accum.event_size == 0) {
    accum.event_size = new_event_size;
  } else if (accum.event_size != new_event_size) {
    UndefinedBehaviour();
  }
}

void AppendU32(uint32_t value) {
  accum.data[accum.position++] = value;
  if (accum.position >= 4) {
    FlushAccum();
  }
}

void FlushAccum() {
  while (accum.position < 4) {
    accum.data[accum.position++] = 0;
  }
  accum.position = 0;
  accum.event_size = 0; // Next event can be any size
  // Find first buffer with space, append 16 bytes to it.
  // Note that start/position/end are all in units of 16 bytes.
  for (auto& buf : bufs) {
    if (buf.valid && buf.start + buf.position <= buf.end) {
      memcpy((buf.start + buf.position) * 16, accum.data, 16); // Atomic write of 16 bytes to L1
      buf.position += 1;
      if (buf.start + buf.position > buf.end) {
        buf.full = true;
      }
      return;
    }
  }
  // No buffers with space; mark all valid buffers as overflowed.
  for (auto& buf : bufs) {
    if (buf.valid) {
      buf.overflow = true;
    }
  }
}
```
