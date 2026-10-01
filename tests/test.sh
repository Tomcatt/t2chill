#!/bin/bash
# Runs t2chill against a fake /sys tree. No root, no real hardware touched.
#   ./tests/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export T2CHILL_SYSFS=$T/sys T2CHILL_STATE=$T/state T2CHILL_CONF=$T/none
S=$T/sys; R=$S/class/powercap/intel-rapl:0; C=$S/devices/system/cpu
pass=0
ok() { echo "  ok  $1"; pass=$((pass + 1)); }
run() { "$@" > /dev/null || { echo "FAIL  '$*' exited $?"; exit 1; }; }
eq() { [ "$(cat "$1")" = "$2" ] || { echo "FAIL  $3: $1 is '$(cat "$1")', want '$2'"; exit 1; }; ok "$3"; }

# Fake hardware with Mac mini 2018 firmware defaults
mkdir -p "$R" "$C/intel_pstate" "$C/cpu0/thermal_throttle" "$S/class/dmi/id" "$S/class/hwmon/hwmon2"
echo 100000000 > "$R/constraint_0_power_limit_uw"
echo 125000000 > "$R/constraint_1_power_limit_uw"
echo 0 > "$R/energy_uj"
for i in 0 1 2 3; do mkdir -p "$C/cpu$i/cpufreq"; echo balance_performance > "$C/cpu$i/cpufreq/energy_performance_preference"; done
echo 0 > "$C/intel_pstate/no_turbo"
echo 42 > "$C/cpu0/thermal_throttle/package_throttle_count"
echo Macmini8,1 > "$S/class/dmi/id/product_name"
echo coretemp > "$S/class/hwmon/hwmon2/name"; echo 61000 > "$S/class/hwmon/hwmon2/temp1_input"; echo 59000 > "$S/class/hwmon/hwmon2/temp2_input"

echo "apply"
run ./t2chill apply
eq "$R/constraint_0_power_limit_uw" 35000000 "PL1 capped to 35W"
eq "$R/constraint_1_power_limit_uw" 45000000 "PL2 capped to 45W"
eq "$C/cpu3/cpufreq/energy_performance_preference" balance_power "EPP set on every cpu"
eq "$C/intel_pstate/no_turbo" 1 "turbo off"
run grep -q 'PL1_UW=100000000' "$T/state/firmware-defaults.env"; ok "firmware defaults backed up before changing"

echo "apply again (must not overwrite the saved firmware defaults)"
run ./t2chill apply
run grep -q 'PL1_UW=100000000' "$T/state/firmware-defaults.env"; ok "defaults still the firmware values"
run test "$(ls "$T"/state/before-*.env | wc -l)" -ge 1; ok "every run leaves a timestamped backup"

echo "revert"
run ./t2chill revert; ok "revert exits 0"
eq "$R/constraint_0_power_limit_uw" 100000000 "PL1 restored"
eq "$R/constraint_1_power_limit_uw" 125000000 "PL2 restored"
eq "$C/cpu2/cpufreq/energy_performance_preference" balance_performance "EPP restored"
eq "$C/intel_pstate/no_turbo" 0 "turbo restored"

echo "custom settings via config file"
printf 'PL1_W=50\nTURBO_OFF=0\n' > "$T/conf"
T2CHILL_CONF=$T/conf run ./t2chill apply
eq "$R/constraint_0_power_limit_uw" 50000000 "PL1 from config"
eq "$C/intel_pstate/no_turbo" 0 "TURBO_OFF=0 keeps turbo"

echo "missing controls are skipped, not fatal"
rm -rf "$C/intel_pstate"
run ./t2chill apply; ok "apply survives a missing intel_pstate"
run ./t2chill revert; ok "revert survives a missing intel_pstate"

echo "log"
run ./t2chill log; run ./t2chill log
run test "$(wc -l < "$T/state/temps.csv")" -eq 3; ok "csv header + 2 lines"
run grep -q ',61,59,42,' "$T/state/temps.csv"; ok "logged package/core temps and throttle count"
rm -rf "$S/class/hwmon/hwmon2"
run ./t2chill log; ok "log survives a missing temperature sensor"

echo "status"
./t2chill status > "$T/status.out" || { echo "FAIL  status exited $?"; exit 1; }
run grep -q 'Macmini8,1' "$T/status.out"; ok "status runs (no sensor)"

echo "first capture of already-tuned values warns"
# Simulate a machine someone already tuned since boot: saving these as "firmware defaults" is wrong
for i in 0 1 2 3; do echo balance_power > "$C/cpu$i/cpufreq/energy_performance_preference"; done
T2CHILL_STATE=$T/state2 ./t2chill apply > "$T/tuned.out"
run grep -q 'look already tuned' "$T/tuned.out"; ok "warns when the defaults capture looks tuned"
for i in 0 1 2 3; do echo balance_performance > "$C/cpu$i/cpufreq/energy_performance_preference"; done
T2CHILL_STATE=$T/state3 ./t2chill apply > "$T/clean.out"
if grep -q 'look already tuned' "$T/clean.out"; then echo "FAIL  warned on a clean firmware capture"; exit 1; fi
ok "no warning on a clean firmware capture"

[ "$pass" -eq 22 ] || { echo "FAIL  expected 22 checks, ran $pass"; exit 1; }
echo; echo "all $pass checks passed"
