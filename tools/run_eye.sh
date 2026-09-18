#!/bin/bash
# يشغّل اللعبة على شاشة افتراضية ويأخذ لقطات كل ثانيتين إلى eye/
# الاستخدام: tools/run_eye.sh <seconds> [extra godot user args...]
SECS=${1:-30}; shift
export DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1
pgrep -x Xvfb >/dev/null || (Xvfb :99 -screen 0 800x1400x24 >/tmp/xvfb.log 2>&1 &) ; sleep 1
cd /home/user/webapp
rm -rf eye && mkdir -p eye
timeout $SECS /home/user/godot/Godot_v4.7.2-stable_linux.x86_64 --path /home/user/webapp --rendering-driver opengl3 --resolution 540x960 --audio-driver Dummy -- --eye=/home/user/webapp/eye "$@" > eye/log.txt 2>&1
echo "exit=$?"; grep -E "ERROR|SCRIPT ERROR|at:" eye/log.txt | grep -v -E "ALSA|alsa|audio" | head -30
ls eye | head -50
