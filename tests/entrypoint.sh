#!/bin/sh
# Entrypoint for the test pdns containers (STOCK powerdns/pdns-auth-51:5.1.3
# image, gsqlite3 backend). Creates test zones + TSIG keys with pdnsutil
# (before the server starts, so no zone-cache staleness), then execs the
# image's own startup script, which execs pdns_server --disable-syslog
# (logs to stderr => `docker logs`).
set -e

# NOTE on allow-dnsupdate-from: per the auth 5.1 docs (dnsupdate.html,
# "How it works", step 4: "If update policy Lua script is provided then skip
# up to 7"), setting lua-dnsupdate-policy-script makes pdns SKIP the global
# allow-dnsupdate-from check (and the per-zone ALLOW-DNSUPDATE-FROM /
# TSIG-ALLOW-DNSUPDATE metadata checks) -- the Lua script is the only gate.
# We therefore deliberately leave allow-dnsupdate-from at its default
# (127.0.0.0/8): all test clients come from docker-network IPs, so any
# accepted non-loopback update proves the global ACL was bypassed and the
# Lua script made the decision. (TSIG validation, zone-exists and the
# dnsupdate=yes check still happen before the script, per the same docs.)
cat > /etc/powerdns/pdns.d/test.conf <<'EOF'
dnsupdate=yes
lua-dnsupdate-policy-script=/policy/hybrid_nsupdate.lua
loglevel=6
EOF

# Zones: forward/reverse are in the test policy; orphan is NOT (case g).
for z in forward.test reverse.test orphan.test; do
    pdnsutil zone create "$z" >/dev/null
done

pdnsutil tsigkey import fwd-key   hmac-sha256 "$TSIG_FWD_SECRET"   >/dev/null
pdnsutil tsigkey import rev-key   hmac-sha256 "$TSIG_REV_SECRET"   >/dev/null
pdnsutil tsigkey import other-key hmac-sha256 "$TSIG_OTHER_SECRET" >/dev/null

exec /usr/local/sbin/pdns_server-startup
