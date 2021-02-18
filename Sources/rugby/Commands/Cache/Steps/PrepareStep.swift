//
//  PrepareStep.swift
//  
//
//  Created by v.khorkov on 31.01.2021.
//

import Files
import XcodeProj

final class PrepareStep: Step {
    struct Output {
        let buildPods: [String]
        let remotePods: Set<String>
        let checksums: [String]
        let podsCount: Int
    }

    init(logFile: File, verbose: Bool) {
        super.init(name: "Prepare", logFile: logFile, verbose: verbose)
    }

    func run(buildTarget: String,
             needRebuild: Bool) throws -> Output {
        // Get remote pods from Podfile.lock
        let podfile = try Podfile(.podfileLock)
        let remotePods = try podfile.getRemotePods().map { $0.trimmingCharacters(in: ["\""]) }
        progress.update(info: "Remote pods ".yellow + "(\(remotePods.count))" + ":".yellow)
        remotePods.forEach { progress.update(info: "* ".yellow + "\($0)") }

        let checksums = try podfile.getChecksums()
        let remoteChecksums = checksums.filter {
            guard let name = $0.components(separatedBy: ": ").first else { return false }
            return remotePods.contains(name)
        }

        let buildPods: [String]
        if needRebuild {
            buildPods = remotePods
        } else {
            let cachedChecksums = (try? Podfile(.cachedChecksums).getChecksums()) ?? []
            let changes = Set(remoteChecksums).subtracting(cachedChecksums)
            let changedPods = changes.compactMap { $0.components(separatedBy: ": ").first }
            buildPods = changedPods.sorted()
        }

        // Collect all remote pods chain
        let podsProject = try XcodeProj(pathString: .podsProject)
        let remotePodsChain = buildRemotePodsChain(project: podsProject, remotePods: Set(remotePods))
        let additionalBuildTargets = remotePodsChain.subtracting(remotePods)
        if !additionalBuildTargets.isEmpty {
            progress.update(info: "Additional build targets ".yellow + "(\(additionalBuildTargets.count))" + ":".yellow)
            additionalBuildTargets.sorted().forEach { progress.update(info: "* ".yellow + "\($0)") }
        }

        // Include parents of build pods
        let buildPodsChain = podsProject.findParentDependencies(Set(buildPods), allTargets: remotePods)

        if buildPodsChain.isEmpty {
            progress.update(info: "Skip".yellow)
        } else {
            progress.update(info: "Build pods ".yellow + "(\(buildPodsChain.count))" + ":".yellow)
            buildPodsChain.sorted().forEach { progress.update(info: "* ".yellow + "\($0)") }

            podsProject.pbxproj.addTarget(name: buildTarget, dependencies: buildPodsChain)
            progress.update(info: "Added aggregated build target: ".yellow + buildTarget)
            try podsProject.write(pathString: .podsProject, override: true)
        }
        done()

        return Output(buildPods: buildPodsChain,
                      remotePods: remotePodsChain,
                      checksums: remoteChecksums,
                      podsCount: checksums.count)
    }

    private func buildRemotePodsChain(project: XcodeProj, remotePods: Set<String>) -> Set<String> {
        remotePods.reduce(Set(remotePods)) { chain, name in
            let targets = Set(project.pbxproj.targets(named: name))
            return chain.union(targets.reduce(Set<String>()) { set, target in
                let dependencies = target.dependencies.compactMap(\.name).filter {
                    // Check that it's a part of remote pod
                    guard let prefix = $0.components(separatedBy: "-").first else { return true }
                    return remotePods.contains(prefix)
                }
                return set.union(dependencies)
            })
        }
    }
}
