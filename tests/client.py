#!/usr/bin/env python3
"""Tiny dnspython client used by tests/run.sh (integration tests).

Usage:
  client.py update SERVER ZONE (--rr NAME,TYPE,TTL,VALUE)... (--del NAME[,TYPE])... [--tsig NAME:SECRET]
  client.py query SERVER NAME TYPE

`update` sends one RFC2136 update message and prints the rcode name
(e.g. NOERROR, REFUSED). `query` prints FOUND or MISSING. Exit code is 0
unless the exchange itself fails (timeout, network, bad TSIG answer).
"""
import sys

import dns.query
import dns.rcode
import dns.message
import dns.tsigkeyring
import dns.update


def do_update(server, zone, rrs, dels, tsig):
    u = dns.update.UpdateMessage(zone)
    for spec in rrs:
        name, rtype, ttl, value = spec.split(",", 3)
        u.add(name, int(ttl), rtype, value)
    for spec in dels:
        u.delete(*spec.split(","))
    if tsig:
        keyname, secret = tsig.split(":", 1)
        u.use_tsig(dns.tsigkeyring.from_text({keyname: secret}))  # default algo = hmac-sha256
    resp = dns.query.udp(u, server, timeout=5)
    print(dns.rcode.to_text(resp.rcode()))


def do_query(server, name, rtype):
    q = dns.message.make_query(name, rtype)
    q.flags = 0  # plain authoritative query, no recursion
    resp = dns.query.udp(q, server, timeout=5)
    print("FOUND" if resp.rcode() == dns.rcode.NOERROR and resp.answer else "MISSING")


def main(argv):
    if len(argv) >= 4 and argv[1] == "update":
        rrs, dels, tsig = [], [], None
        rest = argv[4:]
        while rest:
            if rest[0] == "--rr":
                rrs.append(rest[1]); rest = rest[2:]
            elif rest[0] == "--del":
                dels.append(rest[1]); rest = rest[2:]
            elif rest[0] == "--tsig":
                tsig = rest[1]; rest = rest[2:]
            else:
                sys.exit(f"unknown arg {rest[0]!r}")
        do_update(argv[2], argv[3], rrs, dels, tsig)
    elif len(argv) == 5 and argv[1] == "query":
        do_query(argv[2], argv[3], argv[4])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
