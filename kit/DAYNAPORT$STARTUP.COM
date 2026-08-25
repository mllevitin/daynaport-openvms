$! Prepare the experimental V0.68 DaynaPORT LAN device for TCP/IP Services.
$! Copyright (c) 2026 chatgpt5.6-sol and mlevitin.
$! SPDX-License-Identifier: MIT
$! Preferred boot order:
$!   @SYS$STARTUP:DAYNAPORT$STARTUP.COM
$!   @SYS$STARTUP:TCPIP$STARTUP.COM
$!
$! Keep this procedure beside DP_VCI_CONTROL.EXE.
$! It does not modify persistent TCP/IP data,
$! remove an interface, remove a hook, or shut down another network device.
$ SET NOON
$ ON CONTROL_Y THEN GOTO ABORTED
$ OLD_VERIFY = F$VERIFY(0)
$ START_STATUS = 1
$ PROCEDURE = F$ENVIRONMENT("PROCEDURE")
$ PROJECT_ROOT = F$PARSE(PROCEDURE,,,"DEVICE") + -
                 F$PARSE(PROCEDURE,,,"DIRECTORY")
$ VCI_CONTROL = PROJECT_ROOT + "DP_VCI_CONTROL.EXE"
$
$ IF F$SEARCH("SYS$LOADABLE_IMAGES:DYDRIVER.EXE") .EQS. "" THEN -
      GOTO NO_DRIVER
$ IF F$SEARCH(VCI_CONTROL) .EQS. "" THEN GOTO NO_VCI_CONTROL
$
$ XQA_DEVICE = F$DEVICE("_XQA0:")
$ IF XQA_DEVICE .EQS. "" THEN GOTO CONNECT_DEVICE
$!
$! A repeated invocation after TCP/IP has activated QE0 must return before
$! attempting a hook transition against the live VCI client.
$ CHECK_EXISTING_QE0:
$ IF .NOT. F$GETDVI("_BG0:","EXISTS") THEN GOTO INSTALL_HOOK
$ IF .NOT. F$GETDVI("_BG0:","MNT") THEN GOTO INSTALL_HOOK
$ DEFINE/USER SYS$OUTPUT NL:
$ DEFINE/USER SYS$ERROR NL:
$ TCPIP SHOW INTERFACE QE0
$ IF $STATUS THEN GOTO ACTIVE
$ GOTO INSTALL_HOOK
$
$ CONNECT_DEVICE:
$ WRITE SYS$OUTPUT "Connecting XQA0 to DYDRIVER ..."
$ MCR SYSGEN CONNECT XQA0:/NOADAPTER/DRIVER=DYDRIVER
$ IF .NOT. $STATUS THEN GOTO CONNECT_FAILED
$ XQA_DEVICE = F$DEVICE("_XQA0:")
$ IF XQA_DEVICE .EQS. "" THEN GOTO CONNECT_MISSING
$
$ INSTALL_HOOK:
$! The first ordinary STARTIO request caches the MAC before installing the
$! VCI discovery hook.
$ WRITE SYS$OUTPUT "Caching the DaynaPORT MAC and installing the VCI hook ..."
$ MCR 'VCI_CONTROL' INSTALL XQA0:
$ IF .NOT. $STATUS THEN GOTO HOOK_FAILED
$
$! If TCP/IP is not running yet, its normal startup will consume the
$! persistent QE0 /DHCP record.  If TCP/IP is already running and QE0 is
$! absent, activate the same volatile DHCP interface now.
$ IF .NOT. F$GETDVI("_BG0:","EXISTS") THEN GOTO PREPARED
$ IF .NOT. F$GETDVI("_BG0:","MNT") THEN GOTO PREPARED
$ DEFINE/USER SYS$OUTPUT NL:
$ DEFINE/USER SYS$ERROR NL:
$ TCPIP SHOW INTERFACE QE0
$ IF $STATUS THEN GOTO ACTIVE
$ WRITE SYS$OUTPUT "TCP/IP is running; activating QE0 by DHCP ..."
$ TCPIP SET INTERFACE QE0 /DHCP
$ IF .NOT. $STATUS THEN GOTO DHCP_FAILED
$ GOTO ACTIVE
$
$ PREPARED:
$ WRITE SYS$OUTPUT -
      "DaynaPORT is prepared; TCPIP$STARTUP will activate persistent QE0/DHCP."
$ GOTO DONE
$
$ ACTIVE:
$ WRITE SYS$OUTPUT "DaynaPORT XQA0/QE0 startup completed."
$ GOTO DONE
$
$ NO_DRIVER:
$ WRITE SYS$ERROR "SYS$LOADABLE_IMAGES:DYDRIVER.EXE was not found."
$ GOTO FAILED
$ NO_VCI_CONTROL:
$ WRITE SYS$ERROR "DP_VCI_CONTROL.EXE was not found beside this procedure."
$ GOTO FAILED
$ CONNECT_FAILED:
$ WRITE SYS$ERROR "SYSGEN CONNECT XQA0 failed."
$ GOTO FAILED
$ CONNECT_MISSING:
$ WRITE SYS$ERROR "SYSGEN returned success but XQA0 is absent."
$ GOTO FAILED
$ HOOK_FAILED:
$ WRITE SYS$ERROR -
$      "DaynaPORT preparation failed; VCI hook and TCP/IP were not changed."
$ GOTO FAILED
$ DHCP_FAILED:
$ WRITE SYS$ERROR "QE0 DHCP activation failed; XQA0 and its hook remain available."
$ GOTO FAILED
$ ABORTED:
$ WRITE SYS$ERROR "DaynaPORT startup aborted."
$ GOTO FAILED
$
$ FAILED:
$ START_STATUS = %X10000002
$ DONE:
$ OLD_VERIFY = F$VERIFY(OLD_VERIFY)
$ EXIT START_STATUS
