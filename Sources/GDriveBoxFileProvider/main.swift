import Foundation

// App extensions start in NSExtensionMain (Foundation), which Xcode wires up with `-e _NSExtensionMain`.
// SwiftPM executables need a Swift entry point, so this one hands straight over.
@_silgen_name("NSExtensionMain")
private func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

// NSExtensionPrincipalClass names this class; referencing it keeps it linked.
_ = FileProviderExtension.self
exit(NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv))
