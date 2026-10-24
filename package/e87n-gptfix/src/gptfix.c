// E87N GPT 助手：把 p5（rootfs）缩到指定大小，并新建 p6（rootfs_data）当 overlay。
//
// 背景：出厂镜像的备份 GPT 是坏的，parted 因此拒绝写分区表；而 shell 里算不了 CRC32。
// 这个工具直接读写 GPT，自带 CRC32，一次把主表和备份表都写对。
//
// 用法：
//   e87n-gptfix show  /dev/mmcblk0
//   e87n-gptfix prep  /dev/mmcblk0 [p5扇区数=1048576]   # 缩 p5，建 p6
//
// 只动 p5 和新增的 p6；p1~p4 的条目原样保留，写前会打印将要写入的布局。

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/ioctl.h>
#include <linux/fs.h>

#define SECTOR 512
#define GPT_SIG "EFI PART"
#define ENTRIES 128

static const uint8_t LINUX_FS_GUID[16] = {
	0xaf, 0x3d, 0xc6, 0x0f, 0x83, 0x84, 0x72, 0x47,
	0x8e, 0x79, 0x3d, 0x69, 0xd8, 0x47, 0x7d, 0xe4
};

static uint32_t crc_table[256];
static void crc32_init(void)
{
	for (uint32_t i = 0; i < 256; i++) {
		uint32_t c = i;
		for (int k = 0; k < 8; k++)
			c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
		crc_table[i] = c;
	}
}
static uint32_t crc32_buf(const void *buf, size_t len)
{
	const uint8_t *p = buf;
	uint32_t c = 0xFFFFFFFFu;
	while (len--)
		c = crc_table[(c ^ *p++) & 0xFF] ^ (c >> 8);
	return c ^ 0xFFFFFFFFu;
}

static uint32_t le32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint64_t le64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }
static void put32(uint8_t *p, uint32_t v) { memcpy(p, &v, 4); }
static void put64(uint8_t *p, uint64_t v) { memcpy(p, &v, 8); }

static int rd(int fd, void *buf, size_t len, off_t off)
{
	if (pread(fd, buf, len, off) != (ssize_t)len) {
		fprintf(stderr, "read %zu@%lld failed: %s\n", len, (long long)off, strerror(errno));
		return -1;
	}
	return 0;
}
static int wr(int fd, const void *buf, size_t len, off_t off)
{
	if (pwrite(fd, buf, len, off) != (ssize_t)len) {
		fprintf(stderr, "write %zu@%lld failed: %s\n", len, (long long)off, strerror(errno));
		return -1;
	}
	return 0;
}

static void utf16_to_ascii(const uint8_t *name /* 72 bytes */, char *out, size_t outlen)
{
	size_t j = 0;
	for (int i = 0; i < 36 && j + 1 < outlen; i++) {
		uint16_t c = (uint16_t)name[i * 2] | ((uint16_t)name[i * 2 + 1] << 8);
		if (!c)
			break;
		out[j++] = (c < 128) ? (char)c : '?';
	}
	out[j] = 0;
}

static void ascii_to_utf16(const char *in, uint8_t *out /* 72 bytes */)
{
	memset(out, 0, 72);
	for (int i = 0; in[i] && i < 35; i++) {
		out[i * 2] = (uint8_t)in[i];
		out[i * 2 + 1] = 0;
	}
}

struct gpt {
	int fd;
	uint8_t header[1024];      /* 主表头所在扇区 */
	uint8_t entries[ENTRIES * 128];
	uint64_t total_sectors;
	uint64_t last_lba;
	uint64_t first_usable, last_usable;
	uint32_t hdr_size, ent_cnt, ent_size, ent_crc;
	uint64_t ent_lba;
};

static int gpt_load(struct gpt *g, const char *dev)
{
	g->fd = open(dev, O_RDWR);
	if (g->fd < 0) {
		fprintf(stderr, "open %s: %s\n", dev, strerror(errno));
		return -1;
	}
	uint64_t bytes = 0;
	if (ioctl(g->fd, BLKGETSIZE64, &bytes) < 0) {
		/* 普通文件（本地测试用的镜像）走 lseek */
		off_t end = lseek(g->fd, 0, SEEK_END);
		if (end <= 0) {
			fprintf(stderr, "取不到设备大小: %s\n", strerror(errno));
			return -1;
		}
		bytes = (uint64_t)end;
	}
	g->total_sectors = bytes / SECTOR;
	g->last_lba = g->total_sectors - 1;

	if (rd(g->fd, g->header, sizeof(g->header), SECTOR) < 0)
		return -1;
	if (memcmp(g->header, GPT_SIG, 8)) {
		fprintf(stderr, "%s: 主 GPT 头没有 EFI PART 签名\n", dev);
		return -1;
	}
	g->hdr_size = le32(g->header + 12);
	g->first_usable = le64(g->header + 40);
	g->last_usable = le64(g->header + 48);
	g->ent_lba = le64(g->header + 72);
	g->ent_cnt = le32(g->header + 80);
	g->ent_size = le32(g->header + 84);
	g->ent_crc = le32(g->header + 88);
	if (g->ent_cnt != ENTRIES || g->ent_size != 128) {
		fprintf(stderr, "只支持 128 项 x 128 字节的分区表\n");
		return -1;
	}
	if (rd(g->fd, g->entries, sizeof(g->entries), (off_t)g->ent_lba * SECTOR) < 0)
		return -1;
	if (crc32_buf(g->entries, sizeof(g->entries)) != g->ent_crc) {
		fprintf(stderr, "主表的分区项 CRC 不对，拒绝继续\n");
		return -1;
	}
	return 0;
}

static void gpt_show(struct gpt *g)
{
	printf("设备总扇区 %llu，可用 %llu..%llu\n",
	       (unsigned long long)g->total_sectors,
	       (unsigned long long)g->first_usable,
	       (unsigned long long)g->last_usable);
	for (int i = 0; i < ENTRIES; i++) {
		uint8_t *e = g->entries + i * 128;
		int empty = 1;
		for (int k = 0; k < 16; k++)
			if (e[k])
				empty = 0;
		if (empty)
			continue;
		char name[40];
		utf16_to_ascii(e + 56, name, sizeof(name));
		printf("  p%-2d %10llu..%-10llu %-12s\n", i + 1,
		       (unsigned long long)le64(e + 32),
		       (unsigned long long)le64(e + 40), name);
	}
}

static int gpt_write(struct gpt *g)
{
	/* 主表 */
	put32(g->header + 88, crc32_buf(g->entries, sizeof(g->entries)));
	put32(g->header + 16, 0);
	put32(g->header + 16, crc32_buf(g->header, g->hdr_size));
	/* 只写一个扇区：1024 字节会盖到 LBA2（条目表第一扇区） */
	if (wr(g->fd, g->header, SECTOR, SECTOR) < 0)
		return -1;
	if (wr(g->fd, g->entries, sizeof(g->entries), (off_t)g->ent_lba * SECTOR) < 0)
		return -1;

	/* 备份表：条目表在最后 32 个扇区，表头在最后一个扇区 */
	uint8_t bh[1024];
	memset(bh, 0, sizeof(bh));
	memcpy(bh, g->header, g->hdr_size);
	put64(bh + 24, g->last_lba);          /* my_lba */
	put64(bh + 32, 1);                    /* alternate_lba */
	put64(bh + 72, g->last_lba - 32);     /* partition_entry_lba */
	put32(bh + 16, 0);
	put32(bh + 16, crc32_buf(bh, g->hdr_size));
	if (wr(g->fd, g->entries, sizeof(g->entries), (off_t)(g->last_lba - 32) * SECTOR) < 0)
		return -1;
	/* 备份头同样只占最后 1 个扇区，多写会越过设备末尾 */
	if (wr(g->fd, bh, SECTOR, (off_t)g->last_lba * SECTOR) < 0)
		return -1;

	if (fsync(g->fd) < 0) {
		fprintf(stderr, "fsync: %s\n", strerror(errno));
		return -1;
	}
	return 0;
}

static int find_by_name(struct gpt *g, const char *want)
{
	for (int i = 0; i < ENTRIES; i++) {
		uint8_t *e = g->entries + i * 128;
		char name[40];
		utf16_to_ascii(e + 56, name, sizeof(name));
		if (!strcmp(name, want))
			return i;
	}
	return -1;
}

static int gpt_prep(struct gpt *g, uint64_t p5_sectors)
{
	int idx = find_by_name(g, "rootfs");
	if (idx < 0) {
		fprintf(stderr, "找不到名为 rootfs 的分区\n");
		return -1;
	}
	if (find_by_name(g, "rootfs_data") >= 0) {
		printf("已经有 rootfs_data 分区，什么都不做\n");
		return 0;
	}
	uint8_t *p5 = g->entries + idx * 128;
	uint64_t start = le64(p5 + 32);
	uint64_t new_end = start + p5_sectors - 1;
	uint64_t p6_start = new_end + 1;

	if (new_end >= g->last_usable) {
		fprintf(stderr, "p5 要缩到 %llu，但磁盘只剩到 %llu\n",
			(unsigned long long)new_end, (unsigned long long)g->last_usable);
		return -1;
	}
	if (p6_start + 1024 > g->last_usable) {
		fprintf(stderr, "剩余空间不足以建 p6\n");
		return -1;
	}

	/* 找一个空条目 */
	int slot = -1;
	for (int i = 0; i < ENTRIES; i++) {
		uint8_t *e = g->entries + i * 128;
		int empty = 1;
		for (int k = 0; k < 16; k++)
			if (e[k])
				empty = 0;
		if (empty) {
			slot = i;
			break;
		}
	}
	if (slot < 0) {
		fprintf(stderr, "分区表没有空位\n");
		return -1;
	}

	put64(p5 + 40, new_end);

	uint8_t *p6 = g->entries + slot * 128;
	memset(p6, 0, 128);
	memcpy(p6, LINUX_FS_GUID, 16);
	/* 唯一 GUID：读 16 字节随机数，按 RFC4122 v4 打标记 */
	uint8_t rnd[16];
	int rfd = open("/dev/urandom", O_RDONLY);
	if (rfd < 0 || read(rfd, rnd, sizeof(rnd)) != (ssize_t)sizeof(rnd)) {
		fprintf(stderr, "读不到随机数\n");
		return -1;
	}
	close(rfd);
	rnd[6] = (uint8_t)((rnd[6] & 0x0F) | 0x40);
	rnd[8] = (uint8_t)((rnd[8] & 0x3F) | 0x80);
	memcpy(p6 + 16, rnd, 16);
	put64(p6 + 32, p6_start);
	put64(p6 + 40, g->last_usable);
	ascii_to_utf16("rootfs_data", p6 + 56);

	printf("将写入：\n");
	gpt_show(g);
	return 1;
}

int main(int argc, char **argv)
{
	crc32_init();
	if (argc < 2) {
		fprintf(stderr, "用法: %s show <dev> | %s prep <dev> [p5扇区数]\n", argv[0], argv[0]);
		return 2;
	}
	const char *dev = (argc >= 3) ? argv[2] : "/dev/mmcblk0";
	struct gpt g;
	if (gpt_load(&g, dev) < 0)
		return 1;

	if (!strcmp(argv[1], "show")) {
		gpt_show(&g);
		return 0;
	}
	if (!strcmp(argv[1], "repair")) {
		if (gpt_write(&g) < 0)
			return 1;
		printf("主表与备份表已重写\n");
		return 0;
	}
	if (!strcmp(argv[1], "prep")) {
		uint64_t p5s = (argc >= 4) ? strtoull(argv[3], NULL, 10) : 1048576ULL;
		int r = gpt_prep(&g, p5s);
		if (r <= 0)
			return r < 0 ? 1 : 0;
		if (gpt_write(&g) < 0)
			return 1;
		printf("分区表已更新，接着格式化 p6 并重启\n");
		return 0;
	}
	fprintf(stderr, "未知命令 %s\n", argv[1]);
	return 2;
}
