#!/bin/sh
set -eu
cd "$(dirname "$0")"
app_dir=".build/Maie Prototype.app"
mkdir -p "$app_dir/Contents/MacOS" .build/module-cache
python3 SetupHookChecks.py
python3 SkillChecks.py
python3 generate-guidance.py
swiftc -parse-as-library -module-cache-path .build/module-cache \
    -target "$(uname -m)-apple-macosx13.0" \
    ../spike/HookCore.swift LocalStorage.swift HookTransport.swift OpenAIConnection.swift .build/DiscussionSkills.generated.swift DiscussionGuidance.swift SessionModel.swift "$PWD/ModelChecks.swift" -o .build/model-checks
.build/model-checks
swiftc -parse-as-library -module-cache-path .build/module-cache \
    -target "$(uname -m)-apple-macosx13.0" \
    ../spike/HookCore.swift LocalStorage.swift HookTransport.swift HookMain.swift -o .build/maie-hook
python3 BridgeChecks.py
swiftc -parse-as-library -module-cache-path .build/module-cache \
    -target "$(uname -m)-apple-macosx13.0" \
    ../spike/HookCore.swift LocalStorage.swift HookTransport.swift OpenAIConnection.swift .build/DiscussionSkills.generated.swift DiscussionGuidance.swift SessionModel.swift ConnectionView.swift PrototypeView.swift PrototypeApp.swift \
    -o .build/MaiePrototype.next
mv .build/MaiePrototype.next "$app_dir/Contents/MacOS/MaiePrototype"
cp Info.plist "$app_dir/Contents/Info.plist"
/usr/bin/plutil -lint "$app_dir/Contents/Info.plist"
printf 'Built: %s/%s\n' "$PWD" "$app_dir"
