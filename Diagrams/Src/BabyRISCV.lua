#!/usr/bin/env luajit
-- SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
--
-- SPDX-License-Identifier: Apache-2.0

local buffer = require"string.buffer"
local data_color = "#f4d7e3"
local xu_color = "#d4aa00"
local fe_color = "#87deaa"
local insn_color = "#aaaaff"

local own_dir = debug.getinfo(1, "S").source:match"@?(.*/)" or ""
package.path = own_dir .."?.lua;".. package.path
local Drawing = require"Drawing"

local MultiLine = Drawing.MultiLine

local function WireTextRight(out, x, y, text, dims)
  local x2 = x + 24
  local x3 = (dims and dims.w - 5 or 660) - 1.5
  MultiLine(out, {x, y, ">", x3})
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle" stroke="white" fill="white" stroke-width="10" stroke-linecap="round" stroke-linejoin="round">%s</text>]], x2, y + 1, text)
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">%s</text>]], x2, y + 1, text)
end

local function BabyRISC(args)
  local eth = args.eth
  local out = buffer.new()
  local nul = buffer.new()
  local dims = {w = 665, h = eth and 431 or 583}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local y_spacing_xu = 60
  local y_pad_mux = 15
  local y_spacing_mem = 5

  local iram = Drawing.RectText(out, {x = 330.5, y = 5.5, w = 200, h = 50, color = data_color}, {"Instruction RAM", "16 KiB".. (eth and "" or " (NC only)")})
  local ic = Drawing.RectText(out, {x = iram.x, y = iram.bottom + y_spacing_mem, w = iram.w, h_text = iram.h, h = iram.h + 30, color = data_color}, {"Instruction Cache", eth and "½ KiB" or "½ KiB or 2 KiB"})
  local pf_pad_x = 15
  local prefetcher = Drawing.RectText(out, {x = ic.x + pf_pad_x, right = ic.right - pf_pad_x, h = 27, bottom = ic.bottom - y_spacing_mem, color = xu_color}, "Prefetcher")
  local iram_ic_mux = Drawing.Mux(out, {right = iram.x - 20, y = iram.y_middle - y_pad_mux, w = 10, bottom = ic.y_middle + y_pad_mux}, "<")
  for _, target in ipairs{iram, ic} do
    MultiLine(out, {iram_ic_mux.right, target.y_middle, ">", target.x, head = false})
  end

  local frontend = Drawing.RectText(out, {right = iram_ic_mux.x - 40, y = iram_ic_mux.y, w = 115, h = iram_ic_mux.h, color = xu_color}, {"Frontend", "(two stages)"})
  Drawing.LineTextAbove(out, {frontend.right, frontend.y_middle}, {iram_ic_mux.x, frontend.y_middle}, "32b")

  local pc = Drawing.RectText(out, {right = frontend.x - 10, w = 35, bottom = frontend.bottom, h = (frontend.h - 10) * 0.5, color = data_color}, {[[<tspan font-family="monospace">pc</tspan>]], "32b"})
  local gdb = Drawing.RectText(out, {x = 5.5, right = pc.x - 10, y = pc.y, bottom = pc.bottom, color = xu_color}, {"GDB/Debug","Interface"})
  local bp = Drawing.RectText(out, {x = 5.5, right = pc.right, y = frontend.y, bottom = pc.y - 10, color = xu_color}, {"Branch","Predictor"})
  MultiLine(out, {pc.right, pc.y_middle, ">", frontend.x, head = false})
  MultiLine(out, {pc.x_middle, pc.y, "^", bp.bottom, head = false})
  MultiLine(out, {bp.right, bp.y_middle, ">", frontend.x, head = false})
  MultiLine(out, {gdb.right, gdb.y_middle, ">", pc.x, head = false})

  local ls_l1_y = ic.bottom + y_spacing_mem
  local ic_l1_y = ic.y_middle
  local l1_mux = Drawing.Mux(out, {x = ic.right + 40, y = ic_l1_y - y_pad_mux, w = iram_ic_mux.w, bottom = ls_l1_y + y_pad_mux}, ">")
  Drawing.LineTextAbove(out, {ic.right, ic_l1_y}, {l1_mux.x, ic_l1_y}, "128b")
  WireTextRight(out, l1_mux.right, l1_mux.y_middle, "L1")
  Drawing.LineTextAbove(out, {iram_ic_mux.right, ls_l1_y}, {l1_mux.x, ls_l1_y})

  local lram = Drawing.RectText(out, {x = iram.x, y = ls_l1_y + 1 + y_spacing_mem, w = iram.w, h = iram.h, color = data_color}, {"Local Data RAM", eth and "4 KiB" or "2 KiB or 4 KiB"})
  local mop_cfg = Drawing.RectText(eth and nul or out, {x = lram.x, y = lram.bottom + y_spacing_mem, w = lram.w, h = lram.h, color = data_color}, {"MOP Expander Configuration", "9x 32b (T only)"})
  for _, mem in ipairs(eth and {lram} or {lram, mop_cfg}) do
    Drawing.LineTextAbove(out, {iram_ic_mux.right, mem.y_middle}, {mem.x, mem.y_middle})
  end
  local ls_mux_bottom
  if eth then
    local ls_mux_y = lram.bottom + y_spacing_mem + 12
    for _, target in ipairs{"Ethernet TX configuration and command", "Ethernet RX configuration", "Ethernet MAC configuration", "Ethernet PCS configuration", "NoC 0 configuration and command", "NoC 1 configuration and command", "NoC overlay configuration and command", "PIC configuration and status", "Tile control / debug / status"} do
      WireTextRight(out, iram_ic_mux.right, ls_mux_y, target)
      ls_mux_bottom = ls_mux_y + y_pad_mux
      ls_mux_y = ls_mux_y + 24
    end
  else
    local mop = Drawing.RectText(out, {x = mop_cfg.right + 20, y = mop_cfg.y, w = 108, h = mop_cfg.h, color = xu_color}, {"MOP Expander", "(T only)"})
    Drawing.LineTextAbove(out, {mop_cfg.right, mop.y_middle}, {mop.x, mop.y_middle})

    local ls_mux_y = mop_cfg.bottom + y_spacing_mem + 12
    MultiLine(out, {mop.right - 20, mop.bottom + 2, "v", ls_mux_y - 2})
    MultiLine(out, {mop.right - 40, ls_mux_y - 2, "^", mop.bottom + 2})
    for _, target in ipairs{"Push Tensix instruction (not NC)", "Tensix backend configuration (not NC)", "Tensix GPRs (not NC)", "Tensix semaphores (T only)", "TTSync (T only)", "PCBufs (not NC)", "Mailboxes (not NC)", "NoC 0 configuration and command", "NoC 1 configuration and command", "NoC overlay configuration and command", "TDMA-RISC configuration and command", "PIC configuration and status", "Tile control / debug / status"} do
      WireTextRight(out, iram_ic_mux.right, ls_mux_y, target)
      ls_mux_bottom = ls_mux_y + y_pad_mux
      ls_mux_y = ls_mux_y + 24
    end
  end
  local ls_mux = Drawing.Mux(out, {x = iram_ic_mux.x, y = ls_l1_y - y_pad_mux, w = iram_ic_mux.w, bottom = ls_mux_bottom}, "<")

  local int_xu = Drawing.RectText(out, {x = frontend.x, y = frontend.bottom + y_spacing_xu, w = frontend.w, h = 40, color = xu_color}, "Integer Unit")
  local gpr_mux = Drawing.Mux(out, {right = int_xu.x - 15, w = l1_mux.w, y = frontend.bottom + 20, h = 60}, ">")
  local gpr_mux_io_spacing = (gpr_mux.h - y_pad_mux * 2) / 3
  for i = 0, 1 do
    MultiLine(out, {gpr_mux.right, int_xu.y - 10 - gpr_mux_io_spacing * i, ">", int_xu.x + 25 + gpr_mux_io_spacing * i, "v", int_xu.y - 1})
  end
  out:putf([[<text x="%d" y="%d" text-anchor="start">2x 32b</text>]], gpr_mux.right + 7, int_xu.y - 10 - gpr_mux_io_spacing - 4)
  local gprs = Drawing.RectText(out, {x = gdb.x, y = gpr_mux.y, w = gdb.w, h = gdb.h, color = data_color}, {"GPRs", "32x 32b"})
  MultiLine(out, {gdb.x_middle, gdb.bottom, "v", gprs.y, head = false})
  for i = 0, 1 do
    MultiLine(out, {gprs.right, gpr_mux.y + y_pad_mux + gpr_mux_io_spacing * i, ">", gpr_mux.x - 1})
  end

  local retire_xu = Drawing.RectText(out, {x = int_xu.x, bottom = ls_mux.bottom, w = int_xu.w, h = int_xu.h, color = xu_color}, "Retire Unit")
  MultiLine(out, {retire_xu.x - 3, retire_xu.y_middle, "<", gprs.x_middle, "^", gprs.bottom + 1})
  out:putf([[<text x="%d" y="%d" text-anchor="middle">32b</text>]], retire_xu.x - 35, retire_xu.y_middle - 4)

  local ls_xu = Drawing.RectText(out, {x = int_xu.x, y = int_xu.bottom + y_spacing_xu, w = int_xu.w, bottom = retire_xu.y - y_spacing_xu, color = xu_color}, "Load/Store Unit")
  Drawing.LineTextAbove(out, {ls_xu.right, ls_xu.y_middle}, {ls_mux.x, ls_xu.y_middle}, "32b")

  local insn_pipeline = {frontend, int_xu, ls_xu, retire_xu}
  for i = 2, #insn_pipeline do
    local from = insn_pipeline[i - 1]
    local to = insn_pipeline[i]
    Drawing.ThickArrow(out, from.x_middle, from.bottom + 1, ">>", to.x_middle, to.y - 1, insn_color, 1.5)
    out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">%s</text>]], from.x_middle + 5, (from.bottom + to.y) * 0.5, "1 Instruction")
    if i >= 3 then
      local y = from.bottom + (to.y - from.bottom) * (2/3)
      local x0 = gpr_mux.x - 10
      MultiLine(out, {from.x_middle - 5, y, "<", x0 - (x0 - gprs.right) * ((i - 3) / 2), "^", gpr_mux.y + y_pad_mux + (gpr_mux.h - y_pad_mux * 2) * ((6 - i) / 3), ">", gpr_mux.x - 1})
      out:putf([[<text x="%d" y="%d" text-anchor="middle">32b</text>]], from.x_middle - 35, y - 4)
    end
  end

  out:putf"</svg>\n"
  return tostring(out)
end

local function BabyRISC_BH(args)
  local eth = args.eth
  local vec = args.vec
  local is_t = args.is_t
  local out = buffer.new()
  local nul = buffer.new()
  local dims = {w = 725, h = eth and 431 or 583}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local y_spacing_xu = 60
  local y_pad_mux = 15
  local y_spacing_mem = 5

  local t_only = is_t and "" or " (T only)"
  local not_nc = is_t and "" or " (not NC)"

  local ic = Drawing.RectText(out, {x = 355.5, y = 5.5, w = 210, h_text = 50, h = 112, color = data_color}, {"L0 Instruction Cache", eth and "8 KiB" or "4 KiB"})
  local dc = Drawing.RectText(out, {x = ic.x, y = ic.bottom + y_spacing_mem, w = ic.w, h = 50, color = data_color}, {"L0 Data Cache", "4x 128b"})
  local lram = Drawing.RectText(out, {x = ic.x, y = dc.bottom + y_spacing_mem, w = ic.w, h = dc.h, color = data_color}, {"Local Data RAM", eth and "8 KiB" or is_t and "4 KiB" or "4 KiB or 8 KiB"})
  if not eth then
    MultiLine(out, {lram.right + 20, lram.y_middle, "<", lram.right + 2})
    out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">Separate slow path</text>]], lram.right + 23, lram.y_middle + 1)
  end
  local mop_cfg = Drawing.RectText(eth and nul or out, {x = ic.x, y = lram.bottom + y_spacing_mem, w = ic.w, h = lram.h, color = data_color}, {"MOP Expander Configuration", "9x 32b" .. t_only})

  local l1_mux = Drawing.Mux(out, {x = ic.right + 20, y = ic.y_middle - y_pad_mux, w = 10, bottom = dc.y_middle + y_pad_mux}, ">")
  for _, c in ipairs{ic, dc} do
    Drawing.LineTextAbove(out, {c.right, c.y_middle}, {l1_mux.x, c.y_middle})
  end
  WireTextRight(out, l1_mux.right, l1_mux.y_middle, "L1", dims)

  local pf_pad_x = 15
  local prefetcher = Drawing.RectText(out, {x = ic.x + pf_pad_x, right = ic.right - pf_pad_x, h = 27, bottom = ic.bottom - y_spacing_mem, color = xu_color}, "Prefetcher")
  local ttinsn_fuser = Drawing.RectText(out, {x = prefetcher.x, right = prefetcher.right, h = prefetcher.h, bottom = prefetcher.y - y_spacing_mem, color = xu_color}, ".ttinsn Fusion" .. t_only)

  local frontend = Drawing.RectText(out, {right = ic.x - 80, y_middle = ic.y_middle, w = 115, h = ic.h, color = xu_color}, {"Frontend", "(four stages)"})
  Drawing.LineTextAbove(out, {frontend.right, frontend.y_middle}, {ic.x, frontend.y_middle}, "128b")

  local pc = Drawing.RectText(out, {right = frontend.x - 10, w = 35, bottom = frontend.bottom, h = (frontend.h - 10) * 0.5, color = data_color}, {[[<tspan font-family="monospace">pc</tspan>]], "32b"})
  local gdb = Drawing.RectText(out, {x = 5.5, right = pc.x - 10, y = pc.y, bottom = pc.bottom, color = xu_color}, {"GDB/Debug","Interface"})
  local bp = Drawing.RectText(out, {x = 5.5, right = pc.right, y = frontend.y, bottom = pc.y - 10, color = xu_color}, {"Branch","Predictor"})
  MultiLine(out, {pc.right, pc.y_middle, ">", frontend.x, head = false})
  MultiLine(out, {pc.x_middle, pc.y, "^", bp.bottom, head = false})
  MultiLine(out, {bp.right, bp.y_middle, ">", frontend.x, head = false})
  MultiLine(out, {gdb.right, gdb.y_middle, ">", pc.x, head = false})

  local xu1 = Drawing.RectText(out, {x = frontend.x, y = frontend.bottom + y_spacing_xu * 1.5, w = frontend.w, h = 40, color = xu_color}, "EX1")
  do
    local x = frontend.x_middle + 10
    Drawing.ThickArrow(out, x, frontend.bottom + 1, ">>", x, xu1.y - 1, insn_color, 1.5)
    out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">%s</text>]], x + 5, (frontend.bottom + xu1.y) * 0.5, "1 Instruction")
  end

  local retire_xu = Drawing.RectText(out, {x = gdb.x, bottom = dims.h - 5.5, right = xu1.right, h = xu1.h, color = xu_color}, "Retire Unit")
  local ls_xu = Drawing.RectText(out, {right = xu1.right, y = xu1.bottom + y_spacing_xu, w = 60, bottom = retire_xu.y - y_spacing_xu, color = xu_color}, {"Load", "Store", "Unit"})
  local xu2 = Drawing.RectText(out, {right = ls_xu.x - 20, y_middle = ls_xu.y_middle, w = xu1.w - 40, h = xu1.h, color = xu_color}, "EX2")
  local xu3 = vec and Drawing.RectText(out, {right = xu2.right - 20, bottom = ls_xu.bottom, w = xu2.w, h = xu2.h, color = xu_color}, "EX3") or nil

  for _, xu in ipairs{xu2, retire_xu, ls_xu} do
    local x = xu == retire_xu and ls_xu.x - 10 or (math.max(xu1.x, xu.x) + math.min(xu1.right, xu.right)) * 0.5
    Drawing.ThickArrow(out, x, xu1.bottom + 1, ">>", x, xu.y - 1, insn_color, 1.5)
  end
  for _, xu in ipairs{ls_xu, xu2, xu3} do
    local x = xu == xu2 and vec and xu.right - 10 or xu.x_middle
    Drawing.ThickArrow(out, x, xu.bottom + 1, ">>", x, retire_xu.y - 1, insn_color, 1.5)
  end
  if xu3 then
    local x = (math.max(xu2.x, xu3.x) + math.min(xu2.right, xu3.right)) * 0.5
    Drawing.ThickArrow(out, x, xu2.bottom + 1, ">>", x, xu3.y - 1, insn_color, 1.5)
  end

  local mop = Drawing.RectText(out, {x = mop_cfg.right + 20, y = mop_cfg.y, right = dims.w - 18, h = mop_cfg.h, color = xu_color}, {"MOP Expander", not is_t and "(T only)" or nil})
  Drawing.LineTextAbove(out, {mop_cfg.right, mop.y_middle}, {mop.x, mop.y_middle})

  local ls_mux_right = dc.x - 20
  local ls_mux_y = mop_cfg.bottom + y_spacing_mem + 12
  MultiLine(out, {mop.right - 20, mop.bottom + 2, "v", ls_mux_y - 2})
  MultiLine(out, {mop.right - 40, ls_mux_y - 2, "^", mop.bottom + 2})
  local mmio_y = {}
  for i, target in ipairs{"Push Tensix instruction".. not_nc, "Tensix backend configuration".. not_nc, "Tensix GPRs".. not_nc, "TDMA-RISC".. not_nc, "Tensix Dst".. t_only, "Tensix semaphores".. t_only, "Manual TTSync".. t_only, "Mailboxes and PCBufs".. not_nc, "NoC 0 / 1 configuration and command", "NoC overlay configuration and command", "PIC configuration and status", "Tile control / debug / status"} do
    mmio_y[i] = ls_mux_y
    WireTextRight(out, ls_mux_right, ls_mux_y, target, dims)
    ls_mux_bottom = ls_mux_y + y_pad_mux
    ls_mux_y = ls_mux_y + 24
  end
  local auto_tt = Drawing.RectText(out, {right = dims.w - 18, y = mmio_y[2] - 10, w = 76, bottom = mmio_y[4] + 10, color = xu_color}, {"Auto", "TTSync", not is_t and "(T only)" or nil})
  MultiLine(out, {mop.right - 40, mmio_y[1] + 2, "v", auto_tt.y - 2})

  local ls_mux = Drawing.Mux(out, {right = ls_mux_right, y = dc.y_middle - y_pad_mux, w = 10, bottom = ls_mux_bottom}, "<")
  Drawing.LineTextAbove(out, {ls_xu.right, ls_xu.y_middle}, {ls_mux.x, ls_xu.y_middle}, "128b")
  for _, box in ipairs{dc, lram, mop_cfg} do
    Drawing.LineTextAbove(out, {ls_mux.right, box.y_middle}, {box.x, box.y_middle})
  end

  local gprs = Drawing.RectText(out, {x = gdb.x, y = gdb.bottom + 20, w = gdb.w, h = 110 + (vec and 60 or 0), color = data_color}, {"GPRs", "32x 32b", "", "FPRs", "32x 32b", vec and "" or nil, vec and "Vectors" or nil, vec and "32x 128b" or nil})
  MultiLine(out, {gdb.x_middle, gdb.bottom, "v", gprs.y, head = false})
  MultiLine(out, {retire_xu.x + 10, retire_xu.y - 2, "^", gprs.bottom + 2})
  out:putf([[<text x="%d" y="%d" text-anchor="start">%db</text>]], retire_xu.x + 13, retire_xu.y - 25, vec and 128 or 32)
  local op_mux = Drawing.Mux(out, {x_middle = (xu1.x + xu2.x) * 0.5, w = 10, y = frontend.bottom + 20, bottom = xu2.y - 10}, ">")
  local op_ports = vec and 4 or 3
  for i = 0, 2 do
    MultiLine(out, {retire_xu.x + 50 + i * 10, retire_xu.y - 2, "^", op_mux.bottom - y_pad_mux - (2 - i) * 10, ">", op_mux.x - 2})
  end
  out:putf([[<text x="%d" y="%d" text-anchor="start">3x 32b</text>]], retire_xu.x + 73, retire_xu.y - 25)
  for i = 0, op_ports - 1 do
    MultiLine(out, {gprs.right + 2, op_mux.y + y_pad_mux + i * 10, ">", op_mux.x - 2})
  end
  for i = 0, op_ports - 1 do
    MultiLine(out, {op_mux.right + 2, xu1.y - (i + 1) * 10, ">", xu1.x + (i + 1) * 10, "v", xu1.y - 2})
  end
  out:putf([[<text x="%d" y="%d" text-anchor="start">%s</text>]], op_mux.right + 5, xu1.y - op_ports * 10 - 5, op_ports .."x ".. (vec and "128b" or "32b"))

  out:putf"</svg>\n"
  return tostring(out)
end

assert(io.open(own_dir .."../Out/BabyRISCV.svg", "w")):write(BabyRISC{})
assert(io.open(own_dir .."../Out/BabyRISCV_Eth.svg", "w")):write(BabyRISC{eth = true})

assert(io.open(own_dir .."../Out/BabyRISCV_BH.svg", "w")):write(BabyRISC_BH{})
assert(io.open(own_dir .."../Out/BabyRISCV_BH_T2.svg", "w")):write(BabyRISC_BH{vec = true, is_t = true})
