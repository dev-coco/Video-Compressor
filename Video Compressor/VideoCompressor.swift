import Foundation
import AVFoundation
import AppKit

// 视频压缩 Actor，避免多任务并发压缩
actor VideoConversionActor {
    
    // 进度解析
    nonisolated func extractProgress(from line: String, totalDuration: Double) -> Double? {
        guard totalDuration > 0 else { return nil }
        // 匹配 ffmpeg 标准输出中的时间戳格式
        let pattern = #"time=(\d{2}):(\d{2}):(\d{2})\.(\d{2})"#

        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
            
            // 依次提取正则捕获组：at(1)=小时, at(2)=分钟, at(3)=秒
            let hours = Double(line[Range(match.range(at: 1), in: line)!]) ?? 0
            let minutes = Double(line[Range(match.range(at: 2), in: line)!]) ?? 0
            let seconds = Double(line[Range(match.range(at: 3), in: line)!]) ?? 0

            // 将时:分:秒统一换算为秒，再除以总时长得到 0.0~1.0 的进度
            let currentTime = (hours * 3600) + (minutes * 60) + seconds
            return min(1.0, currentTime / totalDuration)
        }
        return nil
    }

    // 核心压缩方法
    // 调用内嵌 ffmpeg 对单个视频进行压缩
    // - Parameters:
    //   - url: 原始视频文件的 URL
    //   - extremeCompression: 是否启用极限压缩（降低音频采样率和声道数）
    //   - deleteOriginal: 压缩完成后是否将原文件移入废纸篓
    //   - onProgress: 进度回调，值域 0.0 ~ 1.0
    // - Returns: 压缩节省的字节数（原始大小 - 压缩后大小），失败时返回 0
    func compressVideo(url: URL, extremeCompression: Bool, deleteOriginal: Bool, onProgress: @escaping (Double) -> Void) async -> Int64 {
        // 申请沙盒外文件访问权限
        let accessGranted = url.startAccessingSecurityScopedResource()
        defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }

        // 获取可执行文件
        guard let ffmpegPath = Bundle.main.path(forResource: "ffmpeg", ofType: nil) else { return 0 }
        
        // 读取视频总时长，用于后续计算压缩进度百分比
        let asset = AVURLAsset(url: url)
        let duration = (try? await asset.load(.duration))?.seconds ?? 0
        
        // 与原文件同目录，文件名加 "_compressed" 后缀，强制转为 mp4
        let fileName = url.deletingPathExtension().lastPathComponent
        let directory = url.deletingLastPathComponent()
        let destinationURL = directory.appendingPathComponent("\(fileName)_compressed.mp4")
        
        // 如果同名输出文件已存在则先删除，ffmpeg 默认不会覆盖已有文件
        try? FileManager.default.removeItem(at: destinationURL)

        // 配置 ffmpeg 进程
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        
        // 基础视频参数
        var args = [
            "-i", url.path,
            "-c:v", "libx264",
            "-tag:v", "avc1",
            "-movflags", "faststart",
            "-crf", "30",
            "-preset", "superfast"
        ]
        
        // 根据是否开启极限压缩决定音频参数
        if extremeCompression {
            args += ["-ac", "1", "-ar", "16000", "-b:a", "24000"]
        } else {
            args += ["-c:a", "copy"]
        }
        
        args.append(destinationURL.path)
        process.arguments = args

        // 捕获 ffmpeg 进度输出
        let pipe = Pipe()
        process.standardError = pipe
        let fileHandle = pipe.fileHandleForReading
        
        // 异步回调，每当管道中有新数据可读时触发
        fileHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8) {
                if let progress = self.extractProgress(from: line, totalDuration: duration) {
                    onProgress(progress)
                }
            }
        }

        // 启动进程并等待结果
        return await withCheckedContinuation { continuation in
            do {
                try process.run()
                // 在 ffmpeg 进程结束时触发
                process.terminationHandler = { p in
                    // 进程结束后立即移除读取回调，防止悬空引用和内存泄漏
                    fileHandle.readabilityHandler = nil
                    if p.terminationStatus == 0 {
                        // 读取原始文件和压缩后文件的大小，计算节省空间
                        let oldSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
                        let newSize = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
                        
                        // 完成后移入废纸篓
                        if deleteOriginal {
                            DispatchQueue.main.async {
                                NSWorkspace.shared.recycle([url]) { _, _ in }
                            }
                        }
                        continuation.resume(returning: max(0, oldSize - newSize))
                    } else {
                        continuation.resume(returning: 0)
                    }
                }
            } catch {
                continuation.resume(returning: 0)
            }
        }
    }
}
