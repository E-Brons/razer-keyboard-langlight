import Foundation
import ServiceManagement
import RazerBLE

func log(_ s: String) {
    FileHandle.standardError.write("[\(ISO8601DateFormatter().string(from: Date()))] \(s)\n".data(using: .utf8)!)
}

func fail(_ s: String) -> Never { log(s); exit(1) }

let args = Array(CommandLine.arguments.dropFirst())
let usage = """
usage: langlight set RRGGBB
       langlight watch [--he RRGGBB] [--en RRGGBB] [--caps RRGGBB] [--other RRGGBB]
       langlight install [watch options]   (LaunchAgent at login)
       langlight uninstall
       langlight get [CLASS ID SUB1 SUB2]       (default: probe getters 10 80..85)
       langlight raw CLASS ID SUB1 SUB2 [DATA...]   (hex bytes)
"""

nonisolated(unsafe) var watcher: Watcher?
switch args.first {
case "install":
    do { try LaunchAgent.install(extraArgs: Array(args.dropFirst())); exit(0) } catch { fail("\(error)") }
case "uninstall":
    LaunchAgent.uninstall(); exit(0)
case "login-item":   // run from inside Langlight.app: register/unregister as a Login Item
    do {
        if args.dropFirst().first == "off" { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        print("login item status: \(SMAppService.mainApp.status)"); exit(0)
    } catch { fail("\(error)") }
default: break
}

let transport = CoreBluetoothTransport()
if ProcessInfo.processInfo.environment["LL_DEBUG"] != nil { transport.log = log }

func parseBytes(_ a: ArraySlice<String>) -> [UInt8]? {
    let b = a.compactMap { UInt8($0, radix: 16) }
    return b.count == a.count ? b : nil
}

Task { @MainActor in
    let device = RazerDevice(transport: transport)
    if args.first == "watch" || args.isEmpty {   // no args: launched as a login item
        var palette = Palette()
        var i = 1
        while i + 1 < args.count {
            guard let c = RGB(hex: args[i + 1]) else { print(usage); exit(2) }
            switch args[i] {
            case "--he": palette.hebrew = c
            case "--en": palette.english = c
            case "--caps": palette.englishCaps = c
            case "--other": palette.other = c
            default: print(usage); exit(2)
            }
            i += 2
        }
        watcher = Watcher(device: device, palette: palette, log: log)
        watcher?.start()
        SystemEvents.observe { why in watcher?.log("\(why): re-applying"); watcher?.forceApply() }
        return
    }
    device.connect()
    do {
        try await device.waitReady(timeout: 15)
        switch args.first {
        case "set":
            guard args.count == 2, let rgb = RGB(hex: args[1]) else { print(usage); exit(2) }
            try await device.setStaticColor(r: rgb.r, g: rgb.g, b: rgb.b)
        case "get":
            let cmds: [Command]
            if args.count == 5, let b = parseBytes(args.dropFirst()), let c = Command(bytes: b) { cmds = [c] }
            else { cmds = [.get80, .get81, .get82, .get83, .get85] }
            for c in cmds {
                let r = try await device.raw(c)
                print("\(c) -> \(r.status.map(String.init(describing:)) ?? "status \(r.statusByte)") hdr[\(hex(r.header))] payload[\(hex(r.payload))]")
            }
        case "raw":
            guard args.count >= 5, let b = parseBytes(args.dropFirst()), let c = Command(bytes: Array(b.prefix(4))) else { print(usage); exit(2) }
            let r = try await device.raw(c, Array(b.dropFirst(4)))
            print("\(r.status.map(String.init(describing:)) ?? "status \(r.statusByte)") hdr[\(hex(r.header))] payload[\(hex(r.payload))]")
        default:
            print(usage); exit(2)
        }
        exit(0)
    } catch {
        fail("\(error)")
    }
}
RunLoop.main.run()

