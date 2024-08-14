# MSDisplayLink

The missing DisplayLink driver for Apple platforms. Use CADisplayLink on UIKit and CVDisplayLink on AppKit.

Battle tested in [ColorfulX](https://github.com/Lakr233/ColorfulX)

Called MS but it has nothing to do with Microsoft. :P

## Preview

![Preview](Resources/SCR-20240814-qqri.jpeg)

## Installation

### Swift Package Manager

```swift
.package(url: "https://github.com/Lakr233/MSDisplayLink.git", from: "1.0.0")
```

### CocoaPods

**Never thought about it.**

## Usage

### UIKit/AppKit

Follow the steps to get called. The `DisplayLinkDelegate` is friendly to confirm for a UIView or NSView.

- Hold reference to `DisplayLink` object.
- Confirm to `DisplayLinkDelegate` protocol to get called within `synchronization()`.
- Call `displayLink.delegatingObject` with a `DisplayLinkDelegate` object.

Tech Tips:

- Call to `synchronization()` is performed at a background thread.
- Scheduler is a serial queue unique to each `DisplayLinkDriver` holds by `DisplayLink`.
    - Queue inherits the quality of service from the where you created the `DisplayLink`.
    - Does not make scene to use concurrent queue.
    - Does not share the queue across different `DisplayLink` objects.
    - Queue names are same.

### SwiftUI

```
import MSDisplayLink
import SwiftUI

struct ContentView: View {
    @State var frame: Int = 0
    var body: some View {
        VStack {
            Text("MSDisplayLink Trigger: \(frame)")
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .animation(.interactiveSpring, value: frame)
        .modifier(DisplayLinkModifier(scheduleToMainThread: true) {
            frame += 1
        })
        .padding()
    }
}
```

## License

[MIT License](LICENSE)

---

2024.08.14
