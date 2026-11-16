#!/usr/bin/env bash
# Compile and run the module-level unit testbenches with Icarus Verilog.
#   bash scripts/run_unit_tests.sh        -> controller test for N = 3 (default)
#   bash scripts/run_unit_tests.sh 4      -> controller test for N = 4
#
# The testbenches print FAIL and then call $finish, so vvp exits with status 0
# even when a check fails. This script reads the output instead and exits with
# status 1 if any FAIL line appears or a PASSED message is missing.
set -e
cd "$(dirname "$0")/.."
N=${1:-3}
status=0

# run_test <name> <pass message> <iverilog arguments...>
run_test() {
    name=$1
    pass_msg=$2
    shift 2
    iverilog -g2005 -o "sim_$name.vvp" "$@"
    log=$(vvp "sim_$name.vvp")
    echo "$log"
    if echo "$log" | grep -q "FAIL" || ! echo "$log" | grep -q "$pass_msg"; then
        echo ">>> $name: FAILED"
        status=1
    fi
}

run_test mac "MAC TESTBENCH PASSED" \
    rtl/mac_unit.v tb/tb_mac_unit.v

run_test ctrl "CONTROLLER TESTBENCH PASSED" \
    -P tb_systolic_ctrl.N="$N" rtl/systolic_ctrl.v tb/tb_systolic_ctrl.v

if [ "$status" -eq 0 ]; then
    echo "All unit tests passed (N=$N)"
else
    echo "Some unit tests failed (N=$N)"
fi
exit "$status"
