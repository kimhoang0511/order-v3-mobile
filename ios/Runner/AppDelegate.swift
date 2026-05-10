import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return result
  }

  // Always show notification banners when the app is in the foreground.
  // Call super first so Firebase can track the event internally.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: { _ in })
    completionHandler([.banner, .sound, .badge])
  }

  // Store notification tap data in UserDefaults so Flutter can read it on resume.
  // This is the fallback when Firebase's onMessageOpenedApp doesn't fire reliably.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    var data: [String: String] = [:]
    for (k, v) in info {
      if let key = k as? String, let val = v as? String { data[key] = val }
    }

    if !data.isEmpty, let json = try? JSONSerialization.data(withJSONObject: data),
       let str = String(data: json, encoding: .utf8) {
      UserDefaults.standard.set(str, forKey: "kinzo_fcm_tap")

      // Foreground tap: app is already active so lifecycle .resumed won't fire.
      // Invoke Flutter channel directly so navigation happens immediately.
      let state = UIApplication.shared.applicationState
      if state == .active || state == .inactive {
        for scene in UIApplication.shared.connectedScenes {
          if let ws = scene as? UIWindowScene,
             let sd = ws.delegate as? SceneDelegate {
            sd.invokeNotifTap(str)
          }
        }
      }
    }

    super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
  }
}
