/*
 * SPDX-FileCopyrightText: © 2025 Tenstorrent AI ULC
 *
 * SPDX-License-Identifier: Apache-2.0
 */

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#if defined(MAP_ANON) && !defined(MAP_ANONYMOUS)
#define MAP_ANONYMOUS MAP_ANON
#endif

#define FATAL(fmt, ...) do {fprintf(stderr, "FATAL ERROR: " fmt " (raised at %s:%d)\n",##__VA_ARGS__,__FILE__,__LINE__); exit(1);} while(0)

// Inlined copy of what we need from https://github.com/tenstorrent/tt-kmd/blob/main/ioctl.h:

#define TENSTORRENT_IOCTL_GET_DEVICE_INFO   0xFA00
#define TENSTORRENT_IOCTL_QUERY_MAPPINGS    0xFA02
#define TENSTORRENT_IOCTL_ALLOCATE_DMA_BUF  0xFA03
#define TENSTORRENT_IOCTL_PIN_PAGES         0xFA07
#define TENSTORRENT_IOCTL_ALLOCATE_TLB      0xFA0B
#define TENSTORRENT_IOCTL_SET_NOC_CLEANUP   0xFA0E

struct tenstorrent_get_device_info_in {
  uint32_t output_size_bytes;
};
struct tenstorrent_get_device_info_out {
  uint32_t output_size_bytes;
  uint16_t vendor_id;
  uint16_t device_id;
  uint16_t subsystem_vendor_id;
  uint16_t subsystem_id;
  uint16_t bus_dev_fn;            // [0:2] function, [3:7] device, [8:15] bus
  uint16_t max_dma_buf_size_log2; // Since 1.0
  uint16_t pci_domain;            // Since 1.23
};
struct tenstorrent_get_device_info {
  struct tenstorrent_get_device_info_in in;
  struct tenstorrent_get_device_info_out out;
};

#define TENSTORRENT_MAPPING_RESOURCE0_UC 1

struct tenstorrent_mapping {
  uint32_t mapping_id;
  uint32_t reserved;
  uint64_t mapping_base;
  uint64_t mapping_size;
};

#define TENSTORRENT_ALLOCATE_DMA_BUF_NOC_DMA 2

struct tenstorrent_allocate_dma_buf_in {
  uint32_t requested_size;
  uint8_t  buf_index; // [0,TENSTORRENT_MAX_DMA_BUFS)
  uint8_t  flags;
  uint8_t  reserved0[2];
  uint64_t reserved1[2];
};
struct tenstorrent_allocate_dma_buf_out {
  uint64_t physical_address; // or IOVA
  uint64_t mapping_offset;
  uint32_t size;
  uint32_t reserved0;
  uint64_t noc_address; // valid if TENSTORRENT_ALLOCATE_DMA_BUF_NOC_DMA is set
  uint64_t reserved1;
};
struct tenstorrent_allocate_dma_buf {
  struct tenstorrent_allocate_dma_buf_in  in;
  struct tenstorrent_allocate_dma_buf_out out;
};

#define TENSTORRENT_PIN_PAGES_NOC_DMA      2 // app wants to use the pages for NOC DMA
#define TENSTORRENT_PIN_PAGES_NOC_TOP_DOWN 4

struct tenstorrent_pin_pages_in {
  uint32_t output_size_bytes;
  uint32_t flags;
  uint64_t virtual_address;
  uint64_t size;
};
struct tenstorrent_pin_pages_out_extended {
  uint64_t physical_address;
  uint64_t noc_address;
};
struct tenstorrent_pin_pages_extended {
  struct tenstorrent_pin_pages_in in;
  struct tenstorrent_pin_pages_out_extended out;
};

struct tenstorrent_allocate_tlb_in {
  uint64_t size;
  uint64_t reserved;
};
struct tenstorrent_allocate_tlb_out {
  uint32_t id;
  uint32_t reserved0;
  uint64_t mmap_offset_uc;
  uint64_t mmap_offset_wc;
  uint64_t reserved1;
};
struct tenstorrent_allocate_tlb {
  struct tenstorrent_allocate_tlb_in  in;
  struct tenstorrent_allocate_tlb_out out;
};

struct tenstorrent_set_noc_cleanup {
  uint32_t argsz;
  uint32_t flags;
  uint8_t enabled;
  uint8_t x;
  uint8_t y;
  uint8_t noc;
  uint32_t reserved0;
  uint64_t addr;
  uint64_t data;
};

// Very thin user-mode driver, sufficient for poking around in device memory:

typedef struct bh_pcie_device_t {
  int fd;
  uint32_t tlb_cfg[2]; // Cached contents of *tlb_reconfigure, to avoid reconfiguration.
  volatile uint32_t* tlb_reconfigure;
  char* tlb; // 2 MiB window into device memory, configured using tlb_reconfigure.
  size_t host_page_size;
  size_t total_mmap_size;
} bh_pcie_device_t;

#define PCI_VENDOR_ID_TENSTORRENT 0x1E52
#define PCI_DEVICE_ID_BLACKHOLE	  0xB140

#define TLB_CONFIG_ADDR         0x1FC00000
#define TLB_CONFIG_ADDR_STRIDES 0x1FC009D8
#define TLB_CONFIG_ADDR_END     0x1FC00A58

#define INVALID_PARSE ((uintptr_t)(intptr_t)-1)

static uintptr_t parse_small_int(const char* str) {
  uint32_t out = 0;
  unsigned num_digits = 0;
  for (;;) {
    char c = *str++;
    if ('0' <= c && c <= '9') {
      out = out * 10 + (c - '0');
      num_digits |= 1;
      if (out == 0) continue;
      num_digits += 2;
      if (num_digits < 20) continue;
    } else if (c == '\0') {
      if (num_digits) return (uintptr_t)(int32_t)out;
    } else if (c == ' ' || (c == '+' && out == 0)) {
      continue;
    }
    return INVALID_PARSE;
  }
}

static bh_pcie_device_t* open_bh_pcie_device(const char* device_fn) {
  // If passed an integer or an empty string, form a more useful path.
  char device_fn_buf[20];
  int32_t device_num = (device_fn == NULL || *device_fn == '\0') ? 0 : (int32_t)parse_small_int(device_fn);
  if (device_num >= 0 && device_num < 100) {
    sprintf(device_fn_buf, "/dev/tenstorrent/%u", (unsigned)device_num);
    device_fn = device_fn_buf;
  }

  // Try to open the path.
  int fd = open(device_fn, O_RDWR | O_CLOEXEC);
  if (fd < 0) FATAL("Could not open device path '%s'", device_fn);

  // Confirm that it looks like a BH device.
  struct tenstorrent_get_device_info dev_info;
  memset(&dev_info, 0, sizeof(dev_info));
  dev_info.in.output_size_bytes = sizeof(dev_info.out);
  if (ioctl(fd, TENSTORRENT_IOCTL_GET_DEVICE_INFO, &dev_info) < 0
  ||  dev_info.out.vendor_id != PCI_VENDOR_ID_TENSTORRENT
  ||  dev_info.out.device_id != PCI_DEVICE_ID_BLACKHOLE) {
    FATAL("Path '%s' does not seem to be a Tenstorrent Blackhole device", device_fn);
  }

  // We want a single 2 MiB TLB for accessing memory on the device.
  struct tenstorrent_allocate_tlb alloc_tlb;
  memset(&alloc_tlb, 0, sizeof(alloc_tlb));
  alloc_tlb.in.size = 1u << 21;
  if (ioctl(fd, TENSTORRENT_IOCTL_ALLOCATE_TLB, &alloc_tlb) < 0) {
    FATAL("Could not allocate a 2 MiB TLB on device '%s'; is tt-kmd too old?", device_fn);
  }

  // We want BAR0 for reconfiguring the TLB (tt-kmd has a reconfiguration syscall, but we prefer to do it ourselves).
  uint8_t resource_to_mapping[8] = {0};
  struct tenstorrent_mapping mappings[9];
  mappings[0].mapping_size = 8;
  if (ioctl(fd, TENSTORRENT_IOCTL_QUERY_MAPPINGS, &mappings[0].mapping_size) >= 0) {
    for (unsigned i = 1; i < 9; ++i) {
      uint32_t resource = mappings[i].mapping_id;
      if (resource < 8) resource_to_mapping[resource] = i;
    }
  }
  mappings[0].mapping_size = 0;
  struct tenstorrent_mapping* bar0uc = mappings + resource_to_mapping[TENSTORRENT_MAPPING_RESOURCE0_UC];
  if (bar0uc->mapping_size < TLB_CONFIG_ADDR_END) {
    FATAL("BAR0 on device '%s' is only %u bytes, which is less than the required %u bytes", device_fn,
      (unsigned)bar0uc->mapping_size, (unsigned)TLB_CONFIG_ADDR_END);
  }

  // Map the various pieces of memory.
  long page = sysconf(_SC_PAGESIZE);
  if (page <= 1) page = 4096;
  size_t header_size = ((sizeof(bh_pcie_device_t) - 1) / (size_t)page + 1) * (size_t)page;
  size_t bar0_start = (TLB_CONFIG_ADDR / (size_t)page) * (size_t)page;
  size_t bar0_size = ((TLB_CONFIG_ADDR_END - bar0_start - 1) / (size_t)page + 1) * (size_t)page;
  size_t tlb_size = (((1u << 21) - 1) / (size_t)page + 1) * (size_t)page;
  size_t total_mmap_size = header_size + bar0_size + tlb_size;
  void* memory = mmap(NULL, total_mmap_size, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (memory == MAP_FAILED
  ||  mprotect(memory, header_size, PROT_READ | PROT_WRITE) != 0
  ||  mmap((char*)memory + header_size, bar0_size, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, bar0uc->mapping_base + bar0_start) == MAP_FAILED
  ||  mmap((char*)memory + header_size + bar0_size, 1u << 21, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, fd, alloc_tlb.out.mmap_offset_uc) == MAP_FAILED) {
    FATAL("Could not map memory for communicating with device '%s'", device_fn);
  }

  // Some TLB configuration we set once and never change; set that now.
  volatile uint32_t* tlb_reconfigure = (volatile uint32_t*)((char*)memory + header_size + (TLB_CONFIG_ADDR - bar0_start));
  if (alloc_tlb.out.id < 32) {
    tlb_reconfigure[(TLB_CONFIG_ADDR_STRIDES - TLB_CONFIG_ADDR) / sizeof(uint32_t) + alloc_tlb.out.id] = 0;
  }
  tlb_reconfigure += alloc_tlb.out.id * 3;
  tlb_reconfigure[2] = (1u << 6); // TLB_CFG_STRICT_AXI

  // Have everything we need; package it up and return it.
  bh_pcie_device_t* result = (bh_pcie_device_t*)memory;
  result->tlb_cfg[0] = tlb_reconfigure[0];
  result->tlb_cfg[1] = tlb_reconfigure[1];
  result->fd = fd;
  result->tlb_reconfigure = tlb_reconfigure;
  result->tlb = (char*)memory + header_size + bar0_size;
  result->host_page_size = (size_t)page;
  result->total_mmap_size = total_mmap_size;
  return result;
}

static void close_bh_pcie_device(bh_pcie_device_t* device) {
  close(device->fd);
  munmap(device, device->total_mmap_size);
}

static void set_tlb_xy(bh_pcie_device_t* device, unsigned x, unsigned y) {
  uint32_t c1 = device->tlb_cfg[1];
  uint32_t xy = (c1 & 0x7ff) + ((x & 0x3f) << 11) + ((y & 0x3f) << 17);
  if (xy != c1) {
    volatile uint32_t* tlb_reconfigure = device->tlb_reconfigure;
    tlb_reconfigure[1] = xy; // This is a slow UC write.
    device->tlb_cfg[1] = xy;
  }
}

static char* set_tlb_addr(bh_pcie_device_t* device, uint64_t addr) {
  // NB: The lo/mid/hi here are for PCIe 2 MiB TLBs. The on-device NIUs also have
  // fields with lo/mid/hi suffixes, but they use a totally different scheme.
  uint32_t addr_lo = (uint32_t)(addr & 0x1fffff);
  uint32_t addr_mid = (uint32_t)(addr >> 21);
  uint32_t addr_hi = (uint32_t)(addr >> 53);
  uint32_t c0 = device->tlb_cfg[0];
  uint32_t c1 = device->tlb_cfg[1];
  addr_hi += c1 & 0xfffff800; // Preserve the X/Y set by set_tlb_xy.
  char* result = device->tlb + addr_lo;
  volatile uint32_t* tlb_reconfigure = device->tlb_reconfigure;
  if (addr_mid != c0) {
    tlb_reconfigure[0] = addr_mid; // This is a slow UC write.
    device->tlb_cfg[0] = addr_mid;
  }
  if (addr_hi != c1) {
    tlb_reconfigure[1] = addr_hi; // This is a slow UC write.
    device->tlb_cfg[1] = addr_hi;
  }
  return result;
}

static void tlb_write_u32(bh_pcie_device_t* device, uint64_t addr, uint32_t value) {
  *(volatile uint32_t*)set_tlb_addr(device, addr) = value;
}

static uint32_t tlb_read_u32(bh_pcie_device_t* device, uint64_t addr) {
  return *(volatile uint32_t*)set_tlb_addr(device, addr);
}

typedef struct pinned_host_buffer_t {
  size_t size;
  void* host_ptr;
  uint64_t noc_addr;
} pinned_host_buffer_t;

static void allocate_host_buffer(bh_pcie_device_t* device, pinned_host_buffer_t* buf) {
  // Caller has set buf->size, this function populates buf->host_ptr and buf->noc_addr.

  // Try doing a regular allocation and pinning it.
  // This should work for 4 KiB allocations, or for any size if an IOMMU is present and enabled.
  void* memory = mmap(NULL, buf->size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  {
    struct tenstorrent_pin_pages_extended pin_req;
    memset(&pin_req, 0, sizeof(pin_req));
    pin_req.in.output_size_bytes = sizeof(pin_req.out);
    pin_req.in.flags = TENSTORRENT_PIN_PAGES_NOC_DMA | TENSTORRENT_PIN_PAGES_NOC_TOP_DOWN;
    pin_req.in.size = buf->size;
    if (memory != MAP_FAILED) {
      pin_req.in.virtual_address = (uint64_t)(uintptr_t)memory;
      if (ioctl(device->fd, TENSTORRENT_IOCTL_PIN_PAGES, &pin_req) >= 0) {
        buf->host_ptr = memory;
        buf->noc_addr = pin_req.out.noc_address;
        return;
      }
      munmap(memory, buf->size);
    }
    // Try doing a huge page allocation and pinning it.
    // This should work for any size configured as a huge page size.
    memory = mmap(NULL, buf->size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB | (__builtin_ctzll(buf->size) << MAP_HUGE_SHIFT), -1, 0);
    if (memory != MAP_FAILED) {
      pin_req.in.virtual_address = (uint64_t)(uintptr_t)memory;
      if (ioctl(device->fd, TENSTORRENT_IOCTL_PIN_PAGES, &pin_req) >= 0) {
        buf->host_ptr = memory;
        buf->noc_addr = pin_req.out.noc_address;
        return;
      }
      munmap(memory, buf->size);
    }
  }
  // Try doing a DMA allocation.
  // This should work for any size up to the DMA buffer size limit, subject to host memory fragmentation.
  {
    struct tenstorrent_allocate_dma_buf dma_req;
    memset(&dma_req, 0, sizeof(dma_req));
    dma_req.in.requested_size = buf->size;
    dma_req.in.flags = TENSTORRENT_ALLOCATE_DMA_BUF_NOC_DMA;
    if (ioctl(device->fd, TENSTORRENT_IOCTL_ALLOCATE_DMA_BUF, &dma_req) >= 0) {
      memory = mmap(NULL, buf->size, PROT_READ | PROT_WRITE, MAP_SHARED, device->fd, dma_req.out.mapping_offset);
      if (memory != MAP_FAILED) {
        buf->host_ptr = memory;
        buf->noc_addr = dma_req.out.noc_address;
        return;
      }
    }
  }
  // Out of options.
  FATAL("Could not allocate and pin a host buffer of %llu bytes", (long long unsigned)buf->size);
}

// Definitions for Ethernet tile address space:

#define ETH_BOOT_PARAMS_ADDR                    0x0007C000
#define ETH_BOOT_RESULTS_ADDR                   0x0007CC00
#define SOFT_RESET_ADDR                         0xFFB121B0
#define E1_RESET_PC_ADDR                        0xFFB14008
#define E1_END_PC_ADDR                          0xFFB1400C
#define NIU_ADDR(i)                            (0xFFB20000 + (i)*0x10000)
#define TXQ_ADDR(i)                            (0xFFB90000 + (i)*0x1000)
#define RXQ_ADDR(i)                            (0xFFB94000 + (i)*0x1000)
#define TXPKT_CFG_ADDR(i)                      (0xFFB98200 + (i)*0x80)
#define RXCLASS_MAC_RX_ROUTING_ADDR             0xFFB98150
#define RXCLASS_USER_DEFINED_ETHERTYPE_ADDR(i) (0xFFB9C000 + (i)*4)
#define RXCLASS_NO_MATCH_ACTIONS_ADDR           0xFFB9CD04
#define RXCLASS_TCAM_FLUSH                      0xFFB9CD60
#define RXCLASS_OVERRIDE_DECISION_ADDR          0xFFB9D000

// Offsets from NIU_ADDR:
#define NOC_TARG_ADDR_LO_OFFSET     0x000
#define NOC_TARG_ADDR_MID_OFFSET    0x004
#define NOC_TARG_ADDR_HI_OFFSET     0x008
#define NOC_RET_ADDR_LO_OFFSET      0x00C
#define NOC_RET_ADDR_MID_OFFSET     0x010
#define NOC_RET_ADDR_HI_OFFSET      0x014
#define NOC_PACKET_TAG_OFFSET       0x018
#define NOC_CTRL_OFFSET             0x01C
#define NOC_AT_LEN_BE_OFFSET        0x020
#define NOC_AT_LEN_BE_1_OFFSET      0x024
#define NOC_BRCST_EXCLUDE_OFFSET    0x02C
#define NOC_L1_ACC_AT_INSTRN_OFFSET 0x030
#define NOC_ENDPOINT_ID_OFFSET      0x048
#define NIU_CFG_0_OFFSET            0x100
#define ROUTER_CFG_2_OFFSET         0x10C // Has no hardware-defined meaning; we repurpose it for a host-to-device mailbox.
#define ROUTER_CFG_4_OFFSET         0x114 // Has no hardware-defined meaning; we repurpose it for host informing device of its read pointer.
#define NOC_ID_LOGICAL_OFFSET       0x148

// Offsets from TXQ_ADDR:
#define ETH_TXQ_CTRL_OFFSET                0x00
#define ETH_TXQ_CMD_OFFSET                 0x04
#define ETH_TXQ_TRANSFER_START_ADDR_OFFSET 0x14
#define ETH_TXQ_TRANSFER_SIZE_BYTES_OFFSET 0x18
#define ETH_TXQ_REMOTE_SEQ_TIMEOUT_OFFSET  0x48
#define ETH_TXQ_TXPKT_CFG_SEL_SW_OFFSET    0x80

// Offsets from RXQ_ADDR:
#define ETH_RXQ_CTRL_OFFSET                0x00
#define ETH_RXQ_BUF_PTR_OFFSET             0x08
#define ETH_RXQ_BUF_START_WORD_ADDR_OFFSET 0x0C
#define ETH_RXQ_BUF_SIZE_WORDS_OFFSET      0x10
#define ETH_RXQ_HDR_CTRL_OFFSET            0x18
#define ETH_RXQ_PACKET_DROP_CNT_OFFSET     0x4C

// Offsets from TXPKT_CFG_ADDR:
#define TXPKT_CFG_INSERT_CTL_OFFSET    0x00
#define TXPKT_CFG_MAC_SA_OFFSET        0x10
#define TXPKT_CFG_MAC_DA_OFFSET        0x18
#define TXPKT_CFG_USE_ETHERTYPE_OFFSET 0x20
#define TXPKT_CFG_L3_HEADER_OFFSET     0x30
#define TXPKT_CFG_L4_HEADER_OFFSET     0x60

// Values for TXPKT_CFG_INSERT_CTL_OFFSET:
#define TXPKT_CFG_INSERT_CTL_L3_HEADER   (1u <<  8)
#define TXPKT_CFG_INSERT_CTL_L4_HEADER   (1u << 16)
#define TXPKT_CFG_INSERT_CTL_L4_CHECKSUM (1u << 18)

// Values for RXCLASS_MAC_RX_ROUTING_ADDR:
#define RXCLASS_MAC_RX_ROUTING_FROM_MAC     0
#define RXCLASS_MAC_RX_ROUTING_FROM_ACTIONS 2

// Values for RXCLASS_NO_MATCH_ACTIONS_ADDR:
#define RXCLASS_NO_MATCH_ACTIONS_TO_RXQ(i)            (i)
#define RXCLASS_NO_MATCH_ACTIONS_DROP                   4
#define RXCLASS_NO_MATCH_ACTIONS_PREPEND_HW_METADATA 0x40

// Values for RXCLASS_OVERRIDE_DECISION_ADDR:
#define RXCLASS_OVERRIDE_DECISION_ACCEPT  0
#define RXCLASS_OVERRIDE_DECISION_DROP    1
#define RXCLASS_OVERRIDE_DECISION_REGULAR 2

// Values for NOC_RET_ADDR_HI_OFFSET:
#define BH_PCIE_XY (19 + (24 << 6))

// Values for NOC_CTRL_OFFSET:
#define NOC_CMD_WR 2
#define NOC_CMD_VC_STATIC (1u << 7)

// Values for NIU_CFG_0_OFFSET:
#define NIU_CFG_0_HARVESTED (1u << 12)

// Values for SOFT_RESET_ADDR:
#define SOFT_RESET_E0 0x0800
#define SOFT_RESET_E1 0x1000

// Inspecting or choosing an Ethernet tile:

static bool is_endpoint_id_ethernet(uint32_t endpoint_id) {
  return (uint16_t)(endpoint_id >> 8) == 0x0200;
}

static void print_hwinfo(bh_pcie_device_t* device) {
  printf("|Tile|NoC #0  |Logical  |Port   |Training    |Serdes          |MAC Address      |\n");
  printf("|----|--------|---------|-------|------------|----------------|-----------------|\n");
  for (unsigned x = 1, y = 1; x <= 16; ++x) {
    if (x == 8 || x == 9) continue;
    set_tlb_xy(device, x, y);
    uint32_t endpoint_id = tlb_read_u32(device, NIU_ADDR(0) + NOC_ENDPOINT_ID_OFFSET);
    if (!is_endpoint_id_ethernet(endpoint_id)) continue;
    uint32_t niu_cfg_0 = tlb_read_u32(device, NIU_ADDR(0) + NIU_CFG_0_OFFSET);
    printf("|E%-3u|X=%-2u,Y=%u|", (unsigned)(endpoint_id & 0xff), x, y);
    if (niu_cfg_0 & NIU_CFG_0_HARVESTED) {
      printf("Harvested|N/A    |N/A         |N/A             |N/A              |\n");
      continue;
    }
    unsigned noc_id_logical_xy = tlb_read_u32(device, NIU_ADDR(0) + NOC_ID_LOGICAL_OFFSET) & 0xfff;
    printf("X=%-2u,Y=%-2u|", noc_id_logical_xy & 0x3fu, noc_id_logical_xy >> 6);
    volatile uint32_t* boot_results = (volatile uint32_t*)set_tlb_addr(device, ETH_BOOT_RESULTS_ADDR);
    uint32_t port_status = boot_results[1];
    static const char* port_status_meanings[] = {"Unknown", "Up", "Down", "No"};
    if (port_status < sizeof(port_status_meanings)/sizeof(*port_status_meanings)) {
      printf("%-7s|", port_status_meanings[port_status]);
    } else {
      printf("Status %u|", (unsigned)port_status);
    }
    uint32_t train_status = port_status == 0 ? 0 : boot_results[2];
    static const char* train_status_meanings[] = {"In Progress", "Skipped", "Complete", "Int Loopback", "Ext Loopback", "Timeout (EQ)", "Timeout (AN)", "Timeout (CL)", "Timeout (BL)", "Timeout (LU)", "Timeout (CI)"};
    if (train_status < sizeof(train_status_meanings)/sizeof(*train_status_meanings)) {
      printf("%-12s|", train_status_meanings[train_status]);
    } else {
      printf("Status %-5u|", train_status);
    }
    uint32_t serdes_postcode = boot_results[32];
    if (serdes_postcode >= 0xC0DE1000 && serdes_postcode <= 0xC0DEFFFF) {
      uint32_t serdes_inst = boot_results[33];
      uint32_t serdes_lanes = boot_results[34];
      const char* lanes_prefix = " lanes ";
      printf("#%u", serdes_inst);
      for (unsigned i = 0; i < 8; ++i) {
        if (serdes_lanes & (1u << i)) {
          printf("%s%u", lanes_prefix, i);
          lanes_prefix = ",";
        }
      }
      printf("|");
    } else {
      printf("N/A             |");
    }
    if (port_status == 3) {
      // No port -> no MAC address.
      printf("N/A              |");
    } else {
      uint32_t mac_major;
      uint32_t mac_minor;
      if (boot_results[247] == 1) {
        // Tile has attempted chip info exchange with its peer, and we can snoop
        // the MAC address from said information buffer.
        mac_major = boot_results[243];
        mac_minor = boot_results[244];
      } else {
        // Copy of the current firmware logic for choosing a MAC address.
        volatile uint32_t* boot_params = (volatile uint32_t*)set_tlb_addr(device, ETH_BOOT_PARAMS_ADDR);
        uint32_t logical_id = __builtin_popcount(boot_params[0] & ((1u << (endpoint_id & 0x1f)) - 1));
        mac_major = boot_params[36];
        mac_minor = boot_params[37] + logical_id;
      }
      printf("%02x:%02x:%02x:%02x:%02x:%02x|",
        (uint8_t)(mac_major >> 16), (uint8_t)(mac_major >> 8), (uint8_t)(mac_major >> 0),
        (uint8_t)(mac_minor >> 16), (uint8_t)(mac_minor >> 8), (uint8_t)(mac_minor >> 0));
    }
    printf("\n");
  }
}

static void print_tx_headers(bh_pcie_device_t* device) {
  printf("|#|Destination MAC  |Source MAC       |Ethertype|\n");
  printf("|-|-----------------|-----------------|---------|\n");
  for (unsigned i = 0; i < 10; ++i) {
    uint32_t addr = TXPKT_CFG_ADDR(i);
    printf("|%u", i);
    for (unsigned j = 0; j < 2; ++j) {
      volatile uint32_t* ptr = (uint32_t*)set_tlb_addr(device, addr + (j ? TXPKT_CFG_MAC_SA_OFFSET : TXPKT_CFG_MAC_DA_OFFSET));
      uint32_t words[2] = {ptr[0], ptr[1]};
      uint8_t bytes[6] = {
        (uint8_t)(words[1] >>  8),
        (uint8_t)(words[1] >>  0),
        (uint8_t)(words[0] >> 24),
        (uint8_t)(words[0] >> 16),
        (uint8_t)(words[0] >>  8),
        (uint8_t)(words[0] >>  0)
      };
      for (unsigned k = 0; k < 6; ++k) {
        printf("%c%02x", k ? ':' : '|', bytes[k]);
      }
    }
    uint32_t ethertype = tlb_read_u32(device, addr + TXPKT_CFG_USE_ETHERTYPE_OFFSET);
    if (ethertype & 1) {
      printf("|0x%04x   ", ethertype >> 16);
    } else {
      printf("|Length   ");
    }
    printf("|\n");
  }
}

static void set_ethernet_x(bh_pcie_device_t* device, unsigned x) {
  unsigned y;
  if ((1 <= x && x <= 7) || (10 <= x && x <= 16)) {
    y = 1;
  } else if (20 <= x && x <= 31) {
    y = 25;
  } else {
    FATAL("X=%u is not in the valid range for potential Ethernet tiles; try between 20 and 31 instead", x);
  }
  set_tlb_xy(device, x, y);
  uint32_t endpoint_id = tlb_read_u32(device, NIU_ADDR(0) + NOC_ENDPOINT_ID_OFFSET);
  if (!is_endpoint_id_ethernet(endpoint_id)) {
    FATAL("Tile at X=%u,Y=%u is not an Ethernet tile; it reports NOC_ENDPOINT_ID=0x%08x", x, y, (unsigned)endpoint_id);
  }
  uint32_t niu_cfg_0 = tlb_read_u32(device, NIU_ADDR(0) + NIU_CFG_0_OFFSET);
  if (niu_cfg_0 & NIU_CFG_0_HARVESTED) {
    FATAL("Ethernet tile at X=%u,Y=%u has been harvested; try a different one", x, y);
  }
}

// RISCV machine code to run on Ethernet tile:
// This consumes data from an RX queue, and uses an NIU to shuttle the contents
// to a ring buffer somewhere in host memory. Most configuration is performed by
// the host prior to running this code on the device.

static const uint32_t rv_code[] = {
                          // init:
  0x00000297, 0x18828293, //   la t0, fn_arguments
  0x0002a503,             //   lw a0, 0(t0) # h_ring_base_lo
  0x0042a583,             //   lw a1, 4(t0) # h_ring_base_hi
  0x0082a603,             //   lw a2, 8(t0) # h_ring_size
  0x00c2a683,             //   lw a3, 12(t0) # metadata_ptr
  0x0102a703,             //   lw a4, 16(t0) # e_ring_mask
  0x0142a783,             //   lw a5, 20(t0) # initial_drop_count
  0x0182a803,             //   lw a6, 24(t0) # rxq_addr
  0x01c2a883,             //   lw a7, 28(t0) # niu2_addr
  0xffb02137,             //   li sp, 0xFFB02000
  0xfee12e23,             //   sw a4, -4(sp) # Put something non-zero at -4(sp)
  0xffc10b93,             //   addi s7, sp, -4 # Point tx_pending_flag_ptr at something non-zero (so that we don't take the tx_complete jump)
  0x00170c13,             //   addi s8, a4, 1 # e_ring_size = e_ring_mask + 1
  0xfff60c93,             //   addi s9, a2, -1 # h_ring_mask = h_ring_size - 1
  0x00003d37,             //   li s10, 12288 # Set noc_transaction_size_limit (the true limit for misaligned transfers is just shy of 16 KiB, this is a safe underapproximation)
  0x0280006f,             //   j done_e_ring_has_new_or_pending_data
                          // spin_loop:
                          //   # NB: t0, t1, t2, t3 set by loads just before `j spin_loop` (so that we utilise the load latency to perform the jump)
  0x12029263,             //   bne t0, x0, service_mailbox # Mailbox request from host? (NB: Branch target consumes t0)
                          // done_service_mailbox:
  0x0f336263,             //   bltu t1, s3, disable_wrap_mode # RXQ has wrapped?
                          // done_disable_wrap_mode:
  0x0a0e0263,             //   beq t3, x0, tx_complete # NoC transmit finished?
                          // done_tx_complete:
  0x00739393,             //   slli t2, t2, 7 # Want to multiply by 96, but mul by 128 is faster, and is a safe overapproximation
  0x41430333,             //   sub t1, t1, s4
  0x40730333,             //   sub t1, t1, t2 # t1 = (RXQ->ETH_RXQ_BUF_PTR - RXQ->ETH_RXQ_OUTSTANDING_WR_CNT * 128) - e_ring_front_ptr
                          // shift_fixup_0:
  0x00031293,             //   slli t0, t1, 0 # 0 is subject of fixup; once fixed, will move MSB of e_ring_mask to sign bit
  0x02504063,             //   bgt t0, x0, e_ring_has_new_data # New data in RXQ? (NB: Branch target consumes t1)
  0x035a1263,             //   bne s4, s5, e_ring_has_pending_data # Any data available to send to host?
                          // done_e_ring_has_new_or_pending_data:
  0x90c8a283,             //   lw t0, -1780(a7) # t0 = NIU->ROUTER_CFG_2 (using this as a mailbox)
  0x00882303,             //   lw t1, 0x08(a6)  # t1 = RXQ->ETH_RXQ_BUF_PTR
  0x05082383,             //   lw t2, 0x50(a6)  # t2 = RXQ->ETH_RXQ_OUTSTANDING_WR_CNT
  0x000bae03,             //   lw t3, 0(s7)     # t3 = *tx_pending_flag_ptr
  0x9148a903,             //   lw s2, -1772(a7) # h_ring_tail_ptr = NIU->ROUTER_CFG_4 (host writes here)
  0xfc9ff06f,             //   j spin_loop
                          // e_ring_has_new_data:
  0x006a0a33,             //   add s4, s4, t1 # e_ring_front_ptr = RXQ->ETH_RXQ_BUF_PTR - RXQ->ETH_RXQ_OUTSTANDING_WR_CNT * 128
  0x00ea7a33,             //   and s4, s4, a4 # e_ring_front_ptr &= e_ring_mask
                          // e_ring_has_pending_data:
  0xff6a90e3,             //   bne s5, s6, done_e_ring_has_new_or_pending_data # Already have a transfer leaving L1?
  0x40960333,             //   sub t1, a2, s1
  0x01230333,             //   add t1, t1, s2 # t1 = h_ring_size - (h_ring_next_ptr - h_ring_tail_ptr)
  0x415a03b3,             //   sub t2, s4, s5
  0x0a735333,             //   minu t1, t1, t2 # t1 = minu(t1, e_ring_front_ptr - e_ring_next_ptr)
  0xfc0306e3,             //   beq t1, x0, done_e_ring_has_new_or_pending_data # Ring full?
  0x415c03b3,             //   sub t2, s8, s5
  0x0a735333,             //   minu t1, t1, t2 # t1 = minu(t1, e_ring_size - e_ring_next_ptr)
  0x0194f2b3,             //   and t0, s1, s9 # t0 = h_ring_next_ptr & h_ring_mask
  0x0ba35333,             //   minu t1, t1, s10 # t1 = minu(t1, noc_transaction_size_limit)
  0x006484b3,             //   add s1, s1, t1 # h_ring_next_ptr += t1
  0x0096a023,             //   sw s1, 0(a3) # metadata_ptr->h_ring_next_ptr = h_ring_next_ptr
  0x8158a023,             //   sw s5, -2048(a7) # NIU->NOC_TARG_ADDR_LO = e_ring_next_ptr (assuming ring base is 0)
  0x8268a023,             //   sw t1, -2016(a7) # NIU->NOC_AT_LEN_BE = t1
  0x00a282b3,             //   add t0, t0, a0 # t0 += h_ring_base_lo
  0x8058a623,             //   sw t0, -2036(a7) # NIU->NOC_RET_ADDR_LO
  0x00a2b2b3,             //   sltu t0, t0, a0 # t0 = carry bit from prior addition
  0x00b282b3,             //   add t0, t0, a1 # t0 += h_ring_base_hi
  0x8058a823,             //   sw t0, -2032(a7) # NIU->NOC_RET_ADDR_MID
  0x84e8a023,             //   sw a4, -1984(a7) # NIU->NOC_CMD_CTRL = e_ring_mask (all we need is the low bit set)
  0x04e8a023,             //   sw a4, 0x40(a7) # NIU2->NOC_CMD_CTRL = e_ring_mask (all we need is the low bit set)
  0x0408a003,             //   lw x0, 0x40(a7) # Ensure that the NOC_CMD_CTRL store is sent out before any future NIU_MST_WRITE_REQS_OUTGOING_ID load
  0x006a8ab3,             //   add s5, s5, t1 # e_ring_next_ptr += t1
  0x00eafab3,             //   and s5, s5, a4 # e_ring_next_ptr &= e_ring_mask
  0xa8088b93,             //   addi s7, a7, -1408 # tx_pending_flag_ptr = &NIU->NIU_MST_WRITE_REQS_OUTGOING_ID(0)
  0xf7dff06f,             //   j done_e_ring_has_new_or_pending_data
                          // tx_complete:
  0xffc10b93,             //   addi s7, sp, -4 # Point tx_pending_flag_ptr at something non-zero (so that we don't take the tx_complete jump again)
  0x015b42b3,             //   xor t0, s6, s5 # t0 = e_ring_tail_ptr ^ e_ring_next_ptr
  0x000a8b13,             //   mv s6, s5 # e_ring_tail_ptr = e_ring_next_ptr
                          // shift_fixup_1:
  0x00029293,             //   slli t0, t0, 0 # 0 is subject of fixup; once fixed, will move MSB of e_ring_mask to sign bit
  0xf402d8e3,             //   bge t0, x0, done_tx_complete # Still consuming same half of RXQ?
                          //   # Have changed which half we're consuming
  0x004c5293,             //   srli t0, s8, 4
  0x00582823,             //   sw t0, 0x10(a6) # RXQ->ETH_RXQ_BUF_SIZE_WORDS = e_ring_size >> 4
  0x2002e9b3,             //   sh3add s3, t0, x0
  0x0159f9b3,             //   and s3, s3, s5 # e_ring_wrap_thr = e_ring_next_ptr & (e_ring_size >> 1)
                          // shift_fixup_2:
  0x0009d293,             //   srli t0, s3, 0 # 0 is subject of fixup; once fixed, will move MSB of e_ring_mask to 4
  0x00582023,             //   sw t0, 0x00(a6) # RXQ->ETH_RXQ_CTRL = e_ring_wrap_thr ? 4 : 0
  0x00082003,             //   lw x0, 0x00(a6) # Ensure that the ETH_RXQ_CTRL store is sent out before the ETH_RXQ_PACKET_DROP_CNT load
  0x04c82283,             //   lw t0, 0x4C(a6) # t0 = RXQ->ETH_RXQ_PACKET_DROP_CNT
  0xf2f286e3,             //   beq t0, a5, done_tx_complete # Still haven't dropped anything?
  0x0240006f,             //   j err_overflow
                          // disable_wrap_mode: # Preserves t1, t2, t3
                          //   # RXQ has wrapped, disable wrapping mode until we're ready for it to wrap again
  0x00082023,             //   sw x0, 0x00(a6) # RXQ->ETH_RXQ_CTRL = 0 (i.e. raw RX mode, wrapping disabled)
  0xfffb0293,             //   addi t0, s6, -1
  0x0042d293,             //   srli t0, t0, 4
  0x00582823,             //   sw t0, 0x10(a6) # RXQ->ETH_RXQ_BUF_SIZE_WORDS = (e_ring_tail_ptr - 1) >> 4
  0x01082003,             //   lw x0, 0x10(a6) # Ensure that the ETH_RXQ_BUF_SIZE_WORDS store is sent out before the ETH_RXQ_PACKET_DROP_CNT load
  0x04c82283,             //   lw t0, 0x4C(a6) # t0 = RXQ->ETH_RXQ_PACKET_DROP_CNT
  0x00000993,             //   mv s3, x0 # e_ring_wrap_thr = 0 (no longer checking for wrap)
  0xf0f282e3,             //   beq t0, a5, done_disable_wrap_mode # Still haven't dropped anything?
                          // err_overflow:
  0x00100293,             //   li t0, 1
  0x0056a423,             //   sw t0, 8(a3) # metadata_ptr->error = t0
                          // err_overflow_spin:
  0xa808a283,             //   lw t0, -1408(a7) # t0 = NIU->NIU_MST_WRITE_REQS_OUTGOING_ID(0)
  0x0000000f,             //   fence
  0xfe029ce3,             //   bne t0, x0, err_overflow_spin
  0x04e8a023,             //   sw a4, 0x40(a7) # NIU2->NOC_CMD_CTRL = e_ring_mask (all we need is the low bit set)
                          // finished:
  0x0000006f,             //   j finished
                          // service_mailbox:
  0x0056a223,             //   sw t0, 4(a3) # metadata_ptr->mailbox_echo = t0
  0x9008a623,             //   sw x0, -1780(a7) # NIU->ROUTER_CFG_2 = 0 (clearing mailbox)
                          // service_mailbox_spin:
  0xa808a283,             //   lw t0, -1408(a7) # t0 = NIU->NIU_MST_WRITE_REQS_OUTGOING_ID(0)
  0x0000000f,             //   fence
  0xfe029ce3,             //   bne t0, x0, service_mailbox_spin
  0x04e8a023,             //   sw a4, 0x40(a7) # NIU2->NOC_CMD_CTRL = e_ring_mask (all we need is the low bit set)
  0x0408a003,             //   lw x0, 0x40(a7) # Ensure that the NOC_CMD_CTRL store is sent out before any future NIU_MST_WRITE_REQS_OUTGOING_ID load
  0xec5ff06f              //   j done_service_mailbox
                          // fn_arguments:
};
#define label_init 0x0
#define label_spin_loop 0x44
#define label_done_service_mailbox 0x48
#define label_done_disable_wrap_mode 0x4c
#define label_done_tx_complete 0x50
#define label_shift_fixup_0 0x5c
#define label_done_e_ring_has_new_or_pending_data 0x68
#define label_e_ring_has_new_data 0x80
#define label_e_ring_has_pending_data 0x88
#define label_tx_complete 0xf0
#define label_shift_fixup_1 0xfc
#define label_shift_fixup_2 0x114
#define label_disable_wrap_mode 0x12c
#define label_err_overflow 0x14c
#define label_err_overflow_spin 0x154
#define label_finished 0x164
#define label_service_mailbox 0x168
#define label_service_mailbox_spin 0x170
#define label_fn_arguments 0x188

typedef struct rv_code_arguments_t {
  uint64_t h_ring_noc_addr;
  uint32_t h_ring_size;
  uint32_t h_meta_addr;
  uint32_t e_ring_mask;
  uint32_t initial_drop_count;
  uint32_t rxq_addr;
  uint32_t niu_addr;
} rv_code_arguments_t;

// Minimal pcap file writer:

#define PCAP_WRITER_NUM_IOVS 20

typedef struct pcap_writer_t {
  int fd;
  int iovcnt;
  size_t total_pkt_count;
  size_t total_byte_count;
  struct iovec iovs[PCAP_WRITER_NUM_IOVS];
  uint32_t pkt_hdrs[PCAP_WRITER_NUM_IOVS * 4];
} pcap_writer_t;

static void flush_packets(pcap_writer_t* writer) {
  int fd = writer->fd;
  struct iovec* iovs = writer->iovs;
  int iovcnt = writer->iovcnt;
  writer->iovcnt = 0;
  for (;;) {
    ssize_t n = writev(fd, iovs, iovcnt);
    if (n > 0) {
      writer->total_byte_count += n;
      while (iovs->iov_len <= (size_t)n) {
        if (--iovcnt == 0) return;
        n -= iovs->iov_len;
        ++iovs;
      }
      iovs->iov_len -= n;
      iovs->iov_base = (char*)iovs->iov_base + n;
    } else if (n == 0 || errno != EINTR) {
      FATAL("Could not write to output file");
    }
  }
}

static void pcap_writer_init(pcap_writer_t* writer, const char* filename) {
  int fd = open(filename, O_CLOEXEC | O_CREAT | O_TRUNC | O_WRONLY, 0644);
  if (fd < 0) FATAL("Could not open path '%s' for pcap writing", filename);
  writer->fd = fd;
  writer->total_byte_count = 0;
  writer->total_pkt_count = 0;

  uint32_t* pcap_hdr = writer->pkt_hdrs;
  pcap_hdr[0] = 0xA1B23C4D; // Magic number for pcap with timestamps in nanoseconds
  pcap_hdr[1] = 2 + (2 << 16); // Version 2.2
  pcap_hdr[2] = 0; // Timezone correction
  pcap_hdr[3] = 0; // Timestamp accuracy
  pcap_hdr[4] = (1 << 14) - 1; // Maximum capture length
  pcap_hdr[5] = 1; // Ethernet
  writer->iovs[0].iov_base = pcap_hdr;
  writer->iovs[0].iov_len = sizeof(uint32_t) * 6;
  writer->iovcnt = 1;
  flush_packets(writer);
}

static uint32_t append_packets(pcap_writer_t* writer, pinned_host_buffer_t* h_ring, uint32_t read_ptr, uint32_t write_ptr) {
  uint8_t* ring_contents = (uint8_t*)h_ring->host_ptr;
  uint32_t ring_size = h_ring->size;
  int iovcnt = writer->iovcnt;
  while (iovcnt <= (PCAP_WRITER_NUM_IOVS-3) && (write_ptr - read_ptr) >= sizeof(uint32_t)) { // 3 IOVs is the maximum we'll need to write a frame, and 4 bytes is minimum we'll need to read one.
    // Read the frame metadata.
    uint32_t frame_info;
    uint32_t read_ptr_masked = read_ptr & (ring_size - 1);
    if (read_ptr_masked <= ring_size - sizeof(frame_info)) {
      // Metadata does not straddle a ring wrap; this should compile to a simple unaligned load.
      memcpy(&frame_info, ring_contents + read_ptr_masked, sizeof(frame_info));
    } else {
      // Metadata straddles a ring wrap; perform aligned loads from either end of the
      // ring, and then shift bits around to get what we're after.
      uint32_t end = *(volatile uint32_t*)(ring_contents + ring_size - sizeof(uint32_t));
      uint32_t start = *(volatile uint32_t*)ring_contents;
      uint32_t shift = (ring_size - read_ptr_masked) * __CHAR_BIT__;
      end >>= (0u - shift) & 31;
      start <<= shift;
      frame_info = end + start;
    }
    frame_info = __builtin_bswap32(frame_info);
    if ((frame_info & 0xe0880000) != 0u || (frame_info & 0xfffff) < 14u) {
      FATAL("Ring is corrupt at read pointer 0x%x / write pointer 0x%x, as hardware metadata for a ring entry should never be 0x%08x", read_ptr, write_ptr, frame_info);
    }
    uint32_t frame_length = frame_info & 0x3fff;
    if (write_ptr - read_ptr < sizeof(frame_info) + frame_length) {
      // Frame only partially present; don't read it yet.
      break;
    }

    // Consume the frame metadata.
    read_ptr += sizeof(frame_info);
    read_ptr_masked = read_ptr & (ring_size - 1);

    // Form the pcap per-packet header.
    struct timespec ts;
    if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
      FATAL("Could not query time using clock_gettime");
    }
    uint32_t* pkt_hdr = writer->pkt_hdrs + iovcnt * 4;
    pkt_hdr[0] = ts.tv_sec;
    pkt_hdr[1] = ts.tv_nsec;
    pkt_hdr[2] = frame_length;
    pkt_hdr[3] = frame_length;

    // Usually require just one IOV for the header and one for the contents...
    struct iovec* iov = writer->iovs + iovcnt;
    iov[0].iov_base = pkt_hdr;
    iov[0].iov_len = sizeof(uint32_t) * 4;
    iov[1].iov_base = ring_contents + read_ptr_masked;
    iov[1].iov_len = frame_length;
    iovcnt += 2;
    read_ptr += frame_length;
    writer->total_pkt_count += 1;
    if (read_ptr_masked > ring_size - frame_length) {
      // ... but if it straddles a ring wrap, need one more.
      uint32_t avail = ring_size - read_ptr_masked;
      iov[1].iov_len = avail;
      iov[2].iov_base = ring_contents;
      iov[2].iov_len = frame_length - avail;
      ++iovcnt;
    }
  }
  writer->iovcnt = iovcnt;
  return read_ptr;
}

// Device configuration:

#define MILLISECONDS(x) ((x) * 1000000ull)

static uint64_t host_nanos64() {
  struct timespec ts;
  if (clock_gettime(CLOCK_REALTIME, &ts) != 0) {
    FATAL("Could not query time using clock_gettime");
  }
  return ts.tv_sec * MILLISECONDS(1000u) + ts.tv_nsec;
}

static void configure_rx_for_training(bh_pcie_device_t* device) {
  tlb_write_u32(device, RXCLASS_MAC_RX_ROUTING_ADDR, RXCLASS_MAC_RX_ROUTING_FROM_MAC);
  tlb_write_u32(device, RXCLASS_NO_MATCH_ACTIONS_ADDR, 0);
  tlb_write_u32(device, RXCLASS_USER_DEFINED_ETHERTYPE_ADDR(0), 0);
  tlb_write_u32(device, RXCLASS_USER_DEFINED_ETHERTYPE_ADDR(1), 0);
}

static void wait_for_ethernet_training_complete(bh_pcie_device_t* device, const uint8_t* new_loopback_mode) {
  volatile uint32_t* boot_results = (volatile uint32_t*)set_tlb_addr(device, ETH_BOOT_RESULTS_ADDR);
  uint32_t port_status = boot_results[1];
  if (port_status >= 3) {
    FATAL("Selected Ethernet tile does not have an Ethernet port (status %u); try a different one", (unsigned)port_status);
  }
  if (new_loopback_mode) {
    tlb_write_u32(device, SOFT_RESET_ADDR, SOFT_RESET_E0 | SOFT_RESET_E1); // Put both RISCVs into reset.
    configure_rx_for_training(device);
    tlb_write_u32(device, ETH_BOOT_PARAMS_ADDR + 8, *new_loopback_mode); // Set new loopback mode.
    tlb_write_u32(device, ETH_BOOT_RESULTS_ADDR + 4, (port_status = 0)); // Set port status to unknown.
    tlb_write_u32(device, SOFT_RESET_ADDR, SOFT_RESET_E1); // Take E0 out of reset, leave E1 in reset. Firmware on E0 should now start training.
    boot_results = (volatile uint32_t*)set_tlb_addr(device, ETH_BOOT_RESULTS_ADDR); // Need to reconfigure the TLB to point it back to this.
  }
  if (port_status == 0) {
    uint64_t start = host_nanos64();
    for (;;) {
      port_status = boot_results[1];
      if (port_status != 0) {
        break;
      } else if (host_nanos64() - start > MILLISECONDS(1000u)) {
        FATAL("Timed out waiting for Ethernet port training");
      }
    }
    if (port_status >= 3) {
      FATAL("Selected Ethernet tile has unknown port status %u after conclusion of training", (unsigned)port_status);
    }
  }
  if (port_status != 1) {
    FATAL("Selected Ethernet tile\'s port is down; try a different one");
  }
}

typedef struct h_ring_metadata_t {
  uint32_t write_ptr;
  uint32_t mailbox_echo;
  uint32_t error;
  uint32_t padding[13]; // To make the whole thing 64 bytes.
} h_ring_metadata_t;

typedef struct ethdump_context_t {
  pinned_host_buffer_t h_ring;
  pinned_host_buffer_t h_meta;
  uint32_t tx_ascii_counter_addr;
  uint32_t tx_doorbell;
  uint32_t e_ring_size;
} ethdump_context_t;

#define INITIAL_ECHO 1 // Must be odd, but otherwise arbitrary.

static void metadata_init(h_ring_metadata_t* meta) {
  meta->write_ptr = 0;
  meta->mailbox_echo = INITIAL_ECHO;
  meta->error = 0;
}

static void configure_ethernet(bh_pcie_device_t* device, ethdump_context_t* ctx) {
  // Take E0 out of reset, put E1 into reset.
  tlb_write_u32(device, SOFT_RESET_ADDR, SOFT_RESET_E1);

  // Choose device-side addresses.
  uint32_t meta_addr = ctx->e_ring_size;
  uint32_t code_addr = meta_addr + sizeof(h_ring_metadata_t);
  uint32_t tx_buf_addr = code_addr + sizeof(rv_code) + sizeof(rv_code_arguments_t);

  // Send initial metadata to the device.
  metadata_init((h_ring_metadata_t*)ctx->h_meta.host_ptr);
  memcpy(set_tlb_addr(device, meta_addr), ctx->h_meta.host_ptr, sizeof(h_ring_metadata_t));

  // Prepare a TX queue for traffic generation.
  {
    static const char pkt_contents[] = "Hello World 0000 from the " __FILE__ " dummy traffic generator, compiled at " __DATE__ " " __TIME__;
    memcpy(set_tlb_addr(device, tx_buf_addr), pkt_contents, sizeof(pkt_contents));
    ctx->tx_ascii_counter_addr = tx_buf_addr + 12;

    uint32_t txhdr_id = 9;
    uint32_t txhdr_addr = TXPKT_CFG_ADDR(txhdr_id);
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_INSERT_CTL_OFFSET, TXPKT_CFG_INSERT_CTL_L3_HEADER + TXPKT_CFG_INSERT_CTL_L4_HEADER + TXPKT_CFG_INSERT_CTL_L4_CHECKSUM);
    for (uint32_t i = TXPKT_CFG_MAC_SA_OFFSET; i < TXPKT_CFG_MAC_SA_OFFSET + 0x10; i += 4) {
      // Copy MAC addresses from header entry #0.
      tlb_write_u32(device, txhdr_addr + i, tlb_read_u32(device, TXPKT_CFG_ADDR(0) + i));
    }
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_USE_ETHERTYPE_OFFSET, 0x08000001); // Ethertype = 0x0800 (IPv4)
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_L3_HEADER_OFFSET +  0, 0x45000000); // IPv4 version, IHL, DSCP, ECN (also length, but this'll be overwritten)
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_L3_HEADER_OFFSET +  4, 0);          // IPv4 identification, flags, fragment offset
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_L3_HEADER_OFFSET +  8, 0x0A110000); // IPv4 TTL, protocol (also header checksum, but this'll be overwritten)
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_L3_HEADER_OFFSET + 12, 0x7F000001); // IPv4 source address
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_L3_HEADER_OFFSET + 16, 0x7F000002); // IPv4 destination address
    tlb_write_u32(device, txhdr_addr + TXPKT_CFG_L4_HEADER_OFFSET +  0, 0);          // UDP source port, destination port

    uint32_t txq_idx = 2;
    uint32_t txq_addr = TXQ_ADDR(txq_idx);
    tlb_write_u32(device, txq_addr + ETH_TXQ_TRANSFER_START_ADDR_OFFSET, tx_buf_addr);
    tlb_write_u32(device, txq_addr + ETH_TXQ_TRANSFER_SIZE_BYTES_OFFSET, sizeof(pkt_contents));
    tlb_write_u32(device, txq_addr + ETH_TXQ_TXPKT_CFG_SEL_SW_OFFSET, txhdr_id);
    ctx->tx_doorbell = txq_addr + ETH_TXQ_CMD_OFFSET;
  }

  // Configure NIU.
  uint32_t niu_addr = NIU_ADDR(1);
  tlb_write_u32(device, niu_addr + NOC_TARG_ADDR_MID_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_TARG_ADDR_HI_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_RET_ADDR_HI_OFFSET, BH_PCIE_XY);
  tlb_write_u32(device, niu_addr + NOC_PACKET_TAG_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_CTRL_OFFSET, NOC_CMD_WR | NOC_CMD_VC_STATIC);
  tlb_write_u32(device, niu_addr + NOC_AT_LEN_BE_1_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_BRCST_EXCLUDE_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_L1_ACC_AT_INSTRN_OFFSET, 0);
  tlb_write_u32(device, niu_addr + ROUTER_CFG_2_OFFSET, 0);
  tlb_write_u32(device, niu_addr + ROUTER_CFG_4_OFFSET, 0);
  niu_addr += 0x800;
  tlb_write_u32(device, niu_addr + NOC_TARG_ADDR_LO_OFFSET, meta_addr);
  tlb_write_u32(device, niu_addr + NOC_TARG_ADDR_MID_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_TARG_ADDR_HI_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_RET_ADDR_LO_OFFSET, (uint32_t)ctx->h_meta.noc_addr);
  tlb_write_u32(device, niu_addr + NOC_RET_ADDR_MID_OFFSET, (uint32_t)(ctx->h_meta.noc_addr >> 32));
  tlb_write_u32(device, niu_addr + NOC_RET_ADDR_HI_OFFSET, BH_PCIE_XY);
  tlb_write_u32(device, niu_addr + NOC_PACKET_TAG_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_CTRL_OFFSET, NOC_CMD_WR | NOC_CMD_VC_STATIC);
  tlb_write_u32(device, niu_addr + NOC_AT_LEN_BE_OFFSET, sizeof(h_ring_metadata_t));
  tlb_write_u32(device, niu_addr + NOC_AT_LEN_BE_1_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_BRCST_EXCLUDE_OFFSET, 0);
  tlb_write_u32(device, niu_addr + NOC_L1_ACC_AT_INSTRN_OFFSET, 0);

  // Stop TX queues from sending regular TT-link packets.
  for (uint32_t q = 0; q < 3; ++q) {
    uint32_t txq_addr = TXQ_ADDR(q);
    tlb_write_u32(device, txq_addr + ETH_TXQ_CTRL_OFFSET, 8u); // No regular heartbeats, ignore any received drop notifications.
    tlb_write_u32(device, txq_addr + ETH_TXQ_REMOTE_SEQ_TIMEOUT_OFFSET, ~0u); // Maximum resend timeout.
  }

  // Drop all incoming frames while we reconfigure things.
  tlb_write_u32(device, RXCLASS_OVERRIDE_DECISION_ADDR, RXCLASS_OVERRIDE_DECISION_DROP);

  // Configure RX queue.
  uint32_t rxq_idx = 2;
  uint32_t rxq_addr = RXQ_ADDR(rxq_idx);

  tlb_write_u32(device, rxq_addr + ETH_RXQ_CTRL_OFFSET, 0); // Raw RX mode, buffer not wrapping
  tlb_write_u32(device, rxq_addr + ETH_RXQ_BUF_START_WORD_ADDR_OFFSET, 0);
  tlb_write_u32(device, rxq_addr + ETH_RXQ_BUF_SIZE_WORDS_OFFSET, ctx->e_ring_size >> 4);
  tlb_write_u32(device, rxq_addr + ETH_RXQ_HDR_CTRL_OFFSET, 0); // Keep all headers
  tlb_write_u32(device, rxq_addr + ETH_RXQ_BUF_PTR_OFFSET, 0);

  // Configure RX classification engine.
  tlb_write_u32(device, RXCLASS_TCAM_FLUSH, 1); // Flush the TCAM, so that we don't need to care about header extraction nor most of the flow table.
  tlb_write_u32(device, RXCLASS_USER_DEFINED_ETHERTYPE_ADDR(0), 0xFFFF0800); // Rewrite IPv4 ethertype to something else, so that unsupported IPv4 headers aren't dropped.
  tlb_write_u32(device, RXCLASS_USER_DEFINED_ETHERTYPE_ADDR(1), 0xFFFF86DD); // Rewrite IPv6 ethertype to something else, so that unsupported IPv6 headers aren't dropped.
  tlb_write_u32(device, RXCLASS_MAC_RX_ROUTING_ADDR, RXCLASS_MAC_RX_ROUTING_FROM_ACTIONS);
  tlb_write_u32(device, RXCLASS_NO_MATCH_ACTIONS_ADDR, RXCLASS_NO_MATCH_ACTIONS_PREPEND_HW_METADATA + RXCLASS_NO_MATCH_ACTIONS_TO_RXQ(rxq_idx));

  // Deploy RV32 code to the device.
  uint32_t rv_payload[(sizeof(rv_code) + sizeof(rv_code_arguments_t))/sizeof(uint32_t)];
  memcpy((char*)rv_payload, rv_code, sizeof(rv_code));
#define fixup_shift(lbl, val) rv_payload[lbl/sizeof(uint32_t)] = rv_code[lbl/sizeof(uint32_t)] | ((val) << 20)
  fixup_shift(label_shift_fixup_0, 32 - __builtin_ctzl(ctx->e_ring_size));
  fixup_shift(label_shift_fixup_1, 32 - __builtin_ctzl(ctx->e_ring_size));
  fixup_shift(label_shift_fixup_2, __builtin_ctzl(ctx->e_ring_size) - 3);
#undef fixup_shift
  rv_code_arguments_t* rv_args = (rv_code_arguments_t*)((char*)rv_payload + sizeof(rv_code));
  rv_args->h_ring_noc_addr = ctx->h_ring.noc_addr;
  rv_args->h_ring_size = ctx->h_ring.size;
  rv_args->h_meta_addr = meta_addr;
  rv_args->e_ring_mask = ctx->e_ring_size - 1;
  rv_args->initial_drop_count = tlb_read_u32(device, rxq_addr + ETH_RXQ_PACKET_DROP_CNT_OFFSET);
  rv_args->rxq_addr = rxq_addr;
  rv_args->niu_addr = niu_addr;
  memcpy(set_tlb_addr(device, code_addr), rv_payload, sizeof(rv_payload));

  // Point E1 at the code we just deployed.
  tlb_write_u32(device, E1_RESET_PC_ADDR, code_addr);
  tlb_write_u32(device, E1_END_PC_ADDR, code_addr + sizeof(rv_code));

  {
    // Have tt-kmd put E1 back into reset if we abort. This requires a fairly
    // recent tt-kmd; older versions of tt-kmd will fail this with EINVAL.
    struct tenstorrent_set_noc_cleanup req;
    memset(&req, 0, sizeof(req));
    req.argsz = sizeof(req);
    req.enabled = true;
    req.x = (device->tlb_cfg[1] >> 11) & 0x3f;
    req.y = (device->tlb_cfg[1] >> 17) & 0x3f;
    req.addr = SOFT_RESET_ADDR;
    req.data = SOFT_RESET_E1;
    (void)ioctl(device->fd, TENSTORRENT_IOCTL_SET_NOC_CLEANUP, &req);
  }
  // Take E1 out of reset.
  tlb_write_u32(device, SOFT_RESET_ADDR, 0);

  // Start accepting incoming frames again.
  tlb_write_u32(device, RXCLASS_OVERRIDE_DECISION_ADDR, RXCLASS_OVERRIDE_DECISION_ACCEPT);
}

// Main host-side spin loop:

static uint32_t fmt_ascii_u4(uint32_t u) {
  char buf[4];
  buf[3] = '0' + (u % 10); u /= 10;
  buf[2] = '0' + (u % 10); u /= 10;
  buf[1] = '0' + (u % 10); u /= 10;
  buf[0] = '0' + u;
  memcpy(&u, buf, sizeof(buf));
  return u;
}

static volatile sig_atomic_t g_caught_sigint;
static void catch_sigint(int sig) {
  (void)sig;
  g_caught_sigint = 1;
}

static void host_spin(bh_pcie_device_t* device, pcap_writer_t* writer, ethdump_context_t* ctx, bool generate_traffic) {
  // This function will happily run forever, so wire up a SIGINT handler to allow it to be stopped.
  {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = catch_sigint;
    sa.sa_flags = SA_RESETHAND | SA_RESTART;
    g_caught_sigint = 0;
    sigaction(SIGINT, &sa, NULL);
  }

  volatile h_ring_metadata_t* meta = (volatile h_ring_metadata_t*)ctx->h_meta.host_ptr;
reentry:;
  uint64_t last_activity_at = host_nanos64();
  uint32_t write_ptr = 0;
  uint32_t last_echo = INITIAL_ECHO;
  uint32_t read_ptr = 0;
  uint32_t tx_gen_ctr = 0;
  while (!g_caught_sigint) {
    uint32_t new_write_ptr = meta->write_ptr;
    if (new_write_ptr != write_ptr) {
      // Device changed the ring write pointer; this is a clear
      // indication that the device is alive and ticking.
      write_ptr = new_write_ptr;
      last_activity_at = host_nanos64();
    }
    read_ptr = append_packets(writer, &ctx->h_ring, read_ptr, write_ptr);
    if (writer->iovcnt) {
      flush_packets(writer);
      tlb_write_u32(device, NIU_ADDR(1) + ROUTER_CFG_4_OFFSET, read_ptr); // Inform the device of our progress.
      continue;
    }
    uint32_t new_echo = meta->mailbox_echo;
    if ((last_echo - new_echo) & 0x80000000) {
      // Device advanced the mailbox_echo value; this is a clear
      // indication that the device is alive and ticking.
      last_echo = new_echo;
      last_activity_at = host_nanos64();
      continue;
    }
    uint64_t new_time = host_nanos64();
    if ((new_time - last_activity_at) >= MILLISECONDS(10u)) {
      // Haven't seen any activity from the device in a while; this could be
      // because there is no traffic, or it could be because of a problem.
      if (meta->error != 0) {
        fprintf(stderr, "WARNING: Dropped packets; resetting queues and starting again...\n");
        configure_ethernet(device, ctx);
        goto reentry;
      }
      if (generate_traffic) {
        // If we're willing to generate traffic, transmit one packet now.
        tx_gen_ctr = (tx_gen_ctr == 9999) ? 0 : tx_gen_ctr + 1;
        tlb_write_u32(device, ctx->tx_ascii_counter_addr, fmt_ascii_u4(tx_gen_ctr));
        tlb_write_u32(device, ctx->tx_doorbell, 1);
      }
      if (last_echo & 1) {
        // Request that the device write to mailbox_echo, to prove liveness.
        ++last_echo; // Is now even, so we won't take this branch again.
        last_activity_at = new_time; // Bump this to give the device time to respond.
        tlb_write_u32(device, NIU_ADDR(1) + ROUTER_CFG_2_OFFSET, last_echo + 1);
      } else {
        FATAL("Timed out waiting for echo from device");
      }
    }
  }
}

// Command line parsing:

#define PRINT_HW_INFO     0x01
#define PRINT_TX_HEADERS  0x02

typedef struct ethdump_args_t {
  const char* device;
  const char* output;
  uint32_t device_ring_size;
  uint32_t host_ring_size;
  uint8_t ethernet_x;
  uint8_t loopback_mode;
  bool apply_loopback_mode;
  uint8_t to_print;
  bool generate_traffic;
} ethdump_args_t;

typedef struct cmdline_def_t {
  const char* syntax;
  uintptr_t (*fn)(ethdump_args_t*, uintptr_t);
  uintptr_t (*parse_arg)(const char* src);
} cmdline_def_t;

static uintptr_t parse_str(const char* str) {
  return (uintptr_t)str;
}

static uintptr_t parse_byte_size(const char* str) {
  uint32_t out = 0;
  unsigned num_digits = 0;
  for (;;) {
    char c = *str++;
    if ('0' <= c && c <= '9') {
      out = out * 10 + (c - '0');
      num_digits |= 1;
      if (out == 0) continue;
      num_digits += 2;
      if (num_digits < 20) continue;
    } else if (c == '\0') {
      if (num_digits) return out;
    } else if (c == ' ' || (c == '+' && out == 0)) {
      continue;
    } else if (c == 'K' || c == 'M' || c == 'G' || c == 'k' || c == 'm' || c == 'g') {
      if (*str == 'i' && str[1] != '\0') ++str;
      if (*str == 'b' || *str == 'B') ++str;
      if (*str == '\0') {
        if ((c == 'K' || c == 'k') && num_digits && out <= (UINT32_MAX >> 10)) return out << 10;
        if ((c == 'M' || c == 'm') && num_digits && out <= (UINT32_MAX >> 20)) return out << 20;
        if ((c == 'G' || c == 'g') && num_digits && out <= (UINT32_MAX >> 30)) return out << 30;
      }
    } else if (c == '<' && *str == '<') {
      uintptr_t shift = parse_small_int(str + 1);
      if (shift <= 31 && out <= (UINT32_MAX >> shift)) return out << shift;
    }
    return INVALID_PARSE;
  }
}

static uintptr_t action_set_device_ring_size(ethdump_args_t* args, uintptr_t parsed) {
  if (parsed >= 4096 && parsed <= (256 * 1024) && !(parsed & (parsed - 1))) {
    args->device_ring_size = (uint32_t)parsed;
    return parsed;
  } else {
    return INVALID_PARSE;
  }
}

static uintptr_t action_set_device_path(ethdump_args_t* args, uintptr_t parsed) {
  args->device = (const char*)parsed;
  return parsed;
}

static uintptr_t action_set_ethernet_x(ethdump_args_t* args, uintptr_t x) {
  if ((1 <= x && x <= 7) || (10 <= x && x <= 16) || (20 <= x && x <= 31)) {
    args->ethernet_x = (uint8_t)x;
    return x;
  } else {
    return INVALID_PARSE;
  }
}

static uintptr_t action_generate_traffic(ethdump_args_t* args, uintptr_t parsed) {
  args->generate_traffic = true;
  return parsed;
}

static uintptr_t action_set_host_ring_size(ethdump_args_t* args, uintptr_t parsed) {
  if (parsed >= 4096 && parsed <= (2u << 30) && !(parsed & (parsed - 1))) {
    args->host_ring_size = (uint32_t)parsed;
    return parsed;
  } else {
    return INVALID_PARSE;
  }
}

static uintptr_t action_print_hwinfo(ethdump_args_t* args, uintptr_t parsed) {
  args->to_print |= PRINT_HW_INFO;
  return parsed;
}

static uintptr_t action_print_txheaders(ethdump_args_t* args, uintptr_t parsed) {
  args->to_print |= PRINT_TX_HEADERS;
  return parsed;
}

static uintptr_t action_set_loopback_mode(ethdump_args_t* args, uintptr_t x) {
  if (x == (uint8_t)x) {
    args->loopback_mode = (uint8_t)x;
    args->apply_loopback_mode = true;
    return x;
  } else {
    return INVALID_PARSE;
  }
}

static uintptr_t action_set_output_path(ethdump_args_t* args, uintptr_t parsed) {
  args->output = (const char*)parsed;
  return parsed;
}

static int cmdline_def_cmp(const void* key, const void* def) {
  return strcmp((const char*)key, ((cmdline_def_t*)def)->syntax);
}

static const cmdline_def_t g_cmdline_actions[] = {
  {"--device",           action_set_device_path,      parse_str},
  {"--device-ring-size", action_set_device_ring_size, parse_byte_size},
  {"--eth-x",            action_set_ethernet_x,       parse_small_int},
  {"--ethernet-x",       action_set_ethernet_x,       parse_small_int},
  {"--generate-traffic", action_generate_traffic,     NULL},
  {"--host-ring-size",   action_set_host_ring_size,   parse_byte_size},
  {"--hwinfo",           action_print_hwinfo,         NULL},
  {"--loopback",         action_set_loopback_mode,    parse_small_int},
  {"--loopback-mode",    action_set_loopback_mode,    parse_small_int},
  {"--out",              action_set_output_path,      parse_str},
  {"--output",           action_set_output_path,      parse_str},
  {"--txheaders",        action_print_txheaders,      NULL},
};

static void parse_args(ethdump_args_t* args, int argc, const char** argv) {
  char arg_buf[25];
  arg_buf[0] = '-';
  for (int i = 1; i < argc; ++i) {
    const char* arg = argv[i];
    if (arg[0] != '-' || arg[1] == '\0') goto err_bad_flag;
    char* a_out = arg_buf + 1;
    for (++arg;;) {
      char c = *arg++;
      if (c == '\0') {
        arg = NULL;
        *a_out = '\0';
        break;
      } else if (c == '=') {
        *a_out = '\0';
        break;
      } else if (c == '_') {
        c = '-';
      } else if ('A' <= c && c <= 'Z') {
        c = (c - 'A') + 'a';
      }
      *a_out++ = c;
      if (a_out == arg_buf + sizeof(arg_buf)) {
      err_bad_flag:
        FATAL("Unexpected '%s' on command line", argv[i]);
      }
    }
    cmdline_def_t* d = bsearch(arg_buf, g_cmdline_actions, sizeof(g_cmdline_actions) / sizeof(*g_cmdline_actions), sizeof(*g_cmdline_actions), cmdline_def_cmp);
    if (!d) goto err_bad_flag;
    uintptr_t parsed = 0;
    if (d->parse_arg) {
      if (arg) parsed = d->parse_arg(arg);
      else if (++i < argc) parsed = d->parse_arg((arg = argv[i]));
      else FATAL("Expected a value after %s", arg_buf);
    } else if (arg) {
      FATAL("Value '%s' was provided for %s, but it does not expect a value", arg, arg_buf);
    }
    parsed = d->fn(args, parsed);
    if (parsed == INVALID_PARSE) {
      FATAL("Invalid value '%s' provided for %s", arg, arg_buf);
    }
  }
  if (args->host_ring_size < args->device_ring_size) {
    FATAL("Host ring size (%u bytes) cannot be smaller than device ring size (%u bytes)",
      (unsigned)args->host_ring_size, (unsigned)args->device_ring_size);
  }
}

// Entry point:

int main(int argc, const char** argv) {
  ethdump_args_t args;
  memset(&args, 0, sizeof(args));
  args.ethernet_x = 25;
  args.device_ring_size = 256 << 10;
  args.host_ring_size = 2 << 20;
  parse_args(&args, argc, argv);
  bool capturing_traffic = !args.to_print || args.output || args.generate_traffic;

  bh_pcie_device_t* device = open_bh_pcie_device(args.device);
  if (args.to_print & PRINT_HW_INFO) {
    print_hwinfo(device);
  }
  if (capturing_traffic || args.apply_loopback_mode) {
    set_ethernet_x(device, args.ethernet_x);
    wait_for_ethernet_training_complete(device, args.apply_loopback_mode ? &args.loopback_mode : NULL);
  }
  if (args.to_print & PRINT_TX_HEADERS) {
    set_ethernet_x(device, args.ethernet_x);
    print_tx_headers(device);
  }
  if (capturing_traffic) {
    char output_filename_buf[12];
    if (!args.output) {
      sprintf(output_filename_buf, "tt_%u.pcap", (unsigned)args.ethernet_x);
      args.output = output_filename_buf;
    }
    ethdump_context_t ctx;
    ctx.e_ring_size = args.device_ring_size;
    ctx.h_ring.size = args.host_ring_size;
    ctx.h_meta.size = device->host_page_size;
    allocate_host_buffer(device, &ctx.h_ring);
    allocate_host_buffer(device, &ctx.h_meta);
    pcap_writer_t writer;
    pcap_writer_init(&writer, args.output);
    configure_ethernet(device, &ctx);
    host_spin(device, &writer, &ctx, args.generate_traffic);
    tlb_write_u32(device, SOFT_RESET_ADDR, SOFT_RESET_E1);
    close(writer.fd);
    printf("Captured %llu packets, wrote %llu bytes to %s\n",
      (long long unsigned)writer.total_pkt_count,
      (long long unsigned)writer.total_byte_count, args.output);
  }
  close_bh_pcie_device(device);
  return 0;
}
