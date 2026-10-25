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
  Also ships e87n-metrics (1 Hz metrics JSON + ubus object "e87n")
  and the e87n-sdk headers for custom LVGL programs.
endef

# Pure scripts package: no source to build/compile.
define Build/Compile
endef

define Package/e87n-tools/install
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/bin $(1)/etc/init.d $(1)/etc/config $(1)/sbin $(1)/etc/uci-defaults
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd $(1)/usr/share/e87n-sdk
	$(INSTALL_BIN) \
		./files/usr/sbin/fan-control \
		$(1)/usr/sbin/fan-control
	$(INSTALL_BIN) \
		./files/usr/sbin/e87n-prep-overlay \
		$(1)/usr/sbin/e87n-prep-overlay
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
	$(INSTALL_BIN) \
		./files/etc/init.d/bootlog \
		$(1)/etc/init.d/bootlog
	$(INSTALL_BIN) \
		./files/etc/init.d/raguard \
		$(1)/etc/init.d/raguard
	$(INSTALL_BIN) \
		./files/etc/uci-defaults/99-e87n-hnat \
		$(1)/etc/uci-defaults/99-e87n-hnat
	$(INSTALL_BIN) \
		./files/etc/uci-defaults/97-e87n-net-defaults \
		$(1)/etc/uci-defaults/97-e87n-net-defaults
	$(INSTALL_BIN) \
		./files/usr/sbin/e87n-metrics \
		$(1)/usr/sbin/e87n-metrics
	$(INSTALL_BIN) \
		./files/usr/sbin/e87n-theme \
		$(1)/usr/sbin/e87n-theme
	$(INSTALL_BIN) \
		./files/usr/sbin/e87n-saying \
		$(1)/usr/sbin/e87n-saying
	$(INSTALL_BIN) \
		./files/etc/init.d/e87n-saying \
		$(1)/etc/init.d/e87n-saying
	$(INSTALL_BIN) \
		./files/usr/libexec/rpcd/e87n \
		$(1)/usr/libexec/rpcd/e87n
	$(INSTALL_BIN) \
		./files/etc/init.d/e87n-metrics \
		$(1)/etc/init.d/e87n-metrics
	$(INSTALL_BIN) \
		./files/etc/uci-defaults/98-e87n-metrics \
		$(1)/etc/uci-defaults/98-e87n-metrics
	$(INSTALL_DATA) \
		./files/etc/config/fan \
		$(1)/etc/config/fan
	$(INSTALL_DATA) \
		./files/etc/config/screen \
		$(1)/etc/config/screen
	$(INSTALL_DATA) \
		$(TOPDIR)/../docs/sdk/e87n_metrics.h \
		$(1)/usr/share/e87n-sdk/e87n_metrics.h
	$(INSTALL_DATA) \
		$(TOPDIR)/../docs/sdk/e87n_metrics.c \
		$(1)/usr/share/e87n-sdk/e87n_metrics.c
endef

$(eval $(call BuildPackage,e87n-tools))
