# 后端服务源码（单一事实源）

`tool/image_platform_quota_server.dart` 是 **box 后端（图片平台 + 题库 + 插件市场）的
完整源码**，单文件、只依赖 `crypto` 与 Dart SDK。它是线上服务的权威源：

| 位置 | 作用 |
|---|---|
| 本仓 `tool/image_platform_quota_server.dart` | 权威源码（改动只从这里的版本演进） |
| hpa888 部署机 `/opt/box-backend/box-inspect/tool/image_platform_quota_server.dart` | 与上面**同一份**文件的部署副本 |
| hpa888 部署机 `/opt/box-backend/bin/image_platform_quota_server` | `dart compile exe` 出来的 AOT 二进制，systemd `box-image-platform` 跑它 |

> 历史欠账：2026-10-30 之前的约两周里，后端改动只落在部署机、没回仓，仓里的副本
> 落后 339 行（缺举报结案 `adminResolveReport`、权限目录、`save()` 串行化等）。
> 一旦部署机磁盘出事，源码等于没有版本史。现在已同步，**改动必须回仓**。

## 改后端的标准流程

```bash
# 1) 改源码（在部署机上改也行，但改完必须同步回仓）
cd /opt/box-backend/box-inspect
dart analyze tool/image_platform_quota_server.dart          # 应为 No issues
dart compile exe tool/image_platform_quota_server.dart \
  -o /opt/box-backend/bin/image_platform_quota_server.new

# 2) 冒烟：临时端口 + 独立 state，绝不碰线上数据（脚本见下）
PORT=18823 HOST=127.0.0.1 IMAGE_STATE_PATH=/tmp/smoke.json \
  IMAGE_REGISTRATION_ENABLED=true IMAGE_REGISTER_DEFAULT_QUOTA=50 \
  BOX_ADMIN_USERNAME=smokeadmin BOX_ADMIN_PASSWORD=smoke-pw-123456 \
  setsid /opt/box-backend/bin/image_platform_quota_server.new >/tmp/smoke.log 2>&1 &
BASE=http://127.0.0.1:18823 python3 e2e_market.py    # 23 步
fuser -k 18823/tcp

# 3) 上线（先备份二进制）
cd /opt/box-backend/bin
cp -a image_platform_quota_server image_platform_quota_server.bak.$(date +%Y%m%d%H%M)
systemctl stop box-image-platform
mv image_platform_quota_server.new image_platform_quota_server
systemctl start box-image-platform
systemctl show -p NRestarts --value box-image-platform   # 应为 0

# 4) 回仓（这一步最容易忘，而它决定灾备成不成立）
scp /opt/box-backend/box-inspect/tool/image_platform_quota_server.dart \
  175:/root/box/tool/image_platform_quota_server.dart
# 在 175 上验证「从 git 就能重建」：
cd /root/box && dart compile exe tool/image_platform_quota_server.dart -o /tmp/x.exe
git add tool/image_platform_quota_server.dart && git commit && git push
```

## 为什么在 175 上编译验证

部署机与本仓是两台机器。**只有从仓里那份文件能编出可运行的二进制**，「源码在 git
里」才算真的（2026-10-30 实测：`dart compile exe` 4.5s，产物 8.4 MB，能正常启动）。

## 冒烟脚本

在本机 `hpa888:/root/.hermes/cache/scratch/boxmarket/`：

| 脚本 | 覆盖 |
|---|---|
| `e2e_market.py` | 投稿→预览→通过→上架→下载→安装→举报→下架，23 步 |
| `e2e_market2.py` | 举报/结案/24h 限流，15 步 |
| `e2e_perms.py` | 权限目录与逐 code 声明，10 步 |
| `e2e_quicknote_action.py` | 新动作可投稿 + 非法动作 400 + 目录项数，3 步 |

两个坑：投稿接口是 `/api/plugins/submissions`（不是 `/api/plugin-market/...`）；
不给 `BOX_ADMIN_USERNAME/PASSWORD` 时所有审核类步骤 401，看起来像回归其实是没带管理员。
