/*
 * Copyright (c) 2026 chatgpt5.6-sol and mlevitin.
 * SPDX-License-Identifier: MIT
 */

#include <descrip.h>
#include <iodef.h>
#include <starlet.h>

#include <stdio.h>
#include <string.h>

#define DP_VCI_CTL_INSTALL 0x5643492bul
#define DP_VCI_CTL_REMOVE  0x5643492dul

struct dp_iosb {
    unsigned short status;
    unsigned short count;
    unsigned long device_dependent;
};

static int vms_success(unsigned long status)
{
    return (status & 1ul) != 0ul;
}

static int action_is(const char *value, const char *upper, const char *lower)
{
    return strcmp(value, upper) == 0 || strcmp(value, lower) == 0;
}

int main(int argc, char **argv)
{
    const char *device_name = "XQA0:";
    const char *action;
    const char *label;
    struct dsc$descriptor_s device;
    struct dp_iosb iosb;
    unsigned short channel = 0;
    unsigned short function;
    unsigned long magic;
    unsigned long service_status;
    unsigned long status;
    size_t name_length;

    if (argc < 2 || argc > 3) {
        fprintf(stderr, "Usage: DP_VCI_CONTROL INSTALL|REMOVE [device]\n");
        return 2;
    }

    action = argv[1];
    if (argc > 2)
        device_name = argv[2];

    if (action_is(action, "INSTALL", "install")) {
        magic = DP_VCI_CTL_INSTALL;
        label = "install";
    } else if (action_is(action, "REMOVE", "remove")) {
        magic = DP_VCI_CTL_REMOVE;
        label = "remove";
    } else {
        fprintf(stderr, "Action must be INSTALL or REMOVE.\n");
        return 2;
    }

    name_length = strlen(device_name);
    if (name_length == 0u || name_length > 255u) {
        fprintf(stderr, "Invalid device name.\n");
        return 2;
    }

    device.dsc$w_length = (unsigned short)name_length;
    device.dsc$b_dtype = DSC$K_DTYPE_T;
    device.dsc$b_class = DSC$K_CLASS_S;
    device.dsc$a_pointer = (char *)device_name;

    status = sys$assign(&device, &channel, 0, 0);
    if (!vms_success(status)) {
        fprintf(stderr, "SYS$ASSIGN failed: %08lX\n", status);
        return 3;
    }

    function = (unsigned short)(IO$_SETMODE | IO$M_CTRL);
    memset(&iosb, 0, sizeof(iosb));
    service_status = sys$qiow(0, channel, function, &iosb,
                              0, 0, magic, 0, 0, 0, 0, 0);
    (void)sys$dassgn(channel);

    printf("DYDRIVER VCI control (%s): service=%08lX iosb=%04X "
           "count=%u devdep=%08lX\n",
           label, service_status, (unsigned int)iosb.status,
           (unsigned int)iosb.count, iosb.device_dependent);

    if (!vms_success(service_status) ||
        !vms_success((unsigned long)iosb.status)) {
        fprintf(stderr,
                "VCI transition rejected; callback table was not changed.\n");
        return 4;
    }

    printf("VCI callback %s completed.\n", label);
    return 0;
}
