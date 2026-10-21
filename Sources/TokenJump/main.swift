import AppKit
import SpriteKit

func verify(_ condition: @autoclosure () -> Bool, line: UInt = #line) {
    if !condition() { fputs("FAIL at line \(line)\n", stderr); exit(1) }
}

enum Difficulty: String, CaseIterable {
    case easy, normal, hard
    var title: String { switch self { case .easy: return "쉬움"; case .normal: return "보통"; case .hard: return "하드" } }
    var cost: Int { switch self { case .easy: return 5_000; case .normal: return 10_000; case .hard: return 25_000 } }
    var width: CGFloat { switch self { case .easy: return 120; case .normal: return 90; case .hard: return 60 } }
    var gap: CGFloat { switch self { case .easy: return 72; case .normal: return 85; case .hard: return 95 } }
}
enum Avatar: String, CaseIterable {
    case bit, ember, orbit
    var title: String { switch self { case .bit: return "Bit · 로봇"; case .ember: return "Ember · 여우"; case .orbit: return "Orbit · 외계인" } }
    var color: NSColor { switch self { case .bit: return .systemMint; case .ember: return .systemOrange; case .orbit: return .systemPurple } }
}
struct Stage {
    let name: String
    let xs: [CGFloat]
    let rise: CGFloat
    func width(_ mode: Difficulty) -> CGFloat {
        let index = Stage.all.firstIndex(where: { $0.name == name }) ?? 0
        let hasSpikes = [4, 8, 10, 11].contains(index)
        return max(hasSpikes ? 52 : 32, mode.width * (1 - CGFloat(index) * 0.034))
    }
    static let all: [Stage] = [
        Stage(name: "첫 도약", xs: [210, 245, 200, 250, 195], rise: 0.80),
        Stage(name: "지그재그", xs: [210, 125, 220, 120, 225], rise: 0.85),
        Stage(name: "동쪽 계단", xs: [75, 140, 210, 280, 345], rise: 0.90),
        Stage(name: "서쪽 포격", xs: [330, 220, 110, 220, 105], rise: 0.90),
        Stage(name: "가시 능선", xs: [90, 200, 315, 205, 90], rise: 0.92),
        Stage(name: "동쪽 포격", xs: [90, 215, 340, 215, 90, 220], rise: 0.84),
        Stage(name: "교차로", xs: [320, 190, 60, 190, 320, 190], rise: 0.85),
        Stage(name: "좁은 왕복", xs: [80, 215, 350, 215, 80, 215], rise: 0.86),
        Stage(name: "가시 계곡", xs: [340, 180, 55, 215, 370, 210, 55, 215, 370], rise: 0.70),
        Stage(name: "상단 포격", xs: [60, 220, 370, 210, 50, 210, 370, 210, 50, 210, 370], rise: 0.71),
        Stage(name: "정상 직전", xs: [365, 205, 45, 205, 365, 205, 45, 205, 365, 205, 45, 205], rise: 0.72),
        Stage(name: "토큰 정상", xs: [45, 210, 375, 210, 45, 210, 375, 210, 45, 210, 375, 210, 45], rise: 0.72)
    ]
    func points(_ mode: Difficulty) -> [CGPoint] {
        let number = Stage.all.firstIndex(where: { $0.name == name }) ?? 0
        let route: [CGFloat] = mode == .hard && number < 8 ? (0..<(7 + number / 2)).map { [CGFloat(65), 210, 355, 210][$0 % 4] } : xs
        let spacing = mode == .hard && number < 8 ? CGFloat(0.75) : rise
        return route.enumerated().map { CGPoint(x: $0.element, y: 50 + CGFloat($0.offset) * mode.gap * spacing) }
    }
}
struct Save: Codable {
    var runStarted: Bool?
    var runComplete: Bool?
    var clearedStages: Int?
    var collected: Int?
    var spent: Int?
    var jumpCount: Int?
    var providerTokens: [String: Int]?
    var avatar: String?
    var difficulty: String?
    var stage: Int?
    var credits = 0
    var remainder = 0
    var offsets: [String: UInt64] = [:]
    var totals: [String: Int] = [:]
    var initialized = false
    var best = 0
}
final class Usage {
    var difficulty: Difficulty { Difficulty(rawValue: save.difficulty ?? "normal") ?? .normal }
    var threshold: Int { difficulty.cost }
    var wallet: Int { save.credits * 10_000 + save.remainder }
    var available: Int { wallet / threshold }
    func addTokens(_ count: Int) {
        let total = wallet + count
        save.credits = total / 10_000; save.remainder = total % 10_000
    }
    var canChangeDifficulty: Bool { !(save.runStarted ?? false) || (save.runComplete ?? false) }
    var unlockedStage: Int { min(Stage.all.count, (save.clearedStages ?? 0) + 1) }
    @discardableResult func setDifficulty(_ value: Difficulty) -> Bool {
        guard canChangeDifficulty else { return false }
        save.difficulty = value.rawValue; save.stage = 1; save.clearedStages = 0; save.runStarted = false; save.runComplete = false
        persist(); onChange?(); return true
    }
    @discardableResult func selectStage(_ number: Int) -> Bool {
        guard (1...unlockedStage).contains(number) else { return false }
        save.stage = number; persist(); return true
    }
    func finishStage(_ number: Int) {
        guard number == (save.stage ?? 1), (1...unlockedStage).contains(number) else { return }
        save.clearedStages = max(save.clearedStages ?? 0, number)
        if number == Stage.all.count { save.runComplete = true }
        persist()
    }
    @discardableResult func advanceStage() -> Bool {
        let current = save.stage ?? 1
        guard current < Stage.all.count, current <= (save.clearedStages ?? 0) else { return false }
        return selectStage(current + 1)
    }
    let url: URL
    var save: Save
    var onChange: (() -> Void)?
    init(stateDirectory: URL? = nil) {
        let dir = stateDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TokenJump")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("save.json")
        save = (try? JSONDecoder().decode(Save.self, from: Data(contentsOf: url))) ?? Save()
        if save.clearedStages == nil {
            // Old freely-selected stage numbers are not evidence of a sequential clear.
            save.clearedStages = 0; save.stage = 1; save.runStarted = false; save.runComplete = false; persist()
        }
    }
    func persist() { if let data = try? JSONEncoder().encode(save) { try? data.write(to: url, options: .atomic) } }
    func spend() -> Bool {
        guard wallet >= threshold else { return false }
        save.spent = (save.spent ?? 0) + threshold; save.jumpCount = (save.jumpCount ?? 0) + 1
        addTokens(-threshold); persist(); onChange?(); return true
    }
    func scan(roots: [(URL, Bool)]? = nil) {
        let baseline = !save.initialized
        let home = FileManager.default.homeDirectoryForCurrentUser
        for (root, codex) in roots ?? [(home.appendingPathComponent(".codex/sessions"), true), (home.appendingPathComponent(".claude/projects"), false)] {
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { continue }
            for case let file as URL in files where file.pathExtension == "jsonl" {
                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                defer { try? handle.close() }
                let path = file.path
                let size = (try? handle.seekToEnd()) ?? 0
                if baseline {
                    save.offsets[path] = size
                    if codex {
                        try? handle.seek(toOffset: size > 262144 ? size - 262144 : 0)
                        let tail = (try? handle.readToEnd()) ?? Data()
                        for line in tail.split(separator: 10).reversed() {
                            if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                               let payload = obj["payload"] as? [String: Any], payload["type"] as? String == "token_count",
                               let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any],
                               let count = total["total_tokens"] as? Int { save.totals[path] = count; break }
                        }
                    }
                    continue
                }
                let old = save.offsets[path] ?? 0
                // A replaced or truncated file starts a new stream.
                if old > size { save.totals[path] = nil }
                let start = old <= size ? old : 0
                guard size > start else { continue }
                try? handle.seek(toOffset: start)
                // Bound work per file; unfinished lines are retried next time.
                guard let data = try? handle.read(upToCount: 4 * 1024 * 1024), let end = data.lastIndex(of: 10) else { continue }
                let complete = data.prefix(through: end)
                save.offsets[path] = start + UInt64(complete.count)
                for line in complete.split(separator: 10) {
                    guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else { continue }
                    var tokens = 0
                    if codex {
                        guard let payload = object["payload"] as? [String: Any], payload["type"] as? String == "token_count", let info = payload["info"] as? [String: Any], let total = info["total_token_usage"] as? [String: Any], let count = total["total_tokens"] as? Int else { continue }
                        // First observed cumulative value establishes a baseline for an existing session.
                        if let previous = save.totals[path] { tokens = max(0, count - previous) }
                        else if start == 0 { tokens = count }
                        save.totals[path] = max(save.totals[path] ?? 0, count)
                    } else {
                        guard object["type"] as? String == "assistant", let message = object["message"] as? [String: Any], let usage = message["usage"] as? [String: Any], let id = message["id"] as? String else { continue }
                        let count = ["input_tokens", "output_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"].reduce(0) { $0 + (usage[$1] as? Int ?? 0) }
                        let key = "claude:" + id
                        let previous = save.totals[key] ?? 0
                        tokens = max(0, count - previous)
                        save.totals[key] = max(previous, count)
                    }
                    addTokens(tokens)
                    save.collected = (save.collected ?? 0) + tokens
                    var sources = save.providerTokens ?? [:]; sources[codex ? "Codex" : "Claude Code", default: 0] += tokens; save.providerTokens = sources
                }
            }
        }
        save.initialized = true; persist(); onChange?()
    }
}

enum GameArt {
    static let names = ["platform", "platform-rail", "platform-ice", "platform-goal", "cannon", "spikes", "cannonball", "goal-flag"]
    static var cache: [String: SKTexture] = [:]
    static func sprite(_ name: String, size: CGSize) -> SKSpriteNode? {
        if cache[name] == nil {
            let sibling = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("Sprites")
            let roots = [Bundle.main.resourceURL?.appendingPathComponent("Sprites"), sibling].compactMap { $0 }
            guard let file = roots.map({ $0.appendingPathComponent(name + ".png") }).first(where: { FileManager.default.fileExists(atPath: $0.path) }), let image = NSImage(contentsOf: file) else { return nil }
            cache[name] = SKTexture(image: image)
        }
        let node = SKSpriteNode(texture: cache[name]); node.size = size; node.texture?.filteringMode = .linear; return node
    }
}
final class CannonShot: SKShapeNode {
    var flightSpeed: CGFloat = 0
}
final class Game: SKScene {
    let usage: Usage
    var onDismiss: (() -> Void)?
    var onContinue: (() -> Void)?
    var onStageChange: (() -> Void)?
    let player = SKShapeNode(rectOf: CGSize(width: 24, height: 30), cornerRadius: 7)
    let hud = SKLabelNode(fontNamed: "Menlo-Bold")
    let message = SKLabelNode(fontNamed: "Menlo")
    var keys = Set<UInt16>()
    var platforms: [CGPoint] = []
    var mechanicsEnabled = true
    var basePlatforms: [CGPoint] = []
    var previousPlatforms: [CGPoint] = []
    var platformNodes: [SKShapeNode] = []
    var supportIndex: Int? = 0
    var checkpointIndex = 0
    var motionClock: TimeInterval = 0
    var horizontalVelocity: CGFloat = 0
    var iceDrift = false
    var railIndices: [Int] { mechanicsEnabled ? ([3: [2], 6: [2], 8: [2, 4], 10: [3, 8], 11: [2, 8], 12: [4, 8, 10]][stage] ?? []).filter { $0 != spikeTier } : [] }
    var keyTiers: [Int] { mechanicsEnabled ? ([5: [1], 9: [3, 6], 12: [4, 8]][stage] ?? []).filter { $0 < platforms.count - 1 } : [] }
    var switchLink: (source: Int, target: Int)? { mechanicsEnabled ? [3: (1, 2), 8: (1, 2), 11: (6, 7)][stage] : nil }
    var collectedKeys = Set<Int>()
    var switchOn = false
    var keyNodes: [Int: SKNode] = [:]
    var switchNode: SKShapeNode?
    var windDrift: CGFloat = 0
    var windBands: [CGRect] = []
    var windNodes: [SKNode] = []
    var goalUnlocked: Bool { keyTiers.allSatisfy { collectedKeys.contains($0) } }
    var windDirection: CGFloat { stage % 2 == 0 ? 1 : -1 }
    func checkInteractions() {
        let body = CGRect(x: player.position.x - 12, y: player.position.y - 15, width: 24, height: 30)
        for index in keyTiers where platformActive(index) && !collectedKeys.contains(index) {
            let pickup = CGRect(x: platforms[index].x - 12, y: platforms[index].y + 21, width: 24, height: 14)
            if pickup.intersects(body) { collectedKeys.insert(index); keyNodes[index]?.isHidden = true }
        }
        childNode(withName: "flag")?.alpha = goalUnlocked ? 1 : 0.35
        childNode(withName: "flag")?.childNode(withName: "lock")?.isHidden = goalUnlocked
        guard let index = supportIndex, grounded else { return }
        if let link = switchLink, index == link.source, abs(player.position.x - platforms[index].x - switchOffset) < 12 {
            switchOn = true; switchNode?.fillColor = .systemGreen
            if platformNodes.indices.contains(link.target) { platformNodes[link.target].isHidden = false }
        }
    }
    var switchOffset: CGFloat { guard let link = switchLink else { return 0 }; return min(20, ledgeWidth(link.source) / 3) }
    var liftIndices: [Int] {
        guard mechanicsEnabled else { return [] }
        let candidates = [2: [1], 4: [1], 6: [4], 8: [1], 10: [1, 7], 11: [7], 12: [1, 9]][stage] ?? (usage.difficulty == .hard && stage == 1 ? [1] : [])
        return candidates.filter { $0 > 0 && $0 < platforms.count - 1 && $0 % 6 != 0 && $0 != spikeTier && !railIndices.contains($0) && !blinkIndices.contains($0) && !crumbleIndices.contains($0) && !iceIndices.contains($0) }
    }
    var liftAmplitude: CGFloat { usage.difficulty == .easy ? 10 : (usage.difficulty == .normal ? 12 : 14) }
    var liftPeriod: TimeInterval { usage.difficulty == .easy ? 4.4 : (usage.difficulty == .normal ? 3.8 : 3.2) }
    var iceIndices: [Int] { mechanicsEnabled ? ([5: [1], 7: [1, 3], 9: [2, 4, 7], 11: [1, 4, 9], 12: [3, 7, 11]][stage] ?? []) : [] }
    var blinkIndices: [Int] { mechanicsEnabled ? (usage.difficulty == .hard ? [spikeTier == 2 ? 4 : 2] : (stage >= 4 ? [2] : [])).filter { $0 < platforms.count - 1 && $0 != spikeTier } : [] }
    var crumbleIndices: [Int] { mechanicsEnabled ? (usage.difficulty == .hard ? [3, 5] : (stage >= 3 ? [3] : [])).filter { $0 < platforms.count - 1 && $0 != spikeTier } : [] }
    var crumbleAt: [Int: TimeInterval] = [:]
    var rotors: [(center: CGPoint, node: SKNode)] = []
    var spikeTier: Int? { mechanicsEnabled ? ([5: 2, 9: 1, 11: 3, 12: 2][stage] ?? (usage.difficulty == .hard && stage >= 3 ? 4 : nil)) : nil }
    func platformActive(_ index: Int) -> Bool {
        if let link = switchLink, index == link.target && !switchOn { return false }
        if blinkIndices.contains(index) && (motionClock + Double(index) * 0.3).truncatingRemainder(dividingBy: 3.6) >= 2.5 { return false }
        if let touched = crumbleAt[index] { let elapsed = motionClock - touched; if elapsed >= crumbleDelay && elapsed < crumbleDelay + 3 { return false } }
        return true
    }
    var crumbleDelay: TimeInterval { usage.difficulty == .hard ? 0.45 : 0.8 }
    var railAmplitude: CGFloat { stage < 6 ? 20 : (stage < 10 ? 25 : 30) }
    var railPeriod: TimeInterval { stage < 6 ? 4.8 : (stage < 10 ? 4.2 : 3.6) }
    var walls: [CGRect] = []
    var hazards: [CGRect] = []
    var hitNoticeUntil: TimeInterval = 0
    var notice = ""
    var combatEnabled = true
    var attemptStarted = false
    var knockedBack = false
    var recoil: CGFloat = 0
    var combatClock: TimeInterval = 0
    var nextShotAt: TimeInterval = 1.5
    var shotNumber = 0
    var immuneUntil: TimeInterval = 0
    var shots: [CannonShot] = []
    let warningLine = SKShapeNode(rectOf: CGSize(width: 384, height: 2))
    var hasCannons: Bool { combatEnabled && [4, 6, 7, 8, 10, 11, 12].contains(stage) }
    var fireInterval: TimeInterval {
        let base = usage.difficulty == .easy ? 3.4 : (usage.difficulty == .normal ? 2.7 : 2.1)
        return max(0.95, base - Double(stage - 1) * 0.075)
    }
    var platformWidth: CGFloat { Stage.all[stage - 1].width(usage.difficulty) }
    func ledgeWidth(_ index: Int) -> CGFloat {
        let spikes = spikeTier
        if index == spikes { return max(100, platformWidth) }
        guard stage >= 9, index != spikes, [3, 5, 8, 10, 11].contains(index) else { return platformWidth }
        let minimum: CGFloat = usage.difficulty == .easy ? 48 : (usage.difficulty == .normal ? 36 : 26)
        return max(minimum, platformWidth * 0.58)
    }
    var roomIndex = 0
    let roomCamera = SKCameraNode()
    var roomOffset: CGFloat { platforms.indices.contains(roomIndex * 6) ? platforms[roomIndex * 6].y - 50 : 0 }
    func setRoom(for index: Int) {
        let next = min(index / 6, max(0, (platforms.count - 2) / 6))
        if roomIndex != next { clearShots(); nextShotAt = combatClock + 0.8 }
        roomIndex = next
        roomCamera.position = CGPoint(x: 210, y: 280 + roomOffset)
        hud.position.y = roomOffset + 532
        let first = roomIndex * 6, end = min(first + 6, platforms.count - 1)
        for (index, node) in platformNodes.enumerated() { node.isHidden = index < first || index > end || !platformActive(index) }
        childNode(withName: "flag")?.isHidden = platforms.count - 1 > end
        for node in children where node.name == "cannon" { node.position.y = cannonY }
    }
    var cannonFromLeft: Bool { [4, 7, 10, 12].contains(stage) }
    var cannonTier: Int { [10, 12].contains(stage) ? 3 : ([6, 8, 11].contains(stage) ? 2 : 1) }
    var cannonY: CGFloat { basePlatforms.count > cannonTier ? basePlatforms[min(roomIndex * 6 + cannonTier, basePlatforms.count - 2)].y + 45 : 250 }
    var velocity: CGFloat = 0
    var grounded = true
    var cleared = false
    var last: TimeInterval = 0
    var checkpoint = CGPoint(x: 210, y: 71)
    var stage: Int { min(Stage.all.count, max(1, usage.save.stage ?? 1)) }
    init(usage: Usage) { self.usage = usage; super.init(size: CGSize(width: 420, height: 560)); scaleMode = .aspectFit }
    required init?(coder: NSCoder) { fatalError() }
    override func didMove(to view: SKView) {
        backgroundColor = NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.13, alpha: 1)
        roomCamera.position = CGPoint(x: 210, y: 280); addChild(roomCamera); camera = roomCamera
        player.fillColor = .systemMint; player.strokeColor = .clear; player.zPosition = 5; addChild(player)
        hud.fontSize = 13; hud.horizontalAlignmentMode = .left; hud.position = CGPoint(x: 16, y: 532); addChild(hud)
        message.isHidden = true; message.fontSize = 12; message.position = CGPoint(x: 210, y: 505); addChild(message)

        warningLine.fillColor = .systemOrange; warningLine.strokeColor = .clear; warningLine.zPosition = 1; addChild(warningLine)
        for i in 0..<24 {
            let star = SKShapeNode(circleOfRadius: i % 4 == 0 ? 1.4 : 0.7); star.fillColor = .white; star.strokeColor = .clear; star.alpha = 0.12
            star.position = CGPoint(x: 18 + (i * 79) % 386, y: 42 + (i * 53) % 415); star.zPosition = -1; addChild(star)
        }
        applyAvatar()
        loadStage()
    }
    func loadStage() {
        keys.removeAll(); velocity = 0; grounded = true; cleared = false; last = 0
        hitNoticeUntil = 0; notice = ""; recoil = 0; knockedBack = false; attemptStarted = false
        combatClock = 0; nextShotAt = 1.5; shotNumber = 0; immuneUntil = 0; clearShots()
        platforms = Stage.all[stage - 1].points(usage.difficulty)
        collectedKeys.removeAll(); switchOn = false; keyNodes.removeAll(); switchNode = nil; windDrift = 0; windBands.removeAll(); windNodes.removeAll()
        crumbleAt.removeAll(); rotors.removeAll()
        basePlatforms = platforms; previousPlatforms = platforms; platformNodes.removeAll()
        roomIndex = 0
        supportIndex = 0; checkpointIndex = 0; motionClock = 0; horizontalVelocity = 0; iceDrift = false
        checkpoint = CGPoint(x: platforms[0].x, y: 71); player.position = checkpoint
        children.filter { $0.name == "platform" || $0.name == "flag" || $0.name == "obstacle" || $0.name == "cannon" || $0.name == "rail" || $0.name == "wind" }.forEach { $0.removeFromParent() }
        for (i, p) in platforms.enumerated() {
            let node = SKShapeNode(rectOf: CGSize(width: ledgeWidth(i), height: 12), cornerRadius: 6)
            node.fillColor = i == platforms.count - 1 ? .systemYellow : .systemIndigo; node.strokeColor = .clear; node.position = p; node.name = "platform"; addChild(node); platformNodes.append(node)
            if iceIndices.contains(i) {
                node.fillColor = NSColor(calibratedRed: 0.65, green: 0.84, blue: 0.91, alpha: 1)
                let stripe = SKShapeNode(rectOf: CGSize(width: ledgeWidth(i) - 10, height: 1)); stripe.fillColor = .white; stripe.strokeColor = .clear; stripe.alpha = 0.7; stripe.position.y = 2; node.addChild(stripe)
            }

        }
        for (index, node) in platformNodes.enumerated() {
            let name = index == platforms.count - 1 ? "platform-goal" : (iceIndices.contains(index) ? "platform-ice" : ((railIndices.contains(index) || liftIndices.contains(index)) ? "platform-rail" : "platform"))
            if let art = GameArt.sprite(name, size: CGSize(width: ledgeWidth(index), height: 12)) {
                node.fillColor = .clear; node.strokeColor = .clear; node.removeAllChildren()
                art.centerRect = CGRect(x: 0.16, y: 0, width: 0.68, height: 1); node.addChild(art)
                if liftIndices.contains(index) { art.color = .systemTeal; art.colorBlendFactor = 0.4 }
                if blinkIndices.contains(index) { art.color = .systemPurple; art.colorBlendFactor = 0.65 }
                if crumbleIndices.contains(index) {
                    art.color = .systemOrange; art.colorBlendFactor = 0.7
                    let crack = CGMutablePath(); crack.move(to: CGPoint(x: -5, y: 6)); crack.addLine(to: CGPoint(x: 0, y: 1)); crack.addLine(to: CGPoint(x: -3, y: -2)); crack.addLine(to: CGPoint(x: 4, y: -6))
                    let mark = SKShapeNode(path: crack); mark.strokeColor = .black; mark.lineWidth = 1.5; node.addChild(mark)
                }
            }
        }

        let flagPath = CGMutablePath(); flagPath.move(to: CGPoint(x: 0, y: 0)); flagPath.addLine(to: CGPoint(x: 0, y: 20)); flagPath.addLine(to: CGPoint(x: 14, y: 15)); flagPath.addLine(to: CGPoint(x: 0, y: 10))
        let flag = SKShapeNode(path: flagPath); flag.strokeColor = .systemYellow; flag.fillColor = .systemYellow; flag.position = CGPoint(x: platforms.last!.x, y: platforms.last!.y + 6); flag.name = "flag"; addChild(flag)
        if let art = GameArt.sprite("goal-flag", size: CGSize(width: 18, height: 26)) { flag.fillColor = .clear; flag.strokeColor = .clear; art.anchorPoint = .zero; flag.addChild(art) }
        walls = []
        hazards = []
        if let tier = spikeTier, tier < platforms.count - 1 {
            let ledge = platforms[tier]
            // Alternate left/center/right positions on a widened ledge, leaving landing space.
            let offset: CGFloat = stage % 3 == 0 ? 0 : (stage % 3 == 1 ? -22 : 22)
            hazards = [CGRect(x: ledge.x + offset - 6, y: ledge.y + 6, width: 12, height: 12)]
        }
        if mechanicsEnabled && (usage.difficulty == .hard || stage >= 6) {
            let candidates = usage.difficulty == .hard && stage >= 7 ? [1, 5, 9] : [1]
            // A rotor above a hairpin also blocks the incoming jump's apex.
            let safeTiers = (1..<(platforms.count - 1)).filter { i in
                i != spikeTier && i + 1 != spikeTier && (platforms[i].x - platforms[i - 1].x) * (platforms[i + 1].x - platforms[i].x) > 0
            }
            var tiers = candidates.filter { safeTiers.contains($0) }
            if tiers.isEmpty, let fallback = safeTiers.first { tiers = [fallback] }
            for tier in tiers where tier + 1 < platforms.count {
                let a = platforms[tier], b = platforms[tier + 1]
                let center = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + (usage.difficulty == .hard ? 10 : (usage.difficulty == .normal ? 0 : -12)))
                let rotor = SKNode(); rotor.position = center; rotor.name = "obstacle"; rotor.zPosition = 3; addChild(rotor)
                let hub = SKShapeNode(circleOfRadius: 7); hub.fillColor = .darkGray; hub.strokeColor = .systemRed; rotor.addChild(hub)
                for arm in 0..<4 {
                    for radius: CGFloat in (usage.difficulty == .easy ? [9, 17, 25] : (usage.difficulty == .normal ? [11, 21, 31] : [13, 25, 37])) {
                        let tooth = SKShapeNode(rectOf: CGSize(width: 9, height: 9)); tooth.zRotation = .pi / 4
                        tooth.fillColor = .systemRed; tooth.strokeColor = .systemOrange
                        let angle = CGFloat(arm) * .pi / 2
                        tooth.position = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius); rotor.addChild(tooth)
                    }
                }
                rotors.append((center, rotor))
            }
        }
        for rect in walls {
            let node = SKShapeNode(rectOf: rect.size, cornerRadius: 3); node.position = CGPoint(x: rect.midX, y: rect.midY)
            node.fillColor = .darkGray; node.strokeColor = .lightGray; node.lineWidth = 2; node.name = "obstacle"; addChild(node)
            let mark = SKLabelNode(fontNamed: "Menlo-Bold"); mark.text = "▦"; mark.fontSize = 18; mark.verticalAlignmentMode = .center; node.addChild(mark)
        }
        for rect in hazards {
            let path = CGMutablePath()
            for x: CGFloat in [-4, 0] { path.move(to: CGPoint(x: x, y: -5)); path.addLine(to: CGPoint(x: x + 2, y: 5)); path.addLine(to: CGPoint(x: x + 4, y: -5)); path.closeSubpath() }
            let node = SKShapeNode(path: path); node.position = CGPoint(x: rect.midX, y: rect.midY); node.fillColor = .systemRed; node.strokeColor = .systemPink; node.name = "obstacle"; addChild(node)
            if let art = GameArt.sprite("spikes", size: rect.size) { node.fillColor = .clear; node.strokeColor = .clear; node.addChild(art) }
        }
        warningLine.position = CGPoint(x: 210, y: cannonY); warningLine.isHidden = true
        if hasCannons {
            for x: CGFloat in [cannonFromLeft ? 18 : 402] {
                let facing: CGFloat = x < 210 ? 1 : -1
                let cannon = SKNode(); cannon.position = CGPoint(x: x, y: cannonY); cannon.name = "cannon"; cannon.zPosition = 4; addChild(cannon)
                let base = SKShapeNode(circleOfRadius: 11); base.fillColor = NSColor(calibratedWhite: 0.18, alpha: 1); base.strokeColor = .systemOrange; base.lineWidth = 2; cannon.addChild(base)
                let barrel = SKShapeNode(rectOf: CGSize(width: 29, height: 12), cornerRadius: 3); barrel.position = CGPoint(x: facing * 15, y: 3); barrel.fillColor = .systemOrange; barrel.strokeColor = .systemYellow; barrel.lineWidth = 1; cannon.addChild(barrel)
                let muzzle = SKShapeNode(rectOf: CGSize(width: 5, height: 9), cornerRadius: 1); muzzle.position = CGPoint(x: facing * 29, y: 3); muzzle.fillColor = .black; muzzle.strokeColor = .clear; cannon.addChild(muzzle)
                for wheelX: CGFloat in [-6, 6] {
                    let wheel = SKShapeNode(circleOfRadius: 5); wheel.position = CGPoint(x: wheelX, y: -11); wheel.fillColor = .darkGray; wheel.strokeColor = .lightGray; cannon.addChild(wheel)
                }
                if let art = GameArt.sprite("cannon", size: CGSize(width: 48, height: 40)) {
                    cannon.removeAllChildren(); art.anchorPoint = CGPoint(x: 0.25, y: 0.5); art.xScale = facing; cannon.addChild(art)
                }
            }
        }
        buildStageFeatures()
        setRoom(for: 0)
        refreshHUD(); onStageChange?()
    }
    func buildStageFeatures() {
        let palettes: [NSColor] = [NSColor(calibratedRed: 0.04, green: 0.06, blue: 0.13, alpha: 1), NSColor(calibratedRed: 0.035, green: 0.10, blue: 0.105, alpha: 1), NSColor(calibratedRed: 0.12, green: 0.065, blue: 0.06, alpha: 1), NSColor(calibratedRed: 0.085, green: 0.05, blue: 0.13, alpha: 1)]
        backgroundColor = palettes[((stage - 1) / 3) % palettes.count]
        for index in keyTiers {
            let key = SKNode(); key.position = CGPoint(x: 0, y: 28); platformNodes[index].addChild(key); keyNodes[index] = key
            let ring = SKShapeNode(circleOfRadius: 5); ring.strokeColor = .systemYellow; ring.lineWidth = 2; ring.position.x = -6; key.addChild(ring)
            let shaft = CGMutablePath(); shaft.move(to: CGPoint(x: -1, y: 0)); shaft.addLine(to: CGPoint(x: 10, y: 0)); shaft.addLine(to: CGPoint(x: 10, y: -4)); shaft.move(to: CGPoint(x: 6, y: 0)); shaft.addLine(to: CGPoint(x: 6, y: -3))
            let stem = SKShapeNode(path: shaft); stem.strokeColor = .systemYellow; stem.lineWidth = 2; key.addChild(stem)
        }
        if !keyTiers.isEmpty, let flag = childNode(withName: "flag") {
            let lock = SKShapeNode(rectOf: CGSize(width: 12, height: 10), cornerRadius: 2); lock.fillColor = .systemYellow; lock.strokeColor = .clear; lock.position = CGPoint(x: -14, y: 14); lock.name = "lock"
            let loop = SKShapeNode(rectOf: CGSize(width: 8, height: 10), cornerRadius: 4); loop.strokeColor = .systemYellow; loop.fillColor = .clear; loop.lineWidth = 2; loop.position.y = 5; lock.addChild(loop); flag.addChild(lock); flag.alpha = 0.35
        }
        if let link = switchLink {
            let button = SKShapeNode(rectOf: CGSize(width: 14, height: 5), cornerRadius: 2); button.fillColor = .systemOrange; button.strokeColor = .white; button.lineWidth = 1; button.position = CGPoint(x: switchOffset, y: 9); platformNodes[link.source].addChild(button); switchNode = button
        }
        if mechanicsEnabled && [4, 7, 9, 10, 12].contains(stage) {
            for first in stride(from: 0, to: platforms.count - 2, by: 6) {
                let y = basePlatforms[min(first + 2, platforms.count - 2)].y + 12
                let band = CGRect(x: 20, y: y, width: 380, height: 62); windBands.append(band)
                for index in 0..<7 {
                    let path = CGMutablePath(); path.move(to: CGPoint(x: -4 * windDirection, y: -3)); path.addLine(to: .zero); path.addLine(to: CGPoint(x: -4 * windDirection, y: 3))
                    let gust = SKShapeNode(path: path); gust.strokeColor = .systemTeal; gust.alpha = 0.3; gust.lineWidth = 1.4; gust.name = "wind"; gust.zPosition = -0.3
                    gust.position = CGPoint(x: 30 + CGFloat(index) * 54, y: y + 12 + CGFloat(index % 3) * 18); gust.userData = ["originX": gust.position.x]; addChild(gust); windNodes.append(gust)
                }
            }
        }
    }
    func applyAvatar() {
        let avatar = Avatar(rawValue: usage.save.avatar ?? "bit") ?? .bit
        player.removeAllChildren(); player.fillColor = avatar.color
        for x: CGFloat in [-5, 5] {
            let eye = SKShapeNode(circleOfRadius: 2); eye.fillColor = .black; eye.strokeColor = .clear; eye.position = CGPoint(x: x, y: 3); player.addChild(eye)
        }
        if avatar == .ember {
            for x: CGFloat in [-8, 8] {
                let path = CGMutablePath(); path.move(to: CGPoint(x: x - 4, y: 11)); path.addLine(to: CGPoint(x: x, y: 22)); path.addLine(to: CGPoint(x: x + 4, y: 11)); path.closeSubpath()
                let ear = SKShapeNode(path: path); ear.fillColor = .systemOrange; ear.strokeColor = .clear; player.addChild(ear)
            }
        } else {
            let stem = SKShapeNode(rectOf: CGSize(width: 2, height: 8)); stem.fillColor = avatar.color; stem.strokeColor = .clear; stem.position.y = 18; player.addChild(stem)
            let tip = SKShapeNode(circleOfRadius: avatar == .orbit ? 4 : 2); tip.fillColor = avatar == .orbit ? .systemPink : .white; tip.strokeColor = .clear; tip.position.y = 23; player.addChild(tip)
        }
    }
    func refreshHUD() {
        hud.text = "↑ \(usage.available)"
        message.text = cleared ? (stage == Stage.all.count ? "전체 클리어! 스테이지를 골라 다시 도전하세요" : "클리어! N 키로 다음 스테이지 →") : "\(usage.threshold.formatted()) 토큰 = 점프 1회 · 잔여 \(usage.wallet.formatted())"
        if !cleared && knockedBack { message.text = usage.available > 0 ? "포탄에 밀려나는 중" : "남은 점프 0회" }
        if !cleared && last < hitNoticeUntil { message.text = notice }
        message.fontColor = cleared ? .systemYellow : .lightGray
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDismiss?(); return }
        if cleared && [36, 76].contains(event.keyCode) { onContinue?(); return }
        if event.keyCode == 45, cleared, stage < Stage.all.count, !event.isARepeat { if usage.advanceStage() { loadStage() }; return }
        if event.keyCode == 15, !event.isARepeat { loadStage(); return }
        keys.insert(event.keyCode)
        if [49, 13, 126].contains(event.keyCode), !event.isARepeat, !cleared {
            tryJump()
        }
    }
    override func keyUp(with event: NSEvent) { keys.remove(event.keyCode) }
    var isOnSurface: Bool {
        guard grounded, velocity <= 0 else { return false }
        let feet = player.position.y - 15
        if platforms.enumerated().contains(where: { platformActive($0.offset) && abs(feet - ($0.element.y + 6)) < 0.01 && abs(player.position.x - $0.element.x) < ledgeWidth($0.offset) / 2 + 12 }) { return true }
        return walls.contains { abs(feet - $0.maxY) < 0.01 && player.position.x + 12 > $0.minX && player.position.x - 12 < $0.maxX }
    }
    func tryJump() {
        guard !cleared, isOnSurface else { return }
        guard usage.spend() else { return }
        usage.save.runStarted = true; usage.persist()
        if grounded { iceDrift = supportIndex.map { iceIndices.contains($0) } ?? false }
        supportIndex = nil
        attemptStarted = true; velocity = 420; grounded = false

    }
    func suspend() { keys.removeAll(); last = 0; isPaused = true }
    override func update(_ time: TimeInterval) {
        let dt = last == 0 ? 0 : min(time - last, 1.0 / 30); last = time
        let carriedSupport = grounded ? supportIndex : nil
        if !cleared { movePlatforms(dt: dt) }

        refreshHUD()
        guard !cleared else { return }
        let direction: CGFloat = (keys.contains(2) || keys.contains(124) ? 1 : 0) - (keys.contains(0) || keys.contains(123) ? 1 : 0)
        let onIce = grounded && (supportIndex.map { iceIndices.contains($0) } ?? false)
        if onIce || (!grounded && iceDrift) {
            iceDrift = true
            if direction != 0 { horizontalVelocity = min(230, max(-230, horizontalVelocity + direction * 560 * dt)) }
            else { let drag: CGFloat = grounded ? 45 : 15; horizontalVelocity = max(0, abs(horizontalVelocity) - drag * dt) * (horizontalVelocity < 0 ? -1 : 1) }
        } else { horizontalVelocity = direction * 190; if grounded { iceDrift = false } }
        let inWind = !grounded && windBands.contains { $0.contains(player.position) }
        let targetWind: CGFloat = inWind ? windDirection * (usage.difficulty == .hard ? 55 : 35) : 0
        windDrift += (targetWind - windDrift) * min(1, dt * 5)
        let previousX = player.position.x
        player.position.x = min(408, max(12, player.position.x + (horizontalVelocity + recoil + windDrift) * dt))
        recoil *= max(0, 1 - 3.2 * dt)
        resolveWallsHorizontally(from: previousX)
        let previousY = player.position.y
        let oldBottom = previousY - 15
        // Integrate acceleration analytically so jump height does not shrink at 30 FPS.
        player.position.y += velocity * dt - 0.5 * 850 * dt * dt
        velocity -= 850 * dt
        grounded = false; supportIndex = nil
        resolveWallsVertically(from: previousY)
        if velocity <= 0 {
            let newBottom = player.position.y - 15
            // Test overlap at the instant the feet cross the top, including edge landings.
            let hits = platforms.enumerated().filter { index, p in
                guard platformActive(index) else { return false }
                let top = p.y + 6
                let oldLedge = previousPlatforms.indices.contains(index) ? previousPlatforms[index] : p
                let standing = carriedSupport == index && abs(oldBottom - top) < 0.001
                let oldTop = standing ? top : oldLedge.y + 6
                let oldDistance = oldBottom - oldTop, newDistance = newBottom - top
                guard oldDistance >= -0.001, newDistance <= 0.001 else { return false }
                let fraction = abs(oldDistance - newDistance) < 0.000001 ? CGFloat(1) : min(1, max(0, oldDistance / (oldDistance - newDistance)))
                // Standing contact is evaluated at the new position; using the old
                // position here continually snapped a walking player back to the edge.
                let crossingX = abs(oldBottom - top) < 0.001 ? player.position.x : previousX + (player.position.x - previousX) * fraction
                let ledgeX = abs(oldBottom - top) < 0.001 ? p.x : oldLedge.x + (p.x - oldLedge.x) * fraction
                return abs(crossingX - ledgeX) < ledgeWidth(index) / 2 + 12
            }
            if let (index, p) = hits.max(by: { $0.element.y < $1.element.y }) {
                player.position.y = p.y + 21; velocity = 0; grounded = true; knockedBack = false; supportIndex = index
                // Keep the landing footprint on the ledge if the horizontal step crossed its edge.
                player.position.x = min(p.x + ledgeWidth(index) / 2 + 11.5, max(p.x - ledgeWidth(index) / 2 - 11.5, player.position.x))
                setRoom(for: index)
                if crumbleIndices.contains(index) && crumbleAt[index] == nil { crumbleAt[index] = motionClock }
                checkInteractions()
                if platforms.count > 1 && index == platforms.count - 1 && goalUnlocked { cleared = true; clearShots(); usage.finishStage(stage); usage.save.best = max(usage.save.best, stage); usage.persist(); keys.removeAll(); onStageChange?() }
            }
        }
        let body = CGRect(x: player.position.x - 12, y: player.position.y - 15, width: 24, height: 30)
        checkInteractions()
        if hazards.contains(where: { $0.intersects(body) }) || rotorHits(body) {
            restoreCheckpoint(); velocity = 0; grounded = true; keys.removeAll(); hitNoticeUntil = time + 1.5; notice = "위험물! 첫 발판으로 복귀"
        }
        if player.position.y < roomOffset - 30 {

            restoreCheckpoint(); velocity = 0; grounded = true; knockedBack = false; recoil = 0
        }
        updateCannons(dt: dt)

    }
    func railBounds(index: Int) -> ClosedRange<CGFloat> {
        let center = basePlatforms[index].x
        return max(ledgeWidth(index) / 2 + 12, center - railAmplitude)...min(408 - ledgeWidth(index) / 2, center + railAmplitude)
    }
    func movePlatforms(dt: TimeInterval) {
        previousPlatforms = platforms
        guard mechanicsEnabled else { return }
        motionClock += dt
        for index in Array(crumbleAt.keys) {
            if motionClock - (crumbleAt[index] ?? 0) >= crumbleDelay + 3 { crumbleAt[index] = nil }
        }
        let first = roomIndex * 6, end = min(first + 6, platforms.count - 1)
        for (index, node) in platformNodes.enumerated() {
            node.isHidden = index < first || index > end || !platformActive(index)
            let phase = (motionClock + Double(index) * 0.3).truncatingRemainder(dividingBy: 3.6)
            let warning = blinkIndices.contains(index) && phase > 2.1
            let cracking = crumbleAt[index] != nil
            node.alpha = warning || cracking ? (sin(motionClock * 28) > 0 ? 0.4 : 1) : 1
        }
        for gust in windNodes {
            let start = gust.userData?["originX"] as? CGFloat ?? 30
            gust.position.x = 20 + (start - 20 + CGFloat(motionClock) * 24 * windDirection + 100000).truncatingRemainder(dividingBy: 380)
        }
        for rotor in rotors { rotor.node.zRotation = CGFloat(motionClock) * (usage.difficulty == .hard ? 2.2 : 1.35) }
        for index in liftIndices where basePlatforms.indices.contains(index) {
            platforms[index].y = basePlatforms[index].y + sin(motionClock * 2 * .pi / liftPeriod) * liftAmplitude
            if platformNodes.indices.contains(index) { platformNodes[index].position = platforms[index] }
            if grounded && supportIndex == index { player.position.y += platforms[index].y - previousPlatforms[index].y }
        }
        for index in railIndices where basePlatforms.indices.contains(index) {
            let bounds = railBounds(index: index)
            platforms[index].x = min(bounds.upperBound, max(bounds.lowerBound, basePlatforms[index].x + sin(motionClock * 2 * .pi / railPeriod) * railAmplitude))
            if platformNodes.indices.contains(index) { platformNodes[index].position = platforms[index] }
            if grounded && supportIndex == index { player.position.x += platforms[index].x - previousPlatforms[index].x; if checkpointIndex == index { checkpoint = player.position } }
        }
    }
    func rotorHits(_ body: CGRect) -> Bool {
        for rotor in rotors {
            for tooth in rotor.node.children.dropFirst() {
                let point = rotor.node.convert(tooth.position, to: self)
                let x = max(body.minX, min(point.x, body.maxX)), y = max(body.minY, min(point.y, body.maxY))
                if hypot(point.x - x, point.y - y) < 6.5 { return true }
            }
        }
        return false
    }
    func restoreCheckpoint() { loadStage() }
    func clearShots() { shots.forEach { $0.removeFromParent() }; shots.removeAll(); warningLine.isHidden = true }
    func fireShot(fromLeft: Bool) {
        let ball = CannonShot(circleOfRadius: 9)
        ball.fillColor = .systemOrange; ball.strokeColor = .systemYellow; ball.lineWidth = 1.5; ball.zPosition = 6
        ball.position = CGPoint(x: fromLeft ? 55 : 365, y: cannonY + 3)
        ball.flightSpeed = (fromLeft ? 1 : -1) * ((usage.difficulty == .hard ? 245 : 205) + CGFloat(stage - 1) * 5)
        if let art = GameArt.sprite("cannonball", size: CGSize(width: 18, height: 18)) { ball.fillColor = .clear; ball.strokeColor = .clear; ball.addChild(art) }
        let trail = SKShapeNode(rectOf: CGSize(width: 20, height: 4), cornerRadius: 2); trail.fillColor = .systemOrange; trail.strokeColor = .clear; trail.alpha = 0.4; trail.position.x = fromLeft ? -13 : 13; ball.addChild(trail)
        addChild(ball); shots.append(ball)
        let flash = SKShapeNode(circleOfRadius: 14); flash.fillColor = .systemYellow; flash.strokeColor = .clear; flash.position = ball.position; flash.zPosition = 7; addChild(flash)
        flash.run(.sequence([.fadeOut(withDuration: 0.18), .removeFromParent()]))
    }
    func updateCannons(dt: TimeInterval) {
        guard hasCannons && !cleared else { warningLine.isHidden = true; return }
        combatClock += dt
        warningLine.isHidden = true
        warningLine.alpha = 0.2 + 0.35 * CGFloat(abs(sin(combatClock * 8)))
        if combatClock >= nextShotAt { fireShot(fromLeft: cannonFromLeft); shotNumber += 1; nextShotAt += fireInterval }
        var survivors: [CannonShot] = []
        for ball in shots {
            let oldX = ball.position.x; ball.position.x += ball.flightSpeed * dt
            let sweep = CGRect(x: min(oldX, ball.position.x) - 9, y: ball.position.y - 9, width: abs(oldX - ball.position.x) + 18, height: 18)
            let body = CGRect(x: player.position.x - 12, y: player.position.y - 15, width: 24, height: 30)
            if combatClock >= immuneUntil && sweep.intersects(body) {
                recoil = ball.flightSpeed > 0 ? 340 : -340; velocity = max(velocity, 165); grounded = false; knockedBack = true; immuneUntil = combatClock + 0.8
                notice = "포탄 피격"; hitNoticeUntil = last + 0.8; ball.removeFromParent()
            } else if ball.position.x < -20 || ball.position.x > 440 { ball.removeFromParent() }
            else { survivors.append(ball) }
        }
        shots = survivors
        player.alpha = combatClock < immuneUntil ? 0.65 : 1
    }
    func resolveWallsHorizontally(from oldX: CGFloat) {
        for wall in walls where player.position.y + 15 > wall.minY && player.position.y - 15 < wall.maxY {
            if oldX + 12 <= wall.minX && player.position.x + 12 > wall.minX { player.position.x = wall.minX - 12 }
            else if oldX - 12 >= wall.maxX && player.position.x - 12 < wall.maxX { player.position.x = wall.maxX + 12 }
        }
    }
    func resolveWallsVertically(from oldY: CGFloat) {
        for wall in walls where player.position.x + 12 > wall.minX && player.position.x - 12 < wall.maxX {
            if oldY + 15 <= wall.minY && player.position.y + 15 > wall.minY {
                player.position.y = wall.minY - 15; velocity = 0
            } else if oldY - 15 >= wall.maxY && player.position.y - 15 < wall.maxY {
                player.position.y = wall.maxY + 15; velocity = 0; grounded = true
            }
        }
    }

}

// Explicitly forward keyboard events to the scene after the popover takes focus.
final class GameView: SKView {
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { scene?.keyDown(with: event); return }
        guard !isPaused && !isHidden else { return }
        scene?.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) { scene?.keyUp(with: event) }
}

final class App: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    let demo = CommandLine.arguments.contains("--demo")
    lazy var usage = Usage(stateDirectory: demo ? FileManager.default.temporaryDirectory.appendingPathComponent(CommandLine.arguments.contains("--ui-test") ? "TokenJump-ui-test-" + UUID().uuidString : "TokenJump-demo") : nil)
    var status: NSStatusItem!
    let popover = NSPopover()
    var gameView: GameView!
    var scene: Game!
    var timer: Timer?
    var completionPanel: NSVisualEffectView!
    var completionTitle: NSTextField!
    var completionHint: NSTextField!
    var completionButton: NSButton!
    var nextButton: NSButton!
    var selectionPanel: NSView!
    var difficultyPicker: NSSegmentedControl!
    var selectionHint: NSTextField!
    var stageHint: NSTextField!
    var stageButtons: [NSButton] = []
    var selectedStage = 1
    var choosingStage = true
    var emptyHint: NSTextField!
    var tabs: NSSegmentedControl!
    var usagePanel: NSView!
    var statLabels: [String: NSTextField] = [:]
    var chargeProgress: NSProgressIndicator!
    var isGameTab: Bool { tabs == nil || tabs.selectedSegment == 0 }
    var resignObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = Self.makeStatusIcon()
        status.button?.imagePosition = .imageOnly
        status.button?.title = ""
        status.button?.setAccessibilityLabel("TokenJump")
        status.button?.target = self; status.button?.action = #selector(toggle)
        status.button?.toolTip = demo ? "TokenJump · 체험 모드" : "Token Jump"
        usage.onChange = { [weak self] in
            guard let self = self else { return }
            self.status.button?.toolTip = "TokenJump · 점프 \(self.usage.available)회"
            self.refreshUsage()
        }
        if demo { usage.save.credits = 500; usage.onChange?() } else { usage.scan() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in if self?.demo == false { self?.usage.scan() } }; timer?.tolerance = 10

        let controller = NSViewController()
        let content = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 420, height: 640))
        content.material = .popover; content.blendingMode = .withinWindow; content.state = .active
        controller.view = content

        gameView = GameView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
        gameView.preferredFramesPerSecond = 30
        scene = Game(usage: usage)
        scene.onDismiss = { [weak self] in self?.popover.performClose(nil) }
        scene.onContinue = { [weak self] in guard let self = self else { return }; self.continueAfterClear(self.completionButton) }
        gameView.presentScene(scene)
        content.addSubview(gameView)
        let title = NSTextField(labelWithString: demo ? "TokenJump · 체험 모드" : "TokenJump")
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.frame = NSRect(x: 18, y: 608, width: 290, height: 18)
        content.addSubview(title)
        nextButton = NSButton(title: "스테이지", target: self, action: #selector(showSelection))
        nextButton.bezelStyle = .inline; nextButton.frame = NSRect(x: 300, y: 603, width: 68, height: 28); content.addSubview(nextButton)
        scene.onStageChange = { [weak self, weak title] in
            guard let self = self else { return }
            title?.stringValue = self.scene.cleared && self.scene.stage == Stage.all.count ? "TokenJump · 완주" : "TokenJump · \(self.scene.stage)/\(Stage.all.count)"
            self.refreshSelection()
            self.updateGameScreen()
        }
        scene.onStageChange?()
        let settings = NSButton(image: NSImage(systemSymbolName: "gearshape", accessibilityDescription: "캐릭터 설정")!, target: self, action: #selector(showSettings(_:)))
        settings.isBordered = false; settings.frame = NSRect(x: 370, y: 603, width: 32, height: 28)
        settings.toolTip = "캐릭터 · 종료"; content.addSubview(settings)
        tabs = NSSegmentedControl(labels: ["게임", "사용량"], trackingMode: .selectOne, target: self, action: #selector(changeTab(_:)))
        tabs.setLabel("게임", forSegment: 0); tabs.selectedSegment = 0; tabs.segmentStyle = .rounded
        tabs.frame = NSRect(x: 14, y: 565, width: 392, height: 30); tabs.setWidth(192, forSegment: 0); tabs.setWidth(192, forSegment: 1)
        content.addSubview(tabs)
        buildSelectionPanel(in: content)
        emptyHint = text("점프 횟수를 모두 소진했어요.\n토큰을 충전하고 돌아와 주세요.", size: 13, weight: .medium, frame: NSRect(x: 40, y: 455, width: 340, height: 54), parent: content)
        emptyHint.alignment = .center; emptyHint.textColor = .white
        buildUsagePanel(in: content)
        refreshUsage()
        completionPanel = NSVisualEffectView(frame: NSRect(x: 32, y: 162, width: 356, height: 220))
        completionPanel.material = .popover; completionPanel.blendingMode = .withinWindow; completionPanel.state = .active
        completionPanel.wantsLayer = true; completionPanel.layer?.cornerRadius = 12; completionPanel.layer?.masksToBounds = true; completionPanel.isHidden = true
        completionTitle = text("", size: 21, weight: .semibold, frame: NSRect(x: 22, y: 151, width: 312, height: 35), parent: completionPanel)
        completionHint = text("", size: 13, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 96, width: 312, height: 48), parent: completionPanel)
        completionButton = NSButton(title: "다음 스테이지", target: self, action: #selector(continueAfterClear(_:)))
        completionButton.bezelStyle = .rounded; completionButton.frame = NSRect(x: 20, y: 30, width: 316, height: 38); completionButton.keyEquivalent = "\r"; completionPanel.addSubview(completionButton)
        content.addSubview(completionPanel)
        updateCompletion()
        updateGameScreen()
        popover.contentViewController = controller
        popover.contentSize = content.frame.size
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        pauseGame()
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        let menu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Token Jump 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; menu.addItem(appItem); NSApp.mainMenu = menu
        if !CommandLine.arguments.contains("--ui-test") { toggle() }
    }
    func updateCompletion() {
        guard completionPanel != nil else { return }
        completionPanel.isHidden = !isGameTab || choosingStage || !scene.cleared
        completionTitle.stringValue = scene.stage == Stage.all.count ? "모든 스테이지 클리어" : "스테이지 \(scene.stage) 클리어"
        completionHint.stringValue = scene.stage == Stage.all.count ? "완주했습니다. 이제 난이도를 바꿔\n새 도전을 시작할 수 있습니다." : "N 키로 다음 스테이지\nEnter 키 또는 아래 버튼으로도 이동할 수 있어요."
        completionButton.title = scene.stage == Stage.all.count ? "난이도 선택" : "다음 스테이지 →"
    }
    @objc func continueAfterClear(_ sender: NSButton) {
        guard scene.cleared else { return }
        if scene.stage == Stage.all.count { showSelection() } else { nextStage() }
    }
    func buildSelectionPanel(in content: NSView) {
        selectionPanel = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 560)); content.addSubview(selectionPanel)
        _ = text("도전 준비", size: 23, weight: .semibold, frame: NSRect(x: 22, y: 505, width: 376, height: 32), parent: selectionPanel)
        _ = text("난이도", size: 13, weight: .medium, frame: NSRect(x: 22, y: 468, width: 376, height: 22), parent: selectionPanel)
        difficultyPicker = NSSegmentedControl(labels: Difficulty.allCases.map { $0.title }, trackingMode: .selectOne, target: self, action: #selector(pickDifficulty(_:)))
        difficultyPicker.frame = NSRect(x: 22, y: 430, width: 376, height: 30); selectionPanel.addSubview(difficultyPicker)
        selectionHint = text("", size: 11, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 386, width: 376, height: 38), parent: selectionPanel)
        _ = text("스테이지", size: 13, weight: .medium, frame: NSRect(x: 22, y: 351, width: 376, height: 22), parent: selectionPanel)
        for (index, stage) in Stage.all.enumerated() {
            let button = NSButton(title: "", target: self, action: #selector(pickStage(_:)))
            button.tag = index + 1; button.bezelStyle = .regularSquare; button.setButtonType(.pushOnPushOff)
            button.frame = NSRect(x: 22 + (index % 3) * 128, y: 283 - (index / 3) * 57, width: 120, height: 49)
            button.toolTip = stage.name; selectionPanel.addSubview(button); stageButtons.append(button)
        }
        stageHint = text("", size: 11, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 94, width: 376, height: 20), parent: selectionPanel)
        let start = NSButton(title: "선택한 스테이지 시작", target: self, action: #selector(startSelectedStage))
        start.bezelStyle = .rounded; start.frame = NSRect(x: 22, y: 55, width: 376, height: 38); selectionPanel.addSubview(start)
        _ = text("A / D 이동 · Space 점프 · R 다시 시작", size: 11, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 20, width: 376, height: 22), parent: selectionPanel)
        selectedStage = scene.stage; refreshSelection()
    }
    func refreshSelection() {
        guard selectionPanel != nil else { return }
        difficultyPicker.selectedSegment = Difficulty.allCases.firstIndex(of: usage.difficulty) ?? 1
        difficultyPicker.isEnabled = usage.canChangeDifficulty
        selectionHint.stringValue = "점프 1회당 \(usage.threshold.formatted()) 토큰" + (usage.canChangeDifficulty ? " · 시작 전에 난이도를 선택하세요." : "\n도전 중에는 고정됩니다. 전체 클리어 후 변경할 수 있어요.")
        let rules = [1: "기본 도약", 2: "승강 발판의 높이를 보고 도약하세요.", 3: "주황색 버튼을 밟으면 다음 발판이 켜집니다.", 4: "바람과 포격 사이로 이동하세요.", 5: "발판 위 열쇠를 모으면 골인이 열립니다.", 6: "회전 가시와 이동 발판을 통과하세요.", 7: "빙판의 미끄러짐과 역풍에 주의하세요.", 8: "버튼으로 발판을 켜고 사라지기 전에 건너세요.", 9: "열쇠 2개를 모아 바람 구간을 통과하세요.", 10: "바람 속에서 움직이는 발판에 올라타세요.", 11: "위쪽 구간 버튼으로 마지막 길을 여세요.", 12: "열쇠 2개를 모아 모든 장애물을 통과하세요."]
        stageHint?.stringValue = rules[selectedStage] ?? ""
        for button in stageButtons {
            let unlocked = button.tag <= usage.unlockedStage
            let done = button.tag <= (usage.save.clearedStages ?? 0)
            button.title = "\(String(format: "%02d", button.tag)) \(done ? "✓" : unlocked ? "" : "잠김")\n\(Stage.all[button.tag - 1].name)"
            button.isEnabled = unlocked; button.state = button.tag == selectedStage ? .on : .off
        }
    }
    func updateGameScreen() {
        guard scene != nil, gameView != nil else { return }
        gameView.isHidden = !isGameTab || choosingStage
        selectionPanel?.isHidden = !isGameTab || !choosingStage
        emptyHint?.isHidden = !isGameTab || choosingStage || scene.cleared || usage.available > 0
        updateCompletion()
    }
    @objc func showSelection() {
        selectedStage = scene.stage; choosingStage = true; pauseGame(); refreshSelection(); updateGameScreen()
    }
    @objc func pickStage(_ sender: NSButton) {
        guard sender.tag <= usage.unlockedStage else { return }
        selectedStage = sender.tag; refreshSelection()
    }
    @objc func pickDifficulty(_ sender: NSSegmentedControl) {
        guard Difficulty.allCases.indices.contains(sender.selectedSegment), usage.canChangeDifficulty else { refreshSelection(); return }
        let mode = Difficulty.allCases[sender.selectedSegment]
        if mode != usage.difficulty { _ = usage.setDifficulty(mode); selectedStage = 1; scene.loadStage() }
        refreshSelection(); refreshUsage()
    }
    @objc func startSelectedStage() {
        guard usage.selectStage(selectedStage) else { return }
        scene.loadStage(); choosingStage = false; updateGameScreen()
        if popover.isShown { resumeGame() }
    }
    func text(_ value: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .labelColor, frame: NSRect, parent: NSView) -> NSTextField {
        let label = NSTextField(labelWithString: value); label.font = .systemFont(ofSize: size, weight: weight); label.textColor = color; label.frame = frame
        label.maximumNumberOfLines = 0; label.lineBreakMode = .byWordWrapping; parent.addSubview(label); return label
    }
    func buildUsagePanel(in content: NSView) {
        usagePanel = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 560)); usagePanel.isHidden = true; content.addSubview(usagePanel)
        func rule(_ y: CGFloat) { let line = NSBox(frame: NSRect(x: 20, y: y, width: 380, height: 1)); line.boxType = .separator; usagePanel.addSubview(line) }
        func row(_ title: String, key: String, y: CGFloat, prominent: Bool = false) {
            _ = text(title, size: 13, color: .secondaryLabelColor, frame: NSRect(x: 22, y: y, width: 180, height: 25), parent: usagePanel)
            let value = text("", size: prominent ? 20 : 14, weight: .medium, frame: NSRect(x: 202, y: y - 1, width: 196, height: 28), parent: usagePanel)
            value.font = .monospacedDigitSystemFont(ofSize: prominent ? 20 : 14, weight: .medium); value.alignment = .right; statLabels[key] = value
        }
        row("남은 점프", key: "ready", y: 505, prominent: true)
        statLabels["rate"] = text("", size: 11, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 468, width: 376, height: 24), parent: usagePanel)
        chargeProgress = NSProgressIndicator(frame: NSRect(x: 22, y: 449, width: 376, height: 4)); chargeProgress.style = .bar; chargeProgress.isIndeterminate = false; chargeProgress.minValue = 0; chargeProgress.maxValue = 1; usagePanel.addSubview(chargeProgress)
        rule(426)
        row("보유 토큰", key: "wallet", y: 389)
        row("점프에 사용한 토큰", key: "spent", y: 351)
        row("사용한 점프", key: "jumps", y: 313)
        rule(295)
        _ = text("AI 사용 기록", size: 12, weight: .semibold, frame: NSRect(x: 22, y: 261, width: 376, height: 22), parent: usagePanel)
        row("Codex", key: "Codex", y: 225)
        row("Claude Code", key: "Claude Code", y: 189)
        row("합계", key: "total", y: 153)
        rule(135)
        _ = text("1분마다 갱신 · 새로 집계한 로컬 기록 기준", size: 11, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 100, width: 376, height: 22), parent: usagePanel)
        _ = text("기존 잔액은 집계 합계와 다를 수 있습니다.\n웹 채팅과 Grok은 아직 집계하지 않습니다.", size: 11, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 49, width: 376, height: 42), parent: usagePanel)
        if demo { _ = text("체험 모드", size: 11, color: .secondaryLabelColor, frame: NSRect(x: 22, y: 18, width: 376, height: 20), parent: usagePanel) }
    }
    func refreshUsage() {
        updateGameScreen()
        guard usagePanel != nil else { return }
        statLabels["ready"]?.stringValue = "\(usage.available.formatted())회"
        let remaining = usage.threshold - usage.wallet % usage.threshold
        statLabels["rate"]?.stringValue = "\(usage.difficulty.title) · 1회 \(usage.threshold.formatted()) 토큰 · 다음 1회까지 \(remaining.formatted())"
        chargeProgress.doubleValue = Double(usage.wallet % usage.threshold) / Double(usage.threshold)
        statLabels["wallet"]?.stringValue = usage.wallet.formatted()
        statLabels["spent"]?.stringValue = (usage.save.spent ?? 0).formatted()
        for key in ["Codex", "Claude Code"] { statLabels[key]?.stringValue = (usage.save.providerTokens?[key] ?? 0).formatted() }
        statLabels["total"]?.stringValue = (usage.save.collected ?? 0).formatted()
        statLabels["jumps"]?.stringValue = "\((usage.save.jumpCount ?? 0).formatted())회"
    }
    @objc func changeTab(_ sender: NSSegmentedControl) {
        updateGameScreen(); usagePanel.isHidden = isGameTab
        refreshUsage(); updateCompletion()
        if isGameTab && popover.isShown { resumeGame() } else { pauseGame() }
    }
    func resumeGame() { guard !choosingStage && isGameTab else { pauseGame(); return }; scene.last = 0; scene.isPaused = false; gameView.isPaused = false; restoreFocus() }
    static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let stairs = NSBezierPath(); stairs.lineWidth = 1.7; stairs.lineJoinStyle = .round; stairs.lineCapStyle = .round
            stairs.move(to: NSPoint(x: 1.5, y: 2)); stairs.line(to: NSPoint(x: 6.5, y: 2)); stairs.line(to: NSPoint(x: 6.5, y: 5)); stairs.line(to: NSPoint(x: 11.5, y: 5)); stairs.line(to: NSPoint(x: 11.5, y: 8)); stairs.line(to: NSPoint(x: 16.5, y: 8)); stairs.stroke()
            let token = NSBezierPath(ovalIn: NSRect(x: 2, y: 8, width: 6, height: 6)); token.lineWidth = 1.7; token.stroke()
            let leap = NSBezierPath(); leap.lineWidth = 1.7; leap.lineCapStyle = .round; leap.lineJoinStyle = .round
            leap.move(to: NSPoint(x: 10, y: 12)); leap.curve(to: NSPoint(x: 16, y: 16), controlPoint1: NSPoint(x: 11, y: 15), controlPoint2: NSPoint(x: 13, y: 16)); leap.move(to: NSPoint(x: 12.5, y: 16)); leap.line(to: NSPoint(x: 16, y: 16)); leap.line(to: NSPoint(x: 16, y: 12.5)); leap.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "TokenJump"
        return image
    }
    @objc func showSettings(_ sender: NSButton) {
        pauseGame()
        let menu = NSMenu()
        func section(_ title: String, items: [String], selected: Int, action: Selector) {
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let submenu = NSMenu(); submenu.autoenablesItems = false
            for (index, text) in items.enumerated() {
                let item = NSMenuItem(title: text, action: action, keyEquivalent: ""); item.target = self; item.tag = index; item.state = index == selected ? .on : .off
                if action == #selector(changeStage(_:)) { item.isEnabled = index + 1 <= usage.unlockedStage }
                if action == #selector(changeDifficulty(_:)) { item.isEnabled = usage.canChangeDifficulty }
                submenu.addItem(item)
            }
            root.submenu = submenu; menu.addItem(root)
        }
        section("캐릭터", items: Avatar.allCases.map { $0.title }, selected: Avatar.allCases.firstIndex(of: Avatar(rawValue: usage.save.avatar ?? "bit") ?? .bit) ?? 0, action: #selector(changeAvatar(_:)))
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
        if popover.isShown && isGameTab { resumeGame() }
    }
    @objc func nextStage() {
        guard scene.cleared, usage.advanceStage() else { return }
        scene.loadStage(); if popover.isShown && isGameTab { resumeGame() }
    }
    @objc func changeStage(_ sender: NSMenuItem) {
        guard Stage.all.indices.contains(sender.tag) else { return }
        guard usage.selectStage(sender.tag + 1) else { return }; scene.loadStage(); restoreFocus()
    }
    @objc func changeAvatar(_ sender: NSMenuItem) {
        guard Avatar.allCases.indices.contains(sender.tag) else { return }
        usage.save.avatar = Avatar.allCases[sender.tag].rawValue; usage.persist(); scene.applyAvatar(); restoreFocus()
    }
    func restoreFocus() { DispatchQueue.main.async { [weak self] in self?.gameView.window?.makeFirstResponder(self?.gameView) } }
    @objc func changeDifficulty(_ sender: NSMenuItem) {
        guard Difficulty.allCases.indices.contains(sender.tag) else { return }
        guard usage.setDifficulty(Difficulty.allCases[sender.tag]) else { return }
        scene.loadStage()
        refreshUsage(); restoreFocus()
    }
    func pauseGame() { scene.suspend(); gameView.isPaused = true }
    @objc func toggle() {
        guard let button = status.button else { return }
        if popover.isShown { popover.performClose(nil); return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
    func popoverDidShow(_ notification: Notification) {
        gameView.window?.makeKey()
        gameView.window?.makeFirstResponder(gameView)
        if isGameTab { resumeGame() } else { pauseGame(); refreshUsage() }
    }
    func popoverWillClose(_ notification: Notification) { pauseGame(); usage.persist() }
    func detachableWindow(for popover: NSPopover) -> NSWindow? { nil }
    func applicationWillTerminate(_ notification: Notification) { usage.persist() }
}
if CommandLine.arguments.contains("--self-test") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let logs = dir.appendingPathComponent("logs")
    try! FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
    let file = logs.appendingPathComponent("session.jsonl")
    func event(_ count: Int) -> String { "{\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(count)}}}}\n" }
    try! Data(event(50000).utf8).write(to: file)
    let usage = Usage(stateDirectory: dir.appendingPathComponent("state"))
    usage.scan(roots: [(logs, true)])
    verify(usage.save.credits == 0)
    let handle = try! FileHandle(forWritingTo: file); try! handle.seekToEnd()
    try! handle.write(contentsOf: Data((event(75000) + event(75000)).utf8)); try! handle.close()
    usage.scan(roots: [(logs, true)])
    verify(usage.save.credits == 2 && usage.save.remainder == 5000)
    usage.scan(roots: [(logs, true)]); verify(usage.save.credits == 2)
    verify(usage.spend() && usage.spend() && !usage.spend())
    let restored = Usage(stateDirectory: dir.appendingPathComponent("state"))
    verify(restored.save.credits == 0 && restored.save.remainder == 5000)
    let claude = logs.appendingPathComponent("claude.jsonl")
    let record = "{\"type\":\"assistant\",\"message\":{\"id\":\"test-message\",\"usage\":{\"input_tokens\":5000,\"output_tokens\":1000}}}\n"
    try! Data((record + record).utf8).write(to: claude)
    restored.scan(roots: [(logs, false)])
    verify(restored.save.credits == 1 && restored.save.remainder == 1000)
    restored.scan(roots: [(logs, false)])
    verify(restored.save.credits == 1 && restored.save.remainder == 1000)
    verify(restored.save.collected == 31_000 && restored.save.spent == 20_000 && restored.save.jumpCount == 2)
    verify(restored.save.providerTokens?["Codex"] == 25_000 && restored.save.providerTokens?["Claude Code"] == 6_000)
    let balance = restored.wallet
    restored.setDifficulty(.hard)
    verify(restored.wallet == balance && restored.available == balance / 25_000)
    verify(!restored.spend())
    restored.addTokens(50_000)
    verify(restored.available == 2)
    verify(restored.spend() && restored.wallet == balance + 25_000)
    restored.setDifficulty(.easy)
    verify(restored.available == restored.wallet / 5_000)
    let legacy = Usage(stateDirectory: dir.appendingPathComponent("state"))
    verify(legacy.difficulty == .easy && legacy.wallet == restored.wallet)
    for mode in Difficulty.allCases {
        // Vertical apex must clear the top of the next platform.
        verify(420.0 * 420.0 / (2 * 850) > Double(mode.gap))
    }
    for mode in Difficulty.allCases {
        for stage in Stage.all {
            let points = stage.points(mode)
            verify((5...13).contains(points.count) && points.enumerated().allSatisfy { offset, point in point.y - points[min(offset / 6, max(0, (points.count - 2) / 6)) * 6].y + 50 < 490 })
            for (a, b) in zip(points, points.dropFirst()) {
                let rise = Double(b.y - a.y)
                let discriminant = 420.0 * 420.0 - 2 * 850 * rise
                verify(discriminant > 0)
                let flightTime = (420 + sqrt(discriminant)) / 850
                // Full center-to-center travel must be possible before landing.
                verify(Double(abs(b.x - a.x)) < 190 * flightTime + Double(stage.width(mode) / 2 + 10))
            }
        }
    }
    for mode in Difficulty.allCases {
        for number in [5, 9, 11, 12] {
            let tier = [5: 2, 9: 1, 11: 3, 12: 2][number]!
            let ledge = Stage.all[number - 1].points(mode)[tier]
            let spikeX = Stage.all[number - 1].points(mode)[tier - 1].x < ledge.x ? ledge.x + Stage.all[number - 1].width(mode) / 2 - 8 : ledge.x - Stage.all[number - 1].width(mode) / 2
            let spike = CGRect(x: spikeX, y: ledge.y + 6, width: 8, height: 10)
            verify(spike.minX >= ledge.x - Stage.all[number - 1].width(mode) / 2 && spike.maxX <= ledge.x + Stage.all[number - 1].width(mode) / 2)
            verify(!spike.intersects(CGRect(x: ledge.x - 12, y: ledge.y + 6, width: 24, height: 30)))
        }
    }
    let oldData = Data("{\"credits\":2,\"remainder\":500,\"offsets\":{},\"totals\":{},\"initialized\":true,\"best\":0}".utf8)
    let oldSave = try! JSONDecoder().decode(Save.self, from: oldData)
    verify(oldSave.credits == 2 && oldSave.avatar == nil)
    restored.save.avatar = "orbit"; restored.save.stage = 12; restored.persist()
    let settings = Usage(stateDirectory: dir.appendingPathComponent("state"))
    verify(settings.save.avatar == "orbit" && settings.save.stage == 12)
    print("PASS: 12 stages × 3 modes reachable, legacy saves, avatar/stage persistence")
    print("PASS: difficulty rates, wallet conservation, persisted settings, reachable gaps;")
    print("PASS: baseline, incremental credit, duplicate scan/message, spending, persistence")
    exit(0)
}
if CommandLine.arguments.contains("--ui-test") {
    verify(CommandLine.arguments.contains("--demo"))
    _ = NSApplication.shared
    let controller = App()
    controller.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    verify(controller.popover.contentSize == NSSize(width: 420, height: 640))
    verify(controller.status.button?.title == "" && controller.status.button?.image?.isTemplate == true)
    verify(controller.tabs.segmentCount == 2 && controller.tabs.label(forSegment: 0) == "게임" && controller.tabs.label(forSegment: 1) == "사용량")
    controller.tabs.selectedSegment = 1; controller.changeTab(controller.tabs)
    verify(controller.gameView.isHidden && controller.gameView.isPaused && controller.scene.isPaused && !controller.usagePanel.isHidden)
    let before = controller.usage.wallet
    let jump = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
    controller.gameView.keyDown(with: jump); verify(controller.usage.wallet == before)
    verify(controller.statLabels["wallet"]?.stringValue == before.formatted())
    for item in controller.usagePanel.subviews { verify(controller.usagePanel.bounds.contains(item.frame)) }
    controller.tabs.selectedSegment = 0; controller.changeTab(controller.tabs)
    verify(controller.choosingStage && controller.gameView.isHidden && !controller.selectionPanel.isHidden && controller.usagePanel.isHidden)
    verify(controller.stageButtons.count == 12 && !controller.stageButtons[1].isEnabled)
    controller.gameView.keyDown(with: jump); verify(controller.usage.wallet == before)
    controller.startSelectedStage()
    verify(!controller.gameView.isHidden && controller.selectionPanel.isHidden)
    controller.usage.save.stage = 1; controller.usage.save.clearedStages = 0; controller.usage.save.runStarted = true
    controller.scene.loadStage(); verify(controller.completionPanel.isHidden)
    controller.scene.cleared = true; controller.usage.finishStage(1); controller.scene.onStageChange?()
    verify(!controller.completionPanel.isHidden && controller.completionHint.stringValue.contains("N 키로 다음 스테이지"))
    verify(controller.completionButton.title == "다음 스테이지 →")
    controller.scene.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!)
    verify(controller.scene.stage == 2 && controller.completionPanel.isHidden)
    controller.usage.save.stage = 12; controller.usage.save.clearedStages = 11; controller.scene.loadStage()
    controller.scene.cleared = true; controller.usage.finishStage(12); controller.scene.onStageChange?()
    verify(!controller.completionPanel.isHidden && controller.completionButton.title == "난이도 선택" && controller.usage.canChangeDifficulty)
    controller.tabs.selectedSegment = 1; controller.changeTab(controller.tabs); verify(controller.completionPanel.isHidden)
    controller.showSelection(); verify(controller.difficultyPicker.isEnabled && controller.selectionPanel.isHidden)
    controller.tabs.selectedSegment = 0; controller.changeTab(controller.tabs)
    verify(!controller.selectionPanel.isHidden)
    controller.startSelectedStage(); controller.scene.cleared = false
    controller.usage.save.credits = 0; controller.usage.save.remainder = 0; controller.refreshUsage()
    verify(!controller.emptyHint.isHidden)
    controller.usage.save.credits = 1; controller.refreshUsage(); verify(controller.emptyHint.isHidden)
    controller.timer?.invalidate()
    try? FileManager.default.removeItem(at: controller.usage.url.deletingLastPathComponent())
    print("PASS: clear overlay instructions, Enter advances unlocked stage, finale difficulty action, overlay hidden on usage tab")
    print("PASS: two tabs, compact bounds, usage values, hidden game paused, no hidden jump charge, template icon")
    exit(0)
}
if CommandLine.arguments.contains("--hazard-test") {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TokenJump-hazards-" + UUID().uuidString)
    let usage = Usage(stateDirectory: dir); defer { try? FileManager.default.removeItem(at: dir) }
    let scene = Game(usage: usage); scene.combatEnabled = false
    let view = GameView(frame: NSRect(x: 0, y: 0, width: 420, height: 560)); view.presentScene(scene)
    for mode in Difficulty.allCases {
        usage.save.runStarted = false; usage.setDifficulty(mode)
        for number in 1...12 {
            usage.save.stage = number; scene.loadStage(); scene.switchOn = true
            verify(scene.children.filter { $0.name == "rail" }.isEmpty)
            verify(scene.platformActive(0) && scene.platformActive(scene.platforms.count - 1))
            if mode == .hard { verify(!scene.rotors.isEmpty && !scene.blinkIndices.isEmpty && !scene.crumbleIndices.isEmpty) }
            for index in scene.blinkIndices {
                scene.motionClock = 2.7 - Double(index) * 0.3
                scene.movePlatforms(dt: 0); verify(!scene.platformActive(index) && scene.platformNodes[index].isHidden)
                scene.player.position = CGPoint(x: scene.platforms[index].x, y: scene.platforms[index].y + 21); scene.grounded = true; scene.velocity = 0
                verify(!scene.isOnSurface)
                scene.motionClock = 3.7 - Double(index) * 0.3; scene.movePlatforms(dt: 0)
                verify(scene.platformActive(index))
            }
            for index in scene.crumbleIndices {
                scene.crumbleAt[index] = scene.motionClock
                scene.movePlatforms(dt: scene.crumbleDelay - 0.01); verify(scene.platformActive(index))
                scene.movePlatforms(dt: 0.02); verify(!scene.platformActive(index))
                scene.movePlatforms(dt: 3.01); verify(scene.platformActive(index) && scene.crumbleAt[index] == nil)
            }
            if let rotor = scene.rotors.first {
                let tooth = rotor.node.convert(rotor.node.children[1].position, to: scene)
                verify(scene.rotorHits(CGRect(x: tooth.x - 2, y: tooth.y - 2, width: 4, height: 4)))
                verify(!scene.rotorHits(CGRect(x: -200, y: -200, width: 24, height: 30)))
            }
            // Search launch timing and safe landing positions with all platform hazards active.
            for target in 1..<scene.platforms.count {
                var reachable = false
                search: for phase in 0..<24 {
                    for offset: CGFloat in [0, -24, 24, -40, 40] {
                    for sourceShift: CGFloat in (scene.spikeTier == target - 1 ? [-28, 28, -42, 42] : [0, -20, 20]) {
                    for launchDelay in (scene.rotors.isEmpty ? [0.0] : [0.0, 0.10, 0.18]) {
                        scene.loadStage(); scene.switchOn = scene.switchLink.map { target - 1 >= $0.source } ?? false
                        scene.collectedKeys = Set(scene.keyTiers.filter { $0 < target })
                        scene.motionClock = Double(phase) * 0.2; scene.movePlatforms(dt: 0)
                        guard scene.platformActive(target - 1), abs(offset) < scene.ledgeWidth(target) / 2 + 8 else { continue }
                        var source = scene.platforms[target - 1]
                        source.x += sourceShift
                        scene.player.position = CGPoint(x: source.x, y: source.y + 21); scene.supportIndex = target - 1; scene.grounded = true; scene.setRoom(for: target - 1)
                        if scene.crumbleIndices.contains(target - 1) { scene.crumbleAt[target - 1] = scene.motionClock }
                        usage.save.credits = 1000; scene.tryJump()
                        guard scene.attemptStarted else { continue }
                        var clock = 100.0; scene.last = clock
                        for _ in 0..<80 {
                            let dx = scene.platforms[target].x + offset - scene.player.position.x
                            if scene.iceDrift {
                                let v = scene.horizontalVelocity
                                let braking = v * v / (2 * 560)
                                if dx * v > 0 && abs(dx) < braking + 4 { scene.keys = [v > 0 ? 0 : 2] }
                                else { scene.keys = abs(dx) < 2 && abs(v) < 15 ? [] : [dx > 0 ? 2 : 0] }
                            } else { scene.keys = abs(dx) < 2 ? [] : [dx > 0 ? 2 : 0] }
                            if clock - 100 < launchDelay { scene.keys = [] }
                            clock += 1.0 / 60; scene.update(clock)
                            if !scene.attemptStarted { break }
                            if scene.grounded {
                                if scene.supportIndex == target { reachable = true; break search }
                                break
                            }
                        }
                    }
                    }
                    }
                }
                if !reachable { print("unreachable dynamic gap", mode.rawValue, number, target) }
                verify(reachable)
            }
            scene.checkpointIndex = min(3, scene.platforms.count - 1); scene.restoreCheckpoint()
            verify(scene.checkpointIndex == 0 && scene.roomIndex == 0 && scene.player.position == scene.checkpoint && scene.crumbleAt.isEmpty)
        }
    }
    print("PASS: 36 layouts, hard obstacles from stage 1, no rail guides, invisible ledges cannot support jumps, timed recovery, crumble recovery, rotor collisions, first-platform reset")
    exit(0)
}
if CommandLine.arguments.contains("--feature-test") {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TokenJump-features-" + UUID().uuidString)
    let usage = Usage(stateDirectory: dir); defer { try? FileManager.default.removeItem(at: dir) }
    let scene = Game(usage: usage); scene.combatEnabled = false
    let view = GameView(frame: NSRect(x: 0, y: 0, width: 420, height: 560)); view.presentScene(scene)
    for mode in Difficulty.allCases {
        usage.save.runStarted = false; usage.setDifficulty(mode)
        for stage in [3, 8, 11] {
            usage.save.stage = stage; scene.loadStage(); scene.rotors.removeAll(); scene.hazards = []
            let link = scene.switchLink!
            verify(!scene.platformActive(link.target) && scene.platformNodes[link.target].isHidden)
            scene.player.position = CGPoint(x: scene.platforms[link.source].x, y: scene.platforms[link.source].y + 21); scene.supportIndex = link.source; scene.grounded = true
            scene.checkInteractions(); verify(!scene.switchOn)
            scene.player.position.x += scene.switchOffset; scene.checkInteractions()
            verify(scene.switchOn && scene.platformActive(link.target) && !scene.platformNodes[link.target].isHidden)
            scene.restoreCheckpoint(); verify(!scene.switchOn && !scene.platformActive(link.target))
        }
        for stage in [5, 9, 12] {
            usage.save.stage = stage; scene.loadStage(); scene.rotors.removeAll(); scene.hazards = []
            let goal = scene.platforms.count - 1
            scene.player.position = CGPoint(x: scene.platforms[goal].x, y: scene.platforms[goal].y + 22); scene.velocity = -20; scene.grounded = false; scene.last = 1
            scene.update(1 + 1.0 / 30)
            verify(!scene.cleared && !scene.goalUnlocked)
            for index in scene.keyTiers {
                scene.player.position = CGPoint(x: scene.platforms[index].x, y: scene.platforms[index].y + 21); scene.supportIndex = index; scene.grounded = true
                scene.checkInteractions(); verify(scene.collectedKeys.contains(index) && scene.keyNodes[index]!.isHidden)
            }
            verify(scene.goalUnlocked)
            scene.player.position = CGPoint(x: scene.platforms[goal].x, y: scene.platforms[goal].y + 22); scene.velocity = -20; scene.grounded = false; scene.last = 2
            scene.update(2 + 1.0 / 30); verify(scene.cleared)
            scene.restoreCheckpoint(); verify(scene.collectedKeys.isEmpty && !scene.goalUnlocked)
        }
        for stage in [4, 7, 9, 10, 12] {
            usage.save.stage = stage; scene.loadStage(); scene.rotors.removeAll(); scene.hazards = []
            verify(!scene.windBands.isEmpty && scene.windNodes.count <= 14)
            let band = scene.windBands[0]
            scene.player.position = CGPoint(x: 210, y: band.midY); scene.grounded = false; scene.supportIndex = nil; scene.velocity = 200; scene.last = 3
            let balance = usage.wallet
            scene.update(3 + 1.0 / 30)
            verify(scene.windDrift * scene.windDirection > 0 && usage.wallet == balance)
            let clock = scene.motionClock; scene.suspend(); verify(scene.motionClock == clock)
            scene.restoreCheckpoint(); verify(scene.windDrift == 0)
        }
    }
    print("PASS: all modes, switches require plate contact and reset, keys lock goal until collected and reset on fall, directional air wind/no debit/pause/reset")
    exit(0)
}
if CommandLine.arguments.contains("--hazard-preview") {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TokenJump-preview-" + UUID().uuidString)
    let usage = Usage(stateDirectory: dir); defer { try? FileManager.default.removeItem(at: dir) }
    usage.setDifficulty(.hard); usage.save.credits = 10
    let scene = Game(usage: usage), view = GameView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
    view.presentScene(scene); scene.motionClock = 0.6; scene.movePlatforms(dt: 0); scene.refreshHUD()
    guard let texture = view.texture(from: scene, crop: CGRect(x: 0, y: 0, width: 420, height: 560)), let png = NSBitmapImageRep(cgImage: texture.cgImage()).representation(using: .png, properties: [:]) else { fatalError("preview failed") }
    try! png.write(to: URL(fileURLWithPath: "/tmp/TokenJump-hard-preview.png"))
    print("/tmp/TokenJump-hard-preview.png"); exit(0)
}
if CommandLine.arguments.contains("--art-test") {
    _ = NSApplication.shared
    for name in GameArt.names {
        let sprite = GameArt.sprite(name, size: CGSize(width: 96, height: 24))
        verify(sprite != nil && sprite!.texture!.size().width > 0)
    }
    let count = GameArt.cache.count
    _ = GameArt.sprite("platform", size: CGSize(width: 50, height: 12))
    verify(GameArt.cache.count == count)
    print("PASS: all 8 SVG-derived sprites load, nonempty textures, cached reuse")
    exit(0)
}
if CommandLine.arguments.contains("--progression-test") {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let usage = Usage(stateDirectory: dir)
    usage.addTokens(200_000)
    verify(usage.setDifficulty(.hard) && !usage.selectStage(2))
    usage.save.runStarted = true; usage.persist()
    verify(!usage.setDifficulty(.easy) && usage.difficulty == .hard && !usage.advanceStage())
    let wallet = usage.wallet
    for number in 1...Stage.all.count {
        verify(usage.save.stage == number)
        usage.finishStage(number)
        if number < Stage.all.count { verify(!usage.canChangeDifficulty && usage.advanceStage()) }
    }
    verify(usage.canChangeDifficulty && usage.save.runComplete == true)
    verify(usage.setDifficulty(.easy) && usage.save.stage == 1 && usage.unlockedStage == 1 && usage.wallet == wallet)
    usage.save.runStarted = true; usage.finishStage(1); verify(usage.advanceStage())
    let restored = Usage(stateDirectory: dir)
    verify(!restored.canChangeDifficulty && restored.save.stage == 2 && restored.unlockedStage == 2 && !restored.selectStage(3))
    restored.finishStage(12); verify(restored.save.runComplete == false)
    print("PASS: difficulty locks on first jump, sequential stage gate, full-clear unlock, new-run reset, wallet preserved, restart persistence, no skip")
    exit(0)
}
if CommandLine.arguments.contains("--platform-test") {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let usage = Usage(stateDirectory: dir); usage.save.credits = 100
    let scene = Game(usage: usage); scene.combatEnabled = false
    let view = GameView(frame: NSRect(x: 0, y: 0, width: 420, height: 560)); view.presentScene(scene)
    func jump() { scene.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!) }
    var clock: TimeInterval = 1
    usage.save.stage = 3; scene.loadStage(); scene.switchOn = true; scene.supportIndex = 2
    scene.player.position = CGPoint(x: scene.platforms[2].x, y: scene.platforms[2].y + 21); scene.grounded = true
    scene.update(clock)
    let firstX = scene.player.position.x
    for _ in 0..<45 { clock += 1.0 / 60; scene.update(clock) }
    verify(abs(scene.player.position.x - firstX) > 5 && abs(scene.player.position.x - scene.platforms[2].x) < 0.1 && scene.grounded)
    scene.loadStage(); scene.supportIndex = 1; scene.player.position = CGPoint(x: scene.platforms[1].x + scene.switchOffset, y: scene.platforms[1].y + 21); scene.update(clock)
    let wallet = usage.wallet; jump()
    for _ in 0..<160 {
        let dx = scene.platforms[2].x - scene.player.position.x
        scene.keys = abs(dx) < 2 ? [] : [dx > 0 ? 2 : 0]
        clock += 1.0 / 60; scene.update(clock)
        if scene.grounded { break }
    }
    verify(scene.supportIndex == 2 && scene.grounded && usage.wallet == wallet - usage.threshold)
    for mode in Difficulty.allCases {
        usage.save.runStarted = false; usage.setDifficulty(mode); usage.save.stage = 2
        for step in [1.0 / 30, 1.0 / 60, 1.0 / 120] {
            scene.loadStage(); scene.supportIndex = 1
            scene.player.position = CGPoint(x: scene.platforms[1].x, y: scene.platforms[1].y + 21); scene.grounded = true
            scene.last = clock
            let balance = usage.wallet
            for _ in 0..<Int(scene.liftPeriod / step * 2) {
                clock += step; scene.update(clock)
                verify(scene.grounded && scene.supportIndex == 1 && abs(scene.player.position.y - scene.platforms[1].y - 21) < 0.01)
                verify(abs(scene.platforms[1].y - scene.basePlatforms[1].y) <= scene.liftAmplitude + 0.01)
            }
            verify(usage.wallet == balance && scene.children.filter { $0.name == "rail" }.isEmpty)
            let motion = scene.motionClock; scene.suspend(); verify(scene.motionClock == motion)
        }
    }
    usage.save.runStarted = false; usage.setDifficulty(.normal)
    print("PASS: vertical lifts carry riders up/down at 30/60/120 FPS in all modes, bounded motion, no debit or guide lines, pause clock")
    usage.save.stage = 5; scene.loadStage(); scene.supportIndex = 1
    scene.player.position = CGPoint(x: scene.platforms[1].x, y: scene.platforms[1].y + 21); scene.update(clock); scene.keys = [2]
    for _ in 0..<10 { clock += 1.0 / 60; scene.update(clock) }
    let iceX = scene.player.position.x; scene.keys.removeAll(); clock += 1.0 / 60; scene.update(clock)
    verify(scene.player.position.x > iceX && scene.horizontalVelocity > 0)
    scene.keys = [0]; let driftingX = scene.player.position.x; clock += 1.0 / 60; scene.update(clock)
    verify(scene.player.position.x > driftingX)
    usage.save.stage = 2; scene.loadStage(); scene.update(clock); scene.keys = [2]
    for _ in 0..<5 { clock += 1.0 / 60; scene.update(clock) }
    scene.keys.removeAll(); let normalX = scene.player.position.x; clock += 1.0 / 60; scene.update(clock)
    verify(abs(scene.player.position.x - normalX) < 0.01)
    let motion = scene.motionClock; scene.suspend(); verify(scene.motionClock == motion && scene.keys.isEmpty)
    usage.save.stage = 12; scene.loadStage(); scene.supportIndex = 6; scene.checkpointIndex = 6
    scene.player.position = CGPoint(x: scene.platforms[6].x, y: scene.platforms[6].y + 21); scene.setRoom(for: 6)
    verify(scene.roomIndex == 1 && abs(scene.player.position.y - scene.roomOffset - 71) < 0.01)
    let fixedCamera = scene.roomCamera.position
    clock += 1.0 / 60; scene.update(clock)
    verify(scene.roomCamera.position == fixedCamera)
    scene.player.position.y = scene.roomOffset - 31; scene.grounded = false; scene.supportIndex = nil
    clock += 1.0 / 60; scene.update(clock)
    verify(scene.roomIndex == 0 && scene.checkpointIndex == 0 && abs(scene.player.position.y - scene.platforms[0].y - 21) < 0.01)
    print("PASS: late-course room transition, camera fixed in room, failure resets to first platform")
    print("PASS: moving rail carries rider, moving-target landing, exact jump debit, ice coasts/reverses gradually, normal ledge stops, pause preserves motion clock")
    exit(0)
}
if CommandLine.arguments.contains("--combat-test") {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let usage = Usage(stateDirectory: dir)
    let scene = Game(usage: usage)
    let view = GameView(frame: NSRect(x: 0, y: 0, width: 420, height: 560)); view.presentScene(scene)
    func jump() {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        scene.keyDown(with: event)
    }
    func tick(_ duration: TimeInterval) {
        var left = duration
        while left > 0 { let dt = min(left, 1.0 / 30); scene.updateCannons(dt: dt); left -= dt }
    }
    for mode in Difficulty.allCases {
        usage.save.runStarted = false
        usage.setDifficulty(mode); usage.save.stage = 4; usage.save.credits = 0; usage.save.remainder = 0; usage.addTokens(mode.cost)
        scene.loadStage(); scene.update(1)
        let before = usage.wallet
        for i in 1...90 { scene.update(1 + Double(i) / 30) }
        verify(scene.shotNumber > 0 && scene.combatClock > 0 && usage.wallet == before)
        scene.combatClock = 0; scene.nextShotAt = 1.5; scene.shotNumber = 0; scene.clearShots()
        jump()
        verify(scene.attemptStarted && !scene.grounded && usage.wallet == 0)
        // Recovery fixtures are funded separately; starting never requires a reserve.
        usage.addTokens(mode.cost * 3)
        tick(0.71); verify(scene.warningLine.isHidden && scene.shotNumber == 0)
        tick(0.81); verify(scene.shotNumber == 1 && (scene.shots.first?.flightSpeed ?? 0) > 0)
        tick(scene.fireInterval); verify(scene.shotNumber == 2 && (scene.shots.last?.flightSpeed ?? 0) > 0)
        scene.clearShots(); scene.immuneUntil = 0; scene.player.position = CGPoint(x: 210, y: 250); scene.velocity = 0
        scene.fireShot(fromLeft: true); scene.shots[0].position = scene.player.position
        let hitBalance = usage.wallet
        scene.updateCannons(dt: 0)
        verify(scene.recoil > 0 && scene.knockedBack && !scene.grounded && usage.wallet == hitBalance)
        let impactX = scene.player.position.x
        scene.update(scene.last + 1.0 / 30)
        verify(scene.player.position.x > impactX && usage.wallet == hitBalance)
        let hitVelocity = scene.velocity
        for _ in 0..<10 { jump() }
        verify(scene.velocity == hitVelocity && usage.wallet == hitBalance)
        let immuneRecoil = scene.recoil
        scene.fireShot(fromLeft: false); scene.shots.last!.position = scene.player.position; scene.updateCannons(dt: 0)
        verify(scene.recoil == immuneRecoil)
        scene.immuneUntil = 0; scene.updateCannons(dt: 0)
        verify(scene.recoil < 0)
        usage.save.credits = 0; usage.save.remainder = 0; scene.velocity = 100; jump()
        verify(scene.velocity == 100 && usage.wallet == 0)
        let clock = scene.combatClock; scene.suspend(); verify(scene.combatClock == clock)
        scene.clearShots(); verify(scene.shots.isEmpty)
    }
    for mode in Difficulty.allCases {
        usage.save.runStarted = false
        usage.setDifficulty(mode)
        for number in 1...Stage.all.count {
            usage.save.stage = number; scene.loadStage(); scene.switchOn = true
            verify(scene.children.filter { $0.name == "cannon" }.count == (scene.hasCannons ? 1 : 0))
            let labels = scene.children.compactMap { $0 as? SKLabelNode }.filter { !$0.isHidden }
            verify(labels.count == 1 && labels.first === scene.hud && scene.warningLine.isHidden)
            if scene.hasCannons {
                tick(1.51)
                verify(scene.shotNumber == 1 && ((scene.shots.first?.flightSpeed ?? 0) > 0) == scene.cannonFromLeft)
            }
        }
    }
    print("PASS: all 36 map/mode layouts, at most one cannon, correct firing side, count-only HUD, no path overlay")
    let recovered = Usage(stateDirectory: dir)
    verify((recovered.save.spent ?? 0) > 0 && (recovered.save.jumpCount ?? 0) >= 3)
    print("PASS: single-credit start all modes, visible idle firing, no path overlay, single-side cannon, directional recoil, air jump rejected after impact, hit immunity, empty reserve, paused combat clock, saved spending")
    exit(0)
}
if CommandLine.arguments.contains("--game-test") {
    _ = NSApplication.shared
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let usage = Usage(stateDirectory: dir)
    let scene = Game(usage: usage)
    scene.combatEnabled = false
    scene.mechanicsEnabled = false
    let view = GameView(frame: NSRect(x: 0, y: 0, width: 420, height: 560))
    view.presentScene(scene)
    func key(_ code: UInt16) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: code)!
    }
    var clock: TimeInterval = 1
    for step in [1.0 / 30, 1.0 / 60, 1.0 / 120] {
    for mode in Difficulty.allCases {
        usage.save.runStarted = false
        usage.setDifficulty(mode)
        for index in Stage.all.indices {
            usage.save.stage = index + 1; usage.save.credits = 1000; usage.save.remainder = 0
            scene.loadStage(); scene.update(clock); clock += step
            let balance = usage.wallet
            for target in scene.platforms.dropFirst() {
                let previousY = scene.player.position.y
                scene.keyDown(with: key(49))
                verify(!scene.grounded)
                for _ in 0..<160 {
                    let dx = target.x - scene.player.position.x
                    scene.keys = abs(dx) < max(2, 190 * step / 2) ? [] : [dx > 0 ? 2 : 0]
                    scene.update(clock); clock += step
                    if scene.grounded { break }
                }
                if !(scene.grounded && abs(scene.player.position.y - (target.y + 21)) < 1) { print("layout failure", mode.rawValue, index + 1, step, target, scene.player.position) }
                verify(scene.grounded && abs(scene.player.position.y - (target.y + 21)) < 1)
                verify(scene.player.position.y > previousY)
                verify(scene.position == .zero && scene.roomCamera.position.x == 210)
            }
            verify(scene.cleared && usage.wallet == balance - (scene.platforms.count - 1) * mode.cost)
            scene.keyDown(with: key(49)); verify(usage.wallet == balance - (scene.platforms.count - 1) * mode.cost)
            scene.suspend(); verify(scene.keys.isEmpty && scene.isPaused)
        }
    }
    }
    usage.save.credits = 0; usage.save.remainder = 0; scene.loadStage()
    scene.keyDown(with: key(49)); verify(scene.grounded && scene.velocity == 0)
    for avatar in Avatar.allCases { usage.save.avatar = avatar.rawValue; scene.applyAvatar(); verify(scene.player.children.count >= 4) }
    scene.walls = [CGRect(x: 100, y: 100, width: 40, height: 40)]
    scene.player.position = CGPoint(x: 92, y: 120); scene.resolveWallsHorizontally(from: 85)
    verify(scene.player.position.x == 88)
    scene.player.position = CGPoint(x: 148, y: 120); scene.resolveWallsHorizontally(from: 155)
    verify(scene.player.position.x == 152)
    scene.player.position = CGPoint(x: 120, y: 90); scene.velocity = 300; scene.resolveWallsVertically(from: 80)
    verify(scene.player.position.y == 85 && scene.velocity == 0)
    scene.player.position = CGPoint(x: 120, y: 150); scene.velocity = -100; scene.resolveWallsVertically(from: 160)
    verify(scene.player.position.y == 155 && scene.grounded)
    scene.walls = []; scene.loadStage(); scene.hazards = [CGRect(x: scene.player.position.x - 20, y: 50, width: 40, height: 50)]
    let hazardBalance = usage.wallet; scene.update(clock); clock += 1.0 / 120; scene.update(clock)
    verify(scene.player.position == scene.checkpoint && usage.wallet == hazardBalance && scene.hitNoticeUntil > clock)
    // A one-way ledge must allow upward travel through its underside, then support a landing.
    scene.hazards = []; scene.walls = []; scene.platforms = [CGPoint(x: 210, y: 100)]; scene.supportIndex = nil
    scene.player.position = CGPoint(x: 210, y: 70); scene.velocity = 420; scene.grounded = false
    var passedAbove = false
    for _ in 0..<150 { clock += 1.0 / 120; scene.update(clock); passedAbove = passedAbove || scene.player.position.y > 140; if scene.grounded { break } }
    verify(passedAbove && scene.grounded && scene.player.position.y == 121)
    scene.cleared = false; scene.keys.removeAll(); scene.platforms = [CGPoint(x: 210, y: 100)]; scene.supportIndex = nil
    scene.player.position = CGPoint(x: 210 + scene.platformWidth / 2 + 9, y: 122); scene.velocity = -100; scene.grounded = false
    scene.keys = [2]; scene.last = clock; clock += 1.0 / 30; scene.update(clock)
    verify(scene.grounded && scene.player.position.y == 121)
    scene.cleared = false; scene.keys.removeAll(); usage.save.credits = 10
    scene.player.position = CGPoint(x: 210, y: 122); scene.velocity = -40; scene.grounded = false; scene.last = clock
    let bufferBalance = usage.wallet
    scene.keyDown(with: key(49)); verify(usage.wallet == bufferBalance)
    clock += 1.0 / 30; scene.update(clock)
    verify(scene.grounded && scene.velocity == 0 && usage.wallet == bufferBalance)
    scene.cleared = false; scene.keyDown(with: key(49)); verify(!scene.grounded && usage.wallet == bufferBalance - usage.threshold)
    let launchedVelocity = scene.velocity
    for _ in 0..<20 { scene.keyDown(with: key(49)) }
    verify(scene.velocity == launchedVelocity && usage.wallet == bufferBalance - usage.threshold)
    scene.player.position = CGPoint(x: 400, y: 121); scene.velocity = 0; scene.grounded = true
    let offEdgeBalance = usage.wallet; scene.keyDown(with: key(49)); verify(usage.wallet == offEdgeBalance && scene.velocity == 0)
    let icon = App.makeStatusIcon(); verify(icon.isTemplate && icon.size == NSSize(width: 18, height: 18))
    for step in [1.0 / 30, 1.0 / 60, 1.0 / 120] {
        for direction: UInt16 in [0, 2] {
            scene.combatEnabled = false; scene.loadStage(); scene.walls = []; scene.hazards = []
            scene.platforms = [CGPoint(x: 210, y: 100)]; scene.supportIndex = nil
            scene.player.position = CGPoint(x: 210, y: 121); scene.velocity = 0; scene.grounded = true; scene.last = clock; scene.keys = [direction]
            let walkBalance = usage.wallet
            for _ in 0..<100 {
                clock += step; scene.update(clock)
                if scene.player.position.y < 110 { break }
            }
            verify(!scene.grounded && scene.player.position.y < 110 && usage.wallet == walkBalance)
        }
    }
    print("PASS: walking off both ledge edges falls at 30/60/120 FPS with no jump debit")
    print("PASS: 30FPS edge landing, ground-only jump, no buffering/coyote/midair spam, icon template/size")
    print("PASS: walls block left/right/head and support landing; hazard respawn has no debit; one-way upward pass and downward landing")
    print("PASS: 108 stage/mode/FPS playthroughs, simultaneous movement/jump, 684 landings, exact debit, clear lock, pause, empty wallet, 3 avatars, fixed scene")
    exit(0)
}
let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.run()
