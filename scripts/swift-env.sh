# Sourced by the build scripts. Works around two gaps in a Command Line Tools-only install (no Xcode):
#  - the newest SDK declares SwiftUI's @State as a macro whose plugin CLT does not ship, so pin the 26 SDK;
#  - SwiftPM does not find the swift-testing macro plugin, so point the compiler at it.
CLT=/Library/Developer/CommandLineTools

SWIFT_FLAGS=()
if [[ "$(xcode-select -p)" == "$CLT" ]]; then
    if [[ -z "${SDKROOT:-}" && -d "$CLT/SDKs/MacOSX26.sdk" ]]; then
        export SDKROOT="$CLT/SDKs/MacOSX26.sdk"
    fi
    if [[ -d "$CLT/usr/lib/swift/host/plugins/testing" ]]; then
        SWIFT_FLAGS+=(-Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing")
    fi
fi
