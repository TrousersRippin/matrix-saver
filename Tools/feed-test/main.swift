// Runs the log feed tests (Tools/feed-test/Tests.swift, compiled into MatrixView.swift by
// Tools/feed-test.sh). The argument is a scratch directory for test log files.
import Foundation

exit(runFeedTests(scratch: CommandLine.arguments[1]) ? 0 : 1)
