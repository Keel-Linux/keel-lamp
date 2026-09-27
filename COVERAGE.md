# Coverage

Standard: decisions 0003 (90 percent per repository, 95 for code the project
writes) and 0004 (bats plus kcov for shell; a build and a boot on LXC as the
acceptance test of a recipe, docs/org-plan.md section 1).

## Measured 2026-09-27

| File | Test | Lines | Note |
| --- | --- | --- | --- |
| tests/lib/boot-test-lib.sh | tests/boot-test.bats (66 tests) | 100 percent (283/283) under kcov | argument parsing, address discovery, deadlines, the container marks, the spec and secret paths, the HTTP, PHP, CGI, Adminer, Webmin, module and diff verdicts, and this recipe's own: the two artefacts and what each declares, the appliance's landing page and the mark on it, the database answering with the declared secret, and the four assertions that the artefact without a server has none |
| conf.d/main | the build | integration only | build time script, 0004 pragmatic limits; every line of it is a check on what the parent layer, the shared conf scripts and the unit left behind, so a failed build names the thing that is wrong |
| tests/boot-test.sh | itself | integration only | the thin main of the acceptance test: keel and LXC as root, run twice in CI, once per artefact |

Total: **100 percent (283/283)**, 66 bats tests. `tests/coverage.sh` fails
below `COVERAGE_THRESHOLD`, which the workflow sets to 100, the measured
number. It is only ever raised (decision 0006).

    $ COVERAGE_THRESHOLD=100 tests/coverage.sh
    kcov line coverage (threshold 100 percent):
     100.00  283/283  boot-test-lib.sh

This recipe ships no first boot hook and no library of its own, which is why
one file is measured. The database password hook is the shared tree's
(`firstboot.d/35adminer-mysqlpass`) and the database client is the
`mariadb` component's (`bin/mysqlconf.py`); both are gated where they live.
What the recipe does at build time is checked by `conf.d/main`, and what it
does on a running machine is checked by the boot test.

## Why two lines were restructured rather than left uncovered

`bt_page_verdict` first checked the page title and the mark with `case`
statements whose passing arm was empty. kcov counts the pattern line and
never sees it execute, so the file measured 99.30 percent (283/285) with two
arms that every passing test went through. They are `if` statements now. The
alternative, an exclusion or a lowered threshold, would have hidden a real
question behind a number.

## The fifth copy of the boot test library, and what to do about it

`tests/lib/boot-test-lib.sh` now exists in keel-core, keel-nodebb,
keel-mariadb, keel-postgresql, keel-apache-php and here, and keel-lapp is the
seventh. About 130 of its lines are identical in all of them; what differs is
the verdicts of the appliance.

keel-apache-php's COVERAGE.md said the shared half should move into
`keel-linux/.github`, which already holds the reusable workflows and
`bin/require-changelog` with its own gate, and that it should happen "before
LAMP and LAPP add a sixth and a seventh copy". They have now been added,
which is worth stating plainly rather than leaving in a plan: the move did
not happen first, and this repository is part of the reason the duplication
got worse.

It was not done here either, and for a reason that has not changed: it
touches seven repositories and puts test logic behind the same `@main`
reference as the workflows, which the audit of 2026-09-26 called the highest
blast radius in the organization. It is the next thing to do in that
repository, and LAPP should be the last copy made.

## The appliance gate

`appliance / build-and-boot` and `appliance-client / build-and-boot` run
through the organization's `test-appliance.yml` on the self-hosted `keel-lxc`
runner, which fetches the published layer from
`https://mirror.keellinux.org/layers`, verifies it, assembles it, boots it in
LXC and runs `tests/boot-test.sh`. Nothing is built there. While a layer is
not published the job skips with a notice, so the check exists and the
default branch can require it from the first day.

## Plan

- Publish both layers, then require `tests / coverage`,
  `appliance / build-and-boot`, `appliance-client / build-and-boot` and
  `package / changelog` on the default branch.
- Move the shared half of the boot test library into `keel-linux/.github`,
  with its own gate there, and leave each appliance its verdicts.
- Move the MariaDB bind addresses into `unit-mariadb`, where the PostgreSQL
  component already keeps its own, and delete the copy here and the one in
  keel-mariadb's overlay.
