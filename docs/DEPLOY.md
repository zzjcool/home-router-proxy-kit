# 部署手册

> 从零到全量。核心原则：**每一步都可独立回滚，每一步都先验证再前进**。
> 全程任何时刻出问题：`ssh root@<路由器> sb off` 或 `install.sh --rollback`。

## 0. 前置检查（5 分钟，跳过 = 未来的事故）

### 0.1 路由器硬件

```bash
ssh root@<路由器IP> 'cat /tmp/sysinfo/model; uname -m; free | head -2'
```

| 项 | 要求 | 说明 |
|---|---|---|
| 架构 | aarch64 / x86_64 | 其他架构需自行编译 sing-box（musl 静态） |
| 内存 | ≥256MB | sing-box + 10 规则集约 60~85MB RSS |
| 防火墙 | **fw3 + iptables** | `ls /etc/config/firewall` 且 fw4 不存在 |
| 内核 | 5.x, 带 `xt_TPROXY` | 见 0.2 |

### 0.2 TPROXY 能力实测（决定性，GL-MT3600BE 实测通过）

```bash
ssh root@<路由器IP> '
  ls /lib/modules/$(uname -r)/ | grep -iE "tproxy|socket" ;
  iptables -t mangle -N SB_TEST 2>/dev/null ;
  iptables -t mangle -A SB_TEST -p tcp -j TPROXY --on-port 7895 --tproxy-mark 1 && echo TPROXY_OK ;
  iptables -t mangle -F SB_TEST ; iptables -t mangle -X SB_TEST'
```

看到 `TPROXY_OK` 才能继续。若报 `No such file`：尝试 `opkg install kmod-ipt-tproxy iptables-mod-tproxy`。

⚠️ **OpenWrt 22.03+（fw4/nftables）机器本套件不适用**：iptables 规则可能通过兼容层部分生效，但无法保证，请改用 nftables 系方案（nikkinikki/OpenClash）。

### 0.3 mangle 表冲突检查

```bash
ssh root@<路由器IP> 'iptables -t mangle -S | grep -vE "^-P|^:"]; ip rule show; ip route show table 100'
```

mark `1`、table `100`、SB_ 前缀链必须空闲。若被占用，改 `sb-tproxy` 头部的
`MARK`/`TABLE` 变量即可。

### 0.4 硬件 NAT 加速（mtkhnat）

MTK 系路由器默认开硬件快转，会让**已建立连接**绕过 netfilter → TPROXY 抓不到部分流量。
GL 面板 → 网络 → 网络加速 → 关闭（或仅软件加速）。
代价是 CPU 占用上升；MT7987 4 核 A53 跑家用千兆没有压力。
（本生产环境实测保持开启也能工作，但若出现"TCP 走代理、UDP 漏网"类怪象，优先怀疑它。）

### 0.5 节点连通性（最容易翻车的现实一步）

```bash
# 在路由器上直接测到代理服务器的连通性
ssh root@<路由器IP> 'nc -zv <代理服务器IP> <端口>'
```

家宽环境对部分协议/端口有干扰（本环境实测过 TCP 可达但 TLS 握手被 RST）。
**如果路由器上到节点握手失败，先解决节点问题再部署**，否则灰度阶段就会失败。

### 0.6 管理机侧

- 免密 SSH：`ssh-copy-id root@<路由器IP>`，并在 `~/.ssh/config` 配好 Host。
- `scp` 需用 `-O`（老 OpenWrt 没有 sftp-server）。

## 1. 准备配置（管理机上编辑 files/）

### 1.1 节点信息

编辑 `files/sing-box.json`，替换三处 `REPLACE_WITH_*`：

```text
PROXY outbound: server / server_port / password / tls.server_name(SNI)
route.rules 里的 REPLACE_WITH_YOUR_SERVER_DOMAIN（若节点用域名则加直连豁免）
```

协议不限于 anytls：改成 vmess/vless/trojan/hysteria2 等 sing-box 支持的任意 outbound 都行，
**DNS/路由/inbound 部分不用动**。

### 1.2 防环路白名单（必做，跳过 = 灰度时死循环）

编辑 `files/proxy_ips.example` → 每行填一个代理服务器 **IP**（iptables 不认域名）。
直接编辑 .example 文件即可，install.sh 上传时会在路由器侧自动改名为 `proxy_ips`：

```bash
dig +short <你的节点域名>   # 节点用域名时先解析出全部 IP 填入
```

### 1.3 规则集

`files/rules/*.srs` 已附带 10 个常用规则集。需要增补时（在管理机上）：

```bash
MIRROR="https://gh-proxy.com/https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/sing/geo"
curl -sSL -o files/rules/geoip-twitter.srs "$MIRROR/geoip/twitter.srs"
```

新加的规则集要同时在 `sing-box.json` 的 `route.rule_set` 里登记（参考 config.advanced.example.json）。

## 2. 安装（不启动任何东西）

```bash
cd files/
./install.sh              # 传二进制+配置+脚本+规则集, sing-box check 校验
# 或显式指定目标: ROUTER=root@192.168.5.1 ./install.sh
```

装完路由器上多了：`/usr/bin/sing-box`、`/etc/sing-box/*`、`/etc/init.d/sing-box`、`/etc/init.d/sb-tproxy`。
**此刻全屋零影响**（没有规则、没有进程）。

### 2.1 install.sh 自动完成的内容

`install.sh`（无参数运行）会一并完成：sb 运维 CLI、日志裁剪 cron（每小时）、Tab 补全 的部署。
手工操作时需要自行补上（或参考 install.sh 的 install_files 函数）：

```bash
scp -O files/sb root@<路由器IP>:/usr/bin/ && ssh root@<路由器IP> 'chmod +x /usr/bin/sb'
scp -O files/sb-log-trim.sh root@<路由器IP>:/usr/bin/ && ssh root@<路由器IP> 'chmod +x /usr/bin/sb-log-trim.sh'
ssh root@<路由器IP> 'mkdir -p /etc/profile.d'
scp -O files/sb-completion.sh root@<路由器IP>:/etc/profile.d/
ssh root@<路由器IP> '(crontab -l 2>/dev/null; echo "0 * * * * /usr/bin/sb-log-trim.sh") | crontab -'
```

> sb-log-trim.sh 裁剪的日志路径是 `/tmp/log/sing-box.log`，若你的 sing-box.json 里 log.output 改成了 `/var/log/sing-box.log`，需对应改脚本内 LOG 变量。

## 3. 分阶段上线

### 阶段 A：只跑 sing-box（不劫持）

```bash
./install.sh --start
# 验证: 进程在、7895 在听; 全屋上网零影响
```

### 阶段 B：灰度一台设备

```bash
IP=<你的测试设备IP>          # cat /tmp/dhcp.leases 找
./install.sh --gray $IP
# 在测试设备上验证:
#   curl https://api.ip.sb/ip                  → 应显示代理出口 IP
#   curl -o /dev/null -w '%{http_code}' https://www.baidu.com   → 200 且秒回(直连)
#   打开 youtube/google                        → 通
# 家人设备此刻零影响。
```

### 阶段 C：全量

```bash
./install.sh --full
# 全屋设备即刻全部走智能分流
```

### 阶段 D：开机自启

```bash
ssh root@<路由器IP> '/etc/init.d/sing-box enable; /etc/init.d/sb-tproxy enable'
# 重启路由器做一次演练: 重启后 sb status 应显示 TPROXY 已挂载
```

### 回滚（任何阶段）

```bash
./install.sh --rollback      # 或 ssh root@<路由器IP> sb off
./install.sh --verify        # 残留必须 0, verify 必须 PASS
```

## 4. 上线后验收清单

- [ ] `sb status`：进程在、TPROXY 挂载、近期无 ERROR
- [ ] 国内站点直连且快（baidu.com → outbound/direct）
- [ ] 被墙站点走代理（google.com → outbound/PROXY 链）
- [ ] DNS 正常（`dig www.baidu.com @192.168.8.1` 秒回真实 IP）
- [ ] Tailscale（若用）正常：`tailscale ping` 对端通
- [ ] 重启演练一次：断电重开，2 分钟内全屋恢复分流
- [ ] `sb verify` PASS

## 5. 常见安装期问题

| 症状 | 原因 | 处理 |
|---|---|---|
| `sing-box check` 失败 | JSON 手改坏了 | 管理机 `jq .` 校验后重推，绝不在路由器上 sed |
| 灰度设备无法上网 | 节点在路由器网络下握手失败（0.5 节） | 先 `sb off`，解决节点连通性 |
| 一切正常但某 App 不通 | 漏网/误伤 | 走 `docs/TROUBLESHOOTING.md` 的 SOP |
| scp 报 `/usr/libexec/sftp-server not found` | 老 OpenWrt 无 sftp | scp 一律加 `-O`（走 legacy 协议） |
