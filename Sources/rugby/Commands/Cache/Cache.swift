//
//  Cache.swift
//  
//
//  Created by v.khorkov on 29.01.2021.
//

import ArgumentParser
import Files
import Foundation
import Rainbow
import ShellOut

private extension String {
    static let buildTarget = "RemotePods"
}

private enum WrappedError: Error, LocalizedError {
    case common(String)

    var errorDescription: String? {
        switch self {
        case .common(let description):
            return description
        }
    }
}

struct Cache: ParsableCommand {
    @Flag(name: .long, help: "Print more information.") var verbose = false
    @Flag(name: .long, help: "Ignore already cached pods.") var rebuild = false
    @Option(name: .long, help: "Build architechture.") var arch: String?
    @Option(name: .long, help: "Build sdk: sim or ios.\nUse --rebuild after switch.") var sdk: SDK = .sim

    static var configuration: CommandConfiguration = .init(
        abstract: "Remove remote pods, build them and integrate as frameworks."
    )

    func run() throws {
        try wrapError(privateRun)
    }

    private func privateRun() throws {
        let totalTime = try measure {
            let logFile = try Folder.current.createFile(at: .log)
            let buildTarget: String = .buildTarget

            let prepareStep = PrepareStep(logFile: logFile, verbose: verbose)
            let input = try prepareStep.run(buildTarget: buildTarget, needRebuild: rebuild)

            let buildStep = BuildStep(logFile: logFile, verbose: verbose)
            try buildStep.run(scheme: input.buildPods.isEmpty ? nil : buildTarget,
                              checksums: input.checksums,
                              sdk: sdk,
                              arch: arch)

            let integrateStep = IntegrateStep(logFile: logFile, verbose: verbose)
            try integrateStep.run(remotePods: input.remotePods, cacheFolder: .cacheFolder(sdk: sdk))

            let cleanupStep = CleanupStep(logFile: logFile, verbose: verbose)
            try cleanupStep.run(remotePods: input.remotePods, buildTarget: buildTarget)

            try shellOut(to: "tput bel")
        }
        print("[\(totalTime.formatTime())] ".yellow + "Let's roll 🏈 ".green)
    }

    private func wrapError(_ block: () throws -> Void) throws {
        do {
            try block()
        } catch {
            throw WrappedError.common(error.localizedDescription.red)
        }
    }
}
