// Sources/CL10/main.swift
import Foundation

let cli = CLI()
let args = Array(CommandLine.arguments.dropFirst())
let code = cli.run(args: args)
exit(code.rawValue)
