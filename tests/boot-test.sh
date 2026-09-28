#!/bin/bash
# Boot test of this stack (org-plan section 1), modelled on the ones in
# keel-nodebb, keel-mariadb, keel-postgresql and keel-apache-php: assemble the
# published layer chain into an LXC rootfs, boot it headless from the instance
# description, wait for the first boot to finish, then ask the machine for
# what the stack is for.
#
# It runs against either artefact of this recipe and is told which by the
# appliance name:
#
#   tests/boot-test.sh lamp           the stack with a local database server
#   tests/boot-test.sh lamp-client    the stack whose database is elsewhere
#
# What it proves of both, all of it over the container's global IPv6 address,
# because IPv6 first is the default this project builds for and a test written
# against 127.0.0.1 would pass on a stack that answers only on IPv4:
#
#   Apache answers on 80 and on 443 for the appliance's own page,
#   PHP executes, rather than the page coming back as source text,
#   the appliance's page carries the mark and the mark is served,
#   the CGI handler runs the Perl script under /var/www/cgi-bin,
#   Adminer answers on its own port, 12322,
#   the Webmin module the artefact is held to is installed and Webmin
#     answers on 12321,
#   and keel diff reports no drift against the description that was declared.
#
# Then the one question that differs between the artefacts, which is the
# reason there are two of them:
#
#   lamp          the database answers on ::1 and on 127.0.0.1 with the
#                 password the instance description declared,
#   lamp-client   there is no local database server: no package, no data
#                 directory, nothing listening on 3306 and no process.
#
# This proves the stack rather than the ports. A web stack that answered 200
# on every port and could not reach a database would pass a port test and fail
# the operator on the first page they wrote.
#
# Called by the reusable workflow test-appliance.yml after keel pull and keel
# verify; runnable by hand as root on any host with LXC, see tests/README.md.
# It builds nothing: the layers come from the mirror or from a directory
# bt-layer wrote, so the test needs no fab, deck or buildtasks. The logic lives
# in tests/lib/boot-test-lib.sh and is unit tested; this file is the thin main
# that touches the system.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib/boot-test-lib.sh
source "$here/lib/boot-test-lib.sh"

bt_parse_args "$@" || { rc=$?; [ "$rc" -eq 2 ] && exit 0; exit 1; }
# Which artefact this is, and everything that follows from it. The name is
# checked here rather than at the first use, so an unknown one stops before a
# container is built.
bt_has_local_database "$BT_APPLIANCE" || [ $? -eq 1 ] || exit 1
if bt_has_local_database "$BT_APPLIANCE"; then HAS_DB=yes; else HAS_DB=no; fi
BT_SPEC=${BT_SPEC:-$(bt_default_spec_for "$BT_APPLIANCE" "$here")}
secrets=$(bt_secrets_for "$BT_APPLIANCE")
webmin_module=$(bt_webmin_module_for "$BT_APPLIANCE")

if [ "$(id -u)" -ne 0 ]; then
    echo "boot-test: must run as root (keel assemble, lxc-start)" >&2
    exit 1
fi
for tool in keel lxc-start lxc-info lxc-attach lxc-stop curl; do
    command -v "$tool" >/dev/null || { echo "boot-test: $tool not found" >&2; exit 1; }
done

container_dir=$BT_LXC_PATH/$BT_NAME
log() { printf '%s boot-test: %s\n' "$(date -u +%H:%M:%S)" "$*"; }
lxc() { "lxc-$1" -P "$BT_LXC_PATH" -n "$BT_NAME" "${@:2}"; }

cleanup() {
    local rc=$?
    if [ "$rc" -ne 0 ] && [ -r "$BT_ROOTFS/var/log/inithooks.log" ]; then
        log "last lines of the container's inithooks log:"
        tail -n 40 "$BT_ROOTFS/var/log/inithooks.log"
    fi
    if [ "$BT_KEEP" -eq 1 ]; then
        log "keeping $BT_NAME under $BT_LXC_PATH (--keep); lxc-attach -P $BT_LXC_PATH -n $BT_NAME"
        return
    fi
    lxc stop -k >/dev/null 2>&1 || true
    rm -rf "$container_dir"
}
trap cleanup EXIT

log "testing $BT_APPLIANCE, which carries a local database server: $HAS_DB"

# 1. Assemble the chain from the layers the build host published.
log "assembling $BT_APPLIANCE from $BT_LAYERS_DIR into $BT_ROOTFS"
lxc stop -k >/dev/null 2>&1 || true
rm -rf "$container_dir"
mkdir -p "$BT_ROOTFS"
keel pull "$BT_APPLIANCE" --source "$BT_LAYERS_DIR" --cache-dir "$BT_CACHE_DIR" --non-interactive
keel assemble "$BT_APPLIANCE" --rootfs "$BT_ROOTFS" --cache-dir "$BT_CACHE_DIR" --non-interactive

# 2. The container marks, the instance description, the secrets it references
#    and the conf the first boot hooks read. bt_mark_container does what
#    buildtasks' container patch does: the marker under /var/lib/turnkey-info
#    that inspect reads to call the machine a container (managed_by: host),
#    and REDIRECT_OUTPUT=true with a drop-in, without which a hook that prints
#    a lot blocks writing to a tty1 nobody reads. The conf is what makes the
#    first boot headless, and without it 30rootpass waits on a dialog forever.
log "installing the description, the secrets ($secrets) and the conf into $BT_ROOTFS"
bt_mark_container "$BT_ROOTFS"
install -d -m 0700 "$BT_ROOTFS/etc/keel/secrets"
declare -A secret_value=()
for target in $(bt_secret_targets "$BT_ROOTFS" "$secrets"); do
    value=$(bt_random_password)
    printf '%s\n' "$value" > "$target"
    chmod 0600 "$target"
    secret_value[$(basename "$target")]=$value
done
for target in $(bt_spec_targets "$BT_ROOTFS"); do
    install -D -m 0600 "$BT_SPEC" "$target"
done
bt_spec_in_rootfs "$BT_SPEC" "$BT_ROOTFS" > "$container_dir/instance-host.yaml"
keel spec apply --spec "$container_dir/instance-host.yaml" \
    --conf "$BT_ROOTFS/etc/inithooks.conf" --non-interactive

# 3. Boot.
bt_lxc_config "$BT_NAME" "$BT_ROOTFS" "$BT_BRIDGE" > "$container_dir/config"
log "starting $BT_NAME on bridge $BT_BRIDGE"
lxc start -d

# 4. A global IPv6 address from the bridge.
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" "a global IPv6 address on $BT_NAME" \
    bt_container_ipv6 "$BT_NAME" "$BT_LXC_PATH" > /dev/null
addr=$(bt_container_ipv6 "$BT_NAME" "$BT_LXC_PATH")
log "container address $addr"

# 5. First boot finished: 98finalize has cleared RUN_FIRSTBOOT and the machine
#    answers, on the console (confconsole's usage screen) or on SSH. The answer
#    alone is not enough: sshd is up long before the hooks are done, so the
#    flag is what says the first boot ended.
usage_screen() {
    lxc attach -- pgrep -f confconsole > /dev/null 2>&1
}
ssh_answers() {
    local banner
    banner=$(timeout 5 bash -c 'exec 3<>"/dev/tcp/$0/$1" && read -r -t 5 line <&3 && printf "%s" "$line"' \
        "$addr" "$BT_SSH_PORT" 2>/dev/null) || return 1
    bt_is_ssh_banner "$banner"
}
first_boot_done() {
    bt_firstboot_done_in "$BT_ROOTFS/etc/default/inithooks" || return 1
    usage_screen || ssh_answers
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" "the first boot of $BT_NAME to finish" \
    first_boot_done
log "first boot finished; ssh root@$addr"

# 6. Apache answers over IPv6, on both ports, for the appliance's own page.
#    The request is made from the host to the container's global address, so
#    what is proved is a machine on the network and not a socket on loopback.
http_code() {
    curl -6 -k -s -o /dev/null -w '%{http_code}' --max-time 10 "$1" || true
}
http_body() {
    curl -6 -k -s --max-time 10 "$1" || true
}

code=""
page_over_http() {
    code=$(http_code "http://[$addr]:$BT_HTTP_PORT$BT_PAGE_PATH")
    [ "$code" = "$BT_HTTP_OK" ]
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" \
    "apache on http://[$addr]:$BT_HTTP_PORT$BT_PAGE_PATH" page_over_http
bt_http_verdict "$code" "$BT_HTTP_PORT" "apache"

code=$(http_code "https://[$addr]:$BT_HTTPS_PORT$BT_PAGE_PATH")
bt_http_verdict "$code" "$BT_HTTPS_PORT" "apache over TLS"

# 7. PHP executed. The probe page is one line of PHP, so the report in the body
#    is the proof, and the source text in the body is the failure that matters
#    most: a web stack that serves PHP as a file publishes what its pages
#    contain. Both ports are asked, because mod_php is per server and the TLS
#    vhost is a second one.
bt_php_verdict "$(http_body "http://[$addr]:$BT_HTTP_PORT$BT_PHP_PROBE_PATH")"
bt_php_verdict "$(http_body "https://[$addr]:$BT_HTTPS_PORT$BT_PHP_PROBE_PATH")"

# 7b. The appliance's own page: it is the appliance's, it carries the mark, the
#     mark is served, and it says where this artefact's database is. The last
#     is written by conf.d/main from what the image turned out to contain, so
#     reading it back here is what proves the build branched correctly.
bt_page_verdict "$(http_body "https://[$addr]:$BT_HTTPS_PORT$BT_PAGE_PATH")" "$BT_APPLIANCE"
code=$(http_code "https://[$addr]:$BT_HTTPS_PORT$BT_MARK_PATH")
bt_http_verdict "$code" "$BT_HTTPS_PORT" "the mark"
bt_mark_verdict "$(http_body "https://[$addr]:$BT_HTTPS_PORT$BT_MARK_PATH")"

# 8. The CGI handler runs the script under /var/www/cgi-bin, which is where
#    common/conf/apache-cgi points serve-cgi-bin.conf and where the parent
#    layer's overlay puts test.cgi.
code=$(http_code "http://[$addr]:$BT_HTTP_PORT$BT_CGI_PROBE_PATH")
bt_http_verdict "$code" "$BT_HTTP_PORT" "the CGI script"
bt_cgi_verdict "$(http_body "http://[$addr]:$BT_HTTP_PORT$BT_CGI_PROBE_PATH")"

# 8b. Adminer answers on its own port, over TLS: the vhost of the shared tree
#     opens with "SSLEngine on", so a plain HTTP request there is answered 400
#     by Apache rather than by Adminer. The page is checked too, so a 200 from
#     anything else fails.
adminer_answers() {
    code=$(http_code "https://[$addr]:$BT_ADMINER_PORT/")
    [ "$code" = "$BT_HTTP_OK" ]
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" \
    "adminer on https://[$addr]:$BT_ADMINER_PORT/" adminer_answers
bt_http_verdict "$code" "$BT_ADMINER_PORT" "adminer"
bt_adminer_verdict "$(http_body "https://[$addr]:$BT_ADMINER_PORT/")"

# 8c. The panel core carries, with the module this artefact is held to.
status=$(lxc attach -- dpkg-query -W -f '${Status}' "$webmin_module" 2>/dev/null || true)
bt_module_verdict "$webmin_module" "$status"
webmin_answers() {
    code=$(http_code "https://[$addr]:$BT_WEBMIN_PORT/")
    [ "$code" = 200 ] || [ "$code" = 401 ]
}
bt_wait_for "$BT_TIMEOUT" "$BT_INTERVAL" "webmin on https://[$addr]:$BT_WEBMIN_PORT/" \
    webmin_answers
bt_webmin_verdict "$code"

# 9. The database, which is the one question that differs between the two
#    artefacts of this recipe.
if [ "$HAS_DB" = yes ]; then
    # The password the instance description declared, as the test wrote it
    # into the rootfs before booting. The hook read it from the same file
    # through the declarative reader, so logging in with it proves the whole
    # path: description, secret file, DB_PASS, hook, account.
    db_pass=${secret_value[db_password]}
    for host in $BT_DB_HOSTS; do
        listening=$(lxc attach -- ss -H -ltn "sport = :$BT_DB_PORT" 2>/dev/null \
            | grep -F "$host" || true)
        bt_db_listen_verdict "$listening" "$host"
        # The password goes to the client in the environment, never on a
        # command line, where the process listing would publish it.
        answer=$(lxc attach -- env MYSQL_PWD="$db_pass" mysql \
            --user="$BT_DB_USER" --host="$host" --protocol=TCP \
            --port="$BT_DB_PORT" -N -B -e 'SELECT CURRENT_USER()' 2>/dev/null \
            | tr -d '\r' || true)
        bt_db_login_verdict "$answer" "$host"
    done
else
    # The absence, asked four ways. This artefact exists so that an operator
    # whose database is elsewhere does not carry one they never asked for, so
    # finding a server here is a failed boot test and not a note.
    status=$(lxc attach -- dpkg-query -W -f '${Status}' "$BT_DB_SERVER_PACKAGE" 2>&1 || true)
    bt_no_server_package_verdict "$status"
    bt_no_server_datadir_verdict "$(lxc attach -- ls -A "$BT_DB_DATADIR" 2>/dev/null || true)"
    bt_no_server_listen_verdict "$(lxc attach -- ss -H -ltn "sport = :$BT_DB_PORT" 2>/dev/null || true)"
    bt_no_server_process_verdict "$(lxc attach -- pgrep -a "$BT_DB_PROCESS" 2>/dev/null || true)"
fi

# 10. No drift between the declared description and the booted root.
set +e
keel diff --root "$BT_ROOTFS" --spec "$BT_SPEC"
code=$?
set -e
bt_diff_verdict "$code"
log "$BT_APPLIANCE boot test passed"
