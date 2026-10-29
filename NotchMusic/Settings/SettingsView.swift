import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var musicMonitor: MusicMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "music.note")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(
                        LinearGradient(
                            colors: [
                                Color(red: 1.0, green: 0.38, blue: 0.30),
                                Color(red: 0.92, green: 0.22, blue: 0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("NotchMusic")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("在刘海里显示 Apple Music 当前播放的歌曲")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Apple Music")
                    .font(.system(size: 13, weight: .semibold))

                Text(statusText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    if musicMonitor.isConnected {
                        Button("断开连接") {
                            musicMonitor.disconnect()
                        }
                        Button("打开 Apple Music") {
                            musicMonitor.openAppleMusic()
                        }
                    } else {
                        Button("连接 Apple Music") {
                            musicMonitor.connect()
                        }
                    }

                    if musicMonitor.needsPermission {
                        Button("打开自动化设置") {
                            musicMonitor.openAutomationSettings()
                        }
                    }
                }
            }

            Divider()

            Text("NotchMusic 通过 AppleScript 读取曲目并发送播放控制，不上传歌曲、封面或播放记录。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Text("版本 \(versionString)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Text("macOS 14+")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 460, height: 330)
        .onAppear {
            musicMonitor.refreshNow()
        }
    }

    private var statusText: String {
        if !musicMonitor.isConnected {
            return "尚未连接。连接后需要允许 NotchMusic 控制 Apple Music。"
        }
        if musicMonitor.needsPermission {
            return "需要自动化权限。请在系统设置中允许 NotchMusic 控制 Apple Music。"
        }
        if !musicMonitor.isMusicRunning {
            return "Apple Music 当前未运行。"
        }
        if let snapshot = musicMonitor.snapshot {
            return "正在显示：\(snapshot.title)"
        }
        return "已连接，等待 Apple Music 播放歌曲。"
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.2.0"
    }
}
