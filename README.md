# HyperEyeReaderExample
A reference application. 
[HyperEyeFramework](https://github.com/Winkk/HyperEyeFramework) usage example.

# CocoaPods
CocoaPods tool is used to integrate the framework into the project.
Follow the standard CocoaPods steps to integrate `HyperEyeFramework` into a new project.
* Install [CocoaPods](https://cocoapods.org).
* Create a new project in XCode and save somewhere. Quit XCode.
* Go to the project folder (where a `xcodeproj` is situated) via `Terminal`.
* Execute command `pod init`.
* Modify the created Podfile by adding target dependency
```
use_frameworks!
pod 'HyperEyeFramework', :git => 'https://github.com/winkk/HyperEyeFramework.git'
```
* This will install the latest version of the framework.
* Execute the command `pod install`.
* Open the created `xcworkspace` instead of `xcodeproj` in XCode.
