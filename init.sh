#!/bin/bash

set -e

OPENCLAW_HOME="/home/node/.openclaw"
OPENCLAW_WORKSPACE_ROOT="${OPENCLAW_WORKSPACE_ROOT:-$OPENCLAW_HOME}"
OPENCLAW_WORKSPACE_ROOT="${OPENCLAW_WORKSPACE_ROOT%/}"
OPENCLAW_WORKSPACE="${OPENCLAW_WORKSPACE_ROOT}/workspace"
NODE_UID="$(id -u node)"
NODE_GID="$(id -g node)"
GATEWAY_PID=""

log_section() {
    echo "=== $1 ==="
}

modify_node_uid_gid() {
    log_section "修改 Node 用户 UID/GID"

    # 从环境变量读取目标 UID/GID
    local TARGET_UID="${TARGET_UID:-1000}"
    local TARGET_GID="${TARGET_GID:-1000}"

    echo "目标 UID/GID: ${TARGET_UID}:${TARGET_GID}"

    # 获取当前 node 用户的 UID/GID
    if id "node" &>/dev/null; then
        local CURRENT_UID=${NODE_UID}
        local CURRENT_GID=${NODE_GID}
        echo "当前 node 用户: UID=${CURRENT_UID}, GID=${CURRENT_GID}"

        # 只在需要时修改
        if [ "${CURRENT_UID}" != "${TARGET_UID}" ] || [ "${CURRENT_GID}" != "${TARGET_GID}" ]; then
            echo "正在修改 node 用户的 UID/GID..."
            # 修改组 GID
            if [ "${CURRENT_GID}" != "${TARGET_GID}" ]; then
                echo "修改组 GID: ${CURRENT_GID} -> ${TARGET_GID}"
                groupmod -o -g "${TARGET_GID}" node 2>/dev/null || {
                    echo "警告: 组 GID 修改失败，可能 GID ${TARGET_GID} 已被占用"
                    echo "尝试创建新组并修改用户..."
                    # 创建新组并将用户添加到新组
                    groupadd -g "${TARGET_GID}" node_new_group 2>/dev/null
                    usermod -g node_new_group node 2>/dev/null || true
                }
            fi
            # 修改用户 UID
            if [ "${CURRENT_UID}" != "${TARGET_UID}" ]; then
                echo "修改用户 UID: ${CURRENT_UID} -> ${TARGET_UID}"
                usermod -o -u "${TARGET_UID}" node 2>/dev/null || \
                echo "警告: 用户 UID 修改可能失败（UID ${TARGET_UID} 可能已被占用）"
            fi
            echo "✅ Node 用户 UID/GID 修改完成"
        else
            echo "Node 用户 UID/GID 已为目标值，无需修改"
        fi
    else
        echo "错误: node 用户不存在！"
        exit 1
    fi
    # 更新全局变量
    NODE_UID="$(id -u node)"
    NODE_GID="$(id -g node)"
    echo "最终 node 用户: UID=${NODE_UID}, GID=${NODE_GID}"
}

ensure_workspace_root_link() {
    mkdir -p "$OPENCLAW_HOME"

    if [ "$OPENCLAW_WORKSPACE_ROOT" = "$OPENCLAW_HOME" ]; then
        return
    fi

    local workspace_root_parent
    workspace_root_parent="$(dirname "$OPENCLAW_WORKSPACE_ROOT")"
    mkdir -p "$workspace_root_parent"
    mkdir -p "$OPENCLAW_WORKSPACE_ROOT"

    if [ -L "$OPENCLAW_WORKSPACE_ROOT" ]; then
        local current_target
        current_target="$(readlink "$OPENCLAW_WORKSPACE_ROOT" || true)"
        if [ "$current_target" = "$OPENCLAW_HOME" ]; then
            return
        fi
        rm -f "$OPENCLAW_WORKSPACE_ROOT"
    elif [ -e "$OPENCLAW_WORKSPACE_ROOT" ]; then
        if [ -d "$OPENCLAW_WORKSPACE_ROOT" ] && [ -z "$(ls -A "$OPENCLAW_WORKSPACE_ROOT" 2>/dev/null)" ]; then
            rmdir "$OPENCLAW_WORKSPACE_ROOT"
        else
            echo "❌ OPENCLAW_WORKSPACE_ROOT 已存在且不能替换为指向 $OPENCLAW_HOME 的软链接: $OPENCLAW_WORKSPACE_ROOT"
            echo "   请清理或改用其他路径后重试。"
            exit 1
        fi
    fi

    ln -s "$OPENCLAW_HOME" "$OPENCLAW_WORKSPACE_ROOT"
    echo "已创建工作空间根目录软链接: $OPENCLAW_WORKSPACE_ROOT -> $OPENCLAW_HOME"
}

ensure_directories() {
    ensure_workspace_root_link
    mkdir -p "$OPENCLAW_HOME" "$OPENCLAW_WORKSPACE"
}

ensure_config_persistence() {
    log_section "配置 .config 目录持久化"
    local persistent_config_dir="$OPENCLAW_HOME/.config"
    local container_config_dir="/home/node/.config"

    # 1. 创建持久化目录
    mkdir -p "$persistent_config_dir"
    
    # 2. 处理现有目录与迁移
    if [ -d "$container_config_dir" ] && [ ! -L "$container_config_dir" ]; then
        # 如果持久化目录为空，将现有配置迁移过去
        if [ -z "$(ls -A "$persistent_config_dir")" ]; then
            echo "检测到容器内已有 .config 目录，正在迁移到持久化目录..."
            cp -a "$container_config_dir/." "$persistent_config_dir/"
        fi
        rm -rf "$container_config_dir"
    fi

    # 3. 创建软链接
    if [ ! -L "$container_config_dir" ]; then
        ln -sfn "$persistent_config_dir" "$container_config_dir"
        echo "已建立软链接: $container_config_dir -> $persistent_config_dir"
    fi

    # 4. 权限修复
    if is_root; then
        chown -R node:node "$persistent_config_dir" || true
        chown -h node:node "$container_config_dir" || true
    fi
}

sync_seed_extensions() {
    local seed_dir="/home/node/.openclaw-seed/extensions"
    local target_dir="$OPENCLAW_HOME/extensions"
    local seed_version_file="$seed_dir/.seed-version"
    local target_version_file="$target_dir/.seed-version"
    local global_sync="${SYNC_OPENCLAW_CONFIG:-true}"
    local sync_mode="${SYNC_EXTENSIONS_MODE:-seed-version}"
    local sync_on_start="${SYNC_EXTENSIONS_ON_START:-true}"
    local normalized_mode normalized_toggle

    global_sync="$(echo "$global_sync" | tr '[:upper:]' '[:lower:]' | xargs)"
    if [ "$global_sync" = "false" ] || [ "$global_sync" = "0" ] || [ "$global_sync" = "no" ]; then
        echo "ℹ️ 已关闭整体配置同步，跳过插件目录同步"
        return
    fi

    normalized_mode="$(echo "$sync_mode" | tr '[:upper:]' '[:lower:]' | xargs)"
    normalized_toggle="$(echo "$sync_on_start" | tr '[:upper:]' '[:lower:]' | xargs)"

    if [ "$normalized_toggle" = "false" ] || [ "$normalized_toggle" = "0" ] || [ "$normalized_toggle" = "no" ]; then
        echo "ℹ️ 已关闭启动时插件同步"
        return
    fi

    if [ ! -d "$seed_dir" ]; then
        echo "ℹ️ 未找到插件 seed 目录，跳过同步: $seed_dir"
        return
    fi

    mkdir -p "$target_dir"

    case "$normalized_mode" in
        missing)
            echo "=== 同步内置插件（仅补充缺失项） ==="
            find "$seed_dir" -mindepth 1 -maxdepth 1 | while IFS= read -r seed_item; do
                local item_name target_item
                item_name="$(basename "$seed_item")"
                target_item="$target_dir/$item_name"
                if [ -e "$target_item" ]; then
                    continue
                fi
                cp -a "$seed_item" "$target_item"
                echo "➕ 已补充插件/文件: $item_name"
            done
            ;;
        overwrite)
            echo "=== 同步内置插件（强制覆盖） ==="
            # 仅删除 seed 中存在的同名项，以保留用户自行添加的其他插件
            find "$seed_dir" -mindepth 1 -maxdepth 1 ! -name '.seed-version' | while IFS= read -r seed_item; do
                rm -rf "$target_dir/$(basename "$seed_item")"
            done
            cp -a "$seed_dir"/. "$target_dir"/
            ;;
        seed-version|versioned|"")
            local seed_version current_version
            seed_version=""
            current_version=""
            if [ -f "$seed_version_file" ]; then
                seed_version="$(cat "$seed_version_file")"
            fi
            if [ -f "$target_version_file" ]; then
                current_version="$(cat "$target_version_file")"
            fi

            if [ -n "$seed_version" ] && [ "$seed_version" = "$current_version" ]; then
                echo "ℹ️ 内置插件已是最新 seed 版本: $seed_version"
                return
            fi

            echo "=== 同步内置插件（按 seed 版本） ==="
            if [ -n "$current_version" ]; then
                echo "当前插件 seed 版本: $current_version"
            else
                echo "当前插件 seed 版本: 未初始化"
            fi
            if [ -n "$seed_version" ]; then
                echo "镜像内置 seed 版本: $seed_version"
            else
                echo "镜像内置 seed 版本: 未标记，执行覆盖同步"
            fi
            # 仅删除 seed 中存在的同名项，以保留用户自行添加的其他插件
            find "$seed_dir" -mindepth 1 -maxdepth 1 ! -name '.seed-version' | while IFS= read -r seed_item; do
                rm -rf "$target_dir/$(basename "$seed_item")"
            done
            cp -a "$seed_dir"/. "$target_dir"/
            ;;
        *)
            echo "⚠️ 未识别的 SYNC_EXTENSIONS_MODE=$sync_mode，支持 missing / overwrite / seed-version，已跳过插件同步"
            return
            ;;
    esac

    if is_root; then
        chown -R node:node "$target_dir" || true
    fi

    rm -rf "$seed_dir"
    echo "🧹 已清空插件 seed 目录: $seed_dir"
    echo "✅ 内置插件同步完成，模式: ${normalized_mode:-seed-version}"
}

is_root() {
    [ "$(id -u)" -eq 0 ]
}

fix_permissions_if_needed() {
    if ! is_root; then
        return
    fi

    local current_owner
    current_owner="$(stat -c '%u:%g' "$OPENCLAW_HOME" 2>/dev/null || echo unknown:unknown)"

    echo "挂载目录: $OPENCLAW_HOME"
    echo "当前所有者(UID:GID): $current_owner"
    echo "目标所有者(UID:GID): ${NODE_UID}:${NODE_GID}"

    if [ "$current_owner" != "${NODE_UID}:${NODE_GID}" ]; then
        echo "检测到宿主机挂载目录所有者与容器运行用户不一致，尝试自动修复..."
        chown -R node:node "$OPENCLAW_HOME" || true
    fi

    if [ -S /var/run/docker.sock ]; then
        echo "检测到 Docker Socket，正在尝试修复权限以支持沙箱..."
        chmod 666 /var/run/docker.sock || true
    fi

    if ! gosu node test -w "$OPENCLAW_HOME"; then
        echo "❌ 权限检查失败：node 用户无法写入 $OPENCLAW_HOME"
        echo "请在宿主机执行（Linux）："
        echo "  sudo chown -R ${NODE_UID}:${NODE_GID} <your-openclaw-data-dir>"
        echo "或在启动时显式指定用户："
        echo "  docker run --user \$(id -u):\$(id -g) ..."
        echo "若宿主机启用了 SELinux，请在挂载卷后添加 :z 或 :Z"
        exit 1
    fi
}

ensure_base_config() {
    local config_file="$OPENCLAW_HOME/openclaw.json"

    if [ -f "$config_file" ]; then
        return
    fi

    echo "配置文件不存在，创建基础骨架..."
    cat > "$config_file" <<'EOF'
{
  "meta": { "lastTouchedVersion": "2026.2.14" },
  "update": { "checkOnStart": false },
  "browser": {
    "headless": true,
    "noSandbox": true,
    "defaultProfile": "openclaw",
    "executablePath": "/usr/bin/chromium"
  },
  "models": { "mode": "merge", "providers": { "default": { "models": [] } } },
  "agents": {
    "defaults": {
      "compaction": { "mode": "safeguard" },
      "sandbox": { "mode": "off", "workspaceAccess": "none" },
      "elevatedDefault": "full",
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 }
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions",
    "tts": {
      "auto": "off",
      "mode": "final",
      "provider": "edge",
      "providers": {
        "edge": {
          "voice": "zh-CN-XiaoxiaoNeural",
          "lang": "zh-CN",
          "outputFormat": "ogg-24khz-16bit-mono-opus",
          "pitch": "+0Hz",
          "rate": "+0%",
          "volume": "+0%",
          "timeoutMs": 30000
        }
      }
    }
  },
  "commands": { "native": "auto", "nativeSkills": "auto" },
  "tools": {
    "profile": "full",
    "sessions": {
      "visibility": "all"
    },
    "fs": {
      "workspaceOnly": true
    }
  },
  "channels": {},
  "plugins": { "entries": {}, "installs": {} },
  "memory": {
    "backend": "qmd",
    "citations": "auto",
    "qmd": {
      "includeDefaultMemory": true,
      "sessions": {
        "enabled": true
      },
      "limits": {
        "timeoutMs": 8000,
        "maxResults": 16
      },
      "update": {
        "onBoot": true,
        "interval": "5m",
        "debounceMs": 15000
      },
      "command": "/usr/local/bin/qmd",
      "paths": [
        {
          "path": "/home/node/.openclaw/workspace",
          "name": "workspace",
          "pattern": "**/*.md"
        }
      ]
    }
  }
}
EOF
}

sync_config_with_env() {
    local config_file="$OPENCLAW_HOME/openclaw.json"

    ensure_base_config

    echo "正在根据当前环境变量同步配置状态..."
    CONFIG_FILE="$config_file" python3 - <<'PYCODE'
import json
import os
import re
import sys
from copy import deepcopy
from datetime import datetime, timezone

WECOM_ACCOUNT_ID_RE = re.compile(r'^[a-z0-9_-]+$')
FEISHU_ACCOUNT_FIELDS = {
    'appId', 'appSecret', 'name'
}
FEISHU_GROUP_FIELDS = {
    'requireMention'
}
FEISHU_RESERVED_FIELDS = {
    'enabled', 'appId', 'appSecret', 'dmPolicy', 'allowFrom', 'groupPolicy',
    'groupAllowFrom', 'streaming', 'requireMention', 'defaultAccount',
    'accounts', 'groups'
}
DINGTALK_ACCOUNT_FIELDS = {
    'name', 'enabled', 'clientId', 'clientSecret', 'dmPolicy', 'groupPolicy',
    'allowFrom', 'groupAllowFrom', 'displayNameResolution', 'contextVisibility',
    'mediaUrlAllowlist', 'ackReaction', 'journalTTLDays', 'debug', 'messageType',
    'cardTemplateId', 'cardTemplateKey', 'groups', 'maxConnectionAttempts',
    'initialReconnectDelay', 'maxReconnectDelay', 'reconnectJitter',
    'maxReconnectCycles', 'reconnectDeadlineMs', 'useConnectionManager',
    'mediaMaxMb', 'keepAlive', 'bypassProxyForSend', 'proactivePermissionHint',
    'cardRealTimeStream', 'cardStreamingMode', 'cardStreamInterval',
    'aicardDegradeMs', 'learningEnabled', 'learningAutoApply', 'learningNoteTtlMs',
    'convertMarkdownTables', 'cardAtSender'
}
DINGTALK_RESERVED_FIELDS = {
    'enabled', 'clientId', 'clientSecret', 'dmPolicy', 'allowFrom', 'groupPolicy',
    'messageType', 'cardTemplateId', 'cardTemplateKey', 'maxReconnectCycles',
    'debug', 'journalTTLDays', 'accounts', 'groupAllowFrom',
    'displayNameResolution', 'contextVisibility', 'mediaUrlAllowlist',
    'ackReaction', 'groups', 'maxConnectionAttempts', 'initialReconnectDelay',
    'maxReconnectDelay', 'reconnectJitter', 'reconnectDeadlineMs',
    'useConnectionManager', 'mediaMaxMb', 'keepAlive', 'bypassProxyForSend',
    'proactivePermissionHint', 'cardRealTimeStream', 'cardStreamingMode',
    'cardStreamInterval', 'aicardDegradeMs', 'learningEnabled',
    'learningAutoApply', 'learningNoteTtlMs', 'convertMarkdownTables',
    'cardAtSender',
    # 仍保留在 Reserved 中以防止这些过时字段被误识别为账号 ID，但不再包含在 ACCOUNT_FIELDS 中
    'robotCode', 'corpId', 'agentId', 'showThinking', 'thinkingMessage',
    'asyncMode', 'asyncAckText'
}
WECOM_ACCOUNT_FIELDS = {
    'botId', 'secret', 'dmPolicy', 'allowFrom', 'groupPolicy', 'groupAllowFrom',
    'welcomeMessage', 'sendThinkingMessage', 'agent', 'webhooks', 'network',
    'groupChat', 'dm', 'workspaceTemplate'
}
WECOM_RESERVED_FIELDS = {'enabled', 'defaultAccount', 'adminUsers', 'commands', 'dynamicAgents'}
QQBOT_ACCOUNT_FIELDS = {
    'enabled', 'name', 'appId', 'clientSecret', 'clientSecretFile', 'allowFrom',
    'systemPrompt', 'markdownSupport', 'voiceDirectUploadFormats', 'audioFormatPolicy',
    'urlDirectUpload', 'upgradeUrl', 'upgradeMode'
}
QQBOT_RESERVED_FIELDS = {
    'enabled', 'appId', 'clientSecret', 'allowFrom',
    'accounts', 'defaultAccount', 'tts', 'stt'
}

CHANNEL_INSTALLS = {
    'feishu': {'source': 'npm', 'spec': '@openclaw/feishu', 'installPath': '/home/node/.openclaw/extensions/feishu'},
    'dingtalk': {'source': 'npm', 'spec': 'https://github.com/soimy/clawdbot-channel-dingtalk.git', 'installPath': '/home/node/.openclaw/extensions/dingtalk'},
    'openclaw-qqbot': {'source': 'path', 'sourcePath': '/home/node/.openclaw/openclaw-qqbot', 'installPath': '/home/node/.openclaw/extensions/openclaw-qqbot'},
    'napcat': {'source': 'path', 'sourcePath': '/home/node/.openclaw/extensions/napcat', 'installPath': '/home/node/.openclaw/extensions/napcat'},
    'wecom': {'source': 'npm', 'spec': '@sunnoy/wecom', 'installPath': '/home/node/.openclaw/extensions/wecom'},
}


def strip_json_comments_and_trailing_commas(raw):
    raw = re.sub(r'/\*.*?\*/', '', raw, flags=re.S)
    raw = re.sub(r'(^|\s)//.*?$', '', raw, flags=re.M)
    raw = re.sub(r'(^|\s)#.*?$', '', raw, flags=re.M)
    raw = re.sub(r',(?=\s*[}\]])', '', raw)
    return raw


def load_config_with_compat(path):
    with open(path, 'r', encoding='utf-8') as f:
        raw = f.read()

    try:
        return json.loads(raw)
    except json.JSONDecodeError as original_error:
        sanitized = strip_json_comments_and_trailing_commas(raw)
        try:
            config = json.loads(sanitized)
            print('⚠️ 检测到 openclaw.json 含注释或尾随逗号，已按兼容模式自动解析并在保存时标准化为合法 JSON')
            return config
        except json.JSONDecodeError:
            raise ValueError(f'openclaw.json 格式非法: {original_error}')


def ensure_path(cfg, keys):
    curr = cfg
    for key in keys:
        if key not in curr or not isinstance(curr.get(key), dict):
            curr[key] = {}
        curr = curr[key]
    return curr


def deep_merge(dst, src):
    if not isinstance(dst, dict) or not isinstance(src, dict):
        return src
    for key, value in src.items():
        if isinstance(value, dict) and isinstance(dst.get(key), dict):
            dst[key] = deep_merge(dst[key], value)
        else:
            dst[key] = value
    return dst


def parse_bool(value, default=False):
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    val = str(value).strip().lower()
    if not val:
        return default
    return val in ('1', 'true', 'yes', 'on')


def parse_csv(value):
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [item.strip() for item in str(value).split(',') if item.strip()]


def parse_json_object(raw, env_name):
    raw = (raw or '').strip()
    if not raw:
        return None
    try:
        parsed = json.loads(raw)
    except Exception as ex:
        raise ValueError(f'{env_name} 不是合法 JSON: {ex}')
    if not isinstance(parsed, dict):
        raise ValueError(f'{env_name} 必须是 JSON 对象')
    return parsed


def utc_now_iso():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%S.%f')[:-3] + 'Z'


def first_csv_item(raw, default=''):
    values = parse_csv(raw)
    return values[0] if values else default


def normalize_model_ref(raw, provider_names=None, default_provider='default'):
    """归一化模型引用，确保包含 provider 前缀。

    规则：
    1. 不含 / 时，补成 default/<model_id>
    2. 含 / 且首段是已知 provider 名称或内置 provider 名称时，视为完整 provider/model 引用，原样返回
    3. 含 / 但首段不是已知 provider 名称时，视为 default provider 下的模型 ID，补成 default/<raw>
    """
    val = str(raw or '').strip()
    if not val:
        return ''

    provider_names = set(provider_names or [])
    provider_names.add(default_provider)
    provider_names.add('openai-codex')
    provider_names.add('opencode')

    if '/' not in val:
        return f'{default_provider}/{val}'

    provider_prefix = val.split('/', 1)[0].strip()
    if provider_prefix in provider_names:
        return val

    return f'{default_provider}/{val}'


def resolve_primary_model(env, default_model_id, provider_names=None):
    """
    解析主模型：
    1. 优先使用 PRIMARY_MODEL。
    2. 留空时，使用默认模型。
    3. 归一化时仅当首段是已知 provider 名称或内置 provider 名称时，才视为 provider/model；否则补 default/。
    """
    raw = str(env.get('PRIMARY_MODEL') or '').strip()
    if raw:
        return normalize_model_ref(raw, provider_names=provider_names)
    return normalize_model_ref(default_model_id, provider_names=provider_names)


def resolve_image_model(env, default_model_id, provider_names=None):
    """
    解析图片模型：
    1. 优先使用 IMAGE_MODEL_ID。
    2. 留空时，回退到默认模型。
    3. 归一化规则与主模型一致。
    """
    raw = str(env.get('IMAGE_MODEL_ID') or '').strip()
    if raw:
        return normalize_model_ref(raw, provider_names=provider_names)
    return normalize_model_ref(default_model_id, provider_names=provider_names)


def is_valid_account_id(account_id):
    return WECOM_ACCOUNT_ID_RE.match(str(account_id)) is not None


def is_feishu_account_config(value):
    return isinstance(value, dict) and any(key in value for key in FEISHU_ACCOUNT_FIELDS)


def is_dingtalk_account_config(value):
    return isinstance(value, dict) and any(key in value for key in DINGTALK_ACCOUNT_FIELDS)


def is_wecom_account_config(value):
    return isinstance(value, dict) and any(key in value for key in WECOM_ACCOUNT_FIELDS)


def is_qqbot_account_config(value):
    if not isinstance(value, dict):
        return False
    # 至少包含 appId 或 clientSecret 之一，或者包含其他账号特定字段
    return any(key in value for key in {'appId', 'clientSecret', 'name', 'systemPrompt', 'markdownSupport'})


def get_feishu_accounts(feishu):
    if not isinstance(feishu, dict):
        return []
    accounts = feishu.get('accounts')
    if not isinstance(accounts, dict):
        return []
    result = []
    for account_id, cfg in accounts.items():
        if is_valid_account_id(account_id) and is_feishu_account_config(cfg):
            result.append((account_id, cfg))
    return result


def get_dingtalk_accounts(dingtalk):
    if not isinstance(dingtalk, dict):
        return []
    accounts = dingtalk.get('accounts')
    if not isinstance(accounts, dict):
        return []
    result = []
    for account_id, cfg in accounts.items():
        if is_valid_account_id(account_id) and is_dingtalk_account_config(cfg):
            result.append((account_id, cfg))
    return result


def get_wecom_accounts(wecom):
    if not isinstance(wecom, dict):
        return []
    accounts = []
    for account_id, cfg in wecom.items():
        if account_id in WECOM_RESERVED_FIELDS:
            continue
        if is_wecom_account_config(cfg):
            accounts.append((account_id, cfg))
    return accounts


def get_qqbot_accounts(qqbot):
    if not isinstance(qqbot, dict):
        return []
    accounts = qqbot.get('accounts')
    if not isinstance(accounts, dict):
        return []
    result = []
    for account_id, cfg in accounts.items():
        if is_valid_account_id(account_id) and is_qqbot_account_config(cfg):
            result.append((account_id, cfg))
    return result


def normalize_wecom_config(channels):
    wecom = channels.get('wecom')
    if not isinstance(wecom, dict):
        return

    normalized = {}
    migrated = False

    for key in WECOM_RESERVED_FIELDS:
        if key in wecom:
            normalized[key] = wecom[key]

    for key, value in wecom.items():
        if key in WECOM_RESERVED_FIELDS:
            continue
        if is_valid_account_id(key) and is_wecom_account_config(value):
            normalized[key] = value
            continue
        if key in WECOM_ACCOUNT_FIELDS:
            default_account_id = str(wecom.get('defaultAccount') or 'default').strip() or 'default'
            default_cfg = normalized.get(default_account_id)
            if not isinstance(default_cfg, dict):
                default_cfg = {}
            default_cfg.setdefault(key, value)
            normalized[default_account_id] = default_cfg
            migrated = True

    if normalized and normalized != wecom:
        channels['wecom'] = normalized
        migrated = True

    if migrated:
        print('✅ 企业微信配置已标准化为当前多账号结构')


def normalize_dingtalk_config(channels):
    dingtalk = channels.get('dingtalk')
    if not isinstance(dingtalk, dict):
        return

    migrated = False
    accounts = dingtalk.get('accounts')
    if not isinstance(accounts, dict):
        accounts = {}

    has_structured_accounts = any(
        is_valid_account_id(account_id) and is_dingtalk_account_config(cfg)
        for account_id, cfg in accounts.items()
    )
    legacy_account = {key: dingtalk[key] for key in DINGTALK_ACCOUNT_FIELDS if key in dingtalk}
    if legacy_account and not has_structured_accounts:
        default_cfg = accounts.get('default', {})
        if not isinstance(default_cfg, dict):
            default_cfg = {}
        for key, value in legacy_account.items():
            default_cfg.setdefault(key, value)
        accounts['default'] = default_cfg
        migrated = True

    main_account = accounts.pop('main', None) if 'main' in accounts else None
    if isinstance(main_account, dict):
        default_cfg = accounts.get('default', {})
        if not isinstance(default_cfg, dict):
            default_cfg = {}
        for key, value in main_account.items():
            default_cfg.setdefault(key, value)
        accounts['default'] = default_cfg
        migrated = True

    normalized_accounts = {}
    for account_id, cfg in accounts.items():
        if is_valid_account_id(account_id) and is_dingtalk_account_config(cfg):
            # 严格过滤账号字段，确保不包含 Schema 之外的属性（如 agentId, corpId 等）
            normalized_accounts[account_id] = {k: v for k, v in cfg.items() if k in DINGTALK_ACCOUNT_FIELDS}

    if normalized_accounts:
        dingtalk['accounts'] = normalized_accounts
        default_cfg = normalized_accounts.get('default')
        if isinstance(default_cfg, dict):
            for key in DINGTALK_ACCOUNT_FIELDS:
                if key in default_cfg:
                    dingtalk[key] = default_cfg[key]
        migrated = migrated or dingtalk.get('accounts') != accounts

    # 再次清理顶层，移除不在 Reserved 字段中的过时属性（如 robotCode, corpId, agentId 等）
    # 注意：这些字段虽在 DINGTALK_RESERVED_FIELDS 中定义以防止被解析为账号，但在运行时会被校验为多余属性
    active_keys = DINGTALK_ACCOUNT_FIELDS | {'accounts'}
    for key in list(dingtalk.keys()):
        if key not in active_keys:
            del dingtalk[key]

    if migrated:
        print('✅ 钉钉配置已标准化为多机器人结构')


def normalize_qqbot_config(channels):
    qqbot = channels.get('qqbot')
    if not isinstance(qqbot, dict):
        return

    migrated = False
    
    # 移除不再支持的顶层字段
    removed_fields = []
    for field in ['dmPolicy', 'groupPolicy']:
        if field in qqbot:
            del qqbot[field]
            removed_fields.append(field)
            migrated = True
    
    if removed_fields:
        print(f'✅ QQ 机器人配置已移除过时字段: {", ".join(removed_fields)}')
    
    accounts = qqbot.get('accounts')
    if not isinstance(accounts, dict):
        accounts = {}

    has_structured_accounts = any(
        is_valid_account_id(account_id) and is_qqbot_account_config(cfg)
        for account_id, cfg in accounts.items()
    )
    legacy_account = {key: qqbot[key] for key in ('appId', 'clientSecret') if key in qqbot}
    if legacy_account and not has_structured_accounts:
        default_cfg = accounts.get('default', {})
        if not isinstance(default_cfg, dict):
            default_cfg = {}
        for key, value in legacy_account.items():
            default_cfg.setdefault(key, value)
        if 'enabled' not in default_cfg and isinstance(qqbot.get('enabled'), bool):
            default_cfg['enabled'] = qqbot['enabled']
        accounts['default'] = default_cfg
        migrated = True

    main_account = accounts.pop('main', None) if 'main' in accounts else None
    if isinstance(main_account, dict):
        default_cfg = accounts.get('default', {})
        if not isinstance(default_cfg, dict):
            default_cfg = {}
        for key, value in main_account.items():
            default_cfg.setdefault(key, value)
        accounts['default'] = default_cfg
        migrated = True

    normalized_accounts = {}
    for account_id, cfg in accounts.items():
        if is_valid_account_id(account_id) and is_qqbot_account_config(cfg):
            normalized_accounts[account_id] = cfg

    if normalized_accounts:
        qqbot['accounts'] = normalized_accounts
        default_cfg = normalized_accounts.get('default')
        if isinstance(default_cfg, dict):
            if default_cfg.get('appId'):
                qqbot['appId'] = default_cfg['appId']
            if default_cfg.get('clientSecret'):
                qqbot['clientSecret'] = default_cfg['clientSecret']
        migrated = migrated or qqbot.get('accounts') != accounts

    if migrated:
        print('✅ QQ 机器人配置已标准化为多 Bot 结构')


def normalize_telegram_config(channels):
    telegram = channels.get('telegram')
    if not isinstance(telegram, dict):
        return

    streaming = telegram.get('streaming')
    if streaming is None:
        return

    migrated = False

    # 旧版格式：streaming 是字符串，迁移为新版嵌套对象
    if isinstance(streaming, str):
        print('检测到 Telegram 旧版 streaming 配置格式，正在执行自动迁移...')
        mode = streaming if streaming in ('off', 'partial', 'block', 'progress') else 'partial'
        telegram['streaming'] = {
            'mode': mode,
            'chunkMode': 'length',
        }
        print('✅ Telegram 配置已迁移到新版嵌套结构')
        return

    if not isinstance(streaming, dict):
        return

    normalized = dict(streaming)

    chunk_mode = normalized.get('chunkMode')
    if chunk_mode == 'default':
        normalized['chunkMode'] = 'length'
        migrated = True

    preview = normalized.get('preview')
    if isinstance(preview, dict):
        preview = dict(preview)
        preview_chunk = preview.get('chunk')
        if preview_chunk is True:
            preview['chunk'] = {
                'minChars': 200,
                'maxChars': 800,
                'breakPreference': 'paragraph',
            }
            normalized['preview'] = preview
            migrated = True
        elif preview_chunk in (False, None):
            preview.pop('chunk', None)
            if preview:
                normalized['preview'] = preview
            else:
                normalized.pop('preview', None)
            if preview_chunk is False:
                migrated = True

    block = normalized.get('block')
    if isinstance(block, dict):
        block = dict(block)
        coalesce = block.get('coalesce')
        if coalesce is True:
            block['coalesce'] = {
                'idleMs': 1000,
            }
            normalized['block'] = block
            migrated = True
        elif coalesce in (False, None):
            block.pop('coalesce', None)
            if block:
                normalized['block'] = block
            else:
                normalized.pop('block', None)
            if coalesce is False:
                migrated = True

    if migrated:
        print('检测到 Telegram streaming 子字段包含旧版值，正在修正为当前 schema...')
        telegram['streaming'] = normalized
        print('✅ Telegram 配置已迁移到新版嵌套结构')


def normalize_feishu_config(channels):
    feishu = channels.get('feishu')
    if not isinstance(feishu, dict):
        return

    migrated = False
    accounts = feishu.get('accounts')
    if not isinstance(accounts, dict):
        accounts = {}

    has_structured_accounts = any(
        is_valid_account_id(account_id) and is_feishu_account_config(cfg)
        for account_id, cfg in accounts.items()
    )
    legacy_account = {key: feishu[key] for key in FEISHU_ACCOUNT_FIELDS if key in feishu}
    if legacy_account and not has_structured_accounts:
        default_account = accounts.get('default', {})
        if not isinstance(default_account, dict):
            default_account = {}
        for key, value in legacy_account.items():
            default_account.setdefault(key, value)
        if 'name' not in default_account:
            default_account['name'] = feishu.get('name', 'OpenClaw Bot')
        accounts['default'] = default_account
        migrated = True

    main_account = accounts.pop('main', None) if 'main' in accounts else None
    if isinstance(main_account, dict):
        default_account = accounts.get('default', {})
        if not isinstance(default_account, dict):
            default_account = {}
        for key, value in main_account.items():
            default_account.setdefault(key, value)
        accounts['default'] = default_account
        migrated = True

    normalized_accounts = {}
    for account_id, cfg in accounts.items():
        if is_valid_account_id(account_id) and is_feishu_account_config(cfg):
            # 仅保留 FEISHU_ACCOUNT_FIELDS 中定义的键
            pruned_cfg = {k: v for k, v in cfg.items() if k in FEISHU_ACCOUNT_FIELDS}
            normalized_accounts[account_id] = pruned_cfg

    if normalized_accounts:
        feishu['accounts'] = normalized_accounts
        default_account_id = str(feishu.get('defaultAccount') or 'default').strip() or 'default'
        if default_account_id not in normalized_accounts and 'default' in normalized_accounts:
            default_account_id = 'default'
        feishu['defaultAccount'] = default_account_id
        default_account = normalized_accounts.get(default_account_id) or normalized_accounts.get('default')
        if isinstance(default_account, dict):
            if default_account.get('appId'):
                feishu['appId'] = default_account['appId']
            if default_account.get('appSecret'):
                feishu['appSecret'] = default_account['appSecret']
            if default_account.get('name'):
                feishu['name'] = default_account['name']

        # 清理冗余字段，确保只保留 FEISHU_RESERVED_FIELDS 中定义的键
        for key in list(feishu.keys()):
            if key not in FEISHU_RESERVED_FIELDS:
                del feishu[key]

        # 清理 groups 内部字段，仅保留 FEISHU_GROUP_FIELDS 中定义的键
        groups = feishu.get('groups')
        if isinstance(groups, dict):
            for gid, gcfg in groups.items():
                if isinstance(gcfg, dict):
                    pruned_gcfg = {k: v for k, v in gcfg.items() if k in FEISHU_GROUP_FIELDS}
                    groups[gid] = pruned_gcfg
        
        migrated = migrated or feishu.get('accounts') != accounts

    if migrated:
        print('✅ 飞书配置已标准化为多账号结构')


def migrate_feishu_config(channels_root):
    feishu = channels_root.get('feishu', {})
    if 'appId' in feishu and 'accounts' not in feishu:
        print('检测到飞书旧版格式，执行迁移...')
        feishu['accounts'] = {
            'default': {
                'appId': feishu.get('appId', ''),
                'appSecret': feishu.get('appSecret', ''),
                'name': feishu.get('name', 'OpenClaw Bot'),
            }
        }

    accounts = feishu.get('accounts')
    if isinstance(accounts, dict) and 'main' in accounts:
        print('检测到飞书 accounts.main，迁移为 accounts.default...')
        main_account = accounts.pop('main')
        default_account = accounts.get('default')
        if not isinstance(default_account, dict):
            accounts['default'] = main_account if isinstance(main_account, dict) else {}
        elif isinstance(main_account, dict):
            for key, value in main_account.items():
                default_account.setdefault(key, value)

    default_account = accounts.get('default') if isinstance(accounts, dict) else None
    if isinstance(default_account, dict):
        if default_account.get('appId'):
            feishu['appId'] = default_account['appId']
        if default_account.get('appSecret'):
            feishu['appSecret'] = default_account['appSecret']

    normalize_feishu_config(channels_root)


def merge_wecom_accounts_from_env(channels, env):
    raw = (env.get('WECOM_ACCOUNTS_JSON') or '').strip()
    if not raw:
        return False

    try:
        parsed = json.loads(raw)
    except Exception as ex:
        raise ValueError(f'WECOM_ACCOUNTS_JSON 不是合法 JSON: {ex}')

    if not isinstance(parsed, dict):
        raise ValueError('WECOM_ACCOUNTS_JSON 必须是对象，格式为 {"open": {...}, "support": {...}}')

    if 'accounts' in parsed and isinstance(parsed.get('accounts'), dict):
        parsed = parsed['accounts']
    elif 'wecom' in parsed and isinstance(parsed.get('wecom'), dict):
        parsed = {
            key: value
            for key, value in parsed['wecom'].items()
            if key not in WECOM_RESERVED_FIELDS and is_valid_account_id(key)
        }

    wecom = channels.get('wecom')
    if not isinstance(wecom, dict):
        wecom = {}
        channels['wecom'] = wecom

    changed = False
    for account_id, account_cfg in parsed.items():
        if not is_valid_account_id(account_id):
            raise ValueError(f'WECOM_ACCOUNTS_JSON 账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        if not isinstance(account_cfg, dict) or not is_wecom_account_config(account_cfg):
            raise ValueError(f'WECOM_ACCOUNTS_JSON 账号配置非法: {account_id}，至少包含 botId/secret/agent/webhooks/dmPolicy 中的一项')

        old_cfg = wecom.get(account_id)
        if not isinstance(old_cfg, dict):
            old_cfg = {}
        wecom[account_id] = deep_merge(old_cfg, account_cfg)
        changed = True

    if changed:
        wecom['enabled'] = True
        print('✅ 已从企业微信多账号环境变量同步配置')
    return changed


def merge_feishu_accounts_from_env(channels, env):
    raw = (env.get('FEISHU_ACCOUNTS_JSON') or '').strip()
    if not raw:
        return False

    try:
        parsed = json.loads(raw)
    except Exception as ex:
        raise ValueError(f'FEISHU_ACCOUNTS_JSON 不是合法 JSON: {ex}')

    if not isinstance(parsed, dict):
        raise ValueError('FEISHU_ACCOUNTS_JSON 必须是对象，格式为 {"default": {...}, "work": {...}}')

    if 'accounts' in parsed and isinstance(parsed.get('accounts'), dict):
        parsed = parsed['accounts']
    elif 'feishu' in parsed and isinstance(parsed.get('feishu'), dict):
        feishu_payload = parsed['feishu']
        if 'accounts' in feishu_payload and isinstance(feishu_payload.get('accounts'), dict):
            parsed = feishu_payload['accounts']
        else:
            parsed = {key: value for key, value in feishu_payload.items() if key not in FEISHU_RESERVED_FIELDS}

    feishu = channels.get('feishu')
    if not isinstance(feishu, dict):
        feishu = {}
        channels['feishu'] = feishu

    accounts = feishu.get('accounts')
    if not isinstance(accounts, dict):
        accounts = {}
        feishu['accounts'] = accounts

    changed = False
    for account_id, account_cfg in parsed.items():
        if not is_valid_account_id(account_id):
            raise ValueError(f'FEISHU_ACCOUNTS_JSON 账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        if not isinstance(account_cfg, dict) or not is_feishu_account_config(account_cfg):
            raise ValueError(f'FEISHU_ACCOUNTS_JSON 账号配置非法: {account_id}，至少包含 appId/appSecret/name 中的一项')

        old_cfg = accounts.get(account_id)
        if not isinstance(old_cfg, dict):
            old_cfg = {}
        accounts[account_id] = deep_merge(old_cfg, account_cfg)
        changed = True

    if changed:
        feishu['enabled'] = True
        default_account_id = str(feishu.get('defaultAccount') or env.get('FEISHU_DEFAULT_ACCOUNT') or 'default').strip() or 'default'
        if default_account_id not in accounts and 'default' in accounts:
            default_account_id = 'default'
        feishu['defaultAccount'] = default_account_id
        default_cfg = accounts.get(default_account_id) or accounts.get('default')
        if isinstance(default_cfg, dict):
            if default_cfg.get('appId'):
                feishu['appId'] = default_cfg['appId']
            if default_cfg.get('appSecret'):
                feishu['appSecret'] = default_cfg['appSecret']
            if default_cfg.get('name'):
                feishu['name'] = default_cfg['name']
        print('✅ 已从飞书多账号环境变量同步配置')
    return changed


def merge_dingtalk_accounts_from_env(channels, env):
    raw = (env.get('DINGTALK_ACCOUNTS_JSON') or '').strip()
    if not raw:
        return False

    try:
        parsed = json.loads(raw)
    except Exception as ex:
        raise ValueError(f'DINGTALK_ACCOUNTS_JSON 不是合法 JSON: {ex}')

    if not isinstance(parsed, dict):
        raise ValueError('DINGTALK_ACCOUNTS_JSON 必须是对象，格式为 {"bot_1": {...}, "bot_2": {...}}')

    if 'accounts' in parsed and isinstance(parsed.get('accounts'), dict):
        parsed = parsed['accounts']
    elif 'dingtalk' in parsed and isinstance(parsed.get('dingtalk'), dict):
        dingtalk_payload = parsed['dingtalk']
        if 'accounts' in dingtalk_payload and isinstance(dingtalk_payload.get('accounts'), dict):
            parsed = dingtalk_payload['accounts']
        else:
            parsed = {key: value for key, value in dingtalk_payload.items() if key not in DINGTALK_RESERVED_FIELDS}

    dingtalk = channels.get('dingtalk')
    if not isinstance(dingtalk, dict):
        dingtalk = {}
        channels['dingtalk'] = dingtalk

    accounts = dingtalk.get('accounts')
    if not isinstance(accounts, dict):
        accounts = {}
        dingtalk['accounts'] = accounts

    changed = False
    for account_id, account_cfg in parsed.items():
        if not is_valid_account_id(account_id):
            raise ValueError(f'DINGTALK_ACCOUNTS_JSON 账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        if not isinstance(account_cfg, dict) or not is_dingtalk_account_config(account_cfg):
            raise ValueError(f'DINGTALK_ACCOUNTS_JSON 账号配置非法: {account_id}，请检查配置字段是否符合要求')

        old_cfg = accounts.get(account_id)
        if not isinstance(old_cfg, dict):
            old_cfg = {}
        accounts[account_id] = deep_merge(old_cfg, account_cfg)
        changed = True

    if changed:
        dingtalk['enabled'] = True
        default_cfg = accounts.get('default')
        if isinstance(default_cfg, dict):
            for key in DINGTALK_ACCOUNT_FIELDS:
                if key in default_cfg:
                    dingtalk[key] = default_cfg[key]
        print('✅ 已从钉钉多机器人环境变量同步配置')
    return changed


def merge_qqbot_bots_from_env(channels, env):
    raw = (env.get('QQBOT_BOTS_JSON') or '').strip()
    if not raw:
        return False

    try:
        parsed = json.loads(raw)
    except Exception as ex:
        raise ValueError(f'QQBOT_BOTS_JSON 不是合法 JSON: {ex}')

    if not isinstance(parsed, dict):
        raise ValueError('QQBOT_BOTS_JSON 必须是对象，格式为 {"bot1": {...}, "bot2": {...}}')

    if 'accounts' in parsed and isinstance(parsed.get('accounts'), dict):
        parsed = parsed['accounts']
    elif 'qqbot' in parsed and isinstance(parsed.get('qqbot'), dict):
        qqbot_payload = parsed['qqbot']
        if 'accounts' in qqbot_payload and isinstance(qqbot_payload.get('accounts'), dict):
            parsed = qqbot_payload['accounts']
        else:
            parsed = {key: value for key, value in qqbot_payload.items() if key not in QQBOT_RESERVED_FIELDS}

    qqbot = channels.get('qqbot')
    if not isinstance(qqbot, dict):
        qqbot = {}
        channels['qqbot'] = qqbot

    accounts = qqbot.get('accounts')
    if not isinstance(accounts, dict):
        accounts = {}
        qqbot['accounts'] = accounts

    changed = False
    for account_id, account_cfg in parsed.items():
        if not is_valid_account_id(account_id):
            raise ValueError(f'QQBOT_BOTS_JSON 账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        if not isinstance(account_cfg, dict) or not is_qqbot_account_config(account_cfg):
            raise ValueError(f'QQBOT_BOTS_JSON 账号配置非法: {account_id}，至少包含 appId/clientSecret/name/systemPrompt/markdownSupport 中的一项')

        old_cfg = accounts.get(account_id)
        if not isinstance(old_cfg, dict):
            old_cfg = {}
        accounts[account_id] = deep_merge(old_cfg, account_cfg)
        changed = True

    if changed:
        qqbot['enabled'] = True
        default_cfg = accounts.get('default')
        if isinstance(default_cfg, dict):
            if default_cfg.get('appId'):
                qqbot['appId'] = default_cfg['appId']
            if default_cfg.get('clientSecret'):
                qqbot['clientSecret'] = default_cfg['clientSecret']
        print('✅ 已从 QQ 机器人多 Bot 环境变量同步配置')
    return changed


def validate_feishu_multi_accounts(channels):
    feishu = channels.get('feishu')
    if not isinstance(feishu, dict):
        return

    accounts = get_feishu_accounts(feishu)
    if not accounts:
        return

    account_map = dict(accounts)
    default_account = (feishu.get('defaultAccount') or '').strip() if isinstance(feishu.get('defaultAccount'), str) else ''
    if default_account and default_account not in account_map:
        raise ValueError(f'飞书 defaultAccount 不存在: {default_account}')

    app_id_index = {}
    for account_id, cfg in accounts:
        if not is_valid_account_id(account_id):
            raise ValueError(f'飞书账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        app_id = str(cfg.get('appId') or '').strip()
        if app_id:
            app_id_index.setdefault(app_id, []).append(account_id)

    duplicate_app_ids = {key: value for key, value in app_id_index.items() if len(value) > 1}
    if duplicate_app_ids:
        detail = '; '.join([f"{app_id}: {', '.join(ids)}" for app_id, ids in duplicate_app_ids.items()])
        raise ValueError(f'飞书 App ID 冲突（可能导致消息路由错乱）: {detail}')


def validate_wecom_multi_accounts(channels):
    wecom = channels.get('wecom')
    if not isinstance(wecom, dict):
        return

    accounts = get_wecom_accounts(wecom)
    if not accounts:
        return

    account_map = dict(accounts)
    default_account = (wecom.get('defaultAccount') or '').strip() if isinstance(wecom.get('defaultAccount'), str) else ''
    if default_account and default_account not in account_map:
        raise ValueError(f'企业微信 defaultAccount 不存在: {default_account}')

    bot_id_index = {}
    agent_id_index = {}
    for account_id, cfg in accounts:
        if not is_valid_account_id(account_id):
            raise ValueError(f'企业微信账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')

        bot_id = str(cfg.get('botId') or '').strip()
        if bot_id:
            bot_id_index.setdefault(bot_id, []).append(account_id)

        agent = cfg.get('agent') if isinstance(cfg.get('agent'), dict) else None
        if agent:
            agent_id = agent.get('agentId')
            if agent_id is not None and str(agent_id).strip() != '':
                agent_id_index.setdefault(str(agent_id).strip(), []).append(account_id)

    duplicate_bot_ids = {key: value for key, value in bot_id_index.items() if len(value) > 1}
    if duplicate_bot_ids:
        detail = '; '.join([f"{bot_id}: {', '.join(ids)}" for bot_id, ids in duplicate_bot_ids.items()])
        raise ValueError(f'企业微信 botId 冲突（可能导致消息路由错乱）: {detail}')

    duplicate_agent_ids = {key: value for key, value in agent_id_index.items() if len(value) > 1}
    if duplicate_agent_ids:
        detail = '; '.join([f"{agent_id}: {', '.join(ids)}" for agent_id, ids in duplicate_agent_ids.items()])
        raise ValueError(f'企业微信 Agent ID 冲突（可能导致消息路由错乱）: {detail}')


def validate_dingtalk_multi_accounts(channels):
    dingtalk = channels.get('dingtalk')
    if not isinstance(dingtalk, dict):
        return

    accounts = get_dingtalk_accounts(dingtalk)
    if not accounts:
        return

    client_id_index = {}
    robot_code_index = {}
    agent_id_index = {}
    for account_id, cfg in accounts:
        if not is_valid_account_id(account_id):
            raise ValueError(f'钉钉账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')

        client_id = str(cfg.get('clientId') or '').strip()
        if client_id:
            client_id_index.setdefault(client_id, []).append(account_id)

        robot_code = str(cfg.get('robotCode') or '').strip()
        if robot_code:
            robot_code_index.setdefault(robot_code, []).append(account_id)

        agent_id = str(cfg.get('agentId') or '').strip()
        if agent_id:
            agent_id_index.setdefault(agent_id, []).append(account_id)

    duplicate_client_ids = {key: value for key, value in client_id_index.items() if len(value) > 1}
    if duplicate_client_ids:
        detail = '; '.join([f"{client_id}: {', '.join(ids)}" for client_id, ids in duplicate_client_ids.items()])
        raise ValueError(f'钉钉 clientId 冲突（可能导致消息路由错乱）: {detail}')

    duplicate_robot_codes = {key: value for key, value in robot_code_index.items() if len(value) > 1}
    if duplicate_robot_codes:
        detail = '; '.join([f"{robot_code}: {', '.join(ids)}" for robot_code, ids in duplicate_robot_codes.items()])
        raise ValueError(f'钉钉 robotCode 冲突（可能导致消息路由错乱）: {detail}')

    duplicate_agent_ids = {key: value for key, value in agent_id_index.items() if len(value) > 1}
    if duplicate_agent_ids:
        detail = '; '.join([f"{agent_id}: {', '.join(ids)}" for agent_id, ids in duplicate_agent_ids.items()])
        raise ValueError(f'钉钉 Agent ID 冲突（可能导致消息路由错乱）: {detail}')


def validate_qqbot_multi_accounts(channels):
    qqbot = channels.get('qqbot')
    if not isinstance(qqbot, dict):
        return

    accounts = get_qqbot_accounts(qqbot)
    if not accounts:
        return

    app_id_index = {}
    for account_id, cfg in accounts:
        if not is_valid_account_id(account_id):
            raise ValueError(f'QQ 机器人账号 ID 不合法: {account_id}，仅支持小写字母、数字、-、_')
        app_id = str(cfg.get('appId') or '').strip()
        if app_id:
            app_id_index.setdefault(app_id, []).append(account_id)

    duplicate_app_ids = {key: value for key, value in app_id_index.items() if len(value) > 1}
    if duplicate_app_ids:
        detail = '; '.join([f"{app_id}: {', '.join(ids)}" for app_id, ids in duplicate_app_ids.items()])
        raise ValueError(f'QQ 机器人 AppID 冲突（可能导致消息路由错乱）: {detail}')


class SyncContext:
    def __init__(self, config, env):
        self.config = config
        self.env = env
        self.channels = ensure_path(config, ['channels'])
        self.plugins = ensure_path(config, ['plugins'])
        self.entries = ensure_path(self.plugins, ['entries'])
        self.installs = ensure_path(self.plugins, ['installs'])
        self.default_dm_policy = env.get('DM_POLICY') or 'open'
        self.default_allow_from = parse_csv(env.get('ALLOW_FROM')) or ['*']
        self.default_group_policy = env.get('GROUP_POLICY') or 'open'
        self.multi_account_channels = {'feishu', 'dingtalk', 'wecom', 'qqbot'}
        self.has_feishu_single_env = bool((env.get('FEISHU_APP_ID') or '').strip() and (env.get('FEISHU_APP_SECRET') or '').strip())
        self.has_feishu_accounts_env = bool((env.get('FEISHU_ACCOUNTS_JSON') or '').strip())
        self.has_feishu_any_env = self.has_feishu_single_env or self.has_feishu_accounts_env
        self.has_dingtalk_single_env = bool((env.get('DINGTALK_CLIENT_ID') or '').strip() and (env.get('DINGTALK_CLIENT_SECRET') or '').strip())
        self.has_dingtalk_accounts_env = bool((env.get('DINGTALK_ACCOUNTS_JSON') or '').strip())
        self.has_dingtalk_any_env = self.has_dingtalk_single_env or self.has_dingtalk_accounts_env
        self.has_wecom_single_env = bool((env.get('WECOM_BOT_ID') or '').strip() and (env.get('WECOM_SECRET') or '').strip())
        self.has_wecom_accounts_env = bool((env.get('WECOM_ACCOUNTS_JSON') or '').strip())
        self.has_wecom_any_env = self.has_wecom_single_env or self.has_wecom_accounts_env
        self.has_qqbot_single_env = bool((env.get('QQBOT_APP_ID') or '').strip() and (env.get('QQBOT_CLIENT_SECRET') or '').strip())
        self.has_qqbot_bots_env = bool((env.get('QQBOT_BOTS_JSON') or '').strip())
        self.has_qqbot_any_env = self.has_qqbot_single_env or self.has_qqbot_bots_env
        self.feishu_plugin_env = (env.get('FEISHU_OFFICIAL_PLUGIN_ENABLED') or '').strip().lower()
        self.feishu_plugin_enabled = self.feishu_plugin_env in ('1', 'true', 'yes', 'on')
        self.feishu_plugin_explicit = self.feishu_plugin_env in ('0', '1', 'false', 'true', 'no', 'yes', 'off', 'on')

    def channel(self, channel_id):
        return ensure_path(self.channels, [channel_id])

    def entry(self, channel_id):
        return ensure_path(self.entries, [channel_id])

    def install(self, channel_id):
        install_info = CHANNEL_INSTALLS.get(channel_id)
        if install_info and channel_id not in self.installs:
            payload = deepcopy(install_info)
            payload['installedAt'] = utc_now_iso()
            self.installs[channel_id] = payload

    def enable_channel(self, channel_id, install=False):
        self.entries[channel_id] = {'enabled': True}
        if install:
            self.install(channel_id)

    def disable_channel(self, channel_id):
        self.entries[channel_id] = {'enabled': False}

    def is_channel_explicitly_disabled(self, channel_id):
        entry = self.entries.get(channel_id)
        return isinstance(entry, dict) and (entry.get('enabled') is False)


def set_qqbot_plugin_entries(ctx, enabled, install=False):
    ctx.entries['openclaw-qqbot'] = {'enabled': enabled}
    ctx.entries['qqbot'] = {'enabled': enabled}
    if enabled and install:
        ctx.install('openclaw-qqbot')


def is_openclaw_sync_enabled(env):
    return parse_bool(env.get('SYNC_OPENCLAW_CONFIG', 'true'), True)


def sync_models(ctx):
    if not is_openclaw_sync_enabled(ctx.env):
        print('ℹ️ 已关闭整体配置同步，跳过模型同步')
        return

    if not parse_bool(ctx.env.get('SYNC_MODEL_CONFIG', 'true'), True):
        print('ℹ️ 已关闭模型配置同步，跳过模型同步')
        return

    def sync_provider(provider_name, api_key, base_url, protocol, model_ids_raw, context_window, max_tokens):
        providers = ensure_path(ctx.config, ['models', 'providers'])
        if not ((api_key and base_url) or model_ids_raw):
            if provider_name in providers:
                del providers[provider_name]
            return None

        provider = providers.setdefault(provider_name, {})
        
        # API Key
        if api_key:
            provider['apiKey'] = api_key
        else:
            provider.pop('apiKey', None)
            
        # Base URL
        if base_url:
            provider['baseUrl'] = base_url
        else:
            provider.pop('baseUrl', None)
            
        # Protocol
        if protocol:
            provider['api'] = protocol
        elif 'api' not in provider:
            provider['api'] = 'openai-completions'

        # Models
        model_ids = parse_csv(model_ids_raw)
        if not model_ids:
            provider.pop('models', None)
        else:
            existing_models = provider.get('models', [])
            new_models = []
            for model_id in model_ids:
                model_obj = next((item for item in existing_models if item.get('id') == model_id), None)
                if not model_obj:
                    model_obj = {
                        'id': model_id,
                        'name': model_id,
                        'reasoning': False,
                        'input': ['text', 'image'],
                        'cost': {'input': 0, 'output': 0, 'cacheRead': 0, 'cacheWrite': 0},
                    }
                model_obj['contextWindow'] = int(context_window or 200000)
                model_obj['maxTokens'] = int(max_tokens or 8192)
                new_models.append(model_obj)
            provider['models'] = new_models
            
        return provider_name

    synced_provider_names = []
    
    # 1. 同步默认提供商
    primary_provider = sync_provider(
        'default',
        ctx.env.get('API_KEY'),
        ctx.env.get('BASE_URL'),
        ctx.env.get('API_PROTOCOL'),
        ctx.env.get('MODEL_ID') or 'gpt-4o',
        ctx.env.get('CONTEXT_WINDOW'),
        ctx.env.get('MAX_TOKENS'),
    )
    if primary_provider:
        synced_provider_names.append(primary_provider)

    # 2. 同步额外提供商 (2-6)
    enabled_extra_providers = []
    for index in range(2, 7):
        prefix = f'MODEL{index}'
        raw_name = str(ctx.env.get(f'{prefix}_NAME') or '').strip()
        p_name = raw_name or f'model{index}'
        
        synced_name = sync_provider(
            p_name,
            str(ctx.env.get(f'{prefix}_API_KEY') or '').strip(),
            str(ctx.env.get(f'{prefix}_BASE_URL') or '').strip(),
            str(ctx.env.get(f'{prefix}_PROTOCOL') or '').strip(),
            str(ctx.env.get(f'{prefix}_MODEL_ID') or '').strip(),
            str(ctx.env.get(f'{prefix}_CONTEXT_WINDOW') or '').strip(),
            str(ctx.env.get(f'{prefix}_MAX_TOKENS') or '').strip(),
        )
        if synced_name:
            enabled_extra_providers.append(synced_name)
            synced_provider_names.append(synced_name)

    # 3. 清理不再存在的提供商（除了已同步的）
    providers_dict = ensure_path(ctx.config, ['models', 'providers'])
    for name in list(providers_dict.keys()):
        if name not in synced_provider_names:
            del providers_dict[name]

    # 提取默认模型 ID (MODEL_ID 的第一个)
    default_model_id = first_csv_item(ctx.env.get('MODEL_ID') or 'gpt-4o', 'gpt-4o')
    primary_model_raw = str(ctx.env.get('PRIMARY_MODEL') or '').strip()
    image_model_raw = str(ctx.env.get('IMAGE_MODEL_ID') or '').strip()
    provider_names = set(ensure_path(ctx.config, ['models', 'providers']).keys())

    # 解析最终的主模型与图片模型引用
    primary_model = resolve_primary_model(ctx.env, default_model_id, provider_names=provider_names)
    primary_image_model = resolve_image_model(ctx.env, default_model_id, provider_names=provider_names)

    ensure_path(ctx.config, ['agents', 'defaults', 'model'])['primary'] = primary_model
    ensure_path(ctx.config, ['agents', 'defaults', 'imageModel'])['primary'] = primary_image_model

    msg = f'✅ 模型同步完成: 主模型={primary_model}'
    if primary_model_raw:
        msg += f' (来自 PRIMARY_MODEL={primary_model_raw})'
    msg += f', 图片模型={primary_image_model}'
    if enabled_extra_providers:
        msg += f", 已启用额外提供商: {', '.join(enabled_extra_providers)}"
    print(msg)


def sync_agent_and_tools(ctx):
    if not is_openclaw_sync_enabled(ctx.env):
        print('ℹ️ 已关闭整体配置同步，跳过 Agent 与工具同步')
        return

    workspace_root = (ctx.env.get('OPENCLAW_WORKSPACE_ROOT') or '/home/node/.openclaw').rstrip('/') or '/'
    workspace = f"{workspace_root}/workspace" if workspace_root != '/' else '/workspace'
    ensure_path(ctx.config, ['agents', 'defaults'])['workspace'] = workspace

    sandbox = ensure_path(ctx.config, ['agents', 'defaults', 'sandbox'])

    memory = ensure_path(ctx.config, ['memory'])
    memory.setdefault('backend', 'qmd')
    memory.setdefault('citations', 'auto')
    memory_cfg = ensure_path(memory, ['qmd'])
    memory_cfg.setdefault('includeDefaultMemory', True)
    ensure_path(memory_cfg, ['sessions']).setdefault('enabled', True)
    limits_cfg = ensure_path(memory_cfg, ['limits'])
    limits_cfg.setdefault('timeoutMs', 8000)
    limits_cfg.setdefault('maxResults', 16)
    update_cfg = ensure_path(memory_cfg, ['update'])
    update_cfg.setdefault('onBoot', True)
    update_cfg.setdefault('interval', '5m')
    update_cfg.setdefault('debounceMs', 15000)
    paths = memory_cfg.get('paths')
    if not isinstance(paths, list):
        paths = []
        memory_cfg['paths'] = paths
    workspace_path = next((item for item in paths if isinstance(item, dict) and item.get('name') == 'workspace'), None)
    if not workspace_path:
        workspace_path = {'name': 'workspace'}
        paths.append(workspace_path)
    workspace_path['path'] = workspace
    workspace_path['pattern'] = '**/*.md'

    if memory.get('backend') == 'qmd':
        # 探测 qmd 命令路径
        import subprocess
        qmd_path = '/usr/local/bin/qmd'
        try:
            # 尝试运行 qmd --version 来确认它是否能正常执行（处理 Illegal instruction）
            subprocess.run([qmd_path, '--version'], capture_output=True, check=True)
        except Exception:
            try:
                # 尝试 npm 全局安装的默认路径
                qmd_path = 'qmd'
                subprocess.run([qmd_path, '--version'], capture_output=True, check=True)
                qmd_path = subprocess.check_output(['which', 'qmd']).decode().strip()
            except Exception:
                print('⚠️ 警告: qmd 命令执行失败，向量内存功能可能受限')
                qmd_path = None

        if qmd_path:
            memory_cfg['command'] = qmd_path
        else:
            # 如果 qmd 不可用，禁用内存后端或切换回默认
            if memory.get('backend') == 'qmd':
                print('⚠️ 自动禁用 qmd 内存后端（命令不可用或架构不兼容）')
                memory['backend'] = 'off'
    else:
        memory_cfg.setdefault('command', '/usr/local/bin/qmd')
    # 参考官方文档模式: off | non-main | all
    sandbox_mode = (ctx.env.get('OPENCLAW_SANDBOX_MODE') or 'off').strip().lower()
    sandbox['mode'] = sandbox_mode

    # 参考官方文档范围: session | agent | shared
    sandbox_scope = (ctx.env.get('OPENCLAW_SANDBOX_SCOPE') or 'agent').strip().lower()
    sandbox['scope'] = sandbox_scope

    # 参考官方文档访问: none | ro | rw
    sandbox_workspace_access = (ctx.env.get('OPENCLAW_SANDBOX_WORKSPACE_ACCESS') or 'none').strip().lower()
    sandbox['workspaceAccess'] = sandbox_workspace_access

    # 如果启用了沙箱模式且非 off，允许指定 Docker 镜像
    if sandbox_mode != 'off':
        docker_cfg = ensure_path(sandbox, ['docker'])
        if ctx.env.get('OPENCLAW_SANDBOX_DOCKER_IMAGE'):
            docker_cfg['image'] = ctx.env['OPENCLAW_SANDBOX_DOCKER_IMAGE']
        elif 'image' not in docker_cfg:
            # 默认使用官方标准镜像
            docker_cfg['image'] = 'openclaw-sandbox:bookworm-slim'

        # 自动配置加入当前容器网络（解决沙箱无网络问题）
        if parse_bool(ctx.env.get('OPENCLAW_SANDBOX_JOIN_NETWORK'), False):
            hostname = ctx.env.get('HOSTNAME')
            if hostname:
                docker_cfg['network'] = f"container:{hostname}"
                docker_cfg['dangerouslyAllowContainerNamespaceJoin'] = True

    sandbox_json = parse_json_object(ctx.env.get('OPENCLAW_SANDBOX_JSON'), 'OPENCLAW_SANDBOX_JSON')
    if sandbox_json is not None:
        deep_merge(sandbox, sandbox_json)
        print('✅ 已从 OPENCLAW_SANDBOX_JSON 同步沙箱配置')

    # 自动补全加入容器网络所需的特殊权限
    if 'docker' in sandbox and isinstance(sandbox['docker'], dict):
        d_cfg = sandbox['docker']
        net = d_cfg.get('network')
        if isinstance(net, str) and net.startswith('container:'):
            if d_cfg.get('dangerouslyAllowContainerNamespaceJoin') is not True:
                d_cfg['dangerouslyAllowContainerNamespaceJoin'] = True
                print(f'✅ 检测到沙箱网络配置为 {net}，已自动开启 dangerouslyAllowContainerNamespaceJoin')

    tools = ensure_path(ctx.config, ['tools'])
    tools_json = parse_json_object(ctx.env.get('OPENCLAW_TOOLS_JSON'), 'OPENCLAW_TOOLS_JSON')

    if tools_json is not None:
        deep_merge(tools, tools_json)
        print('✅ 已从 OPENCLAW_TOOLS_JSON 同步工具配置')
    else:
        # 默认配置
        tools['profile'] = 'full'
        ensure_path(tools, ['sessions'])['visibility'] = 'all'
        ensure_path(tools, ['fs'])['workspaceOnly'] = True
        print(f'✅ Agent/工具配置同步完成: sandbox.mode={sandbox_mode}, scope={sandbox_scope}, workspaceAccess={sandbox_workspace_access}, profile=full')


def sync_feishu_channel(ctx, channel):
    env = ctx.env
    account_id = (env.get('FEISHU_DEFAULT_ACCOUNT') or 'default').strip() or 'default'
    channel.update({
        'enabled': True,
        'appId': env['FEISHU_APP_ID'],
        'appSecret': env['FEISHU_APP_SECRET'],
        'dmPolicy': env.get('FEISHU_DM_POLICY') or ctx.default_dm_policy,
        'allowFrom': parse_csv(env.get('FEISHU_ALLOW_FROM')) or ctx.default_allow_from,
        'groupPolicy': env.get('FEISHU_GROUP_POLICY') or ctx.default_group_policy,
        'groupAllowFrom': parse_csv(env.get('FEISHU_GROUP_ALLOW_FROM')),
        'streaming': parse_bool(env.get('FEISHU_STREAMING', 'true'), True),
        'requireMention': parse_bool(env.get('FEISHU_REQUIRE_MENTION', 'true'), True),
    })

    feishu_groups = parse_json_object(env.get('FEISHU_GROUPS_JSON'), 'FEISHU_GROUPS_JSON')
    if feishu_groups is not None:
        channel['groups'] = feishu_groups

    channel.setdefault('accounts', {})
    channel['accounts'][account_id] = {
        'appId': env['FEISHU_APP_ID'],
        'appSecret': env['FEISHU_APP_SECRET'],
        'name': env.get('FEISHU_NAME') or 'OpenClaw Bot',
    }


def sync_dingtalk_channel(ctx, channel):
    env = ctx.env
    channel.update({
        'enabled': True,
        'clientId': env['DINGTALK_CLIENT_ID'],
        'clientSecret': env['DINGTALK_CLIENT_SECRET'],
        'dmPolicy': env.get('DINGTALK_DM_POLICY') or ctx.default_dm_policy,
        'groupPolicy': env.get('DINGTALK_GROUP_POLICY') or ctx.default_group_policy,
        'messageType': env.get('DINGTALK_MESSAGE_TYPE') or 'markdown',
        'allowFrom': parse_csv(env.get('DINGTALK_ALLOW_FROM')) or ctx.default_allow_from,
    })
    # 注意：根据最新 Schema，agentId 和 corpId 已被弃用且不再被运行时解析，
    # 设置它们会导致 "must NOT have additional properties" 或类型校验错误。
    if env.get('DINGTALK_CARD_STREAMING_MODE'):
        channel['cardStreamingMode'] = env['DINGTALK_CARD_STREAMING_MODE']
    if env.get('DINGTALK_ACK_REACTION'):
        channel['ackReaction'] = env['DINGTALK_ACK_REACTION']
    if env.get('DINGTALK_CARD_STREAM_INTERVAL'):
        channel['cardStreamInterval'] = int(env['DINGTALK_CARD_STREAM_INTERVAL'])
    if env.get('DINGTALK_CARD_TEMPLATE_ID'):
        channel['cardTemplateId'] = env['DINGTALK_CARD_TEMPLATE_ID']
    if env.get('DINGTALK_CARD_TEMPLATE_KEY'):
        channel['cardTemplateKey'] = env['DINGTALK_CARD_TEMPLATE_KEY']
    if env.get('DINGTALK_MAX_RECONNECT_CYCLES'):
        channel['maxReconnectCycles'] = int(env['DINGTALK_MAX_RECONNECT_CYCLES'])
    if env.get('DINGTALK_DEBUG'):
        channel['debug'] = parse_bool(env.get('DINGTALK_DEBUG'), False)
    if env.get('DINGTALK_JOURNAL_TTL_DAYS'):
        channel['journalTTLDays'] = int(env['DINGTALK_JOURNAL_TTL_DAYS'])
    
    account = ensure_path(channel, ['accounts', 'default'])
    account.update({
        'clientId': env['DINGTALK_CLIENT_ID'],
        'clientSecret': env['DINGTALK_CLIENT_SECRET'],
        'dmPolicy': env.get('DINGTALK_DM_POLICY') or ctx.default_dm_policy,
        'groupPolicy': env.get('DINGTALK_GROUP_POLICY') or ctx.default_group_policy,
        'messageType': env.get('DINGTALK_MESSAGE_TYPE') or 'markdown',
        'allowFrom': parse_csv(env.get('DINGTALK_ALLOW_FROM')) or ctx.default_allow_from,
    })
    if env.get('DINGTALK_CARD_STREAMING_MODE'):
        account['cardStreamingMode'] = env['DINGTALK_CARD_STREAMING_MODE']
    if env.get('DINGTALK_ACK_REACTION'):
        account['ackReaction'] = env['DINGTALK_ACK_REACTION']
    if env.get('DINGTALK_CARD_STREAM_INTERVAL'):
        account['cardStreamInterval'] = int(env['DINGTALK_CARD_STREAM_INTERVAL'])
    if env.get('DINGTALK_CARD_TEMPLATE_ID'):
        account['cardTemplateId'] = env['DINGTALK_CARD_TEMPLATE_ID']
    if env.get('DINGTALK_CARD_TEMPLATE_KEY'):
        account['cardTemplateKey'] = env['DINGTALK_CARD_TEMPLATE_KEY']
    if env.get('DINGTALK_MAX_RECONNECT_CYCLES'):
        account['maxReconnectCycles'] = int(env['DINGTALK_MAX_RECONNECT_CYCLES'])
    if env.get('DINGTALK_DEBUG'):
        account['debug'] = parse_bool(env.get('DINGTALK_DEBUG'), False)


def sync_qqbot_channel(ctx, channel):
    env = ctx.env
    channel.update({
        'enabled': True,
        'appId': env['QQBOT_APP_ID'],
        'clientSecret': env['QQBOT_CLIENT_SECRET'],
        'allowFrom': parse_csv(env.get('QQBOT_ALLOW_FROM')) or ctx.default_allow_from,
    })
    ensure_path(channel, ['accounts', 'default']).update({
        'enabled': True,
        'appId': env['QQBOT_APP_ID'],
        'clientSecret': env['QQBOT_CLIENT_SECRET'],
    })


def sync_napcat_channel(ctx, channel):
    env = ctx.env
    channel.update({
        'enabled': True,
        'reverseWsPort': int(env['NAPCAT_REVERSE_WS_PORT']),
        'requireMention': True,
        'rateLimitMs': 1000,
        'dmPolicy': env.get('NAPCAT_DM_POLICY') or ctx.default_dm_policy,
        'allowFrom': parse_csv(env.get('NAPCAT_ALLOW_FROM')) or ctx.default_allow_from,
        'groupPolicy': env.get('NAPCAT_GROUP_POLICY') or ctx.default_group_policy,
    })
    if env.get('NAPCAT_HTTP_URL'):
        channel['httpUrl'] = env['NAPCAT_HTTP_URL']
    if env.get('NAPCAT_ACCESS_TOKEN'):
        channel['accessToken'] = env['NAPCAT_ACCESS_TOKEN']
    if env.get('NAPCAT_ADMINS'):
        channel['admins'] = [int(item) for item in parse_csv(env.get('NAPCAT_ADMINS'))]


def sync_wecom_channel(ctx, channel):
    env = ctx.env
    channel['enabled'] = True
    channel['dmPolicy'] = env.get('WECOM_DM_POLICY') or ctx.default_dm_policy
    channel['allowFrom'] = parse_csv(env.get('WECOM_ALLOW_FROM')) or ctx.default_allow_from
    channel['groupPolicy'] = env.get('WECOM_GROUP_POLICY') or ctx.default_group_policy

    if env.get('WECOM_ADMIN_USERS'):
        channel['adminUsers'] = parse_csv(env.get('WECOM_ADMIN_USERS'))

    commands = ensure_path(channel, ['commands'])
    commands['enabled'] = parse_bool(env.get('WECOM_COMMANDS_ENABLED'), True)
    commands['allowlist'] = parse_csv(env.get('WECOM_COMMANDS_ALLOWLIST')) or ['/new', '/compact', '/help', '/status']

    dynamic_agents = ensure_path(channel, ['dynamicAgents'])
    dynamic_agents['enabled'] = parse_bool(env.get('WECOM_DYNAMIC_AGENTS_ENABLED'), True)
    dynamic_agents['adminBypass'] = parse_bool(env.get('WECOM_DYNAMIC_AGENTS_ADMIN_BYPASS'), False)

    has_single_account = bool((env.get('WECOM_BOT_ID') or '').strip() and (env.get('WECOM_SECRET') or '').strip())
    if not has_single_account:
        return

    account_id = (env.get('WECOM_DEFAULT_ACCOUNT') or 'default').strip() or 'default'
    channel['defaultAccount'] = account_id
    account = ensure_path(channel, [account_id])
    account.update({'botId': env['WECOM_BOT_ID'], 'secret': env['WECOM_SECRET']})

    optional_fields = {
        'WECOM_WELCOME_MESSAGE': 'welcomeMessage',
        'WECOM_DM_POLICY': 'dmPolicy',
        'WECOM_GROUP_POLICY': 'groupPolicy',
        'WECOM_WORKSPACE_TEMPLATE': 'workspaceTemplate',
    }
    for env_name, field_name in optional_fields.items():
        if env.get(env_name):
            account[field_name] = env[env_name]

    if env.get('WECOM_ALLOW_FROM'):
        account['allowFrom'] = parse_csv(env.get('WECOM_ALLOW_FROM'))
    if env.get('WECOM_GROUP_ALLOW_FROM'):
        account['groupAllowFrom'] = parse_csv(env.get('WECOM_GROUP_ALLOW_FROM'))
    account['sendThinkingMessage'] = parse_bool(env.get('WECOM_SEND_THINKING_MESSAGE'), False)

    dm_cfg = ensure_path(account, ['dm'])
    dm_cfg['createAgentOnFirstMessage'] = parse_bool(env.get('WECOM_DM_CREATE_AGENT_ON_FIRST_MESSAGE'), True)

    group_chat = ensure_path(account, ['groupChat'])
    group_chat['enabled'] = parse_bool(env.get('WECOM_GROUP_CHAT_ENABLED'), True)
    group_chat['requireMention'] = parse_bool(env.get('WECOM_GROUP_CHAT_REQUIRE_MENTION'), True)
    group_chat['mentionPatterns'] = parse_csv(env.get('WECOM_GROUP_CHAT_MENTION_PATTERNS')) or ['@']

    if env.get('WECOM_AGENT_CORP_ID') or env.get('WECOM_AGENT_CORP_SECRET') or env.get('WECOM_AGENT_ID'):
        agent = ensure_path(account, ['agent'])
        if env.get('WECOM_AGENT_CORP_ID'):
            agent['corpId'] = env['WECOM_AGENT_CORP_ID']
        if env.get('WECOM_AGENT_CORP_SECRET'):
            agent['corpSecret'] = env['WECOM_AGENT_CORP_SECRET']
        if env.get('WECOM_AGENT_ID'):
            agent['agentId'] = int(env['WECOM_AGENT_ID'])

    webhook_map = parse_json_object(env.get('WECOM_WEBHOOKS_JSON'), 'WECOM_WEBHOOKS_JSON')
    if webhook_map is not None:
        account['webhooks'] = webhook_map

    network = {}
    if env.get('WECOM_NETWORK_EGRESS_PROXY_URL'):
        network['egressProxyUrl'] = env['WECOM_NETWORK_EGRESS_PROXY_URL']
    if env.get('WECOM_NETWORK_API_BASE_URL'):
        network['apiBaseUrl'] = env['WECOM_NETWORK_API_BASE_URL']
    if network:
        account['network'] = deep_merge(account.get('network', {}), network)


def apply_channel_rules(ctx):
    channel_labels = {
        'telegram': 'Telegram',
        'feishu': '飞书',
        'dingtalk': '钉钉',
        'qqbot': 'QQ 机器人',
        'napcat': 'NapCat',
        'wecom': '企业微信',
    }

    rules = [
        {
            'channel': 'telegram',
            'required_envs': ['TELEGRAM_BOT_TOKEN'],
            'sync': lambda channel: channel.update({
                'botToken': ctx.env['TELEGRAM_BOT_TOKEN'],
                'dmPolicy': ctx.env.get('TELEGRAM_DM_POLICY') or ctx.default_dm_policy,
                'allowFrom': parse_csv(ctx.env.get('TELEGRAM_ALLOW_FROM')) or ctx.default_allow_from,
                'groupPolicy': ctx.env.get('TELEGRAM_GROUP_POLICY') or ctx.default_group_policy,
                'streaming': {
                    'mode': 'partial',
                    'chunkMode': 'length',
                    'preview': {
                        'chunk': {
                            'minChars': 200,
                            'maxChars': 800,
                            'breakPreference': 'paragraph',
                        },
                    },
                    'block': {
                        'enabled': False,
                        'coalesce': {
                            'idleMs': 1000,
                        },
                    },
                },
            }),
            'install': False,
        },
        {
            'channel': 'feishu',
            'required_envs': ['FEISHU_APP_ID', 'FEISHU_APP_SECRET'],
            'sync': lambda channel: sync_feishu_channel(ctx, channel),
            'install': True,
        },
        {
            'channel': 'dingtalk',
            'required_envs': ['DINGTALK_CLIENT_ID', 'DINGTALK_CLIENT_SECRET'],
            'sync': lambda channel: sync_dingtalk_channel(ctx, channel),
            'install': True,
        },
        {
            'channel': 'qqbot',
            'plugin_id': 'openclaw-qqbot',
            'required_envs': ['QQBOT_APP_ID', 'QQBOT_CLIENT_SECRET'],
            'sync': lambda channel: sync_qqbot_channel(ctx, channel),
            'install': True,
        },
        {
            'channel': 'napcat',
            'required_envs': ['NAPCAT_REVERSE_WS_PORT'],
            'sync': lambda channel: sync_napcat_channel(ctx, channel),
            'install': True,
        },
        {
            'channel': 'wecom',
            'required_envs': ['WECOM_BOT_ID', 'WECOM_SECRET'],
            'sync': lambda channel: sync_wecom_channel(ctx, channel),
            'install': True,
        },
    ]

    for rule in rules:
        channel_id = rule['channel']
        plugin_id = rule.get('plugin_id', channel_id)
        channel_label = channel_labels.get(channel_id, channel_id)
        has_env = all(ctx.env.get(key) for key in rule['required_envs'])

        if has_env:
            channel = ctx.channel(channel_id)
            rule['sync'](channel)
            ctx.enable_channel(plugin_id, install=rule['install'])
            if plugin_id != channel_id:
                ctx.disable_channel(channel_id)
            print(f"✅ 渠道同步: {channel_label}")
            continue

        if channel_id == 'feishu' and not ctx.has_feishu_any_env:
            ctx.disable_channel(plugin_id)
            continue

        if channel_id == 'dingtalk' and not ctx.has_dingtalk_any_env:
            ctx.disable_channel(plugin_id)
            continue

        if channel_id == 'wecom' and not ctx.has_wecom_any_env:
            ctx.disable_channel(plugin_id)
            continue

        if channel_id == 'qqbot' and not ctx.has_qqbot_any_env:
            ctx.disable_channel(plugin_id)
            ctx.entries.pop('qqbot', None)
            continue

        if ctx.entries.get(plugin_id, {}).get('enabled'):
            ctx.disable_channel(plugin_id)
            print(f"🚫 {channel_label} 环境变量缺失，已禁用渠道")
        else:
            print(f"ℹ️ {channel_label} 未提供环境变量，保持禁用")


def apply_wecom_legacy_v1_compat(ctx):
    has_new_single_account = bool((ctx.env.get('WECOM_BOT_ID') or '').strip() and (ctx.env.get('WECOM_SECRET') or '').strip())
    has_legacy_v1 = bool((ctx.env.get('WECOM_TOKEN') or '').strip() and (ctx.env.get('WECOM_ENCODING_AES_KEY') or '').strip())
    if has_new_single_account or not has_legacy_v1:
        return

    channel = ctx.channel('wecom')
    sync_wecom_channel(ctx, channel)
    ctx.enable_channel('wecom', install=True)
    print('✅ 渠道同步: 企业微信（兼容旧版环境变量）')


def apply_multi_account_plugin_state(ctx):
    feishu_accounts = get_feishu_accounts(ctx.channels.get('feishu'))
    if ctx.has_feishu_accounts_env:
        if feishu_accounts:
            ctx.enable_channel('feishu', install=True)
            print('✅ 已根据飞书多账号环境变量启用插件')
        else:
            ctx.disable_channel('feishu')
            print('ℹ️ 飞书多账号环境变量未生成有效账号，保持插件禁用')
    elif not ctx.has_feishu_any_env and not feishu_accounts:
        ctx.disable_channel('feishu')
        print('ℹ️ 飞书未提供任何环境变量，保持插件禁用')

    dingtalk_accounts = get_dingtalk_accounts(ctx.channels.get('dingtalk'))
    if ctx.has_dingtalk_accounts_env:
        if dingtalk_accounts:
            ctx.enable_channel('dingtalk', install=True)
            print('✅ 已根据钉钉多机器人环境变量启用插件')
        else:
            ctx.disable_channel('dingtalk')
            print('ℹ️ 钉钉多机器人环境变量未生成有效账号，保持插件禁用')
    elif not ctx.has_dingtalk_any_env:
        ctx.disable_channel('dingtalk')
        print('ℹ️ 钉钉未提供任何环境变量，保持插件禁用')

    wecom_accounts = get_wecom_accounts(ctx.channels.get('wecom'))
    if ctx.has_wecom_accounts_env:
        if wecom_accounts:
            ctx.enable_channel('wecom', install=True)
            print('✅ 已根据企业微信多账号环境变量启用插件')
        else:
            ctx.disable_channel('wecom')
            print('ℹ️ 企业微信多账号环境变量未生成有效账号，保持插件禁用')
    elif not ctx.has_wecom_any_env:
        ctx.disable_channel('wecom')
        print('ℹ️ 企业微信未提供任何环境变量，保持插件禁用')

    qqbot_accounts = get_qqbot_accounts(ctx.channels.get('qqbot'))
    if ctx.has_qqbot_bots_env:
        if qqbot_accounts:
            set_qqbot_plugin_entries(ctx, True, install=True)
            print('✅ 已根据 QQ 机器人多 Bot 环境变量启用插件 openclaw-qqbot')
        else:
            set_qqbot_plugin_entries(ctx, False)
            print('ℹ️ QQ 机器人多 Bot 环境变量未生成有效 Bot，保持插件禁用')
    elif not ctx.has_qqbot_any_env:
        set_qqbot_plugin_entries(ctx, False)
        print('ℹ️ QQ 机器人未提供任何环境变量，保持插件禁用')


def migrate_qqbot_plugin_entry(ctx):
    legacy_plugin_id = 'qqbot'
    official_plugin_id = 'openclaw-qqbot'
    legacy_entry = ctx.entries.get(legacy_plugin_id)
    official_entry = ctx.entries.get(official_plugin_id)

    if isinstance(legacy_entry, dict):
        if not isinstance(official_entry, dict):
            ctx.entries[official_plugin_id] = deepcopy(legacy_entry)
        elif legacy_entry.get('enabled') and not official_entry.get('enabled'):
            official_entry['enabled'] = True

    ctx.entries.pop(legacy_plugin_id, None)

    legacy_install = ctx.installs.get(legacy_plugin_id)
    official_install = ctx.installs.get(official_plugin_id)
    if isinstance(legacy_install, dict):
        if not isinstance(official_install, dict):
            migrated_install = deepcopy(legacy_install)
            migrated_install['sourcePath'] = '/home/node/.openclaw/openclaw-qqbot'
            migrated_install['installPath'] = '/home/node/.openclaw/extensions/openclaw-qqbot'
            ctx.installs[official_plugin_id] = migrated_install

    ctx.installs.pop(legacy_plugin_id, None)


def apply_feishu_plugin_switch(ctx):
    feishu_accounts = get_feishu_accounts(ctx.channels.get('feishu'))
    has_credentials = bool(ctx.env.get('FEISHU_APP_ID') and ctx.env.get('FEISHU_APP_SECRET')) or bool(feishu_accounts)
    official_plugin_id = 'openclaw-lark'
    legacy_plugin_id = 'feishu-openclaw-plugin'
    if legacy_plugin_id in ctx.entries and official_plugin_id not in ctx.entries:
        legacy_entry = ctx.entries.get(legacy_plugin_id)
        if isinstance(legacy_entry, dict):
            ctx.entries[official_plugin_id] = deepcopy(legacy_entry)
        del ctx.entries[legacy_plugin_id]
        print('✅ 已将飞书官方插件 ID 从 feishu-openclaw-plugin 迁移为 openclaw-lark')
    if ctx.feishu_plugin_explicit:
        ctx.entries[official_plugin_id] = {'enabled': ctx.feishu_plugin_enabled}
        ctx.entries['feishu'] = {'enabled': not ctx.feishu_plugin_enabled}
        if ctx.feishu_plugin_enabled:
            print('✅ 已启用插件开关: 飞书官方插件 openclaw-lark')
            print('🚫 已自动禁用旧版渠道: 飞书')
        else:
            print('🚫 已禁用插件开关: 飞书官方插件 openclaw-lark')
            print('✅ 已自动启用旧版渠道: 飞书')
        return

    ctx.entries[official_plugin_id] = {'enabled': False}
    ctx.entries['feishu'] = {'enabled': has_credentials}
    if has_credentials:
        print('ℹ️ 飞书官方插件开关未配置，默认启用旧版飞书渠道并禁用官方插件')
    else:
        print('ℹ️ 未检测到飞书凭证且飞书官方插件开关未配置，已同时禁用官方插件和旧版飞书渠道')


def finalize_plugins(ctx):
    
    ctx.plugins['allow'] = [name for name, entry in ctx.entries.items() if entry.get('enabled')]
    print('📦 已配置插件集合: ' + ', '.join(ctx.plugins['allow']))


def sync_channels_and_plugins(ctx):
    if not is_openclaw_sync_enabled(ctx.env):
        print('ℹ️ 已关闭整体配置同步，跳过渠道与插件同步')
        return

    # 默认启用插件，除非显式禁用
    ctx.plugins['enabled'] = parse_bool(ctx.env.get('OPENCLAW_PLUGINS_ENABLED', 'true'), True)

    apply_channel_rules(ctx)
    apply_wecom_legacy_v1_compat(ctx)
    merge_feishu_accounts_from_env(ctx.channels, ctx.env)
    # 环境同步后再次标准化飞书结构，确保冗余字段被移除
    normalize_feishu_config(ctx.channels)
    
    merge_dingtalk_accounts_from_env(ctx.channels, ctx.env)
    # 环境同步后再次标准化钉钉结构，确保冗余字段被移除
    normalize_dingtalk_config(ctx.channels)
    
    merge_wecom_accounts_from_env(ctx.channels, ctx.env)
    merge_qqbot_bots_from_env(ctx.channels, ctx.env)
    migrate_qqbot_plugin_entry(ctx)
    apply_multi_account_plugin_state(ctx)
    apply_feishu_plugin_switch(ctx)
    finalize_plugins(ctx)
    validate_feishu_multi_accounts(ctx.channels)
    validate_dingtalk_multi_accounts(ctx.channels)
    validate_wecom_multi_accounts(ctx.channels)
    validate_qqbot_multi_accounts(ctx.channels)


def sync_gateway(ctx):
    if not is_openclaw_sync_enabled(ctx.env):
        print('ℹ️ 已关闭整体配置同步，跳过 Gateway 同步')
        return

    if not ctx.env.get('OPENCLAW_GATEWAY_TOKEN'):
        return

    gateway = ensure_path(ctx.config, ['gateway'])
    gateway['port'] = int(ctx.env.get('OPENCLAW_GATEWAY_PORT') or 18789)
    gateway['bind'] = ctx.env.get('OPENCLAW_GATEWAY_BIND') or '0.0.0.0'
    gateway['mode'] = ctx.env.get('OPENCLAW_GATEWAY_MODE') or 'local'

    control_ui = ensure_path(gateway, ['controlUi'])
    control_ui['allowInsecureAuth'] = parse_bool(ctx.env.get('OPENCLAW_GATEWAY_ALLOW_INSECURE_AUTH', 'true'), True)
    control_ui['dangerouslyDisableDeviceAuth'] = parse_bool(ctx.env.get('OPENCLAW_GATEWAY_DANGEROUSLY_DISABLE_DEVICE_AUTH', 'false'), False)
    if ctx.env.get('OPENCLAW_GATEWAY_ALLOWED_ORIGINS'):
        control_ui['allowedOrigins'] = parse_csv(ctx.env.get('OPENCLAW_GATEWAY_ALLOWED_ORIGINS'))

    auth = ensure_path(gateway, ['auth'])
    auth['token'] = ctx.env['OPENCLAW_GATEWAY_TOKEN']
    auth['mode'] = ctx.env.get('OPENCLAW_GATEWAY_AUTH_MODE') or 'token'
    print('✅ Gateway 同步完成')


def migrate_tts_config(config):
    messages = config.get('messages')
    if not isinstance(messages, dict):
        return
    
    tts = messages.get('tts')
    if not isinstance(tts, dict):
        return
    
    # 检测旧版格式：tts 下直接包含 edge 且没有 providers
    if 'edge' in tts and 'providers' not in tts:
        print('检测到旧版 TTS 配置格式，正在执行自动迁移...')
        old_edge = tts.pop('edge')
        if not isinstance(old_edge, dict):
            old_edge = {}
        
        provider = tts.get('provider', 'edge')
        providers = {
            'edge': {
                'voice': old_edge.get('voice', 'zh-CN-XiaoxiaoNeural'),
                'lang': old_edge.get('lang', 'zh-CN'),
                'outputFormat': old_edge.get('outputFormat', 'ogg-24khz-16bit-mono-opus'),
                'pitch': old_edge.get('pitch', '+0Hz'),
                'rate': old_edge.get('rate', '+0%'),
                'volume': old_edge.get('volume', '+0%'),
                'timeoutMs': old_edge.get('timeoutMs', 30000),
            }
        }
        
        tts['auto'] = tts.get('auto', 'off')
        tts['mode'] = tts.get('mode', 'final')
        tts['provider'] = provider
        tts['providers'] = providers
        print('✅ TTS 配置迁移完成')


def sync():
    path = os.environ.get('CONFIG_FILE', '/home/node/.openclaw/openclaw.json')
    try:
        if not is_openclaw_sync_enabled(os.environ):
            print('ℹ️ 已关闭整体配置同步，跳过所有环境变量同步逻辑')
            return

        config = load_config_with_compat(path)
        migrate_tts_config(config)
        ctx = SyncContext(config, os.environ)

        migrate_feishu_config(ctx.channels)
        normalize_dingtalk_config(ctx.channels)
        normalize_wecom_config(ctx.channels)
        normalize_qqbot_config(ctx.channels)
        normalize_telegram_config(ctx.channels)

        sync_models(ctx)
        sync_agent_and_tools(ctx)
        sync_channels_and_plugins(ctx)
        sync_gateway(ctx)

        ensure_path(ctx.config, ['meta'])['lastTouchedAt'] = utc_now_iso()
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(ctx.config, f, indent=2, ensure_ascii=False)
    except Exception as exc:
        print(f'❌ 同步失败: {exc}', file=sys.stderr)
        sys.exit(1)


sync()
PYCODE
}

normalize_sync_check() {
    local global_sync_check="${SYNC_OPENCLAW_CONFIG:-true}"
    local model_sync_check="${SYNC_MODEL_CONFIG:-true}"
    global_sync_check="$(echo "$global_sync_check" | tr '[:upper:]' '[:lower:]' | xargs)"
    model_sync_check="$(echo "$model_sync_check" | tr '[:upper:]' '[:lower:]' | xargs)"

    if [ "$global_sync_check" = "false" ] || [ "$global_sync_check" = "0" ] || [ "$global_sync_check" = "no" ]; then
        echo "global-disabled"
        return
    fi

    if [ "$model_sync_check" = "false" ] || [ "$model_sync_check" = "0" ] || [ "$model_sync_check" = "no" ]; then
        echo "model-disabled"
        return
    fi

    echo "enabled"
}

collect_provider_names() {
    local names=("default")
    local i
    for i in 2 3 4 5 6; do
        local name_var="MODEL${i}_NAME"
        local provider_name="${!name_var}"
        if [ -n "$provider_name" ]; then
            names+=("$provider_name")
        else
            names+=("model${i}")
        fi
    done
    echo "${names[@]}"
}

normalize_model_ref_shell() {
    local raw="$1"
    shift
    local provider_prefix known
    local known_providers=("$@")

    if [ -z "$raw" ]; then
        echo ""
        return
    fi

    if [[ "$raw" != */* ]]; then
        echo "default/$raw"
        return
    fi

    provider_prefix="${raw%%/*}"
    for known in "${known_providers[@]}"; do
        if [ "$provider_prefix" = "$known" ]; then
            echo "$raw"
            return
        fi
    done

    echo "default/$raw"
}

print_model_summary() {
    local sync_check final_mid final_imid
    local provider_names extra_providers i api_key_var provider_name_var provider_name
    sync_check="$(normalize_sync_check)"

    if [ "$sync_check" = "global-disabled" ]; then
        echo "整体配置: 手动模式 (跳过环境变量同步)"
        return
    fi

    if [ "$sync_check" = "model-disabled" ]; then
        echo "模型配置: 手动模式 (跳过模型环境变量同步)"
        return
    fi

    read -r -a provider_names <<< "$(collect_provider_names)"

    final_mid="${PRIMARY_MODEL:-${MODEL_ID:-gpt-4o}}"
    final_mid="$(normalize_model_ref_shell "$final_mid" "${provider_names[@]}")"

    final_imid="${IMAGE_MODEL_ID:-${MODEL_ID:-gpt-4o}}"
    final_imid="$(normalize_model_ref_shell "$final_imid" "${provider_names[@]}")"

    echo "当前主模型: $final_mid"
    echo "当前图片模型: $final_imid"

    extra_providers=()
    for i in 2 3 4 5 6; do
        api_key_var="MODEL${i}_API_KEY"
        provider_name_var="MODEL${i}_NAME"
        if [ -n "${!api_key_var}" ] || [ -n "${!provider_name_var}" ]; then
            provider_name="${!provider_name_var}"
            if [ -z "$provider_name" ]; then
                provider_name="model${i}"
            fi
            extra_providers+=("$provider_name")
        fi
    done

    if [ ${#extra_providers[@]} -gt 0 ]; then
        echo "额外提供商: ${extra_providers[*]}"
    fi
}

print_runtime_summary() {
    log_section "初始化完成"
    print_model_summary
    echo "API 协议: ${API_PROTOCOL:-openai-completions}"
    echo "Base URL: ${BASE_URL}"
    echo "上下文窗口: ${CONTEXT_WINDOW:-200000}"
    echo "最大 Tokens: ${MAX_TOKENS:-8192}"
    echo "Gateway 端口: $OPENCLAW_GATEWAY_PORT"
    echo "Gateway 绑定: $OPENCLAW_GATEWAY_BIND"
    echo "Gateway 模式: ${OPENCLAW_GATEWAY_MODE:-local}"
    echo "Gateway 允许域: ${OPENCLAW_GATEWAY_ALLOWED_ORIGINS:-未设置}"
    echo "Gateway 允许不安全认证: ${OPENCLAW_GATEWAY_ALLOW_INSECURE_AUTH:-true}"
    echo "Gateway 禁用设备认证: ${OPENCLAW_GATEWAY_DANGEROUSLY_DISABLE_DEVICE_AUTH:-false}"
    echo "插件启用: ${OPENCLAW_PLUGINS_ENABLED:-true}"
    echo "沙箱模式: ${OPENCLAW_SANDBOX_MODE:-off}"
    echo "沙箱范围: ${OPENCLAW_SANDBOX_SCOPE:-agent}"
    echo "沙箱访问权限: ${OPENCLAW_SANDBOX_WORKSPACE_ACCESS:-none}"
    echo "允许插件列表已由系统自动同步"
}

setup_runtime_env() {
    export BUN_INSTALL="/usr/local"
    export PATH="$BUN_INSTALL/bin:$PATH"
    export AGENT_REACH_HOME="/home/node/.agent-reach"
    export AGENT_REACH_VENV_HOME="/home/node/.agent-reach-venv"
    export PATH="$AGENT_REACH_HOME/bin:$PATH"
    
    if [ -d "$AGENT_REACH_VENV_HOME/bin" ]; then
        export PATH="$AGENT_REACH_VENV_HOME/bin:$PATH"
    fi

    # 创建一个全局包装脚本，确保交互式 shell 也能直接使用 agent-reach
    if [ -x "$AGENT_REACH_VENV_HOME/bin/agent-reach" ]; then
        cat > /usr/local/bin/agent-reach <<EOF
#!/bin/bash
source $AGENT_REACH_VENV_HOME/bin/activate
exec $AGENT_REACH_VENV_HOME/bin/agent-reach "\$@"
EOF
        chmod +x /usr/local/bin/agent-reach
    fi
    
    export DBUS_SESSION_BUS_ADDRESS=/dev/null
}

install_agent_reach() {
    if [ "${AGENT_REACH_ENABLED:-false}" != "true" ]; then
        return
    fi

    log_section "安装 Agent Reach"

    local github_url="https://github.com/Panniantong/agent-reach/archive/main.zip"
    local pip_mirror=""
    local pip_index_env=""

    if [ "${AGENT_REACH_USE_CN_MIRROR:-false}" = "true" ]; then
        github_url="https://gh.llkk.cc/https://github.com/Panniantong/agent-reach/archive/main.zip"
        pip_mirror="-i https://pypi.tuna.tsinghua.edu.cn/simple"
        pip_index_env="export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple"
    fi

    if gosu node test -f /home/node/.agent-reach-venv/bin/agent-reach; then
        local check_output
        check_output="$(gosu node bash -c "
            export PATH=\$PATH:/home/node/.local/bin
            $pip_index_env
            if [ -f ~/.agent-reach-venv/bin/activate ]; then
                source ~/.agent-reach-venv/bin/activate
            fi
            /home/node/.agent-reach-venv/bin/agent-reach check-update 2>&1 || true
        ")"
        echo "$check_output"

        if echo "$check_output" | grep -q '已是最新版本'; then
            echo "Agent Reach 已是最新版本，跳过安装步骤"
            return
        fi

        echo "Agent Reach 检测到可更新版本，开始自动更新..."
        gosu node bash -c "
            export PATH=\$PATH:/home/node/.local/bin
            $pip_index_env
            if [ -f ~/.agent-reach-venv/bin/activate ]; then
                source ~/.agent-reach-venv/bin/activate
            fi
            pip install --upgrade pip $pip_mirror
            pip install --upgrade $github_url $pip_mirror
        "
    else
        gosu node bash -c "
            export PATH=\$PATH:/home/node/.local/bin
            $pip_index_env
            if [ ! -d ~/.agent-reach-venv ]; then
                python3 -m venv ~/.agent-reach-venv
            fi
            source ~/.agent-reach-venv/bin/activate
            pip install --upgrade pip $pip_mirror
            pip install $github_url $pip_mirror
            agent-reach install --env=auto 
        "
    fi

    gosu node bash -c "
        export PATH=\$PATH:/home/node/.local/bin
        $pip_index_env
        if [ -f ~/.agent-reach-venv/bin/activate ]; then
            source ~/.agent-reach-venv/bin/activate
        fi

        # 配置代理（如果提供）
        if [ -n \"\$AGENT_REACH_PROXY\" ]; then
            agent-reach configure proxy \"\$AGENT_REACH_PROXY\"
        fi

        # 配置 Twitter Cookies
        if [ -n \"\$AGENT_REACH_TWITTER_COOKIES\" ]; then
            agent-reach configure twitter-cookies \"\$AGENT_REACH_TWITTER_COOKIES\"
        fi

        # 配置 Groq Key
        if [ -n \"\$AGENT_REACH_GROQ_KEY\" ]; then
            agent-reach configure groq-key \"\$AGENT_REACH_GROQ_KEY\"
        fi
        
        # 配置小红书 Cookies
        if [ -n \"\$AGENT_REACH_XHS_COOKIES\" ]; then
            agent-reach configure xhs-cookies \"\$AGENT_REACH_XHS_COOKIES\"
        fi
    "
    
    # 建立软链接到 /usr/local/bin 以便全局访问（如果需要）
    # 但我们已经在 setup_runtime_env 中处理了 PATH

    # 检查工作空间父目录下的 skills 目录中是否存在 agent-reach，若存在则同步到工作空间（仅删除目标 SKILL.md 并覆盖）
    local workspace_parent
    workspace_parent="$(dirname "$OPENCLAW_WORKSPACE")"
    if [ -d "$workspace_parent/skills/agent-reach" ]; then
        local src="$workspace_parent/skills/agent-reach"
        local dst="$OPENCLAW_WORKSPACE/skills/agent-reach"
        echo "检测到 $src，正在将其同步到工作空间: $dst"
        mkdir -p "$dst"
        rm -f "$dst/SKILL.md"
        cp -af "$src/." "$dst/" || true
        rm -rf "$src"
        if is_root; then
            chown -R node:node "$dst" || true
        fi
    fi
}

cleanup() {
    echo "=== 接收到停止信号,正在关闭服务 ==="
    if [ -n "$GATEWAY_PID" ]; then
        kill -TERM "$GATEWAY_PID" 2>/dev/null || true
        wait "$GATEWAY_PID" 2>/dev/null || true
    fi
    echo "=== 服务已停止 ==="
    exit 0
}

install_signal_traps() {
    trap cleanup SIGTERM SIGINT SIGQUIT
}

start_gateway() {
    log_section "启动 OpenClaw Gateway"

    gosu node env HOME=/home/node DBUS_SESSION_BUS_ADDRESS=/dev/null \
        BUN_INSTALL="/usr/local" AGENT_REACH_HOME="/home/node/.agent-reach" AGENT_REACH_VENV_HOME="/home/node/.agent-reach-venv" \
        PATH="/home/node/.agent-reach-venv/bin:/usr/local/bin:$PATH" \
        openclaw gateway run \
        --bind "$OPENCLAW_GATEWAY_BIND" \
        --port "$OPENCLAW_GATEWAY_PORT" \
        --token "$OPENCLAW_GATEWAY_TOKEN" \
        --verbose &
    GATEWAY_PID=$!

    echo "=== OpenClaw Gateway 已启动 (PID: $GATEWAY_PID) ==="
}

wait_for_gateway() {
    wait "$GATEWAY_PID"
    local exit_code=$?
    echo "=== OpenClaw Gateway 已退出 (退出码: $exit_code) ==="
    exit "$exit_code"
}

finalize_permissions() {
    if is_root; then
        chown -R node:node "$OPENCLAW_HOME" || true
    fi
}

main() {
    log_section "OpenClaw 初始化脚本"
    modify_node_uid_gid
    ensure_directories
    ensure_config_persistence
    fix_permissions_if_needed
    sync_seed_extensions
    install_agent_reach
    sync_config_with_env
    finalize_permissions
    print_runtime_summary
    setup_runtime_env
    install_signal_traps
    start_gateway
    wait_for_gateway
}

main
