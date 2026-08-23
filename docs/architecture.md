# Driver architecture

## Scope

DYDRIVER is a self-contained OpenVMS VAX SCSI class driver with an Ethernet
frontend. It connects to a DaynaPORT-compatible ZuluSCSI target through the
OpenVMS SCSI Port Interface and publishes an XQA-compatible device to the
OpenVMS LAN virtual-circuit interface (VCI).

The implementation does not emulate DELQA registers. The XQA identity exists
only so the operating system and TCP/IP Services use the established XQ/QE
device naming convention. Ethernet frames are transported by DaynaPORT SCSI
commands.

## Build composition

`driver/DPDRIVER.MAR` contains the complete implementation.
`driver/DYDRIVER_VCI_PREFIX.MAR` enables the XQA/QE identity and the VCI
frontend required by TCP/IP Services. The two modules are assembled together
and linked as `DYDRIVER.EXE`.

## Major objects

### Template UCB

`XQA0:` is an online template UCB. It holds the physical controller
connection and points at one shared DPCB. It is not itself a protocol port.
The generic OpenVMS cloned-UCB mechanism creates a separate UCB for each LAN
protocol port requested through the VCI frontend.

### Cloned port UCB

Each cloned UCB contains port-local state:

- lifecycle state (starting, started, or stopping);
- protocol type and Ethernet format attributes;
- receive buffer and access settings;
- queues of posted receive IRPs;
- a reference to the shared DPCB.

A clone never reconnects the SCSI target and never derives a new target ID
from its clone unit number.

### DPCB

The nonpaged driver-private controller block owns all state shared by the
template and cloned ports:

- the SCSI connection and port-driver vectors;
- one active SCDRP and the controller wait queue;
- the cached hardware MAC address;
- the controller coroutine stack and saved executive registers;
- enable and active-port reference counts;
- VCI callback addresses and installation state;
- receive timer and receive-poll state;
- the VCRP receive pool and its accounting counters;
- TX/RX arbitration state and passive diagnostics.

Only one DaynaPORT SCSI command is active at a time. Requests arriving while
the controller is busy enter a FIFO queue.

### LDC and VCRPs

The LAN data block records receive-pool limits, the free VCRP queue, and the
VCI data required by the upper LAN layer. Receive VCRPs are allocated from
nonpaged pool when the VCI port is created.

The target pool size is captured from SYSGEN `USER4` once during controller
initialization:

- zero or an invalid value selects 32;
- values 8 through 128 are accepted;
- allocation of zero entries fails port creation;
- a partial allocation is retained and reported as the current pool size.

After a frame is delivered upward, ownership of its VCRP transfers to the LAN
consumer. The driver's return callback validates the owner and returns the
VCRP to the free queue. Delivery and return counters make leaks visible.

## Initialization

### Unit initialization

The unit-initialization routine:

1. allocates and initializes the DPCB;
2. allocates the single SCDRP;
3. connects target 4, LUN 0 through the SCSI Port Interface;
4. marks the UCB online and ready;
5. captures and validates the LAN callback table without modifying it;
6. captures the guarded `USER4` receive-pool target.

No SCSI command is submitted from unit initialization. A command can suspend,
and that early context does not provide the continuation state required by
this class driver.

### Deferred MAC discovery

The first ordinary STARTIO request sends DaynaPORT command `0x09`, validates
the 18-byte response, and caches the first six bytes as the hardware address.
The supplied `DP_MAC_INIT` utility creates this ordinary request before the
VCI wrappers are installed.

### VCI installation

Loading and connecting DYDRIVER does not modify the global LAN callback table.
`DP_VCI_CONTROL INSTALL XQA0:` issues an exact private
`IO$_SETMODE|IO$M_CTRL` request with a guarded magic value. The driver
requires `CMKRNL`, validates every captured and current callback address,
checks that all owned queues and ports are in the required state, and then
publishes three aligned wrapper pointers.

Any pointer or ownership mismatch fails closed. The code never attempts to
repair an unfamiliar table.

VCI removal uses a separate guarded value and is accepted only after all
clients, timers, ports, requests, and buffers have drained. It is not a
hot-plug operation.

## Port lifecycle

The VCI create wrapper maps the requested LAN controller to XQA0 and creates a
cloned protocol-port UCB. The port starts only after a valid LAN startup
request.

SETMODE accepts the implemented LAN attributes transactionally. Unknown,
repeated, malformed, or out-of-range entries return `SS$_BADPARAM` without
changing port state. The initial supported set includes:

- Ethernet format;
- protocol type;
- PAD state;
- access mode;
- user buffer size;
- receive-buffer count.

The first started port enables the DaynaPORT interface. The last stopped port
disables it. Shutdown completes or cancels all owned I/O before reporting
success.

SENSEMODE returns only complete attributes that fit in the caller's buffer.
If the next complete attribute does not fit, the driver returns
`SS$_BUFFEROVF` with the number of bytes already stored. The cached physical
address is returned as the six-byte PHA string.

## Transmit path

The transmit path is:

```text
TCP/IP or DECnet
        |
        v
VCI transmit VCRP
        |
        v
DYDRIVER validation and frame coalescing
        |
        v
DaynaPORT WRITE(6), opcode 0x0A
        |
        v
ZuluSCSI Ethernet/Wi-Fi interface
```

For Ethernet format the frame consists of destination address, cached source
address, protocol type, and port payload. The driver:

- validates the VCRP segments and total length;
- supports unchained and bounded chained input;
- emits Ethernet protocol bytes in network order;
- applies the requested LAN PAD count word when enabled;
- pads short physical frames with zeroes to 60 bytes;
- never supplies an Ethernet FCS.

ZuluSCSI or the network medium supplies the FCS. Successful SCSI completion
returns the original VCRP to the VCI completion path exactly once.

## Receive path

Receive is timer paced while at least one VCI port is active:

```text
10 ms idle timer
        |
        v
DaynaPORT READ(6), opcode 0x08, single-packet mode
        |
        v
validate envelope and Ethernet frame
        |
        v
take one VCRP from the configured pool
        |
        v
VCI receive callback
        |
        v
upper layer returns VCRP to DYDRIVER
```

The six-byte DaynaPORT receive envelope is removed. The returned length is
validated, the trailing four-byte FCS is removed, and the remaining Ethernet
frame is checked before delivery.

An empty response rearms the normal timer. A nonempty response schedules one
immediate follow-up READ so a short burst is drained to empty without raising
the idle polling frequency.

When transmit and receive are both ready, the controller alternates them. This
prevents sustained transmit traffic from indefinitely starving receive work.

## Register, IPL, and completion rules

STARTIO and fork callbacks may suspend in the SCSI port driver and resume on a
different interrupt stack. Register state required after resumption is stored
in the DPCB, not left on a transient stack.

The implementation preserves executive-owned R6 through R11 across direct and
forked driver callbacks. The unit-initialization path also preserves the fork
dispatcher's R6. SCSI completion reconstructs the DPCB pointer from the UCB
before touching the shared coroutine state.

Completion follows the OpenVMS driver convention:

- R0 carries status and, for successful transfers, the byte count in its high
  word;
- R1 carries the device-dependent IOSB longword and is cleared unless an
  operation deliberately reports diagnostic state;
- every accepted IRP is completed exactly once;
- controller BUSY remains set across FIFO handoff so a new arrival cannot
  overtake an existing waiter.

## Memory ownership

All storage referenced at elevated IPL is nonpaged:

- DPCB and controller coroutine state;
- SCDRP;
- queued attribute copies;
- receive envelopes and frame buffers;
- VCRPs and VCI metadata;
- timer queue element.

Temporary blocks contain valid OpenVMS dynamic-pool size and type metadata.
Cleanup always converts a payload address back to its true allocation base
before deallocation.

The VCI receive pool remains resident until the VCI owner is fully drained.
`USER4` is therefore intentionally static; changing it cannot safely resize
an active pool.

## Failure behavior

The design prefers rejection over partial state:

- invalid SCSI replies fail the current request;
- malformed LAN attributes do not modify a port;
- an unfamiliar VCI callback table is never changed;
- hook removal with live ownership returns `SS$_DEVACTIVE`;
- no receive VCRP returns `SS$_INSFMEM` during creation;
- a temporary empty receive pool increments telemetry and postpones delivery;
- controller work is serialized rather than rejected because another command
  is active.

The startup procedure stops on a failed connect, MAC discovery, hook install,
or DHCP activation. It does not attempt destructive recovery.

## Tested boundaries

The V0.61 build has been tested with:

- automatic boot-time XQA0 connection;
- a 32-entry default receive pool selected by `USER4=0`;
- TCP/IP Services DHCP on QE0;
- ARP and bidirectional ICMP through full Ethernet frame size;
- repeated FTP transfers in both directions;
- receive-pool high-water telemetry and equality of delivery/return totals.

The final bounded workload reached 11 outstanding VCRPs, recorded no pool
exhaustion, and reported zero QE0 send/receive errors. TCP receive-side
reordering remained visible, so the architecture should not be considered
performance-complete.
