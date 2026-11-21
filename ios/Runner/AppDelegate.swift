import Flutter
import Photos
import SwiftUI
import UIKit
import UserNotifications
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Amíg az app fut, ne aludjon el a kijelző (pózolás / nézéses
    // navigáció közben senki sem érinti a képernyőt).
    application.isIdleTimerDisabled = true
    // Értesítések: engedélykérés, és hogy az app előtérben is mutassa őket.
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      _, _ in
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Az értesítés az app előtérben is jelenjen meg.
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .sound])
  }

  // Koppintás az értesítésre → az app a főoldalon nyílik meg (ott lehet
  // kiválasztani, hány játékos van).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.identifier == StandUpReminder.id {
      StandUpReminder.shared.openHome()
    }
    completionHandler()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VisionPosePlugin") {
      VisionPosePlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhotoSaverPlugin") {
      PhotoSaver.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SharePlugin") {
      ShareSheet.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "StandUpPlugin") {
      StandUpReminder.shared.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlassTextPlugin") {
      registrar.register(GlassTextFactory(), withId: "projekt/glass_text")
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "GlassButtonPlugin") {
      registrar.register(
        GlassButtonFactory(messenger: registrar.messenger()), withId: "projekt/glass_button")
    }
  }
}

/// Apple Vision testpóz-felismerés több emberre.
///
/// Dart → `detect` (bytes: BGRA8888, width, height, bytesPerRow, face) →
/// `{people: [[ [név, x, y, confidence], … ], …], face: […]?}` pixelben,
/// bal-felső origóval. Ha `face` igaz, az arcok is jönnek (`faces`), arconként
/// `[cx, cy, szélesség, magasság, hx, hy, …arckifejezés]`, ahol `hx`/`hy` az
/// orr eltolódása a két szem közepétől, a szemtávolsághoz mérve (a fej
/// iránya); utána (ha megvannak a pontok) az arckifejezés hat mérőszáma.

final class VisionPosePlugin: NSObject {
  private let queue = DispatchQueue(label: "vision.pose", qos: .userInitiated)

  /// Vision ízület → a Dart oldali `BodyPoint` neve.
  private static let joints: [(VNHumanBodyPoseObservation.JointName, String)] = [
    (.nose, "nose"),
    (.leftEye, "leftEye"), (.rightEye, "rightEye"),
    (.leftEar, "leftEar"), (.rightEar, "rightEar"),
    (.leftShoulder, "leftShoulder"), (.rightShoulder, "rightShoulder"),
    (.leftElbow, "leftElbow"), (.rightElbow, "rightElbow"),
    (.leftWrist, "leftWrist"), (.rightWrist, "rightWrist"),
    (.leftHip, "leftHip"), (.rightHip, "rightHip"),
    (.leftKnee, "leftKnee"), (.rightKnee, "rightKnee"),
    (.leftAnkle, "leftAnkle"), (.rightAnkle, "rightAnkle"),
  ]

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "projekt/vision_pose", binaryMessenger: registrar.messenger())
    let instance = VisionPosePlugin()
    channel.setMethodCallHandler { call, result in
      instance.handle(call, result: result)
    }
    // A csatorna erősen tartja a handlert, így az instance is él.
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "detect",
      let args = call.arguments as? [String: Any],
      let data = args["bytes"] as? FlutterStandardTypedData,
      let width = args["width"] as? Int,
      let height = args["height"] as? Int,
      let bytesPerRow = args["bytesPerRow"] as? Int
    else {
      result(FlutterMethodNotImplemented)
      return
    }

    let wantFace = args["face"] as? Bool ?? false
    let handCount = args["hands"] as? Int ?? 0
    queue.async {
      let out = Self.detect(
        bytes: data.data, width: width, height: height, bytesPerRow: bytesPerRow,
        wantFace: wantFace, handCount: handCount)
      DispatchQueue.main.async { result(out) }
    }
  }

  private static func detect(
    bytes: Data, width: Int, height: Int, bytesPerRow: Int, wantFace: Bool,
    handCount: Int
  ) -> [String: Any] {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
      nil, &pixelBuffer)
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return [:] }

    CVPixelBufferLockBaseAddress(buffer, [])
    if let dst = CVPixelBufferGetBaseAddress(buffer) {
      let dstRow = CVPixelBufferGetBytesPerRow(buffer)
      bytes.withUnsafeBytes { raw in
        guard let src = raw.baseAddress else { return }
        let rowBytes = min(dstRow, bytesPerRow)
        for y in 0..<height {
          memcpy(dst + y * dstRow, src + y * bytesPerRow, rowBytes)
        }
      }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])

    // A kamera plugin iOS-en már álló (és elülső kameránál tükrözött)
    // puffert ad, ezért nincs forgatás.
    let request = VNDetectHumanBodyPoseRequest()
    let faceRequest = VNDetectFaceLandmarksRequest()
    let handRequest = VNDetectHumanHandPoseRequest()
    handRequest.maximumHandCount = max(handCount, 1)
    var requests: [VNRequest] = [request]
    if wantFace { requests.append(faceRequest) }
    if handCount > 0 { requests.append(handRequest) }
    let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
    do {
      try handler.perform(requests)
    } catch {
      return [:]
    }

    let w = Double(width), h = Double(height)
    var people: [[[Any]]] = []
    for observation in request.results ?? [] {
      guard let points = try? observation.recognizedPoints(.all) else { continue }
      var person: [[Any]] = []
      for (joint, name) in joints {
        guard let p = points[joint], p.confidence > 0 else { continue }
        // Vision: normalizált, bal-alsó origó → pixel, bal-felső origó.
        person.append([name, Double(p.location.x) * w, (1 - Double(p.location.y)) * h,
                       Double(p.confidence)])
      }
      if !person.isEmpty { people.append(person) }
    }

    var out: [String: Any] = ["people": people]
    if wantFace {
      out["faces"] = (faceRequest.results ?? []).compactMap {
        faceData($0, width: w, height: h)
      }
    }
    if handCount > 0 {
      out["hands"] = (handRequest.results ?? []).compactMap {
        handData($0, width: w, height: h)
      }
    }
    return out
  }

  /// Egy arc: középpont, méret és a fej iránya (az orr eltolódása a szemek
  /// közepétől, szemtávolságban; x jobbra, y lefelé – képpixelben), utána
  /// (ha megvannak a pontok) az arckifejezés mérőszámai.
  private static func faceData(
    _ face: VNFaceObservation, width w: Double, height h: Double
  ) -> [Double]? {
    guard
      let landmarks = face.landmarks,
      let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
      let nose = landmarks.nose
    else { return nil }

    let size = CGSize(width: w, height: h)
    func center(_ region: VNFaceLandmarkRegion2D) -> CGPoint {
      let pts = region.pointsInImage(imageSize: size)
      guard !pts.isEmpty else { return .zero }
      let sx = pts.reduce(0) { $0 + $1.x }, sy = pts.reduce(0) { $0 + $1.y }
      // Vision: bal-alsó origó → bal-felső.
      return CGPoint(x: sx / CGFloat(pts.count), y: CGFloat(h) - sy / CGFloat(pts.count))
    }
    let le = center(leftEye), re = center(rightEye), n = center(nose)
    let eyeMid = CGPoint(x: (le.x + re.x) / 2, y: (le.y + re.y) / 2)
    let eyeDist = hypot(le.x - re.x, le.y - re.y)
    guard eyeDist > 1 else { return nil }

    let box = face.boundingBox
    var out: [Double] = [
      Double(box.midX) * w, (1 - Double(box.midY)) * h,
      Double(box.width) * w, Double(box.height) * h,
      Double((n.x - eyeMid.x) / eyeDist), Double((n.y - eyeMid.y) / eyeDist),
    ]
    if let m = expressionMetrics(landmarks, size: size, eyeDist: eyeDist) {
      out.append(contentsOf: m)
    }
    return out
  }

  /// Arckifejezés-mérőszámok (mind a szemtávolsághoz vagy a szájhoz mérve,
  /// így függetlenek az arc méretétől):
  /// `[szájszélesség, szájnyitás, mosoly-ív, bal szem, jobb szem, szemöldök]`.
  private static func expressionMetrics(
    _ lm: VNFaceLandmarks2D, size: CGSize, eyeDist: CGFloat
  ) -> [Double]? {
    func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] {
      // bal-felső origóra fordítva
      r?.pointsInImage(imageSize: size).map { CGPoint(x: $0.x, y: size.height - $0.y) } ?? []
    }
    func span(_ p: [CGPoint]) -> (w: CGFloat, h: CGFloat, cy: CGFloat) {
      let xs = p.map(\.x), ys = p.map(\.y)
      return (
        (xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0),
        ys.reduce(0, +) / CGFloat(max(ys.count, 1))
      )
    }
    let outer = pts(lm.outerLips), inner = pts(lm.innerLips)
    let lEye = pts(lm.leftEye), rEye = pts(lm.rightEye)
    let lBrow = pts(lm.leftEyebrow), rBrow = pts(lm.rightEyebrow)
    guard outer.count >= 4, inner.count >= 2, lEye.count >= 3, rEye.count >= 3,
      !lBrow.isEmpty, !rBrow.isEmpty
    else { return nil }

    let mouth = span(outer)
    guard mouth.w > 1 else { return nil }
    // Szájszélek: a legbalabb és legjobbra eső ajakpont.
    let cornerL = outer.min(by: { $0.x < $1.x })!, cornerR = outer.max(by: { $0.x < $1.x })!
    // Mosoly: a szájszélek a száj közepe fölé húzódnak (y lefelé nő).
    let smileCurve = (mouth.cy - (cornerL.y + cornerR.y) / 2) / eyeDist
    let mouthOpen = span(inner).h / mouth.w

    func openness(_ e: [CGPoint]) -> CGFloat {
      let s = span(e)
      return s.w > 0 ? s.h / s.w : 0
    }
    let le = span(lEye), re = span(rEye)
    let brow = ((le.cy - span(lBrow).cy) + (re.cy - span(rBrow).cy)) / 2 / eyeDist

    return [
      Double(mouth.w / eyeDist), Double(mouthOpen), Double(smileCurve),
      Double(openness(lEye)), Double(openness(rEye)), Double(brow),
    ]
  }

  /// A kéz 21 pontja ebben a sorrendben (a Dart oldali rajzoló is így várja).
  private static let handJoints: [VNHumanHandPoseObservation.JointName] = [
    .wrist,
    .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
    .indexMCP, .indexPIP, .indexDIP, .indexTip,
    .middleMCP, .middlePIP, .middleDIP, .middleTip,
    .ringMCP, .ringPIP, .ringDIP, .ringTip,
    .littleMCP, .littlePIP, .littleDIP, .littleTip,
  ]

  /// Egy kéz: `[csukló x, csukló y, megbízhatóság, hüvelyk, mutató, középső,
  /// gyűrűs, kisujj, …21 × (x, y, conf)]` – az ujjaknál mennyire van
  /// kinyújtva (-1, ha nem látszik), utána a 21 pont a rajzoláshoz.
  ///
  /// Ujjanként: az ujjhegy csuklótól mért távolsága az alapízületéhez képest
  /// (nyújtva ~1,8–2, behajlítva ~1–1,2). Hüvelykujj: a hegye milyen messze
  /// van a mutatóujj tövétől, a tenyér méretéhez képest.
  ///
  /// A Vision kézpontjai gyakran alacsony megbízhatóságúak (0,1–0,4) akkor
  /// is, ha jó helyen vannak – ezért már 0,1 fölött elfogadjuk őket.
  private static func handData(
    _ hand: VNHumanHandPoseObservation, width w: Double, height h: Double
  ) -> [Double]? {
    let minConf: Float = 0.1
    guard let pts = try? hand.recognizedPoints(.all),
      let wrist = pts[.wrist], wrist.confidence > minConf
    else { return nil }
    func px(_ p: VNRecognizedPoint) -> CGPoint {
      CGPoint(x: p.location.x * w, y: (1 - p.location.y) * h)
    }
    // Az ítélethez (ujjak nyújtottsága) csak a megbízható pontok számítanak;
    // a rajzoláshoz a bizonytalanabbak is.
    func ok(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
      guard let p = pts[j], p.confidence > 0.3 else { return nil }
      return px(p)
    }
    let wr = px(wrist)
    func ratio(
      _ base: VNHumanHandPoseObservation.JointName, _ tip: VNHumanHandPoseObservation.JointName
    ) -> Double {
      guard let b = ok(base), let t = ok(tip) else { return -1 }
      let db = hypot(b.x - wr.x, b.y - wr.y)
      return db > 1 ? Double(hypot(t.x - wr.x, t.y - wr.y) / db) : -1
    }
    var thumb = -1.0
    if let tt = ok(.thumbTip), let im = ok(.indexMCP) {
      let palm = hypot(im.x - wr.x, im.y - wr.y)
      if palm > 1 { thumb = Double(hypot(tt.x - im.x, tt.y - im.y) / palm) }
    }
    var out: [Double] = [
      Double(wr.x), Double(wr.y), Double(hand.confidence),
      thumb,
      ratio(.indexMCP, .indexTip), ratio(.middleMCP, .middleTip),
      ratio(.ringMCP, .ringTip), ratio(.littleMCP, .littleTip),
    ]
    for j in handJoints {
      if let p = pts[j], p.confidence > minConf {
        let q = px(p)
        out.append(contentsOf: [Double(q.x), Double(q.y), Double(p.confidence)])
      } else {
        out.append(contentsOf: [0, 0, 0])
      }
    }
    return out
  }
}

// MARK: - Liquid Glass gomb

/// Natív Liquid Glass gomb (iOS 26+: `.glass()` / `.prominentGlass()`,
/// régebbin sima kitöltött gomb) SF Symbol ikonnal és felirattal.
final class GlassButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    GlassButtonView(
      frame: frame, viewId: viewId, params: args as? [String: Any] ?? [:],
      messenger: messenger)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class GlassButtonView: NSObject, FlutterPlatformView {
  private let container: UIView
  private let button = UIButton(type: .system)
  private let channel: FlutterMethodChannel

  init(frame: CGRect, viewId: Int64, params: [String: Any], messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    container.backgroundColor = .clear
    container.overrideUserInterfaceStyle = .dark
    channel = FlutterMethodChannel(
      name: "projekt/glass_button_\(viewId)", binaryMessenger: messenger)
    super.init()

    button.frame = container.bounds
    button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    button.addTarget(self, action: #selector(onTap), for: .touchUpInside)
    container.addSubview(button)
    apply(params)

    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "update", let p = call.arguments as? [String: Any] {
        self?.apply(p)
      }
      result(nil)
    }
  }

  func view() -> UIView { container }

  @objc private func onTap() {
    channel.invokeMethod("pressed", arguments: nil)
  }

  private func apply(_ p: [String: Any]) {
    let title = p["title"] as? String ?? ""
    let symbol = p["symbol"] as? String
    let prominent = p["prominent"] as? Bool ?? true
    let enabled = p["enabled"] as? Bool ?? true
    let fontSize = CGFloat((p["fontSize"] as? NSNumber)?.doubleValue ?? 20)
    let tint = (p["tint"] as? NSNumber).map { Self.color(argb: $0.int64Value) }

    var config: UIButton.Configuration
    if #available(iOS 26.0, *) {
      config = prominent ? .prominentGlass() : .glass()
    } else {
      config = prominent ? .filled() : .gray()
    }
    config.cornerStyle = .capsule
    config.baseForegroundColor = .white
    if let tint {
      button.tintColor = tint
      if prominent { config.baseBackgroundColor = tint }
    }
    if !title.isEmpty {
      config.attributedTitle = AttributedString(
        title,
        attributes: AttributeContainer([
          .font: UIFont.systemFont(ofSize: fontSize, weight: .bold)
        ]))
    }
    if let symbol {
      config.image = UIImage(
        systemName: symbol,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: fontSize, weight: .bold))
      config.imagePlacement = .leading
      config.imagePadding = 10
    }
    button.configuration = config
    button.isEnabled = enabled
    // Címkeként (pl. a póz neve) nem reagál érintésre, de teljes színű marad.
    button.isUserInteractionEnabled = p["interactive"] as? Bool ?? true
  }

  private static func color(argb: Int64) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255)
  }
}

// MARK: - Fotó mentése

/// `save` (PNG bájtok) → a kép a Fotók appba kerül. `true`, ha sikerült.
enum PhotoSaver {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "projekt/photos", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "save",
        let data = (call.arguments as? FlutterStandardTypedData)?.data,
        let image = UIImage(data: data)
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      save(image) { ok in DispatchQueue.main.async { result(ok) } }
    }
  }

  private static func save(_ image: UIImage, done: @escaping (Bool) -> Void) {
    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      guard status == .authorized || status == .limited else {
        done(false)
        return
      }
      PHPhotoLibrary.shared().performChanges({
        PHAssetCreationRequest.creationRequestForAsset(from: image)
      }) { ok, _ in done(ok) }
    }
  }
}

// MARK: - Liquid Glass betűk

/// A felirat betűinek körvonala SwiftUI alakzatként – erre kerül a valódi
/// Liquid Glass anyag (`glassEffect(in:)`). A betűket a kapott téglalapba
/// illeszti, arányosan, balra igazítva.
struct GlyphShape: Shape {
  let text: String
  let fontSize: CGFloat

  func path(in rect: CGRect) -> Path {
    let font = UIFont.systemFont(ofSize: fontSize, weight: .black)
    let line = CTLineCreateWithAttributedString(
      NSAttributedString(string: text, attributes: [.font: font]))
    let glyphs = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
      let attrs = CTRunGetAttributes(run) as NSDictionary
      let runFont = attrs[kCTFontAttributeName as String] as! CTFont
      let count = CTRunGetGlyphCount(run)
      var ids = [CGGlyph](repeating: 0, count: count)
      var positions = [CGPoint](repeating: .zero, count: count)
      CTRunGetGlyphs(run, CFRange(location: 0, length: count), &ids)
      CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
      for i in 0..<count {
        guard let g = CTFontCreatePathForGlyph(runFont, ids[i], nil) else { continue }
        glyphs.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
      }
    }
    let b = glyphs.boundingBoxOfPath
    guard b.width > 0, b.height > 0 else { return Path() }
    // A betűk y-felfelé állnak: tükrözzük, és arányosan a téglalapba tesszük.
    let scale = min(rect.width / b.width, rect.height / b.height)
    var t = CGAffineTransform(translationX: rect.minX, y: rect.midY + b.height * scale / 2)
      .scaledBy(x: scale, y: -scale)
      .translatedBy(x: -b.minX, y: -b.minY)
    return Path(glyphs.copy(using: &t) ?? glyphs)
  }
}

struct GlassTextView: View {
  let text: String
  let fontSize: CGFloat
  let tint: Color

  var body: some View {
    let shape = GlyphShape(text: text, fontSize: fontSize)
    if #available(iOS 26.0, *) {
      Color.clear
        .glassEffect(.regular.tint(tint), in: shape)
        .overlay(shape.stroke(Color.white.opacity(0.35), lineWidth: 0.8))
    } else {
      shape.fill(
        LinearGradient(
          colors: [Color.white.opacity(0.9), tint], startPoint: .top, endPoint: .bottom))
    }
  }
}

final class GlassTextFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?
  ) -> FlutterPlatformView {
    GlassTextPlatformView(frame: frame, params: args as? [String: Any] ?? [:])
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class GlassTextPlatformView: NSObject, FlutterPlatformView {
  private let host: UIHostingController<GlassTextView>

  init(frame: CGRect, params: [String: Any]) {
    let argb = (params["tint"] as? NSNumber)?.int64Value ?? 0xB3B9A598
    let tint = Color(
      red: Double((argb >> 16) & 0xFF) / 255,
      green: Double((argb >> 8) & 0xFF) / 255,
      blue: Double(argb & 0xFF) / 255,
      opacity: Double((argb >> 24) & 0xFF) / 255)
    host = UIHostingController(
      rootView: GlassTextView(
        text: params["text"] as? String ?? "",
        fontSize: CGFloat((params["fontSize"] as? NSNumber)?.doubleValue ?? 44),
        tint: tint))
    host.view.frame = frame
    host.view.backgroundColor = .clear
    host.view.overrideUserInterfaceStyle = .dark
    super.init()
  }

  func view() -> UIView { host.view }
}

// MARK: - Megosztás

/// `share` ({png, text}) → az iOS megosztó lapja a képpel és a szöveggel.
enum ShareSheet {
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "projekt/share", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { call, result in
      guard call.method == "share",
        let args = call.arguments as? [String: Any],
        let data = (args["png"] as? FlutterStandardTypedData)?.data,
        let image = UIImage(data: data)
      else {
        result(FlutterMethodNotImplemented)
        return
      }
      let text = args["text"] as? String ?? ""
      guard let top = topViewController() else {
        result(false)
        return
      }
      let sheet = UIActivityViewController(
        activityItems: [image, text], applicationActivities: nil)
      // iPaden popoverként kell megjeleníteni.
      sheet.popoverPresentationController?.sourceView = top.view
      sheet.popoverPresentationController?.sourceRect = CGRect(
        x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
      sheet.completionWithItemsHandler = { _, completed, _, _ in result(completed) }
      top.present(sheet, animated: true)
    }
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
      ?? scene?.windows.first?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

// MARK: - „Állj fel!" emlékeztető

/// Helyi értesítés: „Stand up! … strike a pose". A Dart oldal ütemezi
/// (`schedule`: seconds, title, body) és törli (`cancel`); koppintásra az
/// app a főoldalon nyílik meg (`openHome` → Dart). Ha az app az értesítésre
/// koppintva indul el, eleve a főoldalon indul.
final class StandUpReminder {
  static let shared = StandUpReminder()
  static let id = "snapit.standup"

  private var channel: FlutterMethodChannel?

  func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "projekt/standup", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return result(nil) }
      switch call.method {
      case "schedule":
        let args = call.arguments as? [String: Any] ?? [:]
        self.schedule(
          after: (args["seconds"] as? NSNumber)?.doubleValue ?? 30,
          title: args["title"] as? String ?? "",
          body: args["body"] as? String ?? "")
        result(nil)
      case "cancel":
        UNUserNotificationCenter.current().removePendingNotificationRequests(
          withIdentifiers: [Self.id])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func schedule(after seconds: Double, title: String, body: String) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.sound = .default
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
    let request = UNNotificationRequest(identifier: Self.id, content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request)
  }

  func openHome() {
    channel?.invokeMethod("openHome", arguments: nil)
  }
}
