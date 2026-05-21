# 1. Generate the project and build Release
xcodegen generate
xcodebuild -project Yankit.xcodeproj -scheme Yankit -configuration Release \
  -derivedDataPath build build

# 2. Install it
killall Yankit 2>/dev/null            # close any running copy first
rm -rf /Applications/Yankit.app       # remove an old install if present
cp -R build/Build/Products/Release/Yankit.app /Applications/

# 3. Launch it
open /Applications/Yankit.app
