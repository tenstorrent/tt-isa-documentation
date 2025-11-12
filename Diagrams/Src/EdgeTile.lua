#!/usr/bin/env luajit
-- SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
--
-- SPDX-License-Identifier: Apache-2.0

local buffer = require"string.buffer"
local data_color = "#f4d7e3"
local xu_color = "#d4aa00"

local own_dir = debug.getinfo(1, "S").source:match"@?(.*/)" or ""
package.path = own_dir .."?.lua;".. package.path
local Drawing = require"Drawing"

local tile_colors = {
  P = "#ffd3e2",
  A = "#f2fad3",
  C = "#d2fad2",
  D = "#d6fff8",
}
local cdc_color0 = "#A0A0A0"
local cdc_color = cdc_color0 ..'" stroke-dasharray="4 2'

local function NIUs(out, x, y, num, niu_rtr_arrow_dir, tile_label)
  local niu_layer = buffer.new()
  x = x or 600
  y = y or 120
  num = num or 2

  local niu_y_spacing = 210
  local niu_w = 100
  local niu_h = 40
  local router_spacing = 30
  local hop_length = 17

  local noc_colors = {[0] ="#5c009e", "#06829e"}

  local result = {}
  local tiles = {}
  local n1_dx = niu_h - 26
  local n1_dy = niu_h + 34
  local y0 = y
  local cdc_path = {x + n1_dx + niu_w - 20, 0, color = cdc_color, stroke_width = 3, head = false}
  local function append_cdc_path(a, b)
    local n = #cdc_path
    cdc_path[n + 1] = a
    cdc_path[n + 2] = b
  end

  for i = 0, num-1 do
    do
      local x, y = x, y
      if i % 2 == 1 then
        x = x + n1_dx
        y = y + n1_dy
        append_cdc_path(">", cdc_path[1])
      else
        append_cdc_path("v", y - router_spacing - niu_h * 0.5 - hop_length - 7)
        append_cdc_path("<", x - router_spacing - niu_h * 0.5 - hop_length - 7)
        if tile_label == "A" then
          append_cdc_path("v", y - router_spacing + 18)
          append_cdc_path(">", x - router_spacing - niu_h * 0.5 + 4)
        end
        append_cdc_path("v", y - router_spacing + niu_h * 0.5 + hop_length + 7)

        local x0 = x - 10
        local y0 = y - 10
        local x1 = x + n1_dx + niu_w + 10
        local y1 = y + n1_dy + niu_h + 10
        local color = tile_colors[tile_label:sub(1, 1)]
        out:putf([[<rect x="%g" y="%g" width="%g" height="%g" stroke="black" fill="%s" stroke-width="1" rx="5" ry="5"/>]], x0, y0, x1 - x0, y1 - y0, color)
        tiles[#tiles + 1] = {y = y0, bottom = y1}
      end
      local noc_color = noc_colors[i % 2]
      local noc_inactive_color = noc_color .. '" fill-opacity="40%'
      niu_layer:putf([[<rect x="%g" y="%g" width="%g" height="%g" stroke="transparent" fill="%s" rx="5" ry="5"/>]], x, y, niu_w, niu_h, noc_color)
      niu_layer:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="middle" fill="white">NoC #%u NIU</text>]], x + niu_w * 0.5 + 1, y + niu_h * 0.5 + 2, i % 2)

      local r1 = niu_h * 0.5 + 3
      local r2 = r1 / math.sqrt(2)
      local router_x, router_y, hop_dir
      local niu_hop_pad = 6.5
      if i % 2 == 0 then
        router_x = x - router_spacing
        router_y = y - router_spacing
        hop_dir = "->"
        for j = -0.5, 0.5 do
          hop_dir = j > 0 and "->" or "<-"
          Drawing.ThickArrow(out, x + j * niu_hop_pad, y - j * niu_hop_pad, hop_dir, router_x + r2 + j * niu_hop_pad, router_y + r2 - j * niu_hop_pad, hop_dir == niu_rtr_arrow_dir and noc_color or noc_inactive_color, 1)
        end
        hop_dir = "->"
      else
        router_x = x + niu_w + router_spacing
        router_y = y + niu_h + router_spacing
        for j = -0.5, 0.5 do
          hop_dir = j > 0 and "->" or "<-"
          Drawing.ThickArrow(out, x + niu_w + j * niu_hop_pad, y + niu_h - j * niu_hop_pad, hop_dir, router_x - r2 + j * niu_hop_pad, router_y - r2 - j * niu_hop_pad, hop_dir == niu_rtr_arrow_dir and noc_color or noc_inactive_color, 1)
        end
        hop_dir = "<-"
      end
      out:putf([[<circle cx="%g" cy="%g" r="%u" stroke="transparent" fill="%s"/>]], router_x, router_y, niu_h * 0.5, noc_color)
      out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="middle" fill="white">R</text>]], router_x, router_y + 1)

      Drawing.ThickArrow(out, router_x - r1 - hop_length, router_y, hop_dir, router_x - r1, router_y, hop_dir ~= niu_rtr_arrow_dir and noc_color or noc_inactive_color, 1)
      Drawing.ThickArrow(out, router_x + r1, router_y, hop_dir, router_x + r1 + hop_length, router_y, hop_dir == niu_rtr_arrow_dir and noc_color or noc_inactive_color, 1)
      Drawing.ThickArrow(out, router_x, router_y - r1 - hop_length, hop_dir, router_x, router_y - r1, hop_dir ~= niu_rtr_arrow_dir and noc_color or noc_inactive_color, 1)
      Drawing.ThickArrow(out, router_x, router_y + r1, hop_dir, router_x, router_y + r1 + hop_length, hop_dir == niu_rtr_arrow_dir and noc_color or noc_inactive_color, 1)

      result[i+1] = {x = x, y = y, x_middle = x + niu_h * 0.5, y_middle = y + niu_h * 0.5, bottom = y + niu_h, right = x + niu_w}
    end
    if i % 2 == 1 then
      y = y + niu_y_spacing
    end
  end
  result.last = result[num]
  append_cdc_path("v", 800)
  Drawing.MultiLine(out, cdc_path)
  out:put(niu_layer)
  return result, tiles, cdc_path[1]
end

local function CDC(out, left, x, y, right)
  if left then
    out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="middle" fill="%s">%s</text>]],
      x - 8, y, cdc_color0, left)
  end
  if right then
    out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle" fill="%s">%s</text>]],
      x + 8, y, cdc_color0, right)
  end
end

local function PCIe(direction, arch)
  local out = buffer.new()
  local nul = buffer.new()
  local dims = {w = 790, h = 535}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local nius, tiles, cdc_x = NIUs(out, nil, 85, 2, direction == "H2D" and "->" or "<-", "P")

  local mux_pad = 15
  local mux = Drawing.Mux((arch == "BH" and direction == "H2D") and nul or out, {right = nius[1].x - 100, w = 10, y = nius[1].y_middle - mux_pad, bottom = nius.last.y_middle + mux_pad}, "<")
  for _, niu in ipairs(nius) do
    if direction == "H2D" then
      Drawing.ThickArrow(out, mux.right + 0.5, niu.y_middle, "->", niu.x - 1, niu.y_middle, "black", 1)
    else
      Drawing.ThickArrow(out, mux.right + 1, niu.y_middle, "<-", niu.x - 0.5, niu.y_middle, "black", 1)
    end
  end

  local out0 = out
  -- H2D only
  local out = direction == "H2D" and out0 or nul
  local mux3 = Drawing.Mux(out, {x = nius[2].x, w = mux_pad * 3, y = nius.last.bottom + 30, h = 10}, "v")

  local x = mux3.x + mux_pad
  local y = mux3.y - 1
  local niu_lines = {
    {x, y, "^", nius[2].bottom + 2},
    {x, y, "^", nius[2].bottom + 5, " ^", nius[2].y - 5, "^", nius[1].bottom + 2},
  }
  for i, data in ipairs(niu_lines) do
    x = math.floor(mux3.right - mux_pad - (mux3.w - mux_pad * 2) * ((i - 1) / 1) + 0.5)
    data[1] = x
    Drawing.MultiLineWithGaps(out, data)
  end

  local tlbs = Drawing.RectText(out, {right = mux.x - 20, y_middle = mux.y_middle, w = 100, h = 55, color = xu_color}, {"Configurable", "TLBs" .. (arch == "BH" and ", H→N" or "")})
  Drawing.ThickArrow(out, tlbs.right + 0.5, tlbs.y_middle, "->", mux.x - 1, tlbs.y_middle, "black", 1)

  local apb0 = Drawing.RectText(out, {x = tlbs.x, y = tlbs.bottom + 20, w = 55, h = 55, color = xu_color}, {"AXI /", "/ APB"})
  local apb1 = Drawing.RectText(out, {x = tlbs.x, y = apb0.bottom + 20, w = 55, h = 55, color = xu_color}, {"AXI /", "/ APB"})
  Drawing.MultiLine(out, {apb0.right + 1, apb0.y_middle, ">", (apb0.right + tlbs.right) * 0.5, "^", tlbs.bottom + 2})
  Drawing.MultiLine(out, {apb1.right + 1, apb1.y_middle, ">", mux3.x_middle, "^", mux3.bottom + 2})

  local to_arc_y0 = apb1.bottom + 20 + tlbs.h * 0.5
  local to_arc_y1 = 510
  local to_arc_x = 400

  local mux2 = Drawing.Mux(out, {right = tlbs.x - 20, w = 10, y = tlbs.y_middle - mux_pad, bottom = to_arc_y0 + mux_pad}, "<")
  for _, box in ipairs{tlbs, apb0, apb1} do
    Drawing.ThickArrow(out, mux2.right + 0.5, box.y_middle, "->", box.x - 1, box.y_middle, "black", 1)
  end
  Drawing.MultiLine(out, {mux2.right + 0.5, to_arc_y0, ">", to_arc_x, "v", to_arc_y1, thick = 1})
  -- End H2D only
  out = out0
  local above_cdc = buffer.new()
  local pcie_ctrl = Drawing.RectText(above_cdc, {right = mux2.x - 20, y = tlbs.y, w = 180, h = 350, h_text = 320, color = xu_color}, {"PCI Express", "Controller", "and", "PHY"})
  Drawing.MultiLine(out, {
    0, pcie_ctrl.y - 50,
    ">", pcie_ctrl.x_middle,
    "v", pcie_ctrl.bottom + 50,
    "<", 0,
    color = cdc_color, stroke_width = 3, head = false,
  })
  if arch == "BH" and direction == "H2D" then
    CDC(out, "AXI Clock", pcie_ctrl.x_middle, pcie_ctrl.y - 70, nil)
    CDC(out, "PCI Express Clock", pcie_ctrl.x_middle, pcie_ctrl.y - 25, nil)
  else
    CDC(out, "PCI Express Clock", pcie_ctrl.x_middle, pcie_ctrl.y - 25, "AXI Clock")
  end
  if direction == "H2D" then
    CDC(out, "PCI Express Clock", pcie_ctrl.x_middle, pcie_ctrl.bottom + 25, "AXI Clock")
  end
  CDC(out, "AXI Clock", cdc_x, 350, "AI Clock")
  out:put(above_cdc)

  local iatu = Drawing.RectText(out, {x = pcie_ctrl.x + 20, y_middle = (tlbs.bottom + apb0.y) * 0.5, w = 110, h = 40, color = 'black" fill-opacity="25%'}, {"Inbound iATU"})
  local oatu = Drawing.RectText(out, {right = pcie_ctrl.right - 20, bottom = pcie_ctrl.bottom - 20, w = iatu.w, h = iatu.h, color = 'black" fill-opacity="25%'}, {"Outbound iATU"})
  local dma = Drawing.RectText(out, {x = pcie_ctrl.x + 20, bottom = oatu.y - 20, w = pcie_ctrl.w - 40, h = 40, color = 'black" fill-opacity="25%'}, {"DMA Engines"})

  local req_color = "#6889E9"
  local resp_color = req_color ..'" fill-opacity="40%'
  if direction == "H2D" then
    Drawing.ThickArrow(out, pcie_ctrl.x - 12, iatu.y_middle, "->", iatu.x - 1, iatu.y_middle, req_color, 1)
    out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="middle">From Host MMU</text>]],
      pcie_ctrl.x - 17, iatu.y_middle + 2)
    local x = pcie_ctrl.x - 32
    Drawing.ThickArrow(out, x, oatu.y_middle, "<-", pcie_ctrl.x - 0.5, oatu.y_middle, resp_color, 1)
    out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="middle">To Host</text>]],
      x - 5, oatu.y_middle + 2)
    Drawing.ThickArrow(out, iatu.right + 0.5, iatu.y_middle, "->", mux2.x - 1, iatu.y_middle, "black", 1)
    local x = math.floor((dma.right + iatu.right) * 0.5 + 0.5)
    Drawing.ThickArrow(out, x, dma.y - 0.5, "--", x, iatu.y_middle, "black", 1)

    if arch == "BH" then
      local msi = Drawing.RectText(out, {right = tlbs.right, x = pcie_ctrl.right - 70, bottom = tlbs.y - 20, h = 40, color = xu_color}, {"Interrupt Receiver (RP only)"})
      Drawing.MultiLine(out, {(msi.x + pcie_ctrl.right) * 0.5, pcie_ctrl.y - 1, "^", msi.bottom + 2})
      Drawing.ThickArrow(out, msi.right + 0.5, msi.y_middle, "->", mux.x - 1, msi.y_middle, "black", 1)
      Drawing.Mux(out, {x = mux.x, w = mux.w, y = msi.y_middle - mux_pad - mux.w * 0.5, bottom = mux.bottom}, "<")
    end
  else
    local x = pcie_ctrl.x - 32
    Drawing.ThickArrow(out, x, iatu.y_middle, "->", pcie_ctrl.x - 1, iatu.y_middle, resp_color, 1)
    out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="middle">From Host</text>]],
      x - 5, iatu.y_middle + 2)

    Drawing.ThickArrow(out, pcie_ctrl.x - 12, oatu.y_middle, "<-", oatu.x - 0.5, oatu.y_middle, req_color, 1)
    out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="middle">To Host IOMMU</text>]],
      pcie_ctrl.x - 17, oatu.y_middle + 2)
    local x = math.floor((dma.x + oatu.x) * 0.5 + 0.5)
    Drawing.ThickArrow(out, x, dma.bottom + 0.5, "--", x, oatu.y_middle, req_color, 1)
  end

  if direction == "D2H" then
    -- D2H only
    apb0 = Drawing.RectText(out, {x = pcie_ctrl.right + 20, y_middle = dma.y_middle, w = 55, h = 55, color = xu_color}, {"APB /", "/ AXI"})
    Drawing.MultiLine(out, {apb0.x - 1, apb0.y_middle, "<", pcie_ctrl.right + 2})

    mux2 = Drawing.Mux(out, {x = apb0.right + 20, w = 10, y = mux.y_middle - mux_pad, bottom = oatu.y_middle + mux_pad + 5}, "<")

    if arch ~= "BH" then
      Drawing.ThickArrow(out, mux2.right + 1, mux.y_middle, "<-", mux.x - 0.5, mux.y_middle, "black", 1)
    end
    Drawing.ThickArrow(out, apb0.right + 1, apb0.y_middle, "<-", mux2.x - 0.5, apb0.y_middle, "black", 1)
    Drawing.ThickArrow(out, oatu.right + 1, oatu.y_middle, "<-", mux2.x - 0.5, oatu.y_middle, "black", 1)

    to_arc_x = 280
    if arch == "BH" then
      local arc_tlbs = Drawing.RectText(out, {x = mux2.right + 20, bottom = mux2.bottom, w = 100, h = 55, color = xu_color}, {"Configurable", "TLBs, H←A"})
      local noc_tlbs = Drawing.RectText(out, {x = mux2.right + 20, bottom = arc_tlbs.y - 20, w = 100, h = 55, color = xu_color}, {"Configurable", "TLBs, H←N"})
      for _, tlb in ipairs{arc_tlbs, noc_tlbs} do
        Drawing.ThickArrow(out, mux2.right + 1, tlb.y_middle, "<-", tlb.x - 0.5, tlb.y_middle, "black", 1)
      end

      apb1 = Drawing.RectText(out, {x = pcie_ctrl.right + 20, y = mux2.y + mux2.w * 0.5, w = 55, h = 55, color = xu_color}, {"APB /", "/ AXI"})
      Drawing.ThickArrow(out, apb1.right + 1, apb1.y_middle, "<-", mux2.x - 0.5, apb1.y_middle, "black", 1)
      local to_serdes_y = 30
      Drawing.MultiLine(out, {apb1.x_middle, apb1.y - 1, "^", to_serdes_y})
      out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="auto">To Serdes Configuration</text>]],
        apb1.x_middle, to_serdes_y - 7)

      Drawing.MultiLineWithGaps(out, {apb0.x_middle, apb0.bottom + 1, "v", oatu.y_middle - 5, " v", oatu.y_middle + 5, "v", pcie_ctrl.bottom - 5, ">", arc_tlbs.x_middle, "^", arc_tlbs.bottom + 2})
      Drawing.MultiLine(out, {to_arc_x, to_arc_y1, "^", pcie_ctrl.bottom + 20, ">", arc_tlbs.right + 20, "^", arc_tlbs.y_middle, "<", arc_tlbs.right + 1, thick = 1})
      Drawing.MultiLineWithGaps(out, {apb0.x_middle, apb0.y - 1, "^", noc_tlbs.y - ((pcie_ctrl.bottom - 5) - arc_tlbs.bottom), ">", mux2.x - 4, " >", mux2.right + 4, ">", noc_tlbs.x_middle, "v", noc_tlbs.y - 2})

      Drawing.MultiLine(out, {mux.x, mux.y_middle, "<", mux.x - 20, "v", (mux.bottom + noc_tlbs.y) * 0.5, ">", noc_tlbs.right + 20, "v", noc_tlbs.y_middle, "<", noc_tlbs.right + 1, thick = 1})
    else
      Drawing.MultiLine(out, {to_arc_x, to_arc_y1, "^", pcie_ctrl.bottom + 20, ">", mux2.right + 20, "^", mux2.bottom - mux_pad * 3, "<", mux2.right + 1, thick = 1})
    end
  end
  if arch == "BH" then
    to_arc_x = to_arc_x + 35 + (direction == "D2H" and 10 or 0)
  end
  out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="hanging">%s ARC%s</text>]],
    to_arc_x, to_arc_y1 + 5, direction == "H2D" and "To" or "From", arch == "BH" and " (PCIe 1 only)" or "")

  out:putf"</svg>\n"
  return tostring(out)
end

local function ARC(direction)
  local out = buffer.new()
  local nul = buffer.new()
  local above_cdc = buffer.new()
  local dims = {w = 790, h = 450}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local nius, tiles, cdc_x = NIUs(out, nil, nil, 2, direction == "H2D" and "->" or "<-", "A")

  local mux_pad = 15
  local mux
  local noc_tlbs = {}
  local noc_cfg_mux
  do
    local out = direction == "H2D" and out or nul
    for i, niu in ipairs(nius) do
      noc_tlbs[i] = Drawing.RectText(out, {right = nius[1].x - 50, y_middle = niu.y_middle, w = 100, h = 55, color = xu_color}, {"Configurable", "TLBs"})
      Drawing.ThickArrow(out, noc_tlbs[i].right + 0.5, noc_tlbs[i].y_middle, "->", niu.x - 1, noc_tlbs[i].y_middle, "black", 1)
    end
    mux = Drawing.Mux(out, {right = noc_tlbs[1].x - 20, w = 10, y = noc_tlbs[1].y_middle - mux_pad, bottom = noc_tlbs[2].y_middle + mux_pad}, "<")
    noc_cfg_mux = Drawing.Mux(out, {x = noc_tlbs[1].right - mux_pad * 3, right = nius[2].x + mux_pad * 3, y = nius.last.bottom + 30, h = 10}, "v")
  end
  local xbar = Drawing.RectText(out, {right = mux.x - 20, w = 120, h = 55 * 2 + 20, y = nius[1].y, color = xu_color}, {"ARC", "XBAR"})
  if direction == "D2H" then
    mux = Drawing.Mux(out, {right = nius[1].x - 100, w = 10, y = nius[1].y_middle - mux_pad * 3, bottom = nius.last.y_middle + mux_pad}, "<")
    noc_cfg_mux = Drawing.Mux(out, {x = nius[2].x, w = mux_pad * 3, y = nius.last.bottom + 30, h = 10}, "v")
    noc_tlbs = nil
  end
  for _, niu in ipairs(noc_tlbs or nius) do
    if direction == "H2D" then
      Drawing.ThickArrow(out, mux.right + 0.5, niu.y_middle, "->", niu.x - 1, niu.y_middle, "black", 1)
    else
      Drawing.ThickArrow(out, mux.right + 1, niu.y_middle, "<-", niu.x - 0.5, niu.y_middle, "black", 1)
    end
  end
  do
    local x
    local y = noc_cfg_mux.y - 1
    local niu_lines = {
      {x, y, "^", nius[2].bottom + 2},
      {x, y, "^", nius[2].bottom + 5, " ^", nius[2].y - 5, "^", nius[1].bottom + 2},
    }
    for i, data in ipairs(niu_lines) do
      x = math.floor(noc_cfg_mux.right - mux_pad * i)
      data[1] = x
      Drawing.MultiLineWithGaps(out, data)
    end
    if noc_tlbs then
      niu_lines = {
        {x, y, "^", noc_tlbs[2].bottom + 5, " ^", noc_tlbs[2].y - 5, "^", noc_tlbs[1].bottom + 2},
        {x, y, "^", noc_tlbs[2].bottom + 2},
      }
      for i, data in ipairs(niu_lines) do
        x = math.floor(noc_cfg_mux.x + mux_pad * i)
        data[1] = x
        Drawing.MultiLineWithGaps(out, data)
      end
    end
  end

  local gtlb
  do
    local niu_y = (nius[1].y_middle + nius[2].y_middle) * 0.5
    if direction == "H2D" then
      Drawing.ThickArrow(above_cdc, xbar.right + 0.5, niu_y, "->", mux.x - 1, niu_y, "black", 1)
      gtlb = Drawing.RectText(out, {right = xbar.x_middle - 10, bottom = xbar.y - 20, w = 100, h = 55, color = xu_color}, {"Configurable", "TLBs"})
      local ftlb = Drawing.RectText(out, {x = xbar.x_middle + 10, bottom = xbar.y - 20, w = 100, h = 55, color = xu_color}, {"Fixed", "TLBs"})
      local pcie_y = gtlb.y - 20
      Drawing.ThickArrow(above_cdc, gtlb.x_middle, gtlb.y - 0.5, "->", gtlb.x_middle, pcie_y, "black", 1)
      local pcie_x = (ftlb.x + xbar.right) * 0.5
      Drawing.ThickArrow(above_cdc, ftlb.x_middle, ftlb.y - 1, "<-", ftlb.x_middle, pcie_y, "black", 1)
      Drawing.ThickArrow(out, pcie_x, xbar.y - 1, "<-", pcie_x, ftlb.bottom + 0.5, "black", 1)
      pcie_y = pcie_y - 5
      out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="auto">To PCI Express</text>]], gtlb.right, pcie_y)
      out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="auto">From PCI Express</text>]], ftlb.x, pcie_y)
    else
      Drawing.ThickArrow(above_cdc, xbar.right + 1, niu_y, "<-", mux.x - 0.5, niu_y, "black", 1)
      gtlb = Drawing.RectText(out, {x_middle = xbar.x_middle, bottom = xbar.y - 20, w = 100, h = 55, color = xu_color}, {"Configurable", "TLBs"})
      local transfer_x = mux.right + 17
      Drawing.MultiLine(above_cdc, {gtlb.right + 0.5, gtlb.y_middle, ">", transfer_x, "v", mux.y + mux_pad, "<", mux.right + 1, thick = 1})
      local to_dram_y = mux.bottom + 80
      Drawing.MultiLine(out, {mux.x - 0.5, mux.bottom - mux_pad * 2, "<", mux.x - 17, "v", mux.bottom + 17, ">", transfer_x, "v", to_dram_y, thick = 1})
      out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="hanging">To DRAM D0 tiles</text>]], transfer_x, to_dram_y + 5)
    end
    local gtlb_x = (math.max(gtlb.x, xbar.x) + math.min(gtlb.right, xbar.right)) * 0.5
    Drawing.ThickArrow(out, gtlb_x, xbar.y + 0.5, "->", gtlb_x, gtlb.bottom + 1, "black", 1)
  end

  local apb = Drawing.RectText(out, {right = xbar.right, y = xbar.bottom + 20, w = 55, h = 55, color = xu_color}, {"AXI /", "/ APB"})
  Drawing.ThickArrow(out, apb.x_middle, xbar.bottom + 0.5, "->", apb.x_middle, apb.y - 1, "black", 1)

  local apb_mux = Drawing.Mux(out, {x = apb.x - 10, y = apb.bottom + 20, right = apb.right + 10, h = 10}, "^")
  local reset_unit = Drawing.RectText(out, {right = apb.x - 20, w = 100, h = apb.h, y = apb.y, color = xu_color}, {"Reset", "Unit"})
  Drawing.MultiLine(out, {apb.x_middle, apb.bottom + 1, "v", apb_mux.y - 2})
  Drawing.MultiLine(above_cdc, {apb_mux.right - mux_pad, apb_mux.bottom + 1, "v", apb_mux.bottom + 10, ">", noc_cfg_mux.x_middle, "^", noc_cfg_mux.bottom + 2})
  Drawing.MultiLine(out, {apb_mux.x + mux_pad, apb_mux.bottom + 1, "v", apb_mux.bottom + 10, "<", reset_unit.right - reset_unit.w / 4, "^", reset_unit.bottom + 2})
  local apb_misc_y = apb_mux.bottom + 30
  Drawing.MultiLine(out, {apb_mux.x_middle, apb_mux.bottom + 1, "v", apb_misc_y})
  out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="hanging">SPI, I2C, eFuses, ...</text>]],
    apb_mux.x_middle, apb_misc_y + 5)

  local reset_scratch = Drawing.RectText(out, {right = xbar.x - 20, w = 60, h = 55, y = reset_unit.bottom + 20, color = data_color}, {"Scratch", "8x 32b"})
  Drawing.MultiLine(out, {(reset_unit.x + reset_scratch.right) * 0.5, reset_unit.bottom + 1, "v", reset_scratch.y - 2})

  local csm = Drawing.RectText(out, {right = xbar.x - 20, w = 100, h = (xbar.h - 20) * 0.5, y = xbar.y, color = data_color}, {"ARC CSM", "512 KiB"})
  Drawing.ThickArrow(out, csm.right + 1, csm.y_middle, "<-", xbar.x - 0.5, csm.y_middle, "black", 1)
  local arc = Drawing.RectText(out, {right = xbar.x - 20, w = 100, h = (xbar.h - 20) * 0.5, bottom = xbar.bottom, color = xu_color}, {"ARC CPU", "(4 cores)"})
  Drawing.ThickArrow(out, arc.right + 0.5, arc.y_middle, "->", xbar.x - 1, arc.y_middle, "black", 1)
  Drawing.ThickArrow(out, arc.x_middle, arc.y - 0.5, "->", arc.x_middle, csm.bottom + 1, "#6889E9", 1)

  Drawing.MultiLine(out, {(reset_unit.x + arc.right) * 0.5, reset_unit.y - 1, "^", arc.bottom + 2})
  Drawing.MultiLine(out, {reset_unit.x - 1, reset_unit.y + reset_unit.h / 3, "<", arc.x - 10, "^", gtlb.y_middle, ">", gtlb.x - 2})

  local ref_cnt = Drawing.RectText(out, {right = arc.x - 35, w = 80, h = apb.h, y = reset_unit.y, color = xu_color}, {"Cycle", "Counter"})
  Drawing.MultiLine(above_cdc, {reset_unit.x - 1, reset_unit.y + reset_unit.h * 2 / 3, "<", ref_cnt.right + 2})

  local cdc_x0 = 457
  local cdc_y0 = 34
  local cdc_y1 = apb_mux.bottom + 80
  Drawing.MultiLine(out, {
    cdc_x0, cdc_y0,
    "v", xbar.y - 13,
    "<", xbar.right + 10,
    "v", apb.bottom + 10,
    ">", cdc_x0 - 5,
    "v", cdc_y1,
    "<", 5.5,
    "^", cdc_y0,
    ">", cdc_x0,
    color = cdc_color, stroke_width = 3, head = false,
  })
  Drawing.MultiLine(out, {
    140, cdc_y0, "v", cdc_y1,
    color = cdc_color, stroke_width = 3, head = false,
  })
  CDC(out, "REF Clock", 140, cdc_y1 - 10, "ARC Clock")
  CDC(out, "ARC Clock", cdc_x0 - 5, cdc_y1 - 10, "AXI Clock")
  CDC(out, "AXI Clock", cdc_x, cdc_y1 - 10, "AI Clock")
  CDC(out, "AXI Clock", cdc_x, 37, "AI Clock")
  out:put(above_cdc)

  out:putf"</svg>\n"
  return tostring(out)
end

local function GDDR()
  local out = buffer.new()
  local dims = {w = 790, h = 730}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local nius, tiles, cdc_x = NIUs(out, nil, nil, 6, "<-", "D")

  local mux_pad = 15
  local mux = Drawing.Mux(out, {right = nius[1].x - 100, w = 10, y = nius[1].y_middle - mux_pad * 3, bottom = nius.last.y_middle + mux_pad}, "<")
  for _, niu in ipairs(nius) do
    Drawing.ThickArrow(out, mux.right + 1, niu.y_middle, "<-", niu.x - 2, niu.y_middle, "black", 1)
  end
  do
    local transfer_x = mux.right + 17
    Drawing.MultiLine(out, {transfer_x, 25, "v", mux.y + mux_pad, "<", mux.right + 1, thick = 1})
    out:putf([[<text x="%d" y="%d" text-anchor="middle" dominant-baseline="auto">From ARC (D0 tiles only)</text>]],
      transfer_x + 40, 20)
  end

  local above_cdc = buffer.new()
  local function Channel(idx, y)
    local ctrl = Drawing.RectText(above_cdc, {right = mux.x - 20, w = 150, h = 215, y = y, color = xu_color}, {"GDDR6", "Channel ".. idx, "", "Controller", "and", "PHY"})
    local mem = Drawing.RectText(out, {right = ctrl.x - 40, w = ctrl.h, h = ctrl.h, y = ctrl.y, color = data_color}, {"GDDR6", "1 GiB"})
    Drawing.ThickArrow(out, mem.right + 1, mem.y_middle, "<>", ctrl.x - 1, mem.y_middle, "#6889E9", 1)
    return ctrl, mem
  end
  local c0, m0 = Channel(0, mux.y + 15)
  local c1, m1 = Channel(1, c0.bottom + 20)
  for _, c in ipairs{c0, c1} do
    Drawing.ThickArrow(out, c.right + 1, c.y_middle, "<-", mux.x - 0.5, c.y_middle, "black", 1)
  end
  local cdc_x0 = c0.x + 25
  local cdc_y0 = c0.y - 50
  Drawing.MultiLine(out, {
    cdc_x0, cdc_y0,
    "v", c1.bottom + 50,
    "<", m1.x - 50,
    "^", cdc_y0,
    ">", cdc_x0,
    color = cdc_color, stroke_width = 3, head = false,
  })
  CDC(out, "GDDR Clock", cdc_x0, c0.y - 25, "AXI Clock")
  CDC(out, "AXI Clock", cdc_x, 37, "AI Clock")
  out:put(above_cdc)

  local apb = Drawing.RectText(out, {right = mux.x - 20, bottom = mux.bottom - (c0.y - mux.y), w = 55, h = 55, color = xu_color}, {"APB /", "/ AXI"})
  Drawing.ThickArrow(out, apb.right + 1, apb.y_middle, "<-", mux.x - 0.5, apb.y_middle, "black", 1)

  local mux2 = Drawing.Mux(out, {right = apb.x - 20, w = 10, y = apb.y - 10, bottom = apb.bottom + 10}, ">")
  Drawing.MultiLine(out, {apb.x - 1, apb.y_middle, "<", mux2.right + 2})
  Drawing.MultiLine(out, {mux2.x - 1, mux2.y + mux_pad, "<", mux2.x - 8, "^", c1.bottom + 2})
  Drawing.MultiLineWithGaps(out, {mux2.x - 1, mux2.y_middle, "<", mux2.x - 8 - 15, "^", c1.bottom + 4, " ^", c1.y - 4, "^", c0.bottom + 2})

  local mux3 = Drawing.Mux(out, {x = nius[2].x, right = nius[1].right, y = nius.last.bottom + 30, h = 10}, "v")
  Drawing.MultiLine(out, {mux2.x - 1, mux2.bottom - mux_pad, "<", mux2.x - 8, "v", mux3.bottom + 15, ">", mux3.x_middle, "^", mux3.bottom + 2})

  local x = mux3.x + mux_pad
  local y = mux3.y - 1
  local niu_lines = {
    {x, y, "^", nius[6].bottom + 2},
    {x, y, "^", nius[6].bottom + 5, " ^", nius[6].y - 5, "^", nius[5].bottom + 2},
    {x, y, "^", tiles[3].bottom + 5, " ^", tiles[2].bottom + 11, "^", nius[4].bottom + 2},
    {x, y, "^", tiles[3].bottom + 5, " ^", tiles[2].bottom + 11, "^", nius[4].bottom + 5, " ^", nius[4].y - 5, "^", nius[3].bottom + 2},
    {x, y, "^", tiles[3].bottom + 5, " ^", tiles[1].bottom + 11, "^", nius[2].bottom + 2},
    {x, y, "^", tiles[3].bottom + 5, " ^", tiles[1].bottom + 11, "^", nius[2].bottom + 5, " ^", nius[2].y - 5, "^", nius[1].bottom + 2},
  }
  for i, data in ipairs(niu_lines) do
    x = math.floor(mux3.right - mux_pad - (mux3.w - mux_pad * 2) * ((i - 1) / 5) + 0.5)
    data[1] = x
    Drawing.MultiLineWithGaps(out, data)
  end

  out:putf"</svg>\n"
  return tostring(out)
end

local function L2CPU(direction)
  local out = buffer.new()
  local nul = buffer.new()
  local dims = {w = 790, h = 715}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local tl_color = "#6889E9"

  local function Hart(hart_i)
    local y0 = 40 + 160 * hart_i
    local x280 = Drawing.RectText(out, {x = 5.5, y = y0, w = 60, h = 140, color = xu_color}, {"x280", "Hart ".. hart_i})
    local l1d = Drawing.RectText(out, {x = x280.right + 20, y = x280.y, w = 62, h = 50, color = data_color}, {"L1 D$", "32 KiB"})
    local l1i = Drawing.RectText(out, {x = l1d.x, y = l1d.bottom + 10, w = l1d.w, h = l1d.h, color = data_color}, {"L1 I$", "32 KiB"})
    local mmu = Drawing.RectText(out, {x = l1d.right + 20, y = x280.y, w = 58, h = x280.h, color = xu_color}, {"MMU", "and", "BEU"})
    local l2 = Drawing.RectText(out, {x = mmu.right + 20, y_middle = (l1d.y_middle + l1i.y_middle) * 0.5, w = 70, h = 70, color = data_color}, {"L2 $", "128 KiB"})

    for _, l1 in ipairs{l1d, l1i} do
      Drawing.ThickArrow(out, x280.right + 0.5, l1.y_middle, "--", l1.x - 0.5, l1.y_middle, tl_color, 1)
      Drawing.ThickArrow(out, l1.right + 0.5, l1.y_middle, "--", mmu.x - 0.5, l1.y_middle, tl_color, 1)
    end

    return {x280 = x280, mmu = mmu, l2 = l2}
  end

  local nius, tiles, cdc_x = NIUs(out, nil, 85, 2, direction == "H2D" and "->" or "<-", "C")
  local mux_pad = 15
  local niu_mux = Drawing.Mux(out, {right = nius[1].x - 40, w = 10, y = nius[1].y_middle - mux_pad, bottom = nius.last.y_middle + mux_pad}, "<")
  for _, niu in ipairs(nius) do
    if direction == "H2D" then
      Drawing.ThickArrow(out, niu_mux.right + 0.5, niu.y_middle, "->", niu.x - 1, niu.y_middle, "black", 1)
    else
      Drawing.ThickArrow(out, niu_mux.right + 1, niu.y_middle, "<-", niu.x - 0.5, niu.y_middle, "black", 1)
    end
  end
  local mux3 = Drawing.Mux(out, {x = nius[2].x, w = mux_pad * 3, y = nius.last.bottom + 30, h = 10}, "v")
  do
    local x = mux3.x + mux_pad
    local y = mux3.y - 1
    local niu_lines = {
      {x, y, "^", nius[2].bottom + 2},
      {x, y, "^", nius[2].bottom + 3, " ^", nius[2].y - 3, "^", nius[1].bottom + 2},
    }
    for i, data in ipairs(niu_lines) do
      x = math.floor(mux3.right - mux_pad - (mux3.w - mux_pad * 2) * ((i - 1) / 1) + 0.5)
      data[1] = x
      Drawing.MultiLineWithGaps(out, data)
    end
  end

  local harts = {}
  for i = 0, 3 do
    harts[i] = Hart(i)
  end
  local main_mux = Drawing.Mux(out, {x = harts[1].l2.right + 20, w = 10, y = 36, bottom = harts[#harts].x280.bottom}, ">")
  for i = 0, 3 do
    local x280 = harts[i].x280
    local mmu = harts[i].mmu
    local l2 = harts[i].l2
    Drawing.ThickArrow(out, mmu.right + 0.5, l2.y_middle, "--", l2.x - 0.5, l2.y_middle, tl_color, 1)
    Drawing.ThickArrow(out, l2.right + 0.5, l2.y_middle, "->", main_mux.x - 1, l2.y_middle, tl_color, 1)
    local uc_y = mmu.bottom - 10
    Drawing.ThickArrow(out, x280.right + 0.5, uc_y, "--", mmu.x - 0.5, uc_y, tl_color, 1)
    Drawing.ThickArrow(out, mmu.right + 0.5, uc_y, "->", main_mux.x - 1, uc_y, tl_color, 1)

    local y = l2.y_middle + 16
    local spacing = 10
    Drawing.MultiLineWithGaps(out, {main_mux.right, y, ">", main_mux.right + 10, "v", y + spacing, "<", main_mux.right + 3, " <", main_mux.x - 3, "<", l2.right + 2, color = tl_color})
    y = y + spacing * 2
    Drawing.MultiLineWithGaps(out, {main_mux.right, y, ">", main_mux.right + 10, "v", y + spacing, "<", main_mux.right + 3, " <", main_mux.x - 3, "<", mmu.right + 2, color = tl_color})
    y = y + spacing * 2
    Drawing.MultiLineWithGaps(out, {main_mux.right, y, ">", main_mux.right + 10, "v", y + spacing, "<", main_mux.right + 3, " <", main_mux.x - 3, "<", mmu.right + 3, " <", mmu.x - 3, "<", x280.right + 2, color = tl_color})
  end
  local l3 = Drawing.RectText(out, {x = main_mux.right + 20, y = 100, w = 60, h = 380, color = data_color}, {"L3 $", "2 MiB"})
  local dma = Drawing.RectText(out, {x = l3.x, bottom = l3.y - 20, w = l3.w, h = 60, color = xu_color}, {"DMA", "Engine"})
  local post_l3_mux = Drawing.Mux(direction == "D2H" and nul or out, {x = l3.right + 20, w = 10, y = dma.y_middle - mux_pad, bottom = l3.bottom + 50}, ">")
  do
    local l3_y = (harts[1].mmu.bottom + harts[2].mmu.y) * 0.5
    Drawing.ThickArrow(out, main_mux.right + 0.5, l3_y, "->", l3.x - 1, l3_y, tl_color, 1)
  end
  Drawing.MultiLine(out, {main_mux.right, dma.bottom - 8, ">", dma.x - 2})
  if direction == "H2D" then
    Drawing.ThickArrow(out, dma.right + 0.5, dma.y_middle, "->", post_l3_mux.x - 1, dma.y_middle, "black", 1)
    Drawing.MultiLine(out, {dma.x, dma.y + 8, "<", main_mux.x - 20, "v", harts[0].l2.y - 10, ">", main_mux.x - 1, thick = 1})

    Drawing.ThickArrow(out, l3.right + 0.5, l3.y_middle, "->", post_l3_mux.x - 1, l3.y_middle, "black", 1)
    do
      local uc_y = post_l3_mux.bottom - mux_pad - 2
      Drawing.ThickArrow(out, main_mux.right + 0.5, uc_y, "->", post_l3_mux.x - 1, uc_y, "black", 1)
    end
  end
  Drawing.MultiLine(out, {main_mux.right, post_l3_mux.bottom - mux_pad - 16, ">", l3.x_middle, "^", l3.bottom + 2, color = tl_color})

  local tlbs = Drawing.RectText(out, {x = post_l3_mux.right + 20, right = niu_mux.x - 20, y_middle = niu_mux.y_middle, h = 36, color = xu_color}, "TLBs")
  if direction == "H2D" then
    Drawing.ThickArrow(out, post_l3_mux.right + 0.5, tlbs.y_middle, "->", tlbs.x - 1, tlbs.y_middle, "black", 1)
    Drawing.ThickArrow(out, tlbs.right + 0.5, tlbs.y_middle, "->", niu_mux.x - 1, tlbs.y_middle, "black", 1)
  end
  local peripherals = Drawing.RectText(out, {x = l3.x, y = post_l3_mux.bottom + 10, w = 240, h = 36, color = xu_color}, {"External Peripherals"})
  local msi_catcher = Drawing.RectText(out, {right = peripherals.right, y = peripherals.bottom + 20, w = 80, h = 52, color = xu_color}, {"MSI", "Catcher"})
  local scratch = Drawing.RectText(out, {right = msi_catcher.x - 20, y = peripherals.bottom + 20, w = 80, h = msi_catcher.h, color = data_color}, {"Scratch", "64 Bytes"})
  for _, box in ipairs{msi_catcher, scratch} do
    Drawing.MultiLine(out, {box.x_middle, peripherals.bottom, "v", box.y - 2})
  end
  Drawing.ThickArrow(out, main_mux.right + 0.5, peripherals.y_middle, "->", peripherals.x - 1, peripherals.y_middle, "black", 1)
  Drawing.MultiLine(out, {tlbs.x_middle, peripherals.y, "^", tlbs.bottom + 2})
  Drawing.MultiLine(out, {peripherals.right, peripherals.y_middle, ">", mux3.x_middle, "^", mux3.bottom + 2})
  for i = 0, 3 do
    local segments = {peripherals.x + 10 + i * 12, peripherals.bottom, "v", main_mux.bottom + 15 + 10 * i, "<", harts[1].x280.right - 10 - 14 * i}
    for j = 0, 3 do
      local x280 = harts[3 - j].x280
      segments[#segments + 1] = "^"
      if i == j then
        segments[#segments + 1] = x280.bottom + 2
        break
      end
      segments[#segments + 1] = x280.bottom + 3
      segments[#segments + 1] = " ^"
      segments[#segments + 1] = x280.y - 3
    end
    Drawing.MultiLineWithGaps(out, segments)
  end

  if direction == "D2H" then
    Drawing.MultiLine(out, {niu_mux.x, nius[1].y_middle + 8, "<", niu_mux.x - 34, "^", 5.5, "<", main_mux.x - 40, "v", harts[0].l2.y - 10, ">", main_mux.x - 1, thick = 1})
    Drawing.MultiLine(out, {niu_mux.x, nius[2].y_middle - 8, "<", niu_mux.x - 34, "v", peripherals.y - 1, thick = 1})
  else
    local y0 = post_l3_mux.bottom - (tlbs.y_middle - post_l3_mux.y)
    local dx = peripherals.right + 60
    local dy = msi_catcher.bottom + 25
    out:putf([[<rect x="%g" y="%g" width="%g" height="%g" stroke="transparent" fill="white"/>]], tlbs.x_middle - 3, y0 - 5, mux3.x_middle - tlbs.x_middle + 6, 10)
    Drawing.MultiLine(out, {post_l3_mux.right, y0, ">", dx, "v", dy, thick = 1})
    out:putf([[<text x="%d" y="%d" text-anchor="end" dominant-baseline="hanging">To DRAM tile</text>]], dx + 18, dy + 7)
  end

  CDC(out, "L2SYS", cdc_x, 350, nil)
  CDC(out, "Clock", cdc_x, 370, "AI Clock")

  out:putf"</svg>\n"
  return tostring(out)
end

assert(io.open(own_dir .."../Out/EdgeTile_ARC_H2D.svg", "w")):write(ARC"H2D")
assert(io.open(own_dir .."../Out/EdgeTile_ARC_D2H.svg", "w")):write(ARC"D2H")
assert(io.open(own_dir .."../Out/EdgeTile_GDDR.svg", "w")):write(GDDR{})
assert(io.open(own_dir .."../Out/EdgeTile_PCIe_H2D.svg", "w")):write(PCIe("H2D", "WH"))
assert(io.open(own_dir .."../Out/EdgeTile_PCIe_D2H.svg", "w")):write(PCIe("D2H", "WH"))

assert(io.open(own_dir .."../Out/EdgeTile_BH_PCIe_H2D.svg", "w")):write(PCIe("H2D", "BH"))
assert(io.open(own_dir .."../Out/EdgeTile_BH_PCIe_D2H.svg", "w")):write(PCIe("D2H", "BH"))
assert(io.open(own_dir .."../Out/EdgeTile_BH_L2CPU_H2D.svg", "w")):write(L2CPU"H2D")
assert(io.open(own_dir .."../Out/EdgeTile_BH_L2CPU_D2H.svg", "w")):write(L2CPU"D2H")
