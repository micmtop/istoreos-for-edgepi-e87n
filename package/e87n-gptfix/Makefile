include $(TOPDIR)/rules.mk

PKG_NAME:=e87n-gptfix
PKG_VERSION:=1
PKG_RELEASE:=1
PKG_LICENSE:=MIT

PKG_BUILD_DIR := $(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/e87n-gptfix
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=E87N GPT helper (shrink p5, create p6 overlay partition)
  DEPENDS:=+libc
endef

define Package/e87n-gptfix/description
  Reads and rewrites the eMMC GPT with correct CRCs. The factory image ships a
  corrupt backup GPT, so parted refuses to modify the table; this helper writes
  both tables itself. Used once to move the overlay onto its own partition.
endef

define Build/Prepare
	$(INSTALL_DIR) $(PKG_BUILD_DIR)
	$(CP) ./src/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) -o $(PKG_BUILD_DIR)/e87n-gptfix $(PKG_BUILD_DIR)/gptfix.c
endef

define Package/e87n-gptfix/install
	$(INSTALL_DIR) $(1)/usr/sbin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/e87n-gptfix $(1)/usr/sbin/e87n-gptfix
endef

$(eval $(call BuildPackage,e87n-gptfix))
