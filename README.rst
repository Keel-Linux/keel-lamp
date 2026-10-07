.. warning::

   **Archived (2026-10-07).** Keel retired Apache: web appliances use nginx
   with php-fpm (LEMP), see Keel-Linux/keel-nginx-php-fastcgi and Keel-Linux/keel-web.
   This repository is kept read-only for reference.

LAMP
====

Apache, PHP and MariaDB on Debian 13, built as a child of the ``apache-php``
layer with the database carried as a fab unit. Compatible with TurnKey Linux
appliances: this is ``turnkeylinux-apps/lamp``, recomposed so that the web
half is shared with LAPP instead of being built twice.

Two artefacts, split by content
-------------------------------

============  =========================================================
``lamp``      Apache, PHP and a local MariaDB server
``lamp-client``  the same stack with the client and the drivers, and no
              local server, for the database that lives somewhere else
============  =========================================================

Handbook decision 0013 settled the split. An image is never split by
topology: standalone, primary and replica are the same content with a
different configuration, and the console changes them, so two images for
that would be byte identical while each paid for its own build, boot test,
audit, signature and reproducibility. An image *is* split when the content
differs, and a stack with a database server installed and one without are
genuinely different images. The names say what is in them.

The variant without a server must not ship an idle one. That is the whole
reason the split exists, so both the build and the boot test assert the
absence rather than assuming it: ``conf.d/main`` fails the build if a server
package is installed, and the boot test fails if the running machine has a
data directory, a listening database port or a server process.

How the two are built
---------------------

One recipe, and the artefacts differ by exactly one thing: whether
``unit.d/mariadb`` is present in the product directory. ::

    # the stack with a local database server
    git clone --branch v1.0.0 \
        https://github.com/keel-linux/unit-mariadb.git unit.d/mariadb
    bt-layer lamp --parent apache-php

    # the same recipe with no unit cloned
    bt-layer lamp-client --parent apache-php

``fab`` resolves the unit's plan together with this one, applies its overlay
and runs its conf script, and ``bt-layer`` records it in the layer manifest
as ``units mariadb@1.0.0``. A layer built on this one, ``wordpress``,
subtracts the unit by name and does not run that conf script a second time,
which is the thing decision 0010 said had to exist before any component
could move out of the shared tree.

Nothing in the recipe asks which artefact is being built by name.
``conf.d/main`` asks dpkg what the image contains and branches on the answer,
because a makefile variable says what was asked for and dpkg says what
happened.

What this layer adds to ``apache-php``
--------------------------------------

The parent carries Apache, mod_php, php-cli, mod_security2, mod_evasive,
mod_perl2, the Webmin modules for Apache and php.ini, Adminer with its
syntax highlighter, Composer, the CGI path, Adminer's vhost on 12322 and the
web control panel. ``bt-layer`` subtracts all of it. What is left:

- the ``mariadb`` unit, in the ``lamp`` artefact only;
- four packages that make the stack MariaDB's rather than another engine's:
  ``mariadb-client``, ``php-mysql``, ``libdbd-mysql-perl``,
  ``python3-mysqldb``. LAPP names the same four roles with the PostgreSQL
  packages;
- ``conf/adminer-mysql`` from the shared tree, in the ``lamp`` artefact only,
  which points Adminer at the MySQL driver and creates the ``adminer``
  account. In ``lamp-client`` there is no server to create an account in, so
  ``conf.d/main`` does the half that needs none;
- the bind addresses, ``::1`` and ``127.0.0.1``, written as literals;
- the appliance's own landing page and the console service list.

The one thing that should move into the component
-------------------------------------------------

``conf.d/main`` writes ``/etc/mysql/mariadb.conf.d/99-keel-bind.cnf``. It
should not have to. ``unit-postgresql`` sets its own ``listen_addresses``
inside its conf script, with the reasoning in a comment, because the
addresses a server answers on belong to whoever installs the server;
``unit-mariadb`` does not set ``bind-address``, so every recipe that carries
it has to. ``keel-mariadb`` carries the same file in its own overlay, so the
setting already exists twice.

It is left here rather than fixed in passing, because ``unit-mariadb`` is
consumed by ``keel-mariadb`` as well and that repository has the change in
flight. Moving it is one commit in the component and two deletions in the
consumers.

The database password
---------------------

``secrets.db_password`` in the instance description renders to ``DB_PASS``,
which ``firstboot.d/35adminer-mysqlpass`` of the shared tree reads at first
boot and gives to the ``adminer`` account. The build creates that account
with a password nobody knows and the layer is published that way, because a
layer is fetched by name and reused: a password chosen at build time would
be the same password on every appliance built from it.

Nothing new was written for this. The hook is the one upstream ships in the
Adminer overlay and the client is ``mysqlconf.py`` from the ``mariadb``
component.

The appliance's own page
------------------------

``/var/www/index.php`` is the appliance's page and carries the mark, which is
the one place the brand manual asks for it: *"A default landing page shipped
by the appliance, as LAMP has, is ours and carries the mark until they
replace it."* It says which file to replace. The mark is
``keel-lockup.svg``, copied from ``docs/brand`` of the handbook rather than
redrawn.

The host name the page prints comes from the request, so it is escaped before
it reaches the document. The upstream page printed it raw.

What upstream ships and this does not
-------------------------------------

``libapache2-mod-python`` (absent from Debian 13), ``php-xdebug`` (a
debugger and profiler, not something a published appliance should have
switched on), ``php-pear`` (superseded by composer, which the parent
carries), and ``conf-available/remove-upgrade-header.conf`` (a web server
setting with no database in it, proposed for ``apache-php`` where both
stacks would get it). Each is in the changelog with its reason. Keeping them
would make this recipe differ from LAPP in something other than the
database, which is the one thing the composition is measured on.

Tests
-----

``tests/boot-test.sh`` assembles the published chain, boots it in LXC and
asks the running machine, over its global IPv6 address, for what the stack
is for: PHP executing on 80 and on 443 rather than being served as source,
the CGI handler running, Adminer answering on 12322, Webmin on 12321, the
appliance's page carrying the mark, and ``keel diff`` clean. Then the one
question that differs between the artefacts: ``lamp`` is asked whether the
database answers with the declared secret, and ``lamp-client`` is asked to
prove it has no server at all.

``tests/coverage.sh`` measures the logic of the boot test with kcov over the
bats suite; ``COVERAGE.md`` has the numbers and the threshold the workflow
enforces.