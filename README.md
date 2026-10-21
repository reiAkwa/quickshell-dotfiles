# niri

用 Quickshell 0.3.2 复刻 `~/.config/waybar/{config.jsonc,style.css}` 的顶部栏。在原配置基础上，网络模块增加了可交互面板，新增了蓝牙连接按钮，把 `pulseaudio` 模块升级成支持应用音量与麦克风控制的混音器，并用 Quickshell 自己的 `NotificationServer` 取代 mako，提供右上角通知弹窗和通知中心，免打扰也并入了铃铛模块；铃铛右侧新增了保持屏幕常亮的“离开中”开关。电池模块与 ROG Control Center 联动：左键唤起控制中心，右键切换电源模式，并实时显示 asusd 当前的 Quiet/Balanced/Performance 模式。CPU 与内存模块不再调用外部 htop，两个图标都打开同一个 Quickshell 任务管理器面板。另有一个 `Alt+Space` 唤出的 Spotlight 应用启动器。

## 运行

```sh
qs -c niri
```

或直接指定路径：

```sh
qs -p ~/.config/quickshell/niri
```

后台运行：

```sh
qs -d -c niri
```

如果要在 niri 登录时替换 Waybar，把 `~/.config/niri/config.kdl` 里的

```kdl
spawn-at-startup "waybar"
```

改成

```kdl
spawn-at-startup "qs" "-c" "niri"
```

不要同时启动两者，否则两个顶部栏会重叠。

通知同样只能有一个守护进程：Quickshell 启动时会注册 `org.freedesktop.Notifications`，因此不要再启动 mako/dunst。仓库中已经：

- 把 `~/.config/niri/config.kdl` 里的 `spawn-at-startup "mako"` 注释掉；
- 执行 `systemctl --user mask mako.service`，避免 mako 被 D-Bus 激活后抢走名字。

需要恢复 mako 时执行 `systemctl --user unmask mako.service` 并取消 niri 配置里的注释。

## 项目结构

```text
niri/
├── shell.qml                  # 入口：为每块屏幕创建 Bar 和通知弹窗层，并创建全局 Spotlight
├── Bar.qml                    # PanelWindow、背景/底边、左中右三段布局
├── NotificationPopup.qml      # 右上角 toast 层（每屏一个，layer-shell overlay）
├── Spotlight.qml              # Alt+Space 应用启动器（模糊搜索 + 启动频率排序）
├── Niri.qml                   # Singleton：订阅 niri JSON event-stream
├── Stats.qml                  # Singleton：/proc/stat 与 /proc/meminfo（顶栏 10s/30s）
├── Tasks.qml                  # Singleton：任务管理器 /proc 采样、进程排序与结束进程
├── components/
│   ├── qmldir                 # 注册 Theme / Popout / Module / Glyph / PopupRow / PopupButton / VolumeSlider / Notifications / NotificationToast / StayAwake
│   ├── Theme.qml              # 颜色、尺寸、字体（从 style.css 抄来）
│   ├── Module.qml             # 通用圆角模块底 + 文本/前后图标 + 鼠标事件
│   ├── Glyph.qml              # Nerd Font 图标半宽单元（见下文）
│   ├── Popout.qml             # Singleton：同一时间只打开一个弹层
│   ├── Notifications.qml      # Singleton：NotificationServer、toast 队列、历史、DND
│   ├── StayAwake.qml          # Singleton：“离开中”开关状态（PersistentProperties 跨热重载保留）
│   ├── NotificationToast.qml  # 单条 toast 卡片（图标/正文/操作/自动超时）
│   ├── PopupRow.qml           # 网络/蓝牙弹层里的条目
│   ├── PopupButton.qml        # 弹层里的小按钮
│   └── VolumeSlider.qml       # 混音器里的音量滑条
└── modules/
    ├── Workspaces.qml         # niri/workspaces（终端/浏览器/QQ 图标，其余圆点）
    ├── ActiveWindow.qml       # niri/window
    ├── Clock.qml              # clock + 月历面板
    ├── Audio.qml              # pulseaudio（Pipewire）+ 应用/麦克风混音器
    ├── Network.qml            # network（NetworkManager + /proc/net/dev + Wi-Fi/有线面板）
    ├── Bluetooth.qml          # 新增：蓝牙开关、扫描、连接/配对
    ├── Cpu.qml                # cpu + 任务管理器入口
    ├── Memory.qml             # memory + 任务管理器入口
    ├── TaskManagerPanel.qml   # 新增：CPU/内存共用的任务管理器面板
    ├── Battery.qml            # battery（UPower）+ ROG Control Center 联动
    ├── NotificationCenter.qml # 铃铛 + 通知历史 + 免打扰开关
    ├── Away.qml               # 新增：离开中开关 + Wayland IdleInhibitor
    └── Tray.qml               # tray（StatusNotifier）
```

## Waybar → Quickshell 对照

| Waybar 模块 | Quickshell 实现 | 数据来源 |
| --- | --- | --- |
| `niri/workspaces` | `modules/Workspaces.qml` | `niri msg --json event-stream` |
| `niri/window` | `modules/ActiveWindow.qml` | 同上，取 `is_focused` 的窗口 |
| `clock` | `modules/Clock.qml` | `SystemClock` |
| `pulseaudio` | `modules/Audio.qml` | `Quickshell.Services.Pipewire`（默认输出/麦克风/应用流） |
| `network` | `modules/Network.qml` | `Quickshell.Networking` + `/proc/net/dev` |
| （新增）蓝牙 | `modules/Bluetooth.qml` | `Quickshell.Bluetooth`（BlueZ） |
| `cpu` | `modules/Cpu.qml` + `Stats.qml` + `TaskManagerPanel.qml` | `/proc/stat`，顶栏 10s、面板 2s |
| `memory` | `modules/Memory.qml` + `Stats.qml` + `TaskManagerPanel.qml` | `/proc/meminfo`，顶栏 30s、面板 2s |
| `battery` | `modules/Battery.qml` | `Quickshell.Services.UPower` + `/sys/firmware/acpi/platform_profile` |
| `custom/dnd` | `modules/NotificationCenter.qml` | 并入铃铛；Quickshell 通知服务内部标志 |
| `tray` | `modules/Tray.qml` | `Quickshell.Services.SystemTray` |
| （新增）通知 | `NotificationPopup.qml` + `modules/NotificationCenter.qml` | `Quickshell.Services.Notifications` |
| （新增）离开中 | `modules/Away.qml` + `components/StayAwake.qml` | `Quickshell.Wayland.IdleInhibitor` |

## 布局与交互

- 左、中、右三段顺序：
  - 左：workspaces、window
  - 中：clock
  - 右：pulseaudio、network、bluetooth、cpu、memory、battery、notification、away、tray
- 原有交互：
  - 工作区左键切换（`niri msg action focus-workspace`）
  - 音量模块滚轮调整默认输出音量，右键快速静音
  - 托盘左键激活、右键打开 SNI 菜单
- 时钟（左键打开月历面板）：
  - 面板沿用其他弹层的背景、圆角、边框和按钮样式
  - 默认显示当前月份，左右箭头切换月份，`Today` 回到本月；今天用主题色圆形高亮
  - 点击面板外或按 `Esc` 关闭；右键时钟模块切换 `HH:mm` / `yyyy/MM/dd`
- 音量模块（左键打开混音器）：
  - 顶部控制默认输出：音量滑条、静音、在有多个输出设备时直接切换设备
  - `Applications` 列出当前正在播放声音的应用流，每个应用可以单独调音量或静音
  - 底部控制默认麦克风：音量滑条、静音、在有多个输入设备时切换设备
  - 应用流的音量与静音直接写到 PipeWire 节点，不依赖 `pactl`/`wpctl` 子进程
- 网络模块（左键打开面板）：
  - Wi-Fi 总开关和手动重新扫描
  - 点击网络连接/断开；已保存的网络直接连接
  - 新加密网络点击后展开密码输入框，点 `Connect` 提交
  - 有线设备也会显示在面板里，可连接/断开
- 蓝牙模块（左键打开面板）：
  - 面板内开关适配器、开始/停止扫描
  - 点击设备连接/断开；未配对的设备会先配对再连接
  - 右键模块快速开关蓝牙适配器
- CPU / 内存模块（左键打开任务管理器）：
  - 两个图标打开同一个面板；点击另一个图标只移动面板位置，不会关闭；再次点击同一个图标则关闭
  - 面板每 2 秒用 `Quickshell.Io.Process` 读取 `/proc/stat`、`/proc/meminfo` 和每个进程的 `/proc/<pid>/stat`，不再启动 `wezterm -e htop`
  - 顶部显示整体 CPU、核心数、内存与 swap；进程列表显示名称、PID、CPU 和 RSS，可按 CPU / Memory / Name 排序
  - 进程 CPU 是两次采样之间的 jiffies 差值，按单核百分比显示，和 htop 一样可以超过 100%
  - 行内 `End` 按钮第一次点击变成 `Confirm`，3 秒内再点发送 SIGTERM；PID 1 不可结束
  - 点击面板外或按 `Esc` 关闭；关闭后停止进程采样，顶栏的 CPU/内存模块继续按原间隔刷新
- 电池模块（ROG 联动）：
  - 左侧图标实时显示 asusd 当前电源模式：月亮 = Quiet、天平 = Balanced、仪表 = Performance
  - 左键打开 ROG Control Center：窗口已存在时通过 `niri msg action focus-window` 前置，没有窗口时再启动 `rog-control-center`
  - 右键执行 `asusctl profile next`，按 asusd 的顺序切换电源模式
  - 模式图标直接监听 `/sys/firmware/acpi/platform_profile`，所以在 ROG Control Center 里改模式也会立即反映到顶栏
- 通知：
  - 新通知从屏幕右上角弹出，顶栏下方 `8px`，最多同时显示 3 条，新的在上
  - 默认 6 秒后自动消失，鼠标悬停时暂停计时；应用指定 `expire_timeout` 时按其值（最多 10 秒）
  - `critical` 紧急通知不自动消失，也不受免打扰影响
  - 点击 toast 会执行通知的 `default` 动作并关闭；卡片上的按钮对应其余动作
  - 铃铛模块显示历史总数，有新通知未读时变成橙色；左键打开通知中心，右键切换免打扰
  - 免打扰开启时铃铛变红并换成带斜杠的铃铛，通知中心面板里也有 `DND on/off` 按钮
  - 通知中心按时间倒序列出全部通知，可滚动，支持逐条关闭、执行动作、一键清空
  - 免打扰只抑制 toast，通知仍会进入历史并计数
- 离开中开关（铃铛右侧）：
  - 只显示一个咖啡杯图标，不占用文字宽度
  - 未开启时是普通灰色底，开启后背景变成亮黄色 `#ffd54f`
  - 开启期间为每块屏幕创建一个 `1x1` 透明 overlay layer-shell surface，并在它上面持有 `IdleInhibitor`；`swayidle`、niri 的自动关屏/锁屏都不会触发
  - 使用 overlay 而不是顶栏所在 top 层，因为 niri 的全屏窗口会盖住 top 层，而被遮挡的 surface 不会让 inhibitor 生效
  - 再点一次关闭，释放 inhibitor，恢复正常的空闲计时
  - 状态在 `StayAwake` 单例里共享，多屏时每块屏幕都会各自创建一个 inhibitor surface
  - 开关使用 `PersistentProperties` 保存，配置热重载（包括修改 `Away.qml`/`Bar.qml`）后仍保持开启，不会因为编辑 QML 而悄悄失效
- 电池模块没有自定义 tooltip、弹出面板或媒体控制；只有上述点击/右键动作和电源模式图标联动。CPU/内存模块共用任务管理器面板，不再需要额外的 htop 窗口。
- Spotlight（`Alt+Space`，niri bind 执行 `qs -c niri ipc call spotlight toggle`）：
  - 屏幕中央偏上的浮层，带半透明遮罩；打开时用 `WlrKeyboardFocus.Exclusive` 独占键盘，`Esc`、再次按 `Alt+Space` 或点击遮罩关闭
  - 输入即时过滤 `DesktopEntries` 里的应用，匹配名称、GenericName、Keywords、Categories、Comment 和 desktop id；支持子序列模糊匹配，空格分隔多个关键词
  - `↑`/`↓`、`PageUp`/`PageDown`、`Ctrl+N`/`Ctrl+P`、`Tab`/`Shift+Tab` 移动选中项，`Enter` 启动；鼠标点击条目也可启动
  - 空查询按启动次数排序；启动次数保存在 `Quickshell.statePath("spotlight-usage.json")`，常用的应用会自动排到前面
  - 启动走 `DesktopEntry.execute()`；图标用 `Quickshell.iconPath` 解析，绝对路径图标按 `file://` 处理
  - 多屏时在 niri 焦点窗口所在的输出打开；没有焦点窗口时回退到第一块屏幕
  - 原来的 `Mod+Space` 仍然保留为 rofi 的启动入口，两者互不影响

## 视觉复刻的关键点

这些值是通过测量正在运行的 Waybar 的实际控件尺寸得到的，不是猜的：

- 整栏高度 `44px`，底部 `3px` 边框 `#56a0d1`。
- 模块高度 `41px`、圆角 `10px`、左右 padding `10px`。
- 字体：`IosevkaTerm Nerd Font`，实际解析为 11pt；Quickshell 里用 `pixelSize: 14` 得到同样的 7px 半宽步进。
- 工作区按钮宽 `41px`、与模块同高且无额外 margin：活跃工作区用主题色 `#56a0d1` 高亮，非活跃工作区背景为 `#dae2e9`；至少显示三个，依次为终端、浏览器、QQ，其余工作区按钮内不显示图标。
- `niri/window` 的 `max-length: 50` 对应内容区最大 `367px`，超出用 `…` 截断。
- 右侧模块之间没有间距，和 `style.css` 里移除 margin 的提交一致。
- Nerd Font 的部分图标在 Qt 下会按一个全角宽度排版，而 Pango 按半角。`Glyph.qml` 用一个半宽 Item 承载全尺寸字形，避免 CPU/内存/电池/通知的模块被撑宽。
- 补充平面字符（如 `󰤢`、`󰂚`）在 QML 里必须写成 UTF-16 代理对，不能写成 `\uf0922`（JS 的 `\u` 只接收 4 位十六进制）。
- `shell.qml` 顶部的 `//@ pragma IconTheme Adwaita` 让托盘图标和 Waybar/GTK 使用同一套图标主题。
- `shell.qml` 顶部的 `//@ pragma UseQApplication` 是托盘右键菜单生效的必要条件：Quickshell 的 `QsMenuAnchor` 通过 Qt 平台菜单显示托盘菜单，在默认的 `QGuiApplication` 模式下调用 `open()` 会直接报错并返回。修改该 pragma 后需要完整重启 Quickshell（自动重载不会切换应用类型）。

## 数据流

```text
niri event-stream ──> Niri.qml ──> Bar.qml ──> Workspaces / ActiveWindow
/proc/stat ────────> Stats.qml ──> Bar.qml ──> Cpu
/proc/meminfo ─────> Stats.qml ──> Bar.qml ──> Memory
/proc/stat + /proc/meminfo + /proc/<pid>/stat ──> Tasks.qml ──> TaskManagerPanel.qml
Pipewire ──────────> Audio.qml（默认输出/麦克风/应用流）
NetworkManager ────> Network.qml <── /proc/net/dev（5s 一次带宽）
BlueZ ─────────────> Bluetooth.qml
UPower ────────────> Battery.qml
/sys/firmware/acpi/platform_profile ──> Battery.qml（电源模式图标）
Battery.qml ──> niri focus-window / rog-control-center（左键）
Battery.qml ──> asusctl profile next（右键）
StatusNotifier ────> Tray.qml
DesktopEntries ────> Spotlight.qml（模糊匹配 + 启动频率）
Away.qml ──> StayAwake.qml（全局状态）──> IdleInhibitor（每块屏幕的 1x1 overlay surface）
D-Bus Notifications ──> Notifications.qml ──┬─> NotificationPopup.qml（toast）
                                             └─> NotificationCenter.qml（历史）
```

`Niri.qml` 直接监听 `niri msg --json event-stream`。该流启动时会先发送 `WorkspacesChanged` 和 `WindowsChanged`，因此不需要额外轮询 niri。

## 已知边界

- 音频混音器只列出正在播放的应用流（`Stream/Output/Audio`），不显示录音流；麦克风控制针对默认输入设备（`Pipewire.defaultAudioSource`）。切换输出/输入设备通过 `preferredDefaultAudioSink` / `preferredDefaultAudioSource` 完成，交给 WirePlumber 持久化。
- 应用流按 PipeWire 节点 id 排序，避免媒体标题变化时列表重新排序；如果同一应用开了多个播放流，会显示为多行。
- 网络/蓝牙/音频/通知中心/时钟月历/任务管理器弹层用独立的 layer-shell `PanelWindow` 绘制在顶栏下方。顶栏本身是 layer-shell surface，Qt 无法在它上面挂载带 grab 的 `xdg_popup`；独立覆盖层也能让 Wi-Fi 密码框正常取得键盘焦点。弹层打开时会占据屏幕下方区域的输入，点击弹层外或按 `Esc` 关闭。这些弹层使用 `exclusiveZone: -1`，这样 `margins.top` 相对屏幕边缘而不是顶栏预留的区域，否则会多出 `44px` 的空隙。
- `NotificationServer` 只能注册一次 `org.freedesktop.Notifications`。mako/dunst 必须先停掉，否则新通知会继续进入旧的守护进程；niri 配置已注释掉 mako，并 mask 了 `mako.service` 以防 D-Bus 激活抢名字。
- 通知历史保存在内存里，`qs` 完全退出后清空；配置重载时服务端会重新发出上一代通知，代码用 `lastGeneration` 忽略它们，避免重复弹 toast。免打扰状态同样不持久化。
- toast 队列最多 3 条，避免批量通知遮住屏幕；历史最多保留 100 条，超出时自动关闭最旧的。
- 通知正文按纯文本渲染，不广告也不解析 markup/hyperlink；`image-path` 往往只是应用图标，因此只当小图标用，不画大图预览。暂不支持 inline reply。
- 多屏情况下每个屏幕都会弹同一份 toast（`NotificationPopup` 在 `Variants` 里每屏一个）。当前只有 eDP-1，未做“只在焦点屏幕弹出”的处理。
- 蓝牙列表会过滤掉名字就是 MAC 地址的 BLE 广播，避免几十个匿名设备把列表淹没；已配对/已连接设备始终显示。
- 蓝牙配对依赖 BlueZ 的 agent。需要额外确认码或按键的设备可能配对失败，面板会显示提示；已配对设备可直接连接/断开。
- Wi-Fi 新网络的密码通过 `WifiNetwork.connectWithPsk()` 直接交给 NetworkManager；已保存但密码失效的网络连接失败后会重新弹出密码框。
- 托盘图标的排列顺序由 StatusNotifier 注册顺序决定，可能与 Waybar 略有不同；图标数量、尺寸和模块总宽度一致。
- 时钟月历不再使用 Waybar 的 GTK tooltip 或 Quickshell 的 `PopupWindow`，而是和其他弹层一样用 `PanelWindow`；今天是主题色圆底，而不是 Waybar 的下划线。
- 月历只显示当前月份的日期，不显示相邻月份，也不支持点击日期新建日程。
- 网络带宽每 5 秒采样一次，与配置里的 `interval: 5` 一致；刚启动或刚重载后的第一次采样显示 `0.0b/s`。
- 任务管理器只在面板打开时启动 2 秒采样；顶栏的 CPU/内存仍分别沿用 `Stats.qml` 的 10 秒/30 秒间隔。第一次采样只建立 CPU jiffies 基线，面板会在约 250ms 后补一次采样，所以进程 CPU 百分比会比进程列表晚一点出现。
- 进程 CPU 以两次 `/proc/stat` 总 jiffies 的差值为分母，再按核心数换算成 htop 风格的单核百分比；进程 RSS 来自 `/proc/<pid>/stat` 的页数，共享内存会被重复计算，所以进程内存之和可能大于系统已用内存。
- `End` 只发送 SIGTERM，权限不足或进程已退出时不会在面板里显示错误；需要 SIGKILL 时仍需使用终端。PID 1 的结束按钮被禁用。
- 电池模块的电源模式图标依赖 ASUS 的 `/sys/firmware/acpi/platform_profile`；文件不存在时左侧图标留空，电量显示不受影响。右键切换依赖 `asusd`/`asusctl`，左键打开依赖 `rog-control-center`，这些动作在非 ROG 机器上不会生效。
- “离开中”状态用 `PersistentProperties` 跨配置热重载保留；`qs` 完全重启或重新登录后会回到关闭状态。`IdleInhibitor` 依赖合成器的 idle-inhibit 支持（niri 支持）；它只阻止空闲导致的关屏/锁屏，不会阻止显式挂起或合盖休眠。inhibitor 挂在一个 1x1 透明 overlay surface 上，而不是顶栏上，所以即使全屏窗口遮住了顶栏也仍然有效。
- Spotlight 只搜索 `DesktopEntries` 里的 `.desktop` 应用，不搜索文件、窗口，也不执行 shell 命令或计算表达式；`NoDisplay=true` 的辅助入口（URL handler、portal 等）会被过滤。查询只做大小写/重音归一化和子序列匹配，没有拼音或拼写纠错。
- Spotlight 的启动次数写在 `~/.local/state/quickshell/by-shell/<shell-id>/spotlight-usage.json`，shell id 由配置路径决定；移动或改名配置目录后历史会丢失，删掉该文件即可重置排序。
- `Alt+Space` 由 niri 的 bind 触发（`spawn "qs" "-c" "niri" "ipc" "call" "spotlight" "toggle"`）。Quickshell 没运行时按快捷键不会有反应；`qs ipc` 需要通过 `-c niri` 选择这个配置实例。
- Spotlight 打开时会占据整个屏幕的输入层，打开期间其他应用的鼠标点击不会穿透；关闭后 niri 会把键盘焦点还给原来的窗口。
