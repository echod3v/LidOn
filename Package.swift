// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LidOn",
    platforms: [.macOS(.v14)],
    targets: [
        // 순수 로직 + 시스템 접근 (테스트 대상)
        .target(name: "LidOnCore", path: "Sources/LidOnCore",
                linkerSettings: [.linkedFramework("IOKit")]),
        // 메뉴 막대 앱 (번들 안에서는 LidOn으로 이름이 바뀐다)
        .executableTarget(name: "LidOnApp", dependencies: ["LidOnCore"], path: "Sources/LidOnApp",
                          linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("ServiceManagement")]),
        // `lidon` 명령어 (대소문자 구분 없는 파일 시스템에서 LidOn과 충돌하지 않도록 타깃명을 분리)
        .executableTarget(name: "LidOnCLI", dependencies: ["LidOnCore"], path: "Sources/LidOnCLI"),
        .testTarget(name: "LidOnCoreTests", dependencies: ["LidOnCore"], path: "Tests/LidOnCoreTests"),
    ]
)
