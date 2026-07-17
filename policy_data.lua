-- Sample policy data file for hybrid_nsupdate.lua.
--
-- This file MUST return a Lua table describing, per zone, the update policy.
-- The path to this file is given to hybrid_nsupdate.lua via the environment
-- variable UPDATE_POLICY_DATA (default: /etc/powerdns/policy/policy_data.lua).
--
-- Table shape:
--
--   {
--     ["<zone-name-with-trailing-dot.>"] = {
--       -- TSIG key names that are allowed to perform SIGNED updates.
--       -- These are matched against input:getTsigName():toStringNoDot(),
--       -- so list them WITHOUT the trailing dot.
--       ["TSIG-ALLOW-DNSUPDATE"] = { "keyname1", "keyname2" },
--
--       -- Networks (CIDR masks) from which SIGNED updates are accepted once
--       -- the TSIG key matched. An EMPTY list means "no IP restriction"
--       -- (any source IP is allowed for a matching TSIG key).
--       ["ALLOW-DNSUPDATE-FROM"] = { "192.0.2.0/24", "203.0.113.5/32" },
--
--       -- Networks from which UNSIGNED (no TSIG) updates are accepted.
--       -- An empty/absent list means unsigned updates are denied.
--       ["X-ALLOW-UNSIGNED-DNSUPDATE-FROM"] = { "10.0.0.0/8" },
--     },
--   }
--
-- Notes:
--   * Zone names are compared against input:getZoneName():toString(), which
--     includes the trailing dot (e.g. "example.org.").
--   * Any zone or key that is absent is treated as an empty list, i.e. denied
--     (except that an empty ALLOW-DNSUPDATE-FROM for a matched TSIG key means
--     "no IP limit", preserving the original behavior).

return {
    ["example.org."] = {
        ["TSIG-ALLOW-DNSUPDATE"] = { "dhcpdupdate" },
        ["ALLOW-DNSUPDATE-FROM"] = { "192.0.2.0/24" },
        ["X-ALLOW-UNSIGNED-DNSUPDATE-FROM"] = { "127.0.0.1/32" },
    },

    ["1.168.192.in-addr.arpa."] = {
        ["TSIG-ALLOW-DNSUPDATE"] = { "dhcpdupdate" },
        -- Empty ALLOW-DNSUPDATE-FROM => any source IP allowed for a matching TSIG key.
        ["ALLOW-DNSUPDATE-FROM"] = {},
        ["X-ALLOW-UNSIGNED-DNSUPDATE-FROM"] = {},
    },
}
