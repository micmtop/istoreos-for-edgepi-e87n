include $(TOPDIR)/rules.mk

PKG_NAME:=e87n-display
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=MIT

# 本地源码：Build/Prepare 将 ./src 拷入 $(PKG_BUILD_DIR)
PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/e87n-display
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=E87N LVGL screen display program
  URL:=https://github.com/micmtop/istoreos-for-edgepi-e87n
  DEPENDS:=+libc +libpthread +libstdcpp
endef

define Package/e87n-display/description
  E87N LCD display program based on LVGL 9.4.
  Renders system overview / time / network chart / status arcs
  to /dev/fb0 and supports cycle mode + custom text via UCI.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) -r ./src/. $(PKG_BUILD_DIR)/
	# 清理 macOS 元数据（如有）
	find $(PKG_BUILD_DIR) -name .DS_Store -delete 2>/dev/null || true
endef

define Package/e87n-display/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/e87n-display $(1)/usr/bin/e87n-display
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/e87n-display.init $(1)/etc/init.d/e87n-display
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/e87n-display.config $(1)/etc/config/e87n-display
endef

$(eval $(call BuildPackage,e87n-display))