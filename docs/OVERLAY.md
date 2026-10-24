# E87N 的 overlay 设计与换分区记录

记录 2026-10 这次 overlay 不持久的问题：现象、定位过程、最终改法和以后怎么验。

## 现象

改过的配置重启就回默认，装的软件、导入的主题也消失。dmesg 每次都有：

```
mount_root: overlay filesystem has not been fully initialized yet
mount_root: switching to f2fs overlay
```

SSH 主机密钥每次重启都变（`authorized_keys` 丢失，只能空密码登录）。

## 定位过程

按「同一次重启、不同存储位置」做对照：

| 存储位置 | 重启后数据 | 结论 |
|---|---|---|
| p2 直接分区，ext4 | 保住 | 分区直挂没问题 |
| p2 上的 ext4 文件 + loop | 保住 | 文件后备的 loop 没问题 |
| p5 尾部 + loop + f2fs | 丢 | 出问题的路径 |
| p5 尾部 + loop + ext4 | 丢 | 换文件系统无效 |

补充证据：

- p2、p5 的 300 MB / 3 GB / 7 GB 位置裸写 512 字节并 `fsync`，重启后都在 → eMMC 正常。
- 写 16 MB 后 `drop_caches` 再读裸设备，内容确实是新的 → 数据到了 flash。
- f2fs 的 UUID 稳定、checkpoint 版本每次递增 → 文件系统没被重建。

结论：写入能到设备，但重启后这条「跨分区偏移的 loop + 文件系统」路径恢复不出内容，fstools 把空文件系统当成首次启动，重跑 uci-defaults。

## 改法

给 overlay 一个独立分区，不再走 loop。

p5 缩到 512 MB（squashfs 只占 19.6 MB），空出来的空间建 p6：

| 分区 | 起止（扇区） | 大小 | 用途 |
|---|---|---|---|
| p5 | 87040～1135615 | 512 MB | squashfs 根 |
| p6 | 1135616～15269854 | 6.7 GB | overlay，ext4，GPT 名 `rootfs_data` |

固件侧只改一个文件：`files/etc/config/fstab` 增加 extroot 条目，`apply.sh` 把它装进
base-files。没有 p6 的机器上这条 mount 会失败，fstools 退回原来的 loop 方案，不影响启动。

```uci
config mount
	option target '/overlay'
	option device '/dev/mmcblk0p6'
	option fstype 'ext4'
	option enabled '1'
```

## 一次性改分区的步骤

只在没做过这个改动的机器上执行一次。动之前先备份：

```bash
mkdir -p /tmp/gpt
dd if=/dev/mmcblk0 bs=512 count=34 of=/tmp/gpt/gpt_head.bin
dd if=/dev/mmcblk0 bs=512 skip=$((15269888-34)) count=34 of=/tmp/gpt/gpt_tail.bin
dd if=/dev/mmcblk0p1 of=/tmp/gpt/p1.bin
dd if=/dev/mmcblk0p2 of=/tmp/gpt/p2.bin
dd if=/dev/mmcblk0p4 of=/tmp/gpt/p4.bin
sha256sum /dev/mmcblk0p3          # 记下来，全程不能变
```

如果 `parted print` 报 `The backup GPT table is corrupt`，先重建备份表：
备份头放在最后一个 LBA，条目表放在它前面 32 个扇区，CRC 要重算。
修好后 `parted print` 不再报错。

改分区（`parted -s` 不会回答危险操作的确认，必须用 `---pretend-input-tty` 喂 `Yes`）：

```bash
printf 'Yes\n' | parted ---pretend-input-tty /dev/mmcblk0 unit s resizepart 5 1135615s
printf 'Yes\n' | parted ---pretend-input-tty /dev/mmcblk0 unit s mkpart primary ext4 1135616s 100%
parted -s /dev/mmcblk0 unit s name 6 rootfs_data
mknod /dev/mmcblk0p6 b 179 6      # 内核没来得及重读分区表时手工建节点
mkfs.ext4 -q -FF -L rootfs_data /dev/mmcblk0p6
```

做完核对：`sha256sum /dev/mmcblk0p3` 与备份值一致，`head -c 4 /dev/mmcblk0p4` 是 `d00dfeed`。

## 验证持久化

刷入带 extroot 配置的固件后：

```bash
grep ' /overlay ' /proc/mounts        # 应为 /dev/mmcblk0p6 ext4
uci set fan.global.hysteresis=9 && uci commit
touch /root/persist-test && sync
reboot
# 重启后
cat /root/persist-test                # 应该还在
uci get fan.global.hysteresis         # 应该是 9
dmesg | grep -i 'switched to extroot' # 应出现
```

断电再验一次：`poweroff`，拔电源等 10 秒，上电后重复上面的检查。
