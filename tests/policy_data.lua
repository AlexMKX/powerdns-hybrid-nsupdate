-- Test policy data for the integration tests in run.sh. NOT the repo sample.
--
-- IP plan (must match the docker network in tests/run.sh):
--   172.30.199.2   pdns (main, uses this file)
--   172.30.199.3   pdns (missing/broken policy file cases)
--   172.30.199.10  client-a  -- in ALLOW-DNSUPDATE-FROM of forward.test.
--   172.30.199.20  client-b  -- in X-ALLOW-UNSIGNED-DNSUPDATE-FROM of forward.test.
--
-- orphan.test. exists in pdns but is deliberately ABSENT here (case g).

return {
    ["forward.test."] = {
        ["TSIG-ALLOW-DNSUPDATE"] = { "fwd-key" },
        ["ALLOW-DNSUPDATE-FROM"] = { "172.30.199.10/32" },
        ["X-ALLOW-UNSIGNED-DNSUPDATE-FROM"] = { "172.30.199.20/32" },
    },
    ["reverse.test."] = {
        ["TSIG-ALLOW-DNSUPDATE"] = { "rev-key" },
        -- EMPTY ALLOW-DNSUPDATE-FROM => any source IP for a matching key.
        ["ALLOW-DNSUPDATE-FROM"] = {},
        ["X-ALLOW-UNSIGNED-DNSUPDATE-FROM"] = {},
    },
}
