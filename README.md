# The Update Policy LUA script for PowerDNS.

Allows unauthenticated and authenticated DNS UPDATEs for a zone, with per-zone
allow-lists for TSIG keys and source networks.

The authenticated (signed) updates are controlled by the
[TSIG-ALLOW-DNSUPDATE](https://doc.powerdns.com/authoritative/dnsupdate.html#tsig-allow-dnsupdate)
and
[ALLOW-DNSUPDATE-FROM](https://doc.powerdns.com/authoritative/dnsupdate.html#metadata-allow-dnsupdate-from)
policy keys.

The unauthenticated (unsigned) updates are controlled in the same fashion as
`ALLOW-DNSUPDATE-FROM`, by the `X-ALLOW-UNSIGNED-DNSUPDATE-FROM` policy key.

## Dependency-free (stock `powerdns/pdns-auth`)

This script has **zero external Lua dependencies**. It does **not** use
`lua-http`, `lua-json` or `lua-penlight`, and therefore needs **no custom
PowerDNS Docker image** — it runs on the stock `powerdns/pdns-auth` image and
can be delivered as a plain file (e.g. via a Kubernetes ConfigMap).

Instead of querying the PowerDNS HTTP API for zone metadata, the policy data is
loaded once, at script load, from a plain-Lua **data file** (see
[`policy_data.lua`](policy_data.lua) for the shape).

> **Why a data file and not native metadata access?**
> The PowerDNS update-policy Lua environment does **not** expose any native way
> to read a zone's domain metadata. The `input` object registered by PowerDNS
> only provides `getQName`, `getZoneName`, `getQType`, `getLocal`, `getRemote`,
> `getRealRemote`, `getTsigName` and `getPeerPrincipal` (see the official
> [Update policy docs](https://doc.powerdns.com/authoritative/dnsupdate.html#update-policy)
> and `pdns/lua-auth4.cc` in the PowerDNS source). The original HTTP-API
> approach existed precisely because there is no native accessor. Reading a
> local data file removes the HTTP client dependency entirely.

> **⚠️ Breaking change.** This replaces the previous behavior, which read live
> zone metadata from the PowerDNS HTTP API (`UPDATE_POLICY_API` /
> `UPDATE_POLICY_API_KEY`). Those environment variables and the `lua-http` /
> `lua-json` / `lua-penlight` packages are **no longer used**. Provide the
> policy as a `policy_data.lua` data file instead.

## Requirements and installation

### Packages

None. Runs on stock `powerdns/pdns-auth` — no `lua-http`, `lua-json` or
`lua-penlight`.

### Policy data file

Provide a Lua data file that returns the per-zone policy table. See
[`policy_data.lua`](policy_data.lua) for a documented sample. The expected
shape is:

```lua
return {
    ["example.org."] = {
        ["TSIG-ALLOW-DNSUPDATE"]            = { "dhcpdupdate" },
        ["ALLOW-DNSUPDATE-FROM"]            = { "192.0.2.0/24" },
        ["X-ALLOW-UNSIGNED-DNSUPDATE-FROM"] = { "127.0.0.1/32" },
    },
}
```

Notes:

* Zone keys must include the trailing dot (matched against
  `input:getZoneName():toString()`, e.g. `"example.org."`).
* TSIG key names are listed **without** the trailing dot (matched against
  `input:getTsigName():toStringNoDot()`).
* An **empty** `ALLOW-DNSUPDATE-FROM` for a matched TSIG key means "no IP
  restriction" (any source IP allowed) — preserving the original behavior.
* Any absent zone or key is treated as an empty list (deny-by-default).

### Environment variables

`UPDATE_POLICY_DATA` — path to the policy data file.
Default: `/etc/powerdns/policy/policy_data.lua`.

### PowerDNS config

```
lua-dnsupdate-policy-script = /path/to/hybrid_nsupdate.lua
```

### Kubernetes (stock image, ConfigMap) — outline

Mount both `hybrid_nsupdate.lua` and `policy_data.lua` from a ConfigMap into the
stock `powerdns/pdns-auth` container, point `lua-dnsupdate-policy-script` at the
script, and set `UPDATE_POLICY_DATA` to the mounted data-file path. No custom
image or registry is required.
