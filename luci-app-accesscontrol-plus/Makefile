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
