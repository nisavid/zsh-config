#!/usr/bin/env zsh

emulate -L zsh
setopt errexit extendedglob nounset pipefail

local tmpdir=$(mktemp -d)
trap 'rm -rf -- $tmpdir' EXIT

local fixture=$tmpdir/pf-glow-markdown-probe.md
cat >$fixture <<'EOF'
# PF_GLOW_MARKDOWN_PROBE

**PF_GLOW_STRONG_PROBE**
EOF

local output
output=$(BAT_PAGER=cat zsh -lic "PAGER=false; pf ${(q)fixture}" 2>/dev/null)
local plain=${output//$'\e'\[[0-9;]##m/}

[[ $plain == *PF_GLOW_MARKDOWN_PROBE* ]]
[[ $plain != *'# PF_GLOW_MARKDOWN_PROBE'* ]]
[[ $plain != *'**PF_GLOW_STRONG_PROBE**'* ]]
[[ $plain == *'─────'* ]]
[[ $plain == *'File:'* ]]
