import SwiftUI
import AppKit

@main
struct RimeIceUpdaterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    init() {
        // When the binary runs as the bundled RimeNotify helper (launched by
        // the engine script with outcome-key arguments), serve that request
        // and exit before any UI exists.
        NotifyCLI.runIfRequested()
    }

    var body: some Scene {
        Window(L("雾凇词库更新器", "rime-ice Dict Updater"), id: "main") {
            MainWindowView()
                .environmentObject(model)
        }
        .defaultSize(width: 840, height: 640)
        .windowResizability(.contentMinSize)
    }
}

// A single-window SwiftUI app quits when its window closes, which fits this
// tool (the schedule runs via launchd without it). Unsaved edits are carried
// across sessions by the draft file instead of a quit dialog — the veto path
// is unreliable once SwiftUI has torn the scene down.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppModel.shared.flushDraft()
        return .terminateNow
    }
}

// MARK: - main window

struct MainWindowView: View {
    @EnvironmentObject var model: AppModel

    private var errorShown: Binding<Bool> {
        Binding(get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } })
    }

    var body: some View {
        TabView {
            StatusTab()
                .tabItem { Label(L("状态", "Status"), systemImage: "gauge") }
            SettingsTab()
                .tabItem { Label(L("设置", "Settings"), systemImage: "gearshape") }
        }
        .alert(L("出错了", "Error"), isPresented: errorShown) {
            Button("OK") {}
        } message: {
            Text(model.errorMessage ?? "")
        }
        .task {
            model.refresh()
            // Skip when the buffer is already loaded so reopening the window
            // never discards unsaved edits.
            if model.scriptText.isEmpty { model.loadScript() }
        }
    }
}

// MARK: - run console (shared by status tab & script editor page)

struct RunConsoleView: View {
    @EnvironmentObject var model: AppModel
    var tall = false

    private var placeholder: String {
        model.running ? L("检查中…", "Checking…") : " "
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(L("运行输出", "Run output"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if model.scriptDirty && (model.running || !model.runOutput.isEmpty) {
                    Text(L("编辑内容尚未安装，本次运行的是已安装版本",
                           "Edits not installed; this run used the installed copy"))
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if !model.runOutput.isEmpty {
                    Button(L("清空", "Clear")) { model.runOutput = "" }
                        .buttonStyle(.link)
                        .controlSize(.small)
                        .disabled(model.running)
                }
            }
            Group {
                if tall {
                    ScrollViewReader { proxy in
                        ScrollView {
                            text
                            Color.clear.frame(height: 0).id("bottom")
                        }
                        .onChange(of: model.runOutput) { _, _ in
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .frame(height: 150)
                } else {
                    ScrollView { text }
                        .frame(height: 90)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.secondary.opacity(0.25)))
        }
    }

    private var text: some View {
        Text(model.runOutput.isEmpty ? placeholder : model.runOutput)
            .font(.system(size: tall ? 10 : 9, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - status tab (default landing page)

struct StatusTab: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section(L("词库更新", "Dict updates")) {
                if model.state.isComplete {
                    LabeledContent(L("当前词库版本", "Installed version")) {
                        Text(model.version.map { StatusReader.prettyVersion($0) }
                             ?? L("未知（尚未成功运行过）", "Unknown (no successful run yet)"))
                            .font(.callout.monospacedDigit())
                    }
                    if let r = model.lastRun {
                        LabeledContent(L("上次运行", "Last run")) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(r.isOK ? Color.green : Color.red)
                                    .frame(width: 8, height: 8)
                                Text("\(r.timeText) · \(r.label)")
                                    .font(.callout)
                            }
                        }
                    }
                    LabeledContent(L("检查频率", "Interval")) {
                        Text(isZh ? "每周" + model.settings.weekdayName
                                  : "Weekly on " + model.settings.weekdayName)
                    }
                    if let next = Launchd.nextRun(model.settings) {
                        LabeledContent(L("下次运行", "Next run")) {
                            Text(next.formatted(date: .numeric, time: .shortened))
                                .font(.callout.monospacedDigit())
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("尚未安装，或计划任务未加载。",
                               "Not installed, or the schedule is not loaded."))
                            .foregroundStyle(.secondary)
                        Button(L("安装并启用自动更新", "Install & enable auto-update")) {
                            model.deploy()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }

            Section(L("环境检测", "Environment")) {
                envRows
            }

            Section(L("手动运行", "Manual run")) {
                HStack {
                    Button {
                        model.checkNow()
                    } label: {
                        HStack(spacing: 6) {
                            if model.running {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(model.running ? L("正在检查…", "Checking…")
                                               : L("立即检查更新", "Check now"))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(model.running || !model.state.scriptInstalled)

                    Button(L("打开日志", "Open log")) { model.revealLogFile() }
                        .controlSize(.small)
                        .disabled(!model.state.hasStateFile && !model.state.scriptInstalled)

                    if model.running {
                        Button(L("停止", "Stop")) { model.stopRun() }
                            .controlSize(.small)
                    }
                }
                if model.running || !model.runOutput.isEmpty {
                    RunConsoleView()
                }
            }
        }
        .formStyle(.grouped)
        .task { model.refresh() }
    }

    @ViewBuilder private var envRows: some View {
        if model.env.isHealthy {
            Label(L("鼠须管环境正常", "Squirrel environment OK"),
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else {
            if !model.env.squirrelInstalled {
                envWarning(L("未检测到鼠须管，更新后无法自动重新部署",
                             "Squirrel not found; auto-redeploy after update is unavailable"))
            }
            switch model.env.rimeDirState {
            case .missing:
                envWarning(L("未找到 Rime 用户目录 ~/Library/Rime，鼠须管可能尚未部署",
                             "Rime user dir ~/Library/Rime not found; Squirrel may not be deployed yet"))
            case .empty:
                envWarning(L("Rime 用户目录存在，但未检测到 Rime 配置文件",
                             "Rime user dir exists but contains no Rime config files"))
            case .ok:
                EmptyView()
            }
        }
        if let real = model.env.rimeDirRealPath {
            LabeledContent(L("用户目录为符号链接", "User dir is a symlink")) {
                Text(real)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
        }
    }

    private func envWarning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
    }
}

// MARK: - settings tab

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel

    @State private var draft = UpdaterSettings()
    @State private var time = Date()
    @State private var savedAt: Date?
    @State private var confirmUninstall = false
    @State private var uninstalledAt: Date?

    private var currentSettings: UpdaterSettings {
        var s = draft
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        s.hour = c.hour ?? 9
        s.minute = c.minute ?? 0
        return s
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(L("计划运行", "Schedule")) {
                    Picker(L("每周几", "Day of week"), selection: $draft.weekday) {
                        ForEach(1...7, id: \.self) { d in
                            Text((isZh ? UpdaterSettings.weekdayNamesZh
                                       : UpdaterSettings.weekdayNamesEn)[d - 1]).tag(d)
                        }
                    }
                    DatePicker(L("时间", "Time"), selection: $time, displayedComponents: .hourAndMinute)
                    if let next = Launchd.nextRun(currentSettings) {
                        Text(L("下次运行：", "Next run: ")
                             + next.formatted(date: .numeric, time: .shortened))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(L("通知", "Notifications")) {
                    Toggle(L("把每次运行结果推送到通知中心", "Post each run's result to Notification Center"),
                           isOn: $draft.notifyEnabled)
                }

                Section(L("代理", "Proxy")) {
                    HStack(spacing: 8) {
                        Text(L("地址", "Host"))
                        TextField("127.0.0.1", text: $draft.proxyHost)
                            .textFieldStyle(.roundedBorder)
                        Text(L("端口", "Port"))
                        TextField("7890", text: $draft.proxyPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 76)
                    }
                    Toggle(isOn: $draft.manageFlClash) {
                        Text(L("代管 FlClash（代理不在时自动启动，运行结束自动关闭）",
                               "Manage FlClash: auto-start when the proxy is down, auto-close after the run"))
                    }
                    if draft.manageFlClash {
                        HStack(spacing: 8) {
                            Text("Bundle ID")
                            TextField("com.follow.clash", text: $draft.flclashBundle)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    Text(L("关闭代管即为手动代理模式：只使用已开启的系统代理，代理不通时跳过本次检查。",
                           "With management off (manual mode) only the running system proxy is used; the run is skipped when it is down."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L("环境检测", "Environment")) {
                    LabeledContent(L("鼠须管", "Squirrel")) {
                        Text(model.env.squirrelInstalled ? L("已安装", "Installed") : L("未检测到", "Not found"))
                            .foregroundStyle(model.env.squirrelInstalled ? Color.green : Color.orange)
                    }
                    LabeledContent(L("Rime 用户目录", "Rime user dir")) {
                        Text(L("路径 ~/Library/Rime · ", "at ~/Library/Rime · ") + rimeDirStateText)
                            .foregroundStyle(model.env.rimeDirState == .ok ? Color.green : Color.orange)
                    }
                    if let real = model.env.rimeDirRealPath {
                        LabeledContent(L("实际位置", "Resolves to")) {
                            Text(real)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                    Text(L("鼠须管各版本均固定使用 ~/Library/Rime，不支持自定义路径；符号链接会照常穿透读写。",
                           "Every Squirrel version hardcodes ~/Library/Rime and offers no custom path; symlinks are followed transparently."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Button(L("保存并应用", "Save & Apply")) {
                            model.settings = currentSettings
                            model.saveSettingsAndApply()
                            savedAt = Date()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(L("恢复默认值", "Reset to defaults")) {
                            let d = UpdaterSettings()
                            draft = d
                            var c = DateComponents(); c.hour = d.hour; c.minute = d.minute
                            time = Calendar.current.date(from: c) ?? Date()
                        }

                        Spacer()
                    }
                    if let savedAt {
                        Text(L("已保存并应用到计划任务", "Saved and applied to the launchd job")
                             + " · " + savedAt.formatted(date: .omitted, time: .standard))
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }

                Section(L("高级", "Advanced")) {
                    NavigationLink(value: "update-script") {
                        LabeledContent {
                            Text(L("图形化编辑并安装", "Edit & install graphically"))
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(L("更新脚本…", "Update script…"))
                        }
                    }
                    Text(L("直接修改更新引擎脚本，属于进阶功能；一般需求用上面的设置即可满足。",
                           "Directly edit the engine script (advanced). The settings above cover normal needs."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section(L("卸载", "Uninstall")) {
                    Button(L("卸载…", "Uninstall…"), role: .destructive) { confirmUninstall = true }
                        .disabled(!model.state.scriptInstalled || model.running)
                    Text(L("移除计划任务、更新脚本和通知助手；词库文件与运行日志保留。卸载后如需重新使用，可到\"设置 → 高级 → 更新脚本\"重新安装。",
                           "Removes the schedule, the engine script and the notify helper. Dicts and logs are kept. To use it again, reinstall from Settings → Advanced → Update script."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let uninstalledAt {
                        Text(L("已卸载 ", "Uninstalled ")
                             + uninstalledAt.formatted(date: .omitted, time: .standard))
                            .font(.footnote)
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
            .navigationTitle(L("设置", "Settings"))
            .navigationDestination(for: String.self) { route in
                if route == "update-script" {
                    ScriptEditorPage()
                }
            }
            .onAppear(perform: syncFromModel)
            .confirmationDialog(L("确认卸载？", "Uninstall?"),
                                isPresented: $confirmUninstall,
                                titleVisibility: .visible) {
                Button(L("卸载（保留词库与日志）", "Uninstall (keep dicts & logs)"), role: .destructive) {
                    model.uninstall()
                    uninstalledAt = Date()
                }
                Button(L("取消", "Cancel"), role: .cancel) {}
            } message: {
                Text(L("将移除计划任务、更新脚本和通知助手；词库文件与运行日志保留。",
                       "Removes the schedule, the engine script and the notify helper. Dicts and logs are kept."))
            }
        }
    }

    private var rimeDirStateText: String {
        switch model.env.rimeDirState {
        case .ok: return L("正常", "OK")
        case .missing: return L("不存在", "missing")
        case .empty: return L("无 Rime 配置", "no Rime config")
        }
    }

    private func syncFromModel() {
        model.refresh()
        // refresh() probes in the background; load the draft straight from
        // the conf file so it is never stale here.
        draft = SettingsStore.load()
        var c = DateComponents()
        c.hour = draft.hour
        c.minute = draft.minute
        time = Calendar.current.date(from: c) ?? Date()
    }
}

// MARK: - script editor page (secondary page of Settings)

struct ScriptEditorPage: View {
    @EnvironmentObject var model: AppModel
    @State private var confirmNonASCII = false
    @State private var confirmDiscard = false
    @State private var confirmResetBuiltin = false
    @State private var draftTask: Task<Void, Never>?

    private var nonASCIICount: Int {
        model.scriptText.unicodeScalars.filter { !$0.isASCII }.count
    }

    private var lineCount: Int {
        // omittingEmptySubsequences: false so blank lines count, matching
        // what `wc -l` reports for the file.
        model.scriptText.split(omittingEmptySubsequences: false,
                               whereSeparator: \.isNewline).count
    }

    private var installTitle: String {
        if !model.state.scriptInstalled { return L("安装", "Install") }
        return model.scriptDirty ? L("保存并安装", "Save & Install")
                                 : L("重新安装", "Reinstall")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(model.state.scriptInstalled
                 ? L("修改保存后立即生效，无需重载定时任务。",
                     "Saved edits take effect on the next run; the schedule needs no reload.")
                 : L("安装后即可自动检查更新，无需保持本应用打开。",
                     "Once installed, updates run automatically; this app can stay closed."))
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    if nonASCIICount > 0 { confirmNonASCII = true } else { model.deploy() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.down")
                        Text(installTitle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.running || model.scriptText.isEmpty)

                Button {
                    model.checkNow()
                } label: {
                    HStack(spacing: 6) {
                        if model.running {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(model.running ? L("正在检查…", "Checking…")
                                           : L("立即检查更新", "Check now"))
                    }
                }
                .disabled(model.running || !model.state.scriptInstalled)

                Button(L("放弃修改", "Discard edits")) { confirmDiscard = true }
                    .disabled(!model.scriptDirty)

                Button(L("恢复内置版本…", "Reset to built-in…")) { confirmResetBuiltin = true }
                    .disabled(model.running)

                Spacer()

                if model.running {
                    Button(L("停止", "Stop")) { model.stopRun() }
                }
            }

            TextEditor(text: $model.scriptText)
                .font(.system(size: 12, design: .monospaced))
                .frame(maxHeight: .infinity)

            footer

            if model.running || !model.runOutput.isEmpty {
                RunConsoleView(tall: true)
            }
        }
        .padding(16)
        .navigationTitle(L("更新脚本", "Update script"))
        .confirmationDialog(
            L("脚本包含非 ASCII 字符", "The script contains non-ASCII characters"),
            isPresented: $confirmNonASCII,
            titleVisibility: .visible
        ) {
            Button(L("仍要安装", "Install anyway"), role: .destructive) { model.deploy() }
            Button(L("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("为兼容 macOS 自带的 bash 3.2，脚本需要保持纯 ASCII。当前有 \(nonASCIICount) 处非 ASCII 字符，安装后脚本可能无法运行。",
                   "The script must stay pure ASCII for the stock bash 3.2. \(nonASCIICount) non-ASCII characters found; the script may fail to run."))
        }
        .confirmationDialog(
            L("放弃未保存的修改？", "Discard unsaved edits?"),
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button(L("放弃修改", "Discard edits"), role: .destructive) { model.discardEdits() }
            Button(L("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("编辑器将恢复为已安装（或内置）的脚本内容。",
                   "The editor reverts to the installed (or built-in) script."))
        }
        .confirmationDialog(
            L("恢复为内置脚本版本？", "Reset to the built-in script?"),
            isPresented: $confirmResetBuiltin,
            titleVisibility: .visible
        ) {
            Button(L("恢复内置版本", "Reset to built-in"), role: .destructive) {
                model.loadBundledScript()
            }
            Button(L("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("把编辑器内容替换为本 App 内置的最新引擎脚本（可用于升级旧安装或撤销手改）。之后仍需点\"保存并安装\"才会写入磁盘。",
                   "Replaces the editor with the latest engine script bundled in this app (use it to upgrade an old install or undo local tweaks). Nothing is written until you press \"Save & Install\"."))
        }
        .onChange(of: model.scriptText) { _, _ in
            // Debounced draft autosave; quitting flushes whatever is pending.
            draftTask?.cancel()
            draftTask = Task {
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                model.flushDraft()
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.scriptSource == .installed
                         ? L("正在编辑已安装的脚本", "Editing the installed script")
                         : L("尚未安装，显示内置脚本", "Not installed; showing the built-in script"))
                    if model.scriptDirty {
                        Text(L("· 有未保存修改（已自动暂存，重开不丢失）",
                               "· unsaved edits (autosaved as draft)"))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if let at = model.deployedAt, !model.scriptDirty {
                Text(L("已安装 ", "Installed ")
                     + at.formatted(date: .omitted, time: .standard))
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(L("行数 \(lineCount)", "\(lineCount) lines"))
            if nonASCIICount > 0 {
                Label(L("非 ASCII 字符 \(nonASCIICount) 处", "\(nonASCIICount) non-ASCII"),
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text((Paths.script.path as NSString).abbreviatingWithTildeInPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
