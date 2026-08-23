#include <descrip.h>
#include <iodef.h>
#include <starlet.h>

#include <stdio.h>
#include <string.h>

struct dp_iosb {
    unsigned short status;
    unsigned short count;
    unsigned long device_dependent;
};

static int vms_success(unsigned long status)
{
    return (status & 1ul) != 0ul;
}

int main(int argc, char **argv)
{
    const char *device_name = "XQA0:";
    struct dsc$descriptor_s device;
    struct dp_iosb iosb;
    unsigned short channel = 0;
    unsigned long service_status;
    unsigned long status;
    size_t name_length;

    if (argc > 1)
        device_name = argv[1];

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

    memset(&iosb, 0, sizeof(iosb));
    service_status = sys$qiow(0, channel, IO$_DEACCESS, &iosb,
                              0, 0, 0, 0, 0, 0, 0, 0);
    (void)sys$dassgn(channel);

    printf("DYDRIVER MAC initialization: service=%08lX iosb=%04X "
           "count=%u devdep=%08lX\n",
           service_status, (unsigned int)iosb.status,
           (unsigned int)iosb.count, iosb.device_dependent);

    if (!vms_success(service_status) ||
        !vms_success((unsigned long)iosb.status))
        return 4;

    printf("Hardware address cached; interface remains disabled.\n");
    return 0;
}
