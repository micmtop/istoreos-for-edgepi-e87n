include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-e87n
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-e87n
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=E87N fan + screen control
  URL:=https://github.com/micmtop/istoreos-for-edgepi-e87n
  DEPENDS:=+luci-base +e87n-tools +e87n-display
endef

define Package/luci-app-e87n/description
  E87N fan control (auto/manual/off) and screen control
  (on/off + content page + live preview) through LuCI.
endef

define Package/luci-app-e87n/postinst
#!/bin/sh
# enable menu ACL for root (LuCI caches ACLs in rpcd)
if [ -x /etc/init.d/rpcd ]; then
    /etc/init.d/rpcd restart >/dev/null 2>&1 || true
fi
exit 0
endef

define Package/luci-app-e87n/install
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) \
		./files/usr/share/luci/menu.d/e87n.json \
		$(1)/usr/share/luci/menu.d/e87n.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) \
		./files/usr/share/rpcd/acl.d/luci-app-e87n.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-e87n.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/e87n
	$(INSTALL_DATA) \
		./files/www/luci-static/resources/view/e87n/overview.js \
		$(1)/www/luci-static/resources/view/e87n/overview.js
	$(INSTALL_DATA) \
		./files/www/luci-static/resources/e87n.js \
		$(1)/www/luci-static/resources/e87n.js
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) \
		./files/www/cgi-bin/e87n \
		$(1)/www/cgi-bin/e87n
endef

$(eval $(call BuildPackage,luci-app-e87n))