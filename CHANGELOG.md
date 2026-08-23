# Changelog

## V0.62 — 2026-08-24

- Added a native full sequential PCSI kit for OpenVMS VAX V7.3.
- Added a compiler-independent installation path containing the prebuilt
  driver, its two runtime utilities, startup procedure, safe IVP,
  administrator guide, and MIT License.
- Added reproducible native release and PCSI packaging procedures.
- Validated a native build and a PCSI upgrade from V0.61 to V0.62 on the
  development VAXstation.
- Changed no packet-I/O behavior from V0.61; V0.62 is the packaging release.

## V0.61 — 2026-08-23

- Fixed the receive-pool configuration path so reading SYSGEN `USER4` no
  longer overwrites the live LAN-vector pointer in R0.
- Raised the default receive pool to 32 and accepted explicit `USER4` values
  from 8 through 128.
- Passed native build, boot, DHCP, and sustained FTP gates with no receive
  buffer exhaustion or VCRP leak.
