#!/usr/bin/env bash
#
# X1301 / TC358743 bring-up and capture configuration
# ---------------------------------------------------
#
# This script configures a Geekworm X1301 HDMI -> CSI-2 bridge on a
# Raspberry Pi 5 using the Linux V4L2 Media Controller API.
#
# It intentionally does NOT assume:
#
#   - /dev/v4l-subdev2 is always the TC358743
#   - /dev/media0 is always RP1 CFE
#   - /dev/video0 is always the capture node
#   - HDMI is already present when the script starts
#   - the HDMI source is necessarily outputting 1920x1080
#
# Instead it discovers the active RP1 CFE graph and extracts the
# actual device nodes from that graph.
#
# Expected hardware path:
#
#   HDMI source
#       |
#       v
#   Geekworm X1301
#       |
#       | TC358743
#       v
#   Raspberry Pi CSI-2
#       |
#       v
#   RP1 CFE
#       |
#       v
#   /dev/video*
#
# On our current Raspberry Pi 5 installation the X1301 is connected
# to CAM/DISP0 and is enabled with:
#
#   dtoverlay=tc358743,cam0
#   dtoverlay=tc358743-audio
#
# The TC358743 therefore currently appears on I2C10 as:
#
#   tc358743 10-000f
#
# However, this script does not hard-code that I2C bus.
#
# Exit codes:
#
#   1  missing dependency / not root
#   2  RP1 CFE + TC358743 media graph not found
#   3  TC358743 V4L2 subdevice could not be discovered
#   4  HDMI timings did not become valid
#   5  required CSI2 -> CFE media link could not be enabled
#   6  HDMI timing resolution could not be parsed
#   7  capture node could not be discovered/configured
#

set -euo pipefail

source "$(dirname "$0")/common.sh"

need v4l2-ctl
need media-ctl
need awk
need grep

[[ $EUID -eq 0 ]] || {
    echo "ERROR: this script must run as root."
    echo "Run:"
    echo
    echo "    sudo $0"
    echo
    exit 1
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

LOG="$LOG_DIR/configure-$(timestamp).log"

# Send all subsequent stdout/stderr both to the terminal and our logfile.
exec > >(tee "$LOG") 2>&1


# ---------------------------------------------------------------------------
# Helper: extract the device node belonging to a media-controller entity
# ---------------------------------------------------------------------------
#
# Example media-ctl graph fragment:
#
#   - entity 16: tc358743 10-000f (1 pad, 1 link)
#       type V4L2 subdev subtype Unknown flags 0
#       device node name /dev/v4l-subdev2
#
# Given the graph and an entity-name regex, return:
#
#   /dev/v4l-subdev2
#
# This is much safer than grepping `v4l2-ctl --all`, because another
# subdevice can mention tc358743 merely because it is LINKED to it.
#
find_entity_node() {
    local graph="$1"
    local entity_regex="$2"

    awk -v entity_regex="$entity_regex" '
        /^- entity / {
            matched = ($0 ~ entity_regex)
        }

        matched && /device node name/ {
            print $NF
            exit
        }
    ' <<<"$graph"
}


# ---------------------------------------------------------------------------
# DISCOVERY
# ---------------------------------------------------------------------------

section "DISCOVERY"

MEDIA=""
SUBDEV=""
VIDEO=""
GRAPH=""

#
# Locate the media-controller graph that actually contains all of:
#
#   tc358743
#   csi2
#   rp1-cfe
#
# This avoids assuming /dev/media0.
#
for m in /dev/media*; do
    [[ -e "$m" ]] || continue

    candidate_graph="$(media-ctl -d "$m" -p 2>&1 || true)"

    if grep -qi 'tc358743' <<<"$candidate_graph" &&
       grep -qi 'csi2' <<<"$candidate_graph" &&
       grep -qi 'rp1-cfe' <<<"$candidate_graph"; then

        MEDIA="$m"
        GRAPH="$candidate_graph"
        break
    fi
done

if [[ -z "$MEDIA" ]]; then
    echo "ERROR: could not find an RP1 CFE media graph containing TC358743."
    echo
    echo "Available media devices:"
    ls -l /dev/media* 2>/dev/null || true
    exit 2
fi

echo "MEDIA=$MEDIA"

#
# Extract the ACTUAL device node belonging to the tc358743 entity.
#
# On the current system this should resolve to something such as:
#
#   /dev/v4l-subdev2
#
SUBDEV="$(find_entity_node "$GRAPH" 'tc358743')"

if [[ -z "$SUBDEV" || ! -e "$SUBDEV" ]]; then
    echo "ERROR: TC358743 entity exists, but its V4L2 subdevice could not be determined."
    echo
    echo "Current media graph:"
    echo "$GRAPH"
    exit 3
fi

echo "SUBDEV=$SUBDEV"

#
# Discover the primary raw CSI2 channel from the same graph.
#
# Normally this is:
#
#   rp1-cfe-csi2_ch0 -> /dev/video0
#
VIDEO="$(find_entity_node "$GRAPH" 'rp1-cfe-csi2_ch0')"

if [[ -n "$VIDEO" ]]; then
    echo "CAPTURE_NODE=$VIDEO"
else
    echo "CAPTURE_NODE=(will rediscover after graph configuration)"
fi


# ---------------------------------------------------------------------------
# LOAD EDID
# ---------------------------------------------------------------------------

section "LOAD EDID"

EDID="$REPO_ROOT/tools/x1301/1080P60EDID.txt"

if [[ ! -f "$EDID" ]]; then
    echo "ERROR: EDID file not found:"
    echo
    echo "    $EDID"
    echo
    exit 1
fi

echo "Loading EDID:"
echo "  $EDID"
echo
echo "Into:"
echo "  $SUBDEV"

#
# Loading a new EDID can intentionally make the HDMI source drop the current
# connection and renegotiate. Therefore a temporary "Link has been severed"
# immediately after this command is not necessarily an error.
#
v4l2-ctl \
    -d "$SUBDEV" \
    --set-edid=file="$EDID" \
    --fix-edid-checksums


# ---------------------------------------------------------------------------
# WAIT FOR HDMI / EDID RENEGOTIATION
# ---------------------------------------------------------------------------

section "WAIT FOR HDMI"

TIMINGS=""
TIMINGS_OK=0

#
# Give the source up to 20 seconds to:
#
#   1. notice the EDID change
#   2. perform HDMI/HPD negotiation
#   3. select an output mode
#   4. begin sending valid timings
#
for attempt in $(seq 1 20); do

    echo "Querying HDMI timings... attempt $attempt/20"

    if TIMINGS="$(v4l2-ctl \
        -d "$SUBDEV" \
        --query-dv-timings \
        2>&1)"; then

        TIMINGS_OK=1
        echo
        echo "$TIMINGS"
        break
    fi

    echo "$TIMINGS"
    echo

    sleep 1
done

if [[ "$TIMINGS_OK" -ne 1 ]]; then
    echo
    echo "ERROR: HDMI did not establish valid DV timings."
    echo
    echo "The TC358743 itself is present, but no usable HDMI timing"
    echo "was detected after loading the EDID."
    echo
    echo "Check:"
    echo "  - HDMI source is powered"
    echo "  - HDMI output is enabled"
    echo "  - cable is connected to X1301 HDMI IN"
    echo "  - source supports a mode advertised by the EDID"
    echo
    echo "Log:"
    echo "  $LOG"
    exit 4
fi


# ---------------------------------------------------------------------------
# EXTRACT DETECTED RESOLUTION
# ---------------------------------------------------------------------------

section "DETECTED HDMI MODE"

WIDTH="$(
    awk -F: '
        /Active width:/ {
            gsub(/[[:space:]]/, "", $2)
            print $2
            exit
        }
    ' <<<"$TIMINGS"
)"

HEIGHT="$(
    awk -F: '
        /Active height:/ {
            gsub(/[[:space:]]/, "", $2)
            print $2
            exit
        }
    ' <<<"$TIMINGS"
)"

if [[ ! "$WIDTH" =~ ^[0-9]+$ ]] ||
   [[ ! "$HEIGHT" =~ ^[0-9]+$ ]] ||
   [[ "$WIDTH" -le 0 ]] ||
   [[ "$HEIGHT" -le 0 ]]; then

    echo "ERROR: unable to determine active HDMI width/height."
    echo
    echo "$TIMINGS"
    exit 6
fi

echo "WIDTH=$WIDTH"
echo "HEIGHT=$HEIGHT"


# ---------------------------------------------------------------------------
# APPLY DETECTED HDMI TIMINGS TO TC358743
# ---------------------------------------------------------------------------

section "APPLY HDMI TIMINGS"

#
# `query` tells the driver to apply the timings currently detected from
# the HDMI source.
#
v4l2-ctl \
    -d "$SUBDEV" \
    --set-dv-bt-timings query


# ---------------------------------------------------------------------------
# RESET MEDIA GRAPH
# ---------------------------------------------------------------------------

section "RESET MEDIA GRAPH"

#
# Reset mutable links/formats before rebuilding the capture route.
#
# Immutable links remain intact.
#
media-ctl \
    -d "$MEDIA" \
    -r


# ---------------------------------------------------------------------------
# ENABLE CSI2 -> RP1 CFE CAPTURE LINK
# ---------------------------------------------------------------------------

section "ENABLE CSI2 -> CFE LINK"

#
# On RP1 CFE, csi2 pad 4 is routed to the primary capture channel:
#
#   csi2:4
#      |
#      v
#   rp1-cfe-csi2_ch0:0
#
# This is the raw capture path we want for the HDMI bridge.
#
if ! media-ctl \
    -d "$MEDIA" \
    -l "'csi2':4 -> 'rp1-cfe-csi2_ch0':0 [1]"; then

    echo
    echo "ERROR: could not enable CSI2 -> RP1 CFE capture link."
    echo
    echo "Current media graph:"
    media-ctl -d "$MEDIA" -p || true
    exit 5
fi


# ---------------------------------------------------------------------------
# CONFIGURE CSI2 FORMAT
# ---------------------------------------------------------------------------

section "CONFIGURE CSI2 FORMAT"

#
# TC358743 exposes 24-bit RGB over CSI-2.
#
# Rather than assuming 1920x1080, use whatever HDMI active resolution
# was actually detected above.
#
# Examples:
#
#   640x480
#   1280x720
#   1920x1080
#
MEDIA_FMT="RGB888_1X24/${WIDTH}x${HEIGHT}"

echo "Media bus format:"
echo "  $MEDIA_FMT"

#
# csi2 pad 0 = sink from TC358743
#
media-ctl \
    -d "$MEDIA" \
    -V "'csi2':0 [fmt:${MEDIA_FMT} field:none colorspace:srgb]"

#
# csi2 pad 4 = source toward primary capture channel
#
media-ctl \
    -d "$MEDIA" \
    -V "'csi2':4 [fmt:${MEDIA_FMT} field:none colorspace:srgb]"


# ---------------------------------------------------------------------------
# REFRESH GRAPH AFTER CONFIGURATION
# ---------------------------------------------------------------------------

section "FINAL MEDIA GRAPH"

media-ctl -d "$MEDIA" -p

#
# Re-read the graph because resetting/reconfiguring it may alter state.
#
GRAPH="$(media-ctl -d "$MEDIA" -p 2>&1)"


# ---------------------------------------------------------------------------
# DISCOVER PRIMARY VIDEO CAPTURE NODE
# ---------------------------------------------------------------------------

section "CAPTURE NODE"

VIDEO="$(find_entity_node "$GRAPH" 'rp1-cfe-csi2_ch0')"

if [[ -z "$VIDEO" || ! -e "$VIDEO" ]]; then
    echo "WARNING: could not determine rp1-cfe-csi2_ch0 directly."
    echo "Trying generic Video Capture nodes..."

    for v in /dev/video*; do
        [[ -e "$v" ]] || continue

        info="$(v4l2-ctl -d "$v" --all 2>&1 || true)"

        if grep -qiE \
            'Video Capture|Video Capture Multiplanar' \
            <<<"$info"; then

            if v4l2-ctl \
                -d "$v" \
                --set-fmt-video=width="$WIDTH",height="$HEIGHT",pixelformat=RGB3 \
                >/dev/null 2>&1; then

                fmt="$(v4l2-ctl -d "$v" --get-fmt-video 2>&1 || true)"

                if grep -q 'RGB3' <<<"$fmt"; then
                    VIDEO="$v"
                    break
                fi
            fi
        fi
    done
fi

if [[ -z "$VIDEO" || ! -e "$VIDEO" ]]; then
    echo
    echo "ERROR: no usable RP1 CFE capture device was found."
    exit 7
fi

echo "VIDEO=$VIDEO"


# ---------------------------------------------------------------------------
# CONFIGURE V4L2 CAPTURE FORMAT
# ---------------------------------------------------------------------------

section "CONFIGURE VIDEO CAPTURE"

echo "Requesting:"
echo "  ${WIDTH}x${HEIGHT} RGB3"
echo
echo "Device:"
echo "  $VIDEO"

v4l2-ctl \
    -d "$VIDEO" \
    --set-fmt-video=width="$WIDTH",height="$HEIGHT",pixelformat=RGB3

echo
v4l2-ctl \
    -d "$VIDEO" \
    --get-fmt-video


# ---------------------------------------------------------------------------
# FINAL STATUS
# ---------------------------------------------------------------------------

section "RESULT"

echo "X1301_STATUS=CONFIGURED"
echo "MEDIA=$MEDIA"
echo "SUBDEV=$SUBDEV"
echo "VIDEO=$VIDEO"
echo "WIDTH=$WIDTH"
echo "HEIGHT=$HEIGHT"
echo "PIXELFORMAT=RGB3"

#
# Other scripts such as capture-test.sh can use this instead of assuming
# /dev/video0.
#
echo "$VIDEO" > "$LOG_DIR/last-video-node.txt"

#
# Also save the detected mode for later EVF/service use.
#
cat > "$LOG_DIR/last-mode.env" <<EOF
X1301_MEDIA=$MEDIA
X1301_SUBDEV=$SUBDEV
X1301_VIDEO=$VIDEO
X1301_WIDTH=$WIDTH
X1301_HEIGHT=$HEIGHT
X1301_PIXELFORMAT=RGB3
EOF

echo
echo "Saved capture node:"
echo "  $LOG_DIR/last-video-node.txt"

echo
echo "Saved detected mode:"
echo "  $LOG_DIR/last-mode.env"

echo
echo "Log:"
echo "  $LOG"

echo
echo "X1301 configuration complete."