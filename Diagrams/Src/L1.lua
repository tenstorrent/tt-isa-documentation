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

local function CurvingLine(out, data)
  local x = data[1]
  local y = data[2]
  out:putf([[<path d="M %g %g]], x, y)
  local xs = {x}
  local ys = {y}
  for i = 3, #data, 2 do
    local cmd = data[i]
    local val = data[i + 1]
    if cmd == ">" or cmd == "<" then
      x = val
    elseif cmd == "^" or cmd == "v" then
      y = val
    else
      error("Invalid command ".. cmd)
    end
    xs[#xs + 1] = x
    ys[#ys + 1] = y
  end
  local function in_dir_of(x, y, ox, oy)
    local dx = ox - x
    local dy = oy - y
    local scale = (dx * dx + dy * dy) ^ -0.5 * 3
    dx = dx * scale
    dy = dy * scale
    return x + dx, y + dy
  end
  for i = 2, #xs - 1 do
    local x0, x1, x2 = xs[i - 1], xs[i], xs[i + 1]
    local y0, y1, y2 = ys[i - 1], ys[i], ys[i + 1]
    local cx, cy = in_dir_of(x1, y1, x0, y0)
    out:putf(" L %g %g", cx, cy)
    out:putf(" Q %g %g %g %g", x1, y1, in_dir_of(x1, y1, x2, y2))
  end
  x, y = xs[#xs], ys[#ys]
  out:putf([[ L %g %g" stroke="black" fill="transparent" stroke-width="1"/>]], x, y)
  if data.head ~= false then
    local dx, dy = in_dir_of(0, 0, xs[#xs - 1] - x, ys[#ys - 1] - y)
    local nx, ny = dy, -dx
    out:putf([[<path d="M %g %g L %g %g L %g %g" stroke="black" fill="transparent" stroke-width="1"/>]],
      x + dx + nx, y + dy + ny,
      x, y,
      x + dx - nx, y + dy - ny)
  end
end

local function WireTextRight(out, x, y, text)
  local x2 = x + 28
  CurvingLine(out, {x, y, ">", x + 24, head = false})
  out:putf([[<text x="%d" y="%d" text-anchor="start" dominant-baseline="middle">%s</text>]], x2, y + 1, text)
end

local function L1(args)
  local eth = args.eth
  local out = buffer.new()
  local nul = buffer.new()
  local dims = {w = 655, h = eth and 600 or 960}
  out:putf([[<svg version="1.1" width="%u" height="%u" xmlns="http://www.w3.org/2000/svg">]], dims.w, dims.h)
  out:putf([[<rect width="%u" height="%u" rx="15" stroke="transparent" fill="white"/>]], dims.w, dims.h)

  local y_pad_mux = 15

  local client_id
  local client_list
  if eth then
    client_id = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 15}
    client_list = {
      "NoC 1 (write or atomic)",
      "NoC 1 (write or atomic)",
      "NoC 1 (read)",
      "NoC 1 (read)",
      "NoC 0 (write or atomic)",
      "NoC 0 (write or atomic)",
      "NoC 0 (read)",
      "NoC 0 (read)",
      "ECC Scrubber (atomic)",
      "RISCV E (read or write)",
      "Ethernet TX (read)",
      "Ethernet TX (read)",
      "Ethernet RX (write)",
      "Ethernet RX (write)",
      "Debug Daisychain (read or write)",
    }
  else
    client_id = {1, 0, 9, 10, 11, 2, 8, 3, 4, 5, 6, 7, 12, 13, 14, 15}
    client_list = {
      {
        "ECC Scrubber (atomic)",
        "Packer 1 (write or accumulate)",
        "Unpacker 1 (read)"
      },
      "Unpacker 0 (read)",
      {
        "Unpacker 0 (read)",
        "Unpacker 1 (read)"
      },
      {
        "Unpacker 0 (read)",
        "Unpacker 1 (read)"
      },
      {
        "Unpacker 0 (read)",
        "Unpacker 1 (read)"
      },
      {
        {
          {
            "Unpacker 0 (read, for BFP exponents)",
            "Unpacker 1 (read, for BFP exponents)",
          },
          "Packer 0 (read, for L1-to-L1 pack operations)",
          "Packer 2 (write or accumulate)",
          "ThCon (read or write or atomic)",
          "Mover (read)",
        },
        "RISCV B (read or write)",
        "RISCV NC (read or write)",
        "RISCV T0 (read or write)",
      },
      "Packer 0 (write or accumulate)",
      {
        "RISCV T1 (read or write)",
        "RISCV T2 (read or write)",
        {
          "Mover (write)",
          "TDMA-RISC (write)",
          "Packer 3 (write or accumulate)",
        }
      },
      "NoC 0 (write or atomic)",
      "NoC 0 (write or atomic)",
      "NoC 0 (read)",
      "NoC 0 (read)",
      "NoC 1 (write or atomic)",
      "NoC 1 (write or atomic)",
      "NoC 1 (read)",
      {
        "NoC 1 (read)",
        "Debug Timestamper (write)",
        "Debug Daisychain (read or write)"
      },
    }
  end
  local function render_clients(x, y, client_list)
    if type(client_list) == "string" then
      WireTextRight(out, x, y, client_list)
      return y + 24, y
    else
      local x0 = x
      local x1 = x0 + 10
      x = x1 + 10
      local ymin, ymax = 10000, 0
      local cwire
      for _, client in ipairs(client_list) do
        y, cwire = render_clients(x, y, client)
        ymin = math.min(ymin, cwire)
        ymax = math.max(ymax, cwire)
      end
      local mux = Drawing.Mux(out, {x = x1, right = x, y = ymin - y_pad_mux, bottom = ymax + y_pad_mux}, "<")
      Drawing.LineTextAbove(out, {x0, mux.y_middle}, {mux.x, mux.y_middle})
      return math.max(y, mux.bottom + 12), mux.y_middle
    end
  end
  local ports = {}
  local y = 15.5 + 3
  local client_x = eth and 350 or 290
  for i, client in ipairs(client_list) do
    if eth then
      y = y + 15
    elseif 10 <= i and i <= 15 then
      y = y + 11
    elseif i == 4 or i == 5 then
      y = y + 8
    end

    local wire
    y, wire = render_clients(client_x, y, client)
    ports[i] = Drawing.RectText(out, {right = client_x, y_middle = wire, w = 80, h = 30, color = xu_color}, "Port #".. client_id[i])
  end

  local banks = {}
  local y = ports[1].y
  local bank_y_spacing = 6
  local bank_h_ideal = (ports[#ports].bottom - y - bank_y_spacing * 15) / 16
  local bank_h = math.floor(bank_h_ideal)
  local error_term = 0
  for i = 1, 16 do
    local this_h = bank_h
    error_term = error_term + (bank_h_ideal - this_h)
    if error_term > 0.5 then
      this_h = this_h + 1
      error_term = error_term - 1
    end
    banks[i] = Drawing.RectText(out, {x = 3.5, y = y, w = eth and 140 or 80, h = this_h, color = data_color}, eth and {"Bank #".. (i - 1) .."; 16 KiB"} or {"Bank #".. (i - 1), "91½ KiB"})
    y = banks[i].bottom + bank_y_spacing
  end

  local port_mux = Drawing.Mux(out, {right = ports[1].x - 50, w = 10, y = ports[1].y_middle - y_pad_mux, bottom = ports[#ports].y_middle + y_pad_mux}, "<")
  local bank_mux = Drawing.Mux(out, {right = port_mux.x - 5, w = 10, y = port_mux.y, h = port_mux.h}, ">")

  for i, port in ipairs(ports) do
    Drawing.LineTextAbove(out, {port_mux.right, port.y_middle}, {port.x, port.y_middle}, "128b")
  end
  for i, bank in ipairs(banks) do
    Drawing.LineTextAbove(out, {bank.right, bank.y_middle}, {bank_mux.x, bank.y_middle}, "128b")
    Drawing.LineTextAbove(out, {bank_mux.right, bank.y_middle}, {port_mux.x, bank.y_middle})
  end

  out:putf"</svg>\n"
  return tostring(out)
end

assert(io.open(own_dir .."../Out/L1.svg", "w")):write(L1{})
assert(io.open(own_dir .."../Out/L1_Eth.svg", "w")):write(L1{eth=true})
