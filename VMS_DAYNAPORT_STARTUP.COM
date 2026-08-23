$! Prepare the experimental V0.61 DaynaPORT LAN device for TCP/IP Services.
$! Preferred boot order:
$!   @SYS$MANAGER:DAYNAPORT_STARTUP.COM
$!   @SYS$STARTUP:TCPIP$STARTUP.COM
$!
$! Keep this procedure beside DP_MAC_INIT.EXE and DP_VCI_CONTROL.EXE.
$! It does not modify persistent TCP/IP data,
$! remove an interface, remove a hook, or shut down another network device.
$ SET NOON
$ ON CONTROL_Y THEN GOTO ABORTED
$ OLD_VERIFY = F$VERIFY(0)
$ START_STATUS = 1
$ PROCEDURE = F$ENVIRONMENT("PROCEDURE")
$ PROJECT_ROOT = F$PARSE(PROCEDURE,,,"DEVICE") + -
                 F$PARSE(PROCEDURE,,,"DIRECTORY")
$ MAC_INIT = PROJECT_ROOT + "DP_MAC_INIT.EXE"
$ VCI_CONTROL = PROJECT_ROOT + "DP_VCI_CONTROL.EXE"
$
$ IF F$SEARCH("SYS$LOADABLE_IMAGES:DYDRIVER.EXE") .EQS. "" THEN -
      GOTO NO_DRIVER
$ IF F$SEARCH(MAC_INIT) .EQS. "" THEN GOTO NO_MAC_INIT
$ IF F$SEARCH(VCI_CONTROL) .EQS. "" THEN GOTO NO_VCI_CONTROL
$
$ XQA_DEVICE = F$DEVICE("_XQA0:")
$ IF XQA_DEVICE .EQS. "" THEN GOTO CONNECT_DEVICE
$!
$! A repeated invocation after TCP/IP has activated QE0 must return before
$! the MAC-prime DEACCESS QIO.  That QIO correctly rejects an active port,
$! but treating the expected SS$_DEVACTIVE as startup failure is not useful.
$ CHECK_EXISTING_QE0:
$ IF .NOT. F$GETDVI("_BG0:","EXISTS") THEN GOTO PRIME_MAC
$ IF .NOT. F$GETDVI("_BG0:","MNT") THEN GOTO PRIME_MAC
$ DEFINE/USER SYS$OUTPUT NL:
$ DEFINE/USER SYS$ERROR NL:
$ TCPIP SHOW INTERFACE QE0
$ IF $STATUS THEN GOTO ACTIVE
$ GOTO PRIME_MAC
$
$ CONNECT_DEVICE:
$ WRITE SYS$OUTPUT "Connecting XQA0 to DYDRIVER ..."
$ MCR SYSGEN CONNECT XQA0:/NOADAPTER/DRIVER=DYDRIVER
$ IF .NOT. $STATUS THEN GOTO CONNECT_FAILED
$ XQA_DEVICE = F$DEVICE("_XQA0:")
$ IF XQA_DEVICE .EQS. "" THEN GOTO CONNECT_MISSING
$
$ PRIME_MAC:
$ WRITE SYS$OUTPUT "Priming the DaynaPORT hardware address ..."
$ MCR 'MAC_INIT' XQA0:
$ IF .NOT. $STATUS THEN GOTO MAC_FAILED
$
$ INSTALL_HOOK:
$ WRITE SYS$OUTPUT "Installing the VCI discovery hook ..."
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
$ NO_MAC_INIT:
$ WRITE SYS$ERROR "DP_MAC_INIT.EXE was not found beside this procedure."
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
$ MAC_FAILED:
$ WRITE SYS$ERROR "DaynaPORT MAC priming failed; VCI hook was not installed."
$ GOTO FAILED
$ HOOK_FAILED:
$ WRITE SYS$ERROR "VCI hook installation failed; TCP/IP was not changed."
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
