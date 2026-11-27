# Hill 优化清单

> 来源：2026-11-26 项目审查。
> 用法：完成一项后，把 `- [ ]` 改成 `- [x]`，建议在标题末尾补上完成日期。
> 查看剩余项：搜索 `- [ ]`。
> 优先级：P0 直接影响耗电或流畅度，优先做；P1 明显问题；P2 打磨或长期维护。
> 原则：所有优化不得改变现有使用体验与功能，只减少不必要的开销。
> 行号为审查时的位置；代码变动后以文件和函数名为准。
> 无需处理的项同样勾选，并在标题注明关闭原因。

## 验证基线

- Debug 构建通过：
  ```bash
  xcodebuild \
    -project Hill.xcodeproj \
    -scheme Hill \
    -configuration Debug \
    -derivedDataPath .build \
    CODE_SIGNING_ALLOWED=NO \
    build
  ```
- 性能结论来自静态代码审查，尚未跑 Instruments。修改后建议对比空闲与播放 10 分钟的 CPU、能耗，并用 Animation Hitches 检查掉帧。
- 当前 `MACOSX_DEPLOYMENT_TARGET = 26.0`；README 中的 macOS 14 已过时，见“功能与正确性”第 4 项。

## 性能与耗电

- [x] **P0｜播放时整棵 `NotchView` 以 30Hz 重算**（2026-11-26）
  - 位置：`Hill/Music/AudioSpectrumMonitor.swift:166`、`Hill/Notch/NotchView.swift:265`
  - 问题：频谱 `levels` 每 33ms 发布一次，根视图直接读取，导致 2,689 行的视图树和派生字符串、数组反复计算。
  - 建议：把频谱移进独立的 Canvas 或均衡器子视图，`NotchView` 只观察 `isPlaying`；不可见时不发布。
  - 收益：播放时 CPU 和电量明显下降，优先级最高。
  - 完成：`NotchView` 不再观察 `AudioSpectrumMonitor`，仅由 `SpectrumBackground` 和 `CompactPlaybackIndicator` 在各自 `TimelineView` 内读取实时 `levels`。Debug 构建通过；采集暂停仍跟随播放状态，按 UI 可见性暂停未包含在本次。

- [x] **P0｜鼠标穿透检测永久 30Hz 轮询**（2026-11-26）
  - 位置：`Hill/Notch/NotchPanelController.swift:233`
  - 问题：启动后每 33ms 唤醒主线程检查鼠标位置，锁屏后仍继续循环。
  - 建议：改用 `NSTrackingArea` 或全局 mouseMoved 事件；至少降到 10–15Hz，锁屏或面板失效时暂停。
  - 收益：减少常驻后台唤醒。
  - 完成：改用全局与本地鼠标移动/拖动/点击事件驱动，`visibleSize` 变化时同步刷新命中区域；锁屏移除监听，解锁后恢复。Debug 构建通过，运行时验证悬停可展开、移出后恢复穿透，空闲时不再有 33ms 轮询。

- [x] **P0｜17 处 30/60fps 动画帧率过高**（2026-11-26 关闭：保持原帧率）
  - 位置：`Hill/Notch/NotchView.swift:2197`、`Hill/Notch/HillCompactViews.swift:75`、`Hill/Notch/HillBackgrounds.swift`、`Hill/Notch/MusicLyricsView.swift:261`
  - 问题：进度条和时间文字 30fps；收起均衡器 30fps；7 个背景特效 30fps；歌词 60fps。
  - 建议：进度和时间文字降到 1Hz；均衡器 10–15fps；背景 20–24fps；歌词 30fps；收起、锁屏、非激活、Reduce Motion 时暂停。
  - 收益：直接降低 GPU、CPU、发热和耗电。
  - 尝试记录：2026-11-26 降低帧率后观感不佳，已恢复原帧率。后续只从“不可见时暂停”与 Reduce Motion 方向优化，不再牺牲动画流畅度。
  - 进度（2026-11-26）：锁屏暂停已覆盖频谱与全部背景特效；7 种背景均已响应 Reduce Motion 暂停；其余均为可见动画，按用户要求保留原帧率，不再降帧。
  - 关闭说明：可安全实现的锁屏暂停与 Reduce Motion 暂停已完成；继续降低可见动画帧率会影响观感，按用户要求保留原帧率，不再修改。

- [x] **P0｜系统检测每 700ms 做磁盘 I/O 与设备枚举**（2026-11-26）
  - 位置：`Hill/System/SystemActivityMonitor.swift:120`、`:170`
  - 问题：每 700ms 读取一次 `Assertions.json`，并枚举 CoreAudio 进程和 CMIO 设备。
  - 建议：专注模式只依赖 DND 通知；麦克风用 CoreAudio 监听；摄像头和指示灯改为 2–5s 轮询，锁屏暂停。
  - 收益：显著减少空闲功耗。
  - 完成：专注模式改为仅由 DND 通知与设置变化刷新，不再周期读取 `Assertions.json`；Caps Lock 使用独立的 200ms 轻量检测；其余检测从 700ms 降到 1s，并在锁屏时停止、解锁后立即恢复。锁屏期间保留 1s 的会话状态兜底检测，避免解锁通知丢失或竞态导致界面卡在锁屏；调试器模拟锁屏验证约 1s 自动恢复。Debug 构建通过，采样确认专注文件读取为 0 次。

- [x] **P1｜HUD 被动轮询 5.5Hz**（2026-11-26）
  - 位置：`Hill/System/SystemHUDController.swift:819`
  - 问题：没有辅助功能权限时，每 180ms 查询音量、亮度和键盘背光。
  - 建议：音量继续使用已有 CoreAudio listener；亮度降到 1–2s；锁屏停止轮询。
  - 收益：减少常驻 CPU。
  - 完成：音量不再参与轮询，改由 CoreAudio listener 事件驱动；仅启用亮度/键盘背光时才启动 180ms 轮询，保持即时响应；锁屏停止，解锁后恢复。Debug 构建通过，运行验证亮度 HUD 约 250ms 内出现、音量 HUD 约 400ms 内出现，无崩溃。

- [x] **P1｜App 音量每 1.5s 全量扫描**（2026-11-26）
  - 位置：`Hill/System/AppVolumeMixer.swift:88`
  - 问题：启动后每 1.5s 枚举音频进程和运行中 App，即使用户从不打开音量页。
  - 建议：只在音量页可见或首次使用 App 音量时启动；或改用 ProcessObjectList 变化通知。
  - 收益：降低空闲开销。
  - 完成：启动时仅在有已保存的非默认 App 音量、静音或输出设备覆盖时启动扫描；首次打开 App 音量页或锁屏播放卡片时启动并立即刷新，之后保持原 1.5s 频率。已验证无覆盖时启动后 `isRunning=false`、3 秒采样无 `AppVolumeMixer` 扫描；打开音量页后 `isRunning=true`，读取到 9 个 App 和 3 个输出设备；真实 Chrome 44.55% 设置仍正常生效。Debug 构建通过。

- [x] **P1｜UserDefaults 通知风暴**（2026-11-26）
  - 位置：`Hill/App/AppDelegate.swift:349`、`Hill/System/SystemActivityMonitor.swift:310` 等 9 处观察者
  - 问题：任意设置写入都会重建状态栏图标、应用图标、触发系统扫描和 HUD 重配置；音量滑杆的 300ms 防抖持久化也会触发。
  - 建议：用统一的设置 Store 做按键订阅，或只观察具体 key；图标重建加去抖。
  - 收益：拖动滑杆和修改设置时不再卡顿。
  - 完成：新增 `Hill/System/DefaultsKeyObserver.swift`，按具体 key 快照对比后才回调；9 处全局 `UserDefaults.didChangeNotification` 监听改为按组件订阅各自关心的 key。无关设置写入不再触发图标重建、系统扫描、HUD 重配置和锁屏卡片重算。Debug 构建通过；运行时验证：写入无关 key 不触发 `SystemActivityMonitor.refreshNow`，写入摄像头开关 key 正常触发，`alwaysExpanded` 切换面板展开状态正常。

- [x] **P1｜每 2s 重建 AppleScript 与 `NSImage`**（2026-11-26）
  - 位置：`Hill/Music/AppleMusicClient.swift:258`、`Hill/Music/MusicMonitor.swift:237`
  - 问题：每次轮询都新建 `NSAppleScript`；即使封面未变也重新创建 `NSImage`；元数据未变也会发布新 snapshot。
  - 建议：缓存编译后的脚本；按 trackID 缓存 `NSImage`；仅在元数据变化时发布，播放位置交给 TimelineView 推算。
  - 收益：降低 CPU 和内存抖动。
  - 完成：只读脚本（元数据、切歌元数据、封面）按源码缓存 `NSAppleScript` 复用，命令脚本保持原样；`MusicMonitor` 用 `NSCache` 按 trackID 复用解码后的封面；snapshot 字段完全一致时跳过发布。为保持外部拖动进度条能在 2s 内同步，播放中仍按原频率更新位置锚点，未改成纯 TimelineView 推算。运行时验证：启动后 2 个只读脚本各编译 1 次，其后 11 秒轮询 0 次重编译；同一封面只解码 1 次，切歌后新封面也只解码 1 次；暂停时每 2s 命中 `skip-identical`，播放和切歌后标题、进度正常更新。Debug 构建通过。

- [x] **P1｜歌词布局反复测量**（2026-11-26）
  - 位置：`Hill/Notch/MusicLyricsView.swift:244`
  - 问题：在 body 中重建 `LyricsScrollLayout`，对整个歌词逐行执行 NSLayoutManager 测量，每次 snapshot 更新都会重算。
  - 建议：按 trackID、宽度、字号缓存布局，或移到 `LyricsController` 一次算好。
  - 收益：打开歌词页更稳定。
  - 完成：新增文件内 `LyricsLayoutCache`，按 trackID、文本宽度、行高、字号缓存 `LyricsScrollLayout`，并保存歌词快照用于 `SyncedLyrics` 相等性校验，歌词内容变化时自动重建；最多保留 6 份。运行时用 71 行歌词验证：首次布局 19ms，之后每次 body 重算均命中缓存、不再逐行测量；锁屏播放卡歌词显示、高亮行渐变遮罩和滚动位置正常。Debug 构建通过。

- [x] **P2｜锁屏时双 UI 与频谱继续运行**（2026-11-26）
  - 位置：`Hill/Notch/LockScreenPlaybackController.swift`、`Hill/Music/AudioSpectrumMonitor.swift`
  - 问题：锁屏时刘海面板和播放卡片同时存在；频谱采集和 FFT 在锁屏后仍继续；多层 blur、mask、blendMode、compositingGroup 叠加。
  - 建议：锁屏时暂停刘海面板更新和频谱；用 Metal System Trace 检查离屏合成，减少静态层。
  - 收益：锁屏功耗和 GPU 占用下降。
  - 完成：频谱的播放状态改为与锁屏状态合并，锁屏时停止音频 tap、FFT 和 30Hz 电平发布，解锁后约 0.4s 自动恢复；`NotchBackdrop` 将锁屏状态传入全部 7 种刘海背景，锁屏时暂停 30fps 的 `TimelineView` 并保留当前帧，解锁立即恢复。用文件模拟锁屏验证：锁屏后频谱输出 `waitingForPlayback`，极光背景只渲染初始帧便停止；解锁后频谱重新启动、极光恢复 30fps。未执行 Metal System Trace 和静态层合并，留作后续。

## 功能与正确性

- [x] **P1｜App 音量权限提示可能永远不显示**（2026-11-26）
  - 位置：`Hill/System/AppVolumeMixer.swift:278`
  - 问题：`ensureEngine` 失败时设置 `tapFailed = true`，同一次 `refresh` 末尾又因为 `engines.isEmpty` 重置为 `false`。
  - 建议：存在失败的必需引擎时不要清零；改为记录 `lastEngineError`，或按 App 展示权限状态。
  - 收益：用户能知道为什么调音量没反应。
  - 完成：新增 `failedEngineIDs` 记录失败 App，`tapFailed` 统一由失败集合推导；删除 `engines.isEmpty` 的强制清零，单个 App 初始化成功也不再覆盖其他 App 的失败；App 退出或不再需要混音时自动清理失败记录，且只在状态变化时发布。验证：强制引擎失败时 `engines=0`、`tapFailed=1` 连续 7 次刷新（约 9 秒）保持，正常权限下 `engines=1`、`tapFailed=0`。Debug 构建通过，临时验证钩子已移除。

- [x] **P1｜引导页首次启动后无法重新打开**（2026-11-26）
  - 位置：`Hill/App/AppDelegate.swift:292`、`:316`
  - 问题：`showOnboarding()` 只在首次启动时调用，菜单栏只有设置、检查更新和退出；CHANGELOG 声称可从菜单栏重开。
  - 建议：菜单栏增加“欢迎页 / 权限检查”，或在设置-授权页加入口。
  - 收益：权限失效时可以自助恢复。
  - 完成：采用“设置-授权页”方案，未新增菜单栏项。设置侧边栏新增「授权」分类，复用引导页的 `OnboardingModel` 与权限卡片，实时展示辅助功能、音乐控制、日历状态并提供授权/系统设置入口，每 1s 刷新一次且仅在页面可见时运行。运行验证：页面显示 2/3 已授权，辅助功能未授权、音乐控制与日历已授权，按钮与频谱说明正常。同步把 CHANGELOG 中“可从菜单栏重新打开”改为“可在「设置 → 授权」中重新检查权限”。

- [x] **P1｜拖动时可能自动收起面板**（2026-11-26）
  - 位置：`Hill/Notch/NotchPanelState.swift:112`
  - 问题：`scheduleCollapse` 只检查 pinned 和 hovering，不检查鼠标按键；拖动进度或音量出刘海边缘时可能启动 160ms 后收起。
  - 建议：收起前检查 `NSEvent.pressedMouseButtons` 或编辑状态；菜单、弹窗打开期间暂停收起。
  - 收益：拖动操作不被打断。
  - 完成：收起计时器到点后先检查 `NSEvent.pressedMouseButtons`，有按键按住时每 100ms 等待，全部释放且仍未悬停才收起；悬停或固定展开时仍会取消计时器，原有逻辑不变。运行验证：从刘海面板内按下并拖到面板外保持 0.9s，面板保持展开；松开后 0.5s 内正常收起。Debug 构建通过，测试鼠标位置已还原。

- [x] **P1｜统一版本与平台说明**（2026-11-26）
  - 位置：`README.md:12`、`README.md:135`、`Hill/Settings/SettingsView.swift:2900`、`website/index.html:42`、`website/index.html:477`
  - 问题：README 写 macOS 14、版本 0.2.0；关于页写 macOS 14+；实际 target 是 26.0；官网下载链接仍指向 0.5.1。
  - 建议：版本统一从 Bundle 读取；README、关于页、官网、appcast 一次对齐；`LyricsProvider` 的 User-Agent 也改为读取版本。
  - 收益：发布信息一致、可信。
  - 完成：README 最低系统改为 macOS 26，删除“实时频谱需要 macOS 14.2+”的限制项，实现说明改为“Core Audio Process Tap（macOS 14.2 起提供）”；关于页不再硬编码系统版本，改为读取 `LSMinimumSystemVersion`，版本号从 Bundle 读取；`LyricsProvider` 的 User-Agent 改为从 `CFBundleShortVersionString` 生成；README、官网、appcast 的版本与下载链接统一到 `0.6.0`。Debug 构建通过，产物 Info.plist 为 `0.6.0` / `26.0`。

- [x] **P1｜歌词请求的隐私披露**（2026-11-26）
  - 位置：`Hill/Music/LyricsProvider.swift:190`、`Hill/Settings/SettingsView.swift:2882`
  - 问题：歌词请求会把歌名、歌手、专辑、时长发到 lrclib.net，但关于页写“不上传歌曲、封面或播放记录”。
  - 建议：明确说明会请求第三方歌词服务；增加开关；歌词结果落盘缓存并设置 TTL。
  - 收益：隐私说明准确，同时减少重复网络请求。
  - 完成：关于页与 README 明确披露歌词请求只发送歌名、歌手、专辑与时长，不含音频、封面或播放记录；新增 `Hill/Music/LyricsCache.swift`，歌词结果按 trackID 落盘缓存 7 天、最多 200 首，命中缓存时不再请求网络；未新增开关，保持现有歌词功能与体验不变。Debug 构建通过；运行时首次启动写入当前曲目歌词缓存，重启后命中缓存且缓存文件未被重写，离线缓存命中测试通过。

- [x] **P2｜多显示器锁屏卡片位置**（2026-11-26）
  - 位置：`Hill/Notch/LockScreenPlaybackController.swift:233`
  - 问题：使用 `NSScreen.screens.first`，多显示器时可能出现在外接屏而不是刘海屏。
  - 建议：使用 `NotchGeometry.activeScreen()` 或带刘海的屏幕。
  - 收益：多屏下位置正确。
  - 完成：`lockScreenScreen()` 改为 `NotchGeometry.activeScreen() ?? NSScreen.screens.first`，优先当前主屏中的刘海屏，其次任意刘海屏，都没有时才回退到原来的第一块屏幕。本机双屏环境验证：`NSScreen.screens.first` 与 `activeScreen()` 都解析到内建刘海屏，单屏与当前排列下卡片位置不变；Debug 构建通过，应用重启后正常运行。

- [x] **P2｜应用图标设置作用范围不清晰**（2026-11-26）
  - 位置：`Hill/App/AppDelegate.swift:373`
  - 问题：accessory 应用没有 Dock、Finder 图标，运行时只设置 `NSApp.applicationIconImage`，实际基本只影响关于页。
  - 建议：改名为“关于页图标”，或真正修改 bundle 图标，或移除 5 套应用图标选项。
  - 收益：避免“设置了没变化”。
  - 完成：按“真正修改 Bundle 图标”方案实现。`applyApplicationIcon()` 除更新 `NSApp.applicationIconImage` 外，通过 `NSWorkspace.setIcon` 把所选图标写入 `.app`（`Icon\r` + FinderInfo 自定义图标标记）；选择“海洋蓝”时传 `nil` 恢复内置图标。设置页文案改为运行中图标与访达文件图标同步更新，并注明需要应用位于可写位置。运行时验证：临时切到“紫罗兰”后 `Icon\r` 与 `kHasCustomIcon` 标记出现，复制应用包读取图标确认已变为紫罗兰；恢复“海洋蓝”后自定义图标被移除。Debug 构建通过，应用修改图标后重启正常。

- [x] **P2｜AirPods 连接提示有延迟**（2026-11-26）
  - 位置：`Hill/System/DeviceConnectionMonitor.swift` 的 `presentConnectedAirPods`
  - 问题：先等 `/usr/sbin/system_profiler` 返回才显示提示，通常需要 1–3 秒。
  - 建议：先用设备名和模型立即显示，再异步补电量；或改用 IOBluetooth、IORegistry。
  - 收益：连接反馈更及时。
  - 完成：默认输出切到 AirPods 后立即按设备名显示连接卡片，电量暂显示 `--`；`system_profiler` 继续在后台异步查询，返回后仅在默认输出仍是该设备且卡片仍可见时补全电量与更精确的机型。5 秒隐藏计时只在卡片首次出现时启动，异步补全不重置计时，因此展示总时长与原来一致。Debug 构建、`git diff --check` 通过；非 AirPods 输出启动或切换不会触发连接卡片。真实连接时请确认卡片立即出现、电量随后补齐、约 5 秒后消失。

- [x] **P2｜天气依赖“天气”日历**（2026-11-26）
  - 位置：`Hill/Notch/CalendarIslandView.swift` 的 `CalendarWeatherInfo`
  - 问题：只读取名称含“天气”或“weather”的全天事件，设置页没有说明，用户可能永远看不到天气。
  - 建议：增加配置说明；支持手动天气配置；或去掉该功能。
  - 收益：降低困惑。
  - 完成：保持天气读取、日历展示和权限行为不变，在“设置 → 授权”页补充天气来源与事件格式提示，并在 README 的日历面板章节补充完整格式说明。天气仍只读取本机日历，不联网、不定位，未新增开关或手动配置。Debug 构建通过，应用重启后正常运行。

- [x] **P2｜频谱采集默认开启**（2026-11-26 关闭：保持现有体验）
  - 位置：`Hill/Music/AudioSpectrumMonitor.swift:42`
  - 问题：首次播放就会请求系统音频录制权限，部分用户会觉得突兀。
  - 建议：默认关闭，或首次采集前明确询问。
  - 收益：减少权限摩擦。
  - 关闭说明：默认开启属于现有功能和首次播放流程；改为默认关闭或首次采集前询问都会改变当前使用体验。按“只做优化、不改变体验和功能”的要求，本次保留现状，不修改代码。

## UI 与可访问性

- [x] **P1｜设置窗口固定尺寸，字号不可缩放**（2026-11-26 关闭：保持现有尺寸与字号）
  - 位置：`Hill/Settings/SettingsView.swift:316`、`Hill/Notch/CalendarIslandView.swift`
  - 问题：设置窗口固定 520×720 且不可缩放；大量固定字号，日历次要文字只有 7.5–9.5pt。
  - 建议：支持窗口缩放和最小尺寸；适配系统辅助字号；正文至少 11pt，次要信息不低于 10pt。
  - 收益：可读性和无障碍改善。
  - 关闭说明：曾尝试开启窗口缩放并限制为 520×720 至 720×900，按用户要求撤销，保持原有固定尺寸与字号，避免改变现有界面观感。

- [x] **P1｜日历日期滚轮缺少无障碍与键盘支持**（2026-11-26：无障碍完成，方向键按设计保留）
  - 位置：`Hill/Notch/CalendarIslandView.swift:1190`
  - 问题：日期滚轮是自绘 `NSView`，没有 accessibility elements 或 actions，也无法用键盘切换日期。
  - 建议：增加 VoiceOver 子元素和增减动作，支持左右方向键；或改用系统 DatePicker。
  - 收益：VoiceOver 和键盘用户可用。
  - 完成：日期滚轮已作为 VoiceOver 递增器暴露，可读取当前完整日期，并通过“上一天/下一天”动作切换；鼠标点击、滑动和外部日期更新都会发送值变化通知。未改变视觉、拖动、动画和日期加载逻辑。
  - 关闭说明（方向键）：`NotchPanel` 固定 `canBecomeKey = false` 以避免抢前台键盘焦点；加入左右方向键需要让面板临时成为键盘焦点窗口，会改变现有交互。按用户决定不加入，保留当前焦点行为。Debug 构建通过，应用重启后正常运行。

- [x] **P2｜点击区域偏小、部分文字对比度不足**（2026-11-26 关闭：暂不修改）
  - 位置：`Hill/Notch/NotchView.swift:1710`
  - 问题：页面切换 24×20，多个图标按钮 24×24；部分次要文字使用 `white.opacity(0.26)`。
  - 建议：视觉尺寸不变，扩大透明命中区到 32pt；正文对比度至少 4.5:1。
  - 收益：更容易点中、看清。
  - 关闭说明：按用户决定暂不修改点击区域与文字对比度，保持当前视觉和交互。

- [x] **P2｜设置侧栏悬停展开会遮挡内容**（2026-11-26 关闭：保留现有设计）
  - 位置：`Hill/Settings/SettingsViewComponents.swift:64`
  - 问题：侧栏从 52px 展开到 172px，并以 overlay 覆盖设置内容。
  - 建议：改为推挤布局，或使用固定宽度。
  - 收益：不遮挡当前设置项。
  - 关闭说明：用户确认侧栏悬停展开并覆盖内容就是预期效果，不做布局修改。

- [x] **P2｜全部文案硬编码中文**（2026-11-26 关闭：暂不支持多语言）
  - 位置：`Hill/**/*.swift`
  - 问题：没有 String Catalog，后续国际化需要逐文件替换。
  - 建议：如需国际化，先抽取 String Catalog；如果只面向中文用户，可保持现状。
  - 收益：为本地化做准备。
  - 关闭说明：项目当前只面向中文用户，暂不支持多语言；不抽取 String Catalog，保持现有实现。

## 简化与维护

- [x] **P1｜删除 macOS 26 下不可达的兼容分支**（2026-11-26）
  - 位置：`Hill/Music/AudioSpectrumMonitor.swift:46`、`Hill/System/AppVolumeMixer.swift:208`
  - 问题：target 已是 macOS 26，但仍有大量 `#available(macOS 14.2, *)` 和 `@available` 分支，`MusicSpectrumStatus.unsupported` 等状态不可达。
  - 建议：删除旧系统兼容分支和不可达状态；如果确实要支持 macOS 14，则同步降低 target 并保留分支。
  - 收益：代码更少，心智负担更低。
  - 完成：删除 `MusicSpectrumStatus.unsupported` 及设置页对应配色分支、`isSupported` 判断；移除频谱与 App 音量中全部 `#available(macOS 14.2, *)` / `@available(macOS 14.2, *)` 分支；麦克风检测固定使用进程级检测，并删除不再使用的设备级回退实现。所有被删分支在 26.0 目标下原本就不会执行，运行路径与界面不变。Debug 构建通过，`rg "14.2"` 在 `Hill/` 下已无匹配，应用重启后正常运行。`SettingsViewStyles` 中 2 处 `#available(macOS 26.0, *)` 属于玻璃材质回退，不在本次 14.2 兼容分支范围内，未改动。

- [x] **P2｜拆分巨型视图文件**（2026-11-26 关闭：其余部分暂不修改）
  - 位置：`Hill/Notch/NotchView.swift`、`Hill/Settings/SettingsView.swift`、`Hill/Notch/CalendarIslandView.swift`、`Hill/Notch/HillBackgrounds.swift`
  - 问题：四个文件分别为 2,689、3,167、1,656、1,642 行，单个 body 数百行。
  - 建议：按页面或区块拆文件，抽 ViewModel；优先拆 `NotchView` 和 `SettingsView`。
  - 收益：后续改动更安全。
  - 进度（2026-11-26）：① `CalendarDateWheel`、`CalendarDateStrip`、`CalendarDateScrollView`、`CalendarDateDocumentView` 共 487 行原样拆到 `Hill/Notch/CalendarDateWheel.swift`，`CalendarIslandView.swift` 从 1,656 行降到 1,169 行；② `NotchBackgroundView` 与 7 个背景特效共 1,435 行移到 `Hill/Notch/NotchBackgroundEffects.swift`，`HillBackgrounds.swift` 从 1,658 行降到 222 行。仅调整必要的访问级别并补 import，逻辑未改，Debug 构建通过。`NotchView` 与 `SettingsView` 是单个巨型 struct，拆分需把大量 `private` 成员改为 internal，按最小改动原则暂不继续。
  - 关闭说明：已完成的两次拆分保持有效；剩余 `NotchView` 与 `SettingsView` 的单体拆分需要大量调整访问级别，回归风险高。按用户决定暂不继续，后续修改对应页面的大功能时再顺手拆分。

- [x] **P2｜收敛重复抽象、魔法数和设置键**（2026-11-26 关闭：其余部分暂不修改）
  - 位置：`Hill/Notch/NotchView.swift:255`、`Hill/Notch/CalendarIslandView.swift:5`
  - 问题：`PixelTypography` 和 `CalendarPixelTypography` 只是 `.system` 包装；22+ 处重复动画或帧率常量；约 80 个分散的 `NotchMusic.*` 设置键。
  - 建议：建立设计 token（字号、圆角、动画曲线）和 `SettingsKeys` 枚举；删除无意义包装。
  - 收益：统一视觉，降低改动成本。
  - 进度（2026-11-26）：已删除 `PixelTypography` 与 `CalendarPixelTypography`，4 处调用改为 `.system(size:)`；新增 `Hill/Notch/NotchTiming.swift`，把 6 个文件里重复的 16 处 30fps 间隔统一为 `NotchTiming.thirtyFPS`，数值不变。设置键与其余动画常量待后续。
  - 关闭说明：已完成字体包装删除与 30fps 常量收敛；剩余约 80 个设置键集中化属于大范围机械改动，视觉 token 调整还可能改变观感。按用户决定暂不继续。

- [x] **P2｜补充关键单元测试**（2026-11-26 关闭：暂不修改）
  - 位置：项目目前没有测试 target
  - 问题：25k 行代码包含 LRC 解析、布局计算、设置迁移，但没有自动化测试。
  - 建议：至少覆盖 `LyricsParser`、`MusicControlLayoutSettings` 编解码与迁移、`NotchLayout` 高度计算、`SystemHUDSettings.step`。
  - 收益：防止回归。
  - 关闭说明：按用户决定暂不新增测试 target 与测试代码，保持当前工程结构。

- [x] **P2｜Swift 6 并发迁移**（2026-11-26 关闭：暂不迁移）
  - 位置：`Hill/Music/AppleMusicClient.swift`、`Hill/Music/AudioSpectrumMonitor.swift`
  - 问题：存在多个 `@unchecked Sendable`，Swift 语言模式仍为 5.0。
  - 建议：逐步迁移 Swift 6 严格并发；对实时音频回调单独标注约束。
  - 收益：提升并发安全。
  - 关闭说明：按用户决定暂不迁移 Swift 6；当前无测试覆盖，整体切换并发隔离风险较高，保留 Swift 5 语言模式与现有线程模型。

- [x] **P2｜收敛产品功能面**（2026-11-26 关闭：保留现有功能）
  - 位置：`Hill/Settings/SettingsView.swift`、`Hill/System/MouseScrollController.swift`
  - 问题：功能已超出“刘海音乐”：鼠标平滑、HUD、电池、日历、App 音量、锁屏歌词、8 种背景、5 套图标，设置页有 8 个分类。
  - 建议：做“默认精简 + 高级设置”分层；鼠标平滑可拆成独立工具；删掉无效的应用图标选项。
  - 收益：产品更小、更稳、更容易讲清楚。
  - 关闭说明：按用户决定保留全部现有功能与设置分类，不做功能删减或拆分。

- [x] **P2｜优化官网媒体加载与下载链接**（2026-11-26 关闭：介绍网站后续不再使用）
  - 位置：`website/index.html:310`、`website/index.html:42`
  - 问题：首屏同时自动播放 4 个视频（约 4.3MB），下载链接仍指向 0.5.1。
  - 建议：视频进入视口后再加载，使用 `preload="metadata"`；补充 WebM 或 AV1；链接更新到 0.6.0。
  - 收益：官网首屏更快、下载信息正确。
  - 关闭说明：介绍网站后续停用，不值得继续优化媒体加载；下载链接已在版本统一时更新到 0.6.0。

- [x] **P2｜删除已移除功能的残留内容**（2026-11-26）
  - 位置：`Hill/Settings/SettingsView.swift:2957`
  - 问题：关于页仍保留 Multiavatar 头像署名，但头像功能已在 0.5.0 移除。
  - 建议：删除该链接和署名。
  - 收益：界面和功能保持一致。
  - 完成：删除关于页底部「头像样式由 Multiavatar.com 提供」链接及其上方多余分隔线，GitHub 入口与其余关于页内容保持不变。`rg -ni "multiavatar|avatar"` 在 `Hill/` 与 README 中已无匹配，Debug 构建通过，应用重启正常。

## 推荐处理顺序

1. 频谱隔离，以及收起、锁屏、非激活时暂停动画。
2. 指针轮询事件化；系统检测从 700ms 改为通知驱动。
3. 统一动画帧率：进度文字 1Hz、均衡器 10–15fps、背景 20–24fps、歌词 30fps。
4. 修复 `tapFailed`、引导页入口、拖动自动收起。
5. 统一版本与平台说明，删除 macOS 26 下不可达的兼容分支。
