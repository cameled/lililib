#!/bin/bash

SELF_DIR="$(dirname "$(readlink -f "$0")")"


# 配置参数
DEVICE="/dev/video0"
WIDTH=800
HEIGHT=600
FPS=60
DURATION=10
OUTPUT_FILE="${SELF_DIR}/mjpg_capture_${WIDTH}x${HEIGHT}_${FPS}fps.mkv"

echo "📌 正在测量 $WIDTH×$HEIGHT @ $FPS FPS MJPG 码率..."
echo "📌 设备: $DEVICE"
echo "📌 录制时长: $DURATION 秒"
echo "📌 输出文件: $OUTPUT_FILE"

# Step 1: 使用 ffmpeg 直接录制 DURATION 秒
echo -e "\n🎥 开始录制..."
ffmpeg -y \
    -f v4l2 \
    -input_format mjpeg \
    -framerate "$FPS" \
    -video_size "${WIDTH}x${HEIGHT}" \
    -i "$DEVICE" \
    -c:v copy \
    -t "$DURATION" \
    -f matroska \
    "$OUTPUT_FILE" \
    -loglevel error

if [ $? -ne 0 ] || [ ! -f "$OUTPUT_FILE" ] || [ ! -s "$OUTPUT_FILE" ]; then
    echo "❌ 录制失败：文件未生成或为空。请检查设备是否被占用或支持该格式。"
    exit 1
fi

echo "✅ 录制完成：$OUTPUT_FILE"

# Step 2: 使用 ffprobe 分析实际码率
# DURATION_ACTUAL=$(ffprobe -v error -show_entries format=duration -of default=nw=1 "$OUTPUT_FILE" | head -n1)
DURATION_ACTUAL=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUTPUT_FILE")
SIZE_BYTES=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || ls -l "$OUTPUT_FILE" | awk '{print $5}')
SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1024 / 1024" | bc -l)
BITRATE_BPS=$(echo "scale=2; $SIZE_BYTES * 8 / $DURATION_ACTUAL" | bc -l)
BITRATE_MBPBS=$(echo "scale=2; $BITRATE_BPS / 1000000" | bc -l)

rm -f "$OUTPUT_FILE"

# 格式化输出
printf "\n📊 测量结果\n"
printf "────────────────────────────\n"
printf "📁 文件大小: %s MB\n" "$SIZE_MB"
printf "⏱  实际时长: %.2f 秒\n" "$DURATION_ACTUAL"
printf "📊 平均码率: %.2f Mbps\n" "$BITRATE_MBPBS"
printf "────────────────────────────\n"

exit 0