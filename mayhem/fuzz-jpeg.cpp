// mayhem/fuzz_jpeg.cpp — in-process libFuzzer harness for thejinchao/jpeg_encoder.
//
// The upstream API (JpegEncoder::readFromBMP) reads a BMP from a *file path*, so the
// harness stages the fuzz input as a temp file, then drives the real parse + encode code
// path (readFromBMP -> encodeToJPG). This instruments the library itself (built with
// $SANITIZER_FLAGS), unlike the old raw `/fuzzjpeg @@` CLI which recorded 0 edges.
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#include <cstdint>
#include <cstddef>
#include <cstdio>
#include <stdlib.h>
#include <unistd.h>
#include "jpeg_encoder.h"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    char inpath[]  = "/tmp/fuzzjpeg_in_XXXXXX";
    int ifd = mkstemp(inpath);
    if (ifd < 0) return 0;
    ssize_t off = 0;
    while (off < (ssize_t)size) {
        ssize_t w = write(ifd, data + off, size - off);
        if (w <= 0) break;
        off += w;
    }
    close(ifd);

    char outpath[] = "/tmp/fuzzjpeg_out_XXXXXX";
    int ofd = mkstemp(outpath);
    if (ofd >= 0) close(ofd);

    {
        JpegEncoder encoder;
        if (encoder.readFromBMP(inpath)) {
            encoder.encodeToJPG(outpath, 50);
        }
    }

    unlink(inpath);
    unlink(outpath);
    return 0;
}
