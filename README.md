# DaynaPORT SCSI/Link driver for OpenVMS VAX

This repository contains an original OpenVMS VAX driver for the DaynaPORT
SCSI/Link Ethernet protocol implemented by ZuluSCSI. The loadable image
presents the adapter as `XQA0:`; TCP/IP Services sees the corresponding
Ethernet interface as `QE0`.

The current version is V0.61. It is experimental system software: it has been
built and exercised on real hardware, including DHCP, ICMP, and bidirectional
FTP, but it has not been qualified for production use.

## Authorship

The driver and the supporting code in this repository were written entirely
by OpenAI Codex in collaboration with the repository owner. The owner defined
the goal and constraints, provided and operated the hardware, participated in
architecture decisions, supplied observations from the physical consoles and
packet captures, and performed hands-on parts of the live test program.

## Development environment

The implementation was developed and tested in this environment:

- DEC VAXstation 4000 Model 90 with 128 MB RAM;
- OpenVMS VAX V7.3;
- the VAX MACRO assembler, linker, system symbol table, and macro libraries
  shipped with that OpenVMS installation;
- Compaq C V6.4-005 for the support programs;
- TCP/IP Services for OpenVMS V5.1;
- NCR 53C94 SCSI controller exposed by OpenVMS as `PKA0:`;
- ZuluSCSI firmware presenting `Dayna / SCSI/Link / 2.0f` at SCSI ID 4,
  LUN 0;
- an isolated 2.4 GHz WLAN with DHCP for end-to-end Ethernet and IPv4 tests;
- a separate management network, serial console, and a Linux development host
  used for editing and release preparation.

The VAX was also a member of a mixed OpenVMS Cluster during part of the test
program. Cluster membership is not required by the driver.

## Hardware setup

For ZuluSCSI, create an empty marker file named `NE4.img` in the root of the
SD card. It creates a DaynaPORT target at SCSI ID 4. The Wi-Fi SSID and
password are configured using the normal ZuluSCSI network settings.

On the tested VAXstation, target 4, LUN 0 maps to `GKA400:` under the generic
SCSI class driver and to `XQA0:` under this driver. Do not use SCSI ID 6 on a
VAXstation 4000-90: it is reserved for the integral SCSI initiator.

Use exactly one terminator at the physical end of the SCSI bus. Do not enable
the ZuluSCSI terminator when an external terminator is already fitted.

## Repository layout

- `driver/DPDRIVER.MAR` — the loadable VAX driver.
- `driver/DYDRIVER_VCI_PREFIX.MAR` — enables the XQA/QE identity and VCI
  frontend used by TCP/IP Services.
- `src/dp_mac_init.c` — performs the deferred MAC initialization
  required before publishing the interface.
- `src/dp_vci_control.c` — privileged utility that installs or removes the
  VCI callback wrappers.
- `VMS_BUILD.COM` — builds the driver and both runtime utilities.
- `VMS_DAYNAPORT_STARTUP.COM` — establishes the required boot order.
- `docs/architecture.md` — driver architecture and ownership model.
- `docs/build-and-install.md` — complete build, install, SYSGEN, TCP/IP, and
  rollback procedure.
- `docs/protocol.md` — DaynaPORT command and packet framing reference.

## Prerequisites

The build must run on OpenVMS VAX V7.3 with these installed components:

- VAX MACRO and LINK;
- `SYS$LIBRARY:LIB.MLB`;
- `SYS$LIBRARY:LANUDEF.MLB`;
- `SYS$SYSTEM:SYS.STB`;
- a VAX C or Compaq C compiler compatible with `/STANDARD=VAXC`.

No separately generated files are required. The repository contains every
project source file and command procedure used by the release build.

## Build

Copy the repository tree to an ODS-2 disk, preserve the directory structure,
set default to the repository root, and run:

```text
$ @VMS_BUILD.COM
```

The procedure produces:

```text
DYDRIVER.EXE
DP_MAC_INIT.EXE
DP_VCI_CONTROL.EXE
```

It also runs `ANALYZE/IMAGE` on the loadable image. It does not install,
load, connect, or execute any of the results.

## SYSGEN parameter

The driver uses the site-reserved static SYSGEN longword `USER4` to select the
target receive-buffer pool size. OpenVMS does not provide a supported way for
a third-party loadable driver to register a new named SYSGEN parameter, so a
site-reserved parameter is used deliberately.

`USER4` is global to the node. Before assigning it to DYDRIVER, verify that
no other local component uses it.

The accepted values are:

| `USER4` value | Result |
| ---: | --- |
| `0` | Use the compiled default of 32 receive VCRPs |
| `8` through `128` | Request exactly that many receive VCRPs |
| Any other value | Use the compiled default of 32 |

The value is read once during controller initialization. It cannot resize a
live pool. If allocation fails after at least one VCRP has been created, the
driver continues with the actual partial pool; failure to allocate even one
VCRP prevents port creation with `SS$_INSFMEM`.

To inspect and persist the setting:

```text
$ MCR SYSGEN
SYSGEN> SHOW USER4
SYSGEN> USE CURRENT
SYSGEN> SET USER4 32
SYSGEN> WRITE CURRENT
SYSGEN> EXIT
```

Set `USER4` to zero to retain the driver's default-selection behavior. A
persisted change takes effect on the next driver initialization, normally the
next boot. Do not use `WRITE ACTIVE` as a live-resize mechanism.

The tested default of 32 eliminated observed receive-pool exhaustion. The
recorded high-water mark was 11 buffers. Increasing the value above 32 is not
currently supported by test evidence, even though values through 128 are
guarded and accepted.

## Installation overview

Installation modifies privileged system state and should be performed from a
fully privileged SYSTEM account with a known-good system disk backup and a
console available.

At a high level:

1. Build the three images with `@VMS_BUILD.COM`.
2. Copy `DYDRIVER.EXE` to `SYS$LOADABLE_IMAGES:`.
3. Copy the startup procedure and its two support images to one directory,
   normally `SYS$MANAGER:`.
4. Configure `QE0` in TCP/IP Services, using DHCP or a static address suitable
   for the DaynaPORT network.
5. Invoke the DaynaPORT startup procedure before `TCPIP$STARTUP` during boot.
6. Reboot from the console and verify `XQA0`, `QE0`, the MAC address, and
   network operation.

The exact commands, checks, failure behavior, and rollback sequence are in
[docs/build-and-install.md](docs/build-and-install.md). Read that document
before copying the driver into `SYS$LOADABLE_IMAGES:`.

## Runtime sequence

`VMS_DAYNAPORT_STARTUP.COM` performs this order:

1. connect `XQA0:` to `DYDRIVER` if it is absent;
2. issue one harmless driver request that reads and caches the adapter MAC;
3. install the VCI wrapper set through a privileged, fail-closed control QIO;
4. return so normal `TCPIP$STARTUP` can create and activate `QE0`;
5. if TCP/IP is already running, activate a missing `QE0` using DHCP.

The procedure does not modify persistent TCP/IP configuration, remove an
interface, remove a VCI hook, or shut down another network device.

## Current status and limitations

V0.61 has passed native assembly/link/image analysis and repeated clean boot
tests on the stated VAXstation. The tested path has completed:

- automatic XQA0 connection and VCI publication;
- DHCP configuration of QE0;
- bidirectional ARP and ICMP, including full-size Ethernet frames;
- repeated bidirectional FTP transfers;
- receive-pool accounting with equal delivery and return totals;
- zero receive-pool exhaustion with the 32-buffer default;
- zero QE0 send and receive errors during the final bounded workload.

Known limitations:

- only OpenVMS VAX V7.3 on the stated platform has been validated;
- the VCI hook is an installation-time mechanism, not a hot-plug API;
- removal is permitted only after all LAN clients and owned requests have
  stopped and drained;
- one controller command is active at a time, by design;
- receive polling is timer paced and optimized for correctness rather than
  minimum latency;
- significant TCP receive-side reordering was still observed under load;
- a ZuluSCSI write-completion timeout was observed near one load test, but its
  causal relationship to the ordering symptom has not been established.

See [docs/architecture.md](docs/architecture.md) for the detailed data flow,
synchronization model, buffer ownership, and failure rules.

## License

This project is licensed under the [MIT License](LICENSE).
