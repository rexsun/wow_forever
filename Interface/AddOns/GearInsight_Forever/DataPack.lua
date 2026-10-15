-- 数据包（Beta 改动 / 热门配点 / 众包死亡与升级用时）。
-- ⛔ 随插件发布的是空包；GearInsight 更新器从 https://gearinsight.cn/static/dl/forever/datapack.lua 下载、校验 sha256 后整份覆盖本文件
--   （协议 docs/forever-addon-link-protocol.md ①：下载来的文件第一行是「-- GIF_DATAPACK <版本>」，内容是全局表 GIF_PACK）。
-- 空包故意不写那一行 = 更新器当「还没装数据包」，第一次检查就会下载。GIF_PACK 为 nil 时用到它的功能都静默不显示。
GIF_PACK = GIF_PACK
