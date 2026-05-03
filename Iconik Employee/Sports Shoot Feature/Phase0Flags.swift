//
//  Phase0Flags.swift
//  Iconik Employee
//
//  Feature flags for the Phase 0 sync rewrite (SYNC_ARCHITECTURE_SPEC.md
//  on the Mac side, mirrored here in the Swift app).
//
//  Mirrors `src/data/repositories/feature-flags.ts` in the FP Production
//  TypeScript codebase. The flag values are read from UserDefaults so a
//  developer can flip them in Xcode at runtime via debugger console:
//
//    e UserDefaults.standard.set(true, forKey: "use_repo_pattern_subjects")
//
//  Default: OFF. Legacy iPad write path stays the only production path
//  until you opt in. Flipping the flag during a shoot is safe — the
//  current call site reads the flag at the entry to each mutation.
//

import Foundation

enum Phase0Flags {

    /// USE_REPO_PATTERN_subjects (Swift mirror).
    /// When ON and the iPad is in a capture session, subject mutations send
    /// a `subject_command` over WebSocket to the Surface and await an ack
    /// instead of writing to local PowerSync directly. Per spec §11.1 the
    /// Surface is the single ordering authority during a shoot.
    static var useRepoPatternSubjects: Bool {
        UserDefaults.standard.bool(forKey: "use_repo_pattern_subjects")
    }

    /// Convenience setter for Xcode debug. Not invoked from production code.
    static func setUseRepoPatternSubjects(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "use_repo_pattern_subjects")
    }
}
