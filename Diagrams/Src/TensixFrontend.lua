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

local function TensixFrontend(opts)
  local arch = opts.arch
  local out = buffer.new()
  local nul = buffer.new()
  local dims = arch == "WH" and {w = 1030, h = 910} or {w = 1035, h = 996}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local x = arch == "WH" and 5.5 or 10.5
  local fifo1_size = {32, 16, 16}
  local x_spacing = 6
  local y_spacing = 36
  local line_spacing = 20
  local wait_gates = {}
  local wait_cfgs = {}
  for i = 1, 3 do
    local fifo1_y = 85
    local fifo1
    local auto_ttsync
    if arch ~= "WH" then
      auto_ttsync = Drawing.RectText(out, {x = x, y = fifo1_y, w = 155, h = 50, color = xu_color}, {"T".. (i-1), "Auto TTSync"})
      fifo1_y = auto_ttsync.bottom + y_spacing
    end
    fifo1 = Drawing.RectText(out, {x = x, y = fifo1_y, w = 155, h = 30, color = data_color}, {"FIFO; ".. (arch == "WH" and fifo1_size[i] or "29-32") .."x 32b"})

    local mop_expander = Drawing.RectText(out, {x = fifo1.x, y = fifo1.bottom + y_spacing, right = fifo1.right, h = 50, color = xu_color}, {"T".. (i - 1), "MOP Expander"})
    local mop_cfg = Drawing.RectText(out, {x = mop_expander.right + x_spacing, y = mop_expander.y, w = 155, h = mop_expander.h, color = data_color}, {"Instructions and", "counts; 9x 32b"})
    local y = mop_expander.y + mop_expander.h * 0.3
    Drawing.ThickArrow(out, mop_expander.right - 15, y, "<-", mop_cfg.x + 10, y, "black", 1.5)
    y = mop_expander.y + mop_expander.h * 0.7
    Drawing.ThickArrow(out, mop_expander.right - 15, y, "<-", mop_cfg.x + 10, y, insn_color, 1.5)

    local text_y = (auto_ttsync or fifo1).y - y_spacing
    for j, box in ipairs{auto_ttsync or fifo1, mop_cfg} do
      for k, text in ipairs{'<tspan font-family="monospace">'.. (box ~= mop_cfg and "INSTRN_BUF_BASE" or "TENSIX_MOP_CFG_BASE").. "</tspan>", "RISCV T".. (i - 1)} do
        out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="auto">%s</text>]], box.x_middle, text_y - 5 - (k - 1) * line_spacing, text)
      end
    end
    Drawing.MultiLine(out, {mop_cfg.x_middle, text_y, "v", mop_cfg.y - 2})

    local b_text_x = mop_cfg.x + 10
    local dbg_text_x = b_text_x * 2 - mop_expander.x_middle

    local b_mux = Drawing.Mux(out, {x = mop_expander.x_middle - 20, right = dbg_text_x + 20, y = mop_expander.bottom + 75, h = 10}, "v")

    local b_text_y = b_mux.y - y_spacing + 12
    for k, text in ipairs{'<tspan font-family="monospace">INSTRN'.. (i == 1 and "" or (i - 1)) .."_BUF_BASE</tspan>", "RISCV B"} do
      out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="auto">%s</text>]], b_text_x, b_text_y - 5 - (k - 1) * line_spacing, text)
    end
    for k, text in ipairs{'bus', "Debug"} do
      out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="auto">%s</text>]], dbg_text_x, b_text_y - 5 - (k - 1) * line_spacing, text)
    end

    local fifo2 = Drawing.RectText(out, {x = x, y = b_mux.bottom + y_spacing, w = fifo1.w, h = fifo1.h, color = data_color}, {"FIFO; 8x 32b"})

    local replay_expander = Drawing.RectText(out, {x = fifo2.x, y = fifo2.bottom + y_spacing, right = fifo2.right, h = 50, color = xu_color}, {"T".. (i - 1), "Replay Expander"})
    local replay_cfg = Drawing.RectText(out, {x = replay_expander.right + x_spacing, y = replay_expander.y, w = 155, h = replay_expander.h, color = data_color}, {"Instruction buffer", "32x 32b"})
    y = replay_expander.y + replay_expander.h * 0.3
    Drawing.ThickArrow(out, replay_expander.right - 10, y, "->", replay_cfg.x + 15, y, insn_color, 1.5)
    y = replay_expander.y + replay_expander.h * 0.7
    Drawing.ThickArrow(out, replay_expander.right - 15, y, "<-", replay_cfg.x + 10, y, insn_color, 1.5)

    local fifo3 = Drawing.RectText(out, {x = x, y = replay_cfg.bottom + y_spacing, w = fifo1.w, h = fifo1.h, color = data_color}, {"FIFO; 2x 32b"})

    local wait_gate = Drawing.RectText(out, {x = fifo3.x, y = fifo3.bottom + y_spacing, right = fifo3.right, h = 50, color = xu_color}, {"T".. (i - 1), "Wait Gate"})
    local wait_cfg = Drawing.RectText(out, {x = wait_gate.right + x_spacing, y = wait_gate.y, w = 155, h = wait_gate.h, color = data_color}, {"Latched wait", "instruction; 32b"})
    Drawing.ThickArrow(out, wait_gate.right - 15, wait_gate.y_middle, "<-", wait_cfg.x + 10, wait_cfg.y_middle, "black", 1.5)
    wait_gates[i] = wait_gate
    wait_cfgs[i] = wait_cfg

    local main_insn_pipeline = {x = fifo1.x_middle, text_y, fifo1, mop_expander, b_mux, fifo2, replay_expander, fifo3, wait_gate}
    if auto_ttsync then
      table.insert(main_insn_pipeline, 2, auto_ttsync)
    end
    for j, insn_pipeline in ipairs{
      main_insn_pipeline,
      {x = b_text_x,       b_text_y, b_mux},
      {x = dbg_text_x,     b_text_y, b_mux},
    } do
      local x = insn_pipeline.x
      for k = 1, #insn_pipeline do
        local from = insn_pipeline[k - 1]
        local to = insn_pipeline[k]
        if from and to then
          local head = ">>"
          if to == b_mux then
            head = ">-"
          elseif from == b_mux then
            head = "->"
          end
          local label = (to == auto_ttsync or from == auto_ttsync) and "4 Instructions" or "1 Instruction"
          if type(from) ~= "number" then from = from.bottom + (head:sub(1, 1) == ">" and 1 or 0.5) end
          if type(to) ~= "number" then to = to.y - (head:sub(2,2) == ">" and 1 or 0.5) end
          Drawing.ThickArrow(out, x, from, head, x, to, insn_color, 1.5)
          if head ~= ">-" then
            out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">%s</text>]], x + 5, (from + to) * 0.5, label)
          end
        end
      end
    end

    if auto_ttsync then
      Drawing.MultiLine(out, {auto_ttsync.x + 8, auto_ttsync.y_middle, "<", auto_ttsync.x - 5, "v", wait_gate.y_middle, ">", wait_gate.x + 8, head = "both"})
    end

    x = mop_cfg.right + x_spacing * 2
  end

  x = wait_gates[1].x
  local y = wait_gates[1].bottom + y_spacing * 2 + 10
  local xu_labels = {
    {"Sync Unit", "", uops = 3, tall = true},
    {"Unpackers", "", cfg = "<-"},
    {"Matrix Unit", "(FPU)", cfg = "<-"},
    {"Packers", "", cfg = "<-"},
    {"Vector Unit", "(SFPU)"},
    {"Scalar Unit", "(ThCon)", cfg = arch == "WH" and "->" or nil},
    {"Configuration", "Unit", cfg = "<>", uops = 3},
    {"Mover", "", cfg = "<>"},
    {"Miscellaneous", "Unit", uops = 3, tall = true},
  }
  local xus = {}
  local xu_w_ideal = (wait_cfgs[#wait_cfgs].right - x - (#xu_labels - 1) * x_spacing) / #xu_labels
  local xu_w = math.floor(xu_w_ideal)
  local error_term = 0
  for i, text in ipairs(xu_labels) do
    local this_w = xu_w
    error_term = error_term + (xu_w_ideal - this_w)
    if error_term >= 0.5 then
      this_w = this_w + 1
      error_term = error_term - 1
    end
    local xu = Drawing.RectText(out, {x = x, y = y, w = this_w, h = 100 + (text.tall and 50 + x_spacing or 0), h_text = 70, color = xu_color}, text)
    xus[i] = xu
    x = xu.right + x_spacing
  end

  local xu_mux = Drawing.Mux(out, {x = xus[1].x_middle - 20, right = xus[#xus].x_middle + 20, y = wait_gates[1].bottom + y_spacing, h = 10}, "^")
  for i, xu in ipairs(xus) do
    local x = xu.x_middle
    Drawing.ThickArrow(out, x, xu_mux.bottom + 0.5, "->", x, xu.y - 1, insn_color, 1.5)
    local uops = xu_labels[i].uops or 1
    out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">%s</text>]], x + 5, (xu_mux.bottom + xu.y) * 0.5, uops .." Instruction".. (uops > 1 and "s" or ""))
  end

  local backend_cfg = Drawing.RectText(out, {x = xus[2].x, right = xus[8].right, y = xus[2].bottom + x_spacing, h = 50, color = data_color}, {"Backend Configuration", arch == "WH" and "354x 32b" or "398x 32b"})
  for i, xu in ipairs(xus) do
    local cfg_head = xu_labels[i].cfg
    if cfg_head then
      local x = xu.x_middle
      local y0 = xu.bottom
      local y1 = backend_cfg.y
      y0 = y0 - (cfg_head:sub(1,1) == "-" and 10 or 15)
      y1 = y1 + (cfg_head:sub(2,2) == "-" and 10 or 15)
      Drawing.ThickArrow(out, x, y0, cfg_head, x, y1, "black", 1.5)
    end
  end

  local cfg_xu = xus[1]
  for i = 1, 3 do
    Drawing.MultiLine(out, {cfg_xu.x + 8 * i, cfg_xu.y, "^", xu_mux.y - 8 * (4 - i), ">", wait_cfgs[i].x_middle, "^", wait_cfgs[i].bottom + 2})
  end
  local semaphores = Drawing.RectText(out, {x = cfg_xu.x + 3, right = cfg_xu.right - 3, bottom = cfg_xu.bottom - 3, h = 42, color = data_color}, {"Semaphores", "8x 4b"})
  local mutexes = Drawing.RectText(out, {x = semaphores.x, right = semaphores.right, bottom = semaphores.y - 3, h = 42, color = data_color}, {"Mutexes", arch == "WH" and "7x 2b" or "4x 2b"})

  for i, wg in ipairs(wait_gates) do
    local x = wg.x_middle
    Drawing.ThickArrow(out, x, wg.bottom + 1, ">-", x, xu_mux.y - 0.5, insn_color, 1.5)
  end

  local bottom_text_y = backend_cfg.bottom + y_spacing
  for _, label in ipairs{
    {x = xus[7].x_middle, y = backend_cfg.bottom - 10, "RISCV B / T0 / T1 / T2", '<tspan font-family="monospace">TENSIX_CFG_BASE</tspan>'},
    {x = semaphores.right - 15, y = semaphores.bottom - 10, "RISCV T0 / T1 / T2", '<tspan font-family="monospace">0xFFE80020</tspan>'},
  } do
    Drawing.MultiLine(out, {label.x, bottom_text_y, "^", label.y, head = "both"})
    for k, text in ipairs(label) do
      out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="hanging">%s</text>]], label.x, bottom_text_y + 5 + (k - 1) * line_spacing, text)
    end
  end

  out:putf"</svg>\n"
  return tostring(out)
end

assert(io.open(own_dir .."../Out/TensixFrontend.svg", "w")):write(TensixFrontend{arch = "WH"})
assert(io.open(own_dir .."../Out/TensixFrontend_BH.svg", "w")):write(TensixFrontend{arch = "BH"})
