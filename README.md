# 家庭路由器全局智能分流套件（sing-box TPROXY）

> 一套经过生产验证的家庭网络透明代理方案：局域网内**所有设备零配置**走智能分流
> （国内直连、境外走代理、AI 流量专属出口），带灰度上线、一键回滚、自证清零。
>
> 本套件从一套生产运行中的真实家庭环境完整沉淀而来（2026-09 上线，
> 经历灰度→全量→多轮漏网修复→多出口调优的全部买坑过程），
> 包含全部脚本、配置模板、规则集、文档与踩坑事故史。

## 这是什么（30 秒版）

```
LAN 设备(手机/电视/游戏机, 无需任何设置)
    │ 默认网关 = 路由器
    ▼
路由器 iptables mangle TPROXY (mark=1, table=100, :7895)  ← 只劫持 LAN 转发流量
    ▼
sing-box (fakeip DNS 分流 + geosite/geoip 路由分流)
    ├─ cn 域名/IP  → direct 直连（快）
    ├─ 境外域名    → PROXY 出口（Telegram/Google/Twitter/YouTube…）
    ├─ AI 流量     → sg 出口（ChatGPT/Claude/Cursor，出口 IP 稳定不被封）
    └─ 漏网兜底    → direct（漏掉的最多是没走代理，而不是上不了网）
```

**关键设计：只劫持 LAN 接口的转发流量，绝不碰路由器自身**——这来自一次
全屋断网事故的教训（见 `docs/POSTMORTEMS.md`）。

## 目录结构

```
home-router-proxy-kit/
├── README.md                  ← 你在这里（总入口）
├── AGENTS.md                  ← 给 AI Agent 的操作卡（部署指令/禁令/验收）
├── docs/
│   ├── ARCHITECTURE.md        ← 架构与原理（为什么是 TPROXY 而不是 TUN）
│   ├── DEPLOY.md              ← 部署手册（从零到全量, 灰度可回滚）
│   ├── OPERATIONS.md          ← 日常运维（sb 命令/换节点/规则更新/设备分析）
│   ├── TROUBLESHOOTING.md     ← 排障 SOP（"某网站连不上"标准流程）
│   └── POSTMORTEMS.md         ← 事故史（每条教训都固化进了脚本设计）
├── files/                     ← 部署到路由器的文件
│   ├── install.sh             ← 一键安装（默认不启动任何东西; 自动装 sb CLI+cron+补全）
│   ├── sing-box.json           ← 基线配置模板（单出口, 新部署从这里开始）
│   ├── config.advanced.example.json ← 进阶配置参考（多出口 urltest/AI 分流, 已脱敏）
│   ├── proxy_ips.example      ← 代理服务器白名单模板（防流量成环!）
│   ├── sb                     ← 运维 CLI（status/trace/add-rule... 472 行）
│   ├── sb-tproxy              ← TPROXY 规则管理（start/stop/verify）
│   ├── sing-box.init          ← procd 服务（S95）
│   ├── sb-tproxy.init         ← 开机自启（S99）
│   ├── sb-log-trim.sh         ← 日志裁剪（cron 每小时）
│   ├── sb-completion.sh       ← sb 命令补全
│   └── rules/*.srs            ← 10 个规则集（geosite/geoip, 可整目录拷贝）
└── examples/                  ← 生产环境实测快照（iptables/运行状态, 已脱敏, 仅供参考）
```

## 快速开始（给 Agent 的指令）

**直接把本目录（含 `AGENTS.md`）交给 agent 即可**，它会按操作卡工作。
人类用户请继续阅读：

**你是一个帮用户配置家庭路由器透明代理的 Agent。请按以下顺序工作：**

1. **读 `docs/DEPLOY.md`**，掌握部署阶段模型（安装→启动→灰度→全量→自启），每步可回滚。
2. **硬件适配检查**：目标路由器须满足 `docs/DEPLOY.md` 第 0 节的前置条件
   （fw3+iptables、`xt_TPROXY` 可用、aarch64/x86_64、内存 ≥256MB）。
   ⚠️ 如果路由器是 fw4+nftables（OpenWrt 22.03+），本套件的 iptables 方案
   **不适用**，请改用 nikkinikki / OpenClash 等 nftables 方案。
3. **让用户提供**：代理服务器地址/端口/密码/SNI（anytls 或其他 sing-box 支持的协议均可，
   把 `files/sing-box.json` 里的 PROXY outbound 改成用户自己的协议即可），
   以及一台可灰度验证的设备 IP。
4. **改配置**：编辑 `files/sing-box.json`（填节点）与 `files/proxy_ips.example`
   （填节点 IP，防环路）。直接编辑 .example 文件即可，install.sh 上传时会在路由器侧改名为 proxy_ips。
5. **跑 `files/install.sh`**（在管理机上执行，需要免密 SSH）。
   默认**只装文件不启动**，按 DEPLOY.md 阶段推进。
6. **每一步验证通过再进下一步**；任何异常立即 `sb off` 回滚（全屋秒恢复直连）。

**保命规则（给 Agent，也是给人的）：**

- 绝不使用 sing-box `tun` inbound + `auto_route`（会把转发流量一起劫持 → 全屋断网）
- 绝不只停 sing-box 而留 TPROXY 规则（会黑洞）；用 `sb off`
- 换节点必须同步更新 `/etc/sing-box/proxy_ips`（否则流量成环）
- 改 JSON 配置用 `jq` 或在管理机改完 `sing-box check` 再推，绝不用 sed 手改
- 所有规则只在内存：**重启路由器 = 100% 恢复干净状态**（最后的保命手段）

## 适用范围

| 项 | 要求 |
|---|---|
| 路由器 | OpenWrt 21.02 时代 fw3 + iptables（GL.iNet 4.x 固件实测） |
| 内核模块 | `xt_TPROXY`（`iptables -j TPROXY` 实测可用即可） |
| 架构 | aarch64（GL-MT3600BE 实测）/ x86_64；其他架构需自行编译 sing-box |
| sing-box | 1.14.x（musl 静态版，RSS 约 56~81MB） |
| 内存 | ≥256MB 可用 |
| 管理机 | 任意能 SSH 到路由器的机器（macOS/Linux） |

## 与常见方案的区别

| 方案 | 状态 |
|---|---|
| 本套件（sing-box + iptables TPROXY） | fw3/iptables 机器上的生产验证方案 |
| OpenClash / PassWall2 | 为 fw4/nftables 设计，且官方源无包时不可用 |
| sing-box TUN auto_route | ⚠️ 事故根源，本套件明确弃用（见 POSTMORTEMS） |
| dnsmasq+ipset DNS 分流 | 只能防 DNS 污染，做不了完整代理，可作补充 |
