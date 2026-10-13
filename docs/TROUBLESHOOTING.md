# 排障 SOP — "某网站/App 连不上" 的标准流程

> 按顺序执行，不要跳步。此 SOP 同时内置在路由器 `sb help debug` 里。

## 第 0 步 · 心法

分流语义（策略 A）：

```text
geosite-cn / geoip-cn → direct
境外域名 (geolocation-!cn) → PROXY
geoip-telegram → PROXY;  openai/anthropic/cursor → sg;  youtube → hk2
漏网 → final: direct
```

"连不上"只有两大根因：

1. 目标是被墙服务，但没命中任何 PROXY 规则 → 落到 `final:direct` → 被墙
2. 目标命中了 direct 规则但实际需要代理（规则误伤）

## 第 1 步 · 定位失败连接

```bash
sb targets          # [FAILED] 排行里找连不上的目标
sb log err 30       # 最近 30 条错误
```

记下目标的域名或 IP。

## 第 2 步 · 看它现在走哪条路

```bash
sb trace <域名或IP>
```

输出三行：DNS 给什么（fakeip=会走代理链）/ HTTP 探测 / 日志里的实际出站。

- 走代理出站但还连不上 = **节点问题**，与规则无关（换节点或查节点侧）
- 走 direct 且超时 = **漏网**，进第 3 步

## 第 3 步 · 判断漏网类型，对症下药

| 类型 | 特征 | 修法 |
|---|---|---|
| A. 域名不在 geolocation-!cn 列表 | 网站打不开，trace 显示 direct 超时 | `sb add-rule geosite-<名>`，或加自定义 domain_suffix |
| B. App 直接连 IP，无域名 | Telegram/游戏/P2P 常见 | `sb add-rule geoip-<名>` |
| C. 规则误伤 | 命中 direct 但需要代理 | `sb rules` 查顺序；`sb del-rule` 移除误伤项 |
| D. 需要对照验证 | 怀疑直连本来就不通 | `sb bypass add <IP>` → 测 → `sb bypass del` |

注意 add-rule 下载规则集走 gh-proxy 镜像；路由器拉不动时在管理机下载后 scp。

## 第 4 步 · 验证

```bash
sb trace <目标>     # 应显示 → 走代理
```

实际设备上重试该网站/App。

## 第 5 步 · 收尾

```bash
sb status           # 整体健康
```

## 不知道设备在连什么时（抓流量）

```bash
cat /tmp/dhcp.leases                 # 找设备 IP
sb watch 192.168.8.203 30             # sing-box 视角 30 秒决策
sb sniff 192.168.8.203 20             # TLS SNI 抓取(适用于直连IP场景)
tcpdump -i br-lan -n src host 192.168.8.203 and port 443 -c 100   # 原始兜底
grep "from 192.168.8.203" /var/log/sing-box.log | tail -50
```

## 紧急情况

| 场景 | 操作 |
|---|---|
| 全屋断网 | `sb off`（一条命令恢复直连） |
| sb off 后仍异常 | `sb verify` 必须 PASS；不通则重启路由器 |
| SSH 进不去 | Web 面板重启；再不行拔电 |
| 重启后仍不对 | 规则全在内存，重启=干净态；S99 失败时是"只跑 sing-box 不劫持"安全态，SSH 可进 |

**绝对禁止**：只停 sing-box 而留 TPROXY 规则（黑洞）——用 `sb off`，不要单独 stop。

## 专项：Tailscale / 自建内网穿透类

症状：Tailscale 设备连不上或 DERP 打洞异常。

- `.ts.net` 已在 DNS 与路由两层直连豁免
- 曾试过"UDP 3478/7844 端口豁免"，结果**误伤**：DERP 借用 facebook/googlevideo
  域名+7844 端口，按端口豁免会把这些域名放走直连 → 教训：**按域名豁免，不按端口**

## 专项：fakeip 残留导致"某个域名永远打不开"

sing-box 重启后 cache 里存的 fakeip 映射若与客户端 DNS 缓存不同步，偶发个别域名打不开。
处理：客户端刷新 DNS（飞行模式切换 / `sudo dscacheutil -flushcache`），
或清 `/tmp/sing-box-cache.db` 后 `sb restart`。

## 专项：UDP 类应用（语音输入、视频通话）失灵

若家宽无 IPv6 而应用通过 HTTPDNS 拿真实 AAAA 直连（绕过了 fakeip 的 ipv4_only 策略），
v6 流量命中 `geoip-cn → direct` 后 no route to host。
本方案的 `route.rules` 里 `ip_cidr ::/0 → reject` + DNS `strategy: ipv4_only` 已从根上防；
若还有残余，排查该应用是否硬编码 v6 DNS（8.8.8.8 v6 之类）。
