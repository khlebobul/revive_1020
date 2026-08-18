#include <libusb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define HP_VID 0x03f0
#define HP_1020_PID 0x2b17

static void fail(const char *what, int code) {
    fprintf(stderr, "%s: %s\n", what, libusb_error_name(code));
    exit(1);
}

int main(int argc, char **argv) {
    int force_send = argc == 3 && strcmp(argv[1], "--send") == 0;
    if (argc != 2 && !force_send) {
        fprintf(stderr, "usage: %s [--send] FILE\n", argv[0]);
        return 2;
    }
    const char *path = argv[force_send ? 2 : 1];

    libusb_context *ctx = NULL;
    libusb_device_handle *handle = NULL;
    struct libusb_config_descriptor *config = NULL;
    int rc = libusb_init(&ctx);
    if (rc < 0) fail("libusb_init", rc);

    handle = libusb_open_device_with_vid_pid(ctx, HP_VID, HP_1020_PID);
    if (!handle) {
        fprintf(stderr, "HP LaserJet 1020 not found or inaccessible\n");
        libusb_exit(ctx);
        return 1;
    }

    rc = libusb_get_active_config_descriptor(libusb_get_device(handle), &config);
    if (rc < 0) fail("get configuration", rc);

    int interface_number = -1;
    unsigned char endpoint = 0;
    for (int i = 0; i < config->bNumInterfaces; i++) {
        const struct libusb_interface_descriptor *alt =
            &config->interface[i].altsetting[0];
        for (int e = 0; e < alt->bNumEndpoints; e++) {
            const struct libusb_endpoint_descriptor *ep = &alt->endpoint[e];
            if ((ep->bmAttributes & LIBUSB_TRANSFER_TYPE_MASK) == LIBUSB_TRANSFER_TYPE_BULK &&
                (ep->bEndpointAddress & LIBUSB_ENDPOINT_DIR_MASK) == LIBUSB_ENDPOINT_OUT) {
                interface_number = alt->bInterfaceNumber;
                endpoint = ep->bEndpointAddress;
                break;
            }
        }
        if (endpoint) break;
    }
    if (!endpoint) {
        fprintf(stderr, "bulk OUT endpoint not found\n");
        return 1;
    }

    libusb_set_auto_detach_kernel_driver(handle, 1);
    rc = libusb_claim_interface(handle, interface_number);
    if (rc < 0) fail("claim USB printer interface", rc);

    unsigned char id[256] = {0};
    rc = libusb_control_transfer(handle,
        LIBUSB_ENDPOINT_IN | LIBUSB_REQUEST_TYPE_CLASS | LIBUSB_RECIPIENT_INTERFACE,
        0, 0, interface_number, id, sizeof(id), 2000);
    if (rc >= 2) {
        int length = (id[0] << 8) | id[1];
        if (length > rc) length = rc;
        printf("Device ID: %.*s\n", length - 2, id + 2);
        if (!force_send && memmem(id + 2, (size_t)(length - 2), ";FWVER:", 7)) {
            puts("Firmware already loaded.");
            libusb_release_interface(handle, interface_number);
            libusb_free_config_descriptor(config);
            libusb_close(handle);
            libusb_exit(ctx);
            return 0;
        }
    }

    FILE *firmware = fopen(path, "rb");
    if (!firmware) {
        perror(path);
        return 1;
    }

    unsigned char buffer[16384];
    size_t count;
    while ((count = fread(buffer, 1, sizeof(buffer), firmware)) > 0) {
        size_t offset = 0;
        while (offset < count) {
            int sent = 0;
            rc = libusb_bulk_transfer(handle, endpoint, buffer + offset,
                (int)(count - offset), &sent, 30000);
            offset += (size_t)sent;
            if (rc < 0 && sent == 0) {
                fprintf(stderr, "USB transfer stopped at %ld: %s\n",
                    ftell(firmware) - (long)count + (long)offset,
                    libusb_error_name(rc));
                return 1;
            }
        }
    }
    fclose(firmware);
    puts(force_send ? "Print data sent." : "Firmware sent.");

    libusb_release_interface(handle, interface_number);
    libusb_free_config_descriptor(config);
    libusb_close(handle);
    libusb_exit(ctx);
    if (!force_send) sleep(8);
    return 0;
}
