#!/bin/bash
# Run every test cartridge and check the picture shows the four colour bars.
cd "$(dirname "$0")"
python3 make_test_carts.py > /dev/null
pass=0; fail=0
check() {   # name cart extra-args   (names ending in _bad must NOT show the bars)
  local name=$1 cart=$2; shift 2
  local log
  log=$(timeout 900 ./obj_dir/Vtb_top +cart=roms/$cart +frames=5 +out=out/$name "$@" 2>&1)
  local typeline
  typeline=$(echo "$log" | grep '^loader:')
  if python3 - "$name" <<'EOF'
import sys
from PIL import Image
name = sys.argv[1]
im = Image.open(f'out/{name}_004.ppm').convert('RGB')
want = [(3, 82, 168), (184, 136, 9), (73, 188, 32), (238, 238, 238)]
# bars are 80 px wide starting at x=18
got = [im.getpixel((18 + 40 + 80 * i, 120)) for i in range(4)]
sys.exit(0 if got == want else 1)
EOF
  then ok=1; else ok=0; fi
  if [[ $name == *_bad ]]; then ok=$((1-ok)); fi
  if [ $ok == 1 ]; then echo "PASS $name   ($typeline)"; pass=$((pass+1))
  else echo "FAIL $name   ($typeline)"; fail=$((fail+1)); fi
}
check t32       test32.a52
check t16two    test16two.a52
check t16one    test16one.a52
check t8        test8.a52
check t4        test4.a52
check tcar32    test32.car
check tcar16two test16two.car
# forcing the wrong 16K layout must break the picture
check t16two_forced_one_bad test16two.a52 +mode16=1
check t16one_forced_two_bad test16one.a52 +mode16=2
echo "passed $pass, failed $fail"
