include $(TOPDIR)/rules.mk

PKG_NAME:=e87n-tools
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/e87n-tools
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=E87N fan control + screen control tools
  URL:=https://github.com/micmtop/istoreos-for-edgepi-e87n
  DEPENDS:=+busybox
endef

define Package/e87n-tools/description
  E87N fan control daemon (fan-control) + CLI (fanctl) +
  screen backlight utility (screen-ctl) with UCI configs.
endef

# Pure scripts package: no source to build/compile.
define Build/Compile
endef

define Package/e87n-tools/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config $(1)/sbin
	$(INSTALL_BIN) \
		./files/usr/sbin/fan-control \
		$(1)/usr/sbin/fan-control
	$(INSTALL_BIN) \
		./files/usr/sbin/screen-ctl \
		$(1)/usr/sbin/screen-ctl
	$(INSTALL_BIN) \
		./files/usr/bin/fanctl \
		$(1)/usr/bin/fanctl
	$(INSTALL_BIN) \
		./files/sbin/cpuinfo \
		$(1)/sbin/cpuinfo
	$(INSTALL_BIN) \
		./files/etc/init.d/fan \
		$(1)/etc/init.d/fan
	$(INSTALL_BIN) \
		./files/etc/init.d/screen \
		$(1)/etc/init.d/screen
	$(INSTALL_DATA) \
		./files/etc/config/fan \
		$(1)/etc/config/fan
	$(INSTALL_DATA) \
		./files/etc/config/screen \
		$(1)/etc/config/screen
endef

$(eval $(call BuildPackage,e87n-tools))