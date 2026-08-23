# Build and installation

## Read this first

DYDRIVER executes in the OpenVMS kernel and uses nonpaged pool, the SCSI Port
Interface, timer and fork services, and the LAN VCI callback table. A defect
can stop the node. Perform first installation from the physical or serial
console, keep a bootable backup system disk, and know how to perform a
conversational minimum boot.

The commands in this document assume a fully privileged SYSTEM account.

## Required files

The release build needs these project files:

```text
driver/DPDRIVER.MAR
driver/DYDRIVER_VCI_PREFIX.MAR
src/dp_mac_init.c
src/dp_vci_control.c
VMS_BUILD.COM
VMS_DAYNAPORT_STARTUP.COM
```

## OpenVMS prerequisites

The validated build environment is OpenVMS VAX V7.3 with:

- VAX MACRO;
- LINK and ANALYZE/IMAGE;
- `SYS$LIBRARY:LIB.MLB`;
- `SYS$LIBRARY:LANUDEF.MLB`;
- `SYS$SYSTEM:SYS.STB`;
- Compaq C V6.4-005 or a compatible VAX C compiler.

The build refers only to symbols and macros installed on the target system and
to files in this repository.

## Native build

Copy the complete tree to an ODS-2 disk and set default to its root:

```text
$ SET DEFAULT device:[directory]
$ @VMS_BUILD.COM
```

`VMS_BUILD.COM` stops at the first failure. On success it produces:

```text
DYDRIVER.EXE
DP_MAC_INIT.EXE
DP_VCI_CONTROL.EXE
```

The build procedure assembles
`DYDRIVER_VCI_PREFIX.MAR+DPDRIVER.MAR`, links the result against
`SYS$SYSTEM:SYS.STB`, and analyzes the image. The output filename and the
internal image name are both `DYDRIVER`, which is required for installation
as `SYS$LOADABLE_IMAGES:DYDRIVER.EXE`.

The procedure does not copy, install, load, connect, or run any image.

Before installation, require the build procedure to return success and
confirm:

```text
$ ANALYZE/IMAGE DYDRIVER.EXE
```

reports no image error.

## USER4 configuration

DYDRIVER reads `SGN$GL_USER4` once when the controller is initialized.
`USER4` controls the desired number of receive VCRPs:

- `0` selects the default 32;
- `8` through `128` select the exact desired count;
- every other value selects 32.

This is the only SYSGEN site parameter used by the driver.

`USER4` is a node-global site parameter. Do not assign it to DYDRIVER until
you have confirmed that no other locally installed component uses it.

Inspect the current and persisted values:

```text
$ MCR SYSGEN
SYSGEN> SHOW USER4
SYSGEN> USE CURRENT
SYSGEN> SHOW USER4
SYSGEN> EXIT
```

To request 32 explicitly:

```text
$ MCR SYSGEN
SYSGEN> USE CURRENT
SYSGEN> SET USER4 32
SYSGEN> WRITE CURRENT
SYSGEN> EXIT
```

To use the compiled default-selection rule:

```text
$ MCR SYSGEN
SYSGEN> USE CURRENT
SYSGEN> SET USER4 0
SYSGEN> WRITE CURRENT
SYSGEN> EXIT
```

The parameter is static for DYDRIVER. Do not use `WRITE ACTIVE` in an attempt
to resize a connected interface. Reinitialize the driver, normally by an
orderly reboot, after changing the persisted value.

If the requested pool cannot be allocated in full, the driver accepts a
partial pool only when at least one VCRP exists. The LDC current count records
the actual allocation. Failure before the first VCRP returns
`SS$_INSFMEM`.

## Stage files

Preserve the previous `DYDRIVER.EXE` version for rollback. Then copy the new
image:

```text
$ COPY DYDRIVER.EXE SYS$LOADABLE_IMAGES:DYDRIVER.EXE
$ ANALYZE/IMAGE SYS$LOADABLE_IMAGES:DYDRIVER.EXE
```

Keep the startup procedure and both support images in the same directory,
normally `SYS$MANAGER:`:

```text
$ COPY DP_MAC_INIT.EXE SYS$MANAGER:
$ COPY DP_VCI_CONTROL.EXE SYS$MANAGER:
$ COPY VMS_DAYNAPORT_STARTUP.COM SYS$MANAGER:DAYNAPORT_STARTUP.COM
```

The startup procedure locates the two support images beside itself.

## Configure TCP/IP Services

TCP/IP Services maps `XQA0:` to `QE0`. Configure `QE0` for the network
used by the ZuluSCSI adapter.

For DHCP on TCP/IP Services V5.1, first make sure the DHCP client component is
enabled:

```text
$ @SYS$MANAGER:TCPIP$CONFIG DHCP_CLIENT ENABLE
```

Create the persistent QE0 definition using the TCP/IP configuration utility
appropriate to the installed stack. On the validated V5.1 system the
persistent command is:

```text
$ TCPIP SET CONFIGURATION INTERFACE QE0 /DHCP
```

For a static configuration, use a unique address and mask for the physical
network attached to ZuluSCSI. Do not add a second default route unless that is
an intentional part of the host routing design.

`DAYNAPORT_STARTUP.COM` does not create or alter persistent TCP/IP records.
It consumes the configuration already stored for QE0.

## Boot order

DYDRIVER must connect, cache its MAC, and publish the VCI wrappers before
TCP/IP Services enumerates Ethernet controllers.

In `SYS$MANAGER:SYSTARTUP_VMS.COM`, place:

```text
$ @SYS$MANAGER:DAYNAPORT_STARTUP.COM
$ @SYS$STARTUP:TCPIP$STARTUP.COM
```

If the site already starts TCP/IP from another command procedure, insert the
DaynaPORT call immediately before that existing call rather than starting
TCP/IP twice.

Do not connect the same DaynaPORT target concurrently under GKDRIVER. At boot,
DYDRIVER must be the sole class-driver owner of target 4, LUN 0.

## What the startup procedure does

`DAYNAPORT_STARTUP.COM`:

1. verifies that `SYS$LOADABLE_IMAGES:DYDRIVER.EXE` and both support images
   exist;
2. runs `SYSGEN CONNECT XQA0:/NOADAPTER/DRIVER=DYDRIVER` if XQA0 is absent;
3. runs `DP_MAC_INIT XQA0:` to cache the hardware address while
   the interface is disabled;
4. runs `DP_VCI_CONTROL INSTALL XQA0:` to publish the guarded wrapper set;
5. returns for normal `TCPIP$STARTUP`;
6. if TCP/IP is already running, starts an absent QE0 with DHCP.

Every failure stops the procedure and returns an error. It does not disconnect
a driver, remove another node, alter cluster membership, or change persistent
TCP/IP state.

## First boot

Use an orderly shutdown and select shutdown option `NONE`. Boot with the
serial or physical console attached.

Expected startup messages include:

```text
Connecting XQA0 to DYDRIVER ...
Priming the DaynaPORT hardware address ...
Installing the VCI discovery hook ...
DaynaPORT is prepared; TCPIP$STARTUP will activate persistent QE0/DHCP.
```

After login, verify:

```text
$ SHOW DEVICE XQA0 /FULL
$ TCPIP SHOW INTERFACE QE0 /FULL
$ TCPIP SHOW ROUTE
```

The QE0 physical address must match the DaynaPORT MAC. Under DHCP, wait for the
lease before treating a zero address as a driver failure.

Perform bounded checks in this order:

1. ARP or a short ping to a host on the directly attached network;
2. repeated short ICMP;
3. ICMP near the Ethernet MTU;
4. a small TCP transfer;
5. only then a larger bidirectional workload.

Watch device error counters, TCP retransmission behavior, and ZuluSCSI console
messages during the first tests.

## Manual preparation without reboot

The startup procedure can be run interactively before TCP/IP is active:

```text
$ @SYS$MANAGER:DAYNAPORT_STARTUP.COM
```

If TCP/IP is already active, the procedure can prepare XQA0 and request DHCP
activation for a missing QE0. This path is useful for bounded development
tests, but the validated unattended configuration uses the boot order above.

Do not issue `DP_VCI_CONTROL REMOVE` while QE0 or another LAN client is
active. A rejected removal is a safety result, not a condition to bypass.

## Rollback

OpenVMS file versioning normally leaves the prior driver image available.
Before the first boot, record which version is known good.

If the new image fails after OpenVMS starts far enough to reach DCL:

1. stop normal startup before TCP/IP owns QE0;
2. copy the known-good DYDRIVER image as the newest
   `SYS$LOADABLE_IMAGES:DYDRIVER.EXE` version;
3. verify it with `ANALYZE/IMAGE`;
4. ensure temporary minimum-boot parameters are cleared;
5. reboot orderly with shutdown option `NONE`.

If normal startup cannot reach DCL, use a conversational boot and set
`STARTUP_P1` to `MIN` for one recovery boot. Restore the known-good image,
then explicitly return `STARTUP_P1` to the site's normal value and write the
CURRENT parameter set before rebooting.

Do not purge the known-good image until the new driver has passed repeated
cold and warm boot tests.

## Uninstallation

The safe persistent removal is:

1. remove or comment the DaynaPORT call in `SYSTARTUP_VMS.COM`;
2. remove the persistent QE0 TCP/IP definition if it is no longer wanted;
3. reboot orderly so no client owns the VCI wrappers;
4. archive or remove the staged DYDRIVER and support images only after the
   node is running on its normal network configuration.

Runtime hook removal is intended for controlled development only. It requires
all ports, timers, requests, and returned buffers to be fully drained and will
otherwise fail with `SS$_DEVACTIVE`.
