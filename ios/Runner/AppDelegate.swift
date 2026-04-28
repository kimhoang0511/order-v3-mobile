import Flutter
import UIKit
import Photos

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handles kinzoapp:// URLs when app is open or brought to foreground.
  override func application(_ app: UIApplication, open url: URL,
                             options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
    if url.scheme == "kinzoapp" {
      let urlString = url.absoluteString
      if let channel = deepLinkChannel {
        channel.invokeMethod("onDeepLink", arguments: urlString)
      } else {
        pendingDeepLink = urlString
      }
      return true
    }
    return super.application(app, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KinzoStorage") else { return }
    let channel = FlutterMethodChannel(
      name: "com.kinzo/storage",
      binaryMessenger: registrar.messenger()
    )

    channel.setMethodCallHandler { call, result in
      guard call.method == "saveToDownloads" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let bytes = args["bytes"] as? FlutterStandardTypedData else {
        result(FlutterError(code: "INVALID_ARGS", message: "bytes is null", details: nil))
        return
      }

      guard let image = UIImage(data: bytes.data) else {
        result(FlutterError(code: "INVALID_IMAGE", message: "Cannot decode image", details: nil))
        return
      }

      PHPhotoLibrary.requestAuthorization { status in
        guard status == .authorized else {
          result(FlutterError(code: "PERMISSION_DENIED", message: "Photo library access denied", details: nil))
          return
        }
        PHPhotoLibrary.shared().performChanges({
          PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { success, error in
          if success {
            result(true)
          } else {
            result(FlutterError(code: "SAVE_FAILED", message: error?.localizedDescription, details: nil))
          }
        }
      }
    }

    // Deep link channel — delivers kinzoapp:// URLs to Flutter.
    let dlChannel = FlutterMethodChannel(
      name: "com.kinzo/deep_link",
      binaryMessenger: registrar.messenger()
    )
    deepLinkChannel = dlChannel
    dlChannel.setMethodCallHandler { [weak self] _, _ in }

    // Deliver any URL that arrived before Flutter was ready.
    if let pending = pendingDeepLink {
      pendingDeepLink = nil
      dlChannel.invokeMethod("onDeepLink", arguments: pending)
    }
  }
}
