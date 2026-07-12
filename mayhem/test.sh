#!/usr/bin/env bash
#
# mayhem/test.sh — behavioral oracle for jpeg_encoder. Upstream ships NO unit/functional test
# suite (only a `test.cpp` main that shells a BMP->JPEG conversion with no assertions), so this
# is an AUTHORED known-answer oracle: encode several fixed 24-bit BMPs and assert the encoder
# produces STRUCTURALLY VALID JPEG output (SOI 0xFFD8 ... EOI 0xFFD9, non-trivial size). A
# no-op/exit(0) sabotage of the encoder produces no valid output and FAILS here.
# RUNs the /mayhem/test_oracle built by build.sh (never compiles). Emits a CTRF summary.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
cd "$SRC"

emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

ORACLE=/mayhem/test_oracle
if [ ! -x "$ORACLE" ]; then
  echo "test.sh: $ORACLE missing — build.sh must build the oracle first" >&2
  emit_ctrf "jpeg_encoder-oracle" 0 1
  exit 1
fi

passed=0
failed=0

# assert_valid_jpeg <file> : structurally valid JPEG (SOI ... EOI) and non-trivial size
check_case() {
  local name="$1" bmp="$2"
  local out; out="$(mktemp /tmp/oracle_out_XXXXXX.jpg)"
  rm -f "$out"
  if ! "$ORACLE" "$SRC/$bmp" "$out"; then
    echo "FAIL $name: oracle returned non-zero" >&2
    failed=$((failed+1)); return
  fi
  if [ ! -s "$out" ]; then
    echo "FAIL $name: no output produced" >&2
    failed=$((failed+1)); return
  fi
  local size; size=$(stat -c%s "$out")
  if [ "$size" -lt 128 ]; then
    echo "FAIL $name: output too small ($size bytes)" >&2
    failed=$((failed+1)); rm -f "$out"; return
  fi
  # SOI = FF D8 at start, EOI = FF D9 at end
  local soi eoi
  soi=$(head -c2 "$out" | od -An -tx1 | tr -d ' \n')
  eoi=$(tail -c2 "$out" | od -An -tx1 | tr -d ' \n')
  if [ "$soi" != "ffd8" ]; then
    echo "FAIL $name: bad SOI marker ($soi)" >&2
    failed=$((failed+1)); rm -f "$out"; return
  fi
  if [ "$eoi" != "ffd9" ]; then
    echo "FAIL $name: bad EOI marker ($eoi)" >&2
    failed=$((failed+1)); rm -f "$out"; return
  fi
  echo "PASS $name: valid JPEG, $size bytes (SOI/EOI ok)"
  passed=$((passed+1)); rm -f "$out"
}

# determinism: encoding the same input twice must be byte-identical
check_determinism() {
  local name="$1" bmp="$2"
  local a b; a="$(mktemp /tmp/det_a_XXXXXX.jpg)"; b="$(mktemp /tmp/det_b_XXXXXX.jpg)"
  rm -f "$a" "$b"
  if "$ORACLE" "$SRC/$bmp" "$a" && "$ORACLE" "$SRC/$bmp" "$b" && [ -s "$a" ] && [ -s "$b" ] && cmp -s "$a" "$b"; then
    echo "PASS $name: deterministic output"
    passed=$((passed+1))
  else
    echo "FAIL $name: non-deterministic or missing output" >&2
    failed=$((failed+1))
  fi
  rm -f "$a" "$b"
}

check_case         "encode_16x16"  "mayhem/testdata/case1.bmp"
check_case         "encode_8x8"    "mayhem/testdata/case2.bmp"
check_case         "encode_24x16"  "mayhem/testdata/case3.bmp"
check_determinism  "determinism_16x16" "mayhem/testdata/case1.bmp"

emit_ctrf "jpeg_encoder-oracle" "$passed" "$failed"
