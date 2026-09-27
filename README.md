# Goldfish for iOS

A local relationship journal: organize people into ponds, reveal their connections in place, and keep useful memories.

Open `Goldfish.xcodeproj`, select the **Goldfish** scheme and an iPhone simulator, then Run. Minimum deployment target: iOS/iPadOS 17. Build with current Xcode 26 or newer. The checked-in project is ready to use; XcodeGen is optional.

First run offers **Explore a Sample** or **Start My Pond**. Sample data and personal contacts stay in separate scopes. This beta has no cloud sync, live proximity detection or AI voice input.

## TestFlight preparation

See [current release plan](Refinement/TESTFLIGHT_READINESS.md) and [executed checks and remaining blockers](Refinement/P1_RELEASE_VERIFICATION.md). Historical product and submission documents elsewhere in this repository describe earlier concepts and are not release claims.

After Apple membership activation, confirm the support configuration and run `GOLDFISH_TEAM_ID=YOUR_ACTIVATED_TEAM_ID Tools/archive-testflight.sh`, or Archive in Xcode with automatic signing. The helper creates an archive but does not upload it. Validate and distribute through Xcode Organizer; external TestFlight access requires Apple's beta approval.

Existing web/server sources are retained for history; the iOS beta is built by the Xcode project.
