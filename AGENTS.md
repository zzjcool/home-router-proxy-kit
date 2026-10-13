# 给 Agent 的部署指令（必读）

> 本文件是给 AI agent 看的精简操作卡。人类用户请从 README.md 开始。

## 你的任务

在用户的路由器上部署本套件的 sing-box TPROXY 全局智能分流，
让全家庭设备零配置获得国内直连/境外代理的分流上网。

## 工作顺序（严格按序，禁止跳步）

1. **读完本目录全部 docs/**。特别是 `DEPLOY.md` 的阶段模型与回滚手段、
   `POSTMORTEMS.md` 的事故教训（违反其中的禁令会造成全屋断网）。
2. **前置检查**（DEPLOY.md 第 0 节）：fw3+iptables、TPROXY 实测 OK、
   mangle/table 100/mark 1 空闲、内存 ≥256MB。
   ⚠️ fw4/nftables 机器：本套件不适用，告知用户改选 nikkinikki/OpenClash，停止。
3. **收集用户信息**（一次性问全，不要挤牙膏）：
   - 代理服务器：地址/端口/协议/密码/SNI（anytls/vmess/vless/trojan…均可）
   - 路由器 SSH 是否已配好免密（`ssh root@<IP> true` 试一下）
   - 测试设备 IP（灰度阶段用）
4. **编辑文件**（在管理机上）：
   - `files/sing-box.json`：替换 3 处 `REPLACE_WITH_*`（PROXY outbound + 域名直连豁免）。
     协议不是 anytls 时整个 outbound 对象换成用户协议，**DNS/route/inbound 结构不动**。
   - `files/proxy_ips.example` → 填节点 IP（直接编辑 .example，
     install.sh 上传时自动在路由器侧改名为 proxy_ips）。
     节点用域名时 `dig +short <域名>` 解析出全部 IP 填入。
   - `jq empty files/sing-box.json` 校验通过后再动下一步。
5. **执行 `files/install.sh`**（在 files/ 目录下；目标可用 `ROUTER=root@x.x.x.x ./install.sh` 覆盖）。
   默认只装文件不启动。检查输出里 `配置OK`。
6. **分阶段上线**（DEPLOY.md 第 3 节）：`--start` → `--gray <IP>` → 用户设备上验证 → `--full`
   → `--verify`。**每阶段验证通过才进下一阶段**。
7. **开机自启**：两个 init.d 服务 enable + 重启演练（DEPLOY.md 阶段 D + 验收清单）。

## 硬性禁令（违反 = 事故）

- 禁止使用 sing-box tun inbound / `auto_route` / `auto_redirect`（POSTMORTEMS #1）
- 禁止只停 sing-box 而留 TPROXY 规则；回滚只用 `sb off` / `install.sh --rollback`
- 禁止在路由器上用 sed/vi 手改 config.json；只能管理机编辑 + `sing-box check` 后推送
- 换节点必须同步更新 `/etc/sing-box/proxy_ips`（POSTMORTEMS 防环路）
- 禁止按端口号做豁免（POSTMORTEMS #2 Tailscale 误伤）
- `198.18.0.0/15`（fakeip 段）绝不能加进任何旁路/直连豁免（POSTMORTEMS #7）
- 部署中任何一步失败：先 `--rollback` 恢复直连，再排查。不要带病前进。

## 验收标准（全部满足才算完成）

- [ ] `sb status` 正常，`sb verify` PASS
- [ ] 测试设备：国内站直连（快）、境外站走代理（通）
- [ ] `dig www.baidu.com @<路由器IP>` 返回真实 IP（非 fakeip 段）
- [ ] 重启路由器后自动恢复（S95 sing-box + S99 sb-tproxy）
- [ ] 用户知道 `sb off` 一键回滚的用法

## 常见分支

| 情况 | 处理 |
|---|---|
| 用户节点协议不是 anytls | 换 PROXY outbound 对象即可，结构不变 |
| 路由器不是 GL/非 MT3600BE | 只影响 install.sh 型号提示，fw3+iptables+TPROXY 可用即可 |
| 规则集下载失败（GitHub 不通） | 一律加 gh-proxy.com 前缀（install.sh/sb 已内置） |
| 灰度设备完全无法上网 | 0.5 节点握手问题，先回滚，让用户换节点/换协议再试 |
| 用户要 IPv6 | 本套件刻意 ipv4_only + ::/0 reject；v6 是二期工程，先说明再谈 |
