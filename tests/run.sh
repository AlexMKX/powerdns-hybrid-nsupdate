#!/usr/bin/env bash
# Integration tests for hybrid_nsupdate.lua against a REAL, STOCK
# powerdns/pdns-auth-51:5.1.3 container (gsqlite3 backend, no custom image,
# nothing installed into the container).
#
# Brings up a docker network with fixed client IPs, runs the full test matrix
# (cases a-j plus multi-RR/delete extras), prints PASS/FAIL per case, and
# tears everything down via an EXIT trap. Exits non-zero on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

NET=pdns-hn-test
SUBNET=172.30.199.0/24
PDNS_IMAGE=powerdns/pdns-auth-51:5.1.3
CLIENT_IMAGE=python:3-slim
PDNS=172.30.199.2     # pdns with tests/policy_data.lua
PDNS_X=172.30.199.3   # pdns with missing (case h) / broken (case i) policy file
IP_A=172.30.199.10    # client-a: in ALLOW-DNSUPDATE-FROM of forward.test.
IP_B=172.30.199.20    # client-b: in X-ALLOW-UNSIGNED-DNSUPDATE-FROM of forward.test.
C_A=pdns-hn-client-a
C_B=pdns-hn-client-b
PASS_N=0
FAIL_N=0

cleanup() {
  docker rm -f pdns-hn-main pdns-hn-x "$C_A" "$C_B" >/dev/null 2>&1 || true
  docker network rm "$NET" >/dev/null 2>&1 || true
  [ -n "${TD:-}" ] && rm -rf "$TD" || true
}
trap cleanup EXIT

pass() { echo "PASS: $1"; PASS_N=$((PASS_N + 1)); }
fail() { echo "FAIL: $1 -- $2"; FAIL_N=$((FAIL_N + 1)); }
# check DESC EXPECTED ACTUAL
check() {
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected '$2', got '$3'"; fi
}
# log_has DESC CONTAINER PATTERN
# (plain grep, not grep -q: -q exits on first match, SIGPIPEs `docker logs`
# under pipefail and false-fails on big logs)
log_has() {
  if docker logs "$2" 2>&1 | grep "$3" >/dev/null; then
    pass "$1"
  else
    fail "$1" "no log line matching '$3' in $2"
  fi
}

# upd CLIENT SERVER ZONE [client.py args...] -> prints rcode (or ERROR)
upd() { docker exec "$1" python /tests/client.py update "$2" "$3" "${@:4}" || echo ERROR; }
# qry CLIENT SERVER NAME TYPE -> prints FOUND/MISSING (or ERROR)
qry() { docker exec "$1" python /tests/client.py query "$2" "$3" "$4" || echo ERROR; }

# wait_ready CLIENT SERVER ZONE: until SOA resolves (also tolerates the
# client container still pip-installing dnspython).
wait_ready() {
  for _ in $(seq 1 90); do
    if [ "$(qry "$1" "$2" "$3" SOA 2>/dev/null)" = FOUND ]; then return 0; fi
    sleep 1
  done
  echo "ERROR: $2 never became ready" >&2
  return 1
}

FWD=$(openssl rand -base64 32)
REV=$(openssl rand -base64 32)
OTHER=$(openssl rand -base64 32)
export TSIG_FWD_SECRET=$FWD TSIG_REV_SECRET=$REV TSIG_OTHER_SECRET=$OTHER

TD=$(mktemp -d /tmp/pdns-hn-test.XXXXXX)
printf 'error("this policy data file is broken on purpose")\n' > "$TD/broken_policy.lua"

echo "== starting docker network + containers =="
docker network create --subnet "$SUBNET" "$NET" >/dev/null

# Main pdns: stock image, gsqlite3 (DB shipped with the image), zones+keys
# created by the entrypoint via pdnsutil before the server starts.
docker run -d --name pdns-hn-main --network "$NET" --ip "$PDNS" \
  -e UPDATE_POLICY_DATA=/policy/policy_data.lua \
  -e TSIG_FWD_SECRET -e TSIG_REV_SECRET -e TSIG_OTHER_SECRET \
  -v "$PWD/hybrid_nsupdate.lua:/policy/hybrid_nsupdate.lua:ro" \
  -v "$PWD/tests/policy_data.lua:/policy/policy_data.lua:ro" \
  -v "$PWD/tests/entrypoint.sh:/entrypoint-test.sh:ro" \
  --entrypoint sh "$PDNS_IMAGE" /entrypoint-test.sh >/dev/null

for c in "$C_A:$IP_A" "$C_B:$IP_B"; do
  docker run -d --name "${c%%:*}" --network "$NET" --ip "${c##*:}" \
    -v "$PWD/tests:/tests:ro" --entrypoint sh "$CLIENT_IMAGE" \
    -c 'pip -q install dnspython && sleep infinity' >/dev/null
done

wait_ready "$C_A" "$PDNS" forward.test.
wait_ready "$C_B" "$PDNS" forward.test.

echo "== cases =="

# a. signed, allowed key, source IP in ALLOW-DNSUPDATE-FROM -> NOERROR
rc=$(upd "$C_A" "$PDNS" forward.test. --rr a1.forward.test.,A,60,192.0.2.1 --tsig "fwd-key:$FWD")
check "a: signed+allowed key from allowed IP -> NOERROR" NOERROR "$rc"
check "a: record present after accepted update" FOUND "$(qry "$C_A" "$PDNS" a1.forward.test. A)"

# b. signed, allowed key, source IP NOT in ALLOW-DNSUPDATE-FROM -> REFUSED
rc=$(upd "$C_B" "$PDNS" forward.test. --rr b1.forward.test.,A,60,192.0.2.2 --tsig "fwd-key:$FWD")
check "b: signed+allowed key from wrong IP -> REFUSED" REFUSED "$rc"
check "b: record absent after refused update" MISSING "$(qry "$C_A" "$PDNS" b1.forward.test. A)"

# c. signed with a key pdns knows but NOT in TSIG-ALLOW-DNSUPDATE -> REFUSED
rc=$(upd "$C_A" "$PDNS" forward.test. --rr c1.forward.test.,A,60,192.0.2.3 --tsig "other-key:$OTHER")
check "c: signed with known-but-unlisted key -> REFUSED" REFUSED "$rc"
check "c: record absent after refused update" MISSING "$(qry "$C_A" "$PDNS" c1.forward.test. A)"

# d. signed, allowed key, zone with EMPTY ALLOW-DNSUPDATE-FROM: any IP -> NOERROR
rc=$(upd "$C_A" "$PDNS" reverse.test. --rr d1.reverse.test.,A,60,192.0.2.4 --tsig "rev-key:$REV")
check "d: empty ALLOW-DNSUPDATE-FROM, IP a -> NOERROR" NOERROR "$rc"
check "d: record present after accepted update" FOUND "$(qry "$C_A" "$PDNS" d1.reverse.test. A)"
rc=$(upd "$C_B" "$PDNS" reverse.test. --rr d2.reverse.test.,A,60,192.0.2.5 --tsig "rev-key:$REV")
check "d: empty ALLOW-DNSUPDATE-FROM, IP b -> NOERROR" NOERROR "$rc"
check "d: record present after accepted update" FOUND "$(qry "$C_B" "$PDNS" d2.reverse.test. A)"

# e. unsigned, source IP in X-ALLOW-UNSIGNED-DNSUPDATE-FROM -> NOERROR
#    (IP_B is non-loopback and outside the default allow-dnsupdate-from
#    127.0.0.0/8, so this NOERROR also proves the global ACL is bypassed.)
rc=$(upd "$C_B" "$PDNS" forward.test. --rr e1.forward.test.,A,60,192.0.2.6)
check "e: unsigned from X-ALLOW-UNSIGNED IP -> NOERROR" NOERROR "$rc"
check "e: record present after accepted update" FOUND "$(qry "$C_B" "$PDNS" e1.forward.test. A)"

# f. unsigned, source IP not listed -> REFUSED
rc=$(upd "$C_A" "$PDNS" forward.test. --rr f1.forward.test.,A,60,192.0.2.7)
check "f: unsigned from unlisted IP -> REFUSED" REFUSED "$rc"
check "f: record absent after refused update" MISSING "$(qry "$C_A" "$PDNS" f1.forward.test. A)"

# g. zone exists in pdns but is ABSENT from the policy file -> REFUSED
rc=$(upd "$C_A" "$PDNS" orphan.test. --rr g1.orphan.test.,A,60,192.0.2.8 --tsig "fwd-key:$FWD")
check "g: signed to policy-absent zone -> REFUSED" REFUSED "$rc"
check "g: record absent after refused update" MISSING "$(qry "$C_A" "$PDNS" g1.orphan.test. A)"
rc=$(upd "$C_B" "$PDNS" orphan.test. --rr g2.orphan.test.,A,60,192.0.2.9)
check "g: unsigned to policy-absent zone -> REFUSED" REFUSED "$rc"
check "g: record absent after refused update" MISSING "$(qry "$C_B" "$PDNS" g2.orphan.test. A)"

# h. policy file missing: pdns still starts and serves, denies all, logs why.
docker run -d --name pdns-hn-x --network "$NET" --ip "$PDNS_X" \
  -e UPDATE_POLICY_DATA=/policy/missing.lua \
  -e TSIG_FWD_SECRET -e TSIG_REV_SECRET -e TSIG_OTHER_SECRET \
  -v "$PWD/hybrid_nsupdate.lua:/policy/hybrid_nsupdate.lua:ro" \
  -v "$PWD/tests/entrypoint.sh:/entrypoint-test.sh:ro" \
  --entrypoint sh "$PDNS_IMAGE" /entrypoint-test.sh >/dev/null
wait_ready "$C_A" "$PDNS_X" forward.test.
check "h: missing policy file, pdns still serves" FOUND "$(qry "$C_A" "$PDNS_X" forward.test. SOA)"
rc=$(upd "$C_A" "$PDNS_X" forward.test. --rr h1.forward.test.,A,60,192.0.2.10 --tsig "fwd-key:$FWD")
check "h: missing policy file, signed update -> REFUSED" REFUSED "$rc"
rc=$(upd "$C_B" "$PDNS_X" forward.test. --rr h2.forward.test.,A,60,192.0.2.11)
check "h: missing policy file, unsigned update -> REFUSED" REFUSED "$rc"
log_has "h: log contains 'could not load policy data'" pdns-hn-x "could not load policy data"
docker rm -f pdns-hn-x >/dev/null

# i. policy file that errors at load -> deny all + logged
docker run -d --name pdns-hn-x --network "$NET" --ip "$PDNS_X" \
  -e UPDATE_POLICY_DATA=/policy/policy_data.lua \
  -e TSIG_FWD_SECRET -e TSIG_REV_SECRET -e TSIG_OTHER_SECRET \
  -v "$PWD/hybrid_nsupdate.lua:/policy/hybrid_nsupdate.lua:ro" \
  -v "$TD/broken_policy.lua:/policy/policy_data.lua:ro" \
  -v "$PWD/tests/entrypoint.sh:/entrypoint-test.sh:ro" \
  --entrypoint sh "$PDNS_IMAGE" /entrypoint-test.sh >/dev/null
wait_ready "$C_A" "$PDNS_X" forward.test.
rc=$(upd "$C_A" "$PDNS_X" forward.test. --rr i1.forward.test.,A,60,192.0.2.12 --tsig "fwd-key:$FWD")
check "i: erroring policy file, signed update -> REFUSED" REFUSED "$rc"
rc=$(upd "$C_B" "$PDNS_X" forward.test. --rr i2.forward.test.,A,60,192.0.2.13)
check "i: erroring policy file, unsigned update -> REFUSED" REFUSED "$rc"
log_has "i: log contains 'error executing policy data'" pdns-hn-x "error executing policy data"
docker rm -f pdns-hn-x >/dev/null

# j. happy-path log line. NOTE: pdns 5.1.3 does NOT load the policy script at
# startup -- it (re)loads it lazily for every update (see "loaded policy
# data" appearing once per update in the log), so this is checked after the
# updates above, not right after container start.
log_has "j: log contains 'hybrid_nsupdate: loaded policy data'" pdns-hn-main "hybrid_nsupdate: loaded policy data"

# k. multi-RR update (pdns calls the policy per RR) in ONE update message
rc=$(upd "$C_A" "$PDNS" forward.test. \
  --rr k1.forward.test.,A,60,192.0.2.14 \
  --rr k2.forward.test.,TXT,60,multi-rr-test \
  --tsig "fwd-key:$FWD")
check "k: multi-RR update -> NOERROR" NOERROR "$rc"
check "k: first RR present" FOUND "$(qry "$C_A" "$PDNS" k1.forward.test. A)"
check "k: second RR present" FOUND "$(qry "$C_A" "$PDNS" k2.forward.test. TXT)"

# l. delete-record update, signed+allowed
rc=$(upd "$C_A" "$PDNS" forward.test. --del l1.forward.test. --tsig "fwd-key:$FWD")
check "l: signed+allowed delete of absent name -> NOERROR" NOERROR "$rc"
rc=$(upd "$C_A" "$PDNS" forward.test. --rr l1.forward.test.,A,60,192.0.2.15 --tsig "fwd-key:$FWD")
check "l: add record for delete test -> NOERROR" NOERROR "$rc"
rc=$(upd "$C_A" "$PDNS" forward.test. --del l1.forward.test. --tsig "fwd-key:$FWD")
check "l: signed+allowed delete -> NOERROR" NOERROR "$rc"
check "l: record gone after delete" MISSING "$(qry "$C_A" "$PDNS" l1.forward.test. A)"
# delete via qtype ANY from a client whose IP is only unsigned-allowed: unsigned
rc=$(upd "$C_B" "$PDNS" forward.test. --del e1.forward.test.)
check "l: unsigned delete from X-ALLOW-UNSIGNED IP -> NOERROR" NOERROR "$rc"
check "l: record gone after unsigned delete" MISSING "$(qry "$C_B" "$PDNS" e1.forward.test. A)"

echo "== summary: $PASS_N passed, $FAIL_N failed =="
[ "$FAIL_N" -eq 0 ]
