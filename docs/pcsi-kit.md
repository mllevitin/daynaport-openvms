# Native PCSI distribution

`VMS_BUILD_PCSI.COM` creates a full sequential PCSI kit for OpenVMS VAX V7.3.
The kit carries the prebuilt driver and its runtime control utility, so a target
system does not need MACRO-32, a C compiler, or a linker.

## Build inputs

Build the two images from the repository root on OpenVMS VAX:

```text
$ @VMS_BUILD.COM
```

The procedure produces `DYDRIVER.EXE` and `DP_VCI_CONTROL.EXE` without
installing or running them. Package those exact
images with the product description, product text, startup procedure, IVP,
installation guide, and license:

```text
$ @VMS_BUILD_PCSI.COM
```

The result is a `CHATGPT56-VAXVMS-DAYNAPORT-*.PCSI` sequential kit in the
repository root.  PCSI records file identity, size, and installation metadata
while packaging it.

For V0.68 the verified artifact is
`dist/CHATGPT56-VAXVMS-DAYNAPORT-V0068--1.PCSI`, 40960 bytes, with SHA-256
`d293dd3cdfe69e7c5d399b1dbab318d662ebf6a8cc6141297602af6b55e55b52`.

## Installed components

| Component | Destination | Purpose |
| --- | --- | --- |
| `DYDRIVER.EXE` | `SYS$LOADABLE_IMAGES:` | VAX loadable LAN port driver |
| `DP_VCI_CONTROL.EXE` | `SYS$STARTUP:` | Caches the MAC and installs the driver's VCI callback wrappers |
| `DAYNAPORT$STARTUP.COM` | `SYS$STARTUP:` | Connects XQA0 before TCP/IP startup |
| `DAYNAPORT$IVP.COM` | `SYS$TEST:` | Performs non-loading file/image validation |
| `DAYNAPORT$INSTALL.TXT` | `SYS$HELP:` | Administrator installation and rollback guide |
| `DAYNAPORT$LICENSE.TXT` | `SYS$HELP:` | MIT License |

## Installation boundary

The kit intentionally performs no live driver transition.  Installation does
not connect XQA0, publish VCI hooks, edit `SYSTARTUP_VMS.COM`, configure QE0,
or change SYSGEN `USER4`. The PCSI IVP only verifies installed files and runs
`ANALYZE/IMAGE` on the two executable images.

This separation keeps installation repeatable and leaves the first kernel
load, TCP/IP configuration, and boot recovery plan under administrator
control.  Exact post-installation steps are in `DAYNAPORT$INSTALL.TXT`.

## V0.68 verification gate

The V0.68 kit was built and installed on the development OpenVMS VAX V7.3
system as an upgrade from V0.62. The automatic IVP and a separate manual IVP
both passed. After an orderly reboot with shutdown option `NONE`, the kit
image connected XQA0 and brought DHCP-configured QE0 online with zero device
errors.
