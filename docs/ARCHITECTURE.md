# 架构与原理

> 为什么这套方案长这样。每个设计决定背后都有原因，多数是踩坑换来的。

## 1. 总体数据流

```text
LAN 设备 (DHCP 拿到网关=路由器)
    │ IP 包进入路由器 br-lan
    ▼
iptables -t mangle PREROUTING -i br-lan -j SB_TPROXY
    │
    │ SB_TPROXY 链内依次:
    │   1) UDP/TCP dport 53 ──────┐  DNS 最先劫持(必须)
    │   2) 目标是私网/保留段 → RETURN 直连
    │   3) 目标在 proxy_ips 白名单 → RETURN (防环路)
    │   4) 其余全部 TPROXY → :7895, mark=1
    ▼
sing-box tproxy inbound (:7895)
    │  sniff 还原域名
    │  DNS: cn 域名→223.5.5.5 真实解析 / 境外→fakeip(198.18/15)
    │  路由: geosite-cn→direct, geolocation-!cn→PROXY, AI→sg, ...
    ▼
direct 出口(pppoe-wan) 或 anytls 出口(代理服务器)
```

被 mark=1 的包由策略路由送回本机 sing-box：

```bash
ip rule add fwmark 1 lookup 100
ip route add local default dev lo table 100
```

这两条**只影响带 mark 的包**，不像 `auto_route` 的 `from all lookup 2022` 那样劫持全局。

## 2. DNS：fakeip 分流

sing-box 接管所有 53 端口流量后：

- `geosite-cn` 域名 → 走 `dns-local`(223.5.5.5) 拿**真实 IP** → 路由层 `geoip-cn` 命中 → direct
- 境外域名（`geolocation-!cn`）→ 返回 **fakeip**（198.18.0.0/15 段假地址）
  → 客户端连假 IP → 该连接必然进 sing-box → 还原域名按规则送代理

好处：客户端永远秒拿到 DNS 应答（fakeip 即答），真实解析由 sing-box 在代理侧完成，
彻底规避 DNS 污染。代价：**fakeip 段绝不能出现在 TPROXY 旁路表里**，
否则假 IP 的连接被放行到内核路由 = 黑洞。

### 为什么 DNS 劫持必须排在私网旁路之前

设备把 DNS 查询发往 223.5.5.5 这类公网 DNS 时，目标不是私网地址，
不抢在前面劫持，查询就会混过私网旁路规则后被 TPROXY 抓走——那没问题；
但发往 192.168.x.x 上游 DNS 的查询会被私网旁路 RETURN 放行，
导致 fakeip 分流对这些设备完全失效。所以 53 端口规则放在链的最顶端。

（而路由器自身的 dnsmasq 监听在 INPUT 路径，不经过 PREROUTING 的 TPROXY 链，
所以路由器自己的 DNS、GL 面板功能不受影响。）

## 3. 为什么是 iptables TPROXY，而不是 TUN

| | TPROXY（本方案） | TUN + auto_route |
|---|---|---|
| 劫持范围 | 只挂 `-i br-lan`，精确到接口/源 IP | `from all lookup 2022`，**本机+转发全部** |
| 隔离灰度 | 天然支持（`-s` 指定源） | 无 |
| 虚拟网卡 | 不需要 | 需要 tun0，多一次内核拷贝 |
| 回滚 | 删 iptables 规则+策略路由，可自证清零 | `ip rule` 残留极难清干净 |
| 事故记录 | 无 | **全屋断网一次**（见 POSTMORTEMS #1） |

sing-box 官方的 `auto_redirect`（nftables 版自动劫持）依赖 `nft_tproxy`/`nft_socket`
内核模块，GL-MT3600BE 的 5.4.281 内核没编译这些模块，实测不可用。

## 4. 分流语义（"策略 A"）

```text
1. sniff + DNS 劫持
2. 私网/Tailscale/自家服务器域名 → direct
3. AI (openai/anthropic/cursor) → sg        ← 出口 IP 专用, 防风控
4. twitter/instagram/google → hk            ← 对出口 IP 敏感的交互服务
5. youtube → hk2                            ← 大带宽视频
6. geosite-cn / geoip-cn → direct
7. 其余境外 (geolocation-!cn) → PROXY
8. IPv6 (::/0) → reject                     ← 家宽无 v6, 防绕行
9. final → direct                           ← 漏网直连
```

`final: direct` 是刻意的安全取舍：路由器出问题影响全屋，
漏网流量走直连最多「没走代理」，而不是「上不了网」。
想要全局代理语义改 `final: PROXY` 即可，但要接受相应风险。

## 5. 防流量成环

sing-box 连接代理服务器的流量本身从路由器发出。如果代理服务器 IP
也被 TPROXY 劫持，sing-box 会试图"通过代理连接代理"→ 死循环。

解法：`/etc/sing-box/proxy_ips` 白名单（每行一个 IP），
`sb-tproxy start` 时为每个 IP 生成 `-d <ip> RETURN` + `-s <ip> RETURN` 规则。

**换节点时必须同步更新此文件**，这是本方案唯一容易踩的维护坑。

## 6. 可靠性设计

- **规则只在内存**：不写任何 uci / 持久化防火墙配置。重启 = 干净状态。
- **开机自启安全**：S95 sing-box 先起，S99 sb-tproxy 重放规则；
  sb-tproxy init 里 `sleep 8` 等 WAN 就绪。若 S99 失败，处于
  "只跑 sing-box 不劫持"的安全态，SSH 仍可进。
- **停止顺序**：sb-tproxy 的 STOP=05 早于 sing-box 的 STOP=10，
  保证关机时先摘规则再停进程（不留黑洞窗口）。
- **幂等**：`do_start` 先 `do_stop`；`verify` 逐一核对四类残留
  （挂载规则/自定义链/策略路由/路由表）全为 0 才 PASS。
- **配置变更护栏**：sing-box.init 启动前先 `sing-box check`，
  坏配置拒绝启动；`sb restart` 同样先 check。

## 7. 灰度模型

`/etc/sing-box/tproxy.src` 存在且有内容 = 只代理名单内的源 CIDR；
缺失或为空 = 代理整个 br-lan。上线路径：

```text
安装(不启动) → 只跑 sing-box(不劫持) → 灰度 1 台设备 → 验证 → 全量
```

回滚永远是 `sb-tproxy stop`（或 `sb off`），一条命令全屋恢复直连。

## 8. 内存预算（GL-MT3600BE, 512MB RAM）

| 项 | 值 |
|---|---|
| sing-box RSS（10 个本地规则集） | 56~81MB |
| 系统可用 | ~156MB（装完后） |
| 结论 | 够但不宽裕；不要再在这台机器上叠 AdGuardHome 等大户 |

规则集用**本地 .srs 文件**（不用 remote URL）：路由器访问不了 GitHub，
且本地文件省内存、离线可启动。
