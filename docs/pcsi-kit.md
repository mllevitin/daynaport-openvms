# Native PCSI distribution

`VMS_BUILD_PCSI.COM` creates a full sequential PCSI kit for OpenVMS VAX V7.3.
The kit carries the prebuilt driver and its two runtime utilities, so a target
system does not need MACRO-32, a C compiler, or a linker.

## Build inputs

Build the three images from the repository root on OpenVMS VAX:

```text
$ @VMS_BUILD.COM
```

The procedure produces `DYDRIVER.EXE`, `DP_MAC_INIT.EXE`, and
`DP_VCI_CONTROL.EXE` without installing or running them.  Package those exact
images with the product description, product text, startup procedure, IVP,
installation guide, and license:

```text
$ @VMS_BUILD_PCSI.COM
```

The result is a `CHATGPT56-VAXVMS-DAYNAPORT-*.PCSI` sequential kit in the
repository root.  PCSI records file identity, size, and installation metadata
while packaging it.

For V0.62 the verified artifact is
`dist/CHATGPT56-VAXVMS-DAYNAPORT-V0062--1.PCSI`, 40960 bytes, with SHA-256
`dc6ba7c8d6df9c7df6f55b013c3d58d17544bcb95d812747c7716742515cc503`.

## Installed components

| Component | Destination | Purpose |
| --- | --- | --- |
| `DYDRIVER.EXE` | `SYS$LOADABLE_IMAGES:` | VAX loadable LAN port driver |
| `DP_MAC_INIT.EXE` | `SYS$STARTUP:` | Caches the DaynaPORT MAC before VCI discovery |
| `DP_VCI_CONTROL.EXE` | `SYS$STARTUP:` | Installs the driver's VCI callback wrappers |
| `DAYNAPORT$STARTUP.COM` | `SYS$STARTUP:` | Connects XQA0 before TCP/IP startup |
| `DAYNAPORT$IVP.COM` | `SYS$TEST:` | Performs non-loading file/image validation |
| `DAYNAPORT$INSTALL.TXT` | `SYS$HELP:` | Administrator installation and rollback guide |
| `DAYNAPORT$LICENSE.TXT` | `SYS$HELP:` | MIT License |

## Installation boundary

The kit intentionally performs no live driver transition.  Installation does
not connect XQA0, publish VCI hooks, edit `SYSTARTUP_VMS.COM`, configure QE0,
or change SYSGEN `USER4`.  The PCSI IVP only verifies installed files and runs
`ANALYZE/IMAGE` on the three executable images.

This separation keeps installation repeatable and leaves the first kernel
load, TCP/IP configuration, and boot recovery plan under administrator
control.  Exact post-installation steps are in `DAYNAPORT$INSTALL.TXT`.

## V0.62 upgrade gate

On the development OpenVMS VAX V7.3 system, PCSI V7.3-100 upgraded the
registered full product from V0.61 to V0.62.  The automatic IVP and a separate
manual IVP both passed.  The installed common `DYDRIVER.EXE` identified as
V0.62 and all three images reported zero analysis errors.

The upgrade did not load the new driver or disturb the resident node-specific
V0.61 image.  XQA0 remained online with zero device errors and QE0 retained
its DHCP address.  A future administrator-controlled reboot is required to
make an installed V0.62 image resident on a configured target node.
