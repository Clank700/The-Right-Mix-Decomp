/* mp3tool: decode an MP3 with miniaudio (the decoder the Windows port used) to raw signed 16-bit mono PCM.
   usage: mp3tool in.mp3 out.raw      prints: <sample rate> <frames>
   Built by build_mp3tool.bat; used by build_assets.py to turn the SWF's MP3 sounds into trimmed WAV files. */
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MINIAUDIO_IMPLEMENTATION
#include "../../port/windows/audio/miniaudio.h"
#include <stdio.h>
#include <stdlib.h>
int main(int argc, char** argv) {
  if (argc < 3) return 2;
  ma_decoder dec;
  ma_decoder_config cfg = ma_decoder_config_init(ma_format_s16, 1, 0);
  if (ma_decoder_init_file(argv[1], &cfg, &dec) != MA_SUCCESS) { fprintf(stderr, "decode failed\n"); return 1; }
  ma_uint64 total = 0; ma_decoder_get_length_in_pcm_frames(&dec, &total);
  short* buf = (short*)malloc((size_t)total * 2 + 2);
  ma_uint64 got = 0; ma_decoder_read_pcm_frames(&dec, buf, total, &got);
  FILE* f = fopen(argv[2], "wb"); fwrite(buf, 2, (size_t)got, f); fclose(f);
  printf("%u %llu\n", dec.outputSampleRate, got);
  return 0;
}
