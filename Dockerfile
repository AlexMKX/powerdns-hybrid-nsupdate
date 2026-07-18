# Custom PowerDNS Authoritative image: stock powerdns/pdns-auth-51 plus the
# Lua runtime dependencies and the hybrid update-policy script baked in.
#
# Base is pinned to the newest stable pdns-auth release line (5.1.x) by
# exact tag (see README for the digest). No pdns configuration is baked in
# here -- consumers still supply their own pdns.conf and point
# lua-dnsupdate-policy-script at the path this image installs the script to.
FROM powerdns/pdns-auth-51:5.1.3

USER root

# Lua deps required by hybrid_nsupdate.lua:
#   pl.tablex     -> lua-penlight
#   http.request  -> lua-http
#   json          -> lua-json
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      lua-http \
      lua-json \
      lua-penlight && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY hybrid_nsupdate.lua /opt/powerdns-hybrid-nsupdate/hybrid_nsupdate.lua

# Keep the base image's non-root pdns user and default entrypoint/cmd.
USER pdns
