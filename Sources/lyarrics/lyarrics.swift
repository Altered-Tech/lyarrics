// The Swift Programming Language
// https://docs.swift.org/swift-book
// 
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import Configuration
import LRCLib

@main
struct lyarrics: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A utility for fetching song lyrics",
        version: appVersion,
        subcommands: [Serve.self, Fetch.self, Scan.self, Search.self]
    )
}