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

local function PackerPipeline()
  local out = buffer.new()
  local nul = buffer.new()
  local dims = {w = 836, h = 1069}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local y_spacing = 20
  local y_spacing_lbl = 40
  local xu_h = 42

  local iag = Drawing.RectText(out, {x = 180.5, y = 5.5, w = 170 * 3 + 20, h = xu_h, color = xu_color}, "Input Address Generator and Datum Count")
  local dst = Drawing.RectText(out, {x = iag.x, y = iag.bottom + y_spacing, w = (iag.w - 20) / 3, h = 50, color = data_color}, {"Datums from", [[<tspan font-family="monospace">Dst</tspan>]]})
  local l1_src = Drawing.RectText(out, {right = iag.right, w = dst.w, y = dst.y, w = dst.w, h = dst.h, color = data_color}, {"Datums from L1", "(Packer 0 only)"})
  local zero_src = Drawing.RectText(out, {x = dst.right + 10, right = l1_src.x - 10, y = dst.y, h = dst.h, color = data_color}, {"Datums from", [[<tspan font-family="monospace">/dev/null</tspan>]]})
  for _, box in ipairs{dst, l1_src, zero_src} do
    Drawing.MultiLine(out, {box.x_middle, iag.bottom + 1, "v", box.y - 2})
  end

  local fc1 = Drawing.RectText(out, {x = dst.x, w = dst.w, y = dst.bottom + y_spacing, h = xu_h, h_text = xu_h + 2, color = xu_color}, {"Early Format", "Conversion"})
  local em = Drawing.RectText(out, {x = fc1.x, w = fc1.w, y = fc1.bottom + y_spacing, h = fc1.h, h_text = fc1.h_text, color = xu_color}, {"Edge Masking", "to zero or minus infinity"})
  local relu = Drawing.RectText(out, {x = em.x, w = em.w, y = em.bottom + y_spacing, h = em.h, h_text = em.h_text, color = xu_color}, {"ReLU", "(Optional)"})
  local ethr = Drawing.RectText(out, {x = relu.x, w = relu.w, y = relu.bottom + y_spacing, h = relu.h, h_text = relu.h_text, color = xu_color}, {"Exponent", "Thresholding"})
  Drawing.MultiLine(out, {dst.x_middle, dst.bottom + 1, "v", fc1.y - 2})
  Drawing.MultiLine(out, {fc1.x_middle, fc1.bottom + 1, "v", em.y - 2})
  Drawing.MultiLine(out, {em.x_middle, em.bottom + 1, "v", relu.y - 2})
  Drawing.MultiLine(out, {relu.x_middle, relu.bottom + 1, "v", ethr.y - 2})

  local mux_pad = 15
  local src_mux = Drawing.Mux(out, {x = ethr.x_middle - mux_pad, y = ethr.bottom + y_spacing, right = l1_src.x_middle + mux_pad, h = 10}, "v")
  for _, datums in ipairs{ethr, zero_src, l1_src} do
    Drawing.MultiLine(out, {datums.x_middle, datums.bottom + 1, "v", src_mux.y - 2})
  end

  local ds = Drawing.RectText(out, {x_middle = src_mux.x_middle, w = 210, y = src_mux.bottom + y_spacing, h = 70, h_text = 70 + 6, rhombus = true, color = fe_color}, {"Downsample", "Pattern?"})
  Drawing.MultiLine(out, {ds.x_middle, src_mux.bottom + 1, "v", ds.y - 2})
  local ds_discard = Drawing.RectText(out, {x = ds.right + 70, y_middle = ds.y_middle, w = zero_src.w, h = zero_src.h, color = data_color}, {"Output to", [[<tspan font-family="monospace">/dev/null</tspan>]]})
  Drawing.MultiLine(out, {ds.right + 2, ds.y_middle, ">", ds_discard.x - 2})
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="auto">Discard</text>]],
    ds.right + 5, ds.y_middle - 4)

  local comp = Drawing.RectText(out, {x_middle = ds.x_middle, w = ds.w, y = ds.bottom + y_spacing, h = 70, h_text = 70, rhombus = true, color = fe_color}, {"Performing", "Compression?"})
  Drawing.MultiLine(out, {ds.x_middle, ds.bottom + 1, "v", comp.y - 2})
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">Keep</text>]],
    ds.x_middle + 6, (ds.bottom + comp.y) * 0.5 + 1)
  out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="auto">Yes</text>]],
    comp.x - 5, comp.y_middle - 4)

  local bfp_choice = Drawing.RectText(out, {x = comp.x_middle + 70, w = comp.w, y = comp.bottom, h = 70, h_text = 70, rhombus = true, color = fe_color}, {"Output is", "BFP format?"})
  local bfp_buf = Drawing.RectText(out, {x_middle = bfp_choice.x_middle, w = 170, h = 32, y = bfp_choice.bottom + y_spacing, color = data_color}, {"Buffer (16 datums)"})
  local fc2 = Drawing.RectText(out, {x = bfp_buf.x, w = bfp_buf.w, y = bfp_buf.bottom + y_spacing, h = xu_h, h_text = xu_h + 4, color = xu_color}, {"Late Format", "Conversion"})
  local max_exp = Drawing.RectText(out, {right = fc2.x - y_spacing, w = fc2.w, y = fc2.y, h = fc2.h, h_text = fc2.h_text, color = xu_color}, {"Find Maximum", "of 16 Exponents"})
  local dbuf = Drawing.RectText(out, {x_middle = fc2.x_middle, w = bfp_buf.w, h = bfp_buf.h, y = fc2.bottom + y_spacing, color = data_color}, {"Data Buffer (128b)"})
  local ebuf = Drawing.RectText(out, {x = max_exp.x, w = max_exp.w, h = bfp_buf.h, y = max_exp.bottom + y_spacing, color = data_color}, {"Exponent Buffer (128b)"})
  Drawing.MultiLine(out, {comp.right + 2, comp.y_middle, ">", bfp_choice.x_middle, "v", bfp_choice.y - 2})
  Drawing.MultiLine(out, {bfp_choice.x_middle, bfp_choice.bottom + 1, "v", bfp_buf.y - 2})
  Drawing.MultiLine(out, {bfp_buf.x_middle, bfp_buf.bottom + 1, "v", fc2.y - 2})
  Drawing.MultiLine(out, {bfp_choice.right + 2, bfp_choice.y_middle, ">", bfp_choice.right + y_spacing, "v", fc2.y_middle, "<", fc2.right + 2})
  Drawing.MultiLine(out, {bfp_buf.x - 1, bfp_buf.y_middle, "<", max_exp.x_middle, "v", max_exp.y - 2})
  Drawing.MultiLine(out, {max_exp.right + 1, max_exp.y_middle, ">", fc2.x - 2})
  Drawing.MultiLine(out, {max_exp.x_middle, max_exp.bottom + 1, "v", ebuf.y - 2})
  Drawing.MultiLine(out, {fc2.x_middle, fc2.bottom + 1, "v", dbuf.y - 2})
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">Yes</text>]],
    bfp_choice.x_middle + 6, (bfp_choice.bottom + bfp_buf.y) * 0.5 + 1)

  local zero_choice = Drawing.RectText(out, {right = comp.x_middle - (bfp_choice.x - comp.x_middle), w = bfp_choice.w, y = bfp_choice.y, h = bfp_choice.h, h_text = ds.h_text, rhombus = true, color = fe_color}, {"Datum is", "Zero?"})
  Drawing.MultiLine(out, {comp.x - 2, comp.y_middle, "<", zero_choice.x_middle, "v", zero_choice.y - 2})
  Drawing.MultiLine(out, {zero_choice.right + 2, zero_choice.y_middle, ">", bfp_choice.x - 2})
  for _, box in ipairs{comp, zero_choice, bfp_choice} do
    out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="auto">No</text>]],
      box.right + 5, box.y_middle - 4)
  end
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">Regardless</text>]],
    zero_choice.x_middle + 6, zero_choice.bottom + 11)

  local cbuf = Drawing.RectText(out, {right = ebuf.x - y_spacing, w = ebuf.w - 20, h = ebuf.h, y = ebuf.y, color = data_color}, {"RLE Buffer (128b)"})
  local rbuf = Drawing.RectText(out, {right = cbuf.x - y_spacing, w = cbuf.w, h = cbuf.h, y = cbuf.y, color = data_color}, {"RSI Buffer (128b)"})
  local metadata = Drawing.RectText(out, {x = rbuf.x, right = cbuf.right, bottom = cbuf.y - y_spacing, h = xu_h, h_text = xu_h + 4, color = xu_color}, {"Compression Metadata Generator:", "Row Flags, Row Start Indices, RLE of Zeroes"})
  local thdr = Drawing.RectText(out, {x = rbuf.x, w = rbuf.w, h = rbuf.h, bottom = metadata.y - y_spacing, color = data_color}, {"Row Flags (32b)"})
  Drawing.MultiLine(out, {zero_choice.x_middle, zero_choice.bottom + 1, "v", metadata.y - 2})
  for _, box in ipairs{cbuf, rbuf} do
    Drawing.MultiLine(out, {box.x_middle, metadata.bottom + 1, "v", box.y - 2})
  end
  Drawing.MultiLine(out, {thdr.x_middle, metadata.y - 1, "^", thdr.bottom + 2})

  local exp_stats = Drawing.RectText(out, {x = thdr.x, w = thdr.w, h = dst.h, y_middle = (relu.bottom + ethr.y) * 0.5, color = data_color}, {"Exponent", "Histogram"})
  Drawing.MultiLine(out, {relu.x_middle, exp_stats.y_middle, "<", exp_stats.right + 2})

  local acc = Drawing.RectText(out, {x_middle = dbuf.x_middle, w = comp.w, y = dbuf.bottom + y_spacing, h = 70, h_text = 70, rhombus = true, color = fe_color}, {"Performing", "Accumulation?"})
  local adder = Drawing.RectText(out, {x = acc.right + 35, w = 70, y_middle = acc.y_middle, h = fc2.h, color = xu_color}, {"Adder"})
  local wrreg = Drawing.RectText(out, {x = dbuf.right + y_spacing, right = adder.right, y = dbuf.y, bottom = adder.y - y_spacing, color = xu_color}, {"Register", "Write"})
  Drawing.MultiLine(out, {dbuf.x_middle, dbuf.bottom + 1, "v", acc.y - 2})
  Drawing.MultiLine(out, {acc.right + 2, acc.y_middle, ">", adder.x - 2})
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="auto">Yes</text>]],
    acc.right + 5, acc.y_middle - 4)

  local l1 = Drawing.RectText(out, {x = rbuf.x, right = adder.right, h = dst.h, y = acc.bottom + y_spacing, color = data_color}, {"Output to L1"})
  for _, box in ipairs{rbuf, cbuf, ebuf, acc} do
    Drawing.MultiLine(out, {box.x_middle, box.bottom + 1, "v", l1.y - 2})
  end
  Drawing.MultiLine(out, {adder.x_middle, adder.bottom + 2, "v", l1.y - 2, head = "both"})
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">No</text>]],
    acc.x_middle + 6, (acc.bottom + l1.y) * 0.5 + 1)

  local daddr_mux = Drawing.Mux(out, {x = acc.x_middle - mux_pad, right = adder.x_middle + mux_pad, y = l1.bottom + y_spacing, h = 10}, "v")
  local oag = Drawing.RectText(out, {x = l1.x, y = daddr_mux.bottom + y_spacing, w = l1.w, h = xu_h, color = xu_color}, "Output Address Generator (x4)")
  for i, box in ipairs{rbuf, cbuf, ebuf, acc, adder} do
    Drawing.MultiLine(out, {box.x_middle, (i >= 4 and daddr_mux or oag).y - 1, "^", l1.bottom + 2})
  end
  Drawing.MultiLine(out, {daddr_mux.x_middle, oag.y - 1, "^", daddr_mux.bottom + 2})

  out:putf"</svg>\n"
  return tostring(out)
end

assert(io.open(own_dir .."../Out/PackerPipeline.svg", "w")):write(PackerPipeline{})
