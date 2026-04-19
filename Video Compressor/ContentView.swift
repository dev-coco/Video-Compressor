import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
class VideoConverterViewModel: ObservableObject {
    // 待处理的视频文件总数
    @Published var totalCount = 0
    // 已完成压缩的文件数
    @Published var processedCount = 0
    // 累计节省的磁盘空间
    @Published var savedSpace: Int64 = 0
    // 执行批量压缩状态
    @Published var isProcessing = false
    // 正在扫描文件或文件夹的状态
    @Published var isScanning = false
    // 当前单个视频的压缩进度
    @Published var singleVideoProgress: Double = 0.0
    // 当前正在处理的文件名
    @Published var lastFileName = ""
    // 扫描后所有待处理的视频文件
    @Published var allResolvedFiles: [URL] = []
    
    // 隔离在独立并发上下文中执行
    private let conversionActor = VideoConversionActor()

    // 递归扫描所有文件
    func prepareItems(_ urls: [URL]) async {
        isScanning = true
        
        // 重置所有统计状态
        self.processedCount = 0
        self.savedSpace = 0
        self.singleVideoProgress = 0.0
        self.lastFileName = ""

        // 支持的视频文件扩展名
        let videoExts = ["mp4", "mov", "m4v", "mkv", "avi", "flv", "wmv"]
        
        // 将文件扫描放到后台线程，避免堵塞主线程
        let resolvedFiles = await Task.detached(priority: .userInitiated) {
            var files: [URL] = []
            for url in urls {
                // 请求安全作用域访问权限
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                
                var isDir: ObjCBool = false
                // 检查路径是否存在，并判断是文件还是目录
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    if isDir.boolValue {
                        // 如果是文件夹，使用枚举器递归遍历所有子文件
                        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
                        while let fileURL = enumerator?.nextObject() as? URL {
                            // 只收集扩展名匹配的视频文件
                            if videoExts.contains(fileURL.pathExtension.lowercased()) {
                                files.append(fileURL)
                            }
                        }
                    } else if videoExts.contains(url.pathExtension.lowercased()) {
                        files.append(url)
                    }
                }
            }
            // 去重，防止同一文件被处理多次
            return Array(Set(files))
        }.value
        
        // 将后台线程的扫描结果同步回主线程状态
        self.allResolvedFiles = resolvedFiles
        self.totalCount = resolvedFiles.count
        self.isScanning = false
    }

    // 批量压缩视频
    func startConversion(extreme: Bool, deleteOriginal: Bool) async {
        guard totalCount > 0 else { return }
        processedCount = 0
        savedSpace = 0
        withAnimation(.spring()) { isProcessing = true }

        // 按顺序处理每个视频文件
        for fileURL in allResolvedFiles {
            // 更新当前处理文件名称
            self.lastFileName = fileURL.lastPathComponent
            // 重置单文件进度
            self.singleVideoProgress = 0
            
            // 传入进度回调
            let saving = await conversionActor.compressVideo(
                url: fileURL,
                extremeCompression: extreme,
                deleteOriginal: deleteOriginal
            ) { progress in
                DispatchQueue.main.async { self.singleVideoProgress = progress }
            }

            // 已完成数量
            processedCount += 1
            // 累加节省的空间
            savedSpace += saving
        }
        // 所有文件处理完成，恢复空闲状态
        withAnimation(.spring()) { isProcessing = false }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = VideoConverterViewModel()
    // 是否启用极限压缩
    @State private var extremeCompression = false
    // 是否删除原始文件
    @State private var deleteOriginal = false
    // 当前是否有文件拖拽到窗口
    @State private var isTargeted = false
    // 控制 Popover 显示
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            // 使用系统窗口颜色，自适应浅色或深色主题
            Color(NSColor.windowBackgroundColor).edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // 顶部标题
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundColor(.orange)
                        Text("app_name").font(.system(size: 14, weight: .bold, design: .rounded))
                    }
                    Spacer()
                }
                .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 10)
                
                // 内容区
                VStack {
                    if viewModel.totalCount == 0 {
                        // 未拖入文件时显示引导界面
                        welcomeView
                    } else {
                        // 已有文件时显示进度和统计
                        progressView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // 底部栏
                VStack(spacing: 0) {
                    Divider().opacity(0.6)
                    
                    HStack(alignment: .center) {
                        // 左下角齿轮图标
                        Button(action: { showSettings.toggle() }) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        // 从按钮顶部弹出更多设置
                        .popover(isPresented: $showSettings, arrowEdge: .top) {
                            settingsView
                        }
                        .disabled(viewModel.isProcessing)
                        
                        Spacer()
                        
                        // 主功能按钮
                        Button(action: {
                            Task { await viewModel.startConversion(extreme: extremeCompression, deleteOriginal: deleteOriginal) }
                        }) {
                            ZStack {
                                if viewModel.isProcessing {
                                    HStack(spacing: 10) {
                                        // 显示 ProgressView 加载动画 + 文字
                                        ProgressView().controlSize(.small).brightness(1)
                                        Text("status_compressing")
                                    }
                                } else {
                                    Text("action_start_batch")
                                }
                            }
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 110, height: 32)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.large)
                        // 无文件或正在处理时禁用按钮
                        .disabled(viewModel.totalCount == 0 || viewModel.isProcessing)
                    }
                    .padding(.horizontal, 25)
                    .padding(.vertical, 25)
                }
            }
        }
        // 固定窗口尺寸
        .frame(width: 380, height: 500)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    // 从 NSItemProvider 中异步加载文件 URL
                    // loadItem 返回的是 Data 类型，需要转换为 URL
                    if let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) as? Data,
                       let url = URL(dataRepresentation: item, relativeTo: nil) {
                        urls.append(url)
                    }
                }
                if !urls.isEmpty { await viewModel.prepareItems(urls) }
            }
            return true
        }
    }
    
    // 设置 Popover
    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 极限压缩模式开关
            // 开启后使用更激进的压缩参数，体积更小但是音质下降
            Toggle("mode_extreme", isOn: $extremeCompression)
                .font(.system(size: 14, weight: .medium))
            // 完成后删除原始文件开关
            // 节省空间，但不可逆
            Toggle("setting_delete_original", isOn: $deleteOriginal)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 25)
    }
    
    private var welcomeView: some View {
        VStack(spacing: 25) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.05)).frame(width: 140, height: 140)
                Image(systemName: "video.badge.plus").font(.system(size: 44, weight: .thin)).foregroundColor(.orange)
            }
            Text(viewModel.isScanning ? "status_scanning" : "hint_drop_files").font(.system(size: 18, weight: .semibold, design: .rounded))
        }
    }
    
    // 进度视图
    private var progressView: some View {
        VStack(spacing: 35) {
            // 环形进度
            ZStack {
                Circle().stroke(Color.primary.opacity(0.06), lineWidth: 10)
                Circle().trim(from: 0, to: viewModel.totalCount > 0 ? Double(viewModel.processedCount) / Double(viewModel.totalCount) : 0)
                    .stroke(LinearGradient(colors: [.orange, .yellow], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(Int((Double(viewModel.processedCount) / Double(max(1, viewModel.totalCount))) * 100))%").font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    Text("\(viewModel.processedCount) / \(viewModel.totalCount)").font(.system(size: 13, design: .monospaced)).foregroundColor(.secondary)
                }
            }.frame(width: 170, height: 170)
            
            // 水平单文件进度
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(viewModel.lastFileName).font(.caption).lineLimit(1)
                        Spacer()
                        Text("\(Int(viewModel.singleVideoProgress * 100))%").font(.caption.monospacedDigit())
                    }
                    ProgressView(value: viewModel.singleVideoProgress, total: 1.0)
                        .tint(.orange)
                }.padding(.horizontal, 40)
            }
            
            // 节省统计
            VStack(spacing: 2) {
                Text(formatBytes(viewModel.savedSpace)).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundColor(.green)
                Text("result_space_saved").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            }
        }
    }

    // 将字节数转换为人性化的文件大小字符串
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter(); formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
