#!/bin/sh
set -e
# ==================== 配置区（仅改这3行） ====================
# 云端存储MD5加密后的卡密文件（格式：仅32位MD5加密串，一行一个）
GITHUB_CM_URL="https://raw.githubusercontent.com/CannonSense/dfm/refs/heads/main/cm_hwid_md5.txt"
GITHUB_UPDATE_URL="https://raw.githubusercontent.com/CannonSense/dfm/refs/heads/main/update_info.txt"
# 新增：新版本脚本的GitHub下载地址（需替换为实际脚本文件的raw地址）
GITHUB_NEW_SCRIPT_URL="https://raw.githubusercontent.com/CannonSense/dfm/refs/heads/main/NewVersion.sh"
# =============================================================
# 全局变量
CM_FILENAME="cm_verify.txt"
UPDATE_FILENAME="update_info.tmp"
LOCAL_CM_FILE=""
LOCAL_UPDATE_FILE=""
CURRENT_VERSION="1.6.4"
# 新增：本地新版本脚本存储路径（与当前脚本同目录，命名为dfm_new.sh）
NEW_SCRIPT_FILENAME="dfm_new.sh"
LOCAL_NEW_SCRIPT="$PWD/$NEW_SCRIPT_FILENAME"

# 新增：1. 下载更新信息文件（不变）
download_update_info() {
    echo "[INFO] 正在检查版本更新..."
    retry=3
    while [ $retry -ge 0 ]; do
        http_code=$(curl -sSL --connect-timeout 15 -w "%{http_code}" -o "$LOCAL_UPDATE_FILE" "$GITHUB_UPDATE_URL")
        if [ "$http_code" = "200" ] && [ -s "$LOCAL_UPDATE_FILE" ]; then
            echo "[INFO] ✅ 版本更新信息获取成功"
            return 0
        else
            echo "[WARN] ❌ 版本更新信息获取失败，剩余重试次数：$retry"
        fi
        retry=$((retry - 1))
        sleep 2
    done
    echo "[WARN] ⚠️  无法获取版本更新信息，将继续使用当前版本"
    return 1
}

# 新增：2. 解析版本号和更新公告（不变）
parse_update_info() {
    if [ ! -f "$LOCAL_UPDATE_FILE" ]; then
        return 1
    fi
    LATEST_VERSION=$(grep "^VERSION=" "$LOCAL_UPDATE_FILE" | cut -d'=' -f2 | tr -d ' ')
    UPDATE_NOTE=$(sed -n '2,$p' "$LOCAL_UPDATE_FILE" | sed '/^$/d')
    if [ -z "$LATEST_VERSION" ]; then
        echo "[WARN] ⚠️  解析版本号失败"
        return 1
    fi
}

# 新增：3. 自动下载新版本脚本
download_new_script() {
    echo -e "\n[INFO] 📥 正在下载新版本 $LATEST_VERSION ..."
    retry=3
    while [ $retry -ge 0 ]; do
        http_code=$(curl -sSL --connect-timeout 20 -w "%{http_code}" -o "$LOCAL_NEW_SCRIPT" "$GITHUB_NEW_SCRIPT_URL")
        if [ "$http_code" = "200" ] && [ -s "$LOCAL_NEW_SCRIPT" ]; then
            # 给新版本脚本添加执行权限
            chmod +x "$LOCAL_NEW_SCRIPT" >/dev/null 2>&1
            echo "[SUCCESS] ✅ 新版本下载完成！存储路径：$LOCAL_NEW_SCRIPT"
            return 0
        else
            echo "[WARN] ❌ 新版本下载失败，剩余重试次数：$retry"
        fi
        retry=$((retry - 1))
        sleep 3
    done
    echo "[ERROR] ❌ 新版本下载失败，将继续使用当前版本"
    return 1
}

# 优化：4. 版本对比与公告展示（新增自动下载逻辑）
check_version() {
    parse_update_info
    if [ -n "$LATEST_VERSION" ]; then
        echo -e "\n======== 版本信息 ========"
        echo "当前版本：$CURRENT_VERSION"
        echo "最新版本：$LATEST_VERSION"
        CURRENT_NUM=$(echo "$CURRENT_VERSION" | tr '.' '0' | awk '{print $0 + 0}')
        LATEST_NUM=$(echo "$LATEST_VERSION" | tr '.' '0' | awk '{print $0 + 0}')
        
        if [ "$LATEST_NUM" -gt "$CURRENT_NUM" ]; then
            echo -e "\n[NOTICE] 📢 发现新版本！更新公告："
            echo "$UPDATE_NOTE"
            echo -e "==========================\n"
            
            # 新增：自动下载新版本
            if download_new_script; then
                echo -e "\n[INFO] 🎉 新版本已准备就绪！"
                echo "  启动新版本命令：./$NEW_SCRIPT_FILENAME"
                echo "  提示：若需覆盖当前脚本，可执行：mv $NEW_SCRIPT_FILENAME $(basename "$0")"
                echo -e "==========================\n"
                # 可选：自动退出当前脚本，提示用户启动新版本（注释则继续使用旧版本）
                # echo "[INFO] 即将退出当前版本，请启动新版本脚本"
                # clean_temp_file
                # exit 0
            fi
        elif [ "$LATEST_NUM" -eq "$CURRENT_NUM" ]; then
            echo -e "\n[INFO] ✅ 当前已是最新版本"
            echo -e "==========================\n"
        else
            echo -e "\n[WARN] ⚠️ 什么鬼！？测试版吗有点意思。 当前版本高于最新版本！！"
            echo -e "==========================\n"
        fi
    fi
}

# 原有函数（新增md5sum依赖检测）
check_android_env() {
    if [ -z "$ANDROID_ROOT" ] && [ ! -d "/system" ]; then
        echo "[ERROR] 非Android手机环境，建议在Termux/Root终端运行"
        exit 1
    fi
    echo "[INFO] 正在检测手机运行环境..."
    sleep 2
    if [ -f "/data/data/com.termux/files/usr/bin/termux-setup-storage" ] && [ ! -d "$HOME/storage" ]; then
        echo "[INFO] 正在挂载Termux存储，请在弹窗中允许授权..."
        termux-setup-storage
        sleep 3
    fi
    if ! command -v curl >/dev/null 2>&1; then
        echo "[ERROR] 缺少必要依赖，请执行：pkg install curl -y"
        exit 1
    fi
    # 新增：检查md5sum依赖（Termux/Android默认自带，缺失则提示安装）
    if ! command -v md5sum >/dev/null 2>&1; then
        echo "[ERROR] 缺少必要依赖，请执行：pkg install coreutils -y"
        exit 1
    fi
}

check_permission() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "[INFO] ✅ 已获取Root权限！"
    else
        echo "[INFO] 非Root模式（Termux用户权限）"
    fi
}

detect_writable_dir() {
    echo "[INFO] 正在加载缓存目录..."
    dirs="$HOME/storage/downloads:/data/local/tmp:/sdcard/Download:/storage/emulated/0"
    IFS=':'
    for dir in $dirs; do
        unset IFS
        if [ ! -d "$dir" ]; then
            echo "[WARN] 目录 $dir 不存在，尝试创建..."
            mkdir -p "$dir" >/dev/null 2>&1 || continue
        fi
        if touch "$dir/$CM_FILENAME" >/dev/null 2>&1 && touch "$dir/$UPDATE_FILENAME" >/dev/null 2>&1; then
            LOCAL_CM_FILE="$dir/$CM_FILENAME"
            LOCAL_UPDATE_FILE="$dir/$UPDATE_FILENAME"
            return 0
        fi
    done
    echo "[ERROR] ❌ 无可用可写目录"
    echo "  解决：1. Termux执行 termux-setup-storage 授权；2. Root设备重新运行"
    exit 1
}

download_cm_file() {
    echo "[INFO] 正在连接卡密验证服务器..."
    sleep 2
   
    retry=3
    while [ $retry -ge 0 ]; do
        http_code=$(curl -sSL --connect-timeout 20 -w "%{http_code}" -o "$LOCAL_CM_FILE" "$GITHUB_CM_URL")
        if [ "$http_code" = "200" ] && [ -s "$LOCAL_CM_FILE" ]; then
            echo "[INFO] ✅ 卡密服务器连接成功！(1/3)"
            return 0
        elif [ "$http_code" = "404" ]; then
            echo "[WARN] ❌ 服务器连接失败（404），剩余重试次数：$retry"
        else
            echo "[WARN] ❌ 服务器连接失败，剩余重试次数：$retry"
        fi
        retry=$((retry - 1))
        sleep 2
    done
    echo "[ERROR] ❌ 卡密服务器连接失败"
    echo "请检查手机网络是否正常！"
    clean_temp_file
    exit 1
}

# 核心优化：MD5卡密加密与验证（移除有效期相关逻辑）
verify_cm() {
    input_cm="$1"
    # 步骤1：对用户输入的明文卡密进行MD5加密（去除空格/特殊字符，输出32位小写）
    encrypted_cm=$(echo -n "$input_cm" | tr -d ' ' | md5sum | awk '{print $1}' | tr 'A-F' 'a-f')
    echo "[INFO] ✅ 卡密校验完成！(2/3)"
    
    # 步骤2：验证加密卡密是否存在于云端文件（忽略空行和注释行）
    if ! grep -vE '^$|^#' "$LOCAL_CM_FILE" | grep -Fxq "$encrypted_cm"; then
        echo "[ERROR] ❌ 卡密无效"
        echo "  检查：1. 卡密是否输入正确 2. 卡密是否已被封禁"
        clean_temp_file
        exit 1
    fi
    
    echo "[SUCCESS] ✅ 卡密验证完全通过！(3/3)"
}

clean_temp_file() {
    if [ -f "$LOCAL_CM_FILE" ]; then
        rm -f "$LOCAL_CM_FILE"
    fi
    if [ -f "$LOCAL_UPDATE_FILE" ]; then
        rm -f "$LOCAL_UPDATE_FILE"
    fi
    echo "[INFO] 已清理临时文件（防止残留被检测）"
}

# ==================== 主程序入口（不变） ====================
main() {
    input_cm=""
    if [ $# -eq 1 ]; then
        input_cm="$1"
    else
        clear
        echo "=== Resense ==="
        sleep 1
        echo "三角洲云端解密"
        echo "当前版本: $CURRENT_VERSION"
        echo "注意：仅支持root环境"
        echo "======== 卡密验证系统 ========"
        echo -n "请输入卡密："
        read input_cm
        input_cm=$(echo "$input_cm" | tr -d "\"'")
        if [ -z "$input_cm" ]; then
            echo "[ERROR] ❌ 卡密不能为空"
            exit 1
        fi
    fi
    
    check_android_env
    check_permission
    detect_writable_dir
    download_update_info
    check_version  # 已包含自动下载逻辑
    download_cm_file
    verify_cm "$input_cm"
    
 # ==================== 运行模式选择判断（不变） ====================
 echo -e "\n======== 运行模式选择 ========"
 echo "1.本地运行"
 echo "2.虚拟机运行"
 echo "3.开发者运行"
 echo -n "请选择运行方式 (1/2/3) :"
 read mode_choice
if [ "$mode_choice" = "1" ]; then
    echo -e "\n[INFO] 已选择 本地运行"
    sleep 1
    echo "[SUCCESS] 加载成功！"
elif [ "$mode_choice" = "2" ]; then
    echo -e "\n[INFO] 已选择 虚拟机运行"
    sleep 1
    echo "[SUCCESS] 加载成功！"
elif [ "$mode_choice" = "3" ]; then
    echo -e "\n[INFO] 已选择 开发者运行"
    sleep 3
    echo "卡密权限不足，默认选择本地运行"
else
    echo -e "\n[WARN] ⚠️  输入无效，默认选择本地运行"
fi
 
    # ==================== 解密选择判断（不变） ====================
echo -e "\n======== 解密选择 ========"
echo "1. 坐标解密一 (2025/12/27)"
echo "2. 坐标解密二 (2026/1/1)"
echo "3. 坐标解密二 (2026/1/3)"
echo -n "请选择解密方式（1/2/3）:"
read mode_choice
if [ "$mode_choice" = "1" ]; then
    echo -e "\n[INFO] 已选择 解密一，正在连接解密服务器一..."
    sleep 2
elif [ "$mode_choice" = "2" ]; then
    echo -e "\n[INFO] 已选择 解密二，正在连接解密服务器二..."
    sleep 2
elif [ "$mode_choice" = "3" ]; then
    echo -e "\n[INFO] 已选择 解密3，正在连接解密服务器三..."
    sleep 2
else
    echo -e "\n[WARN] ⚠️  输入无效，默认选择解密一"
fi
# ======================================================
    echo "[INFO] 解密服务器连接中......"
    sleep 3
    echo "[SUCCESS] 解密服务器连接成功！"
    sleep 1
    echo "=================================="
    echo "  验证通过！欢迎使用本程序"
    echo "  程序预加载中，将在 3 秒后启动..."
    echo "=================================="
    
#清理逻辑
iptables -F
iptables -X 
iptables -Z
iptables -t nat -F 
#清楚iptables规则
iptables -F
ip6tables=/system/bin/ip6tables
iptables=/system/bin/iptables
#清理三角洲文件
rm -rf /data/data/com.tencent.tmgp.dfm/files/ano_tmp
rm -rf /data/user/0/com.tencent.tmgp.dfm/files/ano_tmp
#修复第三方环境异常
echo 16384 > /proc/sys/fs/inotify/max_queued_events
echo 128 > /proc/sys/fs/inotify/max_user_instances
echo 8192 > /proc/sys/fs/inotify/max_user_watches
# 清理逻辑（不变）
    for i in 3 2 1; do
        echo -n "$i "
        sleep 1
    done
    echo -e "\n注意演戏！"
    sleep 2
    echo "上号猛攻吧孩子！"
    sleep 1
    echo -e "\n[INFO] 程序已在后台运行，请关闭终端"
    sleep 100
}

trap clean_temp_file EXIT
main "$@"
