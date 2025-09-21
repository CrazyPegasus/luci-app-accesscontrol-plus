local uci = luci.model.uci.cursor()

a = Map("miaplus")
a.title = translate("Internet Access Schedule Control Plus")
a.description = translate("Access Schedule Control Description")

a:section(SimpleSection).template = "miaplus/miaplus_status"

t = a:section(TypedSection, "basic")
t.anonymous = true

e = t:option(Flag, "enable", translate("Enabled"))
e.rmempty = false

e = t:option(Flag, "strict", translate("Strict Mode"))
e.description = translate("Strict Mode will degrade CPU performance, but it can achieve better results")
e.rmempty = false

e = t:option(Flag, "ipv6enable", translate("IPV6 Enabled"))
e.rmempty = false

e = t:option(Value, "dynamic_update_interval", translate("Dynamic MAC Update Interval (minutes)"))
e.description = translate("Update interval for dynamic MAC addresses (1-60 minutes)")
e.default = "5"
e.rmempty = false
function e.validate(self, value, section)
	local num = tonumber(value)
	if not num or num < 1 or num > 60 then
		return nil, translate("Invalid interval, must be between 1 and 60 minutes")
	end
	return value
end

t = a:section(TypedSection, "macbind", translate("Client Rules"))
t.template = "cbi/tblsection"
t.anonymous = true
t.addremove = true
t.sortable  = true

e = t:option(Flag, "enable", translate("Enabled"))
e.rmempty = false
e.default = "1"

e = t:option(ListValue, "mactype", translate("MAC Type"))
e:value("static", translate("Static MAC"))
e:value("dynamic", translate("Dynamic MAC (by hostname)"))
e.default = "static"
e.rmempty = false

e = t:option(Value, "macaddr", translate("MAC address (Computer Name)"))
e.rmempty = true
luci.sys.net.mac_hints(function(t,a)
e:value(t,"%s (%s)"%{t,a})
end)
e:depends("mactype", "static")

e = t:option(Value, "hostname", translate("Hostname"))
e.description = translate("Device hostname for dynamic MAC identification")
e.rmempty = true
e:depends("mactype", "dynamic")

e = t:option(ListValue, "template", translate("Template"))
uci:foreach("miaplus", "templates",
        function(s)
            e:value(s['.name'],s['title'])
        end)

return a
