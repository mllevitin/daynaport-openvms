# ZuluSCSI DaynaPORT protocol notes

ZuluSCSI presents DaynaPORT as a SCSI-1 processor device (peripheral type
`0x03`) with inquiry identity `Dayna / SCSI/Link / 2.0f`.

All vendor operations use six-byte CDBs.  For commands that transfer data,
CDB bytes 3 and 4 contain the transfer size in big-endian byte order.

| Opcode | Direction | Purpose |
|---:|:---:|---|
| `0x08` | IN | Receive Ethernet packet(s) |
| `0x09` | IN | Read six-byte MAC followed by three zero counters |
| `0x0A` | OUT | Send Ethernet packet(s) |
| `0x0C` | none | Set interface/broadcast mode; ignored by ZuluSCSI |
| `0x0D` | OUT | Add a six-byte multicast address |
| `0x0E` | none | Enable or disable the interface |
| `0x12` | IN | Standard SCSI INQUIRY |
| `0x40` | OUT | Set MAC; accepted but ignored by ZuluSCSI |
| `0x80` | none | Set mode; accepted but ignored by ZuluSCSI |

## Enable and disable

For opcode `0x0E`, bit `0x80` in CDB byte 5 enables the interface.  Clearing
the bit disables it.  Enabling also empties the firmware receive queue.

## Receive

The first six bytes of each returned packet are:

```text
0..1  packet length, big-endian
2..4  reserved, zero
5     bit 0x10 means another packet follows
```

The packet length includes the four-byte Ethernet FCS appended by ZuluSCSI.
The OpenVMS-facing code removes both the six-byte SCSI header and the FCS.
An empty receive returns six zero bytes.

CDB byte 5 selects transfer mode:

- `0x80`: single-packet/polled mode
- `0xC0`: multi-packet/blind mode

The first implementation intentionally uses single-packet mode.  It avoids
holding the VAXstation SCSI bus while the same controller may be needed for
paging and system-disk traffic.

## Transmit

For opcode `0x0A`, CDB byte 5 equal to zero selects one raw Ethernet frame
without a DaynaPORT preamble.  CDB bytes 3 and 4 are the frame size.  The host
does not append an FCS; the network side supplies it.

## OpenVMS generic SCSI descriptor

`GKDRIVER` accepts `IO$_DIAGNOSE`.  P1 points to a 15-longword descriptor:

```text
opcode, flags, CDB address, CDB length,
data address, data length, pad length,
phase timeout, disconnect timeout, six reserved longwords
```

Opcode 1 selects pass-through.  Flags bit 0 selects DATA IN.  The initial
transport keeps SCSI transfers asynchronous and uses no disconnection.

## Sources used to establish behavior

- ZuluSCSI firmware `lib/SCSI2SD/src/firmware/network.c`
- ZuluSCSI firmware `lib/SCSI2SD/src/firmware/inquiry.c`
- OpenVMS I/O User's Reference Manual, generic SCSI class driver chapter
