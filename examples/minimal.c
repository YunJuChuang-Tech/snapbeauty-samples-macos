/* A complete public C API integration using a locally generated RGBA8 frame. */
#include "sample_license.h"

#include <string.h>

int main(void) {
    enum { width = 64, height = 64, stride = width * 4 };
    uint8_t pixels[height * stride], output[height * stride];
    const char* assets = getenv("SNAPBEAUTY_ASSETS");
    const char* app_id = getenv("SNAPBEAUTY_APP_ID");
    if (!assets || !*assets) {
        fprintf(stderr, "Set SNAPBEAUTY_ASSETS to the SDK Assets directory.\n");
        return 2;
    }
    if (!app_id || !*app_id) app_id = "ai.snapbeauty.samples.macos.minimal";

    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            uint8_t* pixel = pixels + y * stride + x * 4;
            pixel[0] = (uint8_t)(x * 4);
            pixel[1] = (uint8_t)(y * 4);
            pixel[2] = 128;
            pixel[3] = 255;
        }
    }

    if (!initialize_license(app_id, NULL)) return 2;
    xm_desktop_options options = {sizeof(options), assets};
    xm_desktop_engine* engine = NULL;
    xm_status status = xm_desktop_engine_create(&options, &engine);
    if (status != XM_OK) {
        fprintf(stderr, "Engine creation failed (%d): %s\n", (int)status, xm_desktop_last_error(NULL));
        xm_desktop_shutdown();
        return 1;
    }

    float values[XM_PARAM_COUNT] = {0};
    /* Neutral start: zero-filling is not "no effect". These twelve bidirectional face controls are neutral at 0.5;
     * 0 pushes each one to an extreme and visibly reshapes the face. Everything else is neutral at 0. */
    values[XM_PARAM_SHAPE_CHIN_LENGTH] = values[XM_PARAM_SHAPE_FOREHEAD_HEIGHT] = values[XM_PARAM_SHAPE_MOUTH_SIZE] = 0.5f;
    values[XM_PARAM_SHAPE_LIP_FULLNESS] = values[XM_PARAM_SHAPE_EYE_POSITION] = values[XM_PARAM_SHAPE_EYE_DISTANCE] = 0.5f;
    values[XM_PARAM_SHAPE_EYE_TILT] = values[XM_PARAM_SHAPE_NOSE_LENGTH] = values[XM_PARAM_SHAPE_PHILTRUM_LENGTH] = 0.5f;
    values[XM_PARAM_SHAPE_BROW_POSITION] = values[XM_PARAM_SHAPE_BROW_DISTANCE] = values[XM_PARAM_SHAPE_BROW_THICKNESS] = 0.5f;
    values[XM_PARAM_SMOOTHING] = 4.2f;
    values[XM_PARAM_BRIGHTENING] = 0.3f;
    xm_params params = {sizeof(params), values, XM_PARAM_COUNT, NULL, NULL};
    status = xm_desktop_engine_set_params(engine, &params);
    if (status == XM_OK) {
        xm_desktop_frame frame = {
            sizeof(frame), pixels, width, height, stride, XM_PIXEL_RGBA8, 0, output, stride
        };
        xm_frame_result result = {0};
        result.struct_size = sizeof(result);
        status = xm_desktop_process(engine, &frame, &result);
        if (status == XM_OK) {
            printf("SDK %s, process=%d, face_detected=%d, passthrough=%s\n",
                   xm_desktop_version(), (int)status, (int)result.face_detected,
                   memcmp(pixels, output, sizeof(pixels)) == 0 ? "yes" : "no");
        }
    }
    if (status != XM_OK) {
        fprintf(stderr, "Frame setup/processing failed (%d): %s\n", (int)status, xm_desktop_last_error(engine));
    }

    xm_desktop_engine_destroy(engine);
    xm_desktop_shutdown();
    return status == XM_OK ? 0 : 1;
}
