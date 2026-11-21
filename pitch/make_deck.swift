// Snap It! – 5 oldalas pitch deck PDF-ben.
// Futtatás a projekt gyökeréből:  swift pitch/make_deck.swift
// A képernyőképeket a pitch/screens/ mappából veszi (1.jpg … 6.jpg, fekvő,
// már helyesen elforgatva); ha valamelyik hiányzik, helyőrző jelenik meg.

import AppKit
import CoreGraphics

let root = FileManager.default.currentDirectoryPath
let outURL = URL(fileURLWithPath: "\(root)/pitch/SnapIt_pitch.pdf")
let W: CGFloat = 1920, H: CGFloat = 1080

// ── Színek ──
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let bg = rgb(0x0B0E13)
let card = rgb(0x141922)
let line = rgb(0x2A3140)
let white = rgb(0xF4F1EE)
let muted = rgb(0x9AA3B2)
let brand = rgb(0xDCCBBE)  // a logó üvegének világos tónusa
let brandDeep = rgb(0x9C8475)
let green = rgb(0x4CD964)

// ── Rajzoló segédek (fentről lefelé növő y) ──
var ctx: CGContext!

func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
  NSFont.systemFont(ofSize: size, weight: weight)
}

@discardableResult
func text(
  _ s: String, _ x: CGFloat, _ y: CGFloat, w: CGFloat, size: CGFloat,
  weight: NSFont.Weight = .regular, color: NSColor = white, align: NSTextAlignment = .left,
  lineSpacing: CGFloat = 4
) -> CGFloat {
  let p = NSMutableParagraphStyle()
  p.alignment = align
  p.lineSpacing = lineSpacing
  let attr = NSAttributedString(
    string: s,
    attributes: [.font: font(size, weight), .foregroundColor: color, .paragraphStyle: p])
  let bounds = attr.boundingRect(
    with: NSSize(width: w, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
  attr.draw(
    with: NSRect(x: x, y: y, width: w, height: ceil(bounds.height) + 4),
    options: [.usesLineFragmentOrigin, .usesFontLeading])
  return ceil(bounds.height)
}

func box(_ r: CGRect, fill: NSColor = card, stroke: NSColor? = line, radius: CGFloat = 22, width: CGFloat = 2) {
  let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
  fill.setFill()
  path.fill()
  if let stroke {
    stroke.setStroke()
    path.lineWidth = width
    path.stroke()
  }
}

func arrow(from a: CGPoint, to b: CGPoint, color: NSColor = brand) {
  let path = NSBezierPath()
  path.move(to: a)
  path.line(to: b)
  path.lineWidth = 4
  color.setStroke()
  path.stroke()
  let ang = atan2(b.y - a.y, b.x - a.x), len: CGFloat = 18
  let head = NSBezierPath()
  head.move(to: b)
  head.line(to: CGPoint(x: b.x - len * cos(ang - 0.45), y: b.y - len * sin(ang - 0.45)))
  head.line(to: CGPoint(x: b.x - len * cos(ang + 0.45), y: b.y - len * sin(ang + 0.45)))
  head.close()
  color.setFill()
  head.fill()
}

let logo = NSImage(contentsOfFile: "\(root)/media/snapit_logo.png")

func image(_ img: NSImage, in r: CGRect, cover: Bool = false, radius: CGFloat = 0) {
  let s = img.size
  let k = cover ? max(r.width / s.width, r.height / s.height) : min(r.width / s.width, r.height / s.height)
  let w = s.width * k, h = s.height * k
  let dst = CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
  NSGraphicsContext.saveGraphicsState()
  if radius > 0 { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).addClip() }
  img.draw(in: dst, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
  NSGraphicsContext.restoreGraphicsState()
}

/// Oldal: háttér, sorszám, cím, alul a márka.
func page(_ number: Int, _ kicker: String, _ title: String, _ body: () -> Void) {
  var box = CGRect(x: 0, y: 0, width: W, height: H)
  ctx.beginPage(mediaBox: &box)
  ctx.saveGState()
  ctx.translateBy(x: 0, y: H)
  ctx.scaleBy(x: 1, y: -1)
  NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)

  bg.setFill()
  CGRect(x: 0, y: 0, width: W, height: H).fill()
  text("\(number)  ·  \(kicker.uppercased())", 96, 70, w: 1200, size: 24, weight: .semibold, color: brand)
  text(title, 96, 108, w: 1600, size: 64, weight: .heavy)
  body()
  // Márka a jobb alsó sarokban.
  if let logo { image(logo, in: CGRect(x: W - 96 - 230, y: H - 92, width: 52, height: 52)) }
  text("Snap It!", W - 96 - 168, H - 82, w: 170, size: 30, weight: .heavy, color: brand)

  NSGraphicsContext.current = nil
  ctx.restoreGState()
  ctx.endPage()
}

// ── Kezdés ──
var media = CGRect(x: 0, y: 0, width: W, height: H)
ctx = CGContext(outURL as CFURL, mediaBox: &media, [
  kCGPDFContextTitle as String: "Snap It! – pitch deck",
  kCGPDFContextAuthor as String: "Snap It! team",
] as CFDictionary)!

// ── 1. Problem and user ──
page(1, "Problem and user", "Two everyday problems") {
  let cw: CGFloat = 820, top: CGFloat = 260, ch: CGFloat = 560
  for (i, item) in [
    (
      "📸", "“What pose should we do?”",
      "At a party, with family, with friends or your partner – everyone freezes in front of the camera. Every photo ends up with the same stiff smile.",
      "Example: a birthday party, ten group photos – and the exact same pose in all of them."
    ),
    (
      "🪑", "Sitting for way too long",
      "Office workers sit in front of a screen for hours. Everyone knows they should stand up for their health – almost nobody actually does.",
      "Example: a team glued to their desks the whole afternoon, without a single break."
    ),
  ].enumerated() {
    let x = 96 + CGFloat(i) * (cw + 88)
    box(CGRect(x: x, y: top, width: cw, height: ch))
    text(item.0, x + 48, top + 44, w: 120, size: 76)
    text(item.1, x + 48, top + 160, w: cw - 96, size: 44, weight: .bold)
    text(item.2, x + 48, top + 250, w: cw - 96, size: 30, color: muted, lineSpacing: 8)
    text(item.3, x + 48, top + 430, w: cw - 96, size: 28, weight: .semibold, color: brand, lineSpacing: 6)
  }
  text(
    "Who has it: friend groups, families, couples – and office teams.", 96, 870, w: 1700,
    size: 34, weight: .semibold)
}

// ── 2. Solution ──
page(2, "Solution", "Snap It! – a pose game that gets you off your chair") {
  text(
    "Snap It! shows you a pose – you strike it in front of your iPhone, and it scores in real time how well you copied it. Play alone, or compete with up to 6 friends or colleagues.",
    96, 230, w: 1700, size: 34, color: muted, lineSpacing: 8)

  let cw: CGFloat = 840, top: CGFloat = 380, ch: CGFloat = 320
  let modes = [
    (
      "Picture mode",
      "Pick Party, Couple, Family or Casual. Snap It! throws a random pose, counts down from 10 and takes the photo at your best moment – saved with your accuracy % and a watermark."
    ),
    (
      "Play mode",
      "Copy famous memes before the clock runs out. Time gets shorter, the minimum score gets higher. 1–6 players head-to-head – then share: “Beat me if you can!”"
    ),
  ]
  for (i, m) in modes.enumerated() {
    let x = 96 + CGFloat(i) * (cw + 48)
    box(CGRect(x: x, y: top, width: cw, height: ch), stroke: brandDeep)
    text(m.0, x + 44, top + 40, w: cw - 88, size: 44, weight: .bold, color: brand)
    text(m.1, x + 44, top + 116, w: cw - 88, size: 30, color: white, lineSpacing: 8)
  }
  let extras = [
    ("🧍", "Stand-up reminders", "A nudge to get off your chair"),
    ("🙂", "Hands-free", "Steer with your head when the phone is propped up"),
    ("🔄", "Any orientation", "Portrait and landscape, auto re-calibrating"),
  ]
  for (i, e) in extras.enumerated() {
    let x = 96 + CGFloat(i) * (560 + 24)
    box(CGRect(x: x, y: 740, width: 560, height: 150), radius: 18)
    text(e.0, x + 28, 770, w: 70, size: 48)
    text(e.1, x + 110, 768, w: 420, size: 30, weight: .bold)
    text(e.2, x + 110, 814, w: 420, size: 22, color: muted)
  }
}

// ── 3. How it works ──
page(3, "How it works", "From camera frame to score – on device") {
  let y: CGFloat = 280, h: CGFloat = 320, gap: CGFloat = 52
  let w: CGFloat = (1728 - 4 * gap) / 5
  let steps = [
    ("Front camera", "Live frames, portrait or landscape"),
    ("Apple Vision", "Body pose (multi-person)\nFace landmarks\nHand pose – 21 points"),
    ("Smoothing &\ntracking", "One-Euro filter, per-player tracking, off-frame limb inference"),
    ("Scorer", "Limb angles + torso + head + facial expression + finger shape → accuracy %"),
  ]
  for (i, s) in steps.enumerated() {
    let x = 96 + CGFloat(i) * (w + gap)
    box(CGRect(x: x, y: y, width: w, height: h), stroke: i == 1 ? brand : line, width: i == 1 ? 3 : 2)
    let th = text(s.0, x + 28, y + 30, w: w - 56, size: 34, weight: .bold, color: i == 1 ? brand : white)
    text(s.1, x + 28, y + 50 + th, w: w - 56, size: 23, color: muted, lineSpacing: 6)
    if i < steps.count - 1 {
      arrow(from: CGPoint(x: x + w + 8, y: y + h / 2), to: CGPoint(x: x + w + gap - 8, y: y + h / 2))
    }
  }
  // Kimenet: a játék.
  let gx = 96 + 4 * (w + gap)
  arrow(from: CGPoint(x: gx - gap + 8, y: y + h / 2), to: CGPoint(x: gx - 8, y: y + h / 2))
  box(CGRect(x: gx, y: y, width: w, height: h), fill: rgb(0x1C2A1F), stroke: green, width: 3)
  text("Game", gx + 28, y + 30, w: w - 56, size: 34, weight: .bold, color: green)
  text(
    "Picture & Play modes, live feedback, photo stamped with the score, share sheet",
    gx + 28, y + 86, w: w - 56, size: 23, color: muted, lineSpacing: 6)

  // Fej-kurzor ág.
  let hy: CGFloat = 690
  box(CGRect(x: 96 + (w + gap), y: hy, width: 2 * w + gap, height: 150), stroke: brandDeep)
  text("Head cursor", 96 + (w + gap) + 28, hy + 24, w: 600, size: 30, weight: .bold, color: brand)
  text(
    "Face → head direction → on-screen cursor. Look at a button for ~1 s to press it. Re-calibrates when the phone rotates.",
    96 + (w + gap) + 28, hy + 70, w: 2 * w + gap - 56, size: 22, color: muted, lineSpacing: 4)
  arrow(from: CGPoint(x: 96 + (w + gap) + w / 2, y: y + h + 8), to: CGPoint(x: 96 + (w + gap) + w / 2, y: hy - 8))

  text(
    "Built with Flutter (iOS) · Swift · Apple Vision · Liquid Glass (iOS 26) · Photos & share sheet · local notifications",
    96, 900, w: 1700, size: 24, color: muted)
}

// ── 4. Screenshots ──
// A (fekvő) képernyőképek a pitch/screens mappából, 1.jpg … 6.jpg sorrendben.
page(4, "Screenshots", "The working product") {
  let dir = "\(root)/pitch/screens"
  let labels = [
    "Home – tap or steer with your head",
    "Play mode – copy the meme",
    "Live scoring for every player",
    "Round result – who’s out?",
    "Game over – the winner",
    "Shared photo – “Beat me if you can!”",
  ]
  let cols = 3, gap: CGFloat = 36
  let fw = (1728 - CGFloat(cols - 1) * gap) / CGFloat(cols)
  let fh = fw / 2.17
  let rowH = fh + 64
  for i in 0..<6 {
    let c = i % cols, r = i / cols
    let rect = CGRect(x: 96 + CGFloat(c) * (fw + gap), y: 250 + CGFloat(r) * (rowH + 24), width: fw, height: fh)
    if let img = NSImage(contentsOfFile: "\(dir)/\(i + 1).jpg") {
      box(rect, fill: .black, stroke: line, radius: 22)
      image(img, in: rect.insetBy(dx: 4, dy: 4), radius: 18)
    } else {
      box(rect, fill: card, stroke: brandDeep, radius: 22, width: 3)
      text("screenshot \(i + 1)", rect.minX, rect.midY - 16, w: rect.width, size: 26,
        weight: .semibold, color: muted, align: .center)
    }
    text(labels[i], rect.minX, rect.maxY + 14, w: rect.width, size: 24,
      weight: .semibold, color: brand, align: .center)
  }
}

// ── 5. Impact and next steps ──
page(5, "Impact and next steps", "Fit, social – and fun") {
  let benefits = [
    ("💪", "Keeps you fit", "Breaks up long sitting – in a fun way, not as a chore."),
    ("🤝", "Social", "A great icebreaker that brings friends, family and colleagues closer."),
    ("🖼️", "Lasting memories", "Photos you actually want to keep – and share."),
    ("🙌", "Hands-free", "Head control when the phone is propped up across the room."),
  ]
  let cw: CGFloat = 405, top: CGFloat = 250
  for (i, b) in benefits.enumerated() {
    let x = 96 + CGFloat(i) * (cw + 36)
    box(CGRect(x: x, y: top, width: cw, height: 300))
    text(b.0, x + 32, top + 28, w: 100, size: 56)
    text(b.1, x + 32, top + 120, w: cw - 64, size: 34, weight: .bold)
    text(b.2, x + 32, top + 172, w: cw - 64, size: 24, color: muted, lineSpacing: 6)
  }
  text("Who benefits", 96, 610, w: 800, size: 34, weight: .bold, color: brand)
  text(
    "Friend groups and families at parties · couples · office teams and HR wellbeing programs",
    96, 660, w: 800, size: 28, color: white, lineSpacing: 8)
  text("Next steps", 1000, 610, w: 820, size: 34, weight: .bold, color: brand)
  text(
    "• Screen Time (Family Controls) – trigger breaks from real screen time\n• More poses and user-made challenges\n• Online leaderboards and office team challenges\n• Android version",
    1000, 660, w: 820, size: 28, color: white, lineSpacing: 10)
}

ctx.closePDF()
print("Kész: \(outURL.path)")
