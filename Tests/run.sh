#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp Tests/OutboundRulesTests.swift "$test_dir/main.swift"
xcrun swiftc -target arm64-apple-macos15.0 Shared/OutboundRule.swift "$test_dir/main.swift" -o "$test_dir/rules-test"
"$test_dir/rules-test"
cp Tests/InsightsTests.swift "$test_dir/main.swift"
xcrun swiftc -target arm64-apple-macos15.0 Sources/Models.swift Sources/TrafficStore.swift Sources/NetworkInsights.swift "$test_dir/main.swift" -o "$test_dir/insights-test"
"$test_dir/insights-test"
cp Tests/IPAssessmentTests.swift "$test_dir/main.swift"
xcrun swiftc -target arm64-apple-macos15.0 Sources/ClaudeAccountRisk.swift Sources/IPAssessment.swift Sources/IPAssessmentDetails.swift Sources/IPReputation.swift Sources/CheckMyIP.swift Sources/IPReputationSummary.swift Sources/IPEnvironmentRisk.swift Sources/IPExitStability.swift Sources/IPUsage.swift Sources/NetworkConnectivity.swift "$test_dir/main.swift" -o "$test_dir/assessment-test"
"$test_dir/assessment-test"
