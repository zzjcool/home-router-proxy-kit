# 日常运维手册

> 部署完成后，日常所有操作优先用路由器上的 `sb` 命令。
> 它把底层命令都调对了，且内置排障 SOP（`sb help debug`）。

## sb 命令速查

```bash
sb status              # 总览: 进程/规则挂载/分流统计/内存负载
sb rules               # 当前规则集与路由规则
sb devices             # 谁在用代理(各设备连接数)
sb targets             # 出站分析: 代理/直连/失败 三类排行
sb log [N|live|err]    # 日志: 实时 / 最近N行 / 只看错误

sb on                  # 启动(sing-box + TPROXY)
sb off                 # 一键回滚(全屋恢复直连, 最常用)
sb restart             # 重启 sing-box (先 check, 坏配置拒绝重启)
sb verify              # 自证零残留(必须 PASS)

sb trace <域名>         # 看某目标现在走哪条路
sb watch <设备IP>       # 抓某设备流量
sb sniff <设备IP>       # 抓某设备的 TLS SNI
sb bypass add|del|list <CIDR>   # 临时放行某目标

sb add-rule geoip-twitter       # 一键补规则集(jq 原子改配置)
sb del-rule geosite-xxx
sb update-rules         # 全部规则集更新
```

## 常见任务

### 看家人哪台设备在用代理

```bash
ssh root@<路由器IP> 'sb devices'
```

### 发现某境外网站打不开

见 `TROUBLESHOOTING.md`（或路由器上 `sb help debug`）。短版：

```bash
sb targets && sb trace example.com    # 定位
sb add-rule geosite-example           # 补规则(域名类)
sb add-rule geoip-example             # 补规则(IP直连类, 如 Telegram)
```

### 换代理节点（⚠️ 两个文件必须同步改）

```bash
# 1. 改配置里的 PROXY outbound (server/port/password/SNI)
vi files/sing-box.json
sing-box check -c files/sing-box.json          # 必须先过
scp -O files/sing-box.json root@<路由器IP>:/etc/sing-box/config.json

# 2. 新节点 IP 追加进白名单 (防环路, 忘了 = 死循环)
ssh root@<路由器IP> 'echo <新节点IP> >> /etc/sing-box/proxy_ips && sb restart'
```

### 规则集更新

```bash
ssh root@<路由器IP> 'sb update-rules'   # 从镜像源拉最新 .srs 并重启
```

路由器访问不了 GitHub 时用 gh-proxy 镜像（脚本内置）；若镜像也失效，
在管理机下载后 `scp -O` 推上去。

### 临时放行某目标（排查对照）

```bash
sb bypass add 1.2.3.4/32   # 不过代理
sb bypass del 1.2.3.4/32
```

### Clash API（可视化面板）

```bash
# clash_api 开在 0.0.0.0:9090, 浏览器打开任意 clash dashboard 指向它
curl -H "Authorization: Bearer <secret>" http://<路由器IP>:9090/connections
```

可看实时连接、规则命中、切换出站（urltest 组手动切换）。

## 保命等级（按序）

1. **`sb off`** — 一键回滚全屋直连；`sb verify` 自证
2. **拔电重启** — 规则只在内存，重启即干净；S95/S99 自动恢复分流
3. **Web 面板重启** — SSH 进不去时用
4. 绝不：只停 sing-box 留 TPROXY 规则（黑洞）；不检查直接 restart

## 维护节奏

| 频率 | 事项 |
|---|---|
| 每月 | `sb update-rules` 更新规则集 |
| 每月 | `sb status` 看内存（available <40MB 需警惕） |
| 每季 | 重启演练一次（验证自启链路） |
| 固件升级后 | GL 升级保留 /etc 与 /usr/bin（overlay）；跑 `sing-box check` + `sb restart`；若被清则重跑 install.sh（文件在管理机套件里） |

## 日志

- 路径 `/var/log/sing-box.log`（info 级），`sb-log-trim.sh` cron 每小时裁剪（>5MB 截尾保留 2000 行）
- 排障时最有用的三类行：
  - `connection from 192.168.8.x`（谁在连）
  - `outbound/xxx connection to yyy`（走哪条出站）
  - `ERROR ... i/o timeout`（漏网嫌疑：direct 出站超时 = 该走代理没走）
