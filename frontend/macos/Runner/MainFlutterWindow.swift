import Cocoa
import FlutterMacOS
import UserNotifications

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    MiniCameraChannel.register(messenger: flutterViewController.engine.binaryMessenger)
    DesktopNotificationChannel.register(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}

final class DesktopNotificationChannel: NSObject, UNUserNotificationCenterDelegate {
  private static let shared = DesktopNotificationChannel()
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "focusvision/desktop_notifications",
      binaryMessenger: messenger
    )
    self.channel = channel
    UNUserNotificationCenter.current().delegate = shared
    shared.registerCategories()

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "configure":
        UNUserNotificationCenter.current().delegate = shared
        shared.registerCategories()
        result(nil)
      case "requestPermission":
        shared.requestPermission(result: result)
      case "permissionStatus":
        shared.permissionStatus(result: result)
      case "show":
        guard let args = call.arguments as? [String: Any] else {
          result(false)
          return
        }

        shared.show(args: args, result: result)
      case "focusApp":
        shared.activateApp()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestPermission(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if error != nil {
        DispatchQueue.main.async {
          result([
            "authorized": false,
            "status": "error"
          ])
        }
        return
      }

      self.permissionStatus { statusResult in
        if var status = statusResult as? [String: Any] {
          status["authorized"] = granted && (status["authorized"] as? Bool ?? false)
          result(status)
        } else {
          result([
            "authorized": granted,
            "status": granted ? "authorized" : "denied"
          ])
        }
      }
    }
  }

  private func permissionStatus(result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      let status: String
      let authorized: Bool

      switch settings.authorizationStatus {
      case .authorized:
        status = "authorized"
        authorized = true
      case .provisional:
        status = "provisional"
        authorized = true
      case .denied:
        status = "denied"
        authorized = false
      case .notDetermined:
        status = "notDetermined"
        authorized = false
      @unknown default:
        status = "unknown"
        authorized = false
      }

      DispatchQueue.main.async {
        result([
          "authorized": authorized,
          "status": status,
          "alertSetting": settings.alertSetting == .enabled,
          "soundSetting": settings.soundSetting == .enabled,
          "badgeSetting": settings.badgeSetting == .enabled
        ])
      }
    }
  }

  private func show(args: [String: Any], result: @escaping FlutterResult) {
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      if settings.authorizationStatus == .notDetermined {
        self.requestPermission { _ in
          self.show(args: args, result: result)
        }
        return
      }

      guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
        DispatchQueue.main.async {
          result(false)
        }
        return
      }

      let content = UNMutableNotificationContent()
      content.title = args["title"] as? String ?? "FocusVision"
      content.body = args["body"] as? String ?? ""
      content.sound = .default
      content.categoryIdentifier = args["category"] as? String ?? "break_category"
      content.userInfo = [
        "payload": args["payload"] as? String ?? "notification"
      ]

      let identifier = args["identifier"] as? String ?? "focusvision-\(UUID().uuidString)"
      let request = UNNotificationRequest(
        identifier: identifier,
        content: content,
        trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
      )

      UNUserNotificationCenter.current().add(request) { error in
        DispatchQueue.main.async {
          result(error == nil)
        }
      }
    }
  }

  private func registerCategories() {
    let breakActions = [
      UNNotificationAction(identifier: "accept_break", title: "Mola ver", options: [.foreground]),
      UNNotificationAction(identifier: "snooze_break", title: "5 dk sonra", options: []),
      UNNotificationAction(identifier: "decline_break", title: "Devam et", options: [])
    ]

    let continueActions = [
      UNNotificationAction(identifier: "decline_break", title: "Devam et", options: []),
      UNNotificationAction(identifier: "snooze_break", title: "5 dk sonra", options: []),
      UNNotificationAction(identifier: "accept_break", title: "Yine de mola ver", options: [.foreground])
    ]

    let breakReadyActions = [
      UNNotificationAction(identifier: "return_work", title: "Çalışmaya dön", options: [.foreground]),
      UNNotificationAction(identifier: "extend_break", title: "5 dk uzat", options: [])
    ]

    let awayActions = [
      UNNotificationAction(identifier: "ok_away", title: "Tamam", options: [])
    ]

    let categories: Set<UNNotificationCategory> = [
      UNNotificationCategory(identifier: "basic", actions: [], intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: "break_category", actions: breakActions, intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: "focus_drop_category", actions: breakActions, intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: "continue_category", actions: continueActions, intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: "break_ready_category", actions: breakReadyActions, intentIdentifiers: [], options: []),
      UNNotificationCategory(identifier: "away_category", actions: awayActions, intentIdentifiers: [], options: [])
    ]

    UNUserNotificationCenter.current().setNotificationCategories(categories)
  }

  private func activateApp() {
    NSApp.activate(ignoringOtherApps: true)

    for window in NSApplication.shared.windows {
      if window is MainFlutterWindow {
        window.makeKeyAndOrderFront(nil)
        break
      }
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(macOS 11.0, *) {
      completionHandler([.banner, .list, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.actionIdentifier != UNNotificationDismissActionIdentifier {
      activateApp()
    }

    let userInfo = response.notification.request.content.userInfo
    let payload = userInfo["payload"] as? String ?? "notification"
    let actionId: String

    if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
      actionId = "open_session"
    } else {
      actionId = response.actionIdentifier
    }

    DesktopNotificationChannel.channel?.invokeMethod(
      "notificationAction",
      arguments: [
        "actionId": actionId,
        "payload": payload
      ]
    )

    completionHandler()
  }
}

final class MiniCameraChannel {
  private static let controller = MiniCameraPanelController()
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "focusvision/mini_camera",
      binaryMessenger: messenger
    )
    self.channel = channel

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "show":
        controller.show()
        result(nil)
      case "hide":
        controller.hide()
        result(nil)
      case "update":
        guard let args = call.arguments as? [String: Any] else {
          result(nil)
          return
        }

        let frame = (args["frame"] as? FlutterStandardTypedData)?.data
        let focusScore = args["focusScore"] as? Double ?? 0
        let isFocused = args["isFocused"] as? Bool ?? false
        let cameraRunning = args["cameraRunning"] as? Bool ?? false
        let statusLabel = args["statusLabel"] as? String ?? "Canlı analiz açık"

        controller.update(
          frameData: frame,
          focusScore: focusScore,
          isFocused: isFocused,
          cameraRunning: cameraRunning,
          statusLabel: statusLabel
        )
        result(nil)
      case "appFocusState":
        let keyWindow = NSApplication.shared.keyWindow
        let keyIsAppWindow = keyWindow != nil && !(keyWindow is NSPanel)
        let mainVisible = NSApplication.shared.windows.contains { window in
          window is MainFlutterWindow && window.isVisible && !window.isMiniaturized
        }
        let isActive = NSApplication.shared.isActive

        result([
          "isActive": isActive,
          "hasKeyWindow": keyIsAppWindow,
          "mainVisible": mainVisible,
          "shouldUseInApp": isActive && keyIsAppWindow && mainVisible
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func notifyClosed() {
    channel?.invokeMethod("closed", arguments: nil)
  }
}

final class MiniCameraDragView: NSView {
  private var dragOffset: NSPoint?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    dragOffset = event.locationInWindow
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window = self.window, let dragOffset = dragOffset else { return }

    let mouse = NSEvent.mouseLocation
    window.setFrameOrigin(
      NSPoint(
        x: mouse.x - dragOffset.x,
        y: mouse.y - dragOffset.y
      )
    )
  }
}

final class MiniCameraImageView: NSImageView {
  override var intrinsicContentSize: NSSize {
    NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
  }

  private var dragOffset: NSPoint?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    dragOffset = event.locationInWindow
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window = self.window, let dragOffset = dragOffset else { return }

    let mouse = NSEvent.mouseLocation
    window.setFrameOrigin(
      NSPoint(
        x: mouse.x - dragOffset.x,
        y: mouse.y - dragOffset.y
      )
    )
  }
}

final class MiniCameraResizeHandle: NSView {
  private var startMouse: NSPoint?
  private var startFrame: NSRect?
  var minSize = NSSize(width: 72, height: 41)
  var maxSize = NSSize(width: 220, height: 124)

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .resizeLeftRight)
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)

    let stroke = NSColor.white.withAlphaComponent(0.38)
    stroke.setStroke()

    let path = NSBezierPath()
    path.lineWidth = 1.2

    path.move(to: NSPoint(x: bounds.maxX - 12, y: bounds.minY + 5))
    path.line(to: NSPoint(x: bounds.maxX - 5, y: bounds.minY + 12))
    path.move(to: NSPoint(x: bounds.maxX - 17, y: bounds.minY + 5))
    path.line(to: NSPoint(x: bounds.maxX - 5, y: bounds.minY + 17))
    path.stroke()
  }

  override func mouseDown(with event: NSEvent) {
    startMouse = NSEvent.mouseLocation
    startFrame = window?.frame
  }

  override func mouseDragged(with event: NSEvent) {
    guard let window = window,
          let startMouse = startMouse,
          let startFrame = startFrame else { return }

    let mouse = NSEvent.mouseLocation
    let delta = mouse.x - startMouse.x
    let width = min(maxSize.width, max(minSize.width, startFrame.width + delta))
    let height = round(width * 9 / 16)
    let frame = NSRect(
      x: startFrame.origin.x,
      y: startFrame.origin.y + (startFrame.height - height),
      width: width,
      height: height
    )

    window.setFrame(frame, display: true, animate: false)
  }
}

final class MiniCameraPanelController: NSObject {
  private let defaultPanelSize = NSSize(width: 295, height: 166)
  private let minPanelSize = NSSize(width: 193, height: 109)
  private let maxPanelSize = NSSize(width: 456, height: 257)
  private var panel: NSPanel?
  private let imageView = MiniCameraImageView()
  private let dragOverlay = MiniCameraDragView()
  private let titleLabel = NSTextField(labelWithString: "Mini kamera")
  private let scoreLabel = NSTextField(labelWithString: "--%")
  private let statusDot = NSView()
  private let badgeView = NSView()
  private let placeholderLabel = NSTextField(labelWithString: "Görüntü bekleniyor")
  private let resizeHandle = MiniCameraResizeHandle()

  func show() {
    let wasVisible = panel?.isVisible == true

    if panel == nil {
      buildPanel()
    }

    if let panel = panel {
      panel.contentMinSize = minPanelSize
      panel.contentMaxSize = maxPanelSize
      panel.contentAspectRatio = NSSize(width: 16, height: 9)
      panel.minSize = minPanelSize
      panel.maxSize = maxPanelSize

      if !wasVisible || !isFrameVisible(panel.frame) {
        centerPanel(panel)
      } else {
        clampPanel(panel, resetOversized: true)
      }
    }

    panel?.orderFrontRegardless()

    if let panel = panel {
      if !isFrameVisible(panel.frame) {
        centerPanel(panel)
      } else {
        clampPanel(panel, resetOversized: true)
      }
    }
  }

  func hide() {
    panel?.orderOut(nil)
  }

  func update(
    frameData: Data?,
    focusScore: Double,
    isFocused: Bool,
    cameraRunning: Bool,
    statusLabel: String
  ) {
    if panel == nil || panel?.isVisible != true {
      show()
    }

    scoreLabel.stringValue = cameraRunning
      ? "\(Int(focusScore.rounded()))%"
      : "Kapalı"

    titleLabel.stringValue = cameraRunning
      ? statusLabel
      : "Kamera kapalı"

    let statusColor: NSColor

    if !cameraRunning {
      statusColor = NSColor.systemGray
    } else if statusLabel.contains("Kişi") || statusLabel.contains("Ekran") || statusLabel.contains("Beklemede") {
      statusColor = NSColor.systemGray
    } else if focusScore >= 85 {
      statusColor = NSColor.systemGreen
    } else if focusScore >= 70 {
      statusColor = NSColor.systemGreen
    } else if focusScore >= 50 {
      statusColor = NSColor.systemYellow
    } else if focusScore >= 30 {
      statusColor = NSColor.systemOrange
    } else {
      statusColor = NSColor.systemRed
    }

    statusDot.layer?.backgroundColor = statusColor.cgColor

    if let frameData, let image = NSImage(data: frameData) {
      imageView.image = image
      imageView.invalidateIntrinsicContentSize()
      placeholderLabel.isHidden = true
    } else {
      placeholderLabel.isHidden = false
    }

    if let panel = panel {
      clampPanel(panel, resetOversized: true)
    }
  }

  private func buildPanel() {
    let panelSize = defaultPanelSize
    let frame = centeredFrame(size: panelSize)
    let panel = NSPanel(
      contentRect: frame,
      styleMask: [.borderless, .resizable, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )

    panel.title = "FocusVision Mini Camera"
    panel.becomesKeyOnlyIfNeeded = true
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = false
    panel.acceptsMouseMovedEvents = true
    panel.isReleasedWhenClosed = false
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.backgroundColor = .clear
    panel.isOpaque = false
    panel.hasShadow = true
    panel.contentMinSize = minPanelSize
    panel.contentMaxSize = maxPanelSize
    panel.contentAspectRatio = NSSize(width: 16, height: 9)
    panel.minSize = minPanelSize
    panel.maxSize = maxPanelSize

    let root = MiniCameraDragView(frame: NSRect(x: 0, y: 0, width: panelSize.width, height: panelSize.height))
    root.autoresizingMask = [.width, .height]
    root.wantsLayer = true
    root.layer?.cornerRadius = 12
    root.layer?.masksToBounds = true
    root.layer?.backgroundColor = NSColor(calibratedWhite: 0.03, alpha: 0.96).cgColor
    root.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    root.layer?.borderWidth = 1

    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
    imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 12
    imageView.layer?.masksToBounds = true
    imageView.layer?.backgroundColor = NSColor.black.cgColor
    imageView.refusesFirstResponder = true

    dragOverlay.translatesAutoresizingMaskIntoConstraints = false
    dragOverlay.wantsLayer = true
    dragOverlay.layer?.backgroundColor = NSColor.clear.cgColor

    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
    placeholderLabel.textColor = NSColor.white.withAlphaComponent(0.72)
    placeholderLabel.font = .systemFont(ofSize: 7.5, weight: .semibold)

    statusDot.translatesAutoresizingMaskIntoConstraints = false
    statusDot.wantsLayer = true
    statusDot.layer?.cornerRadius = 3.5
    statusDot.layer?.backgroundColor = NSColor.systemGray.cgColor

    resizeHandle.translatesAutoresizingMaskIntoConstraints = false
    resizeHandle.wantsLayer = true
    resizeHandle.minSize = minPanelSize
    resizeHandle.maxSize = maxPanelSize
    resizeHandle.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.08).cgColor
    resizeHandle.layer?.cornerRadius = 7

    let closeButton = NSButton(
      title: "×",
      target: self,
      action: #selector(closeTapped)
    )
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    closeButton.isBordered = false
    closeButton.bezelStyle = .regularSquare
    closeButton.contentTintColor = NSColor.white.withAlphaComponent(0.92)
    closeButton.font = .systemFont(ofSize: 8, weight: .bold)

    root.addSubview(imageView)
    root.addSubview(dragOverlay)
    root.addSubview(placeholderLabel)
    root.addSubview(statusDot)
    root.addSubview(closeButton)
    root.addSubview(resizeHandle)

    NSLayoutConstraint.activate([
      imageView.topAnchor.constraint(equalTo: root.topAnchor),
      imageView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      imageView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      imageView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      dragOverlay.topAnchor.constraint(equalTo: root.topAnchor),
      dragOverlay.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      dragOverlay.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      dragOverlay.bottomAnchor.constraint(equalTo: root.bottomAnchor),

      placeholderLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
      placeholderLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

      statusDot.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 5),
      statusDot.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -5),
      statusDot.widthAnchor.constraint(equalToConstant: 6),
      statusDot.heightAnchor.constraint(equalToConstant: 6),

      closeButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 3),
      closeButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -3),
      closeButton.widthAnchor.constraint(equalToConstant: 14),
      closeButton.heightAnchor.constraint(equalToConstant: 14),

      resizeHandle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -2),
      resizeHandle.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -2),
      resizeHandle.widthAnchor.constraint(equalToConstant: 24),
      resizeHandle.heightAnchor.constraint(equalToConstant: 24),
    ])

    panel.contentView = root
    self.panel = panel
  }

  private func centeredFrame(size: NSSize) -> NSRect {
    let screen = NSScreen.main ?? NSScreen.screens.first
    let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let origin = NSPoint(
      x: visibleFrame.midX - size.width / 2,
      y: visibleFrame.midY - size.height / 2
    )

    return NSRect(origin: origin, size: size)
  }

  private func centerPanel(_ panel: NSPanel) {
    panel.setFrame(
      centeredFrame(size: defaultPanelSize),
      display: true,
      animate: false
    )
  }

  private func clampPanel(_ panel: NSPanel, resetOversized: Bool) {
    let current = panel.frame
    let targetSize: NSSize

    if resetOversized &&
      (current.width > maxPanelSize.width || current.height > maxPanelSize.height) {
      targetSize = defaultPanelSize
    } else {
      let width = min(maxPanelSize.width, max(minPanelSize.width, current.width))
      let height = min(maxPanelSize.height, max(minPanelSize.height, round(width * 9 / 16)))
      targetSize = NSSize(width: width, height: height)
    }

    if abs(current.width - targetSize.width) < 0.5 &&
      abs(current.height - targetSize.height) < 0.5 {
      return
    }

    let origin = NSPoint(
      x: current.origin.x,
      y: current.origin.y + max(0, current.height - targetSize.height)
    )

    panel.setContentSize(targetSize)
    panel.setFrame(
      NSRect(origin: origin, size: targetSize),
      display: true,
      animate: false
    )
  }

  private func isFrameVisible(_ frame: NSRect) -> Bool {
    return NSScreen.screens.contains { screen in
      let intersection = screen.visibleFrame.intersection(frame)
      return intersection.width >= 48 && intersection.height >= 36
    }
  }

  @objc private func closeTapped() {
    hide()
    MiniCameraChannel.notifyClosed()
  }
}
