#!/bin/bash

# 增强版 OpenWrt 访问控制插件生成器
# 支持静态和动态MAC地址控制

set -e  # 遇到错误立即退出
set -u  # 使用未定义变量时退出

echo "=== 开始创建 Enhanced OpenWrt Access Control Plugin ==="
rm -rf ./package/luci-app-accesscontrol-plus
# 创建目录结构
echo "步骤 1: 创建目录结构..."
mkdir -p ./package/luci-app-accesscontrol-plus/luasrc/controller
mkdir -p ./package/luci-app-accesscontrol-plus/luasrc/view/miaplus
mkdir -p ./package/luci-app-accesscontrol-plus/luasrc/model/cbi
mkdir -p ./package/luci-app-accesscontrol-plus/root/etc/config
mkdir -p ./package/luci-app-accesscontrol-plus/root/etc/uci-defaults
mkdir -p ./package/luci-app-accesscontrol-plus/root/etc/init.d
mkdir -p ./package/luci-app-accesscontrol-plus/root/usr/bin
mkdir -p ./package/luci-app-accesscontrol-plus/root/usr/share/rpcd/acl.d
mkdir -p ./package/luci-app-accesscontrol-plus/po/zh-Hans
echo "目录创建完成 ✓"

# 创建控制器文件
echo "步骤 2: 创建控制器文件..."
cat > ./package/luci-app-accesscontrol-plus/luasrc/controller/miaplus.lua << 'EOF1'
module("luci.controller.miaplus",package.seeall)

function index()
	if not nixio.fs.access("/etc/config/miaplus") then
		return
	end

	entry({"admin", "services", "miaplus"}, cbi("base"), _("Internet Access Schedule Control Plus"), 30).dependent = true
	entry({"admin", "services", "miaplus", "status"}, call("act_status")).leaf = true

	entry({"admin", "services", "miaplus", "base"}, cbi("base"), _("Base Setting"), 40).leaf = true
	entry({"admin", "services", "miaplus", "advanced"}, cbi("advanced"), _("Advance Setting"), 50).leaf = true
	entry({"admin", "services", "miaplus", "template"}, cbi("template"), nil).leaf = true
	entry({"admin", "services", "miaplus", "update_dynamic_mac"}, call("act_update_dynamic_mac")).leaf = true
end

function act_status()
	local e = {}
	e.running = luci.sys.call("iptables -L INPUT |grep MIAPLUS >/dev/null") == 0
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end

function act_update_dynamic_mac()
	local result = luci.sys.exec("/usr/bin/update_dynamic_mac.sh")
	local e = {}
	e.result = result
	luci.http.prepare_content("application/json")
	luci.http.write_json(e)
end
EOF1
echo "控制器文件创建完成 ✓"

# 创建状态视图文件
echo "步骤 3: 创建状态视图文件..."
cat > ./package/luci-app-accesscontrol-plus/luasrc/view/miaplus/miaplus_status.htm << 'EOF2'
<script type="text/javascript">//<![CDATA[
XHR.poll(3, '<%=url([[admin]], [[services]], [[miaplus]], [[status]])%>', null,
	function(x, data) {
		var tb = document.getElementById('miaplus_status');
		if (data && tb) {
			if (data.running) {
				var links = '<em><b><font color=green><%:Internet Access Schedule Control Plus%> <%:RUNNING%></font></b></em>';
				tb.innerHTML = links;
			} else {
				tb.innerHTML = '<em><b><font color=red><%:Internet Access Schedule Control Plus%> <%:NOT RUNNING%></font></b></em>';
			}
		}
	}
);

function updateDynamicMAC() {
	XHR.get('<%=url([[admin]], [[services]], [[miaplus]], [[update_dynamic_mac]])%>', null,
		function(x, data) {
			if (data && data.result) {
				alert('<%:Dynamic MAC update completed%>: ' + data.result);
			}
		}
	);
}
//]]>
</script>
<style>.mar-10 {margin-left: 50px; margin-right: 10px;}</style>
<fieldset class="cbi-section">
	<p id="miaplus_status">
		<em><%:Collecting data...%></em>
	</p>
	<div style="margin-top: 10px;">
		<input type="button" value="<%:Update Dynamic MAC%>" onclick="updateDynamicMAC()" class="btn cbi-button" />
	</div>
</fieldset>
EOF2
echo "状态视图文件创建完成 ✓"

# 创建高级设置CBI文件
echo "步骤 4: 创建高级设置CBI文件..."
cat > ./package/luci-app-accesscontrol-plus/luasrc/model/cbi/advanced.lua << 'EOF3'
local ds = require "luci.dispatcher"

a = Map("miaplus")

t = a:section(TypedSection, "templates")
t.template = "cbi/tblsection"
t.anonymous = true
t.addremove = true
t.sortable  = true
t.extedit   = ds.build_url("admin/services/miaplus/template/%s")

e = t:option(Flag, "enable", translate("Enabled"))
e.rmempty = false
e.default = "1"

e = t:option(Value, "title", translate("Template"))
e.width = "40%"
e.optional = false
e.default = "default"

return a
EOF3
echo "高级设置CBI文件创建完成 ✓"

# 创建基本设置CBI文件
echo "步骤 5: 创建基本设置CBI文件..."
cat > ./package/luci-app-accesscontrol-plus/luasrc/model/cbi/base.lua << 'EOF4'
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
EOF4
echo "基本设置CBI文件创建完成 ✓"

# 创建模板CBI文件
echo "步骤 6: 创建模板CBI文件..."
cat > ./package/luci-app-accesscontrol-plus/luasrc/model/cbi/template.lua << 'EOF5'
a = Map("miaplus")

local section = arg[1]

t = a:section(TypedSection, section, translate("Rules"))
t.template = "cbi/tblsection"
t.anonymous = true
t.addremove = true
t.sortable  = true

e = t:option(Flag, "enable", translate("Enabled"))
e.rmempty = false
e.default = "1"

e = t:option(Value, "timeon", translate("Start time"))
e.optional = false
e.default = "00:00"

e = t:option(Value, "timeoff", translate("End time"))
e.optional=false
e.default = "23:59"

e = t:option(Flag, "z1", translate("Mon"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z2", translate("Tue"))
e.rmempty = true
e.default=1

e = t:option(Flag, "z3", translate("Wed"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z4", translate("Thu"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z5", translate("Fri"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z6", translate("Sat"))
e.rmempty = true
e.default = 1

e = t:option(Flag, "z7", translate("Sun"))
e.rmempty = true
e.default = 1

return a
EOF5
echo "模板CBI文件创建完成 ✓"

# 创建配置文件
echo "步骤 7: 创建配置文件..."
cat > ./package/luci-app-accesscontrol-plus/root/etc/miaplus.include << 'EOF6'
/etc/init.d/miaplus restart
EOF6

cat > ./package/luci-app-accesscontrol-plus/root/etc/config/miaplus << 'EOF7'

config basic
	option enable '0'
	option strict '0'
	option ipv6enable '0'
	option dynamic_update_interval '15'

config templates
    option enable '0'
    option title 'default'
EOF7
echo "配置文件创建完成 ✓"

# 创建UCI默认设置文件
echo "步骤 8: 创建UCI默认设置文件..."
cat > ./package/luci-app-accesscontrol-plus/root/etc/uci-defaults/luci-miaplus << 'EOF8'
#!/bin/sh
uci -q batch <<-UCIBATCH >/dev/null
	delete ucitrack.@miaplus[-1]
	add ucitrack miaplus
	set ucitrack.@miaplus[-1].init=miaplus
	set ucitrack.@miaplus[-1].exec='/etc/init.d/miaplus reload'
	set ucitrack.@miaplus[-1].exec='/etc/init.d/miaplus restart'
	commit ucitrack
	delete firewall.miaplus
	set firewall.miaplus=include
	set firewall.miaplus.type=script
	set firewall.miaplus.path=/etc/miaplus.include
	set firewall.miaplus.reload=1
	commit firewall
UCIBATCH
rm -f /tmp/luci-indexcache
exit 0
EOF8
echo "UCI默认设置文件创建完成 ✓"

# 创建主服务脚本
echo "步骤 9: 创建主服务脚本..."
cat > ./package/luci-app-accesscontrol-plus/root/etc/init.d/miaplus << 'EOF9'
#!/bin/sh /etc/rc.common
#
# Copyright (C) 2015 OpenWrt-dist
#
# This is free software, licensed under the GNU General Public License v3.
# See /LICENSE for more information.
#

START=30

CONFIG=miaplus
DYNAMIC_MAC_CACHE="/tmp/miaplus_dynamic_mac.cache"

uci_export_section_name() {
  local ret=$(uci -n export $CONFIG | grep "config $1" | awk '{print $3}' | awk -F\' '{print $2}')
  echo ${ret:=$2}
}

uci_get_by_name() {
	local ret=$(uci get $CONFIG.$1.$2 2>/dev/null)
	echo ${ret:=$3}
}

uci_get_by_type() {
	local index=0
	if [ -n "$4" ]; then
		index=$4
	fi
	local ret=$(uci get $CONFIG.@$1[$index].$2 2>/dev/null)
	echo ${ret:=$3}
}

# 获取主机名对应的MAC地址
get_mac_by_hostname() {
	local hostname="$1"
	local mac=""
	
	# 从多个源查找MAC地址
	# 1. 从ARP表查找
	mac=$(cat /proc/net/arp | grep -i "$hostname" | awk '{print $4}' | head -1)
	
	# 2. 如果ARP表没找到，从DHCP lease文件查找
	if [ -z "$mac" ] && [ -f "/tmp/dhcp.leases" ]; then
		mac=$(cat /tmp/dhcp.leases | grep -i "$hostname" | awk '{print $2}' | head -1)
	fi
	
	# 3. 从/proc/net/arp中按IP匹配主机名
	if [ -z "$mac" ]; then
		local ip=$(nslookup "$hostname" 2>/dev/null | grep "Address" | tail -1 | awk '{print $3}')
		if [ -n "$ip" ]; then
			mac=$(cat /proc/net/arp | grep "$ip" | awk '{print $4}' | head -1)
		fi
	fi
	
	# 验证MAC地址格式
	if echo "$mac" | grep -qE '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$'; then
		echo "$mac"
	fi
}

# 更新动态MAC缓存
update_dynamic_mac_cache() {
	echo "# Dynamic MAC Cache - $(date)" > "$DYNAMIC_MAC_CACHE.tmp"
	
	for i in $(seq 0 100); do
		local enable=$(uci_get_by_type macbind enable '' $i)
		local mactype=$(uci_get_by_type macbind mactype '' $i)
		local hostname=$(uci_get_by_type macbind hostname '' $i)
		local template=$(uci_get_by_type macbind template '' $i)
		
		if [ -z "$enable" ] || [ -z "$mactype" ] || [ -z "$template" ]; then
			break
		fi
		
		if [ "$enable" == "1" ] && [ "$mactype" == "dynamic" ] && [ -n "$hostname" ]; then
			local mac=$(get_mac_by_hostname "$hostname")
			if [ -n "$mac" ]; then
				echo "$hostname|$mac|$template" >> "$DYNAMIC_MAC_CACHE.tmp"
			else
				logger -t miaplus "Warning: Cannot find MAC for hostname: $hostname"
			fi
		fi
	done
	
	mv "$DYNAMIC_MAC_CACHE.tmp" "$DYNAMIC_MAC_CACHE"
}

uci_get_mac_by_template() {
	local template_name="$1"
	local ret=""
	
	# 处理静态MAC
	for i in $(seq 0 100); do
		local enable=$(uci_get_by_type macbind enable '' $i)
		local mactype=$(uci_get_by_type macbind mactype 'static' $i)
		local macaddr=$(uci_get_by_type macbind macaddr '' $i)
		local template=$(uci_get_by_type macbind template '' $i)
		
		if [ -z "$enable" ] || [ -z "$template" ]; then
			break
		fi
		
		if [ "$enable" == "1" ] && [ "$mactype" == "static" ] && [ -n "$macaddr" ]; then
			if [ -z "$template_name" ] || [ "$template" == "$template_name" ]; then
				if [ "$ret" == "" ]; then
					ret="$macaddr"
				else
					ret="$ret $macaddr"
				fi
			fi
		fi
	done
	
	# 处理动态MAC
	if [ -f "$DYNAMIC_MAC_CACHE" ]; then
		while IFS='|' read -r hostname mac template; do
			if [ -n "$hostname" ] && [ -n "$mac" ] && [ -n "$template" ]; then
				if [ -z "$template_name" ] || [ "$template" == "$template_name" ]; then
					if [ "$ret" == "" ]; then
						ret="$mac"
					else
						ret="$ret $mac"
					fi
				fi
			fi
		done < "$DYNAMIC_MAC_CACHE"
	fi
	
	echo "${ret:=$2}"
}

add_rules(){
  local sections=$(uci_export_section_name templates '')
  if [ -n "$sections" ]; then
    for s in $sections
    do
      #local enable=$(uci_get_by_name $s enable '' $i)
      #local title=$(uci_get_by_name $s title '' $i)
	  local enable=$(uci_get_by_name $s enable '')
      local title=$(uci_get_by_name $s title '')
      if [ -z $enable ]; then
        break
      fi
      if [ "$enable" == "1" ]; then
        add_rule $s
      fi
    done
  fi
}

add_rule(){
  ipv6enable=$(uci get miaplus.@basic[0].ipv6enable 2>/dev/null)
  [ -z "$ipv6enable" ] && ipv6enable=0
  
  local macaddrs=$(uci_get_mac_by_template $1 '')
  if [ -z "$macaddrs" ]; then
    return 0
  fi
  
  for macaddr in $macaddrs
  do
    iptables -t filter -A MIAPLUS  -m mac --mac-source $macaddr -j DROP
    [ $ipv6enable -eq 1 ] && ip6tables -t filter -A MIAPLUS  -m mac --mac-source $macaddr -j DROP
  done
  
  for i in $(seq 0 100)
  do
    local enable=$(uci_get_by_type $1 enable '' $i)
    local timeon=$(uci_get_by_type $1 timeon '' $i)
    local timeoff=$(uci_get_by_type $1 timeoff '' $i)
    local z1=$(uci_get_by_type $1 z1 '' $i)
    local z2=$(uci_get_by_type $1 z2 '' $i)
    local z3=$(uci_get_by_type $1 z3 '' $i)
    local z4=$(uci_get_by_type $1 z4 '' $i)
    local z5=$(uci_get_by_type $1 z5 '' $i)
    local z6=$(uci_get_by_type $1 z6 '' $i)
    local z7=$(uci_get_by_type $1 z7 '' $i)
    
    [ "$z1" == "1" ] && Z1="Mon,"
    [ "$z2" == "1" ] && Z2="Tue,"
    [ "$z3" == "1" ] && Z3="Wed,"
    [ "$z4" == "1" ] && Z4="Thu,"
    [ "$z5" == "1" ] && Z5="Fri,"
    [ "$z6" == "1" ] && Z6="Sat,"
    [ "$z7" == "1" ] && Z7="Sun"

    if [ -z $enable ] || [ -z $timeoff ] || [ -z $timeon ]; then
      break
    fi
    
    if [ "$enable" == "1" ]; then
      for macaddr in $macaddrs
      do
        iptables -t filter -I MIAPLUS  -m mac --mac-source $macaddr -m time --kerneltz --timestart $timeon --timestop $timeoff --weekdays $Z1$Z2$Z3$Z4$Z5$Z6$Z7 -j ACCEPT
        [ $ipv6enable -eq 1 ] && ip6tables -t filter -I MIAPLUS  -m mac --mac-source $macaddr -m time --kerneltz --timestart $timeon --timestop $timeoff --weekdays $Z1$Z2$Z3$Z4$Z5$Z6$Z7 -j ACCEPT
      done
    fi
    
    for n in $(seq 1 7)
    do
      unset "Z$n"
    done
  done
}

setup_cron() {
	local interval=$(uci get miaplus.@basic[0].dynamic_update_interval 2>/dev/null)
	[ -z "$interval" ] && interval=5
	
	# 移除旧的cron任务
	crontab -l 2>/dev/null | grep -v "update_dynamic_mac.sh" | crontab -
	
	# 添加新的cron任务
	(crontab -l 2>/dev/null; echo "*/$interval * * * * /usr/bin/update_dynamic_mac.sh >/dev/null 2>&1") | crontab -
}

remove_cron() {
	crontab -l 2>/dev/null | grep -v "update_dynamic_mac.sh" | crontab -
}

start(){
  stop
  enable=$(uci get miaplus.@basic[0].enable 2>/dev/null)
  [ -z "$enable" ] && enable=0
  [ $enable -eq 0 ] && exit 0
  
  # 更新动态MAC缓存
  update_dynamic_mac_cache
  
  # 设置cron任务
  setup_cron
  
  iptables -t filter -N MIAPLUS 2>/dev/null || iptables -t filter -F MIAPLUS
  iptables -I INPUT -p udp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS
  iptables -I INPUT -p tcp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS
  iptables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control"
  iptables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control"
  
  strict=$(uci get miaplus.@basic[0].strict 2>/dev/null)
  [ -z "$strict" ] && strict=0
  [ $strict -eq 1 ] && iptables -t filter -I FORWARD -m comment --comment "Rule For Control" -j MIAPLUS

  ipv6enable=$(uci get miaplus.@basic[0].ipv6enable 2>/dev/null)
  [ -z "$ipv6enable" ] && ipv6enable=0
  if [ "$ipv6enable" -eq 1 ]; then
    ip6tables -t filter -N MIAPLUS
    ip6tables -I INPUT -p udp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS
    ip6tables -I INPUT -p tcp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS
    ip6tables -t nat -A PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control"
    ip6tables -t nat -A PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control"
    [ $strict -eq 1 ] && ip6tables -t filter -I FORWARD -m comment --comment "Rule For Control" -j MIAPLUS
  fi
  
  add_rules
}

stop(){
  # 移除cron任务
  remove_cron
  
  # 清理iptables规则
  iptables -t filter -D FORWARD -m comment --comment "Rule For Control" -j MIAPLUS 2>/dev/null
  iptables -D INPUT -p udp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS 2>/dev/null
  iptables -D INPUT -p tcp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS 2>/dev/null
  iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control" 2>/dev/null
  iptables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control" 2>/dev/null
  iptables -t filter -F MIAPLUS 2>/dev/null
  iptables -t filter -X MIAPLUS 2>/dev/null

  notfound=$(type ip6tables 2>&1 | grep not)
  if [ -z "$notfound" ]; then
    ip6tables -t filter -D FORWARD -m comment --comment "Rule For Control" -j MIAPLUS 2>/dev/null
    ip6tables -D INPUT -p udp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS 2>/dev/null
    ip6tables -D INPUT -p tcp --dport 53 -m comment --comment "Rule For Control" -j MIAPLUS 2>/dev/null
    ip6tables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control" 2>/dev/null
    ip6tables -t nat -D PREROUTING -p tcp --dport 53 -j REDIRECT --to-ports 53 -m comment --comment "Rule For Control" 2>/dev/null
    ip6tables -t filter -F MIAPLUS 2>/dev/null
    ip6tables -t filter -X MIAPLUS 2>/dev/null
  fi
  
  # 清理缓存文件
  rm -f "$DYNAMIC_MAC_CACHE" "$DYNAMIC_MAC_CACHE.tmp"
}

reload() {
  # 仅更新动态MAC并重新应用规则，不重启整个服务
  enable=$(uci get miaplus.@basic[0].enable 2>/dev/null)
  [ -z "$enable" ] && enable=0
  [ $enable -eq 0 ] && return 0
  
  update_dynamic_mac_cache
  setup_cron
  
  # 清理并重新添加规则
  iptables -t filter -F MIAPLUS 2>/dev/null
  ipv6enable=$(uci get miaplus.@basic[0].ipv6enable 2>/dev/null)
  [ -z "$ipv6enable" ] && ipv6enable=0
  [ $ipv6enable -eq 1 ] && ip6tables -t filter -F MIAPLUS 2>/dev/null
  
  add_rules
}
EOF9
echo "主服务脚本创建完成 ✓"

# 创建动态MAC更新脚本
echo "步骤 10: 创建动态MAC更新脚本..."
cat > ./package/luci-app-accesscontrol-plus/root/usr/bin/update_dynamic_mac.sh << 'EOF10'
#!/bin/sh

# 增强版动态MAC更新脚本
CONFIG=miaplus
DYNAMIC_MAC_CACHE="/tmp/miaplus_dynamic_mac.cache"
LOCK_FILE="/tmp/miaplus_update.lock"
LOG_FILE="/tmp/miaplus_update.log"

# 防止并发执行
if [ -f "$LOCK_FILE" ]; then
    echo "Update already in progress"
    exit 1
fi

touch "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

uci_get_by_type() {
    local index=0
    [ -n "$4" ] && index=$4
    local ret=$(uci get $CONFIG.@$1[$index].$2 2>/dev/null)
    echo ${ret:=$3}
}

# 获取主机名对应的所有MAC地址
get_macs_by_hostname() {
    local hostname="$1"
    local macs=""

    # 从 ARP 表查找所有匹配项
    macs=$(grep -i "$hostname" /proc/net/arp 2>/dev/null | awk '{print $4}' | tr '\n' ' ')

    # DHCP leases
    if [ -f "/tmp/dhcp.leases" ]; then
        dhcp_macs=$(grep -i "$hostname" /tmp/dhcp.leases | awk '{print $2}' | tr '\n' ' ')
        macs="$macs $dhcp_macs"
    fi

    # ping + 再查 ARP
    if [ -z "$macs" ]; then
        ping -c 1 -W 2 "$hostname" >/dev/null 2>&1
        sleep 1
        arp_macs=$(grep -i "$hostname" /proc/net/arp | awk '{print $4}' | tr '\n' ' ')
        macs="$macs $arp_macs"
    fi

    # hostapd_cli
    if [ -z "$macs" ] && [ -f "/var/run/hostapd/wlan0" ]; then
        sta_macs=$(hostapd_cli -i wlan0 all_sta 2>/dev/null | grep "^[0-9a-f]" | awk '{print $1}')
        macs="$macs $sta_macs"
    fi

    # 格式化，去重
    echo "$macs" | tr ' ' '\n' | grep -E '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' | sort -u | tr '\n' ' '
}

# 如果服务未启用直接退出
enable=$(uci get miaplus.@basic[0].enable 2>/dev/null)
[ -z "$enable" ] && enable=0
[ "$enable" -eq 0 ] && exit 0

echo "# Dynamic MAC Cache - $(date)" > "$DYNAMIC_MAC_CACHE.tmp"
echo "==== $(date '+%F %T') Dynamic MAC Update Start ====" >> "$LOG_FILE"

updated_count=0
failed_count=0

# 先备份旧缓存（供比较用）
cp "$DYNAMIC_MAC_CACHE" "$DYNAMIC_MAC_CACHE.old" 2>/dev/null || touch "$DYNAMIC_MAC_CACHE.old"

for i in $(seq 0 100); do
    enable=$(uci_get_by_type macbind enable '' $i)
    mactype=$(uci_get_by_type macbind mactype '' $i)
    hostname=$(uci_get_by_type macbind hostname '' $i)
    template=$(uci_get_by_type macbind template '' $i)

    if [ -z "$enable" ] || [ -z "$mactype" ] || [ -z "$template" ]; then
        break
    fi

    if [ "$enable" = "1" ] && [ "$mactype" = "dynamic" ] && [ -n "$hostname" ]; then
        macs=$(get_macs_by_hostname "$hostname")

        if [ -n "$macs" ]; then
            echo "$hostname|$macs|$template" >> "$DYNAMIC_MAC_CACHE.tmp"
            echo "FOUND $hostname -> $macs" >> "$LOG_FILE"
            logger -t miaplus "Updated MAC for $hostname: $macs"
            updated_count=$((updated_count + 1))
        else
            # 保留旧缓存中的值，避免误封
            old_line=$(grep "^$hostname|" "$DYNAMIC_MAC_CACHE.old" 2>/dev/null || true)
            if [ -n "$old_line" ]; then
                echo "$old_line" >> "$DYNAMIC_MAC_CACHE.tmp"
                echo "MISS $hostname -> keep old entry: $old_line" >> "$LOG_FILE"
                logger -t miaplus "MAC not found for $hostname, kept old value"
            else
                echo "MISS $hostname -> no MAC found" >> "$LOG_FILE"
                logger -t miaplus "Warning: Cannot find MAC for hostname: $hostname"
            fi
            failed_count=$((failed_count + 1))
        fi
    fi
done

# 比较新旧缓存，有变化才替换并 reload
if ! cmp -s "$DYNAMIC_MAC_CACHE.tmp" "$DYNAMIC_MAC_CACHE.old"; then
    mv "$DYNAMIC_MAC_CACHE.tmp" "$DYNAMIC_MAC_CACHE"
    logger -t miaplus "Dynamic MAC cache changed, reloading rules"
    /etc/init.d/miaplus reload >/dev/null 2>&1
    echo "CACHE UPDATED -> iptables reloaded" >> "$LOG_FILE"
else
    rm -f "$DYNAMIC_MAC_CACHE.tmp"
    echo "CACHE UNCHANGED -> skip reload" >> "$LOG_FILE"
fi

echo "==== Update Done: $updated_count updated, $failed_count failed ====" >> "$LOG_FILE"
rm -f "$DYNAMIC_MAC_CACHE.old"

EOF10
echo "动态MAC更新脚本创建完成 ✓"

# 创建RPCD权限文件
echo "步骤 11: 创建RPCD权限文件..."
cat > ./package/luci-app-accesscontrol-plus/root/usr/share/rpcd/acl.d/luci-app-accesscontrol-plus.json << 'EOF11'
{
	"luci-app-accesscontrol-plus": {
		"description": "Grant UCI access for luci-app-accesscontrol-plus",
		"read": {
			"uci": [ "miaplus" ],
			"file": {
				"/tmp/miaplus_dynamic_mac.cache": [ "read" ],
				"/proc/net/arp": [ "read" ],
				"/tmp/dhcp.leases": [ "read" ]
			}
		},
		"write": {
			"uci": [ "miaplus" ],
			"file": {
				"/tmp/miaplus_dynamic_mac.cache": [ "write" ]
			}
		},
		"exec": {
			"/usr/bin/update_dynamic_mac.sh": [ "exec" ]
		}
	}
}
EOF11
echo "RPCD权限文件创建完成 ✓"

# 创建中文翻译文件
echo "步骤 12: 创建中文翻译文件..."
cat > ./package/luci-app-accesscontrol-plus/po/zh-Hans/miaplus.po << 'EOF12'
msgid "Internet Access Schedule Control Plus"
msgstr "上网时间控制Plus"

msgid "Access Schedule Control Description"
msgstr "设置客户端访问互联网的时间"

msgid "General switch"
msgstr "开启/关闭"

msgid "Strict Mode"
msgstr "严格模式"

msgid "Strict Mode will degrade CPU performance, but it can achieve better results"
msgstr "严格模式会损耗部分CPU资源，但可以按照时间规则立即拦截数据包，效果更好"

msgid "Client Rules"
msgstr "客户端规则"

msgid "Description"
msgstr "描述"

msgid "MAC address (Computer Name)"
msgstr "MAC 地址 (主机名)"

msgid "MAC Type"
msgstr "MAC类型"

msgid "Static MAC"
msgstr "静态MAC"

msgid "Dynamic MAC (by hostname)"
msgstr "动态MAC (通过主机名)"

msgid "Hostname"
msgstr "主机名"

msgid "Device hostname for dynamic MAC identification"
msgstr "用于动态MAC识别的设备主机名"

msgid "Dynamic MAC Update Interval (minutes)"
msgstr "动态MAC更新间隔（分钟）"

msgid "Update interval for dynamic MAC addresses (1-60 minutes)"
msgstr "动态MAC地址的更新间隔（1-60分钟）"

msgid "Invalid interval, must be between 1 and 60 minutes"
msgstr "无效间隔，必须在1到60分钟之间"

msgid "Update Dynamic MAC"
msgstr "更新动态MAC"

msgid "Dynamic MAC update completed"
msgstr "动态MAC更新完成"

msgid "Start time"
msgstr "开始时间"

msgid "End time"
msgstr "结束时间"

msgid "Mon"
msgstr "一"

msgid "Tue"
msgstr "二"

msgid "Wed"
msgstr "三"

msgid "Thu"
msgstr "四"

msgid "Fri"
msgstr "五"

msgid "Sat"
msgstr "六"

msgid "Sun"
msgstr "日"

msgid "Template"
msgstr "模板"

msgid "RUNNING"
msgstr "运行中"

msgid "NOT RUNNING"
msgstr "未运行"

msgid "Collecting data..."
msgstr "正在收集数据..."

msgid "IPV6 Enabled"
msgstr "启用IPV6"

msgid "Base Setting"
msgstr "基本设置"

msgid "Advance Setting"
msgstr "高级设置"

msgid "Rules"
msgstr "规则"

msgid "Enabled"
msgstr "启用"

EOF12
echo "中文翻译文件创建完成 ✓"

# 创建Makefile
echo "步骤 13: 创建Makefile..."
cat > ./package/luci-app-accesscontrol-plus/Makefile << 'EOF13'
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Access Control Configuration Plus
LUCI_DEPENDS:=+iptables +ip6tables +coreutils +coreutils-nohup
LUCI_PKGARCH:=all
LUCI_LANG:=zh_Hans
PKG_NAME:=luci-app-accesscontrol-plus
PKG_VERSION:=2.0
PKG_RELEASE:=2

# 这是关键：使用LuCI构建框架
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
EOF13
echo "Makefile创建完成 ✓"

# 设置文件权限
echo "步骤 14: 设置文件权限..."
echo "设置目录权限..."
find ./package/luci-app-accesscontrol-plus -type d -exec chmod 755 {} \;

echo "设置Lua文件权限..."
find ./package/luci-app-accesscontrol-plus/luasrc -name "*.lua" -exec chmod 644 {} \;

echo "设置视图文件权限..."
find ./package/luci-app-accesscontrol-plus/luasrc/view -name "*.htm" -exec chmod 644 {} \;

echo "设置配置文件权限..."
chmod 644 ./package/luci-app-accesscontrol-plus/root/etc/config/miaplus
chmod 644 ./package/luci-app-accesscontrol-plus/root/etc/miaplus.include
chmod 644 ./package/luci-app-accesscontrol-plus/root/usr/share/rpcd/acl.d/luci-app-accesscontrol-plus.json

echo "设置可执行脚本权限..."
chmod 755 ./package/luci-app-accesscontrol-plus/root/etc/uci-defaults/luci-miaplus
chmod 755 ./package/luci-app-accesscontrol-plus/root/etc/init.d/miaplus
chmod 755 ./package/luci-app-accesscontrol-plus/root/usr/bin/update_dynamic_mac.sh

echo "设置翻译文件权限..."
chmod 644 ./package/luci-app-accesscontrol-plus/po/zh-Hans/miaplus.po

echo "设置主Makefile权限..."
chmod 644 ./package/luci-app-accesscontrol-plus/Makefile

echo "文件权限设置完成 ✓"

# 显示最终信息
echo ""
echo "=== Enhanced OpenWrt Access Control Plugin 创建完成! ==="
echo ""
echo "主要功能:"
echo "- 支持静态MAC和动态MAC地址控制"
echo "- 自动MAC地址发现机制（ARP、DHCP、hostapd）"
echo "- 可配置的更新间隔（1-60分钟）"
echo "- 健壮的错误处理和故障恢复"
echo "- 完整的中文界面"
echo "- 手动更新按钮"
echo "- 自动cron任务管理"
echo ""
echo "安装说明:"
echo "1. 将package目录复制到OpenWrt构建环境"
echo "2. 运行: make menuconfig"
echo "3. 选择: LuCI -> Applications -> luci-app-accesscontrol-plus"
echo "4. 构建: make package/luci-app-accesscontrol-plus/compile"
echo ""
echo "使用说明:"
echo "- 静态MAC设备: 选择'静态MAC'并输入MAC地址"
echo "- 动态MAC设备: 选择'动态MAC'并输入主机名"
echo "- 系统会根据配置间隔自动更新动态MAC地址"
echo "- 使用'更新动态MAC'按钮进行手动更新"
echo ""
echo "文件结构验证:"
if [ -d "./package/luci-app-accesscontrol-plus" ]; then
    echo "✓ 主目录存在"
    [ -f "./package/luci-app-accesscontrol-plus/Makefile" ] && echo "✓ Makefile存在"
    [ -f "./package/luci-app-accesscontrol-plus/luasrc/controller/miaplus.lua" ] && echo "✓ 控制器文件存在"
    [ -f "./package/luci-app-accesscontrol-plus/root/etc/init.d/miaplus" ] && echo "✓ 服务脚本存在"
    [ -f "./package/luci-app-accesscontrol-plus/root/usr/bin/update_dynamic_mac.sh" ] && echo "✓ 更新脚本存在"
    [ -f "./package/luci-app-accesscontrol-plus/po/zh-Hans/miaplus.po" ] && echo "✓ 中文翻译存在"
else
    echo "✗ 插件目录创建失败"
    exit 1
fi
echo ""
echo "插件生成完成！可以开始使用了。"