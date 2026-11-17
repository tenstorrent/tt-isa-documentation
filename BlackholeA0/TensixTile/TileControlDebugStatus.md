# Tile control / debug / status registers

An assortment of interesting registers exist in the address space starting at address `RISCV_DEBUG_REGS_START_ADDR` (`0xFFB12000`), which are accessible to every RISCV core and to external clients via the NoC. Amongst other things, this region of the address space includes:
* [Soft reset](SoftReset.md) (`RISCV_DEBUG_REG_SOFT_RESET_0`, `RISCV_DEBUG_REG_DISABLE_RESET`, `RISCV_DEBUG_REG_TRISC_RESET_PC_OVERRIDE` et al.)
* The debug timestamper (`RISCV_DEBUG_REG_WALL_CLOCK_L`, `RISCV_DEBUG_REG_WALL_CLOCK_H`, `RISCV_DEBUG_REG_TIMESTAMP` et al.)
* The RISCV GDB/Debug Interface (`RISCV_DEBUG_REG_RISC_DBG_CNTL_0`, `RISCV_DEBUG_REG_RISC_DBG_CNTL_1`, `RISCV_DEBUG_REG_RISC_DBG_STATUS_0`, `RISCV_DEBUG_REG_RISC_DBG_STATUS_1`)
* The debug daisychain (`RISCV_DEBUG_REG_DBG_BUS_CNTL_REG`, `RISCV_DEBUG_REG_DBG_RD_DATA`, `RISCV_DEBUG_REG_DBG_L1_MEM_REG2` et al.)
* PCBuf and TTSync configuration (`RISCV_DEBUG_REG_TRISC_PC_BUF_OVERRIDE`)
* Debug access to the Tensix instruction FIFOs (`RISCV_DEBUG_REG_INSTRN_BUF_STATUS`, `RISCV_DEBUG_REG_INSTRN_BUF_CTRL0`, `RISCV_DEBUG_REG_INSTRN_BUF_CTRL1`)
* Read-only debug access to Tensix backend configuration (`RISCV_DEBUG_REG_CFGREG_RD_CNTL`, `RISCV_DEBUG_REG_CFGREG_RDDATA`)
* [Clock gating](ClockGating.md) enables and hysteresis (`RISCV_DEBUG_REG_CG_CTRL_EN`, `RISCV_DEBUG_REG_CG_CTRL_HYST0` et al., `RISCV_DEBUG_REG_DEST_CG_CTRL`)
