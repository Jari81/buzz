import Flutter
import UIKit

final class ConcentricSheetSurfaceFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    ConcentricSheetSurfacePlatformView(frame: frame, arguments: args)
  }
}

final class ConcentricSheetSurfacePlatformView: NSObject, FlutterPlatformView {
  private let surfaceView: UIView

  init(frame: CGRect, arguments args: Any?) {
    let arguments = args as? [String: Any]
    let colorValue = (arguments?["color"] as? NSNumber)?.uint32Value ?? 0xFFFF_FFFF
    let minimumRadius = (arguments?["minimumRadius"] as? NSNumber)?.doubleValue ?? 24
    let corners = arguments?["corners"] as? String ?? "all"

    surfaceView = UIView(frame: frame)
    surfaceView.isOpaque = true
    surfaceView.backgroundColor = Self.color(from: colorValue)
    surfaceView.clipsToBounds = true
    surfaceView.layer.cornerCurve = .continuous

    if #available(iOS 26.0, *) {
      let radius = UICornerRadius.containerConcentric(minimum: minimumRadius)
      surfaceView.cornerConfiguration =
        corners == "bottom"
        ? .uniformBottomRadius(
          radius,
          topLeftRadius: nil,
          topRightRadius: nil
        )
        : .uniformCorners(radius: radius)
    } else {
      surfaceView.layer.cornerRadius = minimumRadius
      if corners == "bottom" {
        surfaceView.layer.maskedCorners = [
          .layerMinXMaxYCorner,
          .layerMaxXMaxYCorner,
        ]
      }
    }

    super.init()
  }

  func view() -> UIView {
    surfaceView
  }

  private static func color(from value: UInt32) -> UIColor {
    let alpha = CGFloat((value >> 24) & 0xFF) / 255
    let red = CGFloat((value >> 16) & 0xFF) / 255
    let green = CGFloat((value >> 8) & 0xFF) / 255
    let blue = CGFloat(value & 0xFF) / 255
    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}
