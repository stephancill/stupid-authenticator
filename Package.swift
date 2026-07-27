// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "StupidAuthenticator",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    // An xtool project should contain exactly one library product,
    // representing the main app.
    .library(
      name: "StupidAuthenticator",
      targets: ["StupidAuthenticator"]
    ),
    .library(
      name: "StupidAuthenticatorAutofill",
      targets: ["StupidAuthenticatorAutofill"]
    ),
  ],
  targets: [
    .target(
      name: "StupidAuthenticatorCore"
    ),
    .target(
      name: "StupidAuthenticator",
      dependencies: ["StupidAuthenticatorCore"]
    ),
    .target(
      name: "StupidAuthenticatorAutofill",
      dependencies: ["StupidAuthenticatorCore"]
    ),
    .testTarget(
      name: "StupidAuthenticatorTests",
      dependencies: ["StupidAuthenticatorCore"]
    ),
  ]
)
