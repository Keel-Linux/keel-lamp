# Tests

`boot-test.bats` runs the pure half of the boot test, `lib/boot-test-lib.sh`,
under bats. Nothing in it needs root, a network, a web server, a database or
LXC: `lxc-info` is a stub first in `PATH`, the clock and sleep are functions,
and every verdict is a pure function over text the boot test collected.

    bats tests/boot-test.bats
    COVERAGE_THRESHOLD=100 tests/coverage.sh

`boot-test.sh` is the acceptance test and needs a machine: root, LXC, `keel`,
and the published layers. It takes the artefact as its argument, because this
recipe produces two:

    tests/boot-test.sh lamp        --layers-dir /mnt/builds/layers --bridge lxcbr0
    tests/boot-test.sh lamp-client --layers-dir /mnt/builds/layers --bridge lxcbr0

`--bridge` matters: the default is `br0` and a host that has none will hang
waiting for an address. On the project build host the bridge is `lxcbr0`,
whose `/64` is a ULA, which `bt_is_global_ipv6` accepts and link local
addresses it does not.

`--keep` leaves the container running so it can be attached to, which is the
first thing to reach for when a verdict fails and the message is not enough.

In CI both artefacts are booted, by two jobs, on the self-hosted `keel-lxc`
runner. They are separate jobs on purpose: one job for both would hide which
artefact failed, and the one that needs proving most is `lamp-client`, whose
whole purpose is that something is absent.
