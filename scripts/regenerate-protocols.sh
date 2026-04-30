#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

scanner="${WAYLAND_SCANNER:-wayland-scanner}"
protocol_dir="src/lockme/protocols"
xml_dir="$protocol_dir/xml"

generate() {
	protocol="$1"
	base="$2"

	"$scanner" client-header \
		"$xml_dir/$protocol.xml" \
		"$protocol_dir/$base-client-protocol.h"
	"$scanner" private-code \
		"$xml_dir/$protocol.xml" \
		"$protocol_dir/$base-protocol.c"
}

generate ext-session-lock-v1 ext-session-lock-v1
generate single-pixel-buffer-v1 single-pixel-buffer-v1
generate viewporter viewporter
