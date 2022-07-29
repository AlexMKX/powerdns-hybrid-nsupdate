local api_key = os.getenv('UPDATE_POLICY_API_KEY')
local server = os.getenv('UPDATE_POLICY_API')
function get_meta(domain, name)
    local http_request = require "http.request"
    require "json"
    local r = http_request.new_from_uri("http://" .. server .. "/api/v1/servers/localhost/zones/" .. domain .. "/metadata/" .. name)
    r.headers:append('X-API-Key', api_key)
    headers, stream = r:go()
    local body = assert(stream:get_body_as_string())
    local t = json.decode(body)
    return t.metadata
end

function updatepolicy(input)
    local zone = input:getZoneName():toString()
    pdnslog("Updatepolicy: " .. zone)

    if input:getTsigName():countLabels() > 0
    then
        pdnslog("got Tsig " .. input:getTsigName():toStringNoDot())
        local allowed_tsigs_meta = get_meta(zone, 'TSIG-ALLOW-DNSUPDATE')
        pdnslog("Allowed tsigs: " .. table.concat(allowed_tsigs_meta, ', '))
        for k, v in pairs(allowed_tsigs_meta) do
            if v == input:getTsigName():toStringNoDot()
            then
                pdnslog("allowed tsig " .. v .. " checking IPs")
                local allowed_dnsupdate_from_meta = get_meta(zone, 'ALLOW-DNSUPDATE-FROM')
                pdnslog("Allowed signed dnsupdate-from" .. table.concat(allowed_dnsupdate_from_meta, ", "))
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
    pdnslog("Allowed unsigned updates from: " .. table.concat(unsigned_from, ", "))
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
