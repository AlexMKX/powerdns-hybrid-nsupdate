-- Dependency-free PowerDNS update-policy Lua script.
--
-- Runs on a STOCK powerdns/pdns-auth image: it requires NO external Lua
-- libraries (no lua-http, no lua-json, no lua-penlight). Instead of querying
-- the PowerDNS HTTP API for zone metadata, it loads the policy data from a
-- plain-Lua data file once at module load.
--
-- The PowerDNS update-policy Lua environment does NOT expose any native
-- metadata accessor on the `input` object (confirmed against pdns/lua-auth4.cc:
-- only getQName/getZoneName/getQType/getLocal/getRemote/getRealRemote/
-- getTsigName/getPeerPrincipal are registered). Hence the data-file approach.
--
-- Data file path is taken from env UPDATE_POLICY_DATA
-- (default: /etc/powerdns/policy/policy_data.lua). See policy_data.lua for the
-- expected table shape.

local DATA_PATH = os.getenv('UPDATE_POLICY_DATA') or '/etc/powerdns/policy/policy_data.lua'

-- Load the policy data once, at module load. If the file is missing or fails
-- to load we fall back to an empty policy (deny-by-default) and log the reason.
local POLICY = {}
do
    local chunk, err = loadfile(DATA_PATH)
    if not chunk then
        pdnslog("hybrid_nsupdate: could not load policy data from " .. DATA_PATH .. ": " .. tostring(err))
    else
        local ok, result = pcall(chunk)
        if not ok then
            pdnslog("hybrid_nsupdate: error executing policy data " .. DATA_PATH .. ": " .. tostring(result))
        elseif type(result) ~= "table" then
            pdnslog("hybrid_nsupdate: policy data " .. DATA_PATH .. " did not return a table")
        else
            POLICY = result
            pdnslog("hybrid_nsupdate: loaded policy data from " .. DATA_PATH)
        end
    end
end

-- Pure-Lua replacement for pl.tablex.size(): counts entries in a table
-- (works for array-like AND map-like tables, unlike the `#` operator).
local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- Replacement for the former HTTP get_meta(): returns the list stored for the
-- given zone/key in the loaded policy data, or an empty table if absent.
function get_meta(domain, name)
    local zone = POLICY[domain]
    if zone and zone[name] then
        return zone[name]
    end
    return {}
end

function updatepolicy(input)
    local zone = input:getZoneName():toString()
    pdnslog("Updatepolicy: " .. zone)

    if input:getTsigName():countLabels() > 0
    then
        pdnslog("Got Tsig " .. input:getTsigName():toStringNoDot())
        local allowed_tsigs_meta = get_meta(zone, 'TSIG-ALLOW-DNSUPDATE')
        pdnslog("Allowed tsigs: " .. table.concat(allowed_tsigs_meta, ', '))
        for k, v in pairs(allowed_tsigs_meta) do
            if v == input:getTsigName():toStringNoDot()
            then
                pdnslog("Allowed tsig " .. v .. " checking IPs")
                local allowed_dnsupdate_from_meta = get_meta(zone, 'ALLOW-DNSUPDATE-FROM')
                pdnslog("Allowed signed dnsupdate-from " .. table.concat(allowed_dnsupdate_from_meta, ", "))
                if count(allowed_dnsupdate_from_meta) == 0
                then
                    pdnslog("No IP limit (ALLOW-DNSUPDATE-FROM is empty), allowing")
                    return true
                end
                local mynetworks = newNMG()
                mynetworks:addMasks(allowed_dnsupdate_from_meta)
                if not mynetworks:match(input:getRemote())
                then
                    pdnslog("IP " .. input:getRemote():toString() .. " not allowed")
                    return false
                else
                    pdnslog("IP " .. input:getRemote():toString() .. " allowed")
                    return true
                end
            end
        end
        pdnslog("tsig " .. input:getTsigName():toStringNoDot() .. " not allowed")
        return false
    end

    local unsigned_from = get_meta(zone, 'X-ALLOW-UNSIGNED-DNSUPDATE-FROM')
    pdnslog("Allowed unsigned updates from " .. table.concat(unsigned_from, ", "))
    local mynetworks = newNMG()
    mynetworks:addMasks(unsigned_from)
    if not mynetworks:match(input:getRemote())
    then
        pdnslog("IP " .. input:getRemote():toString() .. " not allowed")
        return false
    else
        pdnslog("IP " .. input:getRemote():toString() .. " allowed")
        return true
    end
end
