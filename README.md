# The Update Policy LUA script for PowerDNS. 

Allows unauthenticated and autneticated updates for the zone.

The authenticated updates controlled by the appropriate metas 
[TSIG-ALLOW-DNSUPDATE](https://doc.powerdns.com/authoritative/dnsupdate.html#tsig-allow-dnsupdate) and 
[ALLOW-DNSUPDATE-FROM](https://doc.powerdns.com/authoritative/dnsupdate.html#metadata-allow-dnsupdate-from)


The unauthenticated updates are controlled in the way ALLOW-DNSUPDATE-FROM, by X-ALLOW-UNSIGNED-DNSUPDATE-FROM meta. 

## Rquirements and installation
### Packages
```lua-http lua-json lua-penlight```


### Environment variables

```UPDATE_POLICY_API``` ip:port for the PowerDNS HTTP API (usually 127.0.0.1:8081)

```UPDATE_POLICY_API_KEY``` the API key for the PowerDNS HTTP API

### PowerDNS config
```lua-dnsupdate-policy-script = /path/to/hybrid_nsupdate.lua```

### Prebuilt container image

This repo also publishes a ready-to-use PowerDNS Authoritative image with the
Lua deps and this script baked in — no need to build your own.

Base image: [`powerdns/pdns-auth-51:5.1.3`](https://hub.docker.com/r/powerdns/pdns-auth-51/tags)
(the newest stable pdns-auth release line as of 2026-07; `pdns-auth-52` only
has pre-release `5.2.0-alpha0` tags, so `5.1.3` is the current stable).

```
ghcr.io/alexmkx/powerdns-hybrid-nsupdate:latest
```

Every build is also tagged with the full git SHA
(`ghcr.io/alexmkx/powerdns-hybrid-nsupdate:sha-<40-char-sha>`), and pushes of a
`v*` tag additionally get semver tags (`:X.Y.Z` and `:X.Y`). Pull by immutable
digest in production:

```
ghcr.io/alexmkx/powerdns-hybrid-nsupdate@sha256:<digest>
```

The script is installed at
`/opt/powerdns-hybrid-nsupdate/hybrid_nsupdate.lua`, so a consumer just needs
to point pdns at it and set the two environment variables above:

```
lua-dnsupdate-policy-script=/opt/powerdns-hybrid-nsupdate/hybrid_nsupdate.lua
```

```yaml
env:
  - name: UPDATE_POLICY_API
    value: "127.0.0.1:8081"
  - name: UPDATE_POLICY_API_KEY
    valueFrom:
      secretKeyRef:
        name: pdns-api-key
        key: api-key
```

The image keeps the base `powerdns/pdns-auth-51` image's non-root `pdns` user
and default entrypoint/CMD — only the Lua runtime deps (`lua-http`,
`lua-json`, `lua-penlight`) and the script are added on top.

### CI/CD

`.github/workflows/build.yml` builds `Dockerfile` and pushes to GHCR on:

- push to `main` → `:latest` + `:sha-<sha>`
- push of a `v*` tag → `:X.Y.Z`, `:X.Y`, `:sha-<sha>`
- manual `workflow_dispatch`

Authentication uses the built-in `GITHUB_TOKEN` with `packages: write`
permission — no extra secrets required. For the image to be pullable without
credentials, the GHCR package must be set to **public** (Package settings →
*Change visibility* → Public).

### Building it yourself

If you'd rather build the image yourself instead of using the published one:

```
FROM powerdns/pdns-auth-51:5.1.3
USER root
RUN apt-get update && apt-get install -y --no-install-recommends lua-http lua-json lua-penlight && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
COPY hybrid_nsupdate.lua /opt/powerdns-hybrid-nsupdate/hybrid_nsupdate.lua
USER pdns
```
