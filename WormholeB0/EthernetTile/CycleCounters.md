# Cycle Counters

Two separate cycle counters are available, driven by the same clock:
* A 64-bit counter which increments by one every clock cycle, the value of which can be sampled.
* A 32-bit counter which decrements by one every clock cycle, unless it is already zero.

There's also a software-driven counter at `0xFFB9_4080`, which atomically increments by the written value whenever written to.

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

## The 32-bit counter

If the low bit of `RISCV_DEBUG_REG_WDT_CNTL` is set, then the value within `RISCV_DEBUG_REG_WDT` is decremented by one every cycle, unless it is already zero. The other bits of `RISCV_DEBUG_REG_WDT_CNTL` have no effect in Ethernet tiles.

## Memory map

See the functional specification (below) for state and functions referenced herein.

|Address|Write Behavior|Read Behavior|
|---|---|---|
|`RISCV_DEBUG_REG_WDT`<br/>`0xFFB1_21E0`|`wdt = new_val`|`return wdt`|
|`RISCV_DEBUG_REG_WDT_CNTL`<br/>`0xFFB1_21E4`|`wdt_cntl = new_val`|`return wdt_cntl`|
|`RISCV_DEBUG_REG_WDT_STATUS`<br/>`0xFFB1_21E8`|No effect|`return (wdt == 0) && (wdt_cntl & 1)`|
|`RISCV_DEBUG_REG_WALL_CLOCK_L`<br/>`0xFFB1_21F0`|`counter_high_at = counter >> 32`<br/>(No other effect)|`counter_high_at = counter >> 32`<br/>`return counter & 0xffffffff`|
|`RISCV_DEBUG_REG_WALL_CLOCK_L+4`<br/>`0xFFB1_21F4`|No effect|`return counter >> 32`|
|`RISCV_DEBUG_REG_WALL_CLOCK_H`<br/>`0xFFB1_21F8`|No effect|`return counter_high_at`|
|`ETH_CTRL_REGS_START+128`<br/>`0xFFB9_4080`|`test_sum += new_val`|`return test_sum`|

## Functional specification

Relevant state:

```c
uint64_t counter = 0;
uint32_t counter_high_at = 0;
uint32_t wdt = 0xFFFFFFFF;
uint32_t wdt_cntl;
uint32_t test_sum = 0;
```

This function executes every cycle:

```c
void EveryCycle() {
  counter += 1;
  if ((wdt != 0) && (wdt_cntl & 1)) {
    wdt -= 1;
  }
}
```
