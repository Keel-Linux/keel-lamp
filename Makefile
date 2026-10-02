# keel-lamp: LAMP, built as a child of the apache-php layer with MariaDB
# carried as a fab unit. Compatible with TurnKey Linux appliances: this is
# turnkeylinux-apps/lamp, recomposed so that the web half is the layer LAPP
# also builds on and the database half is a component rather than a parent.
#
# Two artefacts come out of this one recipe, and they differ by exactly one
# thing: whether unit.d/mariadb is present in the product directory.
#
#     # the stack with a local database server
#     git clone --branch v1.0.0 \
#         https://github.com/keel-linux/unit-mariadb.git unit.d/mariadb
#     bt-layer lamp --parent apache-php
#
#     # the same recipe with no unit cloned: no server in the image
#     bt-layer lamp-client --parent apache-php
#
# Decision 0013 is why the split is by content and not by topology. An image
# is never split by standalone, primary or replica: those differ by
# configuration and the console changes them. An image is split when the
# content differs, and a stack with a local database server and one without
# are genuinely different images. The names say what is in them: lamp has the
# server, lamp-client has the client and reaches a server somewhere else.
#
# Nothing below asks which of the two is being built by name. The recipe reads
# its own content instead, and conf.d/main asks dpkg what was actually
# installed rather than trusting the variable, which is traps.md's "asserting
# the configuration is not asserting the behaviour".

# The database component. fab resolves its plan with ours, applies its overlay
# and runs its conf script, and bt-layer records it in the layer manifest as
# "units mariadb@<version>", so a layer built on this one does not run that
# conf script a second time. Absent, the wildcard is empty and this is the
# artefact with no local server.
UNIT_DIRS ?= unit.d
HAS_DB_SERVER := $(if $(wildcard $(UNIT_DIRS)/mariadb),yes,no)

# Everything the finished image is made of is declared here, including what
# the parent already applied. bt-layer subtracts the parent's list and applies
# only the difference, and records the full list in the manifest so that a
# layer built on this one (keel-wordpress) can subtract in its turn. A recipe
# that declared only its own additions would build correctly and leave its
# children re-running the parent's conf scripts.
#
# The first four are the web stack, which is exactly what apache-php carries,
# so bt-layer subtracts all four.
include $(FAB_PATH)/common/mk/turnkey/apache.mk
include $(FAB_PATH)/common/mk/turnkey/php.mk
include $(FAB_PATH)/common/mk/turnkey/adminer.mk
include $(FAB_PATH)/common/mk/turnkey/composer.mk

# Also the parent's: CGI under /var/www/cgi-bin, Adminer behind Apache on
# 12322, and the web control panel assets.
COMMON_CONF += apache-cgi adminer-apache tkl-webcp
COMMON_OVERLAYS += tkl-webcp

# What makes this LAMP rather than the shared web layer, beyond the unit:
# the shared tree's script that points Adminer at the MySQL driver and creates
# the account whose password the first boot hook sets. It starts the server to
# create that account, so it runs only in the artefact that has one. In the
# artefact that does not, conf.d/main does the half that needs no server, so
# Adminer is pointed at MySQL either way.
ifeq ($(HAS_DB_SERVER),yes)
COMMON_CONF += adminer-mysql
endif

# After the includes, so a file of this overlay wins over a file of the shared
# tree and of the unit. The overlay reaches the tree a second time as
# ROOT_OVERLAY, after the units, which is what actually decides it.
COMMON_OVERLAYS += $(CURDIR)/overlay

# 80 and 443 are the stack, 12322 is Adminer, 12321 the panel core carries and
# 12320 the web shell it also carries. The same list the parent sets, and the
# database is not on it in either artefact: in lamp it listens on the two
# loopback addresses only, which the boot test proves on the running machine.
WEBMIN_FW_TCP_INCOMING = 22 80 443 12320 12321 12322

include $(FAB_PATH)/common/mk/turnkey.mk

# The project's own packages (inithooks, confconsole, keel) come from the
# build host's APT repository during the build only. The repository is copied
# into the bootstrap and listed as a [trusted=yes] file source, because the
# staging distribution is unsigned; conf.d/main pins it for the build only and
# removes the source, the copy and the pin from the image. The appliance's own
# Keel source and pin are common's (overlays/turnkey.d/keel-apt). Same block
# as keel-mariadb and keel-nodebb, which is where the pattern is maintained.
KEEL_APT_REPO ?= /srv/keel-apt/repo
KEEL_APT_DIST ?= trixie-staging

define _keel_bootstrap/post

	mkdir -p $O/bootstrap/srv/keel-apt/repo;
	rm -rf $O/bootstrap/srv/keel-apt/repo/dists $O/bootstrap/srv/keel-apt/repo/pool;
	cp -a $(KEEL_APT_REPO)/dists $(KEEL_APT_REPO)/pool $O/bootstrap/srv/keel-apt/repo/;
	echo "deb [trusted=yes] file:///srv/keel-apt/repo $(KEEL_APT_DIST) main" > $O/bootstrap/etc/apt/sources.list.d/keel-staging.list;
	fab-chroot $O/bootstrap "apt-get update";
endef
bootstrap/post += $(_keel_bootstrap/post)
