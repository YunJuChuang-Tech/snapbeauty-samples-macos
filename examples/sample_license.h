#ifndef SNAPBEAUTY_SAMPLE_LICENSE_H
#define SNAPBEAUTY_SAMPLE_LICENSE_H

#include "snapbeauty/desktop.h"
#include <stdio.h>
#include <stdlib.h>

/* Read the token from a local file and report only the SDK's status JSON. */
static int initialize_license(const char* app_id, const char* bundled_path) {
    char token[65536];
    size_t size = 0;
    FILE* file = NULL;
    const char* path = getenv("SNAPBEAUTY_LICENSE_FILE");
    if (!path || !*path) path = bundled_path;
    if (path && *path) file = fopen(path, "rb");
    if (path && *path && !file) {
        fprintf(stderr, "Cannot open the SnapBeauty license file.\n");
        return 0;
    }
    if (file) {
        size = fread(token, 1, sizeof(token), file);
        int invalid = ferror(file) || size == sizeof(token);
        fclose(file);
        if (invalid) {
            fprintf(stderr, "Cannot read license file (maximum 65535 bytes).\n");
            return 0;
        }
        while (size && (token[size - 1] == '\r' || token[size - 1] == '\n')) --size;
    }
    token[size] = '\0';
    xm_desktop_init_options init = {sizeof(init), token, app_id, NULL};
    printf("License status: %s\n", xm_desktop_init(&init));
    return 1;
}

#endif
