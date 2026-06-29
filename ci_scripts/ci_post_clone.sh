#!/bin/sh
set -e
# Oryne.xcodeproj is generated from project.yml by XcodeGen
# and is gitignored, so materialize it before build steps.
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
