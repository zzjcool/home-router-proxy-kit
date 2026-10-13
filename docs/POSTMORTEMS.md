# 事故史 — 每一条都固化进了脚本设计

> 本套件的所有"奇怪设计"都有出处。二次部署/改造前必读。

## #1 全屋断网：TUN auto_route 无隔离测试（2026-09-20）

**事故**：直接把 Mac 的 sing-box 配置（tun inbound + `auto_route: true`）搬上路由器测试。
auto_route 插入 `ip rule: from all lookup 2022`——`from all` 不区分本机流量与转发流量，
LAN 全部转发流量被塞进 sing-box 的 tun0，节点又不可达 → **全屋瞬间断网**。

**教训固化**：
- 方案改用 iptables TPROXY，只挂 `-i br-lan`（只劫持 LAN 转发，不碰本机）
- `sb-tproxy` 头部注释明令禁止 tun+auto_route
- TUN 的 `auto_redirect` 依赖 nft_tproxy（本机内核无此模块），同样被排除
- README/DEPLOY 的保命规则第 1 条

## #2 Tailscale 按端口豁免 → 误伤（2026-09-20）

**事故**：Tailscale 打洞异常，加"UDP 3478/7844 → direct"豁免。
结果 DERP 中继借用 facebook/googlevideo 等域名 + 7844 端口——这些域名需要走代理才通，
按端口放行把它们也直连了 → 被墙服务反而连不上。

**教训固化**：
- **按域名/规则集豁免，绝不按端口**（端口会被无关服务复用）
- `.ts.net` 走 DNS+路由两层直连豁免

## #3 Telegram IP 直连漏网（2026-09-20）

**现象**：TG 一直转圈。TG 客户端不解析域名、直接连 149.154.x.x 段 IP，
域名类规则（geolocation-!cn）完全抓不到 → 落 `final: direct` → 被墙。

**教训固化**：
- 补 `geoip-telegram` 规则集（.srs）
- 排障 SOP 固化"类型 B：IP 直连类漏网"修法
- `sb add-rule geoip-<名>` 一键补丁流程

## #4 sed 手改 JSON 当场改坏配置（2026-09-20）

**事故**：`sb add-rule` 初版用 sed 拼 JSON，转义处理错，config.json 直接损坏。
幸有 Mac 侧镜像恢复。

**教训固化**：
- `sb add-rule`/`del-rule` 重写为 **jq 原子修改 + `sing-box check` 双保险 + 失败自动回滚 .bak**
- 全套手册明令：改配置走管理机 → `sing-box check` → scp 推送，绝不在路由器上 sed

## #5 灰度模式 stop 静默失败（沙箱回归抓出）

**事故**（沙箱阶段）：灰度挂载带 `-s <IP>` 参数，`stop` 删规则时按固定参数删 → 删不掉，
且脚本**报告"已移除"**（静默失败，最危险的形态）。

**教训固化**：
- `detach_all` 逐条解析 PREROUTING 里的实际挂载参数再删
- `stop` 后 `count_residue` 核对四类残留（挂载/链/策略路由/路由表），非零即 exit 1
- `verify` 子命令独立自证，CI/演练可用

## #6 配置漂移：Mac 镜像 ≠ 线上（2026-09-24+）

**现象**：路由器侧经多轮调优（urltest 多出口、AI 分流、CF IP 段），Mac 镜像未同步。
若当初直接按镜像"恢复"，会把线上调优全部回退。

**教训固化**：
- 改配置流程定为"管理机为唯一真源 → check → 推送"，改完立刻提交
- 本套件即为此建立的"离线真源快照"：files/ 下的文件就是可复现部署的完整状态
- 交接/分享时以线上实测为准重新采集，而不是信任任何"应该差不多"的旧镜像

## #7 fakeip 与旁路表的相互作用（设计期发现）

TPROXY 旁路表里**绝不能放 198.18.0.0/15**（fakeip 段）：fakeip 连接必须进 sing-box
才能还原域名分流，被旁路 = 客户端拿着假 IP 等一个永远不会来的响应（黑洞）。
`sb-tproxy` 的 `BYPASS_V4` 列表刻意不含它，注释标明"设计原则 3"。

## #8 节点在路由器网络下 TLS 被 RST（环境特性，2026-09-20 调研期）

调研期实测：路由器到三个代理节点 TCP 端口全 OPEN，但 TLS 握手立刻 RST；
GitHub/官方 opkg 源全部解析失败；百度正常。
即：家宽存在 SNI 阻断/中间盒，且路由器无任何代理可用（先有鸡还是先有蛋）。

**教训固化**：
- DEPLOY 第 0.5 节：部署前必须实测路由器到节点的握手
- 规则集全部走本地 .srs（离线可启动），不依赖 GitHub 直连
- 二进制/规则分发统一走 gh-proxy.com 镜像前缀

## #9 DNS 劫持必须先于私网旁路（设计期发现）

设备若把 DNS 查询发给某个私网内 DNS（如上级路由 192.168.x.x），
被私网 RETURN 旁路后 fakeip 分流失效。所以链内顺序固定为：
**53 端口劫持 → 私网旁路 → 白名单 → 全量 TPROXY**。
（路由器自身 dnsmasq 在 INPUT 路径，不经此链，面板功能不受影响。）

## #10 IPv6 绕行风险（设计取舍）

家宽无 IPv6 出口，但设备可能通过其他途径拿到 v6 路由绕过 TPROXY（仅劫持 v4）。
固化：DNS `strategy: ipv4_only` + 路由 `ip_cidr ::/0 → reject` + TPROXY 仅 v4。
宽带真的有 v6 时需另行补 ip6tables 规则（本套件未含，属已知边界）。

---

## 事故 → 设计的映射表

| 事故 | 固化位置 |
|---|---|
| #1 auto_route 断网 | sb-tproxy 设计原则 1；ARCHITECTURE §3 |
| #2 端口豁免误伤 | ARCHITECTURE；TROUBLESHOOTING 专项 |
| #3 IP 直连漏网 | geoip-telegram 规则；add-rule 流程 |
| #4 sed 改坏 JSON | sb 的 jq 原子修改；OPERATIONS |
| #5 stop 静默失败 | detach_all 逐条解析；verify 自证 |
| #6 配置漂移 | 本套件的存在本身 |
| #7 fakeip 黑洞 | BYPASS_V4 注释（设计原则 3） |
| #8 出网受限 | 本地 .srs；镜像前缀；DEPLOY 0.5 |
| #9 DNS 顺序 | sb-tproxy 设计原则 2 |
| #10 IPv6 绕行 | ipv4_only + ::/0 reject |
