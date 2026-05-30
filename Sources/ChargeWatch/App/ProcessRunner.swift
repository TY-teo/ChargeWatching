import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool
}

/// 安全执行系统 CLI：固定绝对路径、不经 shell、并发排空 stdout/stderr（防管道死锁）、
/// 超时强制终止（必要时 SIGKILL）。仅用于 /usr/bin/pmset 与 /usr/bin/shortcuts。
enum ProcessRunner {
    static func run(_ launchPath: String,
                    _ arguments: [String],
                    stdin: String? = nil,
                    timeout: TimeInterval) async -> ProcessResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runSync(launchPath, arguments, stdin: stdin, timeout: timeout))
            }
        }
    }

    private static func runSync(_ launchPath: String,
                                _ arguments: [String],
                                stdin: String?,
                                timeout: TimeInterval) -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        if stdin != nil { process.standardInput = inPipe }

        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }

        do {
            try process.run()
        } catch {
            return ProcessResult(exitCode: -1, stdout: "", stderr: "launch failed: \(error.localizedDescription)", timedOut: false)
        }

        if let stdin, let data = stdin.data(using: .utf8) {
            inPipe.fileHandleForWriting.write(data)
            try? inPipe.fileHandleForWriting.close()
        }

        // 并发读取，避免子进程写满管道缓冲导致死锁。
        var outData = Data()
        var errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }

        var timedOut = false
        if done.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if done.wait(timeout: .now() + 0.3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                done.wait()
            }
        }
        group.wait()  // 进程退出后管道到达 EOF，读取返回

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            timedOut: timedOut
        )
    }
}
