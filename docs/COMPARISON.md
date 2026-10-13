# 方案对比：为什么选 sing-box（以及什么时候不选它）

> 面向选型者的诚实对比。结论先行：没有银弹，只有场景匹配。
> 本套件 = sing-box 内核 + TPROXY 部署形态，两层各有对手，分开比。

## 0. 一张表选型（TL;DR）

| 你的情况 | 建议 |
|---|---|
| GL.iNet/老 OpenWrt（21.02、fw3+iptables），官方源无代理插件 | **本套件**（就是为这种环境做的） |
| OpenWrt 24.10+（fw4），想要图形界面点鼠标配置 | homeproxy（sing-box 内核）/ OpenClash / Nikki / PassWall2 |
| OpenWrt 22.03~23.05（fw4 过渡期） | OpenClash / PassWall2 / SSR Plus+（三家保留 iptables 路径） |
| 有一台 x86 小盒子专门当路由 | 软路由系统（iKuai/OpenWrt）+ 任意成熟插件 |
| 不想动路由器，就几台设备要上网 | 每设备装 sing-box/clash 客户端 |
| 企业/多人场景要审计、策略、零配置分发 | 商业方案或自建网关，别自己攒 |
| 想要**完全掌控**：可灰度、可自证回滚、可编程管理 | **本套件** |

## 1. 内核对比：sing-box vs 其他代理内核

| 维度 | sing-box | mihomo (Clash.Meta) | xray-core | ss-rust /老内核 |
|---|---|---|---|---|
| 新协议跟进（anytls/hysteria2/tuic/reality/shadowtls） | **最快**，作者本人参与 anytls 设计 | 快，偶尔滞后 | 快 | 基本停滞 |
| 规则引擎 | rule-set（.srs **二进制**，按需加载，省内存） | rule-provider（多为 yaml 文本，大规则集吃内存） | routing（强大但配置繁琐） | 无（靠外部工具） |
| DNS 架构 | 内置 fakeip / DNS 分流 / DNS 劫持 / domain_resolver，一体化 | fakeip/nameserver-policy，一体但调度细节少 | 强（DNS 模块独立），配置复杂 | 弱 |
| 透明代理 | TPROXY + TUN 两种，粒度可控 | TUN 为主，TPROXY 靠外部脚本 | TPROXY 需自己写全部 iptables | 同左 |
| 单二进制部署 | ✅ musl 静态版，无依赖 | ✅ | ✅ | ✅ |
| Clash API 兼容 | ✅ 自带（可用 yacd/metacubexd 全家面板） | ✅ 原生 | ❌ | ❌ |
| 内存占用（10 个规则集，实测） | **56~81MB RSS**（本环境实测） | 无官方数字：个案从 20MB 空载到 256MB 设备 OOM 都有报告，取决于规则集/连接数 | 视配置 | 低但功能少 |
| 配置可编程性 | JSON → **jq 原子修改 + schema 校验**（本套件 sb add-rule 的基础） | yaml，手改易错 | json，校验弱 | - |
| 维护活跃度 | SagerNet 官方，活跃 | MetaCubeX，活跃 | XTLS，活跃 | 各分支 |

**sing-box 的本质优势：把"代理 + DNS + 分流 + 透明代理 + API"收进一个二进制**，
不需要 dnsmasq-ipset、chinadns、ipset-lists 那些胶水件拼装——拼装方案每一个接缝都是坑。

**诚实的劣势：**
- 1.11 起新配置格式（DNS/rule_set 大改），网上老教程照抄会失败；本套件模板已适配 1.14 新格式
- 无 Web 配置界面，纯 JSON；对"只想点鼠标"的人不友好
- 中文社区资料少于 Clash 系

## 2. 部署形态对比：路由器透明代理 vs 其他

| 形态 | 优点 | 缺点 |
|---|---|---|
| **路由器透明代理**（本套件） | 全屋设备零配置（电视/IoT/游戏机/访客手机全覆盖）；策略统一在一处；用户无感 | 路由器性能/内存是硬约束；出问题影响全家（所以必须灰度+回滚） |
| 每设备装客户端 | 单设备问题不扩散；灵活 | 电视/游戏机/IoT 装不了；每台都要维护；访客没法用 |
| x86 软路由 | 性能无忧 | 多一台机器、功耗、成本 |
| 商业固件/商业 TPROXY | 省心 | 花钱；黑盒；定制性差 |

**家庭场景的胜负手**：最大的痛点从来不是电脑，而是**装不了客户端的设备**（电视盒子、
游戏机、IoT、长辈手机）。这就是路由器透明代理存在的理由——这层所有方案共通，
真正要比的是用哪套内核 + 管理体系。

## 3. OpenWrt 插件生态对比（同为路由器形态）

先说结论：**这几款都不是 OpenWrt 上游自带包**，全部来自第三方 feed，各家对防火墙层的要求差异很大。以下信息均核对于各项目 2026-10 的 README/Makefile/Release（出处列在表后）。

| 方案 | 仓库 | 内核 | 防火墙要求 | 维护状态（2026-10） | 特点 vs 本套件 |
|---|---|---|---|---|---|
| OpenClash | vernesong/OpenClash | mihomo（原 Clash Meta） | fw3(iptables) 和 fw4(nftables) **双支持**，18.06+ | 活跃（v0.48.002, 2026-10-12） | LuCI 完整界面、生态最大；行为黑盒程度高，回滚粒度粗 |
| PassWall2 | Openwrt-Passwall/openwrt-passwall2 | Xray 或 sing-box 三选一/All | 无 fw4 时默认 iptables，有则 nftables；README 要求 21.02+、≥256MB RAM | 活跃（26.10.1） | 多内核可选；与一代差别在把内核收成 Basic Core 选项、分流/负载均衡强化 |
| SSR Plus+ | fw876/helloworld | xray/mihomo/ssr 等多选（按架构默认不同） | 同上双支持；老 21.02 编译需自行升 Go 1.21+ | 活跃（v196.19, 2026-10-07） | 老牌；内核生态杂，适合已有存量配置的人 |
| homeproxy | immortalwrt/homeproxy | **sing-box** | **仅 fw4**（依赖 kmod-nft-tproxy），issue 模板要求 ≥24.10 | 活跃；ImmortalWrt 官方 luci 源内置 | **同内核的 LuCI 界面版**——与本套件的 sing-box.json 理念一致，只是劫持层是 nftables |
| Nikki | nikkinikki-org/OpenWrt-nikki | **mihomo**（前身 luci-app-mihomo，因许可证改名） | **仅 fw4**，要求 OpenWrt ≥24.10、内核 ≥5.13 | 活跃（v1.26.2, 2026-10-10），自建 feed | mihomo 界面化标杆；与本套件不同内核 |
| **本套件** | zzjcool/home-router-proxy-kit | **sing-box** | **仅 fw3+iptables**（需要 xt_TPROXY） | 本文档所在仓库 | 老固件唯一解；CLI、灰度/自证回滚/事故文档化 |

**对老 21.02/fw3 机器的意义**：GL-MT3600BE 这类机器内核没编译 nft_tproxy 模块、
GL 官方源也没有任何代理插件，GL 官方论坛也明确警告不要直接装其他版本的包（可能变砖）。
文档上仍保留 iptables 路径的 OpenClash/PassWall2/SSR Plus+ 能不能在特定 GL 定制机上装上，
要按型号核依赖（官方源没有依赖包时基本无解）——而本套件是静态二进制 + 自带规则集 +
自带劫持脚本，**零依赖整包交付**，这也是它存在的理由。

而如果你的机器是 fw4（24.10+），装 homeproxy（同 sing-box 内核）界面化操作更省事，
本套件的 sing-box.json 可直接复用（内核配置无差别，只是劫持层从 iptables 换成 nftables）。

出处：

- OpenClash：<https://github.com/vernesong/OpenClash>（README 双路径安装命令；v0.48.002 Release）
- PassWall2：<https://github.com/Openwrt-Passwall/openwrt-passwall2>（README/Makefile；原 xiaorouji 仓库已迁移）
- SSR Plus+：<https://github.com/fw876/helloworld>（dev 分支 Makefile；v196.19）
- homeproxy：<https://github.com/immortalwrt/homeproxy>（Makefile 依赖 `+sing-box +firewall4 +kmod-nft-tproxy`）
- Nikki：<https://github.com/nikkinikki-org/OpenWrt-nikki>（README：mihomo + fw4 + ≥24.10；改名史见 v1.17.4...v1.17.5）
- OpenWrt/ImmortalWrt 官方源抽查（25.12.x）：上游 luci 源无任何上述插件；ImmortalWrt 源含 homeproxy/OpenClash/PassWall，无 nikki/luci-app-mihomo
- GL 固件版本表：<https://www.gl-inet.com/pages/firmware-versions>（4.x 并非单一 OpenWrt 基线，多数机型仍是 21.02）

### 3.1 多维度评分矩阵

> 5 分制。以“家庭场景长期运行”为评价立场；仅本套件数据来自生产实测，其余为基于上游文档/社区共识的定性评估，仅供参考。

| 维度 | OpenClash | PassWall2 | SSR Plus+ | homeproxy | Nikki | 本套件 |
|---|---|---|---|---|---|---|
| **安装难度** | 3（自动安装器，但依赖源） | 3（同左） | 2（依赖最杂） | 4（ImmortalWrt 源内置） | 4（自建 feed 一条命令） | **5**（零依赖：scp+install.sh） |
| **上手易用性** | 5（LuCI 界面全功能） | 4 | 3 | 4 | 4 | 2（CLI+文档，需读 DEPLOY.md） |
| **性能/内存** | 3（mihomo，大规则集吃内存） | 3（同上，取决于内核） | 3（取决于内核） | 4（sing-box .srs 二进制规则集） | 3（mihomo） | **4**（sing-box，10 规则集 56~81MB 实测） |
| **功能/协议丰富度** | 5（订阅转换、面板、覆写…生态最大） | 5（多内核、负载均衡、ACL） | 4 | 4（跟 sing-box 内核） | 4 | 3（跟 sing-box 内核，无订阅转换） |
| **透明代理质量** | 4（nftables/iptables 自动适配） | 4 | 3（链路多，黑盒） | 4 | 4 | **5**（TPROXY+fakeip，劫持面精确到接口/源IP） |
| **灰度上线能力** | 2（无原生灰度，需手动改规则） | 3（有 ACL 但非灰度语义） | 2 | 2 | 2 | **5**（tproxy.src 一行 IP 即灰度，秒级切换） |
| **回滚可靠性** | 2（停服务+清规则，无自证） | 3 | 3 | 3 | 3 | **5**（sb off 一键+verify 自证四类残留为 0） |
| **可观测/排障** | 5（面板+日志中心） | 4 | 3 | 4（跟内核，无面板集成） | 4 | **5**（sb trace/watch/targets，排障 SOP 固化） |
| **Agent/AI 友好度** | 2（LuCI 状态机复杂，无结构化文档） | 2 | 1 | 3 | 3 | **5**（AGENTS.md 操作卡+jq 可编程配置+全部 CLI 化） |
| **事故可预防性** | 2（多组件联动，出问题难定位） | 3 | 2 | 3 | 3 | **5**（事故史文档化+每条事故固化到脚本） |
| **老 21.02/fw3 可用** | △（有 iptables 路径，但依赖源要核） | △（同左，README 标 21.02+） | △（同左） | ❌（仅 fw4） | ❌（仅 fw4） | ✅ **实测生产** |

**读法**：没有全能冠军。OpenClash 是“功能/易用”双冠，本套件是“可控/可靠/Agent 友好”三冠；
homeproxy/Nikki 各自是 fw4 时代同内核/同界面路线的代表作；老固件上只剩本套件与“碰运气装 OpenClash/PassWall2”两个选项。

### 3.2 性能与资源占用（展开）

家庭路由器的性能瓶颈不在内核实现（sing-box/mihomo/xray 都是 Go，转发路径都在伯仲之间，
瓶颈在家宽带宽和 CPU 的加密开销），而在三件事：**规则集加载方式、内存上限、劫持路径质量**。

**1）规则集格式是内存差距的主因**

- sing-box 用 .srs 二进制规则集（编译后的紧凑格式，按需 mmap）；本套件 10 个规则集（含 445KB 的 geosite-cn）实测 RSS 56~81MB
- mihomo 大量场景用 yaml 文本 rule-provider，加载后驻留内存；几千条规则时内存常显著高于同内容 .srs
- 但两者都没有“官方内存规格”：mihomo 维护者自述 20~80MB（取决于节点/规则/连接数），
  也有 256MB 路由器 OOM 个案（OpenClash#5093）。**256MB 是分水岭**：低于它，任何“全家桶”都危险

**2）劫持路径质量决定“上不上得了带宽”**

- TPROXY（本套件）：内核态 mark 重定向，无用户态拷贝。GL-MT3600BE（MT7987 4核A53）实测跑 300Mbps+ 家宽无压力
- TUN：多一次用户态拷贝，CPU 低端机器上大带宽时差距可感
- 硬件 NAT 加速（mtkhnat）会绕过 netfilter，对 TPROXY/TUN 都有干扰——这是固件层问题，与插件无关（本套件用灰度+实测规避，见 POSTMORTEMS）

**3）DNS 路径**

- 本套件 fakeip：客户端 DNS 毫秒级应答（假 IP 即答），真实解析在代理侧完成——高延迟节点下体验差距明显
- 传统 chinadns-ng / dns2socks 链路（PassWall 一代/SSR 默认）：多一跳解析、缓存策略各异

### 3.3 易用性（展开）：三类用户分别适合什么

**“点鼠标就好”型（大多数家庭用户）**

- 首选 OpenClash：向导式配置、订阅一键导入、面板看连接、社区教程最多
- Nikki（fw4 24.10+）体验更现代
- 本套件不合适：没有界面，首次配置必须改 JSON + 跑命令

**“能折腾但不想读代码”型**

- OpenClash / PassWall2 都能胜任；PassWall2 的分流/负载均衡/ACL 更强，多出口场景更顺
- 本套件的 install.sh + sb CLI 其实把命令都包了，但要接受“文档即界面”

**“掌控型/Agent 用户”型（本套件的目标画像）**

- 需要灰度上线（家人无感）、一键回滚、自证清零、事故可查、配置可编程（jq）、排障 SOP 固化
- 或用 AI agent 帮你/帮朋友配置：AGENTS.md 操作卡 + 全 CLI 接口天然适合 agent 消费
- LuCI 插件的复杂状态机（uci+nftables+多内核协同）对 agent 是灾区：无结构化文档、界面操作无法脚本化复现

### 3.4 功能丰富度（展开）：界面插件的优势区

诚实地说，LuCI 插件有三块本套件没有的功能：

1. **订阅生态**：机场订阅一键导入/自动更新节点列表（OpenClash 转换器生态最强）。
   本套件为自建节点设计，改节点=改 JSON+同步白名单（有 sb 命令辅助，但不是“粘个链接就完事”）
2. **面板生态**：OpenClash 集成 yacd/metacubexd 面板，可视化看连接/切换节点。
   本套件可用任意 Clash API 面板（sing-box 自带 clash_api），但要自己找个面板前端
3. **LuCI 联动**：防火墙/DHCP/QoS 与代理在同一界面管理

反向地，本套件有几块插件们普遍没有的：灰度上线、verify 自证回滚、排障 SOP 固化、
事故史文档、离线整包交付、AI agent 操作卡。

### 3.5 可靠性与出事后的行为（展开）

家庭场景的可靠性要求其实很特殊：**出事影响的不只是你自己，是全家**。对比“出事时”的四个阶段：

| 阶段 | LuCI 插件（泛指） | 本套件 |
|---|---|---|
| **事前预防** | 依赖用户记得备份配置 | 灰度模型强制先验证；sing-box check 拒绝坏配置 |
| **事中止血** | LuCI 进得去→停服务+清规则（多步，顺序易错） | `sb off` 一条命令全屋直连 |
| **事后自证** | 需手工核 iptables/nftables 残留 | `sb verify` 四类残留自动核对，非零即 FAIL |
| **最坏情况** | 配置散在 uci，误存可能持久化坏状态 | 规则只在内存，**重启=100%干净态**（设计保证） |

其中“最坏情况”是本质差异：插件把规则写进 nftables/uci 持久层，出问题可能追着重启跑；
本套件的规则永不落盘，物理重启就是终极回滚手段。

### 3.6 维护成本（展开）

| 事项 | LuCI 插件 | 本套件 |
|---|---|---|
| 日常 | 界面点几下 | `sb status` / 面板看一眼（一样简单） |
| 升级 | opkg 升级，可能连带内核/依赖变动 | scp 新二进制+`sb restart`，其他不动 |
| 规则更新 | 界面点更新（订阅自动） | `sb update-rules`（或 sb add-rule 按需） |
| 换节点 | 粘订阅/改界面 | 改 JSON+同步 proxy_ips（有文档有 sb 辅助） |
| 出问题 | 搜社区帖/开 issue | 读 TROUBLESHOOTING.md SOP（5 步定位法） |
| 固件升级 | 插件可能失配需重装 | 文件在 overlay，重跑 install.sh 即恢复 |

本套件维护成本峰值在首次部署（读文档+改配置），长期低于插件（出事少、排障有 SOP）；
插件的峰值在出事时（黑盒定位慢）。

### 3.7 AI Agent 友好度（本套件的独有维度）

这不是传统维度，但是 2026 年配网络的真实需求：

| 能力 | LuCI 插件 | 本套件 |
|---|---|---|
| 结构化操作文档 | ❌ 散在 wiki/帖子 | ✅ AGENTS.md 操作卡（禁令/验收清单） |
| 状态可编程读取 | 部分可达（uci 导出） | ✅ sb status/trace/targets 全 CLI 结构化输出 |
| 配置可编程修改 | uci 杂项多 | ✅ 单一 JSON+jq 原子修改+check 校验（sb add-rule 已内置） |
| 验收可自动化 | ❌ | ✅ verify 非零退出码、trace 输出可 grep |
| 事故知识可传承 | ❌ | ✅ POSTMORTEMS.md（每条事故→固化位置） |

一个能 grep、能 jq、能 exit code 的系统，agent 就能操作；一个需要点界面的系统，agent 只能干看。

## 4. TPROXY vs TUN（sing-box 自己的两种透明代理模式）

| | TPROXY（本套件） | TUN |
|---|---|---|
| 劫持范围 | iptables 精确圈定（`-i br-lan` / `-s 源IP`） | 全部或自动规则 |
| 灰度能力 | ✅ 天然（改一条 iptables） | ❌ 需绕 |
| 灰度→全量切换 | 秒级，不重启 sing-box | 需重建路由 |
| 回滚 | 删规则可自证清零（verify） | `ip rule` 残留难清干净 |
| 路由器自身流量 | **完全不经过代理链**（管理面稳） | 默认被劫持 |
| 风险记录 | 无事故 | auto_route 曾致全屋断网（见 POSTMORTEMS #1） |
| 依赖 | `xt_TPROXY` 内核模块 | `/dev/net/tun` |

TUN 不是错的——**在客户端（Mac/PC）上 TUN 是对的**，因为那里"本机=全部"。
路由器上"本机管理面"必须和"转发流量"隔离，这正是 TPROXY 的主场。

## 5. 本套件的差异化（在"路由器 sing-box"这个类目内）

同类做法（自写 tproxy 脚本 + sing-box）网上不少，本套件的不同在于**管理体系**：

1. **灰度上线模型**：安装→只跑进程→单设备灰度→全量，家人全程无感
2. **回滚自证**：`verify` 逐一核对四类残留，非零即 FAIL——回滚不靠"应该干净了"
3. **规则只在内存**：不写 uci/持久化防火墙，重启=100% 干净态（最后的保命手段）
4. **配置变更护栏**：`sing-box check` 前置 + jq 原子修改 + 失败自动回滚，杜绝手改 JSON
5. **sb 运维 CLI**：status/trace/watch/add-rule/一键排障 SOP，运维知识固化在命令里
6. **事故史文档化**：10 条真实事故全部标注"固化到了哪行代码/哪个流程"
7. **离线可启动**：规则集本地 .srs，不依赖 GitHub 直连（国内路由器环境实测）

这套东西的价值密度在**长期运维**，不在装完那天。

## 6. 不选本套件的理由（诚实清单）

- 你的路由器是 fw4/nftables（OpenWrt 22.03+）→ 本套件 iptables 层不适用，用 Nikki
- 你想要图形界面、不想碰命令行 → OpenClash/Nikki
- 你的路由器内存 <128MB → sing-box + 规则集跑不动，换性能件或退回 DNS 分流
- 你只有一两台电脑要上网 → 每设备装客户端更简单
- 你需要企业级功能（审计/多用户策略/SSO）→ 商业方案
- 你无法接受"配置是 JSON 文件" → 上面第 2 条

---

> 想看"这些结论怎么来的"：架构层面的推演见 [ARCHITECTURE.md](ARCHITECTURE.md)，
> 每个设计决定对应的事故见 [POSTMORTEMS.md](POSTMORTEMS.md)。
