# sb 命令 Tab 补全 (busybox ash)
_sb_complete() {
	local cur words
	cur="${READLINE_LINE:-$2}"
	words="status on off restart verify log devices targets trace watch sniff bypass rules add-rule del-rule update-rules help"
	if [ -z "$cur" ]; then
		COMPREPLY=$words
	else
		COMPREPLY=$(echo "$words" | tr " " "\n" | grep "^$cur" | tr "\n" " ")
	fi
}
complete -F _sb_complete sb 2>/dev/null || true
