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
	# 演示主题源码：仓库根的 themes/aurora（只拷源码，不拷它自己的 lv_conf.h）
	# 注意：这里用显式文件列表，不要写成 for 循环 + $$f。
	# Makefile 经过递归 make 时会二次展开，$$f 变空导致拷贝整个目录。
	if [ -f $(TOPDIR)/../themes/aurora/main.c ]; then \
		$(INSTALL_DIR) $(PKG_BUILD_DIR)/themes/aurora; \
		$(CP) $(TOPDIR)/../themes/aurora/main.c \
		      $(TOPDIR)/../themes/aurora/e87n_metrics.c \
		      $(TOPDIR)/../themes/aurora/e87n_metrics.h \
		      $(PKG_BUILD_DIR)/themes/aurora/; \
		echo "theme sources:"; ls $(PKG_BUILD_DIR)/themes/aurora/; \
	else \
		echo "FATAL: $(TOPDIR)/../themes/aurora/main.c missing"; exit 1; \
	fi
endef

define Package/e87n-display/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/e87n-display $(1)/usr/bin/e87n-display
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/e87n-display.init $(1)/etc/init.d/e87n-display
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/e87n-display.config $(1)/etc/config/e87n-display
	# 中文点阵字体（GB2312 子集，运行期用 tiny_ttf 加载）：
	# 内置界面和自定义主题都读它，换主题/删主题都不会缺字
	$(INSTALL_DIR) $(1)/usr/share/e87n
	$(INSTALL_DATA) ./files/usr/share/e87n/font.ttf $(1)/usr/share/e87n/font.ttf
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./files/etc/uci-defaults/95-e87n-theme-seed $(1)/etc/uci-defaults/95-e87n-theme-seed
	# 内置演示主题：装在只读分区（/usr/share），首次启动由 uci-defaults 播种到
	# /etc/e87n-display/themes/，这样刷机后主题不会消失
	if [ -f $(PKG_BUILD_DIR)/bin/aurora ]; then \
		$(INSTALL_DIR) $(1)/usr/share/e87n/themes/aurora; \
		$(INSTALL_BIN) $(PKG_BUILD_DIR)/bin/aurora $(1)/usr/share/e87n/themes/aurora/app; \
		$(INSTALL_DATA) $(TOPDIR)/../themes/aurora/theme.json $(1)/usr/share/e87n/themes/aurora/theme.json; \
	fi
endef

$(eval $(call BuildPackage,e87n-display))