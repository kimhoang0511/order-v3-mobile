import Flutter
import UIKit
import Photos

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var flutterEngine: FlutterEngine?
  private var deepLinkChannel: FlutterMethodChannel?
  private var pendingDeepLink: String?

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }

    // Explicit engine avoids the iOS 26 implicit-engine race condition
    // (flutter/flutter#183900) where viewDidLoad fires before engine attaches.
    let engine = FlutterEngine(name: "main")
    engine.run()
    GeneratedPluginRegistrant.register(with: engine)
    flutterEngine = engine

    if let registrar = engine.registrar(forPlugin: "KinzoStorage") {
      let storageChannel = FlutterMethodChannel(
        name: "com.kinzo/storage",
        binaryMessenger: registrar.messenger()
      )
      storageChannel.setMethodCallHandler { call, result in
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

      let dlChannel = FlutterMethodChannel(
        name: "com.kinzo/deep_link",
        binaryMessenger: registrar.messenger()
      )
      deepLinkChannel = dlChannel
      dlChannel.setMethodCallHandler { [weak self] _, _ in }

      if let pending = pendingDeepLink {
        pendingDeepLink = nil
        dlChannel.invokeMethod("onDeepLink", arguments: pending)
      }
    }

    let flutterVC = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let win = UIWindow(windowScene: windowScene)
    win.rootViewController = flutterVC
    self.window = win
    win.makeKeyAndVisible()
  }

  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    guard let url = URLContexts.first?.url, url.scheme == "kinzoapp" else { return }
    let urlString = url.absoluteString
    if let channel = deepLinkChannel {
      channel.invokeMethod("onDeepLink", arguments: urlString)
    } else {
      pendingDeepLink = urlString
    }
  }
}
