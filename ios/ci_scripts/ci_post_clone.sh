#!/bin/sh
# Xcode Cloud runs this right after cloning, before it resolves packages or
# builds. The repo carries no .xcodeproj (project.yml is the source of truth),
# so generate it here exactly as a developer does locally.
set -e
brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
xcodegen generate
