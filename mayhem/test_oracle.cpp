// mayhem/test_oracle.cpp — behavioral oracle driver for jpeg_encoder (built by build.sh
// with the project's NORMAL flags; RUN by mayhem/test.sh). Reads a BMP, encodes to JPEG.
// The oracle assertions (valid JPEG structure / size) live in test.sh, which inspects the
// produced file — so a neutered/no-op encoder (sabotage exit(0)) produces no valid output
// and FAILS the oracle.
#include <cstdio>
#include "jpeg_encoder.h"

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <input.bmp> <output.jpg>\n", argv[0]);
        return 2;
    }
    JpegEncoder encoder;
    if (!encoder.readFromBMP(argv[1])) {
        fprintf(stderr, "readFromBMP failed for %s\n", argv[1]);
        return 3;
    }
    if (!encoder.encodeToJPG(argv[2], 50)) {
        fprintf(stderr, "encodeToJPG failed for %s\n", argv[2]);
        return 4;
    }
    return 0;
}
