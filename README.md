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

### Sample Dockerfile

```
FROM powerdns/pdns-auth-master
USER root
RUN apt-get -y install lua-http lua-json lua-penlight git
RUN git clone https://github.com/AlexMKX/powerdns-hybrid-nsupdate.git /opt/powerdns-hybrid-nsupdate
USER pdns
```
