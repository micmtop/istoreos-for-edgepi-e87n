include $(TOPDIR)/rules.mk

PKG_NAME:=mt7987-2p5g-phy-firmware
PKG_VERSION:=1
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define Package/mt7987-2p5g-phy-firmware
  SECTION:=firmware
  CATEGORY:=Firmware
  TITLE:=MT7987 built-in 2.5G Ethernet PHY firmware
  URL:=https://github.com/istoreos/istoreos
endef

define Package/mt7987-2p5g-phy-firmware/description
  Firmware blobs for the MT7987 built-in 2.5G Ethernet PHY
  (i2p5ge-phy-pmb.bin / i2p5ge-phy-DSPBitTb.bin). Required by the
  mtk-2p5ge driver so the WAN (gmac1/eth1) port can train the link.
endef

# Pure data package: no source to build/compile.
define Build/Compile
endef

define Package/mt7987-2p5g-phy-firmware/install
	$(INSTALL_DIR) $(1)/lib/firmware/mediatek/mt7987
	$(INSTALL_DATA) \
		./files/mt7987/i2p5ge-phy-pmb.bin \
		$(1)/lib/firmware/mediatek/mt7987/i2p5ge-phy-pmb.bin
	$(INSTALL_DATA) \
		./files/mt7987/i2p5ge-phy-DSPBitTb.bin \
		$(1)/lib/firmware/mediatek/mt7987/i2p5ge-phy-DSPBitTb.bin
endef

$(eval $(call BuildPackage,mt7987-2p5g-phy-firmware))
