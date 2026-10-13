import Foundation
import Darwin
guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--request", CommandLine.arguments[2].hasPrefix("/") else { exit(2) }
do { try UpdateHelper.run(requestURL:URL(fileURLWithPath:CommandLine.arguments[2])) }
catch { exit(1) }
