#!/bin/sh
# install.sh - 在 GL-MT3600BE 上安装/升级 sing-box 透明代理
#
# 用法: 在 Mac 上执行
#   ./install.sh                  # 只安装文件, 不启动任何服务
#   ./install.sh --start          # 安装并启动 sing-box (不劫持流量)
#   ./install.sh --gray <IP>      # 安装 + 灰度代理指定设备
#   ./install.sh --full           # 安装 + 全量代理
#   ./install.sh --rollback       # 完全回滚
#
# 设计原则: 默认什么都不启动, 每一步都要显式要求。

set -e

ROUTER="${ROUTER:-root@192.168.8.1}"  # 也可用环境变量覆盖; ssh config 建议配好 Host router
HERE="$(cd "$(dirname "$0")" && pwd)"
LAB="$HERE"            # 规则集与二进制都在 files/ 下
SB_VER="1.14.1"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

rsh() { ssh -o BatchMode=yes "$ROUTER" "$@"; }
rput() { scp -O -q "$@" "$ROUTER:/tmp/"; }

check_router() {
	say "检查路由器连通性"
	rsh 'true' || die "SSH 连不上 $ROUTER"
	M=$(rsh 'cat /tmp/sysinfo/model')
	say "型号: $M"
	case "$M" in
		*MT3600BE*) : ;;
		*) warn "非预期型号 ($M), 继续前请确认" ;;
	esac
}

get_binary() {
	if [ -f "$HERE/sing-box" ]; then
		say "使用本地二进制 $HERE/sing-box"
		return
	fi
	[ -f "$LAB/sing-box-${SB_VER}-linux-arm64-musl/sing-box" ] && return
	say "下载 sing-box $SB_VER (musl 静态版)"
	cd "$LAB"
	curl -sSL -o sb.tar.gz \
	  "https://gh-proxy.com/https://github.com/SagerNet/sing-box/releases/download/v${SB_VER}/sing-box-${SB_VER}-linux-arm64-musl.tar.gz" \
	  || die "下载失败"
	tar xzf sb.tar.gz || die "解压失败"
	rm -f sb.tar.gz
	[ -f "sing-box-${SB_VER}-linux-arm64-musl/sing-box" ] || die "未找到二进制"
}

install_files() {
	say "创建目录"
	rsh 'mkdir -p /etc/sing-box/rules /var/log'

	say "上传 sing-box 二进制 (85MB, 压缩传输约 5 秒)"
	# 先传到 /tmp 再移动到 /usr/bin (overlay), 避免中途断电留下半个文件
	scp -O -C -q "$HERE/sing-box-${SB_VER}-linux-arm64-musl/sing-box" "$ROUTER:/tmp/sing-box.new"
	rsh 'chmod +x /tmp/sing-box.new && mv /tmp/sing-box.new /usr/bin/sing-box'
	rsh '/usr/bin/sing-box version | head -1'

	say "上传配置"
	rput "$HERE/sing-box.json"; rsh 'mkdir -p /etc/sing-box && mv /tmp/sing-box.json /etc/sing-box/config.json'

	say "上传规则集"
	for _p in "$HERE"/rules/*.srs; do
		f="$(basename "$_p")"
		if [ -f "$HERE/rules/$f" ]; then
			rput "$HERE/rules/$f"; rsh "mv /tmp/$f /etc/sing-box/rules/$f"
		else
			warn "缺少规则集 $f"
		fi
	done

	say "上传脚本"
	rput "$HERE/sb-tproxy" "$HERE/sing-box.init" "$HERE/sb-tproxy.init" "$HERE/proxy_ips.example"
	rsh 'mv /tmp/sb-tproxy /etc/sing-box/sb-tproxy && chmod +x /etc/sing-box/sb-tproxy
	     mv /tmp/sing-box.init /etc/init.d/sing-box && chmod +x /etc/init.d/sing-box
	     mv /tmp/sb-tproxy.init /etc/init.d/sb-tproxy && chmod +x /etc/init.d/sb-tproxy
	     mv /tmp/proxy_ips.example /etc/sing-box/proxy_ips'

	say "上传 sb 运维 CLI 与辅助脚本"
	rput "$HERE/sb" "$HERE/sb-log-trim.sh" "$HERE/sb-completion.sh"
	rsh 'mv /tmp/sb /usr/bin/sb && chmod +x /usr/bin/sb
	     mv /tmp/sb-log-trim.sh /usr/bin/sb-log-trim.sh && chmod +x /usr/bin/sb-log-trim.sh
	     mkdir -p /etc/profile.d && mv /tmp/sb-completion.sh /etc/profile.d/sb-completion.sh
	     (crontab -l 2>/dev/null | grep -v sb-log-trim; echo "0 * * * * /usr/bin/sb-log-trim.sh") | crontab -'

	say "校验配置"
	rsh '/etc/init.d/sing-box enabled 2>/dev/null; /usr/bin/sing-box check -c /etc/sing-box/config.json && echo "配置OK"'
}

do_rollback() {
	say "完全回滚"
	rsh '/etc/init.d/sb-tproxy stop 2>/dev/null; /etc/init.d/sing-box stop 2>/dev/null; /etc/sing-box/sb-tproxy stop 2>/dev/null; true'
	say "自检残留"
	rsh '/etc/sing-box/sb-tproxy verify'
	say "已回滚 (二进制和配置保留, 只是不再运行)"
}

case "${1:-}" in
	"")
		check_router; get_binary; install_files
		say "安装完成。未启动任何服务。"
		echo "  下一步:"
		echo "    $0 --start          # 启动 sing-box (不劫持流量)"
		echo "    $0 --gray 192.168.8.118   # 灰度代理指定设备"
		;;
	--start)
		say "启动 sing-box (此时还不劫持任何流量)"
		rsh '/etc/init.d/sing-box start; sleep 3; ps w | grep [s]ing-box | head -2; netstat -ltn | grep 7895'
		say "完成。全屋上网应完全不受影响。"
		;;
	--gray)
		IP="${2:?用法: $0 --gray <设备IP>}"
		say "灰度: 只代理 $IP"
		rsh "echo '$IP/32' > /etc/sing-box/tproxy.src"
		rsh '/etc/sing-box/sb-tproxy start && /etc/sing-box/sb-tproxy status'
		say "完成。只有 $IP 走代理。"
		echo "  回滚: $0 --rollback"
		;;
	--full)
		say "全量代理整个 LAN"
		rsh 'rm -f /etc/sing-box/tproxy.src; /etc/sing-box/sb-tproxy start && /etc/sing-box/sb-tproxy status'
		warn "现在全屋流量都走代理了。出问题执行: $0 --rollback"
		;;
	--verify)
		rsh '/etc/sing-box/sb-tproxy status; echo; /etc/sing-box/sb-tproxy verify'
		;;
	--rollback) do_rollback ;;
	*) sed -n '2,12p' "$0"; exit 1 ;;
esac
